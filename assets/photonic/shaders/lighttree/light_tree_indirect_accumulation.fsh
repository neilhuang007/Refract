#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 indirect_frag_out;
layout(location = 1) out vec4 indirect_variance_frag_out;
layout(location = 2) out vec4 handheld_frag_out;

#include "/photonics/common/header.glsl"
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

vec3 lt_load_current_indirect() {
    vec4 stageIndirect = texelFetch(stage_radiosity_indirect, tex_coord, 0);
    if (stageIndirect.a > 0.0 && !any(isnan(stageIndirect))) {
        return stageIndirect.rgb;
    }

    vec4 resolvedIndirect = texelFetch(radiosity_indirect_resolved, tex_coord, 0);
    if (resolvedIndirect.a > 0.0 && !any(isnan(resolvedIndirect))) {
        return resolvedIndirect.rgb;
    }

    vec4 previousIndirect = texelFetch(radiosity_indirect, tex_coord, 0);
    if (previousIndirect.a > 0.0 && !any(isnan(previousIndirect))) {
        vec3 albedo = clamp(texelFetch(colortex10, tex_coord, 0).rgb, vec3(0.04), vec3(1.0));
        return nrd_safe_remodulate(previousIndirect.rgb, nrd_compute_diffuse_demodulation(albedo));
    }

    return vec3(0.0);
}

void main() {
    if (!is_in_world()) {
        indirect_frag_out = vec4(0.0);
        indirect_variance_frag_out = vec4(0.0);
        handheld_frag_out = vec4(0.0);
        return;
    }

    vec3 currentIndirectRadiance = lt_load_current_indirect();
    vec4 currentHandheld = texelFetch(stage_radiosity_handheld, tex_coord, 0);
    vec3 currentPosition = texelFetch(stage_radiosity_position, tex_coord, 0).xyz;
    vec3 currentNormal = texelFetch(stage_radiosity_normal, tex_coord, 0).xyz;
    vec3 currentAlbedo = clamp(texelFetch(colortex10, tex_coord, 0).rgb, vec3(0.04), vec3(1.0));

    handheld_frag_out = currentHandheld;

    if (any(isnan(currentIndirectRadiance)) || any(isinf(currentIndirectRadiance))) {
        indirect_frag_out = vec4(0.0);
        indirect_variance_frag_out = vec4(0.0);
        return;
    }

    float currentRadianceLuma = lt_luminance(currentIndirectRadiance);
    bool hasCurrentSample = currentRadianceLuma > 1e-5;

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

    if (previousSignal.a <= 0.0 || any(isnan(previousSignal))) {
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
        indirect_frag_out = previousSignal;
        indirect_variance_frag_out = previousVariance;
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
