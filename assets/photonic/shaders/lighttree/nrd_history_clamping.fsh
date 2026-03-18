#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_clamped_slow_out;
layout(location = 1) out vec4 nrd_clamped_fast_out;
layout(location = 2) out vec4 nrd_history_length_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

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
const float nrd_history_acceleration_scale = 10.0;

ivec2 nrd_clamp_texel(ivec2 sampleCoord, ivec2 texSize) {
    return clamp(sampleCoord, ivec2(0), texSize - 1);
}

void nrd_accumulate_fast_history_stats(ivec2 centerCoord, out vec3 meanValue, out vec3 sigmaValue, out float spatialLumaSigma) {
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

vec3 nrd_apply_history_acceleration(vec3 historyColor, vec3 noisyColor, float accelerationAmount, float clampFactor) {
    float blendAmount = clamp(accelerationAmount * clampFactor, 0.0, 1.0);
    return mix(historyColor, noisyColor, blendAmount);
}

float nrd_compute_reset_amount(vec3 slowYcocg, vec3 noisyYcocg, float temporalSigma, float spatialSigma) {
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
    float historyLength = nrd_decoded_history(historyLengthEncoded);
    vec3 centerAlbedo = clamp(texelFetch(colortex10, tex_coord, 0).rgb, vec3(0.04), vec3(1.0));
    vec3 slowRadiance = nrd_safe_demodulate(slowInput.rgb, nrd_compute_diffuse_demodulation(centerAlbedo));
    vec3 fastRadiance = nrd_safe_demodulate(fastInput.rgb, nrd_compute_diffuse_demodulation(centerAlbedo));
    vec3 noisyRadiance = nrd_safe_demodulate(noisyInput.rgb, nrd_compute_diffuse_demodulation(centerAlbedo));

    vec3 slowYcocg = nrd_rgb_to_ycocg(slowRadiance);
    vec3 fastYcocg = nrd_rgb_to_ycocg(fastRadiance);
    vec3 noisyYcocg = nrd_rgb_to_ycocg(noisyRadiance);

    vec3 meanValue;
    vec3 sigmaValue;
    float spatialLumaSigma;
    nrd_accumulate_fast_history_stats(tex_coord, meanValue, sigmaValue, spatialLumaSigma);

    vec3 minBox = meanValue - sigmaValue * nrd_fast_history_clamping_sigma_scale;
    vec3 maxBox = meanValue + sigmaValue * nrd_fast_history_clamping_sigma_scale;
    minBox = min(minBox, fastYcocg);
    maxBox = max(maxBox, fastYcocg);

    vec3 clampedSlowYcocg = clamp(slowYcocg, minBox, maxBox);
    float clampDistance = length(slowYcocg - clampedSlowYcocg);
    float unclampedDistance = max(length(slowYcocg - fastYcocg), 1e-4);
    float clampFactor = clamp(clampDistance / unclampedDistance, 0.0, 1.0);

    float accelerationAmount = nrd_history_acceleration_scale
        * nrd_history_acceleration_amount
        * nrd_luminance(abs(fastRadiance - slowRadiance));
    vec3 acceleratedSlowRgb = nrd_apply_history_acceleration(nrd_ycocg_to_rgb(clampedSlowYcocg), noisyRadiance, accelerationAmount, clampFactor);
    vec3 acceleratedFastRgb = nrd_apply_history_acceleration(fastRadiance, noisyRadiance, accelerationAmount, clampFactor);

    vec3 acceleratedSlowYcocg = nrd_rgb_to_ycocg(acceleratedSlowRgb);
    float temporalSigma = sqrt(nrd_compute_variance(slowInput.a, slowYcocg.x));
    float resetAmount = nrd_compute_reset_amount(acceleratedSlowYcocg, noisyYcocg, temporalSigma, spatialLumaSigma);

    vec3 resolvedSlowRgb = mix(acceleratedSlowRgb, noisyRadiance, resetAmount);
    vec3 resolvedFastRgb = mix(acceleratedFastRgb, noisyRadiance, resetAmount);
    if (historyLength <= nrd_history_fix_frame_num) {
        resolvedSlowRgb = fastRadiance;
    }

    float noisyLuma = nrd_luminance(noisyRadiance);
    float resolvedSlowLuma = nrd_luminance(resolvedSlowRgb);
    float updatedSecondMoment = mix(slowInput.a, noisyLuma * noisyLuma, max(resetAmount, clampFactor));
    updatedSecondMoment = max(updatedSecondMoment, resolvedSlowLuma * resolvedSlowLuma);

    nrd_clamped_slow_out = vec4(nrd_safe_remodulate(resolvedSlowRgb, nrd_compute_diffuse_demodulation(centerAlbedo)), updatedSecondMoment);
    nrd_clamped_fast_out = vec4(nrd_safe_remodulate(resolvedFastRgb, nrd_compute_diffuse_demodulation(centerAlbedo)), fastInput.a);
    nrd_history_length_out = historyLengthEncoded;
}
