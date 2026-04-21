#ifndef PHOTONICS_DI_INITIAL_CANDIDATES_RECONNECTION_GLSL
#define PHOTONICS_DI_INITIAL_CANDIDATES_RECONNECTION_GLSL

float InitialCandidates_computeCurrentSubPixelJacobian(RAB_Surface surface)
{
    vec3 currCameraPos = world_camera_position;
    vec3 currCameraForward = normalize(mat3(gbufferModelView) * vec3(0.0f, 0.0f, -1.0f));
    return scatter_compute_subpixel_jacobian(
        surface.worldPos,
        surface.geoNormal,
        currCameraPos,
        currCameraForward
    );
}

ReservoirSplattingReconnectionData InitialCandidates_createReconnectionData(
    RAB_Surface surface,
    RTXDI_DIReservoir reservoir,
    RAB_LightSample selectedLightSample,
    ivec2 pixel)
{
    float subPixelJacobian = InitialCandidates_computeCurrentSubPixelJacobian(surface);
    return ReconnectionData_build(
        surface,
        reservoir,
        selectedLightSample,
        pixel,
        1.0f,
        subPixelJacobian
    );
}

void InitialCandidates_updateReconnectionData(
    inout ReservoirSplattingReconnectionData reconnectionData,
    vec3 visibilityRgb)
{
    reconnectionData.irradiance = visibilityRgb;
    reconnectionData.earlyThroughput = visibilityRgb;
}

ReservoirSplattingReconnectionData InitialCandidates_buildSelectedReconnection(
    RAB_Surface surface,
    RTXDI_DIReservoir reservoir,
    RAB_LightSample selectedLightSample,
    ivec2 pixel,
    vec3 visibilityRgb)
{
    ReservoirSplattingReconnectionData reconnectionData = InitialCandidates_createReconnectionData(
        surface,
        reservoir,
        selectedLightSample,
        pixel
    );
    InitialCandidates_updateReconnectionData(reconnectionData, visibilityRgb);
    return reconnectionData;
}

#endif
