#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_diffuse_frag_out;
layout(location = 1) out vec4 direct_specular_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform float ph_restir_enable_final_visibility;
uniform float ph_restir_reuse_final_visibility;
uniform float ph_restir_enable_denoiser_packing;
uniform float ph_restir_temporal_visibility_shortcut;

void storeEmptyShadeOutputs() {
    direct_diffuse_frag_out = vec4(0.0f);
    direct_specular_frag_out = vec4(0.0f);
}

void main() {
    ivec2 pixelPosition = tex_coord;
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        storeEmptyShadeOutputs();
        return;
    }

    if (!RTXDI_IsActiveCheckerboardPixel(pixelPosition, false, ph_restir_active_checkerboard_field)) {
        storeEmptyShadeOutputs();
        return;
    }

    DirectSurface currentSurface = lt_load_surface(pixelPosition);
    if (!lt_is_valid_surface(currentSurface)) {
        storeEmptyShadeOutputs();
        return;
    }

    ivec2 reservoirPos = RTXDI_PixelPosToReservoirPos(pixelPosition, ph_restir_active_checkerboard_field);
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

    bool enableFinalVisibility = (ph_restir_enable_final_visibility < -1.5) ? false : true;
    bool reuseFinalVisibility = (ph_restir_reuse_final_visibility < -1.5) ? false : true;
    bool discardIfInvisible = (ph_restir_temporal_visibility_shortcut < -0.5)
        ? false
        : (ph_restir_temporal_visibility_shortcut >= 0.5);

    // RTXDI reference (ShadeSamples.hlsl line 56): only checks RTXDI_IsValidDIReservoir (lightData != 0).
    // DISCREPANCY FIXED: photonics previously also guarded on weightSum > 0, which would skip
    // RTXDI_StoreVisibilityInDIReservoir for zero-weight valid reservoirs, diverging from reference.
    bool hasValidReservoir = RTXDI_IsValidDIReservoir(reservoir);
    if (hasValidReservoir) {
        if (!enableFinalVisibility) {
            LightSample shadeSample = light_sample_decode(reservoir, currentSurface, false);
            if (shadeSample.index >= 0 && shadeSample.solidAnglePdf > 0.0f) {
                shadeSample.color *= RTXDI_GetDIReservoirInvPdf(reservoir) / shadeSample.solidAnglePdf;
                LtSplitRadiance splitShade = lt_shade_surface_split(currentSurface, shadeSample);
                shadedDiffuse = splitShade.diffuse;
                shadedSpecular = splitShade.specular;
                directHitDistance = length(shadeSample.position + world_offset - currentSurface.worldPos);
            }
        } else if (reuseFinalVisibility && rtxdi_has_reusable_visibility(reservoir)) {
            vec3 visRgb = rtxdi_get_visibility(reservoir);
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
            LightSample traceSample = light_sample_decode(reservoir, currentSurface, false);
            if (traceSample.index >= 0) {
                // RTXDI GetFinalVisibility uses a 0.01 ray offset for final shading.
                float hitDist = 0.0f;
                vec3 visRgb = lt_trace_final_visibility_with_offset(traceSample, currentSurface, 0.01f, hitDist);
                bool isVisible = ph_luminance(visRgb) > 0.0f && traceSample.index >= 0;
                RTXDI_StoreVisibilityInDIReservoir(reservoir, visRgb, discardIfInvisible);
                if (isVisible && traceSample.solidAnglePdf > 0.0f) {
                    traceSample.color *= visRgb * (RTXDI_GetDIReservoirInvPdf(reservoir) / traceSample.solidAnglePdf);
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
        direct_diffuse_frag_out = nrd_pack_direct_signal(shadedDiffuse, directHitDistance);
        direct_specular_frag_out = nrd_pack_direct_signal(demodSpecular, directHitDistance);
    } else {
        direct_diffuse_frag_out = vec4(shadedDiffuse, directHitDistance);
        direct_specular_frag_out = vec4(shadedSpecular, directHitDistance);
    }
}
