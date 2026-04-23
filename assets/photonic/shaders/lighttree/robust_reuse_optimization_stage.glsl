#ifndef PHOTONICS_ROBUST_REUSE_OPTIMIZATION_STAGE_GLSL
#define PHOTONICS_ROBUST_REUSE_OPTIMIZATION_STAGE_GLSL

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"
#include "/photonics/lighttree/restir_di_spatial_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_temporal_dof.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_shared.glsl"
#include "/photonics/lighttree/restir_di_temporal_shift_mapping.glsl"

const ivec2 kRobustReuseOptimizationOffsets[8] = ivec2[8](
    ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1),
    ivec2(-1,  0), ivec2(1,  0),
    ivec2(-1,  1), ivec2(0,  1), ivec2(1,  1)
);

void RobustReuseOptimization_store_shifted_path(
    ivec2 pixel,
    int offsetIndex,
    ShiftedPathData shiftedPath)
{
    lt_temporal_store_shifted_path(pixel, offsetIndex, shiftedPath);
}

void RobustReuseOptimization_run(ivec2 pixel)
{
    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel)
    );
    ReservoirSplattingReconnectionData prevReconnection = RestirDI_loadPreviousFrameReconnection(pixel);

    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    RTXDI_RandomSamplerState sg = lt_init_random_sampler(
        uvec2(pixel),
        runtimeParameters.frameIndex,
        1u
    );
    vec2 prevSubPixel = PathReservoir_getSubPixel(prevReservoir, pixel);
    bool canShift = ph_luminance(PathReservoir_getIntegrand(prevReservoir)) > 0.0f;

    for (int offsetIndex = 0; offsetIndex < 8; ++offsetIndex)
    {
        ivec2 neighborOffset = kRobustReuseOptimizationOffsets[offsetIndex];
        ivec2 neighborPixel = pixel + neighborOffset;
        bool neighborIsValid = lt_is_viewport_uv_in_bounds(neighborPixel);

        ShiftedPathData shiftedPath = (neighborIsValid && canShift)
            ? gatherLensVertexCopyShift(
                sg,
                prevReconnection,
                prevReconnection.time + lt_di_temporal_artificial_frame_time(),
                vec2(neighborPixel) + prevSubPixel,
                prevReconnection.lensSample,
                prevReservoir
            )
            : lt_temporal_empty_shifted_path();

        RobustReuseOptimization_store_shifted_path(pixel, offsetIndex, shiftedPath);
    }
}

void main()
{
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    if (!lt_is_viewport_uv_in_bounds(pixel))
    {
        return;
    }

    RobustReuseOptimization_run(pixel);
}

#endif
