#define PH_DECLARE_GI_IMAGES
#include "/photonics/photonics.glsl"
#include "/photonics/common/util.glsl"

// Dirty-region invalidation support for GI path.
// When restir.glsl is included first it already defines this guard + function;
// when common/lighting.glsl is used standalone (basic path) we need our own copy.
#ifndef PH_DIRTY_REGION_DEFINED
#define PH_DIRTY_REGION_DEFINED
uniform float light_blend_factor;
uniform int light_blend_region_count;
uniform vec3 light_blend_min;
uniform vec3 light_blend_max;
uniform vec3 light_blend_min_1;
uniform vec3 light_blend_max_1;
uniform vec3 light_blend_min_2;
uniform vec3 light_blend_max_2;
uniform vec3 light_blend_min_3;
uniform vec3 light_blend_max_3;
uniform vec3 light_blend_min_4;
uniform vec3 light_blend_max_4;
uniform vec3 light_blend_min_5;
uniform vec3 light_blend_max_5;
uniform vec3 light_blend_min_6;
uniform vec3 light_blend_max_6;
uniform vec3 light_blend_min_7;
uniform vec3 light_blend_max_7;

bool ph_dirty_region_contains(vec3 worldPosition, vec3 regionMin, vec3 regionMax) {
    bvec3 insideMin = greaterThanEqual(worldPosition, regionMin);
    bvec3 insideMax = lessThan(worldPosition, regionMax);
    return all(insideMin) && all(insideMax);
}

float ph_dirty_region_factor(vec3 worldPosition) {
    if (light_blend_factor <= 0.0f || light_blend_region_count <= 0) return 0.0f;
    if (ph_dirty_region_contains(worldPosition, light_blend_min, light_blend_max)) return light_blend_factor;
    if (light_blend_region_count <= 1) return 0.0f;
    if (ph_dirty_region_contains(worldPosition, light_blend_min_1, light_blend_max_1)) return light_blend_factor;
    if (light_blend_region_count <= 2) return 0.0f;
    if (ph_dirty_region_contains(worldPosition, light_blend_min_2, light_blend_max_2)) return light_blend_factor;
    if (light_blend_region_count <= 3) return 0.0f;
    if (ph_dirty_region_contains(worldPosition, light_blend_min_3, light_blend_max_3)) return light_blend_factor;
    if (light_blend_region_count <= 4) return 0.0f;
    if (ph_dirty_region_contains(worldPosition, light_blend_min_4, light_blend_max_4)) return light_blend_factor;
    if (light_blend_region_count <= 5) return 0.0f;
    if (ph_dirty_region_contains(worldPosition, light_blend_min_5, light_blend_max_5)) return light_blend_factor;
    if (light_blend_region_count <= 6) return 0.0f;
    if (ph_dirty_region_contains(worldPosition, light_blend_min_6, light_blend_max_6)) return light_blend_factor;
    if (light_blend_region_count <= 7) return 0.0f;
    return ph_dirty_region_contains(worldPosition, light_blend_min_7, light_blend_max_7) ? light_blend_factor : 0.0f;
}
#endif

void sample_handheld(out vec4 color) {
    if (any(notEqual(handheld_color, vec3(0.0f)))) {
        vec4 direction_vert_out = direction_transformation_matrix_in * vec4(left_handed ? 1.0f : -1.0f, -1.0f, 0.0f, 1.0f);
        direction_vert_out.w = 1.0f / direction_vert_out.w;
        direction_vert_out.xyz *= direction_vert_out.w;

        ray.origin = direction_vert_out.xyz + rt_camera_position;
        //                light_ray.origin.y = rt_camera_position.y - 0.5f;

        vec3 to_light = rt_pos - ray.origin;
        ray.direction = normalize(to_light);
        trace_ray(ray, true); // TODO: early terminate, if ray is too far away anyway

        float distance_squared = dot(to_light, to_light);
        float brightness = 2.1f / dot(vec2(1, distance_squared), vec2(0.9f, 0.1f));
        brightness = max(brightness, 0.02f);

        float hand_to_base_distance = distance(ray.origin, rt_pos);
        float hand_to_result_distance = distance(ray.origin, ray.result_position);
        brightness *= clamp(30.0f * (hand_to_result_distance - hand_to_base_distance + 0.05f), 0.0f, 1.0f);

        brightness *= dot(normal, -ray.direction);

        brightness *= (ph_h(frameCounter / 300.0f) * 0.1f + ph_h(frameCounter / 100.0f) * 0.05f) + 0.4f;

        color.xyz = brightness * handheld_color;
    } else {
        color.xyz = vec3(0.0f);
    }
}

// Shared diffuse-path integrator used both by the legacy hashed GI path and by
// the ReSTIR GI initial sample generation. Paths are sampled with a
// cosine-weighted hemisphere, so for the mod's demodulated diffuse convention
// the primary-surface BRDF/pdf factor cancels out and this function should
// return outgoing radiance from the sampled path directly.
vec3 ph_trace_surface_radiance(vec3 surfacePos, vec3 surfaceNormal, int sampleIndexBase, int remainingBounces) {
    vec3 throughput = vec3(1.0f);
    vec3 currentPos = surfacePos;
    vec3 currentNormal = surfaceNormal;
    vec3 viewDir = normalize(rt_camera_position - surfacePos);

    for (int bounce = 0; bounce < remainingBounces; bounce++) {
        if (bounce > 0) {
            float max_throughput = max(throughput.r, max(throughput.g, throughput.b));
            float survival_prob = clamp(max_throughput, 0.05f, 1.0f);
            if (ph_RandomFloat01(rng_state) > survival_prob) {
                return vec3(0.0f);
            }
            throughput /= survival_prob;
        }

        lightEmittance = vec3(0.0f);
        ray.origin = currentPos + 0.1f * currentNormal;
        vec4 materialData = texelFetch(radiosity_material, tex_coord, 0);
        float roughness = clamp(materialData.x, 0.04f, 1.0f);
        float metalness = clamp(materialData.y, 0.0f, 1.0f);
        ray.direction = ph_sample_brdf_direction(currentNormal, viewDir, albedo, roughness, metalness, tex_coord, sampleIndexBase + bounce);

        breakOnEmpty = true;
        trace_ray(ray, true);
        breakOnEmpty = false;

        throughput *= result_tint_color;
        if (!ray.result_hit && !ray_iteration_bound_reached) {
            return ph_clamp_indirect_radiance(throughput * indirect_light_color);
        }
        if (dot(lightEmittance, lightEmittance) > 0.0f) {
            return ph_clamp_indirect_radiance(throughput * lightEmittance);
        }

        throughput *= ray.result_color;
        currentPos = ray.result_position;
        currentNormal = ray.result_normal;
        viewDir = -ray.direction;
    }

    return vec3(0.0f);
}

vec3 ph_sample_indirect_impl() {
    return ph_trace_surface_radiance(rt_pos, block_normal, 0, 2);
}

void ph_seed_indirect_cache(vec3 samplePosition, vec3 sampleNormal, vec3 color) {
    color = ph_clamp_indirect_radiance(color);
    ivec3 write = ph_write(samplePosition, sampleNormal, modelview_projection, world_camera_position);
    if (write == ivec3(NULL)) {
        return;
    }

    uint w = imageAtomicAdd(gi_w, write, uint(1));
    if (w == 0) {
        ivec3 read = ph_read(samplePosition, sampleNormal, previous_modelview_projection, previous_world_camera_position);

        vec4 result = vec4(0.0f);
        if (read != ivec3(NULL)) {
            result.x += imageLoad(gi_x, read).x / 1024.0f;
            result.y += imageLoad(gi_y, read).x / 1024.0f;
            result.z += imageLoad(gi_z, read).x / 1024.0f;
            result.w = imageLoad(gi_w, read).x;
        }

        float localBlend = ph_dirty_region_factor(samplePosition);
        float historyDecay;
        if (localBlend > 0.5f) {
            historyDecay = mix(0.5f, 0.0f, (localBlend - 0.5f) * 2.0f);
        } else if (localBlend > 0.0f) {
            historyDecay = mix(0.9f, 0.5f, localBlend * 2.0f);
        } else if (result.w < 32.0f) {
            historyDecay = mix(0.9f, 0.95f, result.w / 32.0f);
        } else if (result.w < 256.0f) {
            historyDecay = mix(0.95f, 0.985f, (result.w - 32.0f) / 224.0f);
        } else {
            historyDecay = 0.985f;
        }
        result *= historyDecay;

        imageAtomicAdd(gi_x, write, uint(result.x * 1024.0f));
        imageAtomicAdd(gi_y, write, uint(result.y * 1024.0f));
        imageAtomicAdd(gi_z, write, uint(result.z * 1024.0f));
        imageAtomicAdd(gi_w, write, uint(result.w));
    }

    if (w < 2048u) {
        imageAtomicAdd(gi_x, write, uint(max(color.x, 0.0f) * 1024.0f));
        imageAtomicAdd(gi_y, write, uint(max(color.y, 0.0f) * 1024.0f));
        imageAtomicAdd(gi_z, write, uint(max(color.z, 0.0f) * 1024.0f));
    } else {
        imageAtomicAdd(gi_w, write, uint(-1));
    }
}

void sample_indirect() {
    ph_seed_indirect_cache(world_pos, block_normal, ph_sample_indirect_impl());
}
