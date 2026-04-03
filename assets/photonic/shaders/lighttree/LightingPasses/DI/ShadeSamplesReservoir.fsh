#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"

void storeReservoirOutputs(RTXDI_DIReservoir reservoir) {
    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(reservoir);
}

void main() {
    ivec2 GlobalIndex = lt_current_reservoir_pos();
    if (!lt_is_active_reservoir_lane(GlobalIndex)) {
        storeReservoirOutputs(RTXDI_EmptyDIReservoir());
        return;
    }

    const RTXDI_RuntimeParameters params = lt_build_runtime_parameters();
    ivec2 pixelPosition = RTXDI_ReservoirPosToPixelPos(GlobalIndex, int(params.activeCheckerboardField));
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        storeReservoirOutputs(RTXDI_EmptyDIReservoir());
        return;
    }

    RAB_Surface surface = RAB_GetGBufferSurface(pixelPosition, false);
    if (!RAB_IsSurfaceValid(surface)) {
        storeReservoirOutputs(RTXDI_EmptyDIReservoir());
        return;
    }

    const RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    const RTXDI_VisibilityReuseParameters visibilityReuseParams = lt_build_visibility_reuse_parameters();

    RTXDI_DIReservoir reservoir = RTXDI_LoadDIReservoir(
        restirDI.reservoirBufferParams,
        uvec2(GlobalIndex),
        restirDI.bufferIndices.shadingInputBufferIndex
    );

    bool enableFinalVisibility = restirDI.shadingParams.enableFinalVisibility != 0u;
    bool reuseFinalVisibility = restirDI.shadingParams.reuseFinalVisibility != 0u;
    bool discardIfInvisible = (ph_restir_temporal_visibility_shortcut < -0.5)
        ? false
        : (ph_restir_temporal_visibility_shortcut >= 0.5);
    bool enableVisibilityTransmittance = true;

    // Match RTXDI ShadeSamples.hlsl: valid shading / visibility storage is gated
    // only by lightData, not by weightSum.
    bool hasValidReservoir = RTXDI_IsValidDIReservoir(reservoir);
    vec3 visibility = vec3(0.0f);
    bool hasStoredVisibility = reuseFinalVisibility && RTXDI_GetDIReservoirVisibility(reservoir, visibilityReuseParams, visibility);
    if (hasValidReservoir && enableFinalVisibility && !hasStoredVisibility) {
        RAB_LightInfo lightInfo = RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(reservoir), false);
        RAB_LightSample traceSample = RAB_SamplePolymorphicLight(lightInfo, surface, RTXDI_GetDIReservoirSampleUV(reservoir));
        if (traceSample.index >= 0) {
            // RTXDI GetFinalVisibility uses a 0.01 ray offset for final shading.
            float hitDist = 0.0f;
            vec3 visRgb = lt_trace_final_visibility_with_offset(traceSample, surface, 0.01f, hitDist);
            bool isVisible = ph_luminance(visRgb) > 0.0f && traceSample.index >= 0;
            vec3 storedVisRgb = enableVisibilityTransmittance ? visRgb : (isVisible ? vec3(1.0f) : vec3(0.0f));
            RTXDI_StoreVisibilityInDIReservoir(reservoir, storedVisRgb, discardIfInvisible);
        }
    }

    storeReservoirOutputs(reservoir);
}
