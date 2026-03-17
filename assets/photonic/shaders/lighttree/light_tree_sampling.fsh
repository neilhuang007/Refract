#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 position_frag_out;
layout(location = 1) out vec4 normal_frag_out;
layout(location = 2) out vec4 mapped_normal_frag_out;
layout(location = 3) out vec4 direct_frag_out;
layout(location = 4) out vec4 handheld_frag_out;
layout(location = 5) out vec4 indirect_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/common/lighting.glsl"

uniform sampler2D stage_radiosity_position;
uniform sampler2D stage_radiosity_normal;
uniform float ph_direct_sample_budget_scale;
// Debug uniforms for isolating direct lighting issues
uniform float ph_debug_disable_shadow_rays;
uniform float ph_debug_lock_traversal_rng;

const int lt_sample_count = 16;
const int lt_min_sample_count = 2;
const int lt_temporal_history_samples = 2;
const int lt_spatial_history_samples = 2;
const float lt_temporal_reuse_cap = 20.0f;
const float lt_spatial_reuse_cap = 12.0f;
const float lt_reuse_normal_threshold = 0.975f;
const float lt_max_sample_luminance = 50.0f;
const float lt_history_position_threshold_sq = 0.35f;
const float lt_history_normal_threshold = 0.9f;
const float lt_history_bias = 0.85f;
const float lt_stable_luma_floor = 0.02f;
const float lt_history_color_acceptance = 2.25f;
const ivec2 lt_spatial_offsets[4] = ivec2[4](
    ivec2(-1, 0),
    ivec2(1, 0),
    ivec2(0, -1),
    ivec2(0, 1)
);


bool lt_positions_compatible(vec3 currentPosition, vec3 previousPosition) {
    return ph_surface_positions_compatible(currentPosition, previousPosition, lt_history_position_threshold_sq);
}

bool lt_valid_history_sample(vec4 historyDirect, vec3 currentPosition, vec3 currentNormal, vec3 historyPosition, vec3 historyNormal) {
    if (historyDirect.a <= 0.0f || any(isnan(historyDirect))) {
        return false;
    }
    if (dot(normalize(historyNormal), normalize(currentNormal)) < lt_reuse_normal_threshold) {
        return false;
    }
    return lt_positions_compatible(currentPosition, historyPosition);
}

vec3 lt_decode_history_radiance(vec4 historyDirect, float reuseCap) {
    float historyWeight = clamp(historyDirect.a, 1.0f, reuseCap);
    return historyDirect.rgb / historyWeight;
}

bool lt_history_matches_current(vec3 historyLighting, vec3 currentLighting) {
    float historyLuma = max(ph_luminance(historyLighting), lt_stable_luma_floor);
    float currentLuma = max(ph_luminance(currentLighting), lt_stable_luma_floor);
    float maxLuma = max(historyLuma, currentLuma);
    float minLuma = min(historyLuma, currentLuma);
    return maxLuma / minLuma <= lt_history_color_acceptance;
}

bool lt_load_temporal_history(vec3 shadingPos, vec3 shadingNormal, out vec3 historyDirect) {
    historyDirect = vec3(0.0f);
    vec2 reprojectionUv = ph_reprojectf(
        previous_modelview_projection,
        shadingPos + shadingNormal * 0.01f,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    );

    ivec2 previousUv = ivec2(reprojectionUv);
    ivec2 previousTextureSize = textureSize(prev_radiosity_position, 0);
    bool inBounds = all(greaterThanEqual(previousUv, ivec2(0)))
        && all(lessThan(previousUv, previousTextureSize));
    if (!inBounds) {
        return false;
    }

    vec3 previousPosition = texelFetch(prev_radiosity_position, previousUv, 0).xyz;
    vec3 previousNormal = texelFetch(prev_radiosity_normal, previousUv, 0).xyz;
    vec4 previousDirect = texelFetch(prev_radiosity_direct, previousUv, 0);
    if (!lt_valid_history_sample(previousDirect, shadingPos, shadingNormal, previousPosition, previousNormal)) {
        return false;
    }

    historyDirect = lt_decode_history_radiance(previousDirect, lt_temporal_reuse_cap);
    return ph_luminance(historyDirect) > 0.0f;
}

vec3 lt_load_spatial_history(vec3 shadingPos, vec3 shadingNormal) {
    vec3 accumulated = vec3(0.0f);
    float totalWeight = 0.0f;
    ivec2 textureSizeValue = textureSize(stage_radiosity_position, 0);

    for (int i = 0; i < lt_spatial_history_samples; i++) {
        ivec2 neighborCoord = tex_coord + lt_spatial_offsets[i];
        if (any(lessThan(neighborCoord, ivec2(0))) || any(greaterThanEqual(neighborCoord, textureSizeValue))) {
            continue;
        }

        vec3 neighborPosition = texelFetch(stage_radiosity_position, neighborCoord, 0).xyz;
        vec3 neighborNormal = texelFetch(stage_radiosity_normal, neighborCoord, 0).xyz;
        vec4 neighborDirect = texelFetch(prev_radiosity_direct, neighborCoord, 0);
        if (!lt_valid_history_sample(neighborDirect, shadingPos, shadingNormal, neighborPosition, neighborNormal)) {
            continue;
        }

        float weight = max(dot(normalize(neighborNormal), normalize(shadingNormal)), 0.0f);
        accumulated += lt_decode_history_radiance(neighborDirect, lt_spatial_reuse_cap) * weight;
        totalWeight += weight;
    }

    if (totalWeight <= 0.0f) {
        return vec3(0.0f);
    }
    return accumulated / totalWeight;
}

vec3 lt_trace_shadow_tint(int lightIndex, vec3 shadingPos, vec3 shadingNormal) {
    ray.result_hit = false;
    ray.result_position = vec3(0.0f);
    ray.result_normal = vec3(0.0f);

    Light light = load_light(lightIndex);
    if (floor(light.position) == floor(shadingPos)) {
        return vec3(1.0f);
    }

    ray.origin = shadingPos + shadingNormal * 0.02f;
    vec3 toLight = light.position - ray.origin;
    float lightDistance = length(toLight);
    if (lightDistance <= 1e-4f) {
        return vec3(1.0f);
    }

    ray.direction = toLight / lightDistance;
    ray_target = ivec3(light.position);
    RAY_ITERATION_COUNT = clamp(int(lightDistance * 2.0f), 8, 32);
    trace_ray(ray, true);
    RAY_ITERATION_COUNT = 100;

    if (!ray.result_hit) {
        return vec3(0.0f);
    }

    if (floor(light.position) != floor(ray.result_position)) {
        return vec3(0.0f);
    }

    return result_tint_color;
}

vec3 lt_sample_direct_lighting(vec3 shadingPos, vec3 shadingNormal, vec3 albedoColor, inout uint rng) {
    if (ph_light_count <= 0 || ph_light_tree_node_count <= 0) {
        return vec3(0.0f);
    }

    vec3 temporalHistory = vec3(0.0f);
    vec3 spatialHistory = lt_load_spatial_history(shadingPos, shadingNormal);
    bool hasTemporalHistory = lt_load_temporal_history(shadingPos, shadingNormal, temporalHistory);
    bool hasSpatialHistory = ph_luminance(spatialHistory) > 0.0f;

    float distanceToCamera = length(shadingPos - rt_camera_position);
    float distanceScale = clamp(1.0f - distanceToCamera / 96.0f, 0.35f, 1.0f);
    int freshSampleCount = int(round(float(lt_sample_count) * ph_direct_sample_budget_scale * distanceScale));
    if (hasTemporalHistory) {
        freshSampleCount -= lt_temporal_history_samples;
    }
    if (hasSpatialHistory) {
        freshSampleCount -= lt_spatial_history_samples;
    }
    freshSampleCount = clamp(freshSampleCount, lt_min_sample_count, lt_sample_count);

    vec3 directLighting = vec3(0.0f);
    bool hasBestShadowSeed = false;
    vec3 bestSeedPos = vec3(0.0f);
    vec3 bestSeedNormal = vec3(0.0f);
    vec3 bestSeedColor = vec3(0.0f);
    float bestSeedScore = 0.0f;
    for (int sampleIndex = 0; sampleIndex < freshSampleCount; sampleIndex++) {
        int leafIndex = lt_stochastic_traverse(shadingPos, rng);
        if (leafIndex < 0) {
            continue;
        }

        LightTreeNode leaf = lt_get_node(leafIndex);
        int lightIndex;
        float pdf;
        lt_select_light_from_leaf(leaf, shadingPos, rng, lightIndex, pdf);
        if (lightIndex < 0 || pdf <= 0.0f) {
            continue;
        }

        vec3 contribution = lt_evaluate_light(lightIndex, shadingPos, shadingNormal);
        if (ph_luminance(contribution) <= 0.0f) {
            continue;
        }

        vec3 transmissionTint = vec3(1.0f);
        if (ph_debug_disable_shadow_rays < 0.5f) {
            transmissionTint = lt_trace_shadow_tint(lightIndex, shadingPos, shadingNormal);
            if (ph_luminance(transmissionTint) <= 0.0f) {
                continue;
            }

            vec3 seedColor = contribution * transmissionTint;
            float seedScore = ph_luminance(seedColor);
            if (seedScore > bestSeedScore) {
                hasBestShadowSeed = true;
                bestSeedPos = ray.result_position;
                bestSeedNormal = ray.result_normal;
                bestSeedColor = seedColor;
                bestSeedScore = seedScore;
            }
        }

        vec3 sampleContribution = (albedoColor * contribution * transmissionTint) / pdf;
        float sampleLuma = dot(sampleContribution, vec3(0.2126f, 0.7152f, 0.0722f));
        if (sampleLuma > lt_max_sample_luminance) {
            sampleContribution *= lt_max_sample_luminance / sampleLuma;
        }
        directLighting += sampleContribution;
    }

    if (hasBestShadowSeed) {
        ph_seed_indirect_cache(bestSeedPos, normalize(bestSeedNormal), bestSeedColor);
    }

    vec3 freshLighting = directLighting / float(freshSampleCount);
    float blendWeight = 0.0f;
    vec3 reusedLighting = vec3(0.0f);
    if (hasTemporalHistory && lt_history_matches_current(temporalHistory, freshLighting)) {
        reusedLighting += temporalHistory;
        blendWeight += 1.0f;
    }
    if (hasSpatialHistory && lt_history_matches_current(spatialHistory, freshLighting)) {
        reusedLighting += spatialHistory;
        blendWeight += 1.0f;
    }
    if (blendWeight > 0.0f) {
        reusedLighting /= blendWeight;
        return mix(freshLighting, reusedLighting, lt_history_bias);
    }
    return freshLighting;
}

vec3 lt_sample_hemisphere(vec3 normal) {
    float z = ph_RandomFloat01(rng_state) * 2.0f - 1.0f;
    float a = ph_RandomFloat01(rng_state) * 2.0f * 3.14159265359f;
    float r = sqrt(1.0f - z * z);
    vec3 random_dir = vec3(r * cos(a), r * sin(a), z);
    return normalize(normal + random_dir);
}

vec3 lt_sample_indirect(vec3 shadingPos, vec3 shadingNormal) {
    vec3 totalIndirect = vec3(0.0f);
    float validSamples = 0.0f;

    for (int sampleIdx = 0; sampleIdx < 2; sampleIdx++) {
        vec3 throughput = vec3(1.0f);
        vec3 sampleResult = vec3(0.0f);
        bool gotResult = false;

        lightEmittance = vec3(0.0f);
        ray.origin = shadingPos + 0.1f * shadingNormal;
        ray.direction = lt_sample_hemisphere(shadingNormal);

        breakOnEmpty = true;
        trace_ray(ray, true);
        breakOnEmpty = false;

        throughput *= result_tint_color;
        if (!ray.result_hit && !ray_iteration_bound_reached) {
            sampleResult = ph_clamp_indirect_radiance(throughput * indirect_light_color);
            gotResult = true;
        } else if (dot(lightEmittance, lightEmittance) > 0.0f) {
            sampleResult = ph_clamp_indirect_radiance(throughput * lightEmittance);
            gotResult = true;
        } else {
            vec3 bouncePos = ray.result_position;
            vec3 bounceNormal = ray.result_normal;
            throughput *= ray.result_color;

            int leafIndex = lt_stochastic_traverse(bouncePos, rng_state);
            if (leafIndex >= 0) {
                LightTreeNode leaf = lt_get_node(leafIndex);
                int lightIndex;
                float pdf;
                lt_select_light_from_leaf(leaf, bouncePos, rng_state, lightIndex, pdf);
                if (lightIndex >= 0 && pdf > 0.0f) {
                    vec3 neeTerm = lt_evaluate_light(lightIndex, bouncePos, bounceNormal);
                    if (ph_luminance(neeTerm) > 0.0f) {
                        vec3 shadowTint = lt_trace_shadow_tint(lightIndex, bouncePos, bounceNormal);
                        if (ph_luminance(shadowTint) > 0.0f) {
                            vec3 neeContribution = (neeTerm * shadowTint) / pdf;
                            float neeLuma = ph_luminance(neeContribution);
                            if (neeLuma > lt_max_sample_luminance) {
                                neeContribution *= lt_max_sample_luminance / neeLuma;
                            }
                            sampleResult = ph_clamp_indirect_radiance(throughput * neeContribution);
                            gotResult = true;
                        }
                    }
                }
            }
        }

        if (gotResult) {
            totalIndirect += sampleResult;
            validSamples += 1.0f;
        }
    }

    return validSamples > 0.0f ? totalIndirect / validSamples : vec3(0.0f);
}

void main() {
    if (!is_in_world()) {
        position_frag_out = vec4(0.0f);
        normal_frag_out = vec4(0.0f);
        mapped_normal_frag_out = vec4(0.0f);
        direct_frag_out = vec4(0.0f);
        handheld_frag_out = vec4(0.0f);
        indirect_frag_out = vec4(0.0f);
        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);
    rt_pos = world_pos - world_offset;
    bad_angle = is_bad_angle(world_pos, block_normal);

    // Debug: freeze ALL RNG to pure spatial seed — no frameCounter anywhere
    if (ph_debug_freeze_rng > 0.5f) {
        rng_state = uint(uint(gl_FragCoord.x) * uint(1973) + uint(gl_FragCoord.y) * uint(9277)) | uint(1);
    }

    position_frag_out = vec4(world_pos, 1.0f);
    normal_frag_out = vec4(block_normal, 1.0f);
    mapped_normal_frag_out = vec4(normal, 1.0f);

    // Seed tree traversal from the stable per-pixel RNG instead of a heavily
    // quantized world-position hash. The quantized hash created coherent bands
    // across large surfaces, which showed up as striped direct lighting.
    uint lt_rng = rng_state;

    // Debug: when lock_traversal_rng is ON, also lock the global rng_state
    // so shadow rays are fully deterministic too — zero frame-to-frame variance
    if (ph_debug_lock_traversal_rng > 0.5f) {
        rng_state = lt_rng;
    }

    direct_frag_out = vec4(lt_sample_direct_lighting(rt_pos, block_normal, albedo, lt_rng), 1.0f);

    vec4 handheldLighting = vec4(0.0f);
    if (any(notEqual(handheld_color, vec3(0.0f)))) {
        vec4 handDirection = direction_transformation_matrix_in * vec4(left_handed ? 1.0f : -1.0f, -1.0f, 0.0f, 1.0f);
        handDirection.w = 1.0f / handDirection.w;
        handDirection.xyz *= handDirection.w;

        ray.origin = handDirection.xyz + rt_camera_position;
        vec3 toLight = rt_pos - ray.origin;
        ray.direction = normalize(toLight);
        trace_ray(ray, true);

        float distanceSquared = dot(toLight, toLight);
        float brightness = 2.1f / dot(vec2(1.0f, distanceSquared), vec2(0.9f, 0.1f));
        brightness = max(brightness, 0.02f);

        float handToBaseDistance = distance(ray.origin, rt_pos);
        float handToResultDistance = distance(ray.origin, ray.result_position);
        brightness *= clamp(30.0f * (handToResultDistance - handToBaseDistance + 0.05f), 0.0f, 1.0f);
        brightness *= dot(normal, -ray.direction);
        brightness *= 0.4f;

        vec3 handheldTint = vec3(1.0f);
        if (!ray.result_hit || floor(rt_pos) != floor(ray.result_position)) {
            handheldTint = vec3(0.0f);
        } else {
            handheldTint = result_tint_color;
        }

        handheldLighting.xyz = brightness * handheld_color * handheldTint;
    }
    handheld_frag_out = vec4(handheldLighting.rgb, 1.0f);

    // Use a separate view-stable RNG for indirect sampling.
    // This must NOT depend on lt_rng (which was modified by tree traversal and
    // is therefore sensitive to tree changes from light churn). Instead, derive
    // an independent seed from world position using different hash constants.
    rng_state = uint(
        uint(floor(world_pos.x * 7.0f)) * uint(6199) +
        uint(floor(world_pos.y * 7.0f)) * uint(31357) +
        uint(floor(world_pos.z * 7.0f)) * uint(53611) +
        uint(floor(block_normal.x * 3.0f + 4.0f)) * uint(7919) +
        uint(floor(block_normal.y * 3.0f + 4.0f)) * uint(43391)
    ) | uint(1);
    vec3 indirectLighting = lt_sample_indirect(rt_pos, block_normal);
    indirect_frag_out = vec4(indirectLighting, 1.0f);
}




