#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 indirect_frag_out;
layout(location = 1) out vec4 indirect_variance_frag_out;
layout(location = 2) out vec4 handheld_frag_out;

#include "/photonics/common/header.glsl"

uniform sampler2D stage_radiosity_indirect;
uniform sampler2D stage_radiosity_position;
uniform sampler2D stage_radiosity_normal;
uniform sampler2D stage_radiosity_handheld;

// Debug: when enabled, light_reload is ignored and temporal history is never wiped
uniform float ph_debug_disable_temporal_reset;

const float lt_indirect_min_alpha = 0.01;
const float lt_indirect_max_history = 128.0;
const float lt_reproject_normal_threshold = 0.975;
const float lt_reproject_position_threshold_sq = 0.35;
const float lt_boiling_multiplier = 10.0;
const float lt_boiling_luma_floor = 0.01;

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

void main() {
    if (!is_in_world()) {
        indirect_frag_out = vec4(0.0);
        indirect_variance_frag_out = vec4(0.0);
        handheld_frag_out = vec4(0.0);
        return;
    }

    vec4 currentIndirect = texelFetch(stage_radiosity_indirect, tex_coord, 0);
    vec4 currentHandheld = texelFetch(stage_radiosity_handheld, tex_coord, 0);
    vec3 currentPosition = texelFetch(stage_radiosity_position, tex_coord, 0).xyz;
    vec3 currentNormal = texelFetch(stage_radiosity_normal, tex_coord, 0).xyz;

    handheld_frag_out = currentHandheld;

    if (any(isnan(currentIndirect))) {
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
        // No valid history: if we have a current sample use it, otherwise output zero
        if (currentIndirect.a <= 0.0) {
            indirect_frag_out = vec4(0.0);
            indirect_variance_frag_out = vec4(0.0);
            return;
        }
        float luma = lt_luminance(currentIndirect.rgb);
        indirect_frag_out = vec4(currentIndirect.rgb, 1.0);
        indirect_variance_frag_out = vec4(luma, luma * luma, 0.0, 0.0);
        return;
    }

    ivec2 previousUv = ivec2(reprojectionUv);
    vec4 previousSignal = texelFetch(prev_radiosity_indirect, previousUv, 0);
    vec4 previousVariance = texelFetch(prev_radiosity_indirect_variance, previousUv, 0);

    if (previousSignal.a <= 0.0 || any(isnan(previousSignal))) {
        // No valid previous: if we have a current sample use it, otherwise output zero
        if (currentIndirect.a <= 0.0) {
            indirect_frag_out = vec4(0.0);
            indirect_variance_frag_out = vec4(0.0);
            return;
        }
        float luma = lt_luminance(currentIndirect.rgb);
        indirect_frag_out = vec4(currentIndirect.rgb, 1.0);
        indirect_variance_frag_out = vec4(luma, luma * luma, 0.0, 0.0);
        return;
    }

    // If current frame has no indirect sample, carry forward previous value unchanged
    if (currentIndirect.a <= 0.0) {
        indirect_frag_out = previousSignal;
        indirect_variance_frag_out = previousVariance;
        return;
    }

    float history = min(previousSignal.a + 1.0, lt_indirect_max_history);
    float alpha = max(1.0 / history, lt_indirect_min_alpha);

    vec2 neighborhoodLuma = lt_indirect_neighborhood_avg_luma(previousUv);
    float currentLuma = lt_luminance(currentIndirect.rgb);
    if (neighborhoodLuma.y > 0.0) {
        float boilingThreshold = lt_boiling_multiplier * max(neighborhoodLuma.x, lt_boiling_luma_floor);
        if (currentLuma > boilingThreshold) {
            currentIndirect.rgb = previousSignal.rgb;
            currentLuma = lt_luminance(currentIndirect.rgb);
        }
    }

    float previousLuma = lt_luminance(previousSignal.rgb);
    float expectedStdDev = sqrt(max(previousVariance.z, 1e-6));
    float lumaDelta = abs(currentLuma - previousLuma);
    float localLumaScale = max(max(currentLuma, previousLuma), 0.08);
    float normalizedDelta = lumaDelta / max(4.0 * expectedStdDev + 0.02 * localLumaScale, 1e-4);
    float changeResponse = clamp(normalizedDelta - 0.8, 0.0, 1.0);
    float antiLag = changeResponse * changeResponse;
    if (history < 4.0) {
        antiLag = 0.0;
    }

    float adaptiveAlpha = max(alpha, mix(alpha, 0.3, antiLag));
    vec3 blendedColor = mix(previousSignal.rgb, currentIndirect.rgb, adaptiveAlpha);

    vec2 blendedMoments = mix(previousVariance.xy, vec2(currentLuma, currentLuma * currentLuma), adaptiveAlpha);
    float variance = max(blendedMoments.y - blendedMoments.x * blendedMoments.x, 0.0);
    float confidence = clamp((history - 1.0) / max(lt_indirect_max_history - 1.0, 1.0), 0.0, 1.0);

    indirect_frag_out = vec4(blendedColor, history);
    indirect_variance_frag_out = vec4(blendedMoments.x, blendedMoments.y, variance, confidence);
}
