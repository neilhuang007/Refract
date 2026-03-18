#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 indirect_frag_out;
layout(location = 1) out vec4 indirect_variance_frag_out;
layout(location = 2) out vec4 handheld_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/common/lighting.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform float ph_debug_disable_temporal_reset;

const float lt_indirect_min_alpha = 0.01;
const float lt_indirect_max_history = 128.0;
const float lt_reproject_normal_threshold = 0.975;
const float lt_reproject_position_threshold_sq = 0.35;
const float lt_boiling_multiplier = 10.0;
const float lt_boiling_luma_floor = 0.01;

bool ph_surface_positions_compatible(vec3 currentPosition, vec3 previousPosition, float thresholdSq) {
    vec3 delta = previousPosition - currentPosition;
    return dot(delta, delta) <= thresholdSq;
}

float lt_luminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

vec2 lt_indirect_neighborhood_avg_luma(ivec2 previousUv) {
    ivec2 textureSizeValue = textureSize(prev_radiosity_indirect, 0);
    float accumulatedLuma = 0.0;
    float validCount = 0.0;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            ivec2 sampleUv = previousUv + ivec2(dx, dy);
            if (any(lessThan(sampleUv, ivec2(0))) || any(greaterThanEqual(sampleUv, textureSizeValue))) {
                continue;
            }

            vec4 sampleSignal = texelFetch(prev_radiosity_indirect, sampleUv, 0);
            if (sampleSignal.a <= 0.0 || any(isnan(sampleSignal))) {
                continue;
            }

            accumulatedLuma += lt_luminance(sampleSignal.rgb);
            validCount += 1.0;
        }
    }

    return vec2(validCount > 0.0 ? accumulatedLuma / validCount : 0.0, validCount);
}

bool lt_is_valid_reprojection(vec2 reprojectionUv, vec3 currentPosition, vec3 currentNormal) {
    ivec2 previousUv = ivec2(reprojectionUv);
    ivec2 textureSizeValue = textureSize(prev_radiosity_position, 0);
    if (any(lessThan(previousUv, ivec2(0))) || any(greaterThanEqual(previousUv, textureSizeValue))) {
        return false;
    }
    vec3 previousNormal = texelFetch(prev_radiosity_normal, previousUv, 0).xyz;
    if (dot(previousNormal, currentNormal) <= lt_reproject_normal_threshold) {
        return false;
    }
    vec3 previousPosition = texelFetch(prev_radiosity_position, previousUv, 0).xyz;
    return ph_surface_positions_compatible(currentPosition, previousPosition, lt_reproject_position_threshold_sq);
}

vec4 lt_build_handheld_stage() {
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
    return vec4(handheldLighting.rgb, 1.0f);
}

vec4 lt_build_indirect_stage(vec3 shadingPos, vec3 shadingNormal) {
    ivec3 inside = ivec3(lessThan(abs(fract(shadingPos) - 0.5f), vec3(0.48f)));
    bool onEdge = inside.x + inside.y + inside.z <= 1;

    vec3 indirectLighting = ph_trace_surface_radiance(shadingPos, shadingNormal, 0, 2);
    if (!onEdge) {
        ph_seed_indirect_cache(world_pos, block_normal, indirectLighting);
    }

    return vec4(indirectLighting, 1.0f);
}

void main() {
    if (!is_in_world()) {
        indirect_frag_out = vec4(0.0);
        indirect_variance_frag_out = vec4(0.0);
        handheld_frag_out = vec4(0.0);
        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);
    rt_pos = world_pos - world_offset;
    bad_angle = is_bad_angle(world_pos, block_normal);

    rng_state = uint(
        uint(floor(world_pos.x * 7.0f)) * uint(6199) +
        uint(floor(world_pos.y * 7.0f)) * uint(31357) +
        uint(floor(world_pos.z * 7.0f)) * uint(53611) +
        uint(floor(block_normal.x * 3.0f + 4.0f)) * uint(7919) +
        uint(floor(block_normal.y * 3.0f + 4.0f)) * uint(43391)
    ) | uint(1);

    vec4 currentIndirectSample = lt_build_indirect_stage(rt_pos, block_normal);
    vec3 currentIndirectRadiance = currentIndirectSample.rgb;
    bool hasCurrentSample = currentIndirectSample.a > 0.0;
    vec3 currentPosition = texelFetch(stage_radiosity_position, tex_coord, 0).xyz;
    vec3 currentNormal = texelFetch(stage_radiosity_normal, tex_coord, 0).xyz;
    vec3 currentAlbedo = clamp(texelFetch(colortex10, tex_coord, 0).rgb, vec3(0.04), vec3(1.0));

    handheld_frag_out = lt_build_handheld_stage();

    if (any(isnan(currentIndirectRadiance)) || any(isinf(currentIndirectRadiance))) {
        indirect_frag_out = vec4(0.0);
        indirect_variance_frag_out = vec4(0.0);
        return;
    }

    vec2 reprojectionUv = ph_reprojectf(
        previous_modelview_projection,
        currentPosition + currentNormal * 0.01,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    );

    bool lightReloadActive = light_reload && (ph_debug_disable_temporal_reset < 0.5f);
    if (lightReloadActive || !lt_is_valid_reprojection(reprojectionUv, currentPosition, currentNormal)) {
        if (!hasCurrentSample) {
            indirect_frag_out = vec4(0.0);
            indirect_variance_frag_out = vec4(0.0);
            return;
        }
        vec3 demodulatedCurrent = nrd_safe_demodulate(currentIndirectRadiance, nrd_compute_diffuse_demodulation(currentAlbedo));
        float luma = lt_luminance(demodulatedCurrent);
        indirect_frag_out = vec4(demodulatedCurrent, 1.0);
        indirect_variance_frag_out = vec4(luma, luma * luma, 0.0, 0.0);
        return;
    }

    ivec2 previousUv = ivec2(reprojectionUv);
    vec4 previousSignal = texelFetch(prev_radiosity_indirect, previousUv, 0);
    vec4 previousVariance = texelFetch(prev_radiosity_indirect_variance, previousUv, 0);

    if (previousSignal.a <= 0.0 || any(isnan(previousSignal)) || any(isinf(previousSignal))) {
        if (!hasCurrentSample) {
            indirect_frag_out = vec4(0.0);
            indirect_variance_frag_out = vec4(0.0);
            return;
        }
        vec3 demodulatedCurrent = nrd_safe_demodulate(currentIndirectRadiance, nrd_compute_diffuse_demodulation(currentAlbedo));
        float luma = lt_luminance(demodulatedCurrent);
        indirect_frag_out = vec4(demodulatedCurrent, 1.0);
        indirect_variance_frag_out = vec4(luma, luma * luma, 0.0, 0.0);
        return;
    }

    if (!hasCurrentSample) {
        indirect_frag_out = vec4(0.0);
        indirect_variance_frag_out = vec4(0.0);
        return;
    }

    vec3 demodulatedCurrent = nrd_safe_demodulate(currentIndirectRadiance, nrd_compute_diffuse_demodulation(currentAlbedo));
    float history = min(previousSignal.a + 1.0, lt_indirect_max_history);
    float alpha = max(1.0 / history, lt_indirect_min_alpha);

    vec2 neighborhoodLuma = lt_indirect_neighborhood_avg_luma(previousUv);
    float currentLuma = lt_luminance(demodulatedCurrent);
    float neighborhoodAvg = neighborhoodLuma.x;
    float neighborhoodWeight = neighborhoodLuma.y;
    float boilingThreshold = max(lt_boiling_luma_floor, neighborhoodAvg) * lt_boiling_multiplier;
    if (neighborhoodWeight > 0.0 && abs(currentLuma - neighborhoodAvg) > boilingThreshold) {
        alpha = max(alpha, 0.35);
    }

    vec3 blendedColor = mix(previousSignal.rgb, demodulatedCurrent, alpha);
    float blendedLuma = lt_luminance(blendedColor);
    float secondMoment = mix(previousVariance.y, currentLuma * currentLuma, alpha);

    indirect_frag_out = vec4(blendedColor, history);
    indirect_variance_frag_out = vec4(blendedLuma, secondMoment, max(secondMoment - blendedLuma * blendedLuma, 0.0), alpha);
}
