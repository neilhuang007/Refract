#ifndef PHOTONICS_RESTIR_DI_GATHER_TEMPORAL_STAGE_GLSL
#define PHOTONICS_RESTIR_DI_GATHER_TEMPORAL_STAGE_GLSL

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_GATHER_STAGE)

#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_shared.glsl"
#include "/photonics/lighttree/restir_di_temporal_dof.glsl"
#include "/photonics/lighttree/restir_di_temporal_shift_mapping.glsl"
#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"

float GatherTemporalResampling_p_hat(vec3 radiance)
{
    return ph_luminance(radiance);
}

float GatherTemporalResampling_ucw(
    RTXDI_DIReservoir reservoir,
    vec3 storedIntegrand)
{
    float pHatStored = GatherTemporalResampling_p_hat(storedIntegrand);
    if (pHatStored == 0.0f)
    {
        return 0.0f;
    }

    return reservoir.weightSum / pHatStored;
}

bool GatherTemporalResampling_add_sample_from_reservoir(
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
    float samplePHat = GatherTemporalResampling_p_hat(integrand);
    float candidateWeight = sampleMIS * samplePHat * ucw * jacobian;

    PathReservoir_setTotalWeight(
        dstReservoir,
        PathReservoir_getTotalWeight(dstReservoir) + candidateWeight
    );
    dstReservoir.M += max(sampleReservoir.M, 0.0f);

    bool selected = (lt_next_random(rng) * PathReservoir_getTotalWeight(dstReservoir) < candidateWeight);
    if (selected)
    {
        dstReservoir.lightData = sampleReservoir.lightData;
        dstReservoir.uvData = sampleReservoir.uvData;
        dstReservoir.targetPdf = samplePHat;
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

ReconnectionData GatherTemporalResampling_load_current_reconnection(
    ivec2 pixel,
    RTXDI_DIReservoir reservoir)
{
    ReconnectionData reconnectionData;
    scatter_unpack_reconnection(
        texelFetch(scatter_reconnection0, pixel, 0),
        texelFetch(scatter_reconnection1, pixel, 0),
        texelFetch(scatter_reconnection2, pixel, 0),
        texelFetch(scatter_reconnection3, pixel, 0),
        texelFetch(scatter_reconnection4, pixel, 0),
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
        texelFetch(temporal_gather_intermediate_reservoir_data, pixel, 0),
        texelFetch(temporal_gather_intermediate_reservoir_sample, pixel, 0),
        texelFetch(temporal_gather_intermediate_reservoir_meta, pixel, 0),
        RAB_EmptySurface(),
        false
    );
    return reservoir;
}

ReconnectionData GatherTemporalResampling_load_previous_temporal_reconnection(
    ivec2 pixel,
    RTXDI_DIReservoir reservoir)
{
    ReconnectionData reconnectionData;
    scatter_unpack_reconnection(
        texelFetch(temporal_gather_intermediate_reconnection0, pixel, 0),
        texelFetch(temporal_gather_intermediate_reconnection1, pixel, 0),
        texelFetch(temporal_gather_intermediate_reconnection2, pixel, 0),
        texelFetch(temporal_gather_intermediate_reconnection3, pixel, 0),
        texelFetch(temporal_gather_intermediate_reconnection4, pixel, 0),
        0.0f,
        0.0f,
        reconnectionData
    );
    RestirDI_restoreTemporalIntermediateReconnection(pixel, reservoir, reconnectionData);
    return reconnectionData;
}

bool GatherTemporalResampling_load_current_sample(
    ivec2 pixel,
    out RTXDI_DIReservoir currReservoir,
    out ReconnectionData currReconnectionData,
    out float currConfidence)
{
    currReservoir = GatherTemporalResampling_load_current_reservoir(pixel);
    currReconnectionData = GatherTemporalResampling_load_current_reconnection(pixel, currReservoir);
    currConfidence = PathReservoir_getConfidence(currReservoir);
    return any(greaterThan(PathReservoir_getIntegrand(currReservoir), vec3(0.0f)));
}

bool GatherTemporalResampling_load_previous_sample(
    ivec2 pixel,
    out RTXDI_DIReservoir prevReservoir,
    out ReconnectionData prevReconnectionData,
    out float prevConfidence)
{
    prevReservoir = GatherTemporalResampling_load_previous_reservoir(pixel);
    prevReconnectionData = GatherTemporalResampling_load_previous_temporal_reconnection(pixel, prevReservoir);
    prevConfidence = PathReservoir_getConfidence(prevReservoir);
    return any(greaterThan(PathReservoir_getIntegrand(prevReservoir), vec3(0.0f)));
}

float GatherTemporalResampling_shift_current_sample_time(float time)
{
    return time + lt_di_temporal_artificial_frame_time();
}

float GatherTemporalResampling_get_confidence_weight(float confidence)
{
    return lt_restir_temporal_use_confidence_weights() ? confidence : 1.0f;
}

float GatherTemporalResampling_get_shifted_jacobian(
    ShiftedPathData shiftedPathData,
    ReconnectionData reconnectionData,
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
    inout ReconnectionData dstReconnectionData,
    RTXDI_DIReservoir currReservoir,
    ReconnectionData currReconnectionData,
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
        vec2 shiftedPixel = floatingCoord + PathReservoir_getSubPixel(currReservoir, pixel);
        ShiftedPathData shiftedCurr = primaryHitReconnection
            ? gatherPrimaryHitReconnectionShift(
                sg,
                currReconnectionData,
                GatherTemporalResampling_shift_current_sample_time(currReconnectionData.time),
                shiftedPixel,
                currReconnectionData.firstHit,
                currReservoir,
                false,
                true
            )
            : gatherLensVertexCopyShift(
                sg,
                currReconnectionData,
                GatherTemporalResampling_shift_current_sample_time(currReconnectionData.time),
                shiftedPixel,
                currReconnectionData.lensSample,
                currReservoir,
                false,
                true
            );
        float shiftedJacobian = GatherTemporalResampling_get_shifted_jacobian(
            shiftedCurr,
            currReconnectionData,
            primaryHitReconnection
        );

        float m1 = GatherTemporalResampling_p_hat(currIntegrand)
            * GatherTemporalResampling_get_confidence_weight(currConfidence);
        float m2 = GatherTemporalResampling_p_hat(shiftedCurr.radiance)
            * shiftedJacobian
            * GatherTemporalResampling_get_confidence_weight(prevConfidence)
            * shiftProbability;
        m2 = isnan(m2) ? 0.0f : m2;
        currSampleMIS = ((m1 + m2) > 0.0f) ? (m1 / (m1 + m2)) : 0.0f;
    }

    bool currSelected = GatherTemporalResampling_add_sample_from_reservoir(
        dstReservoir,
        dstConfidence,
        currSampleMIS,
        currPHat,
        1.0f,
        GatherTemporalResampling_ucw(currReservoir, currPHat),
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
    inout ReconnectionData dstReconnectionData,
    RTXDI_DIReservoir prevReservoir,
    ReconnectionData prevReconnectionData,
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
                true,
                false
            )
            : gatherLensVertexCopyShift(
                sg,
                prevReconnectionData,
                prevReconnectionData.time,
                shiftedPixel,
                prevReconnectionData.lensSample,
                prevReservoir,
                true,
                false
            );
        shiftedJacobian = GatherTemporalResampling_get_shifted_jacobian(
            shiftedPrev,
            prevReconnectionData,
            primaryHitReconnection
        );

        float m1 = GatherTemporalResampling_p_hat(shiftedPrev.radiance)
            * shiftedJacobian
            * GatherTemporalResampling_get_confidence_weight(currConfidence);
        bool invalidM1 = isnan(m1);
        prevPHat = invalidM1 ? vec3(0.0f) : shiftedPrev.radiance;
        shiftedJacobian = invalidM1 ? 1.0f : shiftedJacobian;
        m1 = invalidM1 ? 0.0f : m1;

        float m2 = GatherTemporalResampling_p_hat(prevIntegrand)
            * GatherTemporalResampling_get_confidence_weight(prevConfidence)
            * shiftProbability;
        prevSampleMIS = ((m1 + m2) > 0.0f) ? (m2 / (m1 + m2)) : 0.0f;

        prevReconnectionData = invalidM1
            ? prevReconnectionData
            : ReconnectionData_update(prevReconnectionData, shiftedPrev);
    }

    bool prevSelected = GatherTemporalResampling_add_sample_from_reservoir(
        dstReservoir,
        dstConfidence,
        prevSampleMIS,
        prevPHat,
        shiftedJacobian,
        GatherTemporalResampling_ucw(prevReservoir, prevIntegrand),
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
    out ReconnectionData currReconnectionData)
{
    RTXDI_RandomSamplerState sg = lt_init_random_sampler(uvec2(pixel), uint(frameCounter), 3u);
    RTXDI_DIReservoir currReservoir;
    ReconnectionData currReconnection;
    float currConfidence = 0.0f;
    GatherTemporalResampling_load_current_sample(
        pixel,
        currReservoir,
        currReconnection,
        currConfidence
    );

    RTXDI_DIReservoir prevReservoir;
    ReconnectionData prevReconnectionData;
    float prevConfidence = 0.0f;
    GatherTemporalResampling_load_previous_sample(
        pixel,
        prevReservoir,
        prevReconnectionData,
        prevConfidence
    );

    const bool hasDepthOfField = lt_di_temporal_camera_aperture_radius() > 0.0f;
    vec2 depthOfFieldProbs = vec2(1.0f, 0.0f);
    if (hasDepthOfField)
    {
        RAB_Surface centerSurface = GatherTemporalResampling_load_current_surface(pixel);
        depthOfFieldProbs = lt_di_temporal_resolve_dof_probabilities(centerSurface);
    }

    const bool doLensVertexCopy = (depthOfFieldProbs.x > 0.0f);
    const bool doPrimaryHitReconnection = (depthOfFieldProbs.y > 0.0f);

    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    float dstConfidence = 0.0f;
    ReconnectionData dstReconnectionData = ReconnectionData_init();

    if (doLensVertexCopy)
    {
        GatherTemporalResampling_add_current_sample(
            pixel,
            dstReservoir,
            dstConfidence,
            dstReconnectionData,
            currReservoir,
            currReconnection,
            currConfidence,
            prevConfidence,
            false,
            depthOfFieldProbs.x,
            sg
        );

        GatherTemporalResampling_add_previous_sample(
            pixel,
            dstReservoir,
            dstConfidence,
            dstReconnectionData,
            prevReservoir,
            prevReconnectionData,
            currConfidence,
            prevConfidence,
            false,
            depthOfFieldProbs.x,
            sg
        );

        PathReservoir_setConfidence(dstReservoir, dstConfidence);
    }

    if (hasDepthOfField && doPrimaryHitReconnection)
    {
        RTXDI_DIReservoir lensVertexCopyReservoir = dstReservoir;
        float lensVertexCopyConfidence = dstConfidence;
        ReconnectionData lensVertexCopyReconnectionData = dstReconnectionData;
        dstReservoir = RTXDI_EmptyDIReservoir();
        dstConfidence = 0.0f;
        dstReconnectionData = ReconnectionData_init();

        RTXDI_DIReservoir currDomainReservoir = doLensVertexCopy
            ? lensVertexCopyReservoir
            : currReservoir;
        ReconnectionData currDomainReconnection = doLensVertexCopy
            ? lensVertexCopyReconnectionData
            : currReconnection;
        float currDomainConfidence = doLensVertexCopy
            ? lensVertexCopyConfidence
            : currConfidence;
        GatherTemporalResampling_add_current_sample(
            pixel,
            dstReservoir,
            dstConfidence,
            dstReconnectionData,
            currDomainReservoir,
            currDomainReconnection,
            currDomainConfidence,
            prevConfidence,
            true,
            depthOfFieldProbs.y,
            sg
        );

        GatherTemporalResampling_add_previous_sample(
            pixel,
            dstReservoir,
            dstConfidence,
            dstReconnectionData,
            prevReservoir,
            prevReconnectionData,
            currDomainConfidence,
            prevConfidence,
            true,
            depthOfFieldProbs.y,
            sg
        );

        PathReservoir_setConfidence(dstReservoir, dstConfidence);
    }

    currReconnectionData = dstReconnectionData;
    return dstReservoir;
}

#endif

#endif
