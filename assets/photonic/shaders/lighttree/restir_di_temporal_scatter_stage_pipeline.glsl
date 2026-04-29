#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_SCATTER_STAGE_PIPELINE_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_SCATTER_STAGE_PIPELINE_GLSL

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_STAGE)
RTXDI_DIReservoir ScatterTemporalResampling_run(
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
        5u
    );

    uint reservoirIdx = lt_temporal_scatter_cell_index_from_pixel(pixel);
    RTXDI_DIReservoir currReservoir = lt_ScatterTemporalResampling_load_current_reservoir(pixel);
    LtScatterCurrentSample currSample = lt_ScatterTemporalResampling_load_current_sample(
        reservoirIdx,
        pixel,
        surface,
        currReservoir
    );

    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    float dstConfidence = 0.0f;
    ReconnectionData dstReconnectionData = ReconnectionData_init();
    ReconnectionData currReconnectionDataLocal = currSample.reconnectionData;
    vec3 currIntegrand = PathReservoir_getIntegrand(currReservoir);
    float currReservoirConfidence = currSample.confidence;
    float currUCW = lt_scatter_compute_ucw(currReservoir, currIntegrand);

    float currSampleMIS = 1.0f;
    if (currSample.hasPositivePHat) {
        float m1 = lt_scatter_radiance_phat(currIntegrand)
            * lt_scatter_confidence_mis_weight(currReservoirConfidence);

        float m2 = 0.0f;
        ShiftedPathData shiftedCurr = scatterReprojectionShift(
            sg,
            currReconnectionDataLocal,
            currReconnectionDataLocal.time + lt_di_temporal_artificial_frame_time(),
            currReconnectionDataLocal.firstHit,
            currReconnectionDataLocal.lensSample,
            currReservoir,
            false,
            true,
            false
        );
        float shiftedJacobian = 0.0f;
        float baseJacobian = currReconnectionDataLocal.subPixelJacobian
            * currReconnectionDataLocal.secondaryPathJacobian;
        if (abs(baseJacobian) > 1e-20f && !isnan(baseJacobian)) {
            shiftedJacobian = (shiftedCurr.subPixelJacobian * shiftedCurr.secondaryPathJacobian)
                / baseJacobian;
        }
        m2 = lt_scatter_radiance_phat(shiftedCurr.radiance) * shiftedJacobian;
        m2 = isnan(m2) ? 0.0f : m2;

        ivec2 scatteredPixel = ivec2(floor(shiftedCurr.fractionalPixel));
        if (lt_is_viewport_uv_in_bounds(scatteredPixel)) {
            float prevReservoirConfidence = ScatterTemporalResampling_load_previous_reservoir_confidence(scatteredPixel);
            m2 *= lt_scatter_confidence_mis_weight(prevReservoirConfidence);
        } else {
            m2 = 0.0f;
        }

        float denominator = m1 + m2;
        currSampleMIS = (denominator > 0.0f) ? (m1 / denominator) : 0.0f;
    }

    bool currSelected = lt_scatter_add_sample_from_reservoir(
        dstReservoir,
        dstConfidence,
        currSampleMIS,
        currIntegrand,
        1.0f,
        currUCW,
        currReservoirConfidence,
        currReservoir,
        sg
    );
    dstReconnectionData = currSelected ? currReconnectionDataLocal : dstReconnectionData;

    float newConfidence = dstConfidence;

    uint numReservoirs = lt_reproject_temporal_samples_cell_counter_value(reservoirIdx);
    uint cellOffset = lt_scatter_temporal_resampling_cell_offset_value(reservoirIdx);
    for (uint i = 0u; i < numReservoirs; ++i) {
        ivec2 scatteredPixel = ivec2(lt_scatter_temporal_resampling_load_sorted_reservoir(cellOffset + i));
        ivec2 previousReservoirPixel = ScatterTemporalResampling_previous_reservoir_pixel(scatteredPixel);
        RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
            lt_build_restir_di_parameters().reservoirBufferParams,
            uvec2(previousReservoirPixel)
        );
        ReconnectionData prevReconnectionData = RestirDI_loadPreviousFrameReconnection(previousReservoirPixel);
        float prevReservoirConfidence = ScatterTemporalResampling_load_previous_reservoir_confidence(scatteredPixel);
        if (!RAB_IsSurfaceValid(surface) || !any(greaterThan(PathReservoir_getIntegrand(prevReservoir), vec3(0.0f)))) {
            continue;
        }

        ShiftedPathData shiftedPrev = scatterReprojectionShift(
            sg,
            prevReconnectionData,
            prevReconnectionData.time,
            prevReconnectionData.firstHit,
            prevReconnectionData.lensSample,
            prevReservoir,
            true,
            false,
            true
        );
        ReconnectionData shiftedPrevReconnectionData = ReconnectionData_update(
            prevReconnectionData,
            shiftedPrev
        );
        RTXDI_DIReservoir shiftedReservoir = prevReservoir;
        PathReservoir_setSubPixel(shiftedReservoir, pixel, shiftedPrevReconnectionData.subPixel);

        float shiftedJacobian = lt_scatter_shift_jacobian_ratio(
            shiftedPrev.subPixelJacobian,
            shiftedPrev.secondaryPathJacobian,
            prevReconnectionData.subPixelJacobian,
            prevReconnectionData.secondaryPathJacobian
        );

        float prevSampleMIS = 0.0f;
        float m1 = lt_scatter_radiance_phat(shiftedPrev.radiance)
            * shiftedJacobian
            * lt_scatter_confidence_mis_weight(currReservoirConfidence);
        bool invalidM1 = isnan(m1);
        vec3 prevPHat = invalidM1 ? vec3(0.0f) : shiftedPrev.radiance;
        shiftedJacobian = invalidM1 ? 1.0f : shiftedJacobian;
        m1 = invalidM1 ? 0.0f : m1;

        float m2 = lt_scatter_radiance_phat(PathReservoir_getIntegrand(prevReservoir))
            * lt_scatter_confidence_mis_weight(prevReservoirConfidence);
        float denominator = m1 + m2;
        prevSampleMIS = (denominator > 0.0f) ? (m2 / denominator) : 0.0f;

        bool prevSelected = lt_scatter_add_sample_from_reservoir(
            dstReservoir,
            newConfidence,
            prevSampleMIS,
            prevPHat,
            shiftedJacobian,
            lt_scatter_compute_ucw(prevReservoir, PathReservoir_getIntegrand(prevReservoir)),
            prevReservoirConfidence,
            shiftedReservoir,
            sg
        );
        if (prevSelected) {
            dstReconnectionData = shiftedPrevReconnectionData;
        }
    }

    PathReservoir_setConfidence(dstReservoir, ScatterTemporalResampling_motion_vector_confidence(pixel, newConfidence));
    currReconnectionData = dstReconnectionData;
    return dstReservoir;
}
#endif

#endif
