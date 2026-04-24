#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_SCATTER_STAGE_PIPELINE_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_SCATTER_STAGE_PIPELINE_GLSL

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_STAGE)
#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
RTXDI_DIReservoir ScatterTemporalResampling_run(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    currReconnectionData = ReservoirSplattingReconnectionData_init();
    return RTXDI_EmptyDIReservoir();
}
#else
RTXDI_DIReservoir ScatterTemporalResampling_run(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    currReconnectionData = ReservoirSplattingReconnectionData_init();

    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);
    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return RTXDI_EmptyDIReservoir();
    }

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
    ReservoirSplattingReconnectionData dstReconnectionData = ReservoirSplattingReconnectionData_init();
    ReservoirSplattingReconnectionData currReconnectionDataLocal = currSample.reconnectionData;
    vec3 currIntegrand = PathReservoir_getIntegrand(currReservoir);
    float currReservoirConfidence = currSample.confidence;
    float currUCW = lt_scatter_compute_ucw(currReservoir, currIntegrand);

    float currSampleMIS = ScatterTemporalResampling_compute_curr_sample_mis(
        currSample,
        pixel,
        surface
    );
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
        float contributorConfidence = newConfidence;
        ScatterTemporalResampling_process_contributor(
            dstReservoir,
            dstReconnectionData,
            contributorConfidence,
            scatteredPixel,
            pixel,
            currReservoir,
            currReconnectionDataLocal,
            currReservoirConfidence,
            sg
        );
    }

    PathReservoir_setConfidence(dstReservoir, ScatterTemporalResampling_motion_vector_confidence(pixel, newConfidence));
    currReconnectionData = dstReconnectionData;
    return dstReservoir;
}
#endif
#endif

#endif
