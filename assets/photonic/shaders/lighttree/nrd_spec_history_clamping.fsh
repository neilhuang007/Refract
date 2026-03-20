#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 spec_clamped_slow_out;
layout(location = 1) out vec4 spec_clamped_fast_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D spec_historyfix_output;
uniform sampler2D spec_fast_input;
uniform sampler2D spec_noisy_input;
uniform sampler2D spec_history_length_clamp_input;
uniform float ph_nrd_max_accumulated_frame_num;
uniform float ph_nrd_max_fast_accumulated_frame_num;
uniform float ph_nrd_denoising_range;

const float spec_fast_history_clamping_sigma_scale = 2.0;
const float spec_history_acceleration_amount = 0.3;
const float spec_history_fix_frame_num = 4.0;
const float spec_history_reset_amount = 0.5;
const float spec_history_reset_temporal_sigma_scale = 0.5;
const float spec_history_reset_spatial_sigma_scale = 4.5;
const float RELAX_ANTILAG_ACCELERATION_AMOUNT_SCALE = 10.0;

ivec2 spec_clamp_texel(ivec2 sampleCoord, ivec2 texSize) {
    return clamp(sampleCoord, ivec2(0), texSize - 1);
}

void spec_accumulate_fast_history_stats(ivec2 centerCoord, out vec3 meanYcocg, out vec3 sigmaYcocg) {
    ivec2 texSize = textureSize(spec_fast_input, 0);
    vec3 sumFirst = vec3(0.0);
    vec3 sumSecond = vec3(0.0);
    float sampleCount = 0.0;

    for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
            ivec2 sampleCoord = spec_clamp_texel(centerCoord + ivec2(dx, dy), texSize);
            // NRD per-sample validity: viewZ > gDenoisingRange skips the tap.
            // Uses viewZ = length(worldPos - cameraPos) (NRD Common.hlsli:244).
            vec3 samplePos = texelFetch(radiosity_position, sampleCoord, 0).xyz;
            float sampleViewZ = nrd_compute_view_z(samplePos);
            if (sampleViewZ > ph_nrd_denoising_range || sampleViewZ < 0.001) continue;
            NrdDirectHistorySample s = nrd_unpack_direct_history(texelFetch(spec_fast_input, sampleCoord, 0));
            vec3 ycocg = nrd_rgb_to_ycocg(s.radiance);
            sumFirst  += ycocg;
            sumSecond += ycocg * ycocg;
            sampleCount += 1.0;
        }
    }

    if (sampleCount == 0.0) {
        meanYcocg = vec3(0.0);
        sigmaYcocg = vec3(0.0);
        return;
    }
    float inv = 1.0 / sampleCount;
    meanYcocg = sumFirst * inv;
    sigmaYcocg = sqrt(max(sumSecond * inv - meanYcocg * meanYcocg, vec3(0.0)));
}

void spec_accumulate_noisy_stats(ivec2 centerCoord, out vec3 noisyMean, out float noisySecondMoment) {
    ivec2 texSize = textureSize(spec_noisy_input, 0);
    vec3 rgbSum = vec3(0.0);
    float lumaSquareSum = 0.0;
    float sampleCount = 0.0;

    for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
            ivec2 sampleCoord = spec_clamp_texel(centerCoord + ivec2(dx, dy), texSize);
            // NRD per-sample validity: viewZ > gDenoisingRange skips the tap.
            // Uses viewZ = length(worldPos - cameraPos) (NRD Common.hlsli:244).
            vec3 samplePos = texelFetch(radiosity_position, sampleCoord, 0).xyz;
            float sampleViewZ = nrd_compute_view_z(samplePos);
            if (sampleViewZ > ph_nrd_denoising_range || sampleViewZ < 0.001) continue;
            NrdDirectHistorySample s = nrd_unpack_direct_history(texelFetch(spec_noisy_input, sampleCoord, 0));
            float luma = nrd_luminance(s.radiance);
            rgbSum += s.radiance;
            lumaSquareSum += luma * luma;
            sampleCount += 1.0;
        }
    }

    if (sampleCount == 0.0) {
        noisyMean = vec3(0.0);
        noisySecondMoment = 0.0;
        return;
    }
    float inv = 1.0 / sampleCount;
    noisyMean = rgbSum * inv;
    noisySecondMoment = lumaSquareSum * inv;
}

void main() {
    if (!is_in_world()) {
        spec_clamped_slow_out = vec4(0.0);
        spec_clamped_fast_out = vec4(0.0);
        return;
    }

    // Center pixel validity check: NRD reference s_SpecNoisy_IsValid[center].w == 0 early-out.
    // Uses viewZ = length(worldPos - cameraPos) vs gDenoisingRange (NRD Common.hlsli:244).
    vec3 centerPos = texelFetch(radiosity_position, tex_coord, 0).xyz;
    float centerViewZ = nrd_compute_view_z(centerPos);
    if (centerViewZ > ph_nrd_denoising_range || centerViewZ < 0.001) {
        spec_clamped_slow_out = texelFetch(spec_historyfix_output, tex_coord, 0);
        spec_clamped_fast_out = texelFetch(spec_fast_input, tex_coord, 0);
        return;
    }

    // --- Fetch inputs ---
    NrdDirectHistorySample slowInput = nrd_unpack_direct_history(texelFetch(spec_historyfix_output, tex_coord, 0));
    NrdDirectHistorySample fastInput = nrd_unpack_direct_history(texelFetch(spec_fast_input, tex_coord, 0));
    float historyLength = nrd_decoded_history(texelFetch(spec_history_length_clamp_input, tex_coord, 0));

    vec3 slowYcocg = nrd_rgb_to_ycocg(slowInput.radiance);
    vec3 fastYcocg = nrd_rgb_to_ycocg(fastInput.radiance);

    // --- Spatial stats (5x5) ---
    vec3 fastMeanYcocg;
    vec3 fastSigmaYcocg;
    spec_accumulate_fast_history_stats(tex_coord, fastMeanYcocg, fastSigmaYcocg);

    vec3 noisyMean;
    float noisySecondMoment;
    spec_accumulate_noisy_stats(tex_coord, noisyMean, noisySecondMoment);

    // --- Build YCoCg clamping box from responsive history (5x5 mean ± sigma) ---
    vec3 minBox = fastMeanYcocg - fastSigmaYcocg * spec_fast_history_clamping_sigma_scale;
    vec3 maxBox = fastMeanYcocg + fastSigmaYcocg * spec_fast_history_clamping_sigma_scale;
    minBox = min(minBox, fastYcocg);
    maxBox = max(maxBox, fastYcocg);

    // --- Clamp slow history into the box ---
    vec3 clampedSlowYcocg = slowYcocg;
    if (ph_nrd_max_fast_accumulated_frame_num < ph_nrd_max_accumulated_frame_num)
        clampedSlowYcocg = clamp(slowYcocg, minBox, maxBox);
    vec3 clampedSlowRgb = nrd_ycocg_to_rgb(clampedSlowYcocg);

    vec3 outSlowRgb = clampedSlowRgb;
    float outSlowSecondMoment = slowInput.secondMoment;
    vec3 outFastRgb = fastInput.radiance;

    bool isYoungHistory = historyLength <= spec_history_fix_frame_num;
    if (isYoungHistory) {
        outSlowRgb = fastInput.radiance;
    }

    // --- Clamping factor ---
    float clampFactor = isYoungHistory
        ? 1.0
        : ((clampedSlowYcocg.x - slowYcocg.x) == 0.0
            ? 0.0
            : clamp((clampedSlowYcocg.x - slowYcocg.x) / (fastYcocg.x - slowYcocg.x), 0.0, 1.0));

    // --- History acceleration magnitude ---
    // NRD reference: specular uses 0.33x scale because specular reprojection
    // already has rejection heuristics that diffuse does not have
    float historyDifferenceL = 0.33 * RELAX_ANTILAG_ACCELERATION_AMOUNT_SCALE
        * spec_history_acceleration_amount
        * nrd_luminance(abs(fastInput.radiance - slowInput.radiance));
    historyDifferenceL *= clampFactor;
    if (isYoungHistory) historyDifferenceL = 0.0;

    // --- Acceleration direction ---
    vec3 colorDistanceToNoisyInput = noisyMean - fastInput.radiance;
    float colorDistanceToNoisyInputL = nrd_luminance(abs(colorDistanceToNoisyInput));
    vec3 colorAcceleration = (colorDistanceToNoisyInputL == 0.0)
        ? vec3(0.0)
        : colorDistanceToNoisyInput * historyDifferenceL / colorDistanceToNoisyInputL;

    float accelerationL = nrd_luminance(abs(colorAcceleration));
    float accelerationRatio = (accelerationL == 0.0) ? 0.0 : colorDistanceToNoisyInputL / accelerationL;
    if (accelerationRatio < 1.0)  colorAcceleration *= accelerationRatio;
    if (accelerationRatio <= 0.0) colorAcceleration = vec3(0.0);

    outSlowRgb += colorAcceleration;
    outFastRgb += colorAcceleration;

    // --- History reset ---
    float slowL = nrd_luminance(slowInput.radiance);
    float noisyMeanL = nrd_luminance(noisyMean);
    float noisyTemporalSigma = spec_history_reset_temporal_sigma_scale
        * sqrt(max(0.0, noisySecondMoment - noisyMeanL * noisyMeanL));
    float noisySpatialSigma = spec_history_reset_spatial_sigma_scale * fastSigmaYcocg.x;
    // NRD reference: specular reset amount scaled by 0.5 vs diffuse
    float resetAmount = 0.5 * spec_history_reset_amount
        * max(0.0, abs(slowL - noisyMeanL) - noisySpatialSigma - noisyTemporalSigma)
        / (1.0e-6 + max(slowL, noisyMeanL) + noisySpatialSigma + noisyTemporalSigma);
    resetAmount = clamp(resetAmount, 0.0, 1.0);

    vec3 noisyCenter = nrd_unpack_direct_history(texelFetch(spec_noisy_input, tex_coord, 0)).radiance;
    outSlowRgb = mix(outSlowRgb, noisyCenter, resetAmount);
    outFastRgb = mix(outFastRgb, noisyCenter, resetAmount);

    // --- 2nd moment correction ---
    float outSlowL = nrd_luminance(outSlowRgb);
    float momentCorrection = outSlowL * outSlowL - slowL * slowL;
    outSlowSecondMoment = max(0.0, outSlowSecondMoment + momentCorrection);

    spec_clamped_slow_out = nrd_pack_direct_history(outSlowRgb, outSlowSecondMoment);
    // NRD reference (line 178): specular responsive output preserves 2nd moment in .a
    // (diffuse zeros it, but specular carries it forward)
    spec_clamped_fast_out = vec4(max(outFastRgb, vec3(0.0)), fastInput.secondMoment);
}
