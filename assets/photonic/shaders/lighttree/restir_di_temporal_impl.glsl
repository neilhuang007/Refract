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

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)
#if 0
vec2 lt_di_temporal_reprojection_motion_vector(ivec2 pixel)
{
    vec4 motionSample = texelFetch(radiosity_motion, pixel, 0);
    vec2 motionVector = motionSample.xy;
    motionVector = (length(motionVector) < 1e-6f) ? vec2(0.0f) : motionVector;
    return motionVector;
}

vec2 lt_di_temporal_reprojection_previous_pixel(ivec2 pixel)
{
    return vec2(pixel) + lt_di_temporal_reprojection_motion_vector(pixel) * vec2(viewWidth, viewHeight);
}

ivec2 lt_di_temporal_reprojection_previous_top_left(vec2 previousPixel)
{
    return ivec2(floor(previousPixel));
}

vec2 lt_di_temporal_reprojection_fractional_coord(vec2 previousPixel, ivec2 previousTopLeft)
{
    return clamp(previousPixel - vec2(previousTopLeft), vec2(0.0f), vec2(1.0f));
}

bool lt_di_temporal_reprojection_is_valid_neighbor_subpixel(vec2 relativeSubPixel)
{
    return all(greaterThanEqual(relativeSubPixel, vec2(0.0f)))
        && all(lessThan(relativeSubPixel, vec2(1.0f)));
}

float lt_di_temporal_reprojection_neighbor_weight(ivec2 offset, vec2 fractionalCoord)
{
    float weightX = mix(1.0f - float(offset.x), float(offset.x), fractionalCoord.x);
    float weightY = mix(1.0f - float(offset.y), float(offset.y), fractionalCoord.y);
    return weightX * weightY;
}

void lt_di_collect_temporal_write_outputs(
    RTXDI_DIReservoir reservoir,
    ReservoirSplattingReconnectionData reconnectionData,
    vec2 floatingCoord)
{
    rt_output_reservoir(intermediate_reservoir_frag_out, reservoir);
    rt_output_reconnection_data(
        intermediate_reconnection0_frag_out,
        intermediate_reconnection1_frag_out,
        reservoir,
        reconnectionData,
        true
    );
    floating_coords_frag_out = vec4(floatingCoord, 0.0f, 0.0f);
}

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_COLLECT_STAGE)
void lt_di_collect_temporal_samples_stage(
    ivec2 currPixel)
{
    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    ReservoirSplattingReconnectionData dstReconnectionData = ReservoirSplattingReconnectionData_init();
    vec2 dstFloatingCoord = vec2(-1.0f);

    vec2 previousPixel = lt_di_temporal_reprojection_previous_pixel(currPixel);
    if (!lt_is_viewport_pixel_in_bounds(previousPixel))
    {
        lt_di_collect_temporal_write_outputs(dstReservoir, dstReconnectionData, dstFloatingCoord);
        return;
    }

    RTXDI_RandomSamplerState sg = lt_init_random_sampler(uvec2(currPixel), uint(frameCounter), 2u);
    ivec2 previousPixelTopLeft = lt_di_temporal_reprojection_previous_top_left(previousPixel);
    vec2 fractionalCoord = lt_di_temporal_reprojection_fractional_coord(previousPixel, previousPixelTopLeft);
    dstFloatingCoord = previousPixel;

    float totalConfidence = 0.0f;
    for (int x = 0; x < 2; ++x)
    {
        for (int y = 0; y < 2; ++y)
        {
            ivec2 offset = ivec2(x, y);
            ivec2 neighborPixel = previousPixelTopLeft + offset;
            if (!lt_is_viewport_uv_in_bounds(neighborPixel))
            {
                continue;
            }

            RTXDI_DIReservoir neighborReservoir = RTXDI_LoadPreviousDIReservoir(
                lt_build_restir_di_parameters().reservoirBufferParams,
                uvec2(neighborPixel)
            );
            ReservoirSplattingReconnectionData neighborReconnectionData = scatter_load_prev_reconnection(neighborPixel);
            vec2 relativeSubPixel = vec2(offset) + neighborReconnectionData.subPixel - fractionalCoord;
            float bilinearWeight = lt_di_temporal_reprojection_neighbor_weight(offset, fractionalCoord);
            totalConfidence += bilinearWeight * lt_scatter_reservoir_confidence(neighborReservoir, neighborReconnectionData);

            if (!lt_di_temporal_reprojection_is_valid_neighbor_subpixel(relativeSubPixel))
            {
                continue;
            }

            neighborReservoir.uv = rtxdi_pack_reservoir_uv(relativeSubPixel);
            bool selected = RTXDI_StreamSample(
                dstReservoir,
                neighborReservoir.lightData,
                relativeSubPixel,
                lt_next_random(sg),
                1.0f,
                1.0f
            );
            if (selected)
            {
                dstReconnectionData = neighborReconnectionData;
                dstReconnectionData.subPixel = relativeSubPixel;
            }
        }
    }

    dstReservoir.confidence = totalConfidence;
    if (isnan(dstReservoir.weightSum))
    {
        dstReservoir = RTXDI_EmptyDIReservoir();
        dstReconnectionData = ReservoirSplattingReconnectionData_init();
    }

    lt_di_collect_temporal_write_outputs(dstReservoir, dstReconnectionData, dstFloatingCoord);
}

void lt_di_collect_temporal_samples(
    ivec2 pixel,
    RAB_Surface surface,
    inout RTXDI_RandomSamplerState sg)
{
    lt_di_collect_temporal_samples_stage(pixel);
}
#else
void lt_di_collect_temporal_samples(
    ivec2 pixel,
    RAB_Surface surface,
    inout RTXDI_RandomSamplerState sg)
{
}
#endif

bool lt_di_gather_temporal_load_current_sample(
    ivec2 pixel,
    out RTXDI_DIReservoir currReservoir,
    out ReservoirSplattingReconnectionData currReconnectionData,
    out float currConfidence)
{
    currReservoir = lt_current_reservoir_at_pixel(pixel);
    currReconnectionData = lt_load_current_reconnection(pixel);
    currConfidence = lt_scatter_reservoir_confidence(currReservoir, currReconnectionData);
    return RTXDI_IsValidDIReservoir(currReservoir) && any(greaterThan(currReservoir.radiance, vec3(0.0f)));
}

bool lt_di_gather_temporal_load_previous_sample(
    ivec2 pixel,
    out RTXDI_DIReservoir prevReservoir,
    out ReservoirSplattingReconnectionData prevReconnectionData,
    out float prevConfidence)
{
    prevReservoir = scatter_load_gather_intermediate_reservoir(pixel);
    prevReconnectionData = scatter_load_gather_intermediate_reconnection(pixel);
    prevConfidence = lt_scatter_reservoir_confidence(prevReservoir, prevReconnectionData);
    return RTXDI_IsValidDIReservoir(prevReservoir) && any(greaterThan(prevReservoir.radiance, vec3(0.0f)));
}

float lt_di_gather_temporal_current_sample_mis(
    RTXDI_DIReservoir currReservoir,
    float currConfidence,
    float prevConfidence)
{
    float m1 = lt_scatter_radiance_phat(currReservoir.radiance) * currConfidence;
    float m2 = lt_scatter_radiance_phat(currReservoir.radiance) * prevConfidence;
    return ((m1 + m2) > 0.0f) ? (m1 / (m1 + m2)) : 0.0f;
}

float lt_di_gather_temporal_previous_sample_mis(
    RTXDI_DIReservoir prevReservoir,
    float currConfidence,
    float prevConfidence)
{
    float m1 = lt_scatter_radiance_phat(prevReservoir.radiance) * currConfidence;
    float m2 = lt_scatter_radiance_phat(prevReservoir.radiance) * prevConfidence;
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
    if (any(greaterThan(currReservoir.radiance, vec3(0.0f))))
    {
        currPHat = currReservoir.radiance;
        LtTemporalGatherShiftedPathData shiftedCurr = scatter_load_gather_shifted_path_data(pixel, shiftedPathIndex);
        float shiftedJacobian = lt_di_gather_temporal_shifted_jacobian(shiftedCurr, currReconnectionData, primaryHitReconnection);
        currSampleMIS = lt_di_gather_temporal_reference_mis(
            currReservoir.radiance,
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
    if (any(greaterThan(prevReservoir.radiance, vec3(0.0f))))
    {
        LtTemporalGatherShiftedPathData shiftedPrev = scatter_load_gather_shifted_path_data(pixel, shiftedPathIndex);
        shiftedJacobian = lt_di_gather_temporal_shifted_jacobian(shiftedPrev, prevReconnectionData, primaryHitReconnection);
        float shiftedWeight = lt_di_gather_temporal_confidence_weight(currConfidence);
        float referenceMIS = lt_di_gather_temporal_reference_mis(
            shiftedPrev.radiance,
            shiftedWeight,
            prevReservoir.radiance,
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
        lt_scatter_compute_ucw(prevReservoir, prevPHat),
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

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_GATHER_STAGE)
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
    const bool hasDepthOfField = lt_spatial_camera_aperture_radius() > 0.0f;
    vec2 depthOfFieldProbs = hasDepthOfField
        ? lt_spatial_resolve_dof_probabilities(centerSurface)
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
void lt_di_reproject_temporal_samples(
    ivec2 pixel,
    RAB_Surface surface,
    inout RTXDI_RandomSamplerState sg)
{
    lt_di_reproject_temporal_samples_stage(pixel);
}

// Reference stage 2d half 1 wrapper: SortReprojectedReservoirs::computeCellOffsets(pixel).
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

// Reference stage 2e wrapper: ScatterTemporalResampling::run(pixel).
RTXDI_DIReservoir lt_di_scatter_temporal_resampling(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    return lt_di_scatter_temporal_resampling_stage(
        pixel,
        currReconnectionData
    );
}

// Reference stage 2e backup wrapper: ScatterBackupTemporalResampling::run(pixel).
RTXDI_DIReservoir lt_di_scatter_backup_temporal_resampling(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    return lt_di_scatter_backup_temporal_resampling_stage(
        pixel,
        currReconnectionData
    );
}

// Reference stage 2f wrapper: MultiReprojectTemporalSamples::run(pixel).
void lt_di_multi_reproject_temporal_samples(
    ivec2 pixel,
    RAB_Surface surface,
    inout RTXDI_RandomSamplerState sg)
{
    lt_di_multi_reproject_temporal_samples_stage(pixel);
}

// Reference stage 2g half 1 wrapper: MultiSortReprojectedReservoirs::computeCellOffsets(pixel).
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

// Reference stage 2h wrapper: MultiScatterTemporalResampling::run(pixel).
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
