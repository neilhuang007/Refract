#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/restir_di_bridge.glsl"

#if !defined(PH_RESTIR_TEMPORAL_SCATTER_ISOLATION_MODE)
uniform float ph_restir_temporal_scatter_isolation_mode;
#endif

bool lt_temporal_scatter_disable_spatial_temporal_input()
{
#if !defined(PH_RESTIR_TEMPORAL_SCATTER_ISOLATION_MODE)
    return ph_restir_temporal_scatter_isolation_mode >= 5.0f;
#else
    return float(PH_RESTIR_TEMPORAL_SCATTER_ISOLATION_MODE) >= 5.0f;
#endif
}

void storeDIReservoir(RTXDI_DIReservoir reservoir) {
    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(reservoir);
}

void main() {
    ivec2 GlobalIndex = lt_current_reservoir_pos();
    if (!lt_is_active_reservoir_lane(GlobalIndex)) {
        storeDIReservoir(RTXDI_EmptyDIReservoir());
        return;
    }

    const RTXDI_RuntimeParameters params = lt_build_runtime_parameters();
    ivec2 pixelPosition = RTXDI_ReservoirPosToPixelPos(GlobalIndex, int(params.activeCheckerboardField));
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        storeDIReservoir(RTXDI_EmptyDIReservoir());
        return;
    }

    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(
        uvec2(pixelPosition),
        params.frameIndex,
        RTXDI_DI_SPATIAL_RESAMPLING_RANDOM_SEED
    );
    const RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    RAB_Surface surface = RAB_GetGBufferSurface(pixelPosition, false);
    RTXDI_DIReservoir spatialResult = RTXDI_EmptyDIReservoir();

    if (RAB_IsSurfaceValid(surface))
    {
        uint spatialInputBufferIndex = lt_temporal_scatter_disable_spatial_temporal_input()
            ? restirDI.bufferIndices.initialSamplingOutputBufferIndex
            : restirDI.bufferIndices.spatialResamplingInputBufferIndex;
        RTXDI_DIReservoir centerSample = RTXDI_LoadDIReservoir(
            restirDI.reservoirBufferParams,
            uvec2(GlobalIndex),
            spatialInputBufferIndex
        );

        if (RTXDI_IsValidDIReservoir(centerSample))
        {
            spatialResult = lt_area_spatial_resampling(
                pixelPosition,
                surface,
                centerSample,
                rng
            );
        }
    }

    storeDIReservoir(spatialResult);
}
