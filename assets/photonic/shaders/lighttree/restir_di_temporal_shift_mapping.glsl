#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_SHIFT_MAPPING_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_SHIFT_MAPPING_GLSL

// Temporal scatter stages reuse the reference ShiftMapping names, but the GLSL
// port resolves radiance/jacobians through the spatial scatter helper surface.

ShiftedPathData lt_temporal_empty_shifted_path()
{
    ShiftedPathData shiftedPathData;
    shiftedPathData.primaryHit = vec3(0.0f);
    shiftedPathData.firstRayDir = vec3(0.0f, 0.0f, -1.0f);
    shiftedPathData.radiance = vec3(0.0f);
    shiftedPathData.fractionalPixel = vec2(0.0f);
    shiftedPathData.subPixel = vec2(0.5f);
    shiftedPathData.lensSample = vec2(0.5f);
    shiftedPathData.subPixelJacobian = 1.0f;
    shiftedPathData.secondaryPathJacobian = 1.0f;
    shiftedPathData.lensVertexJacobian = 1.0f;
    return shiftedPathData;
}

ShiftedPathData lt_temporal_shifted_path_from_spatial(SpatialShiftedPathData spatialShiftedPath)
{
    ShiftedPathData shiftedPathData = lt_temporal_empty_shifted_path();
    shiftedPathData.primaryHit = spatialShiftedPath.primaryHit;
    shiftedPathData.firstRayDir = spatialShiftedPath.firstRayDir;
    shiftedPathData.radiance = spatialShiftedPath.radiance;
    shiftedPathData.fractionalPixel = spatialShiftedPath.fractionalPixel;
    shiftedPathData.subPixel = spatialShiftedPath.subPixel;
    shiftedPathData.lensSample = spatialShiftedPath.lensSample;
    shiftedPathData.subPixelJacobian = spatialShiftedPath.subPixelJacobian;
    shiftedPathData.secondaryPathJacobian = spatialShiftedPath.secondaryPathJacobian;
    shiftedPathData.lensVertexJacobian = spatialShiftedPath.lensVertexJacobian;
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
    SpatialShiftedPathData spatialShiftedPath = spatial_gather_lens_vertex_copy_shift(
        rng,
        reconnectionData,
        time,
        fractionalPixel,
        lensSample,
        sourceReservoir
    );
    return lt_temporal_shifted_path_from_spatial(spatialShiftedPath);
}

ReservoirSplattingReconnectionData ScatterTemporalReconnectionData_update(
    ReservoirSplattingReconnectionData source,
    ShiftedPathData shiftedPath)
{
    ReservoirSplattingReconnectionData updated = source;
    updated.firstHit.worldPos = shiftedPath.primaryHit;
    updated.firstHit.viewDepth = length(shiftedPath.primaryHit - world_camera_position);
    updated.firstWi = -shiftedPath.firstRayDir;
    updated.subPixel = clamp(shiftedPath.subPixel, vec2(0.0f), vec2(1.0f));
    updated.lensSample = shiftedPath.lensSample;
    updated.subPixelJacobian = max(shiftedPath.subPixelJacobian, 1e-10f);
    updated.lensVertexJacobian = max(shiftedPath.lensVertexJacobian, 1e-10f);
    updated.secondaryPathJacobian = max(shiftedPath.secondaryPathJacobian, 1e-10f);
    updated.irradiance = max(shiftedPath.radiance, vec3(0.0f));
    updated.earlyThroughput = vec3(1.0f);
    return updated;
}

#endif
