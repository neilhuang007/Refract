#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"

void storeDIReservoir(RTXDI_DIReservoir reservoir) {
    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(reservoir);
}

void main() {
    ivec2 GlobalIndex = lt_current_reservoir_pos();
    RTXDI_DIReservoir stageOutput;
    lt_temporal_scatter_emit_empty_stage_output(stageOutput);
    if (!lt_is_active_reservoir_lane(GlobalIndex)) {
        storeDIReservoir(stageOutput);
        return;
    }

    const RTXDI_RuntimeParameters params = lt_build_runtime_parameters();
    ivec2 pixelPosition = RTXDI_ReservoirPosToPixelPos(GlobalIndex, int(params.activeCheckerboardField));
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        storeDIReservoir(stageOutput);
        return;
    }

    const RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    RAB_Surface surface = RAB_GetGBufferSurface(pixelPosition, false);
    if (!RAB_IsSurfaceValid(surface)) {
        storeDIReservoir(stageOutput);
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
        RTXDI_DI_SPATIAL_RESAMPLING_RANDOM_SEED + 13u
    );

    stageOutput = lt_area_temporal_reprojection_stage(
        pixelPosition,
        surface,
        currentSample,
        rng
    );

    storeDIReservoir(stageOutput);
}
