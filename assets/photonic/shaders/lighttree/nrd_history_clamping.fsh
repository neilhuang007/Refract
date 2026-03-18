#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_clamped_slow_out;
layout(location = 1) out vec4 nrd_clamped_fast_out;
layout(location = 2) out vec4 nrd_history_length_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D direct_historyfix_output;
uniform sampler2D nrd_diff_fast_input;
uniform sampler2D nrd_diff_noisy_input;
uniform sampler2D nrd_history_length_tex;

const float nrd_fast_history_clamping_sigma_scale = 2.0;
const float nrd_history_acceleration_amount = 0.3;
const float nrd_history_fix_frame_num = 4.0;
const float nrd_history_reset_amount = 0.5;
const float nrd_history_reset_temporal_sigma_scale = 0.5;
const float nrd_history_reset_spatial_sigma_scale = 4.5;
const float RELAX_ANTILAG_ACCELERATION_AMOUNT_SCALE = 10.0;
// Must match temporal accumulation constants for conditional clamping guard
const float nrd_max_slow_history = 30.0;
const float nrd_max_fast_history = 6.0;

ivec2 nrd_clamp_texel(ivec2 sampleCoord, ivec2 texSize) {
    return clamp(sampleCoord, ivec2(0), texSize - 1);
}

// Gathers responsive (fast) history stats over a 5x5 neighborhood in YCoCg space.
// Validity-gated: skips sky/invalid pixels matching reference (viewZ < denoisingRange).
void nrd_accumulate_fast_history_stats(ivec2 centerCoord, out vec3 meanYcocg, out vec3 sigmaYcocg) {
    ivec2 texSize = textureSize(nrd_diff_fast_input, 0);
    vec3 sumFirst = vec3(0.0);
    vec3 sumSecond = vec3(0.0);
    float sampleCount = 0.0;

    for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
            ivec2 sampleCoord = nrd_clamp_texel(centerCoord + ivec2(dx, dy), texSize);
            // Reference validity gate: skip sky/invalid pixels (equivalent to viewZ < denoisingRange)
            vec3 sampleNorm = texelFetch(radiosity_normal, sampleCoord, 0).xyz;
            if (dot(sampleNorm, sampleNorm) < 0.01) continue;
            NrdDirectHistorySample s = nrd_unpack_direct_history(texelFetch(nrd_diff_fast_input, sampleCoord, 0));
            vec3 ycocg = nrd_rgb_to_ycocg(s.radiance);
            sumFirst  += ycocg;
            sumSecond += ycocg * ycocg;
            sampleCount += 1.0;
        }
    }

    float inv = 1.0 / max(sampleCount, 1e-4);
    meanYcocg = sumFirst * inv;
    sigmaYcocg = sqrt(max(sumSecond * inv - meanYcocg * meanYcocg, vec3(0.0)));
}

// Gathers noisy input stats over a 5x5 neighborhood:
// - noisyMean: spatial average of RGB radiance
// - noisySecondMoment: spatial average of luminance^2
// Used for acceleration direction and history reset detection.
void nrd_accumulate_noisy_stats(ivec2 centerCoord, out vec3 noisyMean, out float noisySecondMoment) {
    ivec2 texSize = textureSize(nrd_diff_noisy_input, 0);
    vec3 rgbSum = vec3(0.0);
    float lumaSquareSum = 0.0;
    float sampleCount = 0.0;

    for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
            ivec2 sampleCoord = nrd_clamp_texel(centerCoord + ivec2(dx, dy), texSize);
            // Reference validity gate: skip sky/invalid pixels
            vec3 sampleNorm = texelFetch(radiosity_normal, sampleCoord, 0).xyz;
            if (dot(sampleNorm, sampleNorm) < 0.01) continue;
            NrdDirectHistorySample s = nrd_unpack_direct_history(texelFetch(nrd_diff_noisy_input, sampleCoord, 0));
            float luma = nrd_luminance(s.radiance);
            rgbSum += s.radiance;
            lumaSquareSum += luma * luma;
            sampleCount += 1.0;
        }
    }

    float inv = 1.0 / max(sampleCount, 1e-4);
    noisyMean = rgbSum * inv;
    noisySecondMoment = lumaSquareSum * inv;
}

void main() {
    if (!is_in_world()) {
        nrd_clamped_slow_out = vec4(0.0);
        nrd_clamped_fast_out = vec4(0.0);
        nrd_history_length_out = vec4(0.0);
        return;
    }

    // --- Fetch inputs ---
    NrdDirectHistorySample slowInput = nrd_unpack_direct_history(texelFetch(direct_historyfix_output, tex_coord, 0));
    NrdDirectHistorySample fastInput = nrd_unpack_direct_history(texelFetch(nrd_diff_fast_input, tex_coord, 0));
    float historyLength = nrd_decoded_history(texelFetch(nrd_history_length_tex, tex_coord, 0));

    vec3 slowYcocg = nrd_rgb_to_ycocg(slowInput.radiance);
    vec3 fastYcocg = nrd_rgb_to_ycocg(fastInput.radiance);

    // --- Spatial stats (5x5) ---
    vec3 fastMeanYcocg;
    vec3 fastSigmaYcocg;
    nrd_accumulate_fast_history_stats(tex_coord, fastMeanYcocg, fastSigmaYcocg);

    vec3 noisyMean;
    float noisySecondMoment;
    nrd_accumulate_noisy_stats(tex_coord, noisyMean, noisySecondMoment);

    // --- Build YCoCg clamping box from responsive history (5x5 mean ± sigma) ---
    // Expand to include the responsive center pixel to minimize bias.
    vec3 minBox = fastMeanYcocg - fastSigmaYcocg * nrd_fast_history_clamping_sigma_scale;
    vec3 maxBox = fastMeanYcocg + fastSigmaYcocg * nrd_fast_history_clamping_sigma_scale;
    minBox = min(minBox, fastYcocg);
    maxBox = max(maxBox, fastYcocg);

    // --- Clamp slow history into the box ---
    // Reference: only clamp when fast max frames < slow max frames (otherwise fast == slow, no clamping needed)
    vec3 clampedSlowYcocg = slowYcocg;
    if (nrd_max_fast_history < nrd_max_slow_history)
        clampedSlowYcocg = clamp(slowYcocg, minBox, maxBox);
    vec3 clampedSlowRgb = nrd_ycocg_to_rgb(clampedSlowYcocg);

    // outSlow starts as clamped slow (rgb) + original slow 2nd moment (a).
    // outFast starts as responsive center rgb + 0 for 2nd moment (matches reference outDiffuseResponsive init).
    vec3 outSlowRgb = clampedSlowRgb;
    float outSlowSecondMoment = slowInput.secondMoment;
    vec3 outFastRgb = fastInput.radiance;

    // For young history the reference copies responsive to slow, sets clampFactor = 1,
    // then zeros acceleration before continuing to acceleration + reset logic.
    bool isYoungHistory = historyLength <= nrd_history_fix_frame_num;
    if (isYoungHistory) {
        outSlowRgb = fastInput.radiance;
    }

    // --- Clamping factor: how far slow was pushed toward fast ---
    // Young history: factor = 1 (ref line 289).
    float clampFactor = isYoungHistory
        ? 1.0
        : ((clampedSlowYcocg.x - slowYcocg.x) == 0.0
            ? 0.0
            : clamp((clampedSlowYcocg.x - slowYcocg.x) / (fastYcocg.x - slowYcocg.x), 0.0, 1.0));

    // --- History acceleration magnitude ---
    // Young history: zeroed (ref line 299).
    float historyDifferenceL = RELAX_ANTILAG_ACCELERATION_AMOUNT_SCALE
        * nrd_history_acceleration_amount
        * nrd_luminance(abs(fastInput.radiance - slowInput.radiance));
    historyDifferenceL *= clampFactor;
    if (isYoungHistory) historyDifferenceL = 0.0;

    // --- Acceleration direction: responsive center -> noisy spatial mean ---
    vec3 colorDistanceToNoisyInput = noisyMean - fastInput.radiance;
    float colorDistanceToNoisyInputL = nrd_luminance(abs(colorDistanceToNoisyInput));
    vec3 colorAcceleration = (colorDistanceToNoisyInputL == 0.0)
        ? vec3(0.0)
        : colorDistanceToNoisyInput * historyDifferenceL / colorDistanceToNoisyInputL;

    // Anti-overshoot: clamp so acceleration doesn't push past the noisy mean.
    float accelerationL = nrd_luminance(abs(colorAcceleration));
    float accelerationRatio = (accelerationL == 0.0) ? 0.0 : colorDistanceToNoisyInputL / accelerationL;
    if (accelerationRatio < 1.0)  colorAcceleration *= accelerationRatio;
    if (accelerationRatio <= 0.0) colorAcceleration = vec3(0.0);

    // Same acceleration vector applied to both outputs (ref lines 317-318).
    outSlowRgb += colorAcceleration;
    outFastRgb += colorAcceleration;

    // --- History reset ---
    // Compare pre-clamp slow luminance against noisy spatial mean.
    float slowL = nrd_luminance(slowInput.radiance);
    float noisyMeanL = nrd_luminance(noisyMean);
    float noisyTemporalSigma = nrd_history_reset_temporal_sigma_scale
        * sqrt(max(0.0, noisySecondMoment - noisyMeanL * noisyMeanL));
    float noisySpatialSigma = nrd_history_reset_spatial_sigma_scale * fastSigmaYcocg.x;
    float resetAmount = nrd_history_reset_amount
        * max(0.0, abs(slowL - noisyMeanL) - noisySpatialSigma - noisyTemporalSigma)
        / (1.0e-6 + max(slowL, noisyMeanL) + noisySpatialSigma + noisyTemporalSigma);
    resetAmount = clamp(resetAmount, 0.0, 1.0);

    // Reset toward noisy center pixel (ref lines 328-330).
    vec3 noisyCenter = nrd_unpack_direct_history(texelFetch(nrd_diff_noisy_input, tex_coord, 0)).radiance;
    outSlowRgb = mix(outSlowRgb, noisyCenter, resetAmount);
    outFastRgb = mix(outFastRgb, noisyCenter, resetAmount);

    // --- 2nd moment correction applied after reset (ref lines 333-337) ---
    // Additive correction: (final_outL^2 - original_slowL^2), clamped to >= 0.
    float outSlowL = nrd_luminance(outSlowRgb);
    float momentCorrection = outSlowL * outSlowL - slowL * slowL;
    outSlowSecondMoment = max(0.0, outSlowSecondMoment + momentCorrection);

    // History length is written back unchanged (ref line 353).
    nrd_clamped_slow_out = nrd_pack_direct_history(outSlowRgb, outSlowSecondMoment);
    nrd_clamped_fast_out = nrd_pack_direct_history(outFastRgb, 0.0);
    nrd_history_length_out = vec4(nrd_encoded_history(historyLength), 0.0, 0.0, 1.0);
}
