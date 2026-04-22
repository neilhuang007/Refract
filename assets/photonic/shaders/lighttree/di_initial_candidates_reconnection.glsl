#ifndef PHOTONICS_DI_INITIAL_CANDIDATES_RECONNECTION_GLSL
#define PHOTONICS_DI_INITIAL_CANDIDATES_RECONNECTION_GLSL

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
    ivec2 pixel)
{
    float subPixelJacobian = InitialCandidates_computeCurrentSubPixelJacobian(surface);
    return ReconnectionData_build(
        surface,
        candidateReservoir,
        selectedLightSample,
        pixel,
        1.0f,
        subPixelJacobian
    );
}

ReservoirSplattingReconnectionData InitialCandidates_buildSelectedReconnection(
    RAB_Surface surface,
    RTXDI_DIReservoir candidateReservoir,
    RAB_LightSample selectedLightSample,
    ivec2 pixel)
{
    return InitialCandidates_createReconnectionData(
        surface,
        candidateReservoir,
        selectedLightSample,
        pixel
    );
}

#endif
