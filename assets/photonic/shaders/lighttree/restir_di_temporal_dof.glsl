#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_DOF_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_DOF_GLSL

#include "/photonics/lighttree/restir_di_temporal_camera.glsl"

float computePrimaryHitCircleOfConfusion(vec3 x1)
{
    float lensRadius = lt_di_temporal_camera_aperture_radius();
    vec3 cameraW = lt_di_temporal_camera_w();
    vec3 camDir = normalize(cameraW);
    float camZ = dot(x1 - world_camera_position, camDir);
    float filmZ = camZ - length(cameraW);
    float filmRadius = abs(lensRadius / camZ * filmZ);
    float normalizedFilm = length(lt_di_temporal_camera_u() / viewWidth + lt_di_temporal_camera_v() / viewHeight);
    return filmRadius / normalizedFilm;
}

float computeEnvMapCircleOfConfusion()
{
    float lensRadius = lt_di_temporal_camera_aperture_radius();
    float normalizedFilm = length(lt_di_temporal_camera_u() / viewWidth + lt_di_temporal_camera_v() / viewHeight);
    return lensRadius / normalizedFilm;
}

vec2 computeDepthOfFieldGatherShiftProbabilities(float r)
{
    float gamma;
    if (r <= 0.2f)
    {
        gamma = 1.0f;
    }
    else
    {
        gamma = 0.2f + 6.2f / (r - 5.6f);
        gamma = clamp(gamma, 0.2f, 1.0f);
    }
    return vec2(gamma, 1.0f - gamma);
}

vec2 lt_di_temporal_resolve_dof_probabilities(RAB_Surface centerSurface)
{
    float circleOfConfusion = RAB_IsSurfaceValid(centerSurface)
        ? computePrimaryHitCircleOfConfusion(centerSurface.worldPos)
        : computeEnvMapCircleOfConfusion();
    return computeDepthOfFieldGatherShiftProbabilities(circleOfConfusion);
}

#endif
