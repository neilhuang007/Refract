#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_SCATTER_PIPELINE_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_SCATTER_PIPELINE_GLSL

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
    uint partitionedCellIndex = lt_temporal_partitioned_cell_index(partitionIndex, cellLinearIndex);
    uint counterBaseIndex = lt_temporal_partitioned_counter_index(partitionIndex, LT_MULTI_TEMPORAL_COUNTER_INDEX_DATA_COUNT);
    uint localCellIndex = lt_multi_reproject_temporal_samples_cell_counter_atomic_add(partitionIndex, partitionedCellIndex, 1u);
    uint appendIndex = lt_multi_reproject_temporal_samples_global_counter_atomic_add(partitionIndex, counterBaseIndex, 1u);
    uint scatteredBufferIndex = lt_temporal_partitioned_contributor_index(partitionIndex, appendIndex);
    lt_multi_reproject_temporal_samples_store_reservoir_index(partitionIndex, scatteredBufferIndex, uvec2(cellLinearIndex, localCellIndex));
    lt_multi_reproject_temporal_samples_store_scattered_reservoir(partitionIndex, scatteredBufferIndex, uvec2(sourceReservoirPos));
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
void lt_SortReprojectedReservoirs_compute_cell_offsets(ivec2 pixel)
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

void lt_SortReprojectedReservoirs_sort_cell_data(uint scatterIndex)
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
void lt_MultiSortReprojectedReservoirs_compute_cell_offsets(ivec2 pixel)
{
    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return;
    }

    uint cellIndex = uint(pixel.y * viewWidth + pixel.x);
    for (uint partitionIndex = 0u; partitionIndex < lt_multi_temporal_partition_count(); ++partitionIndex) {
        uint partitionedCellIndex = lt_temporal_partitioned_cell_index(partitionIndex, cellIndex);
        uint cellCounter = lt_multi_reproject_temporal_samples_cell_counter_value(partitionIndex, partitionedCellIndex);
        if (cellCounter == 0u) {
            continue;
        }
        uint counterIndex = lt_temporal_partitioned_counter_index(partitionIndex, LT_TEMPORAL_SCATTER_COUNTER_INDEX_PREFIX_SUM);
        uint offset = lt_multi_reproject_temporal_samples_global_counter_atomic_add(partitionIndex, counterIndex, cellCounter);
        lt_multi_scatter_temporal_resampling_store_cell_offset(partitionIndex, partitionedCellIndex, offset);
    }
}

void lt_MultiSortReprojectedReservoirs_sort_cell_data(uint scatterIndex)
{
    for (uint partitionIndex = 0u; partitionIndex < lt_multi_temporal_partition_count(); ++partitionIndex) {
        uint counterIndex = lt_temporal_partitioned_counter_index(partitionIndex, LT_TEMPORAL_SCATTER_COUNTER_INDEX_DATA_COUNT);
        uint partitionCount = lt_multi_reproject_temporal_samples_global_counter_value(partitionIndex, counterIndex);
        if (scatterIndex >= partitionCount) {
            continue;
        }

        uint scatteredBufferIndex = lt_temporal_partitioned_contributor_index(partitionIndex, scatterIndex);
        uvec2 reservoirIndex = lt_multi_reproject_temporal_samples_load_reservoir_index(partitionIndex, scatteredBufferIndex);
        uint cellLinearIndex = reservoirIndex.x;
        uint localCellIndex = reservoirIndex.y;
        uint partitionedCellIndex = lt_temporal_partitioned_cell_index(partitionIndex, cellLinearIndex);
        uint sortedIndex = lt_multi_scatter_temporal_resampling_cell_offset_value(partitionIndex, partitionedCellIndex) + localCellIndex;
        uint sortedBufferIndex = lt_temporal_partitioned_contributor_index(partitionIndex, sortedIndex);
        lt_multi_scatter_temporal_resampling_store_sorted_reservoir(partitionIndex, sortedBufferIndex, lt_multi_reproject_temporal_samples_load_scattered_reservoir(partitionIndex, scatteredBufferIndex));
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
    float pHatCurrent = candidateReservoir.targetPdf;
    float pHatCanonical = canonicalReservoir.targetPdf;
    float c_i = max(candidateReservoir.M, 0.0f);
    float c_star = max(canonicalReservoir.M, 1.0f);

    if (pHatCurrent <= 0.0f || pHatCanonical <= 0.0f || c_i <= 0.0f || candidateReservoir.weightSum <= 0.0f || supportWeight <= 0.0f) {
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

    float sampleWeight = m0 * pHatCurrent * candidateReservoir.weightSum * splatJacobian;

    state.M += weightedCandidateConfidence;
    state.weightSum += sampleWeight;
    state.canonicalWeight += m1;

    bool selectSample = (sampleWeight > 0.0 && state.weightSum > 0.0)
        ? (lt_next_random(rng) * state.weightSum < sampleWeight)
        : false;

    if (selectSample) {
        state.targetPdf = pHatCurrent;
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
    return max(reservoir.M, 0.0f)
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

            denominator += bilinearWeight * sourcePrevReservoir.M * sourceProposalWeight * invSupportJ;
        }
    }

    return denominator;
#endif
}

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)
#include "/photonics/lighttree/restir_di_temporal.glsl"

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_REPROJECT_STAGE)
float lt_multi_temporal_reproject_partition(
    ScatterReconnectionData prevReconnection,
    uint partitionIndex,
    out vec2 newFractionalPixel,
    out bool hitValid,
    out vec3 rayDirection)
{
    float fractionalTime = lt_multi_temporal_partition_fraction(prevReconnection.time);
    float newTime = lt_multi_temporal_partition_time(fractionalTime, partitionIndex);
    hitValid = prevReconnection.firstHit.viewDepth > 0.0f
        && any(greaterThan(abs(prevReconnection.firstHit.worldPos), vec3(0.0f)));

    if (hitValid) {
        rayDirection = prevReconnection.firstHit.worldPos - world_camera_position;
        newFractionalPixel = scatter_forward_project_to_current_frame(prevReconnection.firstHit.worldPos);
        return newTime;
    }

    if (prevReconnection.lightIsDistant) {
        rayDirection = -prevReconnection.firstWi;
        vec3 farPoint = world_camera_position + rayDirection * 1e5f;
        newFractionalPixel = scatter_forward_project_to_current_frame(farPoint);
        return newTime;
    }

    rayDirection = vec3(0.0f);
        newFractionalPixel = vec2(-1.0f);
        return newTime;
    }

void lt_di_multi_reproject_temporal_samples_stage(
    ivec2 pixel)
{
    if (ph_scatter_temporal_enabled <= 0.5f || ph_debug_enable_direct_temporal_reuse < 0.5f) {
        return;
    }

    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return;
    }

    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel)
    );
    if (!RTXDI_IsValidDIReservoir(prevReservoir)) {
        return;
    }

    ScatterReconnectionData prevReconnection = scatter_load_prev_reconnection(pixel);
    RAB_Surface prevSurface = lt_load_previous_surface(pixel);
    for (uint partitionIndex = 0u; partitionIndex < lt_multi_temporal_partition_count(); ++partitionIndex) {
        vec2 newFractionalPixel;
        bool hitValid;
        vec3 rayDirection;
        float newTime = lt_multi_temporal_reproject_partition(
            prevReconnection,
            partitionIndex,
            newFractionalPixel,
            hitValid,
            rayDirection
        );
        if (newFractionalPixel.x < 0.0f || newFractionalPixel.y < 0.0f) {
            continue;
        }

        ivec2 newPixel = ivec2(floor(newFractionalPixel));
        if (!lt_is_viewport_uv_in_bounds(newPixel)) {
            continue;
        }

        vec3 normalizedRayDirection = normalize(rayDirection);
        vec3 cameraForward = normalize(mat3(gbufferModelView) * vec3(0.0f, 0.0f, -1.0f));
        float cameraFacing = dot(normalizedRayDirection, cameraForward);
        if (cameraFacing <= 0.001f) {
            continue;
        }

        RAB_Surface currentSurface = RAB_GetGBufferSurface(newPixel, false);
        if (!RAB_IsSurfaceValid(currentSurface)) {
            continue;
        }

        ScatterReconnectionData partitionedReconnection = prevReconnection;
        partitionedReconnection.time = newTime;
        if (hitValid) {
            if (!lt_area_is_temporal_neighbor_valid(currentSurface, prevSurface, partitionedReconnection, newPixel)) {
                continue;
            }
        } else if (!partitionedReconnection.lightIsDistant) {
            continue;
        }

        lt_multi_temporal_scatter_append_contributor(partitionIndex, newPixel, pixel);
    }
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_REPROJECT_STAGE)
void lt_di_reproject_temporal_samples_stage(
    ivec2 pixel)
{
    if (ph_scatter_temporal_enabled <= 0.5f || ph_debug_enable_direct_temporal_reuse < 0.5f) {
        return;
    }

    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return;
    }

    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel)
    );
    if (!RTXDI_IsValidDIReservoir(prevReservoir)) {
        return;
    }

    ScatterReconnectionData prevReconnection = scatter_load_prev_reconnection(pixel);

    bool hasPrimaryHit = prevReconnection.firstHit.viewDepth > 0.0f;
    vec2 newFractionalPixel = vec2(-1.0f);

    if (hasPrimaryHit) {
        newFractionalPixel = scatter_forward_project_to_current_frame(prevReconnection.firstHit.worldPos);
    } else {
        if (!prevReconnection.lightIsDistant) {
            return;
        }
        vec3 currentRayDirection = normalize(-prevReconnection.firstWi);
        vec4 clipPosition = gbufferProjection * gbufferModelView * vec4(world_camera_position + currentRayDirection, 1.0f);
        if (clipPosition.w <= 1e-5f) {
            return;
        }
        vec3 ndc = clipPosition.xyz / clipPosition.w;
        newFractionalPixel = (ndc.xy * vec2(0.5f, -0.5f) + vec2(0.5f)) * vec2(viewWidth, viewHeight);
    }

    if (newFractionalPixel.x < 0.0f || newFractionalPixel.y < 0.0f) {
        return;
    }

    ivec2 newPixel = ivec2(floor(newFractionalPixel));
    if (!lt_is_viewport_uv_in_bounds(newPixel)) {
        return;
    }

    if (hasPrimaryHit) {
        vec3 rayOrigin = world_camera_position;
        vec3 rayDirection = normalize(prevReconnection.firstHit.worldPos - rayOrigin);
        float traceDistance = length(prevReconnection.firstHit.worldPos - rayOrigin);
        if (traceDistance <= 1e-5f) {
            return;
        }

        ray.origin = rayOrigin;
        ray.direction = rayDirection;
        ray_target = ivec3(floor(prevReconnection.firstHit.worldPos));
        ray_ignore_block_id = -1;
        ray_stop_on_target = true;
        ray_min_trace_distance = 0.001f * traceDistance;
        ray_max_trace_distance = max(ray_min_trace_distance, 0.999f * traceDistance);
        trace_ray(ray, true);
        ray_target = ivec3(-9999);
        ray_ignore_block_id = -1;
        ray_stop_on_target = false;
        ray_min_trace_distance = 0.0f;
        ray_max_trace_distance = -1.0f;
        if (!lt_visibility_trace_is_unoccluded()) {
            return;
        }
    }

    lt_temporal_scatter_append_contributor(newPixel, pixel, 1.0f);
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY)
void computeCellOffsetsStage(
    ivec2 pixel)
{
    if (ph_scatter_temporal_enabled <= 0.5f) {
        return;
    }

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
    return;
#else
    lt_SortReprojectedReservoirs_compute_cell_offsets(pixel);
#endif
}
#else
void computeCellOffsetsStage(
    ivec2 pixel)
{
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
void sortCellDataStage(
    uint index)
{
    if (ph_scatter_temporal_enabled <= 0.5f) {
        return;
    }

    lt_SortReprojectedReservoirs_sort_cell_data(index);
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_STAGE)
#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
RTXDI_DIReservoir lt_di_scatter_temporal_resampling_stage(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    currReconnectionData = ReservoirSplattingReconnectionData_init();
    return RTXDI_EmptyDIReservoir();
}
#else
RTXDI_DIReservoir lt_di_scatter_temporal_resampling_stage(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    currReconnectionData = ReservoirSplattingReconnectionData_init();

    if (ph_scatter_temporal_enabled <= 0.5f || ph_debug_enable_direct_temporal_reuse < 0.5f) {
        return RTXDI_EmptyDIReservoir();
    }

    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);
    if (!lt_is_viewport_uv_in_bounds(pixel) || !RAB_IsSurfaceValid(surface)) {
        return RTXDI_EmptyDIReservoir();
    }

    RTXDI_RandomSamplerState sg = lt_init_random_sampler(
        uvec2(pixel),
        uint(frameCounter),
        5u
    );

    uint reservoirIdx = uint(pixel.y * viewWidth + pixel.x);
    RTXDI_DIReservoir currReservoir = lt_ScatterTemporalResampling_load_current_reservoir(pixel);
    LtScatterCurrentSample currSample = lt_ScatterTemporalResampling_load_current_sample(
        reservoirIdx,
        pixel,
        surface,
        currReservoir
    );

    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    ReservoirSplattingReconnectionData dstReconnectionData = ReservoirSplattingReconnectionData_init();
    ReservoirSplattingReconnectionData currReconnectionDataLocal = currSample.reconnectionData;
    vec3  currIntegrand            = currSample.isValid ? scatter_reconnection_integrand(currReconnectionDataLocal) : vec3(0.0f);
    float currReservoirConfidence  = currSample.confidence;
    float currUCW                  = currSample.isValid ? lt_scatter_compute_ucw(currReservoir, currIntegrand) : 0.0f;

    float currSampleMIS = ScatterTemporalResampling_compute_curr_sample_mis(
        currSample,
        pixel,
        surface
    );
    bool currSelected = lt_scatter_add_sample_from_reservoir(
        dstReservoir,
        dstReservoir.M,
        currSampleMIS,
        currIntegrand,
        1.0f,
        currUCW,
        currReservoirConfidence,
        currReservoir,
        sg
    );
    dstReconnectionData = currSelected ? currReconnectionDataLocal : dstReconnectionData;

    float newConfidence = dstReservoir.M;

    uint numReservoirs = lt_reproject_temporal_samples_cell_counter_value(reservoirIdx);
    uint cellOffset = lt_scatter_temporal_resampling_cell_offset_value(reservoirIdx);
    for (uint i = 0u; i < numReservoirs; ++i) {
        ivec2 scatteredPixel = ivec2(lt_scatter_temporal_resampling_load_sorted_reservoir(cellOffset + i));
        ScatterTemporalResampling_process_contributor(
            dstReservoir,
            dstReconnectionData,
            newConfidence,
            scatteredPixel,
            pixel,
            currReservoir,
            currReconnectionDataLocal,
            currReservoirConfidence,
            sg
        );
    }

    dstReservoir.M = ScatterTemporalResampling_motion_vector_confidence(pixel, newConfidence);
    currReconnectionData = dstReconnectionData;
    return dstReservoir;
}
#endif
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SCATTER_STAGE)
bool lt_multi_scatter_process_contributor(
    inout RTXDI_DIReservoir dstReservoir,
    inout ReservoirSplattingReconnectionData dstReconnectionData,
    ivec2 scatteredPixel,
    ivec2 resolvePixel,
    uint partitionIndex,
    RTXDI_DIReservoir currReservoir,
    ScatterReconnectionData currReconnection,
    float currReservoirConfidence,
    inout RTXDI_RandomSamplerState sg)
{
    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(scatteredPixel)
    );
    if (!RTXDI_IsValidDIReservoir(prevReservoir)) {
        return false;
    }

    ScatterReconnectionData prevReconnection = scatter_load_prev_reconnection(scatteredPixel);
    RAB_Surface targetSurface = RAB_GetGBufferSurface(resolvePixel, false);
    LtScatterShiftedPath shiftedPrev;
    RTXDI_DIReservoir shiftedReservoir;
    ScatterReconnectionData shiftedReconnection;
    float shiftedJacobian;
    if (!lt_scatter_update_shifted_reservoir(
            prevReconnection,
            prevReservoir,
            true,
            false,
            targetSurface,
            resolvePixel,
            shiftedPrev,
            shiftedReservoir,
            shiftedReconnection,
            shiftedJacobian)) {
        return false;
    }

    float prevMIS = 0.0f;
    if (any(greaterThan(scatter_reconnection_integrand(prevReconnection), vec3(0.0f)))) {
        float m1 = lt_scatter_radiance_phat(shiftedPrev.radiance)
            * shiftedJacobian
            * currReservoirConfidence;
        float m2 = lt_scatter_radiance_phat(scatter_reconnection_integrand(prevReconnection))
            * lt_scatter_reservoir_confidence(prevReservoir, prevReconnection);
        float denominator = m1 + m2;
        prevMIS = (denominator > 0.0f) ? (m2 / denominator) : 0.0f;
    }

    bool prevSelected = lt_scatter_add_sample_from_reservoir(
        dstReservoir,
        dstReservoir.M,
        prevMIS,
        shiftedPrev.radiance,
        shiftedJacobian * (1.0f / float(lt_multi_temporal_partition_count())),
        lt_scatter_compute_ucw(shiftedReservoir, shiftedPrev.radiance),
        lt_scatter_reservoir_confidence(prevReservoir, prevReconnection),
        shiftedReservoir,
        sg
    );
    if (prevSelected) {
        float timePartitions = 1.0f / float(lt_multi_temporal_partition_count());
        float fractionalTime = clamp(prevReconnection.time, 0.0f, 1.0f);
        shiftedReconnection.time = (fractionalTime + float(partitionIndex)) * timePartitions;
        shiftedReconnection.subPixel = clamp(
            shiftedPrev.fractionalPixel - floor(shiftedPrev.fractionalPixel),
            vec2(0.0f),
            vec2(1.0f)
        );
        dstReconnectionData = shiftedReconnection;
    }
    return prevSelected;
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_STAGE)
void multiComputeCellOffsetsStage(
    ivec2 pixel)
{
#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
    if (ph_scatter_temporal_enabled > 0.5f) {
        lt_MultiSortReprojectedReservoirs_compute_cell_offsets(pixel);
    }
#endif
}

void multiSortCellDataStage(
    uint index)
{
#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
    if (ph_scatter_temporal_enabled > 0.5f) {
        lt_MultiSortReprojectedReservoirs_sort_cell_data(index);
    }
#endif
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_BACKUP_STAGE)
RTXDI_DIReservoir lt_di_scatter_backup_temporal_resampling_stage(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    currReconnectionData = ReservoirSplattingReconnectionData_init();

    if (ph_scatter_temporal_enabled <= 0.5f || ph_debug_enable_direct_temporal_reuse < 0.5f) {
        return RTXDI_EmptyDIReservoir();
    }

    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);
    if (!lt_is_viewport_uv_in_bounds(pixel) || !RAB_IsSurfaceValid(surface)) {
        return RTXDI_EmptyDIReservoir();
    }

    RTXDI_RandomSamplerState sg = lt_init_random_sampler(
        uvec2(pixel),
        uint(frameCounter),
        6u
    );

    uint reservoirIdx = uint(pixel.y * viewWidth + pixel.x);
    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    ReservoirSplattingReconnectionData dstReconnectionData = ReservoirSplattingReconnectionData_init();

    RTXDI_DIReservoir currReservoir = lt_ScatterTemporalResampling_load_current_reservoir(pixel);
    LtScatterCurrentSample currSample = lt_ScatterTemporalResampling_load_current_sample(
        reservoirIdx,
        pixel,
        surface,
        currReservoir
    );

    RTXDI_DIReservoir backupReservoir = RTXDI_LoadDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel),
        lt_build_restir_di_parameters().bufferIndices.spatialResamplingInputBufferIndex
    );
    ReservoirSplattingReconnectionData backupReconnectionData = scatter_load_gather_intermediate_reconnection(pixel);

    {
        float currSampleMIS = 1.0f;
        if (currSample.isValid && currSample.hasPositivePHat) {
            float m1 = lt_scatter_radiance_phat(scatter_reconnection_integrand(currSample.reconnectionData))
                * currSample.confidence;

            float m2 = 0.0f;
            LtScatterShiftedPath scatteredCurr;
            RTXDI_DIReservoir shiftedCurrReservoir;
            ScatterReconnectionData shiftedCurrReconnectionData;
            float scatteredJacobian;
            if (lt_scatter_update_shifted_reservoir(
                    currSample.reconnectionData,
                    currSample.reservoir,
                    false,
                    true,
                    surface,
                    pixel,
                    scatteredCurr,
                    shiftedCurrReservoir,
                    shiftedCurrReconnectionData,
                    scatteredJacobian)) {
                ivec2 scatteredPixel = ivec2(floor(scatteredCurr.fractionalPixel));
                if (lt_is_viewport_uv_in_bounds(scatteredPixel)) {
                    float prevReservoirConfidence = ScatterTemporalResampling_load_previous_reservoir_confidence(scatteredPixel);
                    m2 = lt_scatter_radiance_phat(scatteredCurr.radiance)
                        * scatteredJacobian
                        * 0.5f
                        * prevReservoirConfidence;
                    m2 = (isnan(m2) || isinf(m2)) ? 0.0f : m2;
                }
            }

            float m3 = 0.0f;
            vec2 floatingCoord = scatter_load_gather_floating_coords(pixel);
            if (lt_is_viewport_uv_in_bounds(ivec2(floor(floatingCoord)))
                && all(greaterThanEqual(floatingCoord, vec2(0.0f)))
                && all(lessThan(floatingCoord, vec2(viewWidth, viewHeight)))) {
                ShiftedPathData shiftedCurr = gatherLensVertexCopyShift(
                    sg,
                    currSample.reconnectionData,
                    currSample.reconnectionData.time,
                    floatingCoord + currReservoir.pixelSampleUV,
                    currSample.reconnectionData.lensSample,
                    currReservoir
                );
                float shiftedJacobian = shiftedCurr.secondaryPathJacobian
                    / max(currSample.reconnectionData.secondaryPathJacobian, 1e-10f);
                float backupReservoirConfidence = lt_scatter_reservoir_confidence(backupReservoir, backupReconnectionData);
                m3 = lt_scatter_radiance_phat(shiftedCurr.radiance)
                    * shiftedJacobian
                    * 0.5f
                    * backupReservoirConfidence;
                m3 = (isnan(m3) || isinf(m3)) ? 0.0f : m3;
            }

            float denominator = m1 + m2 + m3;
            currSampleMIS = (denominator > 0.0f) ? (m1 / denominator) : 0.0f;
        }

        bool currSelected = lt_scatter_add_sample_from_reservoir(
            dstReservoir,
            dstReservoir.M,
            currSampleMIS,
            scatter_reconnection_integrand(currSample.reconnectionData),
            1.0f,
            currSample.isValid ? lt_scatter_compute_ucw(currSample.reservoir, scatter_reconnection_integrand(currSample.reconnectionData)) : 0.0f,
            currSample.confidence,
            currSample.reservoir,
            sg
        );
        dstReconnectionData = currSelected ? currSample.reconnectionData : dstReconnectionData;
    }

    {
        float backupSampleMIS = 0.0f;
        vec3 backupPHat = vec3(0.0f);
        float shiftedJacobian = 1.0f;
        if (RTXDI_IsValidDIReservoir(backupReservoir) && any(greaterThan(scatter_reconnection_integrand(backupReconnectionData), vec3(0.0f)))) {
            ShiftedPathData shiftedBackup = gatherLensVertexCopyShift(
                sg,
                backupReconnectionData,
                backupReconnectionData.time,
                vec2(pixel) + backupReservoir.pixelSampleUV,
                backupReconnectionData.lensSample,
                backupReservoir
            );
            shiftedJacobian = shiftedBackup.secondaryPathJacobian
                / max(backupReconnectionData.secondaryPathJacobian, 1e-10f);
            float m1 = lt_scatter_radiance_phat(shiftedBackup.radiance)
                * shiftedJacobian
                * currSample.confidence;
            backupPHat = (isnan(m1) || isinf(m1)) ? vec3(0.0f) : max(shiftedBackup.radiance, vec3(0.0f));
            shiftedJacobian = (isnan(m1) || isinf(m1)) ? 1.0f : shiftedJacobian;
            m1 = (isnan(m1) || isinf(m1)) ? 0.0f : m1;

            backupReconnectionData = ScatterTemporalReconnectionData_update(backupReconnectionData, shiftedBackup);

            float m2 = 0.0f;
            LtScatterShiftedPath scatteredBackup;
            RTXDI_DIReservoir shiftedBackupReservoir;
            ScatterReconnectionData shiftedBackupReconnectionData;
            float scatteredJacobian;
            if (lt_scatter_update_shifted_reservoir(
                    backupReconnectionData,
                    backupReservoir,
                    false,
                    true,
                    surface,
                    pixel,
                    scatteredBackup,
                    shiftedBackupReservoir,
                    shiftedBackupReconnectionData,
                    scatteredJacobian)) {
                ivec2 scatteredPixel = ivec2(floor(scatteredBackup.fractionalPixel));
                if (lt_is_viewport_uv_in_bounds(scatteredPixel)) {
                    float prevReservoirConfidence = ScatterTemporalResampling_load_previous_reservoir_confidence(scatteredPixel);
                    m2 = lt_scatter_radiance_phat(scatteredBackup.radiance)
                        * scatteredJacobian
                        * shiftedJacobian
                        * 0.5f
                        * prevReservoirConfidence;
                    m2 = (isnan(m2) || isinf(m2)) ? 0.0f : m2;
                }
            }

            float backupReservoirConfidence = lt_scatter_reservoir_confidence(backupReservoir, backupReconnectionData);
            float m3 = lt_scatter_radiance_phat(scatter_reconnection_integrand(backupReconnectionData))
                * 0.5f
                * backupReservoirConfidence;
            float denominator = m1 + m2 + m3;
            backupSampleMIS = (denominator > 0.0f) ? (m3 / denominator) : 0.0f;
        }

        bool backupSelected = lt_scatter_add_sample_from_reservoir(
            dstReservoir,
            dstReservoir.M,
            backupSampleMIS,
            backupPHat,
            shiftedJacobian,
            lt_scatter_compute_ucw(backupReservoir, scatter_reconnection_integrand(backupReconnectionData)),
            lt_scatter_reservoir_confidence(backupReservoir, backupReconnectionData),
            backupReservoir,
            sg
        );
        dstReconnectionData = backupSelected ? backupReconnectionData : dstReconnectionData;
    }

    float newConfidence = dstReservoir.M;

    uint numReservoirs = lt_reproject_temporal_samples_cell_counter_value(reservoirIdx);
    uint cellOffset = lt_scatter_temporal_resampling_cell_offset_value(reservoirIdx);
    for (uint i = 0u; i < numReservoirs; ++i) {
        ivec2 scatteredPixel = ivec2(lt_scatter_temporal_resampling_load_sorted_reservoir(cellOffset + i));
        ScatterTemporalResampling_process_contributor(
            dstReservoir,
            dstReconnectionData,
            newConfidence,
            scatteredPixel,
            pixel,
            currSample.reservoir,
            currSample.reconnectionData,
            currSample.confidence,
            sg
        );
    }

    dstReservoir.M = ScatterTemporalResampling_motion_vector_confidence(pixel, newConfidence);
    currReconnectionData = dstReconnectionData;
    return dstReservoir;
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SCATTER_STAGE)
RTXDI_DIReservoir lt_di_multi_scatter_temporal_resampling_stage(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    currReconnectionData = ReservoirSplattingReconnectionData_init();
    if (ph_scatter_temporal_enabled <= 0.5f || ph_debug_enable_direct_temporal_reuse < 0.5f) {
        return RTXDI_EmptyDIReservoir();
    }

    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);
    if (!lt_is_viewport_uv_in_bounds(pixel) || !RAB_IsSurfaceValid(surface)) {
        return RTXDI_EmptyDIReservoir();
    }

    RTXDI_RandomSamplerState sg = lt_init_random_sampler(uvec2(pixel), uint(frameCounter), 5u);
    uint reservoirIdx = uint(pixel.y * viewWidth + pixel.x);
    RTXDI_DIReservoir currReservoir = lt_ScatterTemporalResampling_load_current_reservoir(pixel);
    LtScatterCurrentSample currSample = lt_ScatterTemporalResampling_load_current_sample(
        reservoirIdx,
        pixel,
        surface,
        currReservoir
    );

    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    ReservoirSplattingReconnectionData dstReconnectionData = ReservoirSplattingReconnectionData_init();

    {
        float currSampleMIS = ScatterTemporalResampling_compute_curr_sample_mis(
            currSample,
            pixel,
            surface
        );
        bool currSelected = lt_scatter_add_sample_from_reservoir(
            dstReservoir,
            dstReservoir.M,
            currSampleMIS,
            scatter_reconnection_integrand(currSample.reconnectionData),
            1.0f,
            currSample.isValid ? lt_scatter_compute_ucw(currSample.reservoir, scatter_reconnection_integrand(currSample.reconnectionData)) : 0.0f,
            currSample.confidence,
            currSample.reservoir,
            sg
        );
        dstReconnectionData = currSelected ? currSample.reconnectionData : dstReconnectionData;
    }

    float newConfidence = dstReservoir.M;

    for (uint partitionIndex = 0u; partitionIndex < lt_multi_temporal_partition_count(); ++partitionIndex) {
        uint partitionedCellIndex = lt_temporal_partitioned_cell_index(partitionIndex, reservoirIdx);
        uint numReservoirs = lt_multi_reproject_temporal_samples_cell_counter_value(partitionIndex, partitionedCellIndex);
        uint cellOffset = lt_multi_scatter_temporal_resampling_cell_offset_value(partitionIndex, partitionedCellIndex);
        for (uint i = 0u; i < numReservoirs; ++i)
        {
            uint sortedBufferIndex = lt_temporal_partitioned_contributor_index(partitionIndex, cellOffset + i);
            ivec2 scatteredPixel = ivec2(lt_multi_scatter_temporal_resampling_load_sorted_reservoir(partitionIndex, sortedBufferIndex));
            bool prevSelected = lt_multi_scatter_process_contributor(
                dstReservoir,
                dstReconnectionData,
                scatteredPixel,
                pixel,
                partitionIndex,
                currSample.reservoir,
                currSample.reconnectionData,
                currSample.confidence,
                sg
            );
            newConfidence = prevSelected ? dstReservoir.M : newConfidence;
        }
    }

    dstReservoir.M = ScatterTemporalResampling_motion_vector_confidence(pixel, newConfidence);
    currReconnectionData = dstReconnectionData;
    return dstReservoir;
}
#endif
#endif
#endif

#endif
