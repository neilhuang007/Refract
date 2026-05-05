#ifndef PHOTONICS_INITIAL_CANDIDATES_RECONNECTION_GLSL
#define PHOTONICS_INITIAL_CANDIDATES_RECONNECTION_GLSL

ReconnectionData InitialCandidates_createReconnectionData(
    RAB_Surface surface,
    RTXDI_DIReservoir candidateReservoir,
    RAB_LightSample selectedLightSample,
    ivec2 pixel,
    float time,
    vec3 selectedIrradiance,
    vec3 selectedEarlyThroughput)
{
    return ReconnectionData_build(
        surface,
        candidateReservoir,
        selectedLightSample,
        pixel,
        time,
        1.0f,
        scatter_resolve_subpixel_jacobian(
            surface,
            time,
            PathReservoir_getLensSample(candidateReservoir)
        ),
        selectedIrradiance,
        selectedEarlyThroughput
    );
}

ReconnectionData InitialCandidates_buildSelectedReconnection(
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
    RAB_LightSample selectedLightSample,
    vec3 selectedIrradiance,
    vec3 selectedEarlyThroughput,
    inout RTXDI_DIReservoir reservoir,
    out ReconnectionData reconnectionData)
{
    reconnectionData = ReconnectionData_init();
    if (!RAB_IsSurfaceValid(surface) || !RTXDI_IsValidDIReservoir(reservoir))
    {
        reservoir = RTXDI_EmptyDIReservoir();
        return false;
    }

    if (selectedLightSample.index < 0)
    {
        reservoir = RTXDI_EmptyDIReservoir();
        return false;
    }

    // Reference Reservoir.slang/PathReservoir stores `integrand` as the full
    // shaded radiance (f / p in PSS, including visibility) so that resolve is a
    // single `integrand * UCW`. We must therefore bake the traced visibility
    // into the candidate integrand here instead of carrying it as a separate
    // packedVisibility multiplier at resolve time.
    vec3 transmittance = vec3(1.0f);
    if (initialSamplingParams.enableInitialVisibility != 0u)
    {
        RAB_LightSample lightSampleCopy = selectedLightSample;
        transmittance = lt_trace_final_visibility_transmittance(lightSampleCopy, surface, 0.001f);
        if (ph_luminance(transmittance) <= 0.0f)
        {
            RTXDI_StoreVisibilityInDIReservoir(reservoir, vec3(0.0f), true);
            reconnectionData = ReconnectionData_init();
            return false;
        }
        RTXDI_StoreVisibilityInDIReservoir(reservoir, transmittance, true);
    }
    else
    {
        // No initial-visibility trace: keep the integrand unshadowed and let any
        // future final-visibility test apply transmittance separately.
        RTXDI_StoreVisibilityInDIReservoir(reservoir, vec3(1.0f), true);
    }

    selectedIrradiance = max(selectedIrradiance, vec3(0.0f));
    selectedEarlyThroughput = max(selectedEarlyThroughput, vec3(0.0f));
    vec3 selectedIntegrand = max(selectedIrradiance * selectedEarlyThroughput * transmittance, vec3(0.0f));
    float selectedPHat = ph_luminance(selectedIntegrand);
    if (selectedPHat <= 0.0f)
    {
        reservoir = RTXDI_EmptyDIReservoir();
        reconnectionData = ReconnectionData_init();
        return false;
    }

    PathReservoir_setIntegrand(reservoir, selectedIntegrand);
    reservoir.targetPdf = selectedPHat;

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
