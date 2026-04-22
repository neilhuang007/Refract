#include "/photonics/modifiers/attenuation_modifier.glsl"

#ifdef PH_ATTENUATION_MODIFIER_DISABLED
vec3 ph_compute_attenuation(
    Light light,
    vec3 to_light_dir, // not normalized
    vec3 sample_pos,
    vec3 source_pos,
    vec3 geometry_normal,
    vec3 texture_normal
) {
    vec3 normal_dir = normalize(to_light_dir);
    if (dot(normal_dir, geometry_normal) < 0.01f) return vec3(0f);

    float distance_squared = dot(to_light_dir, to_light_dir) * light.falloff;
    vec3 result_color = light.color * light.intensity / dot(vec2(1, distance_squared), light.attenuation);

    // Orientation: emission cone falloff matching the ReGIR proposal weight
    if (light.orientationSpread < 3.14159265359) {
        float axisAngle = acos(clamp(dot(light.emissionAxis, -normal_dir), -1.0, 1.0));
        result_color *= max(cos(max(axisAngle - light.orientationSpread, 0.0)), 0.0);
    }

    // Paper Eq. 3: f_a * |cos theta_i| -- use physical cosine falloff
    result_color *= max(dot(texture_normal, normal_dir), 0.0);

    return result_color;
}
#else
#define ph_compute_attenuation(light, to_light_dir, sample_pos, source_pos, geometry_normal, texture_normal) modify_attenuation(light, to_light_dir, sample_pos, source_pos, geometry_normal, texture_normal)
#endif
