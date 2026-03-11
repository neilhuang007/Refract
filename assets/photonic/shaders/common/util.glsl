#ifndef PH_UTIL_INCLUDE
#define PH_UTIL_INCLUDE

const float ph_light_jitter_radius = 1.0f / 16.0f;

float rand_next_float() {
    return ph_RandomFloat01(rng_state);
}

int rand_next_int(float min, float max) {
    return int(min + (rand_next_float() * (max - min)));
}

const float F = 2.0f;

// Pulse function
float ph_g(float x) {
    return sin(F * 3.141592f * clamp(x, 0.0f, 1.0f / F));
}

// Noise
float ph_n(float x) {
    return 0.5f * sin(1000.0f * x) + 0.5f;
}

// Periodic function with random offset
float ph_h(float x) {
    return ph_g(fract(x) - (1.0f - 1.0f / F) * ph_n(floor(x)));
}

float ph_luminance(vec3 rgb) {
    return dot(rgb, vec3(0.2126f, 0.7152f, 0.0722f));
}

void jitter_sample_position(inout vec3 position) {
    vec3 light_position = floor(position) + 0.5f;

    // Fetch a blue noise value for this frame.
    vec2 rnd_sample      = vec2(rand_next_float(), rand_next_float());

    vec3 light_dir       = light_position - ray.origin;

    vec3 light_tangent   = normalize(cross(light_dir, normalize(vec3(0.0f, 1.0f, 1.0f))));
    vec3 light_bitangent = normalize(cross(light_tangent, light_dir));

    // calculate disk point
    float point_radius = ph_light_jitter_radius * sqrt(rnd_sample.x);

    float point_angle  = rnd_sample.y * 2.0f * 3.14159265f;
    vec2  disk_point   = vec2(point_radius * cos(point_angle), point_radius * sin(point_angle));

    position = light_position + disk_point.x * light_tangent + disk_point.y * light_bitangent;
}

bool is_bad_angle(vec3 world_pos, vec3 normal) {
    float dist = distance(floor(world_pos), floor(world_camera_position));
    return dot(normal, normalize(world_pos - world_camera_position)) > -0.2f && dist > 16.0f;
}
#endif
