#ifndef PHOTONICS_RESERVOIR_SPLATTING_MULTI_SCATTER_TEMPORAL_RESAMPLING_GLSL
#define PHOTONICS_RESERVOIR_SPLATTING_MULTI_SCATTER_TEMPORAL_RESAMPLING_GLSL

#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"
#include "/photonics/lighttree/restir_di_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_spatial_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_shared.glsl"
#include "/photonics/lighttree/restir_di_temporal_shift_mapping.glsl"
#include "/photonics/lighttree/restir_di_temporal.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_common.glsl"

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
    ivec2 previousReservoirPixel = ScatterTemporalResampling_previous_reservoir_pixel(scatteredPixel);
    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(previousReservoirPixel)
    );
    ScatterReconnectionData prevReconnectionData = RestirDI_loadPreviousFrameReconnection(previousReservoirPixel);
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
            * lt_scatter_confidence_mis_weight(currSample.confidence);
        bool invalidM1 = isnan(m1);
        prevPHat = invalidM1 ? vec3(0.0f) : shiftedPrev.radiance;
        shiftedJacobian = invalidM1 ? 1.0f : shiftedJacobian;
        m1 = invalidM1 ? 0.0f : m1;

        float prevReservoirConfidence = lt_scatter_reservoir_confidence(prevReservoir, prevReconnectionData);
        float m2 = lt_scatter_radiance_phat(prevIntegrand)
            * lt_scatter_confidence_mis_weight(prevReservoirConfidence);
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
    if (!currSample.hasPositivePHat)
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
    ivec2 previousReservoirPixel = ScatterTemporalResampling_previous_reservoir_pixel(scatteredPixel);
    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(previousReservoirPixel)
    );
    float prevReservoirConfidence = ScatterTemporalResampling_load_previous_reservoir_confidence(scatteredPixel);

    float m1 = lt_scatter_radiance_phat(PathReservoir_getIntegrand(currSample.reservoir))
        * lt_scatter_confidence_mis_weight(currSample.confidence);
    float m2 = lt_scatter_radiance_phat(shiftedCurr.radiance)
        * shiftedJacobian
        * lt_scatter_confidence_mis_weight(prevReservoirConfidence);
    m2 = isnan(m2) ? 0.0f : m2;

    float denominator = m1 + m2;
    return (denominator > 0.0f) ? (m1 / denominator) : 0.0f;
}

RTXDI_DIReservoir MultiScatterTemporalResampling_run(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        currReconnectionData = ReservoirSplattingReconnectionData_init();
        return RTXDI_EmptyDIReservoir();
    }
    currReconnectionData = ReservoirSplattingReconnectionData_init();

    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);

    RTXDI_RandomSamplerState sg = lt_init_random_sampler(uvec2(pixel), uint(frameCounter), 5u);
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

    float currSampleMIS = lt_MultiScatterTemporalResampling_current_sample_mis(currSample);
    bool currSelected = lt_scatter_add_sample_from_reservoir(
        dstReservoir,
        dstConfidence,
        currSampleMIS,
        PathReservoir_getIntegrand(currSample.reservoir),
        1.0f,
        lt_scatter_compute_ucw(currSample.reservoir, PathReservoir_getIntegrand(currSample.reservoir)),
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
                newConfidence,
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
