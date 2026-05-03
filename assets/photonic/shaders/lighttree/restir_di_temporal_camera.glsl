#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_CAMERA_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_CAMERA_GLSL

vec3 lt_di_temporal_camera_relative_world_from_ndc(
    vec2 ndc,
    mat4 projectionInverse,
    mat4 modelViewInverse,
    vec3 cameraWorldPosition)
{
    vec4 viewPoint = projectionInverse * vec4(ndc, -1.0f, 1.0f);
    float viewW = (abs(viewPoint.w) > 1e-6f) ? viewPoint.w : 1.0f;
    vec3 viewPosition = viewPoint.xyz / viewW;
    vec3 worldPosition = (modelViewInverse * vec4(viewPosition, 1.0f)).xyz;
    return worldPosition - cameraWorldPosition;
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

float lt_di_temporal_shutter_speed()
{
    return ph_reservoir_splatting_shutter_speed;
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

float lt_di_temporal_camera_tan_fov_y()
{
    float focalDistance = max(length(lt_di_temporal_camera_w()), 1e-6f);
    return length(lt_di_temporal_camera_v()) / focalDistance;
}

float lt_di_temporal_camera_aspect_ratio()
{
    return length(lt_di_temporal_camera_u()) / max(length(lt_di_temporal_camera_v()), 1e-6f);
}

float lt_di_temporal_camera_interval_duration()
{
    return max(lt_di_temporal_artificial_frame_time(), 1e-6f);
}

float lt_di_temporal_camera_interval_blend(float time)
{
    return clamp(time / lt_di_temporal_camera_interval_duration(), 0.0f, 1.0f);
}

vec3 lt_di_temporal_slerp_direction(vec3 currentDir, vec3 previousDir, float blend)
{
    vec3 a = normalize(currentDir);
    vec3 b = normalize(previousDir);
    float cosTheta = clamp(dot(a, b), -1.0f, 1.0f);
    if (cosTheta > 0.9995f)
    {
        return normalize(mix(a, b, blend));
    }

    float theta = acos(cosTheta);
    float sinTheta = sin(theta);
    if (abs(sinTheta) <= 1e-6f)
    {
        return normalize(mix(a, b, blend));
    }

    float w0 = sin((1.0f - blend) * theta) / sinTheta;
    float w1 = sin(blend * theta) / sinTheta;
    return normalize(w0 * a + w1 * b);
}

vec3 lt_di_temporal_camera_pos_at_time(float time)
{
    float blend = lt_di_temporal_camera_interval_blend(time);
    return world_camera_position * (1.0f - blend) + previous_world_camera_position * blend;
}

vec3 lt_di_temporal_camera_forward_at_time(float time)
{
    return lt_di_temporal_slerp_direction(
        lt_di_temporal_camera_w(),
        lt_di_temporal_previous_camera_w(),
        lt_di_temporal_camera_interval_blend(time)
    );
}

vec3 lt_di_temporal_camera_u_at_time(float time)
{
    vec3 forward = lt_di_temporal_camera_forward_at_time(time);
    vec3 up = (abs(dot(forward, vec3(0.0f, 1.0f, 0.0f))) > 0.999f)
        ? vec3(0.0f, 0.0f, 1.0f)
        : vec3(0.0f, 1.0f, 0.0f);
    vec3 right = normalize(cross(forward, up));
    float blend = lt_di_temporal_camera_interval_blend(time);
    float cameraULength = length(lt_di_temporal_camera_u()) * (1.0f - blend)
        + length(lt_di_temporal_previous_camera_u()) * blend;
    return right * cameraULength;
}

vec3 lt_di_temporal_camera_v_at_time(float time)
{
    vec3 forward = lt_di_temporal_camera_forward_at_time(time);
    vec3 right = normalize(lt_di_temporal_camera_u_at_time(time));
    float blend = lt_di_temporal_camera_interval_blend(time);
    float cameraVLength = length(lt_di_temporal_camera_v()) * (1.0f - blend)
        + length(lt_di_temporal_previous_camera_v()) * blend;
    return normalize(cross(right, forward)) * cameraVLength;
}

vec3 lt_di_temporal_camera_w_at_time(float time)
{
    float blend = lt_di_temporal_camera_interval_blend(time);
    float focalDistance = length(lt_di_temporal_camera_w()) * (1.0f - blend)
        + length(lt_di_temporal_previous_camera_w()) * blend;
    return lt_di_temporal_camera_forward_at_time(time) * focalDistance;
}

#endif
