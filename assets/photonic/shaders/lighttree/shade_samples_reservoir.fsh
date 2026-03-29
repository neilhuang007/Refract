#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"

uniform float ph_restir_enable_final_visibility;
uniform float ph_restir_reuse_final_visibility;
uniform float ph_restir_temporal_visibility_shortcut;
uniform float ph_debug_enable_direct_final_visibility;
uniform float ph_debug_enable_direct_visibility_transmittance;

void storeReservoirOutputs(Reservoir reservoir) {
    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(reservoir);
}

void main() {
    ivec2 reservoirPos = lt_current_reservoir_pos();
    if (!lt_is_active_reservoir_lane(reservoirPos)) {
        storeReservoirOutputs(rtxdi_empty_reservoir());
        return;
    }

    ivec2 pixelPosition = lt_current_pixel_pos();
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        storeReservoirOutputs(rtxdi_empty_reservoir());
        return;
    }

    DirectSurface currentSurface = lt_load_surface(pixelPosition);
    if (!lt_is_valid_surface(currentSurface)) {
        storeReservoirOutputs(rtxdi_empty_reservoir());
        return;
    }

    Reservoir reservoir = rtxdi_empty_reservoir();
    rtxdi_unpack_reservoir_at_surface(
        reservoir,
        texelFetch(radiosity_reservoirs, reservoirPos, 0),
        texelFetch(radiosity_reservoir_samples, reservoirPos, 0),
        texelFetch(radiosity_reservoir_meta, reservoirPos, 0),
        currentSurface,
        false
    );

    bool enableFinalVisibility = (ph_restir_enable_final_visibility < -1.5) ? false : true;
    if (ph_debug_enable_direct_final_visibility < 0.5) {
        enableFinalVisibility = false;
    }
    bool reuseFinalVisibility = (ph_restir_reuse_final_visibility < -1.5) ? false : true;
    bool discardIfInvisible = (ph_restir_temporal_visibility_shortcut < -0.5)
        ? false
        : (ph_restir_temporal_visibility_shortcut >= 0.5);
    bool enableVisibilityTransmittance = ph_debug_enable_direct_visibility_transmittance >= 0.5;

    // Match RTXDI ShadeSamples.hlsl: valid shading / visibility storage is gated
    // only by lightData, not by weightSum.
    bool hasValidReservoir = RTXDI_IsValidDIReservoir(reservoir);
    if (hasValidReservoir && enableFinalVisibility && (!reuseFinalVisibility || !rtxdi_has_reusable_visibility(reservoir))) {
        LightSample traceSample = light_sample_decode(reservoir, currentSurface, false);
        if (traceSample.index >= 0) {
            // RTXDI GetFinalVisibility uses a 0.01 ray offset for final shading.
            float hitDist = 0.0f;
            vec3 visRgb = lt_trace_final_visibility_with_offset(traceSample, currentSurface, 0.01f, hitDist);
            bool isVisible = ph_luminance(visRgb) > 0.0f && traceSample.index >= 0;
            vec3 storedVisRgb = enableVisibilityTransmittance ? visRgb : (isVisible ? vec3(1.0f) : vec3(0.0f));
            RTXDI_StoreVisibilityInDIReservoir(reservoir, storedVisRgb, discardIfInvisible);
        }
    }

    storeReservoirOutputs(reservoir);
}
