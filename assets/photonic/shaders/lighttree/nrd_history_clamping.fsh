#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_clamped_slow_out;
layout(location = 1) out vec4 nrd_clamped_fast_out;
layout(location = 2) out vec4 nrd_history_length_out;

#include "/photonics/common/header.glsl"

uniform sampler2D nrd_diff_slow_input;
uniform sampler2D nrd_diff_fast_input;
uniform sampler2D nrd_diff_noisy_input;
uniform sampler2D nrd_history_length_tex;

const float nrd_fast_history_clamping_sigma_scale = 2.0;
const float nrd_history_acceleration_amount = 0.3;
const float nrd_history_fix_frame_num = 3.0;
const float nrd_history_reset_amount = 0.5;
const float nrd_history_reset_temporal_sigma_scale = 0.5;
const float nrd_history_reset_spatial_sigma_scale = 0.5;
const float nrd_min_variance = 1e-6;
const float nrd_history_acceleration_scale = 10.0;

vec3 nrd_rgb_to_ycocg(vec3 color) {
    float y = dot(color, vec3(0.25, 0.5, 0.25));
    float co = color.r - color.b;
    float cg = color.g - 0.5 * (color.r + color.b);
    return vec3(y, co, cg);
}

vec3 nrd_ycocg_to_rgb(vec3 ycocg) {
    float y = ycocg.x;
    float co = ycocg.y;
    float cg = ycocg.z;
    float t = y - 0.5 * cg;
    float g = cg + t;
    float b = t - 0.5 * co;
    float r = b + co;
    return vec3(r, g, b);
}

float nrd_luminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

ivec2 nrd_clamp_texel(ivec2 sampleCoord, ivec2 texSize) {
    return clamp(sampleCoord, ivec2(0), texSize - 1);
}

float nrd_safe_history_length(vec4 encodedHistory) {
    return clamp(encodedHistory.r * 255.0, 0.0, 255.0);
}

vec3 nrd_clamp_ycocg(vec3 value, vec3 minValue, vec3 maxValue) {
    return clamp(value, minValue, maxValue);
}

float nrd_compute_variance(float secondMoment, float mean) {
    return max(secondMoment - mean * mean, nrd_min_variance);
}

void nrd_accumulate_fast_history_stats(
    ivec2 centerCoord,
    out vec3 meanValue,
    out vec3 sigmaValue,
    out float spatialLumaSigma
) {
    ivec2 texSize = textureSize(nrd_diff_fast_input, 0);
    vec3 sumValue = vec3(0.0);
    vec3 sumSquares = vec3(0.0);
    float lumaSum = 0.0;
    float lumaSquares = 0.0;
    float sampleCount = 0.0;

    for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
            ivec2 sampleCoord = nrd_clamp_texel(centerCoord + ivec2(dx, dy), texSize);
            vec3 sampleValue = nrd_rgb_to_ycocg(texelFetch(nrd_diff_fast_input, sampleCoord, 0).rgb);
            float sampleLuma = sampleValue.x;
            sumValue += sampleValue;
            sumSquares += sampleValue * sampleValue;
            lumaSum += sampleLuma;
            lumaSquares += sampleLuma * sampleLuma;
            sampleCount += 1.0;
        }
    }

    float invSampleCount = 1.0 / max(sampleCount, 1.0);
    meanValue = sumValue * invSampleCount;
    vec3 varianceValue = max(sumSquares * invSampleCount - meanValue * meanValue, vec3(0.0));
    sigmaValue = sqrt(varianceValue);

    float lumaMean = lumaSum * invSampleCount;
    float lumaVariance = max(lumaSquares * invSampleCount - lumaMean * lumaMean, 0.0);
    spatialLumaSigma = sqrt(lumaVariance);
}

vec3 nrd_apply_history_acceleration(
    vec3 historyColor,
    vec3 noisyColor,
    float accelerationAmount,
    float clampFactor
) {
    float blendAmount = clamp(accelerationAmount * clampFactor, 0.0, 1.0);
    return mix(historyColor, noisyColor, blendAmount);
}

float nrd_compute_reset_amount(
    vec3 slowYcocg,
    vec3 noisyYcocg,
    float temporalSigma,
    float spatialSigma
) {
    float divergence = abs(slowYcocg.x - noisyYcocg.x);
    float resetThreshold = temporalSigma * nrd_history_reset_temporal_sigma_scale
        + spatialSigma * nrd_history_reset_spatial_sigma_scale;
    if (divergence <= resetThreshold) {
        return 0.0;
    }

    float resetRange = max(resetThreshold, 1e-4);
    float normalizedDivergence = (divergence - resetThreshold) / resetRange;
    return clamp(normalizedDivergence * nrd_history_reset_amount, 0.0, 1.0);
}

void main() {
    if (!is_in_world()) {
        nrd_clamped_slow_out = vec4(0.0);
        nrd_clamped_fast_out = vec4(0.0);
        nrd_history_length_out = vec4(0.0);
        return;
    }

    vec4 slowInput = texelFetch(nrd_diff_slow_input, tex_coord, 0);
    vec4 fastInput = texelFetch(nrd_diff_fast_input, tex_coord, 0);
    vec4 noisyInput = texelFetch(nrd_diff_noisy_input, tex_coord, 0);
    vec4 historyLengthEncoded = texelFetch(nrd_history_length_tex, tex_coord, 0);
    float historyLength = nrd_safe_history_length(historyLengthEncoded);

    vec3 slowYcocg = nrd_rgb_to_ycocg(slowInput.rgb);
    vec3 fastYcocg = nrd_rgb_to_ycocg(fastInput.rgb);
    vec3 noisyYcocg = nrd_rgb_to_ycocg(noisyInput.rgb);

    vec3 meanValue;
    vec3 sigmaValue;
    float spatialLumaSigma;
    nrd_accumulate_fast_history_stats(tex_coord, meanValue, sigmaValue, spatialLumaSigma);

    vec3 minBox = meanValue - sigmaValue * nrd_fast_history_clamping_sigma_scale;
    vec3 maxBox = meanValue + sigmaValue * nrd_fast_history_clamping_sigma_scale;
    minBox = min(minBox, fastYcocg);
    maxBox = max(maxBox, fastYcocg);

    vec3 clampedSlowYcocg = nrd_clamp_ycocg(slowYcocg, minBox, maxBox);
    float clampDistance = length(slowYcocg - clampedSlowYcocg);
    float unclampedDistance = max(length(slowYcocg - fastYcocg), 1e-4);
    float clampFactor = clamp(clampDistance / unclampedDistance, 0.0, 1.0);

    float accelerationAmount = nrd_history_acceleration_scale
        * nrd_history_acceleration_amount
        * nrd_luminance(abs(fastInput.rgb - slowInput.rgb));
    vec3 acceleratedSlowRgb = nrd_apply_history_acceleration(
        nrd_ycocg_to_rgb(clampedSlowYcocg),
        noisyInput.rgb,
        accelerationAmount,
        clampFactor
    );
    vec3 acceleratedFastRgb = nrd_apply_history_acceleration(
        fastInput.rgb,
        noisyInput.rgb,
        accelerationAmount,
        clampFactor
    );

    vec3 acceleratedSlowYcocg = nrd_rgb_to_ycocg(acceleratedSlowRgb);
    float temporalSigma = sqrt(nrd_compute_variance(slowInput.a, slowYcocg.x));
    float resetAmount = nrd_compute_reset_amount(
        acceleratedSlowYcocg,
        noisyYcocg,
        temporalSigma,
        spatialLumaSigma
    );

    vec3 resolvedSlowRgb = mix(acceleratedSlowRgb, noisyInput.rgb, resetAmount);
    vec3 resolvedFastRgb = mix(acceleratedFastRgb, noisyInput.rgb, resetAmount);
    if (historyLength <= nrd_history_fix_frame_num) {
        resolvedSlowRgb = fastInput.rgb;
    }

    float noisyLuma = nrd_luminance(noisyInput.rgb);
    float resolvedSlowLuma = nrd_luminance(resolvedSlowRgb);
    float updatedSecondMoment = mix(
        slowInput.a,
        noisyLuma * noisyLuma,
        max(resetAmount, clampFactor)
    );
    updatedSecondMoment = max(updatedSecondMoment, resolvedSlowLuma * resolvedSlowLuma);

    nrd_clamped_slow_out = vec4(resolvedSlowRgb, updatedSecondMoment);
    nrd_clamped_fast_out = vec4(resolvedFastRgb, fastInput.a);
    nrd_history_length_out = historyLengthEncoded;
}
