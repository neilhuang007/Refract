#ifndef PHOTONICS_RESTIR_DI_BRIDGE_GLSL
#define PHOTONICS_RESTIR_DI_BRIDGE_GLSL

#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_di_spatial.glsl"
#include "/photonics/lighttree/restir_di_spatial_impl.glsl"
#include "/photonics/lighttree/restir_di_spatial_scatter_impl.glsl"

// ============================================================================
// Stage 3 (SpatialResampling.rt.slang) — direct port of the currently
// implemented local spatial stage, shaped after the reference file
// reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/SpatialResampling.rt.slang
//
// Algorithmic summary (lines 67-185 of the reference):
//   1. Seed SG (the port's RTXDI random sampler already does this upstream).
//   2. Load centralReservoir and centralReconnection from the PREV buffer
//      (in the port that is the temporal-stage output — `scatter_reconnection*`
//      and spatialResamplingInputBufferIndex == TEMPORAL_RESAMPLING_OUTPUT).
//   3. Compute DoF shift probabilities. Pinhole ⇒ gamma == 1 ⇒ all neighbors
//      use the lens-vertex-copy shift; the ratio (numLensVertexCopyShifts)
//      is still evaluated dynamically so a future DoF add-in drops in.
//   4. centralSampleMIS = 1.0; centralWeight = lum(central.integrand) / N * central.confidence.
//   5. dstReservoir = empty; dstReconnection = empty; validNeighbors = 0.
//   6. For each neighbor:
//        a. Select shift branch (lensVertexCopy for i < numLensVertexCopyShifts).
//        b. Pick neighborPixel via the SDK neighbor-offset LUT.
//        c. Shift central -> neighbor domain (for m1).
//        d. Accumulate centralSampleMIS += 1 - m1/(m1+centralWeight).
//        e. Shift neighbor -> central domain (for candidateWeight).
//        f. Update neighborReconnection with shifted outputs.
//        g. addSampleFromReservoir(neighborSampleMIS, neighborPHat, shiftedJacobian, neighborReservoir).
//   7. addSampleFromReservoir(centralSampleMIS, central.integrand, 1.0, centralReservoir).
//   8. dstReservoir.totalWeight /= (validNeighbors + 1).
// ============================================================================

float lt_spatial_reconnection_phat(ReservoirSplattingReconnectionData reconnection)
{
    return ph_luminance(max(reconnection.integrand, vec3(0.0f)));
}

// Unbiased contribution weight recovery.
// Reference: Reservoir.slang:112-116 PathReservoir::computeUCW = totalWeight / pHat.
//
// Port contract (see restir_di_scatter_impl.glsl:375-389):
//   * Stage 1 initial-sampling output       : weightSum = UCW (post-finalize).
//   * Stage 2 temporal-scatter output       : weightSum = totalWeight (NO finalize).
//   * Stage 3 spatial-resampling output     : weightSum = totalWeight / (N+1).
//
// Stage 3 consumes Stage 2's output for both central and neighbor reservoirs
// (see restir_di_bridge.glsl:256 loading from `spatialResamplingInputBufferIndex`
// == `TEMPORAL_RESAMPLING_OUTPUT`). Therefore the incoming `weightSum` is the
// reference's `totalWeight`, and UCW is recovered exactly as
// `PathReservoir::computeUCW = totalWeight / pHat` (Reservoir.slang:112-116).
float lt_spatial_reconnection_compute_ucw(RTXDI_DIReservoir reservoir, ReservoirSplattingReconnectionData reconnection)
{
    float pHat = lt_spatial_reconnection_phat(reconnection);
    if (pHat <= 0.0f) return 0.0f;
    float ucw = max(reservoir.weightSum, 0.0f) / pHat;
    return (isnan(ucw) || isinf(ucw) || ucw < 0.0f) ? 0.0f : ucw;
}

// Reference: Reservoir.slang:83-96 PathReservoir::addSampleFromReservoir
//   w = mis * pHat * other.computeUCW() * jacobian
//   this.totalWeight += w
//   this.confidence = min(this.confidence + other.confidence, cap)
//   rng selects with probability w / totalWeight
float lt_spatial_reservoir_confidence(RTXDI_DIReservoir reservoir)
{
    return clamp(max(reservoir.M, 0.0f), 0.0f, SCATTER_RECONNECTION_CONFIDENCE_MAX);
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
        * RTXDI_GetDIReservoirInvPdf(sampleReservoir)
        * shiftedJacobian;
    bool selected = RTXDI_InternalSimpleResample(
        dstReservoir.M,
        risWeight,
        lt_next_random(sg)
    );
    if (!selected) {
        return false;
    }

    dstReservoir.pixelSampleUV = sampleReservoir.pixelSampleUV;
    dstReservoir.lensSampleUV  = sampleReservoir.lensSampleUV;
    dstReservoir.pathSample    = sampleReservoir.pathSample;
    dstReservoir.canonicalWeight = sampleReservoir.canonicalWeight;
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
    updated.worldPos              = shifted.primaryHit;
    updated.firstWi               = -shifted.firstRayDir;
    updated.faceId                = uint(round(scatter_load_surface_identity(landingPixel, false).w));
    // Update the relevant data.
    updated.subPixel              = shifted.subPixel;
    updated.lensSample            = shifted.lensSample;
    updated.subPixelJacobian      = max(shifted.subPixelJacobian, 1e-10f);
    updated.lensVertexJacobian    = max(shifted.lensVertexJacobian, 1e-10f);
    updated.secondaryPathJacobian = max(shifted.secondaryPathJacobian, 1e-10f);
    updated.integrand             = max(shifted.radiance, vec3(0.0f));
    return updated;
}

// Reads the spatial input reconnection buffer at the current pixel.
// Mirrors `prevReconnectionData[reservoirIdx]` from SpatialResampling.rt.slang:101.
ReservoirSplattingReconnectionData SpatialResampling_load_prev_reconnection(ivec2 pixel)
{
    vec4 reservoirMeta = texelFetch(radiosity_reservoir_meta, pixel, 0);
    vec4 sampleData    = texelFetch(radiosity_reservoir_samples, pixel, 0);
    return scatter_unpack_reconnection(
        texelFetch(current_stage_reconnection0, pixel, 0),
        texelFetch(current_stage_reconnection1, pixel, 0),
        sampleData,
        reservoirMeta.y,
        reservoirMeta.z
    );
}

// Resolve the DoF shift probabilities for a primary hit (or env map if there
// is no valid hit). Pinhole camera => always returns (1, 0) but we compute it
// dynamically to preserve parity hooks.
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

    RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();

    vec2 depthOfFieldProbs = lt_spatial_resolve_dof_probabilities(centerSurface);
    uint numLensVertexCopyShifts = uint(round(depthOfFieldProbs.x * float(spatialResampling.neighborCount)));

    float centralSampleMIS = 1.0f;
    float centralWeight = ph_luminance(max(centralReservoir.integrand, vec3(0.0f)))
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
            restirDI.reservoirBufferParams,
            uvec2(neighborPixel),
            restirDI.bufferIndices.spatialResamplingInputBufferIndex
        );
        ReservoirSplattingReconnectionData neighborReconnection = SpatialResampling_load_prev_reconnection(neighborPixel);

        float m1 = 0.0f;
        if (any(centralReservoir.integrand > 0.0f))
        {
            vec2 fractionalPixel = vec2(neighborPixel) + centralReservoir.pixelSampleUV;
            ShiftedPathData shiftedCentral = lensVertexCopyShift
                ? gatherLensVertexCopyShift(sg, centralReconnection, centralReconnection.time, fractionalPixel, centralReconnection.lensSample)
                : gatherPrimaryHitReconnectionShift(sg, centralReconnection, centralReconnection.time, fractionalPixel, centralReconnection.firstHit);

            float shiftedJacobian = (lensVertexCopyShift ? 1.0f : (shiftedCentral.lensVertexJacobian / centralReconnection.lensVertexJacobian))
                * (shiftedCentral.secondaryPathJacobian / centralReconnection.secondaryPathJacobian);

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
        if (any(neighborReservoir.integrand > 0.0f))
        {
            vec2 fractionalPixel = vec2(pixel) + neighborReservoir.pixelSampleUV;
            ShiftedPathData shiftedNeighbor = lensVertexCopyShift
                ? gatherLensVertexCopyShift(sg, neighborReconnection, neighborReconnection.time, fractionalPixel, neighborReconnection.lensSample)
                : gatherPrimaryHitReconnectionShift(sg, neighborReconnection, neighborReconnection.time, fractionalPixel, neighborReconnection.firstHit);

            shiftedJacobian = (lensVertexCopyShift ? 1.0f : (shiftedNeighbor.lensVertexJacobian / neighborReconnection.lensVertexJacobian))
                * (shiftedNeighbor.secondaryPathJacobian / neighborReconnection.secondaryPathJacobian);

            float neighborWeight = ph_luminance(max(shiftedNeighbor.radiance, vec3(0.0f)))
                * shiftedJacobian
                * (spatialResampling.useConfidenceWeights ? lt_spatial_reservoir_confidence(centralReservoir) : 1.0f);
            neighborPHat = isnan(neighborWeight) ? vec3(0.0f) : max(shiftedNeighbor.radiance, vec3(0.0f));
            shiftedJacobian = isnan(neighborWeight) ? 1.0f : shiftedJacobian;
            neighborWeight = isnan(neighborWeight) ? 0.0f : neighborWeight / float(spatialResampling.neighborCount);

            neighborReconnection = ReconnectionData_update(neighborReconnection, shiftedNeighbor);

            float m2 = ph_luminance(max(neighborReservoir.integrand, vec3(0.0f)))
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
        centralReservoir.integrand,
        1.0f,
        centralReservoir,
        centralReconnection,
        centralReconnection.subPixel,
        false
    );
    dstReconnectionData = centralSelected ? centralReconnection : dstReconnectionData;

    dstReservoir.weightSum /= float(validNeighbors + 1);

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
    RTXDI_RuntimeParameters runtimeParams = lt_build_runtime_parameters();

    SpatialResampling spatialResampling;
    spatialResampling.params = spatialParams;
    spatialResampling.useConfidenceWeights = true;
    spatialResampling.iteration = 0u;
    spatialResampling.neighborCount = (centralReservoir.M < float(spatialParams.targetHistoryLength))
        ? max(spatialParams.numDisocclusionBoostSamples, spatialParams.numSamples)
        : spatialParams.numSamples;
    spatialResampling.neighborCount = max(spatialResampling.neighborCount, 1u);
    spatialResampling.gatherRadius = spatialParams.samplingRadius;
    spatialResampling.pixel = pixel;
    spatialResampling.centerSurface = centerSurface;
    spatialResampling.centralReservoir = centralReservoir;
    spatialResampling.centralReconnectionData = SpatialResampling_load_prev_reconnection(pixel);

    RTXDI_DIReservoir currReservoir = RTXDI_EmptyDIReservoir();
    lt_SpatialResampling_run(spatialResampling, sg, currReservoir, currReconnectionData);
    return currReservoir;
}

#endif
