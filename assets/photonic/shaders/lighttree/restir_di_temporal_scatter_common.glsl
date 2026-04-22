#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_SCATTER_COMMON_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_SCATTER_COMMON_GLSL

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS) || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE)

void lt_temporal_scatter_emit_empty_stage_output(out RTXDI_DIReservoir reservoir)
{
    reservoir = RTXDI_EmptyDIReservoir();
}

RTXDI_DIReservoir lt_area_temporal_spatial_passthrough(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng)
{
    return currentReservoir;
}

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_REPROJECT_STAGE) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY)
void lt_temporal_scatter_append_contributor(ivec2 targetPixel, ivec2 sourceReservoirPos, float supportWeight)
{
    if (!lt_is_viewport_uv_in_bounds(targetPixel) || supportWeight <= 0.0f) {
        return;
    }

    ivec2 targetReservoirPos = RTXDI_PixelPosToReservoirPos(targetPixel, ph_restir_active_checkerboard_field);
    if (!lt_is_active_reservoir_lane(targetReservoirPos)) {
        return;
    }

    uint cellLinearIndex = lt_temporal_scatter_linear_index(targetReservoirPos);
    uint localCellIndex  = lt_reproject_temporal_samples_cell_counter_atomic_add(cellLinearIndex, 1u);
    uint appendIndex     = lt_reproject_temporal_samples_global_counter_atomic_add(LT_TEMPORAL_SCATTER_COUNTER_INDEX_DATA_COUNT, 1u);
    lt_reproject_temporal_samples_store_reservoir_index(appendIndex, uvec2(cellLinearIndex, localCellIndex));
    lt_reproject_temporal_samples_store_scattered_reservoir(appendIndex, uvec2(sourceReservoirPos));
}

#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_REPROJECT_STAGE) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY)
void lt_multi_temporal_scatter_append_contributor(
    uint partitionIndex,
    ivec2 targetPixel,
    ivec2 sourceReservoirPos)
{
    if (!lt_is_viewport_uv_in_bounds(targetPixel)) {
        return;
    }

    ivec2 targetReservoirPos = RTXDI_PixelPosToReservoirPos(targetPixel, ph_restir_active_checkerboard_field);
    if (!lt_is_active_reservoir_lane(targetReservoirPos)) {
        return;
    }

    uint cellLinearIndex = lt_temporal_scatter_linear_index(targetReservoirPos);
    uint localCellIndex = lt_multi_reproject_temporal_samples_cell_counter_atomic_add(partitionIndex, cellLinearIndex, 1u);
    uint appendIndex = lt_multi_reproject_temporal_samples_global_counter_atomic_add(
        partitionIndex,
        LT_MULTI_TEMPORAL_COUNTER_INDEX_DATA_COUNT,
        1u
    );
    lt_multi_reproject_temporal_samples_store_reservoir_index(
        partitionIndex,
        appendIndex,
        uvec2(cellLinearIndex, localCellIndex)
    );
    lt_multi_reproject_temporal_samples_store_scattered_reservoir(
        partitionIndex,
        appendIndex,
        uvec2(sourceReservoirPos)
    );
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
void SortReprojectedReservoirs_computeCellOffsets(ivec2 pixel)
{
    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return;
    }

    uint cellIndex = uint(pixel.y * viewWidth + pixel.x);
    uint cellCounter = lt_reproject_temporal_samples_cell_counter_value(cellIndex);
    if (cellCounter == 0u) {
        return;
    }
    uint offset = lt_reproject_temporal_samples_global_counter_atomic_add(LT_TEMPORAL_SCATTER_COUNTER_INDEX_PREFIX_SUM, cellCounter);
    lt_scatter_temporal_resampling_store_cell_offset(cellIndex, offset);
}

void SortReprojectedReservoirs_sortCellData(uint scatterIndex)
{
    if (scatterIndex >= lt_reproject_temporal_samples_global_counter_value(LT_TEMPORAL_SCATTER_COUNTER_INDEX_DATA_COUNT)) {
        return;
    }

    uvec2 reservoirIndex = lt_reproject_temporal_samples_load_reservoir_index(scatterIndex);
    uint targetCell      = reservoirIndex.x;
    uint localCellIndex  = reservoirIndex.y;
    uint sortedIndex     = lt_scatter_temporal_resampling_cell_offset_value(targetCell) + localCellIndex;
    lt_scatter_temporal_resampling_store_sorted_reservoir(sortedIndex, lt_reproject_temporal_samples_load_scattered_reservoir(scatterIndex));
}

#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_STAGE) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
void MultiSortReprojectedReservoirs_computeCellOffsets(ivec2 pixel)
{
    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return;
    }

    uint cellIndex = uint(pixel.y * viewWidth + pixel.x);
    for (uint partitionIndex = 0u; partitionIndex < lt_multi_temporal_partition_count(); ++partitionIndex) {
        uint cellCounter = lt_multi_reproject_temporal_samples_cell_counter_value(partitionIndex, cellIndex);
        if (cellCounter == 0u) {
            continue;
        }
        uint offset = lt_multi_reproject_temporal_samples_global_counter_atomic_add(
            partitionIndex,
            LT_TEMPORAL_SCATTER_COUNTER_INDEX_PREFIX_SUM,
            cellCounter
        );
        lt_multi_scatter_temporal_resampling_store_cell_offset(partitionIndex, cellIndex, offset);
    }
}

void MultiSortReprojectedReservoirs_sortCellData(uint scatterIndex)
{
    for (uint partitionIndex = 0u; partitionIndex < lt_multi_temporal_partition_count(); ++partitionIndex) {
        uint partitionCount = lt_multi_reproject_temporal_samples_global_counter_value(
            partitionIndex,
            LT_TEMPORAL_SCATTER_COUNTER_INDEX_DATA_COUNT
        );
        if (scatterIndex >= partitionCount) {
            continue;
        }

        uvec2 reservoirIndex = lt_multi_reproject_temporal_samples_load_reservoir_index(partitionIndex, scatterIndex);
        uint cellLinearIndex = reservoirIndex.x;
        uint localCellIndex = reservoirIndex.y;
        uint sortedIndex = lt_multi_scatter_temporal_resampling_cell_offset_value(partitionIndex, cellLinearIndex) + localCellIndex;
        lt_multi_scatter_temporal_resampling_store_sorted_reservoir(
            partitionIndex,
            sortedIndex,
            lt_multi_reproject_temporal_samples_load_scattered_reservoir(partitionIndex, scatterIndex)
        );
    }
}
#endif

void splat_resample_temporal_pairwise_mis(
    inout RTXDI_DIReservoir state,
    RTXDI_DIReservoir canonicalReservoir,
    RAB_Surface canonicalSurface,
    ivec2 canonicalPixel,
    RTXDI_DIReservoir candidateReservoir,
    RAB_Surface candidateSurface,
    ivec2 candidatePixel,
    float pHatPrev,
    float confidenceWeightSum,
    float candidateNormalization,
    float splatJacobian,
    float supportWeight,
    inout RTXDI_RandomSamplerState rng)
{
    float pHatCurrent = ph_luminance(PathReservoir_getIntegrand(candidateReservoir));
    float pHatCanonical = ph_luminance(PathReservoir_getIntegrand(canonicalReservoir));
    float c_i = PathReservoir_getConfidence(candidateReservoir);
    float c_star = max(PathReservoir_getConfidence(canonicalReservoir), 1.0f);

    if (pHatCurrent <= 0.0f || pHatCanonical <= 0.0f || c_i <= 0.0f || PathReservoir_getTotalWeight(candidateReservoir) <= 0.0f || supportWeight <= 0.0f) {
        return;
    }

    float weightedCandidateConfidence = c_i * supportWeight;
    float weightedCandidateNormalization = candidateNormalization * pHatPrev;

    float m0Denominator = c_star * pHatCurrent + weightedCandidateNormalization;
    float m0 = (m0Denominator > 0.0f) ? (weightedCandidateNormalization / m0Denominator) : 0.0f;

    RAB_LightSample canonicalLightAtPrev = lt_decode_reservoir_sample_for_frame(
        canonicalReservoir, candidateSurface, false, true);
    float pHatCanonicalAtPrev = (RAB_IsSurfaceValid(candidateSurface) && canonicalLightAtPrev.index >= 0)
        ? lt_surface_target_pdf(candidateSurface, canonicalLightAtPrev)
        : 0.0;

    float canonicalReverseContribution = weightedCandidateConfidence * pHatCanonicalAtPrev * splatJacobian;
    float m1Denominator = c_star * pHatCanonical + canonicalReverseContribution;
    float m1 = (m1Denominator > 0.0f) ? ((c_star * pHatCanonical) / m1Denominator) : 0.0f;

    float sampleWeight = m0 * pHatCurrent * PathReservoir_getTotalWeight(candidateReservoir) * splatJacobian;

    PathReservoir_setConfidence(state, PathReservoir_getConfidence(state) + weightedCandidateConfidence);
    PathReservoir_setTotalWeight(state, PathReservoir_getTotalWeight(state) + sampleWeight);
    state.canonicalWeight += m1;

    bool selectSample = (sampleWeight > 0.0 && PathReservoir_getTotalWeight(state) > 0.0)
        ? (lt_next_random(rng) * PathReservoir_getTotalWeight(state) < sampleWeight)
        : false;

    if (selectSample) {
        PathReservoir_setIntegrand(state, PathReservoir_getIntegrand(candidateReservoir));
        state.targetPdf = candidateReservoir.targetPdf;
        state.lightData = candidateReservoir.lightData;
        state.uvData = candidateReservoir.uvData;
        state.pixelSampleUV = candidateReservoir.pixelSampleUV;
        state.pathSample = candidateReservoir.pathSample;
        state.lensSampleUV = candidateReservoir.lensSampleUV;
        state.packedVisibility = candidateReservoir.packedVisibility;
        state.age = candidateReservoir.age;
        state.spatialDistance = candidateReservoir.spatialDistance;
    }
}

float lt_temporal_proposal_pdf(RTXDI_DIReservoir reservoir, ScatterReconnectionData reconnection) {
    return max(reconnection.lightPdf, 0.0f);
}

float lt_temporal_proposal_weight(RTXDI_DIReservoir reservoir, ScatterReconnectionData reconnection) {
    float proposalPdf = lt_temporal_proposal_pdf(reservoir, reconnection);
    if (proposalPdf <= 0.0f) {
        return 0.0f;
    }

    return 1.0f / proposalPdf;
}

float lt_temporal_candidate_confidence_weight(
    RTXDI_DIReservoir reservoir,
    ScatterReconnectionData reconnection,
    float supportWeight)
{
    float proposalWeight = lt_temporal_proposal_weight(reservoir, reconnection);
    float clampedProposalWeight = clamp(proposalWeight, 0.25f, 4.0f);
    return PathReservoir_getConfidence(reservoir)
        * max(supportWeight, 0.0f)
        * clampedProposalWeight;
}

float lt_temporal_scatter_debug_stage_marker()
{
    return 0.0f;
}

float lt_temporal_proposal_match_weight(
    ScatterReconnectionData canonicalReconnection,
    ScatterReconnectionData candidateReconnection)
{
    float weight = 1.0f;
    float lightPdfA = max(canonicalReconnection.lightPdf, 0.0f);
    float lightPdfB = max(candidateReconnection.lightPdf, 0.0f);
    if (lightPdfA > 0.0f && lightPdfB > 0.0f) {
        float pdfRatio = max(lightPdfA, lightPdfB) / max(min(lightPdfA, lightPdfB), 1e-6f);
        weight *= clamp(1.0f / sqrt(pdfRatio), 0.35f, 1.0f);
    }

    return clamp(weight, 0.0f, 1.0f);
}

float lt_temporal_scatter_support_denominator(
    ivec2 basePixel,
    vec2 frac,
    ScatterReconnectionData sourceReconnection,
    RAB_Surface sourcePrevSurface,
    RTXDI_DIReservoir sourcePrevReservoir,
    vec3 prevCameraPos,
    vec3 prevCameraForward)
{
#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
    return 0.0f;
#else
    float denominator = 0.0f;
    vec3 currCameraForward = normalize(mat3(gbufferModelView) * vec3(0.0f, 0.0f, -1.0f));
    float sourceProposalWeight = lt_temporal_proposal_weight(sourcePrevReservoir, sourceReconnection);

    for (int dy = 0; dy <= 1; ++dy) {
        for (int dx = 0; dx <= 1; ++dx) {
            ivec2 neighborPixel = basePixel + ivec2(dx, dy);
            if (!lt_is_viewport_uv_in_bounds(neighborPixel)) {
                continue;
            }

            float bilinearWeight = lt_scatter_bilinear_weight(frac, dx, dy);
            if (bilinearWeight <= 1e-5f) {
                continue;
            }

            RAB_Surface neighborSurface = RAB_GetGBufferSurface(neighborPixel, false);
            if (!RAB_IsSurfaceValid(neighborSurface)) {
                continue;
            }

            if (!lt_area_is_surface_neighbor_valid(neighborSurface, sourcePrevSurface)) {
                continue;
            }

            RTXDI_DIReservoir shiftedNeighbor = lt_translate_reservoir_between_frames(sourcePrevReservoir, true, false);
            if (!RTXDI_IsValidDIReservoir(shiftedNeighbor)) {
                continue;
            }

            lt_area_finalize_candidate(shiftedNeighbor, neighborPixel, shiftedNeighbor.pathSample);
            RAB_LightSample shiftedLight = lt_decode_reservoir_sample_for_frame(
                shiftedNeighbor, neighborSurface, false, false);
            float pHatNeighbor = lt_surface_target_pdf(neighborSurface, shiftedLight);
            if (pHatNeighbor <= 0.0f) {
                continue;
            }

            float jPrev = scatter_resolve_stored_subpixel_jacobian(
                sourceReconnection, sourcePrevSurface, prevCameraPos, prevCameraForward);
            float jCurr = scatter_compute_subpixel_jacobian(
                neighborSurface.worldPos, neighborSurface.geoNormal, world_camera_position, currCameraForward);
            float supportJacobian = scatter_compute_scatter_jacobian(
                jPrev,
                jCurr,
                scatter_resolve_stored_secondary_jacobian(sourceReconnection),
                1.0f
            );
            float invSupportJ = (supportJacobian > 1e-8f) ? (1.0f / supportJacobian) : 0.0f;

            denominator += bilinearWeight * PathReservoir_getConfidence(sourcePrevReservoir) * sourceProposalWeight * invSupportJ;
        }
    }

    return denominator;
#endif
}

#endif

#endif
