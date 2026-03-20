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

// RTXDI: enableVisibilityShortcut from RTXDI_DITemporalResamplingParameters (ReSTIRDI.cpp line 60).
// Controls discardIfInvisible in rtxdi_store_visibility (ShadeSamples.hlsl line 64).
// SDK default: false (0). When unbound (0.0): disabled (SDK default).
// When enabled (1.0): invisible reservoir samples are discarded (lightData + weightSum cleared).
// Shares the same uniform as restir_di_temporal.fsh — RTXDI uses a single enableVisibilityShortcut
// for both temporal bias correction and final shading.
uniform float ph_restir_temporal_visibility_shortcut;  // RTXDI: enableVisibilityShortcut

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
    if (!lt_is_viewport_uv_in_bounds(pixelPosition) || !is_in_world()) {
        storeEmptyShadeOutputs();
        storeReservoirOutputs(rtxdi_empty_reservoir());
        return;
    }

    if (!lt_is_active_reservoir_lane(reservoirPos)) {
        storeEmptyShadeOutputs();
        storeReservoirOutputs(rtxdi_empty_reservoir());
        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);
    rt_pos = world_pos - world_offset;
    bad_angle = is_bad_angle(world_pos, block_normal);

    DirectSurface currentSurface = lt_current_surface();

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
    bool reuseFinalVisibility = (ph_restir_reuse_final_visibility < -1.5) ? false : true;
    // SDK default (ReSTIRDI.cpp line 60): enableVisibilityShortcut = false.
    // discardIfInvisible mirrors enableVisibilityShortcut (ShadeSamples.hlsl line 64).
    // Sentinel: -1.0 → SDK default (false), 0.0 → false, >= 0.5 → true.
    bool discardIfInvisible = (ph_restir_temporal_visibility_shortcut < -0.5)
        ? false
        : (ph_restir_temporal_visibility_shortcut >= 0.5);

    bool hasValidReservoir = RTXDI_IsValidDIReservoir(reservoir) && reservoir.weightSum > 0.0f;
    if (hasValidReservoir) {
        if (!enableFinalVisibility) {
            // RTXDI: enableFinalVisibility=false — shade without any visibility test.
            LightSample shadeSample = light_sample_decode(reservoir, currentSurface, false);
            if (shadeSample.index >= 0) {
                LtSplitRadiance splitShade = lt_shade_surface_split(currentSurface, shadeSample);
                shadedDiffuse = splitShade.diffuse * reservoir.weightSum;
                shadedSpecular = splitShade.specular * reservoir.weightSum;
                directHitDistance = length(shadeSample.position + world_offset - currentSurface.worldPos);
            }
        } else if (reuseFinalVisibility && rtxdi_has_reusable_visibility(reservoir)) {
            // RTXDI: reuseFinalVisibility=true and cached visibility is still valid — reuse RGB value.
            // Apply 3-channel visibility modulation instead of binary gating so colored shadows
            // and partial occlusion are preserved.
            vec3 visRgb = rtxdi_get_visibility(reservoir);
            if (rtxdi_is_visible(reservoir)) {
                LightSample shadeSample = light_sample_decode(reservoir, currentSurface, false);
                if (shadeSample.index >= 0) {
                    LtSplitRadiance splitShade = lt_shade_surface_split(currentSurface, shadeSample);
                    shadedDiffuse = splitShade.diffuse * reservoir.weightSum * visRgb;
                    shadedSpecular = splitShade.specular * reservoir.weightSum * visRgb;
                    directHitDistance = length(shadeSample.position + world_offset - currentSurface.worldPos);
                }
            }
        } else {
            // Trace a fresh visibility ray (reuseFinalVisibility=false or no cached visibility).
            LightSample traceSample = light_sample_decode(reservoir, currentSurface, false);
            if (traceSample.index >= 0) {
                float hitDist = light_sample_trace_hit_surface(traceSample, false, currentSurface);
                bool isVisible = hitDist > 0.0f && traceSample.index >= 0;
                // Wire discardIfInvisible from enableVisibilityShortcut (ShadeSamples.hlsl line 64).
                // When discardIfInvisible=true and invisible: lightData+weightSum are cleared (RTXDI lines 93-96).
                RTXDI_StoreVisibilityInDIReservoir(reservoir, isVisible ? vec3(1.0f) : vec3(0.0f), discardIfInvisible);
                if (isVisible) {
                    // Use RGB visibility from the freshly traced result (binary: vec3(1) when hit).
                    vec3 visRgb = rtxdi_get_visibility(reservoir);
                    LtSplitRadiance splitShade = lt_shade_surface_split(currentSurface, traceSample);
                    shadedDiffuse = splitShade.diffuse * reservoir.weightSum * visRgb;
                    shadedSpecular = splitShade.specular * reservoir.weightSum * visRgb;
                    directHitDistance = length(traceSample.position + world_offset - currentSurface.worldPos);
                }
            } else {
                RTXDI_StoreVisibilityInDIReservoir(reservoir, vec3(0.0f), discardIfInvisible);
            }
        }
    }

    direct_diffuse_frag_out = nrd_pack_direct_signal(shadedDiffuse, directHitDistance);
    direct_specular_frag_out = nrd_pack_direct_signal(shadedSpecular, directHitDistance);
    storeReservoirOutputs(reservoir);
}
