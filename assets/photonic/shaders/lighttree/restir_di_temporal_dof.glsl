#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_DOF_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_DOF_GLSL

// Minimal temporal-stage DoF helper surface extracted for stage 2 gather.
// This keeps GatherTemporalResampling on the narrow temporal include graph
// without pulling the full spatial bridge / scatter implementation surface.

float lt_di_temporal_camera_aperture_radius()
{
    return 0.0f;
}

vec2 lt_di_temporal_depth_of_field_shift_probabilities(float circleOfConfusion)
{
    float gamma;
    if (circleOfConfusion <= 0.2f)
    {
        gamma = 1.0f;
    }
    else
    {
        gamma = 0.2f + 6.2f / (circleOfConfusion - 5.6f);
        gamma = clamp(gamma, 0.2f, 1.0f);
    }
    return vec2(gamma, 1.0f - gamma);
}

float lt_di_temporal_primary_hit_circle_of_confusion(vec3 primaryHitPosW)
{
    const float apertureRadius = 0.0f;
    if (apertureRadius <= 0.0f)
    {
        return 0.0f;
    }

    vec3 cameraForward = normalize(mat3(gbufferModelView) * vec3(0.0f, 0.0f, -1.0f));
    float cameraDepth = max(abs(dot(primaryHitPosW - world_camera_position, cameraForward)), 1e-6f);
    float focalDepth = 1.0f;
    float filmDepth = cameraDepth - focalDepth;
    float filmRadius = abs(apertureRadius / cameraDepth * filmDepth);
    return filmRadius;
}

float lt_di_temporal_env_map_circle_of_confusion()
{
    return 0.0f;
}

vec2 lt_di_temporal_resolve_dof_probabilities(RAB_Surface centerSurface)
{
    float circleOfConfusion = RAB_IsSurfaceValid(centerSurface)
        ? lt_di_temporal_primary_hit_circle_of_confusion(centerSurface.worldPos)
        : lt_di_temporal_env_map_circle_of_confusion();
    return lt_di_temporal_depth_of_field_shift_probabilities(circleOfConfusion);
}

#endif
