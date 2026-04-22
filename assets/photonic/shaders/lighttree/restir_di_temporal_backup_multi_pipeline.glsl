#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_BACKUP_MULTI_PIPELINE_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_BACKUP_MULTI_PIPELINE_GLSL

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
