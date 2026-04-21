#ifndef PHOTONICS_DI_INITIAL_CANDIDATES_RECONNECTION_GLSL
#define PHOTONICS_DI_INITIAL_CANDIDATES_RECONNECTION_GLSL

float computeCurrentSubPixelJacobian(RAB_Surface surface)
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

ReservoirSplattingReconnectionData buildInitialSelectedReconnection(
    RAB_Surface surface,
    RTXDI_DIReservoir reservoir,
    RAB_LightSample selectedLightSample,
    ivec2 pixel,
    vec3 visibilityRgb)
{
    float subPixelJacobian = computeCurrentSubPixelJacobian(surface);
    ReservoirSplattingReconnectionData reconnectionData = scatter_build_reconnection(
        surface,
        reservoir,
        selectedLightSample,
        pixel,
        1.0f,
        subPixelJacobian
    );
    reconnectionData.irradiance = visibilityRgb;
    reconnectionData.earlyThroughput = visibilityRgb;
    return reconnectionData;
}

#endif
