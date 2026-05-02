#version 430

in vec4 direction_vert_out;

// MRT layout per nrd_refactor_contract.md §7 HistoryClamping
layout(location = 0) out vec4 nrd_diff_illum_prev_out;            // RGBA16F → nrdDiffIllumPrevFb
layout(location = 1) out vec4 nrd_diff_illum_responsive_prev_out; // RGBA16F → nrdDiffIllumResponsivePrevFb
layout(location = 2) out vec4 nrd_spec_illum_prev_out;            // RGBA16F → nrdSpecIllumPrevFb
layout(location = 3) out vec4 nrd_spec_illum_responsive_prev_out; // RGBA16F → nrdSpecIllumResponsivePrevFb
layout(location = 4) out vec4 nrd_history_length_prev_out;        // R8     → nrdHistoryLengthPrevFb

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

// Samplers declared in samplers.glsl (via header.glsl → photonics.glsl → ph_samplers.glsl → samplers.glsl):
//   nrd_in_tiles, nrd_history_length,
//   nrd_out_diff_radiance_hitdist, nrd_out_spec_radiance_hitdist,
//   nrd_diff_illum_ping, nrd_spec_illum_ping,
//   nrd_diff_illum_pong, nrd_spec_illum_pong,
//   radiosity_position

// RELAX_HistoryClamping.cs.hlsl constant
// Reference: RELAX_Config.hlsli — RELAX_ANTILAG_ACCELERATION_AMOUNT_SCALE = 10.0
const float RELAX_ANTILAG_ACCELERATION_AMOUNT_SCALE = 10.0;

// ---------------------------------------------------------------------------
// IMPLEMENTATION NOTE — groupshared memory:
//
// The HLSL reference uses groupshared arrays (s_DiffResponsiveYCoCg,
// s_DiffNoisy_IsValid, s_SpecResponsiveYCoCg, s_SpecNoisy_IsValid) loaded in
// a Preload() function before the main loop to amortise texture bandwidth
// across the compute thread group (RELAX_HistoryClamping.cs.hlsl:22-53).
//
// Fragment shaders have no groupshared memory.  We replicate the same 5×5
// gather by calling texelFetch directly for each tap.  This produces 25 taps
// per channel per pixel — identical values and identical clamping behaviour at
// the cost of redundant texture reads.  The sampling pattern, validity gate,
// moment accumulation, and all subsequent arithmetic are exact ports.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Shared 5×5 gather helpers
//
// Reference: RELAX_HistoryClamping.cs.hlsl:103-147 (the unrolled 5×5 loop).
//
// Both diff and spec use the same validity gate:
//   isValid = IsInDenoisingRange(viewZ)
//           = (viewZ < gDenoisingRange)
// which in Photonics is (viewZ < ph_nrd_denoising_range && viewZ >= 0.001).
//
// Moments are divided by `sum` (count of valid taps) after the loop, exactly
// matching the reference normalisation at lines 151-154 / 253-256.
// ---------------------------------------------------------------------------

// Returns true when the tap is inside the denoising range.
// Reference: RELAX_HistoryClamping.cs.hlsl Preload() isValid condition.
bool nrd_hc_tap_is_valid(ivec2 coord) {
    vec3 worldPos = texelFetch(radiosity_position, coord, 0).xyz;
    float viewZ = nrd_compute_view_z(worldPos);
    return (viewZ >= 0.001 && viewZ < ph_nrd_denoising_range);
}

// Clamp a coordinate to the texture extent.
ivec2 nrd_hc_clamp_coord(ivec2 coord, ivec2 texSize) {
    return clamp(coord, ivec2(0), texSize - ivec2(1));
}

// Gather diffuse 5×5 statistics.
// Outputs:
//   responsiveFirstMomentYCoCg  — mean of responsive RGB in YCoCg
//   responsiveSecondMomentYCoCg — E[YCoCg^2] of responsive
//   noisyFirstMoment            — mean of noisy RGB
//   noisySecondMoment           — mean of noisy luminance^2
//
// Reference: RELAX_HistoryClamping.cs.hlsl:103-147 (NRD_DIFF block)
//            normalisation at lines 253-256.
void nrd_hc_gather_diff_stats(
    ivec2 centerCoord,
    out vec3  responsiveFirstMomentYCoCg,
    out vec3  responsiveSecondMomentYCoCg,
    out vec3  noisyFirstMoment,
    out float noisySecondMoment
) {
    ivec2 respTexSize  = textureSize(nrd_diff_illum_pong, 0);
    ivec2 noisyTexSize = textureSize(nrd_out_diff_radiance_hitdist, 0);

    responsiveFirstMomentYCoCg  = vec3(0.0);
    responsiveSecondMomentYCoCg = vec3(0.0);
    noisyFirstMoment            = vec3(0.0);
    noisySecondMoment           = 0.0;
    float sum = 0.0;

    for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
            ivec2 coord = centerCoord + ivec2(dx, dy);
            ivec2 validCoord = nrd_hc_clamp_coord(coord, respTexSize);

            // Validity gate: skip taps outside denoising range.
            // Reference: s_DiffNoisy_IsValid[p].w — set in Preload() as IsInDenoisingRange(viewZ).
            if (!nrd_hc_tap_is_valid(validCoord)) continue;

            // Responsive (fast) sample — YCoCg first/second moments.
            // Reference: diffuseSampleYCoCg from s_DiffResponsiveYCoCg (line 135-137).
            vec3 respRgb       = texelFetch(nrd_diff_illum_pong, validCoord, 0).rgb;
            vec3 respYCoCg     = nrd_rgb_to_ycocg(respRgb);
            responsiveFirstMomentYCoCg  += respYCoCg;
            responsiveSecondMomentYCoCg += respYCoCg * respYCoCg;

            // Noisy sample — RGB first moment + luminance^2 second moment.
            // Reference: diffuseNoisySample from s_DiffNoisy_IsValid (lines 139-142).
            ivec2 noisyCoord  = nrd_hc_clamp_coord(coord, noisyTexSize);
            vec3 noisyRgb     = texelFetch(nrd_out_diff_radiance_hitdist, noisyCoord, 0).rgb;
            float noisyLuma   = nrd_luminance(noisyRgb);
            noisyFirstMoment  += noisyRgb;
            noisySecondMoment += noisyLuma * noisyLuma;

            sum += 1.0;
        }
    }

    if (sum > 0.0) {
        float invSum = 1.0 / sum;
        responsiveFirstMomentYCoCg  *= invSum;
        responsiveSecondMomentYCoCg *= invSum;
        noisyFirstMoment            *= invSum;
        noisySecondMoment           *= invSum;
    }
}

// Gather specular 5×5 statistics.
// Same structure as diffuse; spec responsive lives in nrd_spec_illum_pong,
// spec noisy in nrd_out_spec_radiance_hitdist.
//
// Reference: RELAX_HistoryClamping.cs.hlsl:103-147 (NRD_SPEC block)
//            normalisation at lines 151-154.
void nrd_hc_gather_spec_stats(
    ivec2 centerCoord,
    out vec3  responsiveFirstMomentYCoCg,
    out vec3  responsiveSecondMomentYCoCg,
    out vec3  noisyFirstMoment,
    out float noisySecondMoment
) {
    ivec2 respTexSize  = textureSize(nrd_spec_illum_pong, 0);
    ivec2 noisyTexSize = textureSize(nrd_out_spec_radiance_hitdist, 0);

    responsiveFirstMomentYCoCg  = vec3(0.0);
    responsiveSecondMomentYCoCg = vec3(0.0);
    noisyFirstMoment            = vec3(0.0);
    noisySecondMoment           = 0.0;
    float sum = 0.0;

    for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
            ivec2 coord = centerCoord + ivec2(dx, dy);
            ivec2 validCoord = nrd_hc_clamp_coord(coord, respTexSize);

            // Reference: s_SpecNoisy_IsValid[p].w validity gate (line 116-117).
            if (!nrd_hc_tap_is_valid(validCoord)) continue;

            // Responsive (fast) spec sample in YCoCg.
            // Reference: specularSampleYCoCg from s_SpecResponsiveYCoCg (lines 126-128).
            vec3 respRgb       = texelFetch(nrd_spec_illum_pong, validCoord, 0).rgb;
            vec3 respYCoCg     = nrd_rgb_to_ycocg(respRgb);
            responsiveFirstMomentYCoCg  += respYCoCg;
            responsiveSecondMomentYCoCg += respYCoCg * respYCoCg;

            // Noisy spec sample.
            // Reference: specularNoisySample from s_SpecNoisy_IsValid (lines 130-132).
            ivec2 noisyCoord  = nrd_hc_clamp_coord(coord, noisyTexSize);
            vec3 noisyRgb     = texelFetch(nrd_out_spec_radiance_hitdist, noisyCoord, 0).rgb;
            float noisyLuma   = nrd_luminance(noisyRgb);
            noisyFirstMoment  += noisyRgb;
            noisySecondMoment += noisyLuma * noisyLuma;

            sum += 1.0;
        }
    }

    if (sum > 0.0) {
        float invSum = 1.0 / sum;
        responsiveFirstMomentYCoCg  *= invSum;
        responsiveSecondMomentYCoCg *= invSum;
        noisyFirstMoment            *= invSum;
        noisySecondMoment           *= invSum;
    }
}

// ---------------------------------------------------------------------------
// Specular history clamping
//
// Reference: RELAX_HistoryClamping.cs.hlsl:149-249 (NRD_SPEC block).
//
// Differences from diffuse path (per reference lines cited):
//   - history acceleration uses 0.33× scale (line 190)
//   - history reset amount uses 0.5× (line 223)
//   - outSpecularResponsive.a carries the original responsive .a (line 178) —
//     for spec, the .a of the responsive ping-pong buffer is not 2nd moment;
//     it is the reflection hitDist stored by the temporal accumulator.
//   - 2nd moment correction applies to outSpecular.a only (lines 232-236).
// ---------------------------------------------------------------------------
void nrd_spec_history_clamping(
    ivec2 centerCoord,
    float historyLength,
    out vec4 outSpec,        // rgb = clamped/accelerated/reset slow, a = 2nd moment
    out vec4 outSpecResponsive // rgb = accelerated/reset responsive, a = original responsive .a
) {
    // 5×5 spatial statistics.
    vec3  specResponsiveFirstMomentYCoCg;
    vec3  specResponsiveSecondMomentYCoCg;
    vec3  specNoisyFirstMoment;
    float specNoisySecondMoment;
    nrd_hc_gather_spec_stats(
        centerCoord,
        specResponsiveFirstMomentYCoCg,
        specResponsiveSecondMomentYCoCg,
        specNoisyFirstMoment,
        specNoisySecondMoment
    );

    // Responsive sigma and color box.
    // Reference: lines 155-162.
    vec3 specResponsiveSigmaYCoCg = sqrt(max(
        vec3(0.0),
        specResponsiveSecondMomentYCoCg - specResponsiveFirstMomentYCoCg * specResponsiveFirstMomentYCoCg
    ));
    vec3 specResponsiveColorMinYCoCg = specResponsiveFirstMomentYCoCg - ph_nrd_history_clamping_color_box_sigma_scale * specResponsiveSigmaYCoCg;
    vec3 specResponsiveColorMaxYCoCg = specResponsiveFirstMomentYCoCg + ph_nrd_history_clamping_color_box_sigma_scale * specResponsiveSigmaYCoCg;

    // Expand color box with center pixel of responsive to minimise introduced bias.
    // Reference: lines 160-162.
    vec4 specResponsiveCenterRaw    = texelFetch(nrd_spec_illum_pong, centerCoord, 0);
    vec3 specResponsiveCenterYCoCg  = nrd_rgb_to_ycocg(specResponsiveCenterRaw.rgb);
    specResponsiveColorMinYCoCg = min(specResponsiveColorMinYCoCg, specResponsiveCenterYCoCg);
    specResponsiveColorMaxYCoCg = max(specResponsiveColorMaxYCoCg, specResponsiveCenterYCoCg);

    // Read slow (= ping) specular: rgb = illumination, a = 2nd moment.
    // Reference: specularIlluminationAnd2ndMoment = gIn_Spec[pixelPos] (line 165).
    vec4  specIllumAnd2ndMoment = texelFetch(nrd_spec_illum_ping, centerCoord, 0);

    // Clamp slow into the color box (only when fast max < slow max frames).
    // Reference: lines 167-170.
    vec3  specYCoCg        = nrd_rgb_to_ycocg(specIllumAnd2ndMoment.rgb);
    vec3  clampedSpecYCoCg = specYCoCg;
    if (ph_nrd_max_fast_accumulated_frame_num < ph_nrd_max_accumulated_frame_num)
        clampedSpecYCoCg = clamp(specYCoCg, specResponsiveColorMinYCoCg, specResponsiveColorMaxYCoCg);
    vec3 clampedSpec = nrd_ycocg_to_rgb(clampedSpecYCoCg);

    // Initial outputs.
    // outSpecular.a = specularIlluminationAnd2ndMoment.a (2nd moment carried through).
    // outSpecularResponsive.a = specularResponsiveCenterYCoCg.a? No — see reference line 178:
    //   outSpecularResponsive = float4(specularResponsiveCenter, specularResponsiveCenterYCoCg.a)
    //   but s_SpecResponsiveYCoCg[center].a was loaded as specularResponsive.a (Preload line 40),
    //   i.e., the .a channel of the responsive buffer — which is the reflection hitDist stored
    //   by the temporal accumulator into nrd_spec_illum_pong.a.
    // Reference: lines 176-180.
    vec3 specResponsiveCenter = nrd_ycocg_to_rgb(specResponsiveCenterYCoCg);
    outSpec          = vec4(clampedSpec, specIllumAnd2ndMoment.a);
    outSpecResponsive = vec4(specResponsiveCenter, specResponsiveCenterRaw.a);
    if (historyLength <= ph_nrd_history_fix_frame_num)
        outSpec = outSpecResponsive; // Reference line 179-180

    // Clamping factor: (clamped - slow) / (fast - slow), saturated.
    // Reference: lines 184-186.
    float specClampingFactor = (clampedSpecYCoCg.x - specYCoCg.x) == 0.0
        ? 0.0
        : clamp(
            (clampedSpecYCoCg.x - specYCoCg.x) / (specResponsiveCenterYCoCg.x - specYCoCg.x),
            0.0, 1.0
          );
    if (historyLength <= ph_nrd_history_fix_frame_num)
        specClampingFactor = 1.0; // Reference line 185-186

    // History acceleration magnitude.
    // Specular uses 0.33× because its reprojection already has rejection heuristics.
    // Reference: line 190.
    float specHistoryDifferenceL = 0.33
        * RELAX_ANTILAG_ACCELERATION_AMOUNT_SCALE
        * ph_nrd_history_acceleration_amount
        * nrd_luminance(abs(specResponsiveCenter - specIllumAnd2ndMoment.rgb));

    // Acceleration proportional to clamping amount.
    // Reference: lines 193-197.
    specHistoryDifferenceL *= specClampingFactor;
    if (historyLength <= ph_nrd_history_fix_frame_num)
        specHistoryDifferenceL = 0.0;

    // Acceleration direction: responsive center → averaged noisy input.
    // Reference: lines 200-202.
    vec3  specColorDistanceToNoisy  = specNoisyFirstMoment - specResponsiveCenter;
    float specColorDistanceL        = nrd_luminance(abs(specColorDistanceToNoisy));
    vec3  specColorAcceleration     = (specColorDistanceL == 0.0)
        ? vec3(0.0)
        : specColorDistanceToNoisy * specHistoryDifferenceL / specColorDistanceL;

    // Anti-overshoot: do not push past the noisy mean.
    // Reference: lines 207-212.
    float specColorAccelerationL    = nrd_luminance(abs(specColorAcceleration));
    float specColorAccelerationRatio = (specColorAccelerationL == 0.0)
        ? 0.0
        : specColorDistanceL / specColorAccelerationL;
    if (specColorAccelerationRatio < 1.0)
        specColorAcceleration *= specColorAccelerationRatio;
    if (specColorAccelerationRatio <= 0.0)
        specColorAcceleration = vec3(0.0);

    // Apply acceleration to both outputs.
    // Reference: lines 215-216.
    outSpec.rgb          += specColorAcceleration;
    outSpecResponsive.rgb += specColorAcceleration;

    // History reset calculation.
    // Spec reset amount is 0.5× the uniform (reference line 223).
    float specL         = nrd_luminance(specIllumAnd2ndMoment.rgb);
    float specNoisyL    = nrd_luminance(specNoisyFirstMoment);
    float specTemporalSigma = ph_nrd_history_reset_temporal_sigma_scale
        * sqrt(max(0.0, specNoisySecondMoment - specNoisyL * specNoisyL));
    float specSpatialSigma  = ph_nrd_history_reset_spatial_sigma_scale * specResponsiveSigmaYCoCg.x;
    // Reference: line 223 — 0.5 * gHistoryResetAmount
    float specResetAmount = 0.5 * ph_nrd_history_reset_amount
        * max(0.0, abs(specL - specNoisyL) - specSpatialSigma - specTemporalSigma)
        / (1.0e-6 + max(specL, specNoisyL) + specSpatialSigma + specTemporalSigma);
    specResetAmount = clamp(specResetAmount, 0.0, 1.0);

    // Reset toward the noisy center pixel.
    // Reference: lines 227-229.
    vec3 specNoisyCenter = texelFetch(nrd_out_spec_radiance_hitdist, centerCoord, 0).rgb;
    outSpec.rgb          = mix(outSpec.rgb,          specNoisyCenter, specResetAmount);
    outSpecResponsive.rgb = mix(outSpecResponsive.rgb, specNoisyCenter, specResetAmount);

    // 2nd moment correction.
    // Reference: lines 232-236.
    float outSpecL = nrd_luminance(outSpec.rgb);
    float specMomentCorrection = outSpecL * outSpecL - specL * specL;
    outSpec.a += specMomentCorrection;
    outSpec.a  = max(0.0, outSpec.a);
}

// ---------------------------------------------------------------------------
// Diffuse history clamping
//
// Reference: RELAX_HistoryClamping.cs.hlsl:251-353 (NRD_DIFF block).
//
// Differences from spec path:
//   - history acceleration uses full 1× scale (line 292)
//   - history reset amount uses full gHistoryResetAmount (line 325)
//   - outDiffuseResponsive.a = 0 (line 281)
// ---------------------------------------------------------------------------
void nrd_diff_history_clamping(
    ivec2 centerCoord,
    float historyLength,
    out vec4 outDiff,           // rgb = clamped/accelerated/reset slow, a = 2nd moment
    out vec4 outDiffResponsive  // rgb = accelerated/reset responsive, a = 0
) {
    // 5×5 spatial statistics.
    vec3  diffResponsiveFirstMomentYCoCg;
    vec3  diffResponsiveSecondMomentYCoCg;
    vec3  diffNoisyFirstMoment;
    float diffNoisySecondMoment;
    nrd_hc_gather_diff_stats(
        centerCoord,
        diffResponsiveFirstMomentYCoCg,
        diffResponsiveSecondMomentYCoCg,
        diffNoisyFirstMoment,
        diffNoisySecondMoment
    );

    // Responsive sigma and color box.
    // Reference: lines 257-264.
    vec3 diffResponsiveSigmaYCoCg = sqrt(max(
        vec3(0.0),
        diffResponsiveSecondMomentYCoCg - diffResponsiveFirstMomentYCoCg * diffResponsiveFirstMomentYCoCg
    ));
    vec3 diffResponsiveColorMinYCoCg = diffResponsiveFirstMomentYCoCg - ph_nrd_history_clamping_color_box_sigma_scale * diffResponsiveSigmaYCoCg;
    vec3 diffResponsiveColorMaxYCoCg = diffResponsiveFirstMomentYCoCg + ph_nrd_history_clamping_color_box_sigma_scale * diffResponsiveSigmaYCoCg;

    // Expand color box with center pixel of responsive.
    // Reference: lines 262-264.
    vec4 diffResponsiveCenterRaw   = texelFetch(nrd_diff_illum_pong, centerCoord, 0);
    vec3 diffResponsiveCenterYCoCg = nrd_rgb_to_ycocg(diffResponsiveCenterRaw.rgb);
    diffResponsiveColorMinYCoCg = min(diffResponsiveColorMinYCoCg, diffResponsiveCenterYCoCg);
    diffResponsiveColorMaxYCoCg = max(diffResponsiveColorMaxYCoCg, diffResponsiveCenterYCoCg);

    // Read slow (= ping) diffuse: rgb = illumination, a = 2nd moment.
    // Reference: diffuseIlluminationAnd2ndMoment = gIn_Diff[pixelPos] (line 268).
    vec4 diffIllumAnd2ndMoment = texelFetch(nrd_diff_illum_ping, centerCoord, 0);

    // Clamp slow into the color box.
    // Reference: lines 270-273.
    vec3 diffYCoCg        = nrd_rgb_to_ycocg(diffIllumAnd2ndMoment.rgb);
    vec3 clampedDiffYCoCg = diffYCoCg;
    if (ph_nrd_max_fast_accumulated_frame_num < ph_nrd_max_accumulated_frame_num)
        clampedDiffYCoCg = clamp(diffYCoCg, diffResponsiveColorMinYCoCg, diffResponsiveColorMaxYCoCg);
    vec3 clampedDiff = nrd_ycocg_to_rgb(clampedDiffYCoCg);

    // Initial outputs.
    // outDiffuseResponsive.a = 0 (reference line 281).
    // Reference: lines 279-283.
    vec3 diffResponsiveCenter = nrd_ycocg_to_rgb(diffResponsiveCenterYCoCg);
    outDiff          = vec4(clampedDiff, diffIllumAnd2ndMoment.a);
    outDiffResponsive = vec4(diffResponsiveCenter, 0.0);
    if (historyLength <= ph_nrd_history_fix_frame_num)
        outDiff.rgb = outDiffResponsive.rgb; // Reference line 282-283

    // Clamping factor.
    // Reference: lines 287-289.
    float diffClampingFactor = (clampedDiffYCoCg.x - diffYCoCg.x) == 0.0
        ? 0.0
        : clamp(
            (clampedDiffYCoCg.x - diffYCoCg.x) / (diffResponsiveCenterYCoCg.x - diffYCoCg.x),
            0.0, 1.0
          );
    if (historyLength <= ph_nrd_history_fix_frame_num)
        diffClampingFactor = 1.0; // Reference line 288-289

    // History acceleration magnitude — full 1× scale for diffuse.
    // Reference: line 292.
    float diffHistoryDifferenceL = RELAX_ANTILAG_ACCELERATION_AMOUNT_SCALE
        * ph_nrd_history_acceleration_amount
        * nrd_luminance(abs(diffResponsiveCenter - diffIllumAnd2ndMoment.rgb));

    // Acceleration proportional to clamping amount.
    // Reference: lines 295-299.
    diffHistoryDifferenceL *= diffClampingFactor;
    if (historyLength <= ph_nrd_history_fix_frame_num)
        diffHistoryDifferenceL = 0.0;

    // Acceleration direction: responsive center → averaged noisy input.
    // Reference: lines 302-304.
    vec3  diffColorDistanceToNoisy  = diffNoisyFirstMoment - diffResponsiveCenter;
    float diffColorDistanceL        = nrd_luminance(abs(diffColorDistanceToNoisy));
    vec3  diffColorAcceleration     = (diffColorDistanceL == 0.0)
        ? vec3(0.0)
        : diffColorDistanceToNoisy * diffHistoryDifferenceL / diffColorDistanceL;

    // Anti-overshoot.
    // Reference: lines 309-314.
    float diffColorAccelerationL    = nrd_luminance(abs(diffColorAcceleration));
    float diffColorAccelerationRatio = (diffColorAccelerationL == 0.0)
        ? 0.0
        : diffColorDistanceL / diffColorAccelerationL;
    if (diffColorAccelerationRatio < 1.0)
        diffColorAcceleration *= diffColorAccelerationRatio;
    if (diffColorAccelerationRatio <= 0.0)
        diffColorAcceleration = vec3(0.0);

    // Apply acceleration to both outputs.
    // Reference: lines 317-318.
    outDiff.rgb          += diffColorAcceleration;
    outDiffResponsive.rgb += diffColorAcceleration;

    // History reset calculation.
    // Reference: lines 321-326.
    float diffL      = nrd_luminance(diffIllumAnd2ndMoment.rgb);
    float diffNoisyL = nrd_luminance(diffNoisyFirstMoment);
    float diffTemporalSigma = ph_nrd_history_reset_temporal_sigma_scale
        * sqrt(max(0.0, diffNoisySecondMoment - diffNoisyL * diffNoisyL));
    float diffSpatialSigma  = ph_nrd_history_reset_spatial_sigma_scale * diffResponsiveSigmaYCoCg.x;
    float diffResetAmount = ph_nrd_history_reset_amount
        * max(0.0, abs(diffL - diffNoisyL) - diffSpatialSigma - diffTemporalSigma)
        / (1.0e-6 + max(diffL, diffNoisyL) + diffSpatialSigma + diffTemporalSigma);
    diffResetAmount = clamp(diffResetAmount, 0.0, 1.0);

    // Reset toward the noisy center pixel.
    // Reference: lines 328-330.
    vec3 diffNoisyCenter = texelFetch(nrd_out_diff_radiance_hitdist, centerCoord, 0).rgb;
    outDiff.rgb          = mix(outDiff.rgb,          diffNoisyCenter, diffResetAmount);
    outDiffResponsive.rgb = mix(outDiffResponsive.rgb, diffNoisyCenter, diffResetAmount);

    // 2nd moment correction.
    // Reference: lines 332-337.
    float outDiffL = nrd_luminance(outDiff.rgb);
    float diffMomentCorrection = outDiffL * outDiffL - diffL * diffL;
    outDiff.a += diffMomentCorrection;
    outDiff.a  = max(0.0, outDiff.a);
}

void main() {
    // ---------------------------------------------------------------------------
    // Tile-based early-out.
    // Reference: RELAX_HistoryClamping.cs.hlsl:68-73.
    //
    // gIn_Tiles is sampled at (pixelPos >> 4) — i.e., one texel per 16×16 tile.
    // In Photonics the tiles FBO has resolution ceil(width/16)×ceil(height/16),
    // so we fetch at tex_coord >> 4 using ivec2 integer shift.
    //
    // Contract §11 rule 7: use discard for sky tiles.
    // ---------------------------------------------------------------------------
    ivec2 tileCoord = tex_coord >> 4;
    float isSky = texelFetch(nrd_in_tiles, tileCoord, 0).r;
    if (isSky > 0.5) {
        // Tile is sky — write safe zeroes and return.
        nrd_diff_illum_prev_out            = vec4(0.0);
        nrd_diff_illum_responsive_prev_out = vec4(0.0);
        nrd_spec_illum_prev_out            = vec4(0.0);
        nrd_spec_illum_responsive_prev_out = vec4(0.0);
        nrd_history_length_prev_out        = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }

    // ---------------------------------------------------------------------------
    // Center pixel validity check.
    // Reference: RELAX_HistoryClamping.cs.hlsl:76-83.
    //   s_SpecNoisy_IsValid / s_DiffNoisy_IsValid center .w == 0 → return.
    //
    // When the center is out of range we pass through the current-frame slow and
    // responsive buffers unchanged — there is nothing to clamp.
    // ---------------------------------------------------------------------------
    if (!nrd_hc_tap_is_valid(tex_coord)) {
        nrd_diff_illum_prev_out            = texelFetch(nrd_diff_illum_ping, tex_coord, 0);
        nrd_diff_illum_responsive_prev_out = texelFetch(nrd_diff_illum_pong, tex_coord, 0);
        nrd_spec_illum_prev_out            = texelFetch(nrd_spec_illum_ping, tex_coord, 0);
        nrd_spec_illum_responsive_prev_out = texelFetch(nrd_spec_illum_pong, tex_coord, 0);
        // History length passthrough.
        float hl = nrd_decoded_history(texelFetch(nrd_history_length, tex_coord, 0));
        nrd_history_length_prev_out = vec4(hl / 255.0, 0.0, 0.0, 1.0);
        return;
    }

    // ---------------------------------------------------------------------------
    // Read history length.
    // Reference: RELAX_HistoryClamping.cs.hlsl:86.
    //   historyLength = 255.0 * gIn_HistoryLength[pixelPos]
    // ---------------------------------------------------------------------------
    float historyLength = nrd_decoded_history(texelFetch(nrd_history_length, tex_coord, 0));

    // ---------------------------------------------------------------------------
    // Run specular clamping path.
    // Reference: RELAX_HistoryClamping.cs.hlsl:149-249.
    // ---------------------------------------------------------------------------
    vec4 outSpec;
    vec4 outSpecResponsive;
    nrd_spec_history_clamping(tex_coord, historyLength, outSpec, outSpecResponsive);

    // ---------------------------------------------------------------------------
    // Run diffuse clamping path.
    // Reference: RELAX_HistoryClamping.cs.hlsl:251-350.
    // ---------------------------------------------------------------------------
    vec4 outDiff;
    vec4 outDiffResponsive;
    nrd_diff_history_clamping(tex_coord, historyLength, outDiff, outDiffResponsive);

    // ---------------------------------------------------------------------------
    // Write outputs.
    // Reference: RELAX_HistoryClamping.cs.hlsl:339-341 / 353.
    //
    // History length is written to the permanent prev buffer here.
    // The old Photonics implementation skipped this write to avoid a feedback
    // hazard, but the refactored pipeline uses separate transient (nrdHistoryLengthFb)
    // and permanent (nrdHistoryLengthPrevFb) buffers per contract §8, so the
    // hazard is gone and we match the reference exactly.
    // ---------------------------------------------------------------------------
    nrd_diff_illum_prev_out            = outDiff;
    nrd_diff_illum_responsive_prev_out = outDiffResponsive;
    nrd_spec_illum_prev_out            = outSpec;
    nrd_spec_illum_responsive_prev_out = outSpecResponsive;
    // Reference line 353: gOut_HistoryLength[pixelPos] = historyLength / 255.0
    nrd_history_length_prev_out        = vec4(historyLength / 255.0, 0.0, 0.0, 1.0);
}
