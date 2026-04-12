#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;
layout(location = 3) out vec4 reconnection0_frag_out;
layout(location = 4) out vec4 reconnection1_frag_out;
layout(location = 5) out vec4 reconnection2_frag_out;
layout(location = 6) out vec4 reconnection3_frag_out;
layout(location = 7) out vec4 reconnection4_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"

void storeTemporalResult(RTXDI_DIReservoir reservoir, ScatterReconnectionData reconnection) {
    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(reservoir);
    scatter_pack_reconnection(reconnection,
        reconnection0_frag_out,
        reconnection1_frag_out,
        reconnection2_frag_out,
        reconnection3_frag_out,
        reconnection4_frag_out);
}

void storeEmptyResult() {
    storeTemporalResult(RTXDI_EmptyDIReservoir(), scatter_empty_reconnection());
}

void main() {
    ivec2 GlobalIndex = lt_current_reservoir_pos();
    if (!lt_is_active_reservoir_lane(GlobalIndex)) {
        storeEmptyResult();
        return;
    }

    const RTXDI_RuntimeParameters params = lt_build_runtime_parameters();
    ivec2 pixelPosition = RTXDI_ReservoirPosToPixelPos(GlobalIndex, int(params.activeCheckerboardField));
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        storeEmptyResult();
        return;
    }

    const RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    RAB_Surface surface = RAB_GetGBufferSurface(pixelPosition, false);
    if (!RAB_IsSurfaceValid(surface)) {
        storeEmptyResult();
        return;
    }

    RTXDI_DIReservoir currentSample = RTXDI_LoadDIReservoir(
        restirDI.reservoirBufferParams,
        uvec2(GlobalIndex),
        restirDI.bufferIndices.initialSamplingOutputBufferIndex
    );

    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(
        uvec2(pixelPosition),
        params.frameIndex,
        RTXDI_DI_SPATIAL_RESAMPLING_RANDOM_SEED + 47u
    );

    ScatterReconnectionData reconnection = scatter_empty_reconnection();
    RTXDI_DIReservoir temporalResult = lt_area_temporal_scatter_stage(
        pixelPosition,
        surface,
        currentSample,
        rng,
        reconnection
    );

    storeTemporalResult(temporalResult, reconnection);
}
