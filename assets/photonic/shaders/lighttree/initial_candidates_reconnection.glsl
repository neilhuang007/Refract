#ifndef PHOTONICS_INITIAL_CANDIDATES_RECONNECTION_GLSL
#define PHOTONICS_INITIAL_CANDIDATES_RECONNECTION_GLSL

float InitialCandidates_computeSubPixelJacobianRaw(
    vec3 primaryHitPos,
    vec3 primaryHitNormal,
    vec3 cameraPos,
    vec3 cameraForward)
{
    vec3 toHit;
    float dist;
    vec3 rayDir;
    float cosNormal;
    float cosSensor;
    float jacobian;

    toHit = primaryHitPos - cameraPos;
    dist = length(toHit);
    if (dist < 1e-6f) {
        return 1.0f;
    }

    rayDir = toHit / dist;
    cosNormal = abs(dot(-rayDir, primaryHitNormal));
    cosSensor = max(abs(dot(cameraForward, rayDir)), 1e-6f);
    jacobian = cosNormal / (dist * dist * cosSensor * cosSensor * cosSensor);
    return max(jacobian, 1e-10f);
}

float InitialCandidates_computeCurrentSubPixelJacobian(RAB_Surface surface)
{
    vec3 currCameraPos = world_camera_position;
    vec3 currCameraForward = normalize(mat3(gbufferModelView) * vec3(0.0f, 0.0f, -1.0f));
    return InitialCandidates_computeSubPixelJacobianRaw(
        surface.worldPos,
        surface.geoNormal,
        currCameraPos,
        currCameraForward
    );
}

ReservoirSplattingReconnectionData InitialCandidates_createReconnectionData(
    RAB_Surface surface,
    RTXDI_DIReservoir candidateReservoir,
    RAB_LightSample selectedLightSample,
    ivec2 pixel,
    float time,
    vec3 selectedIrradiance,
    vec3 selectedEarlyThroughput)
{
    float subPixelJacobian = InitialCandidates_computeCurrentSubPixelJacobian(surface);
    return ReconnectionData_build(
        surface,
        candidateReservoir,
        selectedLightSample,
        pixel,
        time,
        1.0f,
        subPixelJacobian,
        selectedIrradiance,
        selectedEarlyThroughput
    );
}

ReservoirSplattingReconnectionData InitialCandidates_buildSelectedReconnection(
    RAB_Surface surface,
    RTXDI_DIReservoir candidateReservoir,
    RAB_LightSample selectedLightSample,
    ivec2 pixel,
    float time,
    vec3 selectedIrradiance,
    vec3 selectedEarlyThroughput)
{
    return InitialCandidates_createReconnectionData(
        surface,
        candidateReservoir,
        selectedLightSample,
        pixel,
        time,
        selectedIrradiance,
        selectedEarlyThroughput
    );
}

RAB_LightSample InitialCandidates_decodeSelectedLocalLight(
    RTXDI_DIReservoir reservoir,
    RAB_Surface surface,
    bool fastRandomMode,
    out vec3 incidentRadiance,
    out vec3 earlyThroughput,
    out vec3 unshadowedIntegrand)
{
    incidentRadiance = vec3(0.0f);
    earlyThroughput = vec3(0.0f);
    unshadowedIntegrand = vec3(0.0f);

    Light selectedLight = lt_decode_reservoir_light(reservoir, false);
    if (selectedLight.index < 0) {
        return RAB_EmptyLightSample();
    }

    vec3 sampledPosition = lt_sample_light_position_from_uv(
        selectedLight,
        rtxdi_get_sample_uv(reservoir),
        lt_surface_ray_origin(lt_surface_rt_pos(surface), surface.geoNormal)
    );

    if (fastRandomMode)
    {
        RAB_LightSample selectedSample = light_sample_new_at_position_fast_random(
            selectedLight,
            sampledPosition,
            surface,
            incidentRadiance,
            unshadowedIntegrand
        );
        earlyThroughput = vec3(1.0f);
        return selectedSample;
    }

    return light_sample_new_at_position_with_radiometry(
        selectedLight,
        sampledPosition,
        surface,
        incidentRadiance,
        earlyThroughput,
        unshadowedIntegrand
    );
}

bool InitialCandidates_finalizeSelectedReservoir(
    RTXDI_DIInitialSamplingParameters initialSamplingParams,
    ivec2 pixel,
    RAB_Surface surface,
    inout RTXDI_DIReservoir reservoir,
    out ReservoirSplattingReconnectionData reconnectionData)
{
    reconnectionData = ReservoirSplattingReconnectionData_init();
    if (!RAB_IsSurfaceValid(surface) || !RTXDI_IsValidDIReservoir(reservoir))
    {
        reservoir = RTXDI_EmptyDIReservoir();
        return false;
    }

    bool fastRandomMode = initialSamplingParams.localLightSamplingMode
        == uint(RTXDI_LOCAL_LIGHT_SAMPLING_FAST_RANDOM);
    vec3 incidentRadiance;
    vec3 earlyThroughput;
    vec3 unshadowedIntegrand;
    RAB_LightSample selectedLightSample = InitialCandidates_decodeSelectedLocalLight(
        reservoir,
        surface,
        fastRandomMode,
        incidentRadiance,
        earlyThroughput,
        unshadowedIntegrand
    );
    if (selectedLightSample.index < 0)
    {
        reservoir = RTXDI_EmptyDIReservoir();
        return false;
    }

    vec3 visibility = vec3(1.0f);
    if (initialSamplingParams.enableInitialVisibility != 0u && !fastRandomMode)
    {
        float visibilityHitDistance = 0.0f;
        visibility = lt_trace_final_visibility_with_offset(
            selectedLightSample,
            surface,
            0.0f,
            visibilityHitDistance
        );
    }

    vec3 selectedIrradiance = max(incidentRadiance * visibility, vec3(0.0f));
    vec3 selectedEarlyThroughput = max(earlyThroughput, vec3(0.0f));
    vec3 visibleIntegrand = max(selectedIrradiance * selectedEarlyThroughput, vec3(0.0f));
    float previousPHat = ph_luminance(max(PathReservoir_getIntegrand(reservoir), vec3(0.0f)));
    float visiblePHat = ph_luminance(visibleIntegrand);
    if (previousPHat <= 0.0f || visiblePHat <= 0.0f)
    {
        reservoir = RTXDI_EmptyDIReservoir();
        reconnectionData = ReservoirSplattingReconnectionData_init();
        return false;
    }

    float targetRatio = visiblePHat / previousPHat;
    PathReservoir_setIntegrand(reservoir, visibleIntegrand);
    PathReservoir_setTotalWeight(reservoir, PathReservoir_getTotalWeight(reservoir) * targetRatio);
    reservoir.targetPdf = visiblePHat;
    RTXDI_StoreVisibilityInDIReservoir(reservoir, visibility, false);

    reconnectionData = InitialCandidates_buildSelectedReconnection(
        surface,
        reservoir,
        selectedLightSample,
        pixel,
        lt_path_sample_time(reservoir.pathSample),
        selectedIrradiance,
        selectedEarlyThroughput
    );
    return true;
}

#endif
