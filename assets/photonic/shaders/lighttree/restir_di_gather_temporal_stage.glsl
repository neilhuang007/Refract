#ifndef PHOTONICS_RESTIR_DI_GATHER_TEMPORAL_STAGE_GLSL
#define PHOTONICS_RESTIR_DI_GATHER_TEMPORAL_STAGE_GLSL

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_GATHER_STAGE)

#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"
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
#ifndef temporal_gather_previous_reconnection0
#define temporal_gather_previous_reconnection0 temporal_gather_intermediate_reconnection0
#endif
#ifndef temporal_gather_previous_reconnection1
#define temporal_gather_previous_reconnection1 temporal_gather_intermediate_reconnection1
#endif
#ifndef temporal_gather_previous_reconnection2
#define temporal_gather_previous_reconnection2 temporal_gather_intermediate_reconnection2
#endif
#ifndef temporal_gather_previous_reconnection3
#define temporal_gather_previous_reconnection3 temporal_gather_intermediate_reconnection3
#endif
#ifndef temporal_gather_previous_reconnection4
#define temporal_gather_previous_reconnection4 temporal_gather_intermediate_reconnection4
#endif

float lt_scatter_radiance_phat(vec3 radiance)
{
    return ph_luminance(radiance);
}

float lt_scatter_compute_ucw(
    RTXDI_DIReservoir reservoir,
    vec3 storedIntegrand)
{
    float pHatStored = lt_scatter_radiance_phat(storedIntegrand);
    if (pHatStored <= 0.0f)
    {
        return 0.0f;
    }

    float totalWeight = max(reservoir.weightSum, 0.0f);
    if (totalWeight <= 0.0f)
    {
        return 0.0f;
    }

    float ucw = totalWeight / pHatStored;
    return (isnan(ucw) || isinf(ucw) || ucw < 0.0f) ? 0.0f : ucw;
}

bool lt_scatter_add_sample_from_reservoir(
    inout RTXDI_DIReservoir dstReservoir,
    inout float dstConfidence,
    float sampleMIS,
    vec3 integrand,
    float jacobian,
    float ucw,
    float sampleConfidence,
    RTXDI_DIReservoir sampleReservoir,
    inout RTXDI_RandomSamplerState rng)
{
    float samplePHat = lt_scatter_radiance_phat(integrand);
    float candidateWeight = max(sampleMIS, 0.0f)
        * samplePHat
        * max(ucw, 0.0f)
        * max(jacobian, 0.0f);
    if (isnan(candidateWeight) || isinf(candidateWeight) || candidateWeight < 0.0f)
    {
        candidateWeight = 0.0f;
    }

    PathReservoir_setTotalWeight(
        dstReservoir,
        PathReservoir_getTotalWeight(dstReservoir) + candidateWeight
    );

    bool selected = (candidateWeight > 0.0f)
        && RTXDI_IsValidDIReservoir(sampleReservoir)
        && (lt_next_random(rng) * PathReservoir_getTotalWeight(dstReservoir) < candidateWeight);
    if (selected)
    {
        dstReservoir.lightData = sampleReservoir.lightData;
        dstReservoir.uvData = sampleReservoir.uvData;
        dstReservoir.targetPdf = sampleReservoir.targetPdf;
        dstReservoir.packedVisibility = sampleReservoir.packedVisibility;
        dstReservoir.age = sampleReservoir.age;
        dstReservoir.spatialDistance = sampleReservoir.spatialDistance;
        PathReservoir_setIntegrand(dstReservoir, integrand);
        dstReservoir.pixelSampleUV = sampleReservoir.pixelSampleUV;
        dstReservoir.lensSampleUV = sampleReservoir.lensSampleUV;
        dstReservoir.pathSample = sampleReservoir.pathSample;
    }

    dstConfidence = min(
        SCATTER_RECONNECTION_CONFIDENCE_MAX,
        dstConfidence + scatter_clamp_reconnection_confidence(sampleConfidence)
    );

    return selected;
}

RAB_Surface GatherTemporalResampling_load_current_surface(ivec2 pixel)
{
    vec4 positionData = texelFetch(radiosity_position, pixel, 0);
    if (positionData.w == BACKGROUND_DEPTH)
    {
        return RAB_EmptySurface();
    }

    return lt_make_surface(
        positionData.xyz,
        texelFetch(radiosity_normal, pixel, 0).xyz,
        texelFetch(radiosity_mapped_normal, pixel, 0).xyz,
        clamp(texelFetch(radiosity_albedo, pixel, 0).rgb, vec3(0.04f), vec3(1.0f)),
        texelFetch(radiosity_material, pixel, 0),
        positionData.w
    );
}

RTXDI_DIReservoir GatherTemporalResampling_load_current_reservoir(
    ivec2 pixel)
{
    RTXDI_DIReservoir reservoir = RTXDI_EmptyDIReservoir();
    rtxdi_unpack_reservoir_at_surface(
        reservoir,
        texelFetch(radiosity_proposal_reservoirs, pixel, 0),
        texelFetch(radiosity_proposal_reservoir_samples, pixel, 0),
        texelFetch(radiosity_proposal_reservoir_meta, pixel, 0),
        RAB_EmptySurface(),
        false
    );
    return reservoir;
}

ReservoirSplattingReconnectionData GatherTemporalResampling_load_current_reconnection(
    ivec2 pixel,
    RTXDI_DIReservoir reservoir)
{
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

ReservoirSplattingReconnectionData GatherTemporalResampling_load_previous_temporal_reconnection(
    ivec2 pixel,
    RTXDI_DIReservoir reservoir)
{
    ReservoirSplattingReconnectionData reconnectionData;
    scatter_unpack_reconnection(
        texelFetch(temporal_gather_previous_reconnection0, pixel, 0),
        texelFetch(temporal_gather_previous_reconnection1, pixel, 0),
        texelFetch(temporal_gather_previous_reconnection2, pixel, 0),
        texelFetch(temporal_gather_previous_reconnection3, pixel, 0),
        texelFetch(temporal_gather_previous_reconnection4, pixel, 0),
        0.0f,
        0.0f,
        reconnectionData
    );
    RestirDI_restoreReconnectionRadiometry(pixel, true, reservoir, reconnectionData);
    return reconnectionData;
}

bool GatherTemporalResampling_load_current_sample(
    ivec2 pixel,
    out RTXDI_DIReservoir currReservoir,
    out ReservoirSplattingReconnectionData currReconnectionData,
    out float currConfidence)
{
    currReservoir = GatherTemporalResampling_load_current_reservoir(pixel);
    currReconnectionData = GatherTemporalResampling_load_current_reconnection(pixel, currReservoir);
    currConfidence = PathReservoir_getConfidence(currReservoir);
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
    prevReconnectionData = GatherTemporalResampling_load_previous_temporal_reconnection(pixel, prevReservoir);
    prevConfidence = PathReservoir_getConfidence(prevReservoir);
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
                currReservoir,
                true
            )
            : gatherLensVertexCopyShift(
                sg,
                currReconnectionData,
                GatherTemporalResampling_current_to_previous_time(currReconnectionData.time),
                shiftedPixel,
                currReconnectionData.lensSample,
                currReservoir,
                true
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
                prevReservoir,
                false
            )
            : gatherLensVertexCopyShift(
                sg,
                prevReconnectionData,
                prevReconnectionData.time,
                shiftedPixel,
                prevReconnectionData.lensSample,
                prevReservoir,
                false
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

    RAB_Surface centerSurface = GatherTemporalResampling_load_current_surface(pixel);
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
