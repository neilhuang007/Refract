#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_IMPL_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_IMPL_GLSL

// Shared DI temporal ABI surface.
// This module now exposes the step-by-step local port of the Reservoir
// Splatting temporal chain:
//   CollectTemporalSamples      -> stage 2a
//   GatherTemporalResampling    -> stage 2b
//   ReprojectTemporalSamples    -> stage 2c
//   SortReprojectedReservoirs   -> stage 2d.1 / 2d.2
//   ScatterTemporalResampling   -> stage 2e
//   MultiReprojectTemporalSamples      -> stage 2f
//   MultiSortReprojectedReservoirs     -> stage 2g.1 / 2g.2
//   MultiScatterTemporalResampling     -> stage 2h

// NOTE:
// The active temporal stage implementation now lives in reuse_bridge.glsl +
// restir_di_scatter_impl.glsl. This file is retained as a thin ABI wrapper
// surface so include ordering remains stable while the reference-structured
// implementation is consolidated elsewhere.

#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_COLLECT_STAGE)
void lt_di_store_collect_temporal_sample_result(
    vec2 floatingCoord,
    RTXDI_DIReservoir reservoir,
    ReservoirSplattingReconnectionData reconnectionData)
{
    floating_coords_frag_out = floatingCoord;

    float transportAux0;
    float transportAux1;
    scatter_pack_reconnection_fields(
        reconnectionData.firstHit.worldPos,
        reconnectionData.firstHit.viewDepth,
        reconnectionData.lightPdf,
        reconnectionData.time,
        reconnectionData.irradiance,
        reconnectionData.subPixel,
        reconnectionData.subPixelJacobian,
        reconnectionData.secondaryPathJacobian,
        reconnectionData.firstHit.faceId,
        reconnectionData.pathLength,
        reconnectionData.firstBSDFComponentType,
        reconnectionData.secondBSDFComponentType,
        reconnectionData.transmissionEvent,
        reconnectionData.lightIsNEE,
        reconnectionData.lightIsDistant,
        transportAux0,
        transportAux1,
        intermediate_reconnection0_frag_out,
        intermediate_reconnection1_frag_out
    );

    intermediate_reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    intermediate_reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    intermediate_reservoir_meta_frag_out = rtxdi_pack_reservoir_meta_with_transport(reservoir, transportAux0, transportAux1);
}

void lt_di_collect_temporal_samples_stage(
    ivec2 currPixel)
{
    vec2 prevPixel = lt_temporal_previous_pixel_center(currPixel) - vec2(0.5f);
    if (!lt_is_viewport_uv_in_bounds(ivec2(floor(prevPixel)))
        || any(lessThan(prevPixel, vec2(0.0f)))
        || any(greaterThanEqual(prevPixel, vec2(viewWidth, viewHeight)))) {
        return;
    }

    ivec2 roundedPrevPixel = ivec2(round(prevPixel));
    if (!lt_is_viewport_uv_in_bounds(roundedPrevPixel)) {
        return;
    }

    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(roundedPrevPixel)
    );
    ReservoirSplattingReconnectionData prevReconnectionData = RestirDI_loadPreviousFrameReconnection(roundedPrevPixel);

    lt_di_store_collect_temporal_sample_result(
        prevPixel,
        prevReservoir,
        prevReconnectionData
    );
}

#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_GATHER_STAGE)
#include "/photonics/lighttree/restir_di_temporal_dof.glsl"

RTXDI_DIReservoir lt_di_load_current_proposal_reservoir(
    ivec2 pixel)
{
    return RTXDI_LoadDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel),
        lt_build_restir_di_parameters().bufferIndices.initialSamplingOutputBufferIndex
    );
}

ReservoirSplattingReconnectionData lt_di_load_current_proposal_reconnection(ivec2 pixel)
{
    vec4 proposalReservoirMeta = texelFetch(radiosity_proposal_reservoir_meta, pixel, 0);
    RTXDI_DIReservoir reservoir = lt_di_load_current_proposal_reservoir(pixel);
    ReservoirSplattingReconnectionData reconnection;
    scatter_unpack_reconnection(
        texelFetch(current_stage_reconnection0, pixel, 0),
        texelFetch(current_stage_reconnection1, pixel, 0),
        texelFetch(radiosity_proposal_reservoir_samples, pixel, 0),
        proposalReservoirMeta.y,
        proposalReservoirMeta.z,
        reconnection
    );
    RestirDI_restoreReconnectionRadiometry(pixel, false, reservoir, reconnection);
    return reconnection;
}

RTXDI_DIReservoir lt_di_load_gather_intermediate_reservoir(ivec2 pixel)
{
    RTXDI_DIReservoir reservoir = RTXDI_EmptyDIReservoir();
    rtxdi_unpack_reservoir_at_surface(
        reservoir,
        texelFetch(temporal_gather_intermediate_reservoir_data, pixel, 0),
        texelFetch(temporal_gather_intermediate_reservoir_sample, pixel, 0),
        texelFetch(temporal_gather_intermediate_reservoir_meta, pixel, 0),
        RAB_EmptySurface(),
        false
    );
    return reservoir;
}

float lt_scatter_reservoir_confidence(
    RTXDI_DIReservoir reservoir,
    ScatterReconnectionData reconnection);
float lt_scatter_radiance_phat(vec3 radiance);
float lt_scatter_compute_ucw(
    RTXDI_DIReservoir reservoir,
    vec3 storedIntegrand);
bool lt_scatter_add_sample_from_reservoir(
    inout RTXDI_DIReservoir state,
    inout float stateConfidence,
    float misWeight,
    vec3 pHat,
    float jacobian,
    float otherUcw,
    float otherConfidence,
    RTXDI_DIReservoir otherReservoir,
    inout RTXDI_RandomSamplerState rng);

bool lt_di_gather_temporal_load_current_sample(
    ivec2 pixel,
    out RTXDI_DIReservoir currReservoir,
    out ReservoirSplattingReconnectionData currReconnectionData,
    out float currConfidence)
{
    currReservoir = lt_di_load_current_proposal_reservoir(pixel);
    currReconnectionData = lt_di_load_current_proposal_reconnection(pixel);
    currConfidence = lt_scatter_reservoir_confidence(currReservoir, currReconnectionData);
    return RTXDI_IsValidDIReservoir(currReservoir)
        && any(greaterThan(scatter_reconnection_integrand(currReconnectionData), vec3(0.0f)));
}

bool lt_di_gather_temporal_load_previous_sample(
    ivec2 pixel,
    out RTXDI_DIReservoir prevReservoir,
    out ReservoirSplattingReconnectionData prevReconnectionData,
    out float prevConfidence)
{
    prevReservoir = lt_di_load_gather_intermediate_reservoir(pixel);
    prevReconnectionData = RestirDI_loadGatherIntermediateReconnection(pixel);
    prevConfidence = lt_scatter_reservoir_confidence(prevReservoir, prevReconnectionData);
    return RTXDI_IsValidDIReservoir(prevReservoir)
        && any(greaterThan(scatter_reconnection_integrand(prevReconnectionData), vec3(0.0f)));
}

float lt_di_gather_temporal_current_sample_mis(
    ReservoirSplattingReconnectionData currReconnectionData,
    float currConfidence,
    float prevConfidence)
{
    vec3 currIntegrand = scatter_reconnection_integrand(currReconnectionData);
    float m1 = lt_scatter_radiance_phat(currIntegrand) * currConfidence;
    float m2 = lt_scatter_radiance_phat(currIntegrand) * prevConfidence;
    return ((m1 + m2) > 0.0f) ? (m1 / (m1 + m2)) : 0.0f;
}

float lt_di_gather_temporal_previous_sample_mis(
    ReservoirSplattingReconnectionData prevReconnectionData,
    float currConfidence,
    float prevConfidence)
{
    vec3 prevIntegrand = scatter_reconnection_integrand(prevReconnectionData);
    float m1 = lt_scatter_radiance_phat(prevIntegrand) * currConfidence;
    float m2 = lt_scatter_radiance_phat(prevIntegrand) * prevConfidence;
    return ((m1 + m2) > 0.0f) ? (m2 / (m1 + m2)) : 0.0f;
}

float lt_di_gather_temporal_confidence_weight(float confidence)
{
    return confidence;
}

float lt_di_gather_temporal_shifted_jacobian(
    LtTemporalGatherShiftedPathData shiftedPathData,
    ReservoirSplattingReconnectionData reconnectionData,
    bool primaryHitReconnection)
{
    if (primaryHitReconnection)
    {
        return (shiftedPathData.lensVertexJacobian * shiftedPathData.secondaryPathJacobian)
            / max(reconnectionData.lensVertexJacobian * reconnectionData.secondaryPathJacobian, 1e-10f);
    }
    return shiftedPathData.secondaryPathJacobian / max(reconnectionData.secondaryPathJacobian, 1e-10f);
}

float lt_di_gather_temporal_reference_mis(
    vec3 sourceRadiance,
    float sourceWeight,
    vec3 shiftedRadiance,
    float shiftedJacobian,
    float shiftedWeight,
    float shiftProbability,
    bool selectSource)
{
    float m1 = lt_scatter_radiance_phat(sourceRadiance) * sourceWeight;
    float m2 = lt_scatter_radiance_phat(shiftedRadiance) * shiftedJacobian * shiftedWeight * shiftProbability;
    m2 = isnan(m2) ? 0.0f : m2;
    float sum = m1 + m2;
    if (sum <= 0.0f)
    {
        return 0.0f;
    }
    return selectSource ? (m1 / sum) : (m2 / sum);
}

bool lt_di_gather_temporal_add_current_sample(
    ivec2 pixel,
    inout RTXDI_DIReservoir dstReservoir,
    inout ReservoirSplattingReconnectionData dstReconnectionData,
    RTXDI_DIReservoir currReservoir,
    ReservoirSplattingReconnectionData currReconnectionData,
    float currConfidence,
    float prevConfidence,
    bool primaryHitReconnection,
    float shiftProbability,
    int shiftedPathIndex,
    inout RTXDI_RandomSamplerState sg)
{
    float currSampleMIS = 0.0f;
    vec3 currPHat = vec3(0.0f);
    vec3 currIntegrand = scatter_reconnection_integrand(currReconnectionData);
    if (any(greaterThan(currIntegrand, vec3(0.0f))))
    {
        currPHat = currIntegrand;
        LtTemporalGatherShiftedPathData shiftedCurr = scatter_load_gather_shifted_path_data(pixel, shiftedPathIndex);
        float shiftedJacobian = lt_di_gather_temporal_shifted_jacobian(shiftedCurr, currReconnectionData, primaryHitReconnection);
        currSampleMIS = lt_di_gather_temporal_reference_mis(
            currIntegrand,
            lt_di_gather_temporal_confidence_weight(currConfidence),
            shiftedCurr.radiance,
            shiftedJacobian,
            lt_di_gather_temporal_confidence_weight(prevConfidence),
            shiftProbability,
            true
        );
    }

    bool currSelected = lt_scatter_add_sample_from_reservoir(
        dstReservoir,
        currConfidence,
        currSampleMIS,
        currPHat,
        1.0f,
        lt_scatter_compute_ucw(currReservoir, currPHat),
        currConfidence,
        currReservoir,
        sg
    );
    if (currSelected)
    {
        dstReconnectionData = currReconnectionData;
    }
    return currSelected;
}

bool lt_di_gather_temporal_add_previous_sample(
    ivec2 pixel,
    inout RTXDI_DIReservoir dstReservoir,
    inout ReservoirSplattingReconnectionData dstReconnectionData,
    RTXDI_DIReservoir prevReservoir,
    ReservoirSplattingReconnectionData prevReconnectionData,
    float currConfidence,
    float prevConfidence,
    bool primaryHitReconnection,
    float shiftProbability,
    int shiftedPathIndex,
    inout RTXDI_RandomSamplerState sg)
{
    float prevSampleMIS = 0.0f;
    vec3 prevPHat = vec3(0.0f);
    float shiftedJacobian = 1.0f;
    vec3 prevIntegrand = scatter_reconnection_integrand(prevReconnectionData);
    if (any(greaterThan(prevIntegrand, vec3(0.0f))))
    {
        LtTemporalGatherShiftedPathData shiftedPrev = scatter_load_gather_shifted_path_data(pixel, shiftedPathIndex);
        shiftedJacobian = lt_di_gather_temporal_shifted_jacobian(shiftedPrev, prevReconnectionData, primaryHitReconnection);
        float shiftedWeight = lt_di_gather_temporal_confidence_weight(currConfidence);
        float referenceMIS = lt_di_gather_temporal_reference_mis(
            shiftedPrev.radiance,
            shiftedWeight,
            prevIntegrand,
            1.0f,
            lt_di_gather_temporal_confidence_weight(prevConfidence),
            shiftProbability,
            false
        );
        float m1 = lt_scatter_radiance_phat(shiftedPrev.radiance) * shiftedJacobian * shiftedWeight;
        prevPHat = isnan(m1) ? vec3(0.0f) : max(shiftedPrev.radiance, vec3(0.0f));
        shiftedJacobian = isnan(m1) ? 1.0f : shiftedJacobian;
        prevSampleMIS = isnan(m1) ? 0.0f : referenceMIS;
    }

    bool prevSelected = lt_scatter_add_sample_from_reservoir(
        dstReservoir,
        prevConfidence,
        prevSampleMIS,
        prevPHat,
        shiftedJacobian,
        lt_scatter_compute_ucw(prevReservoir, prevIntegrand),
        prevConfidence,
        prevReservoir,
        sg
    );
    if (prevSelected)
    {
        dstReconnectionData = prevReconnectionData;
    }
    return prevSelected;
}

RTXDI_DIReservoir lt_di_gather_temporal_resampling_stage(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    RTXDI_RandomSamplerState sg = lt_init_random_sampler(uvec2(pixel), uint(frameCounter), 3u);
    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    currReconnectionData = ReservoirSplattingReconnectionData_init();

    RTXDI_DIReservoir currReservoir;
    ReservoirSplattingReconnectionData currentReconnectionData;
    float currConfidence = 0.0f;
    bool hasCurrentSample = lt_di_gather_temporal_load_current_sample(
        pixel,
        currReservoir,
        currentReconnectionData,
        currConfidence
    );

    RTXDI_DIReservoir prevReservoir;
    ReservoirSplattingReconnectionData prevReconnectionData;
    float prevConfidence = 0.0f;
    bool hasPreviousSample = lt_di_gather_temporal_load_previous_sample(
        pixel,
        prevReservoir,
        prevReconnectionData,
        prevConfidence
    );

    RAB_Surface centerSurface = RAB_GetGBufferSurface(pixel, false);
    const bool hasDepthOfField = lt_di_temporal_camera_aperture_radius() > 0.0f;
    vec2 depthOfFieldProbs = hasDepthOfField
        ? lt_di_temporal_resolve_dof_probabilities(centerSurface)
        : vec2(1.0f, 0.0f);
    const bool doLensVertexCopy = (depthOfFieldProbs.x > 0.0f);
    const bool doPrimaryHitReconnection = (depthOfFieldProbs.y > 0.0f);

    if (doLensVertexCopy)
    {
        lt_di_gather_temporal_add_current_sample(
            pixel,
            dstReservoir,
            currReconnectionData,
            currReservoir,
            currentReconnectionData,
            currConfidence,
            prevConfidence,
            false,
            depthOfFieldProbs.x,
            0,
            sg
        );
    }

    if (hasPreviousSample)
    {
        lt_di_gather_temporal_add_previous_sample(
            pixel,
            dstReservoir,
            currReconnectionData,
            prevReservoir,
            prevReconnectionData,
            currConfidence,
            prevConfidence,
            false,
            depthOfFieldProbs.x,
            1,
            sg
        );
    }

    if (hasDepthOfField && doPrimaryHitReconnection)
    {
        RTXDI_DIReservoir lensVertexCopyReservoir = dstReservoir;
        ReservoirSplattingReconnectionData lensVertexCopyReconnectionData = currReconnectionData;
        dstReservoir = RTXDI_EmptyDIReservoir();
        currReconnectionData = ReservoirSplattingReconnectionData_init();

        RTXDI_DIReservoir currentDomainReservoir = hasCurrentSample ? lensVertexCopyReservoir : currReservoir;
        ReservoirSplattingReconnectionData currentDomainReconnectionData = hasCurrentSample ? lensVertexCopyReconnectionData : currentReconnectionData;

        if (hasCurrentSample)
        {
            lt_di_gather_temporal_add_current_sample(
                pixel,
                dstReservoir,
                currReconnectionData,
                currentDomainReservoir,
                currentDomainReconnectionData,
                currConfidence,
                prevConfidence,
                true,
                depthOfFieldProbs.y,
                2,
                sg
            );
        }

        if (doLensVertexCopy && hasPreviousSample)
        {
            lt_di_gather_temporal_add_previous_sample(
                pixel,
                dstReservoir,
                currReconnectionData,
                prevReservoir,
                prevReconnectionData,
                currConfidence,
                prevConfidence,
                true,
                depthOfFieldProbs.y,
                3,
                sg
            );
        }
    }

    return dstReservoir;
}

RTXDI_DIReservoir lt_di_gather_temporal_resampling(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    return lt_di_gather_temporal_resampling_stage(
        pixel,
        currReconnectionData
    );
}
#else
RTXDI_DIReservoir lt_di_gather_temporal_resampling(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    currReconnectionData = ReservoirSplattingReconnectionData_init();
    return RTXDI_EmptyDIReservoir();
}
#endif

// Reference stage 2a wrapper: CollectTemporalSamples::run(pixel).
void lt_di_collect_temporal_samples(
    ivec2 pixel,
    RAB_Surface surface,
    inout RTXDI_RandomSamplerState sg)
{
    lt_di_collect_temporal_samples_stage(pixel);
}

// Reference stage 2c wrapper: ReprojectTemporalSamples::run(pixel).
#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_REPROJECT_STAGE)
void lt_di_reproject_temporal_samples(
    ivec2 pixel,
    RAB_Surface surface,
    inout RTXDI_RandomSamplerState sg)
{
    lt_di_reproject_temporal_samples_stage(pixel);
}
#endif

// Reference stage 2d half 1 wrapper: SortReprojectedReservoirs::computeCellOffsets(pixel).
#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE)
void computeCellOffsets(
    ivec2 pixel)
{
    computeCellOffsetsStage(pixel);
}

// Reference stage 2d half 2 wrapper: SortReprojectedReservoirs::sortCellData(index).
void sortCellData(
    uint index)
{
    sortCellDataStage(index);
}
#endif

// Reference stage 2e wrapper: ScatterTemporalResampling::run(pixel).
#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_STAGE)
RTXDI_DIReservoir lt_di_scatter_temporal_resampling(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    return lt_di_scatter_temporal_resampling_stage(
        pixel,
        currReconnectionData
    );
}
#endif

// Reference stage 2e backup wrapper: ScatterBackupTemporalResampling::run(pixel).
#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_BACKUP_STAGE)
RTXDI_DIReservoir lt_di_scatter_backup_temporal_resampling(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    return lt_di_scatter_backup_temporal_resampling_stage(
        pixel,
        currReconnectionData
    );
}
#endif

// Reference stage 2f wrapper: MultiReprojectTemporalSamples::run(pixel).
#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_REPROJECT_STAGE)
void lt_di_multi_reproject_temporal_samples(
    ivec2 pixel,
    RAB_Surface surface,
    inout RTXDI_RandomSamplerState sg)
{
    lt_di_multi_reproject_temporal_samples_stage(pixel);
}
#endif

// Reference stage 2g half 1 wrapper: MultiSortReprojectedReservoirs::computeCellOffsets(pixel).
#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_STAGE)
void multiComputeCellOffsets(
    ivec2 pixel)
{
    multiComputeCellOffsetsStage(pixel);
}

// Reference stage 2g half 2 wrapper: MultiSortReprojectedReservoirs::sortCellData(index).
void multiSortCellData(
    uint index)
{
    multiSortCellDataStage(index);
}
#endif

// Reference stage 2h wrapper: MultiScatterTemporalResampling::run(pixel).
#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SCATTER_STAGE)
RTXDI_DIReservoir lt_di_multi_scatter_temporal_resampling(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    return lt_di_multi_scatter_temporal_resampling_stage(
        pixel,
        currReconnectionData
    );
}
#endif
#endif
