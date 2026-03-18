#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 position_frag_out;
layout(location = 1) out vec4 normal_frag_out;
layout(location = 2) out vec4 mapped_normal_frag_out;
layout(location = 3) out vec4 reservoir_frag_out;
layout(location = 4) out vec4 direct_frag_out;
layout(location = 5) out vec4 handheld_frag_out;
layout(location = 6) out vec4 indirect_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/common/lighting.glsl"

uniform float ph_direct_sample_budget_scale;

const int lt_sample_count = 12;
const int lt_min_sample_count = 2;
const int lt_direct_cut_budget = 8;
const int lt_indirect_cut_budget = 6;
const float lt_max_sample_luminance = 50.0f;

vec4 lt_encode_direct_proposal(Reservoir reservoir) {
    if (!reservoir_is_valid(reservoir) || reservoir.weight_sum <= 0.0f || reservoir.samples <= 0.0f) {
        return reservoir_encode(reservoir_new());
    }

    reservoir_compute_weight(reservoir);
    return reservoir_encode(reservoir);
}

vec4 lt_build_direct_proposal(vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, inout uint rng) {
    if (ph_light_count <= 0 || ph_light_tree_node_count <= 0) {
        return reservoir_encode(reservoir_new());
    }

    float distanceToCamera = length(shadingPos - rt_camera_position);
    float distanceScale = clamp(1.0f - distanceToCamera / 96.0f, 0.35f, 1.0f);
    int freshSampleCount = int(round(float(lt_sample_count) * ph_direct_sample_budget_scale * distanceScale));
    freshSampleCount = clamp(freshSampleCount, lt_min_sample_count, lt_sample_count);

    int refinementBudget = clamp(freshSampleCount + 4, 6, lt_direct_cut_budget);
    LtCutResult cut = lt_build_candidate_cut(shadingPos, shadingNormal, mappedNormal, albedoColor, refinementBudget);
    if (cut.count <= 0 || cut.totalEstimate <= 0.0f) {
        return reservoir_encode(reservoir_new());
    }

    Reservoir reservoir = reservoir_new();
    for (int sampleIndex = 0; sampleIndex < freshSampleCount; sampleIndex++) {
        int lightIndex = -1;
        float sampledProposalPdf = 0.0f;
        if (!lt_sample_cut_node(cut, shadingPos, shadingNormal, mappedNormal, albedoColor, rng, lightIndex, sampledProposalPdf)) {
            continue;
        }
        if (lightIndex < 0) {
            continue;
        }

        float proposalPdf = lt_cut_light_pdf(cut, shadingPos, shadingNormal, mappedNormal, albedoColor, lightIndex);
        if (proposalPdf <= 0.0f) {
            continue;
        }

        LightSample smple = light_sample_decode(float(lightIndex), shadingPos, false);
        if (smple.index < 0 || smple.weight <= 0.0f) {
            continue;
        }

        reservoir_update(
            reservoir,
            smple,
            smple.weight / proposalPdf,
            1.0f
        );
    }

    return lt_encode_direct_proposal(reservoir);
}

vec3 lt_sample_hemisphere(vec3 normal) {
    float z = ph_RandomFloat01(rng_state) * 2.0f - 1.0f;
    float a = ph_RandomFloat01(rng_state) * 2.0f * 3.14159265359f;
    float r = sqrt(1.0f - z * z);
    vec3 random_dir = vec3(r * cos(a), r * sin(a), z);
    return normalize(normal + random_dir);
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
        return vec3(1.0f);
    }

    if (floor(light.position) != floor(ray.result_position)) {
        return vec3(0.0f);
    }

    return result_tint_color;
}

vec3 lt_evaluate_cut_radiance(LtCutResult cut, vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, vec3 throughput, inout uint rng) {
    if (cut.count <= 0 || cut.totalEstimate <= 0.0f) {
        return vec3(0.0f);
    }

    vec3 accumulated = vec3(0.0f);

    for (int sampleIndex = 0; sampleIndex < lt_min_sample_count; sampleIndex++) {
        int lightIndex = -1;
        float pdf = 0.0f;
        if (!lt_sample_cut_node(cut, shadingPos, shadingNormal, mappedNormal, albedoColor, rng, lightIndex, pdf)) {
            continue;
        }
        if (lightIndex < 0 || pdf <= 0.0f) {
            continue;
        }

        vec3 neeTerm = lt_evaluate_light(lightIndex, shadingPos, shadingNormal);
        if (ph_luminance(neeTerm) <= 0.0f) {
            continue;
        }

        vec3 shadowTint = lt_trace_shadow_tint(lightIndex, shadingPos, shadingNormal);
        if (ph_luminance(shadowTint) <= 0.0f) {
            continue;
        }

        vec3 neeContribution = (neeTerm * shadowTint) / pdf;
        float neeLuma = ph_luminance(neeContribution);
        if (neeLuma > lt_max_sample_luminance) {
            neeContribution *= lt_max_sample_luminance / neeLuma;
        }
        accumulated += throughput * neeContribution;
    }

    accumulated /= float(lt_min_sample_count);
    return ph_luminance(accumulated) > 0.0f ? ph_clamp_indirect_radiance(accumulated) : vec3(0.0f);
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

            vec3 bounceAlbedo = clamp(ray.result_color, vec3(0.0f), vec3(1.0f));
            LtCutResult bounceCut = lt_build_candidate_cut(bouncePos, bounceNormal, bounceNormal, bounceAlbedo, lt_indirect_cut_budget);
            if (bounceCut.count > 0) {
                sampleResult = lt_evaluate_cut_radiance(bounceCut, bouncePos, bounceNormal, bounceNormal, bounceAlbedo, throughput, rng_state);
                gotResult = ph_luminance(sampleResult) > 0.0f;
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
        reservoir_frag_out = vec4(0.0f);
        direct_frag_out = vec4(0.0f);
        handheld_frag_out = vec4(0.0f);
        indirect_frag_out = vec4(0.0f);
        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);
    rt_pos = world_pos - world_offset;
    bad_angle = is_bad_angle(world_pos, block_normal);

    if (ph_debug_freeze_rng > 0.5f) {
        rng_state = uint(uint(gl_FragCoord.x) * uint(1973) + uint(gl_FragCoord.y) * uint(9277)) | uint(1);
    }

    position_frag_out = vec4(world_pos, 1.0f);
    normal_frag_out = vec4(block_normal, 1.0f);
    mapped_normal_frag_out = vec4(normal, 1.0f);

    uint lt_rng = rng_state;
    if (ph_debug_lock_traversal_rng > 0.5f) {
        rng_state = lt_rng;
    }

    reservoir_frag_out = lt_build_direct_proposal(rt_pos, block_normal, normal, albedo, lt_rng);
    direct_frag_out = vec4(0.0f);

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
