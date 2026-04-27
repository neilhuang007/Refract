#ifndef PHOTONICS_RESERVOIR_SPLATTING_SCATTER_BACKUP_TEMPORAL_RESAMPLING_GLSL
#define PHOTONICS_RESERVOIR_SPLATTING_SCATTER_BACKUP_TEMPORAL_RESAMPLING_GLSL

#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"
#include "/photonics/lighttree/restir_di_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_spatial_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_shared.glsl"
#include "/photonics/lighttree/restir_di_temporal_shift_mapping.glsl"
#include "/photonics/lighttree/restir_di_temporal.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_common.glsl"

RTXDI_DIReservoir lt_di_load_gather_intermediate_reservoir(
    ivec2 pixel)
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
    inout ReconnectionData dstReconnectionData,
    LtScatterCurrentSample currSample,
    RTXDI_DIReservoir backupReservoir,
    ReconnectionData backupReconnectionData,
    inout RTXDI_RandomSamplerState sg)
{
    float currSampleMIS = 1.0f;
    vec3 currIntegrand = PathReservoir_getIntegrand(currSample.reservoir);
    if (currSample.hasPositivePHat)
    {
        float m1 = lt_scatter_radiance_phat(currIntegrand)
            * lt_scatter_confidence_mis_weight(currSample.confidence);

        float m2 = 0.0f;
        LtScatterShiftedPath scatteredCurr;
        RTXDI_DIReservoir shiftedCurrReservoir;
        ReconnectionData shiftedCurrReconnection;
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
                * lt_scatter_confidence_mis_weight(prevReservoirConfidence);
            m2 = isnan(m2) ? 0.0f : m2;
        }

        float m3 = 0.0f;
        vec2 floatingCoord = GatherData_getFloatingCoords(pixel);
        if (lt_is_viewport_uv_in_bounds(floatingCoord))
        {
            ShiftedPathData shiftedCurr = gatherLensVertexCopyShift(
                sg,
                currSample.reconnectionData,
                currSample.reconnectionData.time + lt_di_temporal_artificial_frame_time(),
                floatingCoord + PathReservoir_getSubPixel(currSample.reservoir, pixel),
                currSample.reconnectionData.lensSample,
                currSample.reservoir,
                false,
                true
            );
            float shiftedJacobian = shiftedCurr.secondaryPathJacobian
                / currSample.reconnectionData.secondaryPathJacobian;
            float backupReservoirConfidence = lt_scatter_reservoir_confidence(backupReservoir, backupReconnectionData);
            m3 = lt_scatter_radiance_phat(shiftedCurr.radiance)
                * shiftedJacobian
                * 0.5f
                * lt_scatter_confidence_mis_weight(backupReservoirConfidence);
            m3 = isnan(m3) ? 0.0f : m3;
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
        lt_scatter_compute_ucw(currSample.reservoir, currIntegrand),
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
    inout ReconnectionData dstReconnectionData,
    LtScatterCurrentSample currSample,
    RTXDI_DIReservoir backupReservoir,
    inout ReconnectionData backupReconnectionData,
    inout RTXDI_RandomSamplerState sg)
{
    float backupSampleMIS = 0.0f;
    vec3 backupPHat = vec3(0.0f);
    float shiftedJacobian = 1.0f;
    vec3 backupIntegrand = PathReservoir_getIntegrand(backupReservoir);
    if (any(greaterThan(backupIntegrand, vec3(0.0f))))
    {
        ShiftedPathData shiftedBackup = gatherLensVertexCopyShift(
            sg,
            backupReconnectionData,
            backupReconnectionData.time,
            vec2(pixel) + PathReservoir_getSubPixel(backupReservoir, pixel),
            backupReconnectionData.lensSample,
            backupReservoir,
            true,
            false
        );
        shiftedJacobian = shiftedBackup.secondaryPathJacobian
            / backupReconnectionData.secondaryPathJacobian;

        float m1 = lt_scatter_radiance_phat(shiftedBackup.radiance)
            * shiftedJacobian
            * lt_scatter_confidence_mis_weight(currSample.confidence);
        bool invalidM1 = isnan(m1);
        backupPHat = invalidM1 ? vec3(0.0f) : shiftedBackup.radiance;
        shiftedJacobian = invalidM1 ? 1.0f : shiftedJacobian;
        m1 = invalidM1 ? 0.0f : m1;

        backupReconnectionData = ReconnectionData_update(backupReconnectionData, shiftedBackup);

        float m2 = 0.0f;
        if (!lt_ScatterBackupTemporalResampling_use_pairwise_mis())
        {
            LtScatterShiftedPath scatteredBackup;
            RTXDI_DIReservoir shiftedBackupReservoir;
            ReconnectionData shiftedBackupReconnection;
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
                    * lt_scatter_confidence_mis_weight(prevReservoirConfidence);
                m2 = isnan(m2) ? 0.0f : m2;
            }
        }

        float backupReservoirConfidence = lt_scatter_reservoir_confidence(backupReservoir, backupReconnectionData);
        float m3 = lt_scatter_radiance_phat(backupIntegrand)
            * 0.5f
            * lt_scatter_confidence_mis_weight(backupReservoirConfidence);
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
    inout ReconnectionData dstReconnectionData,
    ivec2 scatteredPixel,
    LtScatterCurrentSample currSample,
    RTXDI_DIReservoir backupReservoir,
    ReconnectionData backupReconnectionData,
    inout RTXDI_RandomSamplerState sg)
{
    ivec2 previousReservoirPixel = ScatterTemporalResampling_previous_reservoir_pixel(scatteredPixel);
    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(previousReservoirPixel)
    );
    ReconnectionData prevReconnectionData = RestirDI_loadPreviousFrameReconnection(previousReservoirPixel);
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
        ReconnectionData shiftedReconnection;
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
            * lt_scatter_confidence_mis_weight(currSample.confidence);
        bool invalidM1 = isnan(m1);
        prevPHat = invalidM1 ? vec3(0.0f) : scatteredPrev.radiance;
        scatteredJacobian = invalidM1 ? 1.0f : scatteredJacobian;
        m1 = invalidM1 ? 0.0f : m1;

        float m2 = lt_scatter_radiance_phat(prevIntegrand)
            * 0.5f
            * lt_scatter_confidence_mis_weight(prevReservoirConfidence);

        float m3 = 0.0f;
        if (!lt_ScatterBackupTemporalResampling_use_pairwise_mis())
        {
            vec2 floatingCoord = GatherData_getFloatingCoords(pixel);
            vec2 relativeSubPixel = PathReservoir_getSubPixel(shiftedReservoir, pixel);
            if (lt_is_viewport_uv_in_bounds(floatingCoord + relativeSubPixel))
            {
                ShiftedPathData shiftedPrevBackup = gatherLensVertexCopyShift(
                    sg,
                    shiftedReconnection,
                    prevReconnectionData.time + lt_di_temporal_artificial_frame_time(),
                    floatingCoord + relativeSubPixel,
                    shiftedReconnection.lensSample,
                    shiftedReservoir,
                    false,
                    true
                );
                float shiftedJacobian = shiftedPrevBackup.secondaryPathJacobian
                    / shiftedReconnection.secondaryPathJacobian;
                float backupReservoirConfidence = lt_scatter_reservoir_confidence(backupReservoir, backupReconnectionData);
                m3 = lt_scatter_radiance_phat(shiftedPrevBackup.radiance)
                    * shiftedJacobian
                    * scatteredJacobian
                    * 0.5f
                    * lt_scatter_confidence_mis_weight(backupReservoirConfidence);
                m3 = isnan(m3) ? 0.0f : m3;
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

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_BACKUP_STAGE)
RTXDI_DIReservoir ScatterBackupTemporalResampling_run(
    ivec2 pixel,
    out ReconnectionData currReconnectionData)
{
    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        currReconnectionData = ReconnectionData_init();
        return RTXDI_EmptyDIReservoir();
    }
    currReconnectionData = ReconnectionData_init();

    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);

    RTXDI_RandomSamplerState sg = lt_init_random_sampler(
        uvec2(pixel),
        uint(frameCounter),
        6u
    );

    uint reservoirIdx = lt_temporal_scatter_cell_index_from_pixel(pixel);
    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    float dstConfidence = 0.0f;
    ReconnectionData dstReconnectionData = ReconnectionData_init();

    RTXDI_DIReservoir currReservoir = lt_ScatterTemporalResampling_load_current_reservoir(pixel);
    LtScatterCurrentSample currSample = lt_ScatterTemporalResampling_load_current_sample(
        reservoirIdx,
        pixel,
        surface,
        currReservoir
    );

    RTXDI_DIReservoir backupReservoir = lt_ScatterBackupTemporalResampling_load_backup_reservoir(pixel);
    ReconnectionData backupReconnectionData = RestirDI_loadGatherIntermediateReconnection(pixel);

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
            newConfidence,
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

#endif
