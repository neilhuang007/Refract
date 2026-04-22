#ifndef PHOTONICS_RESTIR_DI_BRIDGE_GLSL
#define PHOTONICS_RESTIR_DI_BRIDGE_GLSL

#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"
#include "/photonics/lighttree/restir_di_spatial.glsl"
#include "/photonics/lighttree/restir_di_spatial_impl.glsl"
#include "/photonics/lighttree/restir_di_spatial_scatter_impl.glsl"

// ============================================================================
// Stage 3 (SpatialResampling.rt.slang) -- direct port of the currently
// implemented local spatial stage, shaped after the reference file
// reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/SpatialResampling.rt.slang
// ============================================================================

vec3 lt_spatial_reconnection_integrand(ReservoirSplattingReconnectionData reconnection)
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
    ReservoirSplattingReconnectionData reconnection)
{
    float ucw = PathReservoir_computeStoredUCW(pathReservoir);
    return (isnan(ucw) || isinf(ucw) || ucw < 0.0f) ? 0.0f : ucw;
}

// Unbiased contribution weight recovery.
// Reference: Reservoir.slang:112-116 PathReservoir::computeUCW = totalWeight / pHat.
float lt_spatial_reconnection_compute_ucw(RTXDI_DIReservoir reservoir, ReservoirSplattingReconnectionData reconnection)
{
    return PathReservoir_computeUCW(reservoir, reconnection);
}

float lt_spatial_reservoir_confidence(RTXDI_DIReservoir reservoir)
{
    return PathReservoir_getConfidence(reservoir);
}

bool lt_spatial_reservoir_add_sample_from_reservoir(
    inout RTXDI_DIReservoir dstReservoir,
    inout ReservoirSplattingReconnectionData dstReconnectionData,
    inout RTXDI_RandomSamplerState sg,
    float sampleMIS,
    vec3 samplePHat,
    float shiftedJacobian,
    RTXDI_DIReservoir sampleReservoir,
    ReservoirSplattingReconnectionData sampleReconnectionData,
    vec2 sampleSubPixel,
    bool overwriteSubPixel)
{
    float risWeight = sampleMIS
        * ph_luminance(max(samplePHat, vec3(0.0f)))
        * lt_spatial_reconnection_compute_ucw(sampleReservoir, sampleReconnectionData)
        * shiftedJacobian;

    // Reference parity (Reservoir.slang PathReservoir::addSampleFromReservoir lines 87-91):
    //   this.totalWeight = this.totalWeight + w;
    //   this.confidence  = min(this.confidence + other.confidence, confidenceCap);
    //   float rng        = sampleNext1D(sg);
    //   bool  selected   = (rng * this.totalWeight < w);
    PathReservoir_setTotalWeight(dstReservoir, PathReservoir_getTotalWeight(dstReservoir) + risWeight);
    PathReservoir_setConfidence(
        dstReservoir,
        PathReservoir_getConfidence(dstReservoir) + lt_spatial_reservoir_confidence(sampleReservoir)
    );

    float selectionRandom = lt_next_random(sg);
    bool selected = (selectionRandom * PathReservoir_getTotalWeight(dstReservoir) < risWeight);
    if (!selected) {
        return false;
    }

    dstReservoir.lightData = sampleReservoir.lightData;
    dstReservoir.uvData = sampleReservoir.uvData;
    dstReservoir.targetPdf = sampleReservoir.targetPdf;
    dstReservoir.packedVisibility = sampleReservoir.packedVisibility;
    dstReservoir.spatialDistance = sampleReservoir.spatialDistance;
    dstReservoir.age = sampleReservoir.age;
    dstReservoir.canonicalWeight = sampleReservoir.canonicalWeight;
    dstReservoir.transportAux0 = sampleReservoir.transportAux0;
    dstReservoir.transportAux1 = sampleReservoir.transportAux1;
    dstReservoir.pixelSampleUV = sampleReservoir.pixelSampleUV;
    dstReservoir.lensSampleUV  = sampleReservoir.lensSampleUV;
    dstReservoir.pathSample    = sampleReservoir.pathSample;

    dstReconnectionData = sampleReconnectionData;
    dstReconnectionData.subPixel = overwriteSubPixel ? sampleSubPixel : dstReconnectionData.subPixel;
    return true;
}

// Writes the shifted outputs onto an existing reconnection record. Mirrors
// `ReconnectionData::update(shiftedPath)` from the reference.
ReservoirSplattingReconnectionData ReconnectionData_update(
    ReservoirSplattingReconnectionData source,
    SpatialShiftedPathData shifted)
{
    ReservoirSplattingReconnectionData updated = source;
    ivec2 landingPixel = clamp(
        ivec2(floor(shifted.fractionalPixel)),
        ivec2(0),
        ivec2(int(viewWidth) - 1, int(viewHeight) - 1)
    );
    updated.firstHit.worldPos       = shifted.primaryHit;
    updated.firstHit.viewDepth      = length(shifted.primaryHit - world_camera_position);
    updated.firstWi                 = -shifted.firstRayDir;
    updated.firstHit.faceId         = uint(round(scatter_load_surface_identity(landingPixel, false).w));
    updated.secondHit.faceId        = updated.firstHit.faceId;
    updated.subPixel                = clamp(
        shifted.fractionalPixel - floor(shifted.fractionalPixel),
        vec2(0.0f),
        vec2(1.0f)
    );
    updated.lensSample              = shifted.lensSample;
    updated.subPixelJacobian        = max(shifted.subPixelJacobian, 1e-10f);
    updated.lensVertexJacobian      = max(shifted.lensVertexJacobian, 1e-10f);
    updated.secondaryPathJacobian   = max(shifted.secondaryPathJacobian, 1e-10f);
    return updated;
}

ReservoirSplattingReconnectionData SpatialResampling_load_input_reconnection(ivec2 pixel, RTXDI_DIReservoir reservoir)
{
    vec4 reservoirMeta = texelFetch(radiosity_reservoir_meta, pixel, 0);
    vec4 sampleData    = texelFetch(radiosity_reservoir_samples, pixel, 0);
    ReservoirSplattingReconnectionData reconnection;
    scatter_unpack_reconnection(
        texelFetch(current_stage_reconnection0, pixel, 0),
        texelFetch(current_stage_reconnection1, pixel, 0),
        sampleData,
        reservoirMeta.y,
        reservoirMeta.z,
        reconnection
    );
    RestirDI_restoreReconnectionRadiometry(pixel, false, reservoir, reconnection);
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
    ReservoirSplattingReconnectionData centralReconnectionData;
};

void lt_SpatialResampling_run(
    SpatialResampling spatialResampling,
    inout RTXDI_RandomSamplerState sg,
    out RTXDI_DIReservoir currReservoir,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    ivec2 pixel = spatialResampling.pixel;
    RAB_Surface centerSurface = spatialResampling.centerSurface;
    RTXDI_DIReservoir centralReservoir = spatialResampling.centralReservoir;
    ReservoirSplattingReconnectionData centralReconnection = spatialResampling.centralReconnectionData;

    currReservoir = RTXDI_EmptyDIReservoir();
    currReconnectionData = ReservoirSplattingReconnectionData_init();
    if (!RAB_IsSurfaceValid(centerSurface) || !RTXDI_IsValidDIReservoir(centralReservoir)) {
        return;
    }

    RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();

    vec2 depthOfFieldProbs = lt_spatial_resolve_dof_probabilities(centerSurface);
    uint numLensVertexCopyShifts = uint(round(depthOfFieldProbs.x * float(spatialResampling.neighborCount)));

    float centralSampleMIS = 1.0f;
    float centralWeight = lt_spatial_path_phat(centralReservoir)
        / float(spatialResampling.neighborCount)
        * (spatialResampling.useConfidenceWeights
            ? lt_spatial_reservoir_confidence(centralReservoir)
            : 1.0f);

    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    ReservoirSplattingReconnectionData dstReconnectionData = ReservoirSplattingReconnectionData_init();

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
        validNeighbors += 1;

        RTXDI_DIReservoir neighborReservoir = RTXDI_LoadDIReservoir(
            lt_build_restir_di_parameters().reservoirBufferParams,
            uvec2(neighborPixel),
            lt_build_restir_di_parameters().bufferIndices.spatialResamplingInputBufferIndex
        );
        ReservoirSplattingReconnectionData neighborReconnection = SpatialResampling_load_input_reconnection(neighborPixel, neighborReservoir);

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

            m1 = ph_luminance(max(shiftedCentral.radiance, vec3(0.0f)))
                * shiftedJacobian
                * (spatialResampling.useConfidenceWeights ? lt_spatial_reservoir_confidence(neighborReservoir) : 1.0f);
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

            float neighborWeight = ph_luminance(max(shiftedNeighbor.radiance, vec3(0.0f)))
                * shiftedJacobian
                * (spatialResampling.useConfidenceWeights ? lt_spatial_reservoir_confidence(centralReservoir) : 1.0f);
            neighborPHat = isnan(neighborWeight) ? vec3(0.0f) : max(shiftedNeighbor.radiance, vec3(0.0f));
            shiftedJacobian = isnan(neighborWeight) ? 1.0f : shiftedJacobian;
            neighborWeight = isnan(neighborWeight) ? 0.0f : neighborWeight / float(spatialResampling.neighborCount);

            neighborReconnection = ReconnectionData_update(neighborReconnection, shiftedNeighbor);

            float m2 = lt_spatial_path_phat(neighborReservoir)
                * (spatialResampling.useConfidenceWeights ? lt_spatial_reservoir_confidence(neighborReservoir) : 1.0f);
            neighborSampleMIS = (m2 + neighborWeight > 0.0f) ? m2 / (neighborWeight + m2) : 0.0f;

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
        : ReservoirSplattingReconnectionData_init();
}

RTXDI_DIReservoir lt_di_spatial_resampling_stage(
    ivec2 pixel,
    RAB_Surface centerSurface,
    RTXDI_DIReservoir centralReservoir,
    inout RTXDI_RandomSamplerState sg,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    RTXDI_DISpatialResamplingParameters spatialParams = restirDI.spatialResamplingParams;

    SpatialResampling spatialResampling;
    spatialResampling.params = spatialParams;
    spatialResampling.useConfidenceWeights = true;
    spatialResampling.iteration = 0u;
    spatialResampling.neighborCount = (PathReservoir_getConfidence(centralReservoir) < float(spatialParams.targetHistoryLength))
        ? max(spatialParams.numDisocclusionBoostSamples, spatialParams.numSamples)
        : spatialParams.numSamples;
    spatialResampling.neighborCount = max(spatialResampling.neighborCount, 1u);
    spatialResampling.gatherRadius = spatialParams.samplingRadius;
    spatialResampling.pixel = pixel;
    spatialResampling.centerSurface = centerSurface;
    spatialResampling.centralReservoir = centralReservoir;
    spatialResampling.centralReconnectionData = SpatialResampling_load_input_reconnection(pixel, centralReservoir);

    RTXDI_DIReservoir currReservoir = RTXDI_EmptyDIReservoir();
    lt_SpatialResampling_run(spatialResampling, sg, currReservoir, currReconnectionData);
    return currReservoir;
}

#endif
