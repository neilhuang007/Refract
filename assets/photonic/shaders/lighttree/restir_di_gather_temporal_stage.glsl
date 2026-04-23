#ifndef PHOTONICS_RESTIR_DI_GATHER_TEMPORAL_STAGE_GLSL
#define PHOTONICS_RESTIR_DI_GATHER_TEMPORAL_STAGE_GLSL

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_GATHER_STAGE)

#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"
#include "/photonics/lighttree/restir_di_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_shared.glsl"
#include "/photonics/lighttree/restir_di_temporal_dof.glsl"
#include "/photonics/lighttree/restir_di_temporal_shift_mapping.glsl"

#ifndef temporal_gather_previous_reservoir_data
#define temporal_gather_previous_reservoir_data temporal_gather_intermediate_reservoir_data
#endif
#ifndef temporal_gather_previous_reservoir_sample
#define temporal_gather_previous_reservoir_sample temporal_gather_intermediate_reservoir_sample
#endif
#ifndef temporal_gather_previous_reservoir_meta
#define temporal_gather_previous_reservoir_meta temporal_gather_intermediate_reservoir_meta
#endif

RTXDI_DIReservoir GatherTemporalResampling_load_current_reservoir(
    ivec2 pixel)
{
    return RTXDI_LoadDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel),
        lt_build_restir_di_parameters().bufferIndices.initialSamplingOutputBufferIndex
    );
}

ReservoirSplattingReconnectionData GatherTemporalResampling_load_current_reconnection(
    ivec2 pixel)
{
    RTXDI_DIReservoir reservoir = GatherTemporalResampling_load_current_reservoir(pixel);
    ReservoirSplattingReconnectionData reconnectionData;
    scatter_unpack_reconnection(
        texelFetch(current_stage_reconnection0, pixel, 0),
        texelFetch(current_stage_reconnection1, pixel, 0),
        texelFetch(current_stage_reconnection2, pixel, 0),
        texelFetch(current_stage_reconnection3, pixel, 0),
        texelFetch(current_stage_reconnection4, pixel, 0),
        0.0f,
        0.0f,
        reconnectionData
    );
    RestirDI_restoreReconnectionRadiometry(pixel, false, reservoir, reconnectionData);
    return reconnectionData;
}

RTXDI_DIReservoir GatherTemporalResampling_load_previous_reservoir(ivec2 pixel)
{
    RTXDI_DIReservoir reservoir = RTXDI_EmptyDIReservoir();
    rtxdi_unpack_reservoir_at_surface(
        reservoir,
        texelFetch(temporal_gather_previous_reservoir_data, pixel, 0),
        texelFetch(temporal_gather_previous_reservoir_sample, pixel, 0),
        texelFetch(temporal_gather_previous_reservoir_meta, pixel, 0),
        RAB_EmptySurface(),
        false
    );
    return reservoir;
}

bool GatherTemporalResampling_load_current_sample(
    ivec2 pixel,
    out RTXDI_DIReservoir currReservoir,
    out ReservoirSplattingReconnectionData currReconnectionData,
    out float currConfidence)
{
    currReservoir = GatherTemporalResampling_load_current_reservoir(pixel);
    currReconnectionData = GatherTemporalResampling_load_current_reconnection(pixel);
    currConfidence = lt_scatter_reservoir_confidence(currReservoir, currReconnectionData);
    return RTXDI_IsValidDIReservoir(currReservoir)
        && ph_luminance(PathReservoir_getIntegrand(currReservoir)) > 0.0f;
}

bool GatherTemporalResampling_load_previous_sample(
    ivec2 pixel,
    out RTXDI_DIReservoir prevReservoir,
    out ReservoirSplattingReconnectionData prevReconnectionData,
    out float prevConfidence)
{
    prevReservoir = GatherTemporalResampling_load_previous_reservoir(pixel);
    prevReconnectionData = RestirDI_loadPreviousTemporalReconnection(pixel);
    prevConfidence = lt_scatter_reservoir_confidence(
        prevReservoir,
        prevReconnectionData
    );
    return RTXDI_IsValidDIReservoir(prevReservoir)
        && ph_luminance(PathReservoir_getIntegrand(prevReservoir)) > 0.0f;
}

float GatherTemporalResampling_current_to_previous_time(float time)
{
    return time + lt_di_temporal_artificial_frame_time();
}

float GatherTemporalResampling_confidence_weight(float confidence)
{
    return lt_restir_temporal_use_confidence_weights() ? confidence : 1.0f;
}

float GatherTemporalResampling_shifted_jacobian(
    ShiftedPathData shiftedPathData,
    ReservoirSplattingReconnectionData reconnectionData,
    bool primaryHitReconnection)
{
    if (primaryHitReconnection)
    {
        return (shiftedPathData.lensVertexJacobian * shiftedPathData.secondaryPathJacobian)
            / (reconnectionData.lensVertexJacobian * reconnectionData.secondaryPathJacobian);
    }

    return shiftedPathData.secondaryPathJacobian / reconnectionData.secondaryPathJacobian;
}

bool GatherTemporalResampling_add_current_sample(
    ivec2 pixel,
    inout RTXDI_DIReservoir dstReservoir,
    inout float dstConfidence,
    inout ReservoirSplattingReconnectionData dstReconnectionData,
    RTXDI_DIReservoir currReservoir,
    ReservoirSplattingReconnectionData currReconnectionData,
    float currConfidence,
    float prevConfidence,
    bool primaryHitReconnection,
    float shiftProbability,
    inout RTXDI_RandomSamplerState sg)
{
    float currSampleMIS = 0.0f;
    vec3 currPHat = vec3(0.0f);
    vec3 currIntegrand = PathReservoir_getIntegrand(currReservoir);
    if (any(greaterThan(currIntegrand, vec3(0.0f))))
    {
        currPHat = currIntegrand;

        GatherHelper gatherHelper = GatherHelper_init(pixel);
        vec2 floatingCoord = GatherHelper_getFloatingCoords(gatherHelper);
        vec2 shiftedPixel = floatingCoord + currReconnectionData.subPixel;
        ShiftedPathData shiftedCurr = primaryHitReconnection
            ? gatherPrimaryHitReconnectionShift(
                sg,
                currReconnectionData,
                GatherTemporalResampling_current_to_previous_time(currReconnectionData.time),
                shiftedPixel,
                currReconnectionData.firstHit,
                currReservoir
            )
            : gatherLensVertexCopyShift(
                sg,
                currReconnectionData,
                GatherTemporalResampling_current_to_previous_time(currReconnectionData.time),
                shiftedPixel,
                currReconnectionData.lensSample,
                currReservoir
            );
        float shiftedJacobian = GatherTemporalResampling_shifted_jacobian(
            shiftedCurr,
            currReconnectionData,
            primaryHitReconnection
        );

        float m1 = lt_scatter_radiance_phat(currIntegrand)
            * GatherTemporalResampling_confidence_weight(currConfidence);
        float m2 = lt_scatter_radiance_phat(shiftedCurr.radiance)
            * shiftedJacobian
            * GatherTemporalResampling_confidence_weight(prevConfidence)
            * shiftProbability;
        m2 = isnan(m2) ? 0.0f : m2;
        currSampleMIS = ((m1 + m2) > 0.0f) ? (m1 / (m1 + m2)) : 0.0f;
    }

    bool currSelected = lt_scatter_add_sample_from_reservoir(
        dstReservoir,
        dstConfidence,
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

bool GatherTemporalResampling_add_previous_sample(
    ivec2 pixel,
    inout RTXDI_DIReservoir dstReservoir,
    inout float dstConfidence,
    inout ReservoirSplattingReconnectionData dstReconnectionData,
    RTXDI_DIReservoir prevReservoir,
    ReservoirSplattingReconnectionData prevReconnectionData,
    float currConfidence,
    float prevConfidence,
    bool primaryHitReconnection,
    float shiftProbability,
    inout RTXDI_RandomSamplerState sg)
{
    float prevSampleMIS = 0.0f;
    vec3 prevPHat = vec3(0.0f);
    float shiftedJacobian = 1.0f;
    vec3 prevIntegrand = PathReservoir_getIntegrand(prevReservoir);
    if (any(greaterThan(prevIntegrand, vec3(0.0f))))
    {
        vec2 shiftedPixel = vec2(pixel) + PathReservoir_getSubPixel(prevReservoir, pixel);
        ShiftedPathData shiftedPrev = primaryHitReconnection
            ? gatherPrimaryHitReconnectionShift(
                sg,
                prevReconnectionData,
                prevReconnectionData.time,
                shiftedPixel,
                prevReconnectionData.firstHit,
                prevReservoir
            )
            : gatherLensVertexCopyShift(
                sg,
                prevReconnectionData,
                prevReconnectionData.time,
                shiftedPixel,
                prevReconnectionData.lensSample,
                prevReservoir
            );
        shiftedJacobian = GatherTemporalResampling_shifted_jacobian(
            shiftedPrev,
            prevReconnectionData,
            primaryHitReconnection
        );

        float m1 = lt_scatter_radiance_phat(shiftedPrev.radiance)
            * shiftedJacobian
            * GatherTemporalResampling_confidence_weight(currConfidence);
        prevPHat = isnan(m1) ? vec3(0.0f) : shiftedPrev.radiance;
        shiftedJacobian = isnan(m1) ? 1.0f : shiftedJacobian;
        m1 = isnan(m1) ? 0.0f : m1;

        float m2 = lt_scatter_radiance_phat(prevIntegrand)
            * GatherTemporalResampling_confidence_weight(prevConfidence)
            * shiftProbability;
        prevSampleMIS = ((m1 + m2) > 0.0f) ? (m2 / (m1 + m2)) : 0.0f;

        prevReconnectionData = ReconnectionData_update(prevReconnectionData, shiftedPrev);
    }

    bool prevSelected = lt_scatter_add_sample_from_reservoir(
        dstReservoir,
        dstConfidence,
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

RTXDI_DIReservoir GatherTemporalResampling_run(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    RTXDI_RandomSamplerState sg = lt_init_random_sampler(uvec2(pixel), uint(frameCounter), 3u);
    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    float dstConfidence = 0.0f;
    currReconnectionData = ReservoirSplattingReconnectionData_init();

    RTXDI_DIReservoir currReservoir;
    ReservoirSplattingReconnectionData currentReconnectionData;
    float currConfidence = 0.0f;
    bool hasCurrentSample = GatherTemporalResampling_load_current_sample(
        pixel,
        currReservoir,
        currentReconnectionData,
        currConfidence
    );

    RTXDI_DIReservoir prevReservoir;
    ReservoirSplattingReconnectionData prevReconnectionData;
    float prevConfidence = 0.0f;
    bool hasPreviousSample = GatherTemporalResampling_load_previous_sample(
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
        if (hasCurrentSample)
        {
            GatherTemporalResampling_add_current_sample(
                pixel,
                dstReservoir,
                dstConfidence,
                currReconnectionData,
                currReservoir,
                currentReconnectionData,
                currConfidence,
                prevConfidence,
                false,
                depthOfFieldProbs.x,
                sg
            );
        }

        if (hasPreviousSample)
        {
            GatherTemporalResampling_add_previous_sample(
                pixel,
                dstReservoir,
                dstConfidence,
                currReconnectionData,
                prevReservoir,
                prevReconnectionData,
                currConfidence,
                prevConfidence,
                false,
                depthOfFieldProbs.x,
                sg
            );
        }

        PathReservoir_setConfidence(dstReservoir, dstConfidence);
    }

    if (hasDepthOfField && doPrimaryHitReconnection)
    {
        RTXDI_DIReservoir lensVertexCopyReservoir = dstReservoir;
        float lensVertexCopyConfidence = dstConfidence;
        ReservoirSplattingReconnectionData lensVertexCopyReconnectionData = currReconnectionData;
        dstReservoir = RTXDI_EmptyDIReservoir();
        dstConfidence = 0.0f;
        currReconnectionData = ReservoirSplattingReconnectionData_init();

        RTXDI_DIReservoir currentDomainReservoir = doLensVertexCopy
            ? lensVertexCopyReservoir
            : currReservoir;
        ReservoirSplattingReconnectionData currentDomainReconnectionData = doLensVertexCopy
            ? lensVertexCopyReconnectionData
            : currentReconnectionData;
        float currentDomainConfidence = doLensVertexCopy
            ? lensVertexCopyConfidence
            : currConfidence;
        bool hasCurrentDomainSample = doLensVertexCopy
            ? (RTXDI_IsValidDIReservoir(currentDomainReservoir)
                && ph_luminance(PathReservoir_getIntegrand(currentDomainReservoir)) > 0.0f)
            : hasCurrentSample;

        if (hasCurrentDomainSample)
        {
            GatherTemporalResampling_add_current_sample(
                pixel,
                dstReservoir,
                dstConfidence,
                currReconnectionData,
                currentDomainReservoir,
                currentDomainReconnectionData,
                currentDomainConfidence,
                prevConfidence,
                true,
                depthOfFieldProbs.y,
                sg
            );
        }

        if (hasPreviousSample)
        {
            GatherTemporalResampling_add_previous_sample(
                pixel,
                dstReservoir,
                dstConfidence,
                currReconnectionData,
                prevReservoir,
                prevReconnectionData,
                currentDomainConfidence,
                prevConfidence,
                true,
                depthOfFieldProbs.y,
                sg
            );
        }

        PathReservoir_setConfidence(dstReservoir, dstConfidence);
    }

    return dstReservoir;
}

#endif

#endif
