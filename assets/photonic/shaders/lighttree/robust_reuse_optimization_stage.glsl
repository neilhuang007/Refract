#ifndef PHOTONICS_ROBUST_REUSE_OPTIMIZATION_STAGE_GLSL
#define PHOTONICS_ROBUST_REUSE_OPTIMIZATION_STAGE_GLSL

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"
#include "/photonics/lighttree/restir_di_spatial_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_shared.glsl"

const ivec2 kRobustReuseOptimizationOffsets[8] = ivec2[8](
    ivec2(-1, -1), ivec2(0, -1), ivec2(1, -1),
    ivec2(-1,  0), ivec2(1,  0),
    ivec2(-1,  1), ivec2(0,  1), ivec2(1,  1)
);

ShiftedPathData RobustReuseOptimization_empty_shifted_path()
{
    ShiftedPathData shiftedPathData;
    shiftedPathData.primaryHit = ReservoirSplattingHitInfo_empty();
    shiftedPathData.fractionalPixel = vec2(-1.0f);
    shiftedPathData.lensSample = vec2(0.0f);
    shiftedPathData.firstRayDir = vec3(0.0f);
    shiftedPathData.subPixelJacobian = 1.0f;
    shiftedPathData.lensVertexJacobian = 1.0f;
    shiftedPathData.secondaryPathJacobian = 1.0f;
    shiftedPathData.radiance = vec3(0.0f);
    return shiftedPathData;
}

ReservoirSplattingHitInfo RobustReuseOptimization_make_shifted_primary_hit(
    SpatialShiftedPathData spatialShiftedPath)
{
    ReservoirSplattingHitInfo primaryHit = ReservoirSplattingHitInfo_empty();
    ivec2 landingPixel = clamp(
        ivec2(floor(spatialShiftedPath.fractionalPixel)),
        ivec2(0),
        ivec2(int(viewWidth) - 1, int(viewHeight) - 1)
    );
    primaryHit.worldPos = spatialShiftedPath.primaryHit;
    primaryHit.viewDepth = length(spatialShiftedPath.primaryHit - world_camera_position);
    primaryHit.faceId = uint(round(scatter_load_surface_identity(landingPixel, false).w));
    return primaryHit;
}

ShiftedPathData RobustReuseOptimization_shifted_path_from_spatial(
    SpatialShiftedPathData spatialShiftedPath)
{
    ShiftedPathData shiftedPathData = RobustReuseOptimization_empty_shifted_path();
    shiftedPathData.primaryHit = RobustReuseOptimization_make_shifted_primary_hit(spatialShiftedPath);
    shiftedPathData.fractionalPixel = spatialShiftedPath.fractionalPixel;
    shiftedPathData.lensSample = spatialShiftedPath.lensSample;
    shiftedPathData.firstRayDir = spatialShiftedPath.firstRayDir;
    shiftedPathData.subPixelJacobian = spatialShiftedPath.subPixelJacobian;
    shiftedPathData.lensVertexJacobian = spatialShiftedPath.lensVertexJacobian;
    shiftedPathData.secondaryPathJacobian = spatialShiftedPath.secondaryPathJacobian;
    shiftedPathData.radiance = spatialShiftedPath.radiance;
    return shiftedPathData;
}

ShiftedPathData RobustReuseOptimization_gather_lens_vertex_copy_shift(
    inout RTXDI_RandomSamplerState rng,
    ReservoirSplattingReconnectionData reconnectionData,
    float time,
    vec2 fractionalPixel,
    vec2 lensSample,
    RTXDI_DIReservoir sourceReservoir)
{
    SpatialShiftedPathData shiftedPathSpatial = spatial_gather_lens_vertex_copy_shift(
        rng,
        reconnectionData,
        time,
        fractionalPixel,
        lensSample,
        sourceReservoir
    );
    return RobustReuseOptimization_shifted_path_from_spatial(shiftedPathSpatial);
}

void RobustReuseOptimization_store_shifted_path(
    ivec2 pixel,
    int offsetIndex,
    ShiftedPathData shiftedPath)
{
    ph_temporal_gather_shifted_paths_data[
        lt_temporal_gather_shifted_path_vec4_index(pixel, offsetIndex, 0u)
    ] = vec4(shiftedPath.primaryHit.worldPos, shiftedPath.primaryHit.viewDepth);
    ph_temporal_gather_shifted_paths_data[
        lt_temporal_gather_shifted_path_vec4_index(pixel, offsetIndex, 1u)
    ] = vec4(
        uintBitsToFloat(shiftedPath.primaryHit.faceId),
        shiftedPath.fractionalPixel,
        shiftedPath.lensSample.x
    );
    ph_temporal_gather_shifted_paths_data[
        lt_temporal_gather_shifted_path_vec4_index(pixel, offsetIndex, 2u)
    ] = vec4(shiftedPath.lensSample.y, shiftedPath.firstRayDir);
    ph_temporal_gather_shifted_paths_data[
        lt_temporal_gather_shifted_path_vec4_index(pixel, offsetIndex, 3u)
    ] = vec4(
        shiftedPath.subPixelJacobian,
        shiftedPath.lensVertexJacobian,
        shiftedPath.secondaryPathJacobian,
        0.0f
    );
    ph_temporal_gather_shifted_paths_data[
        lt_temporal_gather_shifted_path_vec4_index(pixel, offsetIndex, 4u)
    ] = vec4(shiftedPath.radiance, 0.0f);
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
            ? RobustReuseOptimization_gather_lens_vertex_copy_shift(
                sg,
                prevReconnection,
                prevReconnection.time + frameTime,
                vec2(neighborPixel) + prevSubPixel,
                prevReconnection.lensSample,
                prevReservoir
            )
            : RobustReuseOptimization_empty_shifted_path();

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
