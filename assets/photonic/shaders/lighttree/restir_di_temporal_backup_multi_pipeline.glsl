#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_BACKUP_MULTI_PIPELINE_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_BACKUP_MULTI_PIPELINE_GLSL

bool lt_ScatterBackupTemporalResampling_use_pairwise_mis()
{
    return ph_restir_scatter_backup_mis_mode > 0.5f;
}

float lt_ScatterBackupTemporalResampling_mis_scale()
{
    return lt_ScatterBackupTemporalResampling_use_pairwise_mis() ? 0.5f : 1.0f;
}

RTXDI_DIReservoir lt_ScatterBackupTemporalResampling_load_backup_reservoir(
    ivec2 pixel)
{
    return lt_di_load_gather_intermediate_reservoir(pixel);
}

bool lt_ScatterBackupTemporalResampling_add_current_sample(
    ivec2 pixel,
    inout RTXDI_DIReservoir dstReservoir,
    inout float dstConfidence,
    inout ReservoirSplattingReconnectionData dstReconnectionData,
    LtScatterCurrentSample currSample,
    RTXDI_DIReservoir backupReservoir,
    ReservoirSplattingReconnectionData backupReconnectionData,
    inout RTXDI_RandomSamplerState sg)
{
    float currSampleMIS = 1.0f;
    vec3 currIntegrand = PathReservoir_getIntegrand(currSample.reservoir);
    if (currSample.isValid && currSample.hasPositivePHat)
    {
        float m1 = lt_scatter_radiance_phat(currIntegrand) * currSample.confidence;

        float m2 = 0.0f;
        LtScatterShiftedPath scatteredCurr;
        RTXDI_DIReservoir shiftedCurrReservoir;
        ScatterReconnectionData shiftedCurrReconnection;
        float scatteredJacobian;
        if (lt_scatter_update_shifted_reservoir_to_previous_frame(
                currSample.reconnectionData,
                currSample.reservoir,
                false,
                scatteredCurr,
                shiftedCurrReservoir,
                shiftedCurrReconnection,
                scatteredJacobian))
        {
            ivec2 scatteredPixel = ivec2(floor(scatteredCurr.fractionalPixel));
            float prevReservoirConfidence = ScatterTemporalResampling_load_previous_reservoir_confidence(scatteredPixel);
            m2 = lt_scatter_radiance_phat(scatteredCurr.radiance)
                * scatteredJacobian
                * 0.5f
                * prevReservoirConfidence;
            m2 = (isnan(m2) || isinf(m2)) ? 0.0f : m2;
        }

        float m3 = 0.0f;
        GatherHelper gatherHelper = GatherHelper_init(pixel);
        vec2 floatingCoord = GatherHelper_getFloatingCoords(gatherHelper);
        if (lt_is_viewport_uv_in_bounds(floatingCoord))
        {
        ShiftedPathData shiftedCurr = gatherLensVertexCopyShift(
            sg,
            currSample.reconnectionData,
            currSample.reconnectionData.time + lt_di_temporal_artificial_frame_time(),
            floatingCoord + PathReservoir_getSubPixel(currSample.reservoir, pixel),
            currSample.reconnectionData.lensSample,
            currSample.reservoir
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

        if (lt_ScatterBackupTemporalResampling_use_pairwise_mis())
        {
            float pairwise12 = ((0.5f * m1 + m2) > 0.0f) ? (0.5f * m1 / (0.5f * m1 + m2)) : 0.0f;
            float pairwise13 = ((0.5f * m1 + m3) > 0.0f) ? (0.5f * m1 / (0.5f * m1 + m3)) : 0.0f;
            currSampleMIS = 0.5f * (pairwise12 + pairwise13);
        }
        else
        {
            float denominator = m1 + m2 + m3;
            currSampleMIS = (denominator > 0.0f) ? (m1 / denominator) : 0.0f;
        }
    }

    bool currSelected = lt_scatter_add_sample_from_reservoir(
        dstReservoir,
        dstConfidence,
        currSampleMIS,
        currIntegrand,
        1.0f,
        currSample.isValid ? lt_scatter_compute_ucw(currSample.reservoir, currIntegrand) : 0.0f,
        currSample.confidence,
        currSample.reservoir,
        sg
    );
    if (currSelected)
    {
        dstReconnectionData = currSample.reconnectionData;
    }
    return currSelected;
}

bool lt_ScatterBackupTemporalResampling_add_backup_sample(
    ivec2 pixel,
    inout RTXDI_DIReservoir dstReservoir,
    inout float dstConfidence,
    inout ReservoirSplattingReconnectionData dstReconnectionData,
    LtScatterCurrentSample currSample,
    RTXDI_DIReservoir backupReservoir,
    inout ReservoirSplattingReconnectionData backupReconnectionData,
    inout RTXDI_RandomSamplerState sg)
{
    float backupSampleMIS = 0.0f;
    vec3 backupPHat = vec3(0.0f);
    float shiftedJacobian = 1.0f;
    vec3 backupIntegrand = PathReservoir_getIntegrand(backupReservoir);
    if (RTXDI_IsValidDIReservoir(backupReservoir)
        && any(greaterThan(backupIntegrand, vec3(0.0f))))
    {
        ShiftedPathData shiftedBackup = gatherLensVertexCopyShift(
            sg,
            backupReconnectionData,
            backupReconnectionData.time,
            vec2(pixel) + PathReservoir_getSubPixel(backupReservoir, pixel),
            backupReconnectionData.lensSample,
            backupReservoir
        );
        shiftedJacobian = shiftedBackup.secondaryPathJacobian
            / max(backupReconnectionData.secondaryPathJacobian, 1e-10f);

        float m1 = lt_scatter_radiance_phat(shiftedBackup.radiance)
            * shiftedJacobian
            * currSample.confidence;
        bool invalidM1 = isnan(m1) || isinf(m1);
        backupPHat = invalidM1 ? vec3(0.0f) : max(shiftedBackup.radiance, vec3(0.0f));
        shiftedJacobian = invalidM1 ? 1.0f : shiftedJacobian;
        m1 = invalidM1 ? 0.0f : m1;

        backupReconnectionData = ReconnectionData_update(backupReconnectionData, shiftedBackup);

        float m2 = 0.0f;
        if (!lt_ScatterBackupTemporalResampling_use_pairwise_mis())
        {
            LtScatterShiftedPath scatteredBackup;
            RTXDI_DIReservoir shiftedBackupReservoir;
            ScatterReconnectionData shiftedBackupReconnection;
            float scatteredJacobian;
            if (lt_scatter_update_shifted_reservoir_to_previous_frame(
                    backupReconnectionData,
                    backupReservoir,
                    false,
                    scatteredBackup,
                    shiftedBackupReservoir,
                    shiftedBackupReconnection,
                    scatteredJacobian))
            {
                ivec2 scatteredPixel = ivec2(floor(scatteredBackup.fractionalPixel));
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
        float m3 = lt_scatter_radiance_phat(backupIntegrand)
            * 0.5f
            * backupReservoirConfidence;
        float denominator = lt_ScatterBackupTemporalResampling_mis_scale() * m1 + m2 + m3;
        backupSampleMIS = (denominator > 0.0f)
            ? (lt_ScatterBackupTemporalResampling_mis_scale() * m3 / denominator)
            : 0.0f;
    }

    bool backupSelected = lt_scatter_add_sample_from_reservoir(
        dstReservoir,
        dstConfidence,
        backupSampleMIS,
        backupPHat,
        shiftedJacobian,
        lt_scatter_compute_ucw(backupReservoir, backupIntegrand),
        lt_scatter_reservoir_confidence(backupReservoir, backupReconnectionData),
        backupReservoir,
        sg
    );
    if (backupSelected)
    {
        dstReconnectionData = backupReconnectionData;
    }
    return backupSelected;
}

bool lt_ScatterBackupTemporalResampling_add_scattered_previous_sample(
    ivec2 pixel,
    inout RTXDI_DIReservoir dstReservoir,
    inout float dstConfidence,
    inout ReservoirSplattingReconnectionData dstReconnectionData,
    ivec2 scatteredPixel,
    LtScatterCurrentSample currSample,
    RTXDI_DIReservoir backupReservoir,
    ReservoirSplattingReconnectionData backupReconnectionData,
    inout RTXDI_RandomSamplerState sg)
{
    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(scatteredPixel)
    );
    if (!RTXDI_IsValidDIReservoir(prevReservoir))
    {
        return false;
    }

    ScatterReconnectionData prevReconnectionData = RestirDI_loadPreviousFrameReconnection(scatteredPixel);
    float prevReservoirConfidence = ScatterTemporalResampling_load_previous_reservoir_confidence(scatteredPixel);
    RAB_Surface targetSurface = RAB_GetGBufferSurface(pixel, false);
    if (!RAB_IsSurfaceValid(targetSurface))
    {
        return false;
    }

    float prevSampleMIS = 0.0f;
    vec3 prevPHat = vec3(0.0f);
    float scatteredJacobian = 1.0f;
    vec3 prevIntegrand = PathReservoir_getIntegrand(prevReservoir);
    if (any(greaterThan(prevIntegrand, vec3(0.0f))))
    {
        LtScatterShiftedPath scatteredPrev;
        RTXDI_DIReservoir shiftedReservoir;
        ScatterReconnectionData shiftedReconnection;
        if (!lt_scatter_update_shifted_reservoir(
                prevReconnectionData,
                prevReservoir,
                true,
                false,
                targetSurface,
                pixel,
                scatteredPrev,
                shiftedReservoir,
                shiftedReconnection,
                scatteredJacobian))
        {
            return false;
        }

        float m1 = lt_scatter_radiance_phat(scatteredPrev.radiance)
            * scatteredJacobian
            * currSample.confidence;
        bool invalidM1 = isnan(m1) || isinf(m1);
        prevPHat = invalidM1 ? vec3(0.0f) : max(scatteredPrev.radiance, vec3(0.0f));
        scatteredJacobian = invalidM1 ? 1.0f : scatteredJacobian;
        m1 = invalidM1 ? 0.0f : m1;

        float m2 = lt_scatter_radiance_phat(prevIntegrand)
            * 0.5f
            * prevReservoirConfidence;

        float m3 = 0.0f;
        if (!lt_ScatterBackupTemporalResampling_use_pairwise_mis())
        {
            GatherHelper gatherHelper = GatherHelper_init(pixel);
            vec2 floatingCoord = GatherHelper_getFloatingCoords(gatherHelper);
            vec2 relativeSubPixel = PathReservoir_getSubPixel(shiftedReservoir, pixel);
            if (lt_is_viewport_uv_in_bounds(floatingCoord + relativeSubPixel))
            {
                ShiftedPathData shiftedPrevBackup = gatherLensVertexCopyShift(
                    sg,
                    shiftedReconnection,
                    prevReconnectionData.time + lt_di_temporal_artificial_frame_time(),
                    floatingCoord + relativeSubPixel,
                    shiftedReconnection.lensSample,
                    shiftedReservoir
                );
                float shiftedJacobian = shiftedPrevBackup.secondaryPathJacobian
                    / max(shiftedReconnection.secondaryPathJacobian, 1e-10f);
                float backupReservoirConfidence = lt_scatter_reservoir_confidence(backupReservoir, backupReconnectionData);
                m3 = lt_scatter_radiance_phat(shiftedPrevBackup.radiance)
                    * shiftedJacobian
                    * scatteredJacobian
                    * 0.5f
                    * backupReservoirConfidence;
                m3 = (isnan(m3) || isinf(m3)) ? 0.0f : m3;
            }
        }

        float denominator = lt_ScatterBackupTemporalResampling_mis_scale() * m1 + m2 + m3;
        prevSampleMIS = (denominator > 0.0f)
            ? (lt_ScatterBackupTemporalResampling_mis_scale() * m2 / denominator)
            : 0.0f;

        bool prevSelected = lt_scatter_add_sample_from_reservoir(
            dstReservoir,
            dstConfidence,
            prevSampleMIS,
            prevPHat,
            scatteredJacobian,
            lt_scatter_compute_ucw(prevReservoir, prevIntegrand),
            prevReservoirConfidence,
            shiftedReservoir,
            sg
        );
        if (prevSelected)
        {
            dstReconnectionData = shiftedReconnection;
        }
        return prevSelected;
    }

    return false;
}

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SCATTER_STAGE)
bool lt_MultiScatterTemporalResampling_add_scattered_previous_sample(
    ivec2 pixel,
    inout RTXDI_DIReservoir dstReservoir,
    inout float dstConfidence,
    inout ReservoirSplattingReconnectionData dstReconnectionData,
    ivec2 scatteredPixel,
    uint partitionIndex,
    LtScatterCurrentSample currSample,
    inout RTXDI_RandomSamplerState sg)
{
    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(scatteredPixel)
    );
    if (!RTXDI_IsValidDIReservoir(prevReservoir))
    {
        return false;
    }

    ScatterReconnectionData prevReconnectionData = RestirDI_loadPreviousFrameReconnection(scatteredPixel);
    ScatterReconnectionData partitionedReconnectionData = prevReconnectionData;
    float fractionalTime = lt_multi_temporal_partition_fraction(prevReconnectionData.time);
    float newTime = lt_multi_temporal_partition_time(fractionalTime, partitionIndex);
    partitionedReconnectionData.time = newTime;

    RAB_Surface targetSurface = RAB_GetGBufferSurface(pixel, false);
    if (!RAB_IsSurfaceValid(targetSurface))
    {
        return false;
    }

    float prevSampleMIS = 0.0f;
    vec3 prevPHat = vec3(0.0f);
    float shiftedJacobian = 1.0f;
    vec3 prevIntegrand = PathReservoir_getIntegrand(prevReservoir);
    if (any(greaterThan(prevIntegrand, vec3(0.0f))))
    {
        LtScatterShiftedPath shiftedPrev;
        RTXDI_DIReservoir shiftedReservoir;
        ScatterReconnectionData shiftedReconnection;
        if (!lt_scatter_update_shifted_reservoir(
                partitionedReconnectionData,
                prevReservoir,
                true,
                false,
                targetSurface,
                pixel,
                shiftedPrev,
                shiftedReservoir,
                shiftedReconnection,
                shiftedJacobian))
        {
            return false;
        }

        float m1 = lt_scatter_radiance_phat(shiftedPrev.radiance)
            * shiftedJacobian
            * currSample.confidence;
        bool invalidM1 = isnan(m1) || isinf(m1);
        prevPHat = invalidM1 ? vec3(0.0f) : max(shiftedPrev.radiance, vec3(0.0f));
        shiftedJacobian = invalidM1 ? 1.0f : shiftedJacobian;
        m1 = invalidM1 ? 0.0f : m1;

        float prevReservoirConfidence = lt_scatter_reservoir_confidence(prevReservoir, prevReconnectionData);
        float m2 = lt_scatter_radiance_phat(prevIntegrand) * prevReservoirConfidence;
        float denominator = m1 + m2;
        prevSampleMIS = (denominator > 0.0f) ? (m2 / denominator) : 0.0f;

        bool prevSelected = lt_scatter_add_sample_from_reservoir(
            dstReservoir,
            dstConfidence,
            prevSampleMIS,
            prevPHat,
            shiftedJacobian * (1.0f / float(lt_multi_temporal_partition_count())),
            lt_scatter_compute_ucw(prevReservoir, prevIntegrand),
            prevReservoirConfidence,
            shiftedReservoir,
            sg
        );
        if (prevSelected)
        {
            dstReconnectionData = shiftedReconnection;
        }
        return prevSelected;
    }

    return false;
}

float lt_MultiScatterTemporalResampling_current_sample_mis(
    LtScatterCurrentSample currSample)
{
    if (!currSample.isValid || !currSample.hasPositivePHat)
    {
        return 1.0f;
    }

    float timePartitions = lt_multi_temporal_partition_duration();
    float fractionalTime = (currSample.reconnectionData.time
        - floor(currSample.reconnectionData.time / timePartitions) * timePartitions)
        / timePartitions;

    ScatterReconnectionData partitionedCurrReconnection = currSample.reconnectionData;
    partitionedCurrReconnection.time = fractionalTime;

    LtScatterShiftedPath shiftedCurr;
    RTXDI_DIReservoir shiftedReservoir;
    ScatterReconnectionData shiftedReconnection;
    float shiftedJacobian;
    if (!lt_scatter_update_shifted_reservoir_to_previous_frame(
            partitionedCurrReconnection,
            currSample.reservoir,
            false,
            shiftedCurr,
            shiftedReservoir,
            shiftedReconnection,
            shiftedJacobian))
    {
        return 1.0f;
    }

    ivec2 scatteredPixel = ivec2(floor(shiftedCurr.fractionalPixel));
    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(scatteredPixel)
    );
    float prevReservoirConfidence = RTXDI_IsValidDIReservoir(prevReservoir)
        ? ScatterTemporalResampling_load_previous_reservoir_confidence(scatteredPixel)
        : 0.0f;

    float m1 = lt_scatter_radiance_phat(PathReservoir_getIntegrand(currSample.reservoir))
        * currSample.confidence;
    float m2 = lt_scatter_radiance_phat(shiftedCurr.radiance)
        * shiftedJacobian
        * prevReservoirConfidence;
    m2 = (isnan(m2) || isinf(m2)) ? 0.0f : m2;

    float denominator = m1 + m2;
    return (denominator > 0.0f) ? (m1 / denominator) : 0.0f;
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_STAGE)
void multiComputeCellOffsetsStage(
    ivec2 pixel)
{
#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
    if (ph_scatter_temporal_enabled > 0.5f) {
        MultiSortReprojectedReservoirs_computeCellOffsets(pixel);
    }
#endif
}

void multiSortCellDataStage(
    uint index)
{
#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
    if (ph_scatter_temporal_enabled > 0.5f) {
        MultiSortReprojectedReservoirs_sortCellData(index);
    }
#endif
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_BACKUP_STAGE)
RTXDI_DIReservoir ScatterBackupTemporalResampling_run(
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
    float dstConfidence = 0.0f;
    ReservoirSplattingReconnectionData dstReconnectionData = ReservoirSplattingReconnectionData_init();

    RTXDI_DIReservoir currReservoir = lt_ScatterTemporalResampling_load_current_reservoir(pixel);
    LtScatterCurrentSample currSample = lt_ScatterTemporalResampling_load_current_sample(
        reservoirIdx,
        pixel,
        surface,
        currReservoir
    );

    RTXDI_DIReservoir backupReservoir = lt_ScatterBackupTemporalResampling_load_backup_reservoir(pixel);
    ReservoirSplattingReconnectionData backupReconnectionData = RestirDI_loadGatherIntermediateReconnection(pixel);

    lt_ScatterBackupTemporalResampling_add_current_sample(
        pixel,
        dstReservoir,
        dstConfidence,
        dstReconnectionData,
        currSample,
        backupReservoir,
        backupReconnectionData,
        sg
    );

    lt_ScatterBackupTemporalResampling_add_backup_sample(
        pixel,
        dstReservoir,
        dstConfidence,
        dstReconnectionData,
        currSample,
        backupReservoir,
        backupReconnectionData,
        sg
    );

    float newConfidence = dstConfidence;

    uint numReservoirs = lt_reproject_temporal_samples_cell_counter_value(reservoirIdx);
    uint cellOffset = lt_scatter_temporal_resampling_cell_offset_value(reservoirIdx);
    for (uint i = 0u; i < numReservoirs; ++i)
    {
        ivec2 scatteredPixel = ivec2(lt_scatter_temporal_resampling_load_sorted_reservoir(cellOffset + i));
        lt_ScatterBackupTemporalResampling_add_scattered_previous_sample(
            pixel,
            dstReservoir,
            dstConfidence,
            dstReconnectionData,
            scatteredPixel,
            currSample,
            backupReservoir,
            backupReconnectionData,
            sg
        );
    }

    PathReservoir_setConfidence(
        dstReservoir,
        ScatterTemporalResampling_motion_vector_confidence(pixel, newConfidence)
    );
    currReconnectionData = dstReconnectionData;
    return dstReservoir;
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SCATTER_STAGE)
RTXDI_DIReservoir MultiScatterTemporalResampling_run(
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
    float dstConfidence = 0.0f;
    ReservoirSplattingReconnectionData dstReconnectionData = ReservoirSplattingReconnectionData_init();

    float currSampleMIS = lt_MultiScatterTemporalResampling_current_sample_mis(currSample);
    bool currSelected = lt_scatter_add_sample_from_reservoir(
        dstReservoir,
        dstConfidence,
        currSampleMIS,
        PathReservoir_getIntegrand(currSample.reservoir),
        1.0f,
        currSample.isValid ? lt_scatter_compute_ucw(currSample.reservoir, PathReservoir_getIntegrand(currSample.reservoir)) : 0.0f,
        currSample.confidence,
        currSample.reservoir,
        sg
    );
    if (currSelected)
    {
        dstReconnectionData = currSample.reconnectionData;
    }

    float newConfidence = dstConfidence;

    for (uint partitionIndex = 0u; partitionIndex < lt_multi_temporal_partition_count(); ++partitionIndex)
    {
        uint numReservoirs = lt_multi_reproject_temporal_samples_cell_counter_value(partitionIndex, reservoirIdx);
        uint cellOffset = lt_multi_scatter_temporal_resampling_cell_offset_value(partitionIndex, reservoirIdx);
        for (uint i = 0u; i < numReservoirs; ++i)
        {
            ivec2 scatteredPixel = ivec2(
                lt_multi_scatter_temporal_resampling_load_sorted_reservoir(partitionIndex, cellOffset + i)
            );
            lt_MultiScatterTemporalResampling_add_scattered_previous_sample(
                pixel,
                dstReservoir,
                dstConfidence,
                dstReconnectionData,
                scatteredPixel,
                partitionIndex,
                currSample,
                sg
            );
        }
    }

    PathReservoir_setConfidence(
        dstReservoir,
        ScatterTemporalResampling_motion_vector_confidence(pixel, newConfidence)
    );
    currReconnectionData = dstReconnectionData;
    return dstReservoir;
}
#endif

#endif
