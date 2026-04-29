#ifndef PHOTONICS_RESTIR_DI_SPATIAL_GLSL
#define PHOTONICS_RESTIR_DI_SPATIAL_GLSL

// Reference stage module: SpatialResampling.rt.slang

#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"
#include "/photonics/lighttree/restir_di_spatial_impl.glsl"
#include "/photonics/lighttree/restir_di_spatial_scatter_impl.glsl"

vec3 lt_spatial_reconnection_integrand(ReconnectionData reconnection)
{
    return scatter_reconnection_integrand(reconnection);
}

vec3 lt_spatial_path_integrand(RTXDI_DIReservoir reservoir)
{
    return PathReservoir_getIntegrand(reservoir);
}

float lt_spatial_path_phat(RTXDI_DIReservoir reservoir)
{
    return ph_luminance(lt_spatial_path_integrand(reservoir));
}

float PathReservoir_computeUCW(
    RTXDI_DIReservoir pathReservoir,
    ReconnectionData reconnection)
{
    float ucw = PathReservoir_computeStoredUCW(pathReservoir);
    return (isnan(ucw) || isinf(ucw) || ucw < 0.0f) ? 0.0f : ucw;
}

float lt_spatial_reconnection_compute_ucw(
    RTXDI_DIReservoir reservoir,
    ReconnectionData reconnection)
{
    return PathReservoir_computeUCW(reservoir, reconnection);
}

bool lt_spatial_reservoir_add_sample_from_reservoir(
    inout RTXDI_DIReservoir dstReservoir,
    inout ReconnectionData dstReconnectionData,
    inout RTXDI_RandomSamplerState sg,
    float sampleMIS,
    vec3 samplePHat,
    float shiftedJacobian,
    RTXDI_DIReservoir sampleReservoir,
    ReconnectionData sampleReconnectionData,
    vec2 sampleSubPixel,
    bool overwriteSubPixel)
{
    float risWeight = sampleMIS
        * ph_luminance(samplePHat)
        * lt_spatial_reconnection_compute_ucw(sampleReservoir, sampleReconnectionData)
        * shiftedJacobian;

    PathReservoir_setTotalWeight(dstReservoir, PathReservoir_getTotalWeight(dstReservoir) + risWeight);
    dstReservoir.M += max(sampleReservoir.M, 0.0f);

    float accumulatedConfidence = PathReservoir_getConfidence(dstReservoir)
        + PathReservoir_getConfidence(sampleReservoir);

    float selectionRandom = lt_next_random(sg);
    bool selected = (selectionRandom * PathReservoir_getTotalWeight(dstReservoir) < risWeight);
    if (!selected)
    {
        PathReservoir_setConfidence(dstReservoir, accumulatedConfidence);
        return false;
    }

    dstReservoir.lightData = sampleReservoir.lightData;
    dstReservoir.uvData = sampleReservoir.uvData;
    dstReservoir.targetPdf = ph_luminance(max(samplePHat, vec3(0.0f)));
    dstReservoir.packedVisibility = sampleReservoir.packedVisibility;
    dstReservoir.spatialDistance = sampleReservoir.spatialDistance;
    dstReservoir.age = sampleReservoir.age;
    PathReservoir_setIntegrand(dstReservoir, samplePHat);
    dstReservoir.pixelSampleUV = sampleReservoir.pixelSampleUV;
    dstReservoir.lensSampleUV = sampleReservoir.lensSampleUV;
    dstReservoir.pathSample = sampleReservoir.pathSample;
    PathReservoir_setConfidence(dstReservoir, accumulatedConfidence);

    dstReconnectionData = sampleReconnectionData;
    dstReconnectionData.subPixel = overwriteSubPixel ? sampleSubPixel : dstReconnectionData.subPixel;
    return true;
}

ReconnectionData ReconnectionData_update(
    ReconnectionData source,
    SpatialShiftedPathData shifted)
{
    ReconnectionData updated = source;
    updated.firstHit = shifted.primaryHit;
    updated.subPixel = shifted.fractionalPixel - floor(shifted.fractionalPixel);
    updated.lensSample = shifted.lensSample;
    updated.firstWi = -shifted.firstRayDir;
    updated.subPixelJacobian = shifted.subPixelJacobian;
    updated.lensVertexJacobian = shifted.lensVertexJacobian;
    updated.secondaryPathJacobian = shifted.secondaryPathJacobian;
    return updated;
}

ReconnectionData SpatialResampling_load_input_reconnection(
    ivec2 pixel,
    RTXDI_DIReservoir inputReservoir)
{
    ReconnectionData reconnection;
    scatter_unpack_reconnection(
        texelFetch(scatter_reconnection0, pixel, 0),
        texelFetch(scatter_reconnection1, pixel, 0),
        texelFetch(scatter_reconnection2, pixel, 0),
        texelFetch(scatter_reconnection3, pixel, 0),
        texelFetch(scatter_reconnection4, pixel, 0),
        0.0f,
        0.0f,
        reconnection
    );
    RestirDI_restoreReconnectionRadiometry(pixel, false, inputReservoir, reconnection);
    return reconnection;
}

vec2 lt_spatial_resolve_dof_probabilities(RAB_Surface centerSurface)
{
    float circleOfConfusion = RAB_IsSurfaceValid(centerSurface)
        ? spatial_compute_primary_hit_circle_of_confusion(centerSurface.worldPos)
        : spatial_compute_env_map_circle_of_confusion();
    return spatial_compute_depth_of_field_gather_shift_probabilities(circleOfConfusion);
}

struct SpatialResampling
{
    RTXDI_DISpatialResamplingParameters params;
    bool useConfidenceWeights;

    uint iteration;
    uint neighborCount;
    float gatherRadius;

    ivec2 pixel;
    RAB_Surface centerSurface;
    RTXDI_DIReservoir centralReservoir;
    ReconnectionData centralReconnectionData;
};

void SpatialResampling_execute(
    SpatialResampling spatialResampling,
    inout RTXDI_RandomSamplerState sg,
    out RTXDI_DIReservoir currReservoir,
    out ReconnectionData currReconnectionData)
{
    ivec2 pixel = spatialResampling.pixel;
    RAB_Surface centerSurface = spatialResampling.centerSurface;
    RTXDI_DIReservoir centralReservoir = spatialResampling.centralReservoir;
    ReconnectionData centralReconnection = spatialResampling.centralReconnectionData;

    currReservoir = RTXDI_EmptyDIReservoir();
    currReconnectionData = ReconnectionData_init();
    if (!RAB_IsSurfaceValid(centerSurface) || !RTXDI_IsValidDIReservoir(centralReservoir))
    {
        return;
    }

    RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    RTXDI_Parameters restirDI = lt_build_restir_di_parameters();

    vec2 depthOfFieldProbs = lt_spatial_resolve_dof_probabilities(centerSurface);
    uint numLensVertexCopyShifts = uint(round(depthOfFieldProbs.x * float(spatialResampling.neighborCount)));

    float centralSampleMIS = 1.0f;
    float centralWeight = lt_spatial_path_phat(centralReservoir)
        / float(spatialResampling.neighborCount)
        * (spatialResampling.useConfidenceWeights
            ? PathReservoir_getConfidence(centralReservoir)
            : 1.0f);

    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    ReconnectionData dstReconnectionData = ReconnectionData_init();

    int validNeighbors = 0;
    uint startIdx = uint(lt_next_random(sg) * float(runtimeParameters.neighborOffsetMask + 1u));
    for (uint i = 0u; i < spatialResampling.neighborCount; ++i)
    {
        bool lensVertexCopyShift = (i < numLensVertexCopyShifts);

        uint neighborOffsetIdx = (startIdx + i) & runtimeParameters.neighborOffsetMask;
        ivec2 neighborPixel = ivec2(round(
            vec2(pixel) + spatialResampling.gatherRadius * lt_load_neighbor_offset(int(neighborOffsetIdx))
        ));
        if (!lt_is_viewport_uv_in_bounds(neighborPixel)) continue;

        RAB_Surface neighborSurface = RAB_GetGBufferSurface(neighborPixel, false);
        if (!RAB_IsSurfaceValid(neighborSurface)) continue;

        if (!RTXDI_IsValidNeighbor(
            RAB_GetSurfaceNormal(centerSurface),
            RAB_GetSurfaceNormal(neighborSurface),
            RAB_GetSurfaceLinearDepth(centerSurface),
            RAB_GetSurfaceLinearDepth(neighborSurface),
            spatialResampling.params.normalThreshold,
            spatialResampling.params.depthThreshold
        )) continue;

        if (spatialResampling.params.enableMaterialSimilarityTest != 0u
            && !RAB_AreMaterialsSimilar(RAB_GetMaterial(centerSurface), RAB_GetMaterial(neighborSurface))) continue;

        validNeighbors += 1;

        ivec2 neighborReservoirPos = RTXDI_PixelPosToReservoirPos(
            neighborPixel,
            int(runtimeParameters.activeCheckerboardField)
        );

        RTXDI_DIReservoir neighborReservoir = RTXDI_LoadDIReservoir(
            restirDI.reservoirBufferParams,
            uvec2(neighborReservoirPos),
            restirDI.bufferIndices.spatialResamplingInputBufferIndex
        );
        ReconnectionData neighborReconnection = SpatialResampling_load_input_reconnection(neighborPixel, neighborReservoir);

        float m1 = 0.0f;
        if (lt_spatial_path_phat(centralReservoir) > 0.0f)
        {
            vec2 fractionalPixel = vec2(neighborPixel) + centralReconnection.subPixel;
            SpatialShiftedPathData shiftedCentral = spatial_gather_shift(
                lensVertexCopyShift,
                sg,
                centralReconnection,
                centralReconnection.time,
                fractionalPixel,
                centralReconnection.lensSample,
                centralReconnection.firstHit.worldPos,
                centralReservoir
            );

            float shiftedCentralLensRatio = lensVertexCopyShift
                ? 1.0f
                : (shiftedCentral.lensVertexJacobian / max(centralReconnection.lensVertexJacobian, 1e-10f));
            float shiftedJacobian = shiftedCentralLensRatio
                * (shiftedCentral.secondaryPathJacobian / max(centralReconnection.secondaryPathJacobian, 1e-10f));

            m1 = ph_luminance(shiftedCentral.radiance)
                * shiftedJacobian
                * (spatialResampling.useConfidenceWeights ? PathReservoir_getConfidence(neighborReservoir) : 1.0f);
            m1 = isnan(m1) ? 0.0f : m1;
        }

        centralSampleMIS += 1.0f;
        centralSampleMIS -= (m1 + centralWeight > 0.0f) ? m1 / (m1 + centralWeight) : 0.0f;

        float neighborSampleMIS = 0.0f;
        vec3 neighborPHat = vec3(0.0f);
        float shiftedJacobian = 1.0f;
        if (lt_spatial_path_phat(neighborReservoir) > 0.0f)
        {
            vec2 fractionalPixel = vec2(pixel) + neighborReconnection.subPixel;
            SpatialShiftedPathData shiftedNeighbor = spatial_gather_shift(
                lensVertexCopyShift,
                sg,
                neighborReconnection,
                neighborReconnection.time,
                fractionalPixel,
                neighborReconnection.lensSample,
                neighborReconnection.firstHit.worldPos,
                neighborReservoir
            );

            float shiftedNeighborLensRatio = lensVertexCopyShift
                ? 1.0f
                : (shiftedNeighbor.lensVertexJacobian / max(neighborReconnection.lensVertexJacobian, 1e-10f));
            shiftedJacobian = shiftedNeighborLensRatio
                * (shiftedNeighbor.secondaryPathJacobian / max(neighborReconnection.secondaryPathJacobian, 1e-10f));

            float neighborWeight = ph_luminance(shiftedNeighbor.radiance)
                * shiftedJacobian
                * (spatialResampling.useConfidenceWeights ? PathReservoir_getConfidence(centralReservoir) : 1.0f);
            neighborPHat = isnan(neighborWeight) ? vec3(0.0f) : shiftedNeighbor.radiance;
            shiftedJacobian = isnan(neighborWeight) ? 1.0f : shiftedJacobian;
            neighborWeight = isnan(neighborWeight) ? 0.0f : neighborWeight / float(spatialResampling.neighborCount);

            neighborReconnection = ReconnectionData_update(neighborReconnection, shiftedNeighbor);

            float m2 = lt_spatial_path_phat(neighborReservoir)
                * (spatialResampling.useConfidenceWeights ? PathReservoir_getConfidence(neighborReservoir) : 1.0f);
            neighborSampleMIS = (m2 + neighborWeight > 0.0f) ? m2 / (neighborWeight + m2) : 0.0f;
        }

        bool neighborSelected = lt_spatial_reservoir_add_sample_from_reservoir(
            dstReservoir,
            dstReconnectionData,
            sg,
            neighborSampleMIS,
            neighborPHat,
            shiftedJacobian,
            neighborReservoir,
            neighborReconnection,
            neighborReconnection.subPixel,
            true
        );
        dstReconnectionData = neighborSelected ? neighborReconnection : dstReconnectionData;
    }

    bool centralSelected = lt_spatial_reservoir_add_sample_from_reservoir(
        dstReservoir,
        dstReconnectionData,
        sg,
        centralSampleMIS,
        lt_spatial_path_integrand(centralReservoir),
        1.0f,
        centralReservoir,
        centralReconnection,
        centralReconnection.subPixel,
        false
    );
    dstReconnectionData = centralSelected ? centralReconnection : dstReconnectionData;

    PathReservoir_setTotalWeight(dstReservoir, PathReservoir_getTotalWeight(dstReservoir) / float(validNeighbors + 1));

    currReservoir = RTXDI_IsValidDIReservoir(dstReservoir) ? dstReservoir : RTXDI_EmptyDIReservoir();
    currReconnectionData = RTXDI_IsValidDIReservoir(dstReservoir)
        ? dstReconnectionData
        : ReconnectionData_init();
}

RTXDI_DIReservoir SpatialResampling_run(
    ivec2 pixelPosition,
    RAB_Surface centerSurface,
    RTXDI_DIReservoir centerSample,
    inout RTXDI_RandomSamplerState rng,
    out ReconnectionData reconnection)
{
    RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    RTXDI_DISpatialResamplingParameters spatialParams = restirDI.spatialResamplingParams;

    SpatialResampling spatialResampling;
    spatialResampling.params = spatialParams;
    spatialResampling.useConfidenceWeights = true;
    spatialResampling.iteration = 0u;
    spatialResampling.neighborCount = (PathReservoir_getConfidence(centerSample) < float(spatialParams.targetHistoryLength))
        ? max(spatialParams.numDisocclusionBoostSamples, spatialParams.numSamples)
        : spatialParams.numSamples;
    spatialResampling.neighborCount = max(spatialResampling.neighborCount, 1u);
    spatialResampling.gatherRadius = spatialParams.samplingRadius;
    spatialResampling.pixel = pixelPosition;
    spatialResampling.centerSurface = centerSurface;
    spatialResampling.centralReservoir = centerSample;
    spatialResampling.centralReconnectionData = SpatialResampling_load_input_reconnection(pixelPosition, centerSample);

    RTXDI_DIReservoir currReservoir = RTXDI_EmptyDIReservoir();
    SpatialResampling_execute(spatialResampling, rng, currReservoir, reconnection);
    return currReservoir;
}

#endif
