#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_diffuse_frag_out;
layout(location = 1) out vec4 direct_specular_frag_out;
layout(location = 2) out vec4 reservoir_frag_out;
layout(location = 3) out vec4 reservoir_sample_frag_out;
layout(location = 4) out vec4 reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

// RTXDI RTXDI_ShadingParameters (ReSTIRDIParameters.h lines 199-210).
// 1.0 = enabled, 0.0 = disabled. Defaults to enabled when unbound.
uniform float ph_restir_enable_final_visibility;    // RTXDI: enableFinalVisibility
uniform float ph_restir_reuse_final_visibility;     // RTXDI: reuseFinalVisibility
uniform float ph_restir_enable_denoiser_packing;    // RTXDI: enableDenoiserInputPacking
uniform float ph_debug_enable_direct_final_visibility;
uniform float ph_debug_enable_direct_visibility_transmittance;

// RTXDI: enableVisibilityShortcut from RTXDI_DITemporalResamplingParameters (ReSTIRDI.cpp line 60).
// Controls discardIfInvisible in rtxdi_store_visibility (ShadeSamples.hlsl line 64).
// SDK default: false (0). When unbound (0.0): disabled (SDK default).
// When enabled (1.0): invisible reservoir samples are discarded (lightData + weightSum cleared).
// Shares the same uniform as restir_di_temporal.fsh — RTXDI uses a single enableVisibilityShortcut
// for both temporal bias correction and final shading.
uniform float ph_restir_temporal_visibility_shortcut;  // RTXDI: enableVisibilityShortcut

const float ph_nrd_spec_fp16_safe_luma = 248.0;

vec3 ph_clamp_specular_for_relax(vec3 demodulatedSpecular) {
    demodulatedSpecular = max(demodulatedSpecular, vec3(0.0));
    float specularLuma = nrd_luminance(demodulatedSpecular);
    if (specularLuma > ph_nrd_spec_fp16_safe_luma) {
        demodulatedSpecular *= ph_nrd_spec_fp16_safe_luma / max(specularLuma, 1e-6);
    }
    return demodulatedSpecular;
}

void storeEmptyShadeOutputs() {
    direct_diffuse_frag_out = vec4(0.0f);
    direct_specular_frag_out = vec4(0.0f);
}

void storeReservoirOutputs(Reservoir reservoir) {
    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(reservoir);
}

void main() {
    ivec2 reservoirPos = lt_current_reservoir_pos();
    ivec2 pixelPosition = lt_current_pixel_pos();
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        storeEmptyShadeOutputs();
        storeReservoirOutputs(rtxdi_empty_reservoir());
        return;
    }

    if (!lt_is_active_reservoir_lane(reservoirPos)) {
        storeEmptyShadeOutputs();
        storeReservoirOutputs(rtxdi_empty_reservoir());
        return;
    }

    DirectSurface currentSurface = lt_load_surface(pixelPosition);
    if (!lt_is_valid_surface(currentSurface)) {
        storeEmptyShadeOutputs();
        storeReservoirOutputs(rtxdi_empty_reservoir());
        return;
    }

    // Load the final reservoir from the spatial resampling output.
    Reservoir reservoir = rtxdi_empty_reservoir();
    rtxdi_unpack_reservoir_at_surface(
        reservoir,
        texelFetch(radiosity_reservoirs, reservoirPos, 0),
        texelFetch(radiosity_reservoir_samples, reservoirPos, 0),
        texelFetch(radiosity_reservoir_meta, reservoirPos, 0),
        currentSurface,
        false
    );

    vec3 shadedDiffuse = vec3(0.0f);
    vec3 shadedSpecular = vec3(0.0f);
    float directHitDistance = 0.0f;

    // RTXDI RTXDI_ShadingParameters: enableFinalVisibility / reuseFinalVisibility.
    // SDK defaults (ReSTIRDI.cpp lines 113-116): enableFinalVisibility=true, reuseFinalVisibility=true.
    // Sentinel pattern for SDK-default-true booleans:
    //   -1.0 → SDK default (true), 0.0 (unbound) → SDK default (true), >= 0.5 → true.
    //   Explicit disable: pass -2.0 (< -1.5) to force false.
    bool enableFinalVisibility = (ph_restir_enable_final_visibility < -1.5) ? false : true;
    if (ph_debug_enable_direct_final_visibility < 0.5) {
        enableFinalVisibility = false;
    }
    bool reuseFinalVisibility = (ph_restir_reuse_final_visibility < -1.5) ? false : true;
    bool enableVisibilityTransmittance = ph_debug_enable_direct_visibility_transmittance >= 0.5;
    // SDK default (ReSTIRDI.cpp line 60): enableVisibilityShortcut = false.
    // discardIfInvisible mirrors enableVisibilityShortcut (ShadeSamples.hlsl line 64).
    // Sentinel: -1.0 → SDK default (false), 0.0 → false, >= 0.5 → true.
    bool discardIfInvisible = (ph_restir_temporal_visibility_shortcut < -0.5)
        ? false
        : (ph_restir_temporal_visibility_shortcut >= 0.5);

    // RTXDI reference (ShadeSamples.hlsl line 56): only checks RTXDI_IsValidDIReservoir (lightData != 0).
    // DISCREPANCY FIXED: photonics previously also guarded on weightSum > 0, which would skip
    // RTXDI_StoreVisibilityInDIReservoir for zero-weight valid reservoirs, diverging from reference.
    bool hasValidReservoir = RTXDI_IsValidDIReservoir(reservoir);
    if (hasValidReservoir) {
        if (!enableFinalVisibility) {
            // RTXDI: enableFinalVisibility=false — shade without any visibility test.
            LightSample shadeSample = light_sample_decode(reservoir, currentSurface, false);
            if (shadeSample.index >= 0 && shadeSample.solidAnglePdf > 0.0f) {
                shadeSample.color *= RTXDI_GetDIReservoirInvPdf(reservoir) / shadeSample.solidAnglePdf;
                LtSplitRadiance splitShade = lt_shade_surface_split(currentSurface, shadeSample);
                shadedDiffuse = splitShade.diffuse;
                shadedSpecular = splitShade.specular;
                directHitDistance = length(shadeSample.position + world_offset - currentSurface.worldPos);
            }
        } else if (reuseFinalVisibility && rtxdi_has_reusable_visibility(reservoir)) {
            // RTXDI: reuseFinalVisibility=true and cached visibility is still valid — reuse RGB value.
            // Apply 3-channel visibility modulation instead of binary gating so colored shadows
            // and partial occlusion are preserved.
            vec3 visRgb = rtxdi_get_visibility(reservoir);
            if (!enableVisibilityTransmittance && rtxdi_is_visible(reservoir)) {
                visRgb = vec3(1.0f);
            }
            if (rtxdi_is_visible(reservoir)) {
                LightSample shadeSample = light_sample_decode(reservoir, currentSurface, false);
                if (shadeSample.index >= 0 && shadeSample.solidAnglePdf > 0.0f) {
                    shadeSample.color *= visRgb * (RTXDI_GetDIReservoirInvPdf(reservoir) / shadeSample.solidAnglePdf);
                    LtSplitRadiance splitShade = lt_shade_surface_split(currentSurface, shadeSample);
                    shadedDiffuse = splitShade.diffuse;
                    shadedSpecular = splitShade.specular;
                    directHitDistance = length(shadeSample.position + world_offset - currentSurface.worldPos);
                }
            }
        } else {
            // Trace a fresh visibility ray (reuseFinalVisibility=false or no cached visibility).
            LightSample traceSample = light_sample_decode(reservoir, currentSurface, false);
            if (traceSample.index >= 0) {
                // RTXDI GetFinalVisibility uses a 0.01 ray offset for final shading.
                float hitDist = 0.0f;
                vec3 visRgb = lt_trace_final_visibility_with_offset(traceSample, currentSurface, 0.01f, hitDist);
                bool isVisible = ph_luminance(visRgb) > 0.0f && traceSample.index >= 0;
                vec3 storedVisRgb = enableVisibilityTransmittance ? visRgb : (isVisible ? vec3(1.0f) : vec3(0.0f));
                // Wire discardIfInvisible from enableVisibilityShortcut (ShadeSamples.hlsl line 64).
                // When discardIfInvisible=true and invisible: lightData+weightSum are cleared (RTXDI lines 93-96).
                RTXDI_StoreVisibilityInDIReservoir(reservoir, storedVisRgb, discardIfInvisible);
                if (isVisible && traceSample.solidAnglePdf > 0.0f) {
                    traceSample.color *= storedVisRgb * (RTXDI_GetDIReservoirInvPdf(reservoir) / traceSample.solidAnglePdf);
                    LtSplitRadiance splitShade = lt_shade_surface_split(currentSurface, traceSample);
                    shadedDiffuse = splitShade.diffuse;
                    shadedSpecular = splitShade.specular;
                    directHitDistance = length(traceSample.position + world_offset - currentSurface.worldPos);
                }
            }
        }
    }

    if (ph_restir_enable_denoiser_packing >= 0.5f) {
        // RTXDI reference (ShadeSamples.hlsl line 66-68, ShadingHelpers.hlsli line 119-122):
        // - Diffuse:  NO demodulation. brdf.demodulatedDiffuse is Lambert(N,-L) only; albedo is
        //             NOT divided out here (albedo is only used for the luminance gradient store).
        // - Specular: DemodulateSpecular = specular / max(0.01, F0), channel-wise, nothing more.
        // DISCREPANCY FIXED: photonics previously applied nrd_material_factors (full env-BRDF-based
        // diffFactor and specFactor) to both channels, which is incorrect. The reference uses
        // no diffuse demod and only a simple F0 division for specular.
        float metallic = clamp(currentSurface.material.y, 0.0, 1.0);
        vec3 Rf0 = mix(vec3(0.04), clamp(currentSurface.albedo, vec3(0.0), vec3(1.0)), metallic);
        // Diffuse: pass through unchanged (reference stores Lambert*radiance with no albedo demod)
        vec3 demodSpecular = shadedSpecular / max(vec3(0.01), Rf0);
        // Keep the demodulated specular in the range where RELAX's RGBA16F
        // radiance+second-moment history can still carry useful variance.
        demodSpecular = ph_clamp_specular_for_relax(demodSpecular);
        direct_diffuse_frag_out = nrd_pack_direct_signal(shadedDiffuse, directHitDistance);
        direct_specular_frag_out = nrd_pack_direct_signal(demodSpecular, directHitDistance);
    } else {
        direct_diffuse_frag_out = vec4(shadedDiffuse, directHitDistance);
        direct_specular_frag_out = vec4(shadedSpecular, directHitDistance);
    }
    storeReservoirOutputs(reservoir);
}
