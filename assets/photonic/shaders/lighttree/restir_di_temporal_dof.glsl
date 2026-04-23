#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_DOF_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_DOF_GLSL

uniform float ph_reservoir_splatting_camera_aperture_radius;
uniform float ph_reservoir_splatting_artificial_frame_time;

vec3 lt_di_temporal_camera_relative_world_from_ndc(
    vec2 ndc,
    mat4 projectionInverse,
    mat4 modelViewInverse,
    vec3 cameraPosition)
{
    vec4 viewPoint = projectionInverse * vec4(ndc, -1.0f, 1.0f);
    float viewW = (abs(viewPoint.w) > 1e-6f) ? viewPoint.w : 1.0f;
    vec3 viewPosition = viewPoint.xyz / viewW;
    vec3 worldPosition = (modelViewInverse * vec4(viewPosition, 1.0f)).xyz;
    return worldPosition - cameraPosition;
}

vec3 lt_di_temporal_current_camera_relative_world_from_ndc(vec2 ndc)
{
    return lt_di_temporal_camera_relative_world_from_ndc(
        ndc,
        gbufferProjectionInverse,
        gbufferModelViewInverse,
        world_camera_position
    );
}

vec3 lt_di_temporal_previous_camera_relative_world_from_ndc(vec2 ndc)
{
    return lt_di_temporal_camera_relative_world_from_ndc(
        ndc,
        inverse(gbufferPreviousProjection),
        inverse(gbufferPreviousModelView),
        previous_world_camera_position
    );
}

float lt_di_temporal_camera_aperture_radius()
{
    return ph_reservoir_splatting_camera_aperture_radius;
}

float lt_di_temporal_artificial_frame_time()
{
    return ph_reservoir_splatting_artificial_frame_time;
}

vec3 lt_di_temporal_camera_u()
{
    return lt_di_temporal_current_camera_relative_world_from_ndc(vec2(1.0f, 0.0f))
        - lt_di_temporal_current_camera_relative_world_from_ndc(vec2(0.0f, 0.0f));
}

vec3 lt_di_temporal_camera_v()
{
    return lt_di_temporal_current_camera_relative_world_from_ndc(vec2(0.0f, 1.0f))
        - lt_di_temporal_current_camera_relative_world_from_ndc(vec2(0.0f, 0.0f));
}

vec3 lt_di_temporal_camera_w()
{
    return lt_di_temporal_current_camera_relative_world_from_ndc(vec2(0.0f, 0.0f));
}

vec3 lt_di_temporal_previous_camera_u()
{
    return lt_di_temporal_previous_camera_relative_world_from_ndc(vec2(1.0f, 0.0f))
        - lt_di_temporal_previous_camera_relative_world_from_ndc(vec2(0.0f, 0.0f));
}

vec3 lt_di_temporal_previous_camera_v()
{
    return lt_di_temporal_previous_camera_relative_world_from_ndc(vec2(0.0f, 1.0f))
        - lt_di_temporal_previous_camera_relative_world_from_ndc(vec2(0.0f, 0.0f));
}

vec3 lt_di_temporal_previous_camera_w()
{
    return lt_di_temporal_previous_camera_relative_world_from_ndc(vec2(0.0f, 0.0f));
}

float computePrimaryHitCircleOfConfusion(vec3 x1)
{
    float lensRadius = lt_di_temporal_camera_aperture_radius();
    if (lensRadius <= 0.0f)
    {
        return 0.0f;
    }

    vec3 cameraW = lt_di_temporal_camera_w();
    vec3 camDir = normalize(cameraW);
    float camZ = dot(x1 - world_camera_position, camDir);
    if (abs(camZ) <= 1e-6f)
    {
        return 0.0f;
    }
    float filmZ = camZ - length(cameraW);
    float filmRadius = abs(lensRadius / camZ * filmZ);
    float normalizedFilm = length(
        lt_di_temporal_camera_u() / max(viewWidth, 1.0f)
        + lt_di_temporal_camera_v() / max(viewHeight, 1.0f)
    );
    return filmRadius / max(normalizedFilm, 1e-6f);
}

float computeEnvMapCircleOfConfusion()
{
    float lensRadius = lt_di_temporal_camera_aperture_radius();
    if (lensRadius <= 0.0f)
    {
        return 0.0f;
    }

    float normalizedFilm = length(
        lt_di_temporal_camera_u() / max(viewWidth, 1.0f)
        + lt_di_temporal_camera_v() / max(viewHeight, 1.0f)
    );
    return lensRadius / max(normalizedFilm, 1e-6f);
}

vec2 computeDepthOfFieldGatherShiftProbabilities(float r)
{
    float gamma = 0.2f + 6.2f / (r - 5.6f);
    gamma = (r <= 0.2f) ? 1.0f : clamp(gamma, 0.2f, 1.0f);
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
