#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_SHIFT_MAPPING_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_SHIFT_MAPPING_GLSL

// Temporal scatter stages reuse the reference ShiftMapping names, but the GLSL
// port resolves radiance/jacobians through the spatial scatter helper surface.

ShiftedPathData lt_temporal_empty_shifted_path()
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

ReservoirSplattingHitInfo lt_temporal_make_shifted_primary_hit(SpatialShiftedPathData spatialShiftedPath)
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

ShiftedPathData lt_temporal_shifted_path_from_spatial(SpatialShiftedPathData spatialShiftedPath)
{
    ShiftedPathData shiftedPathData = lt_temporal_empty_shifted_path();
    shiftedPathData.primaryHit = lt_temporal_make_shifted_primary_hit(spatialShiftedPath);
    shiftedPathData.fractionalPixel = spatialShiftedPath.fractionalPixel;
    shiftedPathData.lensSample = spatialShiftedPath.lensSample;
    shiftedPathData.firstRayDir = spatialShiftedPath.firstRayDir;
    shiftedPathData.subPixelJacobian = spatialShiftedPath.subPixelJacobian;
    shiftedPathData.lensVertexJacobian = spatialShiftedPath.lensVertexJacobian;
    shiftedPathData.secondaryPathJacobian = spatialShiftedPath.secondaryPathJacobian;
    shiftedPathData.radiance = spatialShiftedPath.radiance;
    return shiftedPathData;
}

ShiftedPathData gatherLensVertexCopyShift(
    inout RTXDI_RandomSamplerState rng,
    ReservoirSplattingReconnectionData reconnectionData,
    float time,
    vec2 fractionalPixel,
    vec2 lensSample,
    RTXDI_DIReservoir sourceReservoir)
{
    SpatialShiftedPathData shiftedPathSpatial;
    shiftedPathSpatial = spatial_gather_lens_vertex_copy_shift(
        rng,
        reconnectionData,
        time,
        fractionalPixel,
        lensSample,
        sourceReservoir
    );
    return lt_temporal_shifted_path_from_spatial(shiftedPathSpatial);
}

ReservoirSplattingReconnectionData ReconnectionData_update(
    ReservoirSplattingReconnectionData source,
    ShiftedPathData shiftedPath)
{
    ReservoirSplattingReconnectionData updated = source;
    updated.firstHit = shiftedPath.primaryHit;
    updated.firstWi = -shiftedPath.firstRayDir;
    updated.subPixel = clamp(
        shiftedPath.fractionalPixel - floor(shiftedPath.fractionalPixel),
        vec2(0.0f),
        vec2(1.0f)
    );
    updated.lensSample = shiftedPath.lensSample;
    updated.subPixelJacobian = max(shiftedPath.subPixelJacobian, 1e-10f);
    updated.lensVertexJacobian = max(shiftedPath.lensVertexJacobian, 1e-10f);
    updated.secondaryPathJacobian = max(shiftedPath.secondaryPathJacobian, 1e-10f);
    return updated;
}

#endif
