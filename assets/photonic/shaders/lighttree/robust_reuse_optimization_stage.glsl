#ifndef PHOTONICS_ROBUST_REUSE_OPTIMIZATION_STAGE_GLSL
#define PHOTONICS_ROBUST_REUSE_OPTIMIZATION_STAGE_GLSL

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"
#include "/photonics/lighttree/restir_di_spatial_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_shared.glsl"
#include "/photonics/lighttree/restir_di_temporal_shift_mapping.glsl"

const ivec2 kRobustReuseOptimizationOffsets[8] = ivec2[8](
    ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1),
    ivec2(-1,  0), ivec2(1,  0),
    ivec2(-1,  1), ivec2(0,  1), ivec2(1,  1)
);

float RobustReuseOptimization_current_to_previous_time(float time)
{
    return clamp(time + frameTime, 0.0f, 1.0f);
}

void RobustReuseOptimization_store_empty_shifted_paths(ivec2 pixel)
{
    for (int offsetIndex = 0; offsetIndex < 8; ++offsetIndex)
    {
        lt_temporal_store_shifted_path(pixel, offsetIndex, lt_temporal_empty_shifted_path());
    }
}

void RobustReuseOptimization_store_shifted_paths(ivec2 pixel)
{
    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel)
    );
    ReservoirSplattingReconnectionData prevReconnectionData = RestirDI_loadPreviousFrameReconnection(pixel);
    if (!RTXDI_IsValidDIReservoir(prevReservoir)
        || ph_luminance(PathReservoir_getIntegrand(prevReservoir)) <= 0.0f)
    {
        return;
    }

    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    RTXDI_RandomSamplerState randomSampler = lt_init_random_sampler(
        uvec2(pixel),
        runtimeParameters.frameIndex,
        1u
    );
    vec2 prevSubPixel = PathReservoir_getSubPixel(prevReservoir, pixel);

    for (int offsetIndex = 0; offsetIndex < 8; ++offsetIndex)
    {
        ivec2 neighborPixel = pixel + kRobustReuseOptimizationOffsets[offsetIndex];
        if (!lt_is_viewport_uv_in_bounds(neighborPixel))
        {
            continue;
        }

        ShiftedPathData shiftedPath = gatherLensVertexCopyShift(
            randomSampler,
            prevReconnectionData,
            RobustReuseOptimization_current_to_previous_time(prevReconnectionData.time),
            vec2(neighborPixel) + prevSubPixel,
            prevReconnectionData.lensSample,
            prevReservoir
        );
        lt_temporal_store_shifted_path(pixel, offsetIndex, shiftedPath);
    }
}

void main()
{
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    if (!lt_is_viewport_uv_in_bounds(pixel))
    {
        return;
    }

    RobustReuseOptimization_store_empty_shifted_paths(pixel);

    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    ivec2 reservoirPosition = RTXDI_PixelPosToReservoirPos(pixel, int(runtimeParameters.activeCheckerboardField));
    if (!lt_is_active_reservoir_lane(reservoirPosition))
    {
        return;
    }

    RobustReuseOptimization_store_shifted_paths(pixel);
}

#endif
