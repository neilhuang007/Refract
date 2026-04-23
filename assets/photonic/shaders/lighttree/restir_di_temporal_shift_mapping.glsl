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

ShiftedPathData lt_temporal_shifted_path_from_spatial(SpatialShiftedPathData spatialShiftedPath)
{
    ShiftedPathData shiftedPathData = lt_temporal_empty_shifted_path();
    shiftedPathData.primaryHit = spatialShiftedPath.primaryHit;
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

ShiftedPathData gatherPrimaryHitReconnectionShift(
    inout RTXDI_RandomSamplerState rng,
    ReservoirSplattingReconnectionData reconnectionData,
    float time,
    vec2 fractionalPixel,
    ReservoirSplattingHitInfo primaryHit,
    RTXDI_DIReservoir sourceReservoir)
{
    SpatialShiftedPathData shiftedPathSpatial;
    shiftedPathSpatial = spatial_gather_primary_hit_reconnection_shift(
        rng,
        reconnectionData,
        time,
        fractionalPixel,
        primaryHit.worldPos,
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
    updated.subPixel = shiftedPath.fractionalPixel - floor(shiftedPath.fractionalPixel);
    updated.lensSample = shiftedPath.lensSample;
    updated.subPixelJacobian = shiftedPath.subPixelJacobian;
    updated.lensVertexJacobian = shiftedPath.lensVertexJacobian;
    updated.secondaryPathJacobian = shiftedPath.secondaryPathJacobian;
    return updated;
}

#endif
