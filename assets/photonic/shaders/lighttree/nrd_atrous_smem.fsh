#version 430

// NRD RELAX A-trous first pass (stride = 1, "SMEM" pass).
// Reference: RELAX_AtrousSmem.cs.hlsl
//
// This pass reads from the permanent slow buffers (post-anti-firefly):
//   nrd_diff_illum_prev, nrd_spec_illum_prev  (.a = 2nd moment of luminance)
//
// Two branches match the reference exactly:
//   - historyLength >= gHistoryThreshold (6): run 3x3 A-trous with Gaussian weights.
//   - historyLength <  gHistoryThreshold    : spatial variance estimation over 5x5.
//
// .a invariant (contract section 11.6):
//   Input  .a = secondMoment (E[luma^2]).
//   Variance is computed internally as max(secondMoment - luma*luma, 0).
//   Output .a = secondMoment (filtered with w^2 weighting), NOT variance.
//   See RELAX_Atrous.cs.hlsl accumulation block for the w^2 pattern.

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_diff_atrous_out;
layout(location = 1) out vec4 nrd_spec_atrous_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform int   direct_atrous_step_size;   // Java sets to 1 for this pass
uniform int   direct_atrous_is_last_pass;// unused by shader; kept for binding compat

// NRD RELAX constants (no confidence pipeline, no SH mode)
// Reference: RELAX_AtrousSmem.cs.hlsl lines 261-262
const float gaussian3x3[2] = float[](0.44198, 0.27901);
// Reference: gHistoryThreshold = 6 (RELAX_Config.hlsli default)
const float gHistoryThreshold = 6.0;
// gSpecMaxLuminanceRelativeDifference: -log(saturate(minLuminanceWeight=0.0)) -> +Inf;
// use 1e9 to match uncapped behaviour.
const float gSpecMaxLuminanceRelativeDifference = 1e9;
const float gDiffMaxLuminanceRelativeDifference = 1e9;
// gRoughnessEdgeStoppingRelaxation default = 0.3 (RELAX_Config.hlsli)
// Referenced as gRoughnessEdgeStoppingRelaxation in RELAX_AtrousSmem.cs.hlsl:300
const float gRoughnessEdgeStoppingRelaxation = 0.3;
// gNormalEdgeStoppingRelaxation default = 0.3 (used in spec normal weight params)
const float gNormalEdgeStoppingRelaxation = 0.3;
// Reference: gRoughnessEdgeStoppingEnabled = true (default)
const bool  gRoughnessEdgeStoppingEnabled = true;
// Specular reprojection confidence: pipeline deleted, use 1.0 (fully confident)
const float specReprojectionConfidence = 1.0;

// ---------------------------------------------------------------------------
// computeVariance: 3x3 Gaussian blur of the 2nd moment to estimate variance.
// Reference: RELAX_AtrousSmem.cs.hlsl:42-94 computeVariance().
// In the reference this uses shared memory; here we use texelFetch (same result).
// The 3x3 kernel is: { {1/4, 1/8}, {1/8, 1/16} } (reference lines 59-63).
// ---------------------------------------------------------------------------
void computeVariance(
    ivec2       centerCoord,
    sampler2D   diffTex,
    sampler2D   specTex,
    ivec2       texSize,
    out float   diffVariance,
    out float   specVariance
) {
    // Reference kernel[abs(dx)][abs(dy)]
    const float kernel[2] = float[](0.25, 0.125); // kernel[0][0]=1/4, kernel[1][0]=1/8
    const float kernelDiag = 0.0625;               // kernel[1][1]=1/16

    vec4 diffSum  = vec4(0.0);
    vec4 specSum  = vec4(0.0);

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            ivec2 p = clamp(centerCoord + ivec2(dx, dy), ivec2(0), texSize - ivec2(1));
            // kernel weight: kernel[abs(dx)][abs(dy)] where corner = 1/16, edge = 1/8, center = 1/4
            float k = (abs(dx) == 0 && abs(dy) == 0) ? 0.25
                    : (abs(dx) == 1 && abs(dy) == 1)  ? 0.0625
                    : 0.125;
            diffSum += texelFetch(diffTex, p, 0) * k;
            specSum += texelFetch(specTex, p, 0) * k;
        }
    }

    // Reference lines 85-87 / 90-92:
    //   float specular1stMoment = Color::Luminance(specularSum.rgb);
    //   float specular2ndMoment = specularSum.a;
    //   specularVariance = max(0, specular2ndMoment - specular1stMoment^2);
    float diff1stMoment = nrd_luminance(diffSum.rgb);
    float diff2ndMoment = diffSum.a;
    diffVariance = max(0.0, diff2ndMoment - diff1stMoment * diff1stMoment);

    float spec1stMoment = nrd_luminance(specSum.rgb);
    float spec2ndMoment = specSum.a;
    specVariance = max(0.0, spec2ndMoment - spec1stMoment * spec1stMoment);
}

void main() {
    // ---------------------------------------------------------------------------
    // Tile-based early out.
    // Reference: RELAX_AtrousSmem.cs.hlsl:127, 154-155
    // ---------------------------------------------------------------------------
    float isSky = texelFetch(nrd_in_tiles, tex_coord >> 4, 0).r;
    if (isSky > 0.5) {
        discard;
    }

    ivec2 texSize = textureSize(nrd_diff_illum_prev, 0);

    vec3  centerPosition     = texelFetch(radiosity_position,       tex_coord, 0).xyz;
    vec3  centerGeomNormal   = nrd_safe_normal(texelFetch(radiosity_normal,        tex_coord, 0).xyz);
    vec3  centerMappedNormal = nrd_select_surface_normal(centerGeomNormal, texelFetch(radiosity_mapped_normal, tex_coord, 0).xyz);
    vec4  centerMaterial     = texelFetch(radiosity_material,        tex_coord, 0);
    float centerRoughness    = clamp(centerMaterial.x, 0.0, 1.0);

    // Reference: RELAX_AtrousSmem.cs.hlsl:166
    float historyLength = nrd_decoded_history(texelFetch(nrd_history_length, tex_coord, 0));

    // Reference: RELAX_AtrousSmem.cs.hlsl:157-159 IsInDenoisingRange check
    float centerViewZ = nrd_compute_view_z(centerPosition);
    if (centerViewZ > ph_nrd_denoising_range) {
        discard;
    }

    // ---------------------------------------------------------------------------
    // Branch: running A-trous or spatial variance estimation.
    // Reference: RELAX_AtrousSmem.cs.hlsl:169
    // ---------------------------------------------------------------------------
    if (historyLength >= gHistoryThreshold) {
        // -----------------------------------------------------------------
        // A-trous 3x3 branch (reference lines 171-373)
        // -----------------------------------------------------------------

        // Reference lines 172-186: computeVariance()
        float centerDiffVar;
        float centerSpecVar;
        computeVariance(tex_coord, nrd_diff_illum_prev, nrd_spec_illum_prev, texSize, centerDiffVar, centerSpecVar);

        // Reference line 189: diffuseLobeAngleFraction = gLobeAngleFraction (stride=1, no step-size scaling)
        float diffuseLobeAngleFraction = ph_nrd_lobe_angle_fraction;

        // ---- Diffuse setup (reference lines 234-258) ----
        vec4  centerDiffData      = texelFetch(nrd_diff_illum_prev, tex_coord, 0);
        float centerDiffLuminance = nrd_luminance(centerDiffData.rgb);
        // Reference line 236: 1.0 / max(1e-4, gDiffPhiLuminance * sqrt(centerDiffuseVar))
        float diffPhiLInv = 1.0 / max(1e-4, ph_nrd_phi_luminance_diff * sqrt(centerDiffVar));
        // No confidence pipeline: diffuseLuminanceWeightRelaxation = 1.0
        float diffLuminanceWeightRelaxation = 1.0;
        // Reference line 252: GetNormalWeightParam2(1.0, diffuseLobeAngleFraction)
        float diffNormalWeightParam = nrd_normal_weight_param(1.0, diffuseLobeAngleFraction);

        // Reference lines 254-256: centre initialisation (w = kernel^2 for SMEM, iterate includes centre)
        float sumWDiff = 0.0;
        vec4  sumDiffIllumAnd2ndMoment = vec4(0.0);

        // ---- Specular setup (reference lines 191-231) ----
        vec4  centerSpecData      = texelFetch(nrd_spec_illum_prev, tex_coord, 0);
        float centerSpecLuminance = nrd_luminance(centerSpecData.rgb);
        float specPhiLInv = 1.0 / max(1e-4, ph_nrd_phi_luminance_spec * sqrt(centerSpecVar));

        // Reference lines 195-196: GetRoughnessWeightParams
        vec2 roughnessWeightParams = nrd_roughness_weight_params(centerRoughness, ph_nrd_roughness_fraction);

        // Reference lines 196-197: simplified + full lobe angle fractions (no confidence)
        float diffLobeAngleFractionForSimplifiedSpec = diffuseLobeAngleFraction;
        float specularLobeAngleFraction = ph_nrd_lobe_angle_fraction;

        // Reference lines 199-200: specularLuminanceWeightRelaxation (no confidence, no step size cap)
        float specLuminanceWeightRelaxation = 1.0;

        // Reference lines 216-217: GetNormalWeightParam2(1.0, diffLobeAngleFractionForSimplifiedSpec)
        float specNormalWeightParamSimplified = nrd_normal_weight_param(1.0, diffLobeAngleFractionForSimplifiedSpec);
        // Reference lines 217-224: GetNormalWeightParams_ATrous(...)
        // Confidence pipeline deleted; specReprojectionConfidence = 1.0 (fully confident)
        vec2 specNormalWeightParams = nrd_spec_normal_weight_params_atrous(
            centerRoughness, historyLength, specReprojectionConfidence,
            gNormalEdgeStoppingRelaxation, specularLobeAngleFraction, ph_nrd_spec_lobe_angle_slack
        );

        vec3  centerV  = -normalize(centerPosition - world_camera_position);
        float sumWSpec = 0.0;
        vec4  sumSpecIllumAnd2ndMoment = vec4(0.0);

        // Reference line 262: gDepthThreshold * centerViewZ (perspective mode)
        float depthThreshold = ph_nrd_depth_threshold * centerViewZ;

        // -----------------------------------------------------------------
        // 3x3 sample loop (reference lines 264-349)
        // Note: SMEM pass includes the centre in the loop (isCenter branch).
        // -----------------------------------------------------------------
        for (int j = -1; j <= 1; j++) {
            for (int i = -1; i <= 1; i++) {
                bool isCenter  = (i == 0 && j == 0);
                ivec2 p        = tex_coord + ivec2(i, j);
                bool  isInside = all(greaterThanEqual(p, ivec2(0))) && all(lessThan(p, texSize));

                // Reference line 273: kernel = isInside ? gaussian[|i|]*gaussian[|j|] : 0
                float kernel = isInside ? gaussian3x3[abs(i)] * gaussian3x3[abs(j)] : 0.0;
                if (kernel == 0.0) continue;

                ivec2 sampleCoord = clamp(p, ivec2(0), texSize - ivec2(1));

                vec4  sampleNormalMat   = texelFetch(radiosity_material,       sampleCoord, 0);
                float sampleRoughness   = clamp(sampleNormalMat.x, 0.0, 1.0);
                vec3  sampleGeomNormal  = nrd_safe_normal(texelFetch(radiosity_normal,       sampleCoord, 0).xyz);
                vec3  sampleMappedNormal = nrd_select_surface_normal(sampleGeomNormal,
                                               texelFetch(radiosity_mapped_normal, sampleCoord, 0).xyz);
                vec3  sampleWorldPos    = texelFetch(radiosity_position,       sampleCoord, 0).xyz;

                // Reference lines 284-289: GetPlaneDistanceWeight_Atrous * kernel
                float geometryW = nrd_plane_distance_weight(
                    centerPosition, centerMappedNormal, sampleWorldPos, depthThreshold
                );
                geometryW *= kernel;

                // ---- Specular tap (reference lines 293-323) ----
                {
                    // Reference line 300: sampleV = -normalize(sampleWorldPos + relax * centerWorldPos)
                    vec3 sampleV = -normalize(sampleWorldPos - world_camera_position
                                             + gRoughnessEdgeStoppingRelaxation * (centerPosition - world_camera_position));

                    // Reference line 301: normalWSpecularSimplified
                    float normalWSpecSimplified = nrd_normal_weight_atrous(centerMappedNormal, sampleMappedNormal,
                                                                           specNormalWeightParamSimplified);
                    // Reference line 302: GetSpecularNormalWeight_ATrous
                    float normalWSpecFull = nrd_spec_normal_weight_atrous_full(specNormalWeightParams,
                                               centerMappedNormal, sampleMappedNormal, centerV, sampleV);
                    // Reference line 304: ComputeWeight(sampleRoughness, roughnessWeightParams)
                    float roughnessWSpec = nrd_compute_weight(sampleRoughness,
                                              roughnessWeightParams.x, roughnessWeightParams.y);

                    vec4  sampleSpecData  = texelFetch(nrd_spec_illum_prev, sampleCoord, 0);
                    float sampleSpecLuma  = nrd_luminance(sampleSpecData.rgb);

                    // Reference lines 310-312
                    float specLumaW = abs(centerSpecLuminance - sampleSpecLuma) * specPhiLInv;
                    specLumaW = min(gSpecMaxLuminanceRelativeDifference, specLumaW);
                    specLumaW *= specLuminanceWeightRelaxation;

                    // Reference line 314: wSpecular = geometryW * exp(-specularLuminanceW)
                    float wSpec = geometryW * exp(-specLumaW);
                    // Reference line 315
                    wSpec *= gRoughnessEdgeStoppingEnabled
                        ? (normalWSpecFull * roughnessWSpec)
                        : normalWSpecSimplified;
                    // Reference line 316
                    wSpec *= nrd_material_weight(centerMaterial, sampleNormalMat);
                    // Reference line 317: centre pixel gets kernel weight directly
                    wSpec = isCenter ? kernel : wSpec;

                    // Reference line 319-320: accumulate with w (rgb) and w*w (.a = 2nd moment)
                    // .a invariant: accumulate sampleSpecData.a (= 2nd moment) with w^2 weight
                    sumWSpec += wSpec;
                    sumSpecIllumAnd2ndMoment += vec4(sampleSpecData.rgb * wSpec,
                                                     sampleSpecData.a  * wSpec * wSpec);
                }

                // ---- Diffuse tap (reference lines 325-347) ----
                {
                    // Reference line 327: angled = acos(dot(centerNormal, sampleNormal))
                    // Reference line 328: normalWDiffuse = ComputeWeight(angled, diffNormalWeightParam, 0)
                    float normalWDiff = nrd_normal_weight_atrous(centerMappedNormal, sampleMappedNormal, diffNormalWeightParam);

                    vec4  sampleDiffData = texelFetch(nrd_diff_illum_prev, sampleCoord, 0);
                    float sampleDiffLuma = nrd_luminance(sampleDiffData.rgb);

                    // Reference lines 334-336
                    float diffLumaW = abs(centerDiffLuminance - sampleDiffLuma) * diffPhiLInv;
                    diffLumaW = min(gDiffMaxLuminanceRelativeDifference, diffLumaW);
                    diffLumaW *= diffLuminanceWeightRelaxation;

                    // Reference line 338-339
                    float wDiff = geometryW * normalWDiff * exp(-diffLumaW);
                    wDiff *= nrd_material_weight(centerMaterial, sampleNormalMat);
                    // Reference line 341: centre pixel gets kernel weight directly
                    wDiff = isCenter ? kernel : wDiff;

                    // Reference lines 342-343: accumulate
                    sumWDiff += wDiff;
                    sumDiffIllumAnd2ndMoment += vec4(sampleDiffData.rgb * wDiff,
                                                     sampleDiffData.a  * wDiff * wDiff);
                }
            }
        }

        // Reference lines 350-373: normalise
        // .a invariant: divide rgb by sumW, divide .a (2nd moment accumulation) by sumW^2
        sumWSpec = max(sumWSpec, 1e-6);
        vec4 filteredSpec = vec4(sumSpecIllumAnd2ndMoment.rgb / sumWSpec,
                                 sumSpecIllumAnd2ndMoment.a  / (sumWSpec * sumWSpec));

        sumWDiff = max(sumWDiff, 1e-6);
        vec4 filteredDiff = vec4(sumDiffIllumAnd2ndMoment.rgb / sumWDiff,
                                 sumDiffIllumAnd2ndMoment.a  / (sumWDiff * sumWDiff));

        // Reference writes (rgb, variance) to gOut_*_Variance in SMEM pass.
        // Contract section 11.6 mandates (.a = secondMoment) invariant.
        // We write back the normalised 2nd moment (filtered.a) — NOT variance.
        nrd_diff_atrous_out = filteredDiff;
        nrd_spec_atrous_out = filteredSpec;

    } else {
        // -----------------------------------------------------------------
        // Spatial variance estimation branch (reference lines 377-481)
        // Used when history is too short for reliable variance estimate.
        // Reference: RELAX_AtrousSmem.cs.hlsl:377-481
        // -----------------------------------------------------------------

        // Reference line 399: diffuseNormalWeightParam = GetNormalWeightParam2(1.0, gLobeAngleFraction)
        float diffNormalWeightParam = nrd_normal_weight_param(1.0, ph_nrd_lobe_angle_fraction);

        float sumWDiff = 0.0;
        vec3  sumDiffIllum    = vec3(0.0);
        float sumDiff1stMoment = 0.0;
        float sumDiff2ndMoment = 0.0;

        float sumWSpec = 0.0;
        vec3  sumSpecIllum    = vec3(0.0);
        float sumSpec1stMoment = 0.0;
        float sumSpec2ndMoment = 0.0;

        vec4 centerMaterialID = texelFetch(radiosity_material, tex_coord, 0);

        // Reference lines 403-452: 5x5 loop
        for (int cy = -2; cy <= 2; cy++) {
            for (int cx = -2; cx <= 2; cx++) {
                ivec2 p = clamp(tex_coord + ivec2(cx, cy), ivec2(0), texSize - ivec2(1));

                vec3  sampleGeomNormal   = nrd_safe_normal(texelFetch(radiosity_normal, p, 0).xyz);
                vec3  sampleMappedNormal = nrd_select_surface_normal(sampleGeomNormal,
                                               texelFetch(radiosity_mapped_normal, p, 0).xyz);
                vec4  sampleMaterialVal  = texelFetch(radiosity_material, p, 0);

                // Reference lines 415-417: normal weight (same for diff and spec in this branch)
                float angle   = acos(clamp(dot(centerMappedNormal, sampleMappedNormal), -1.0, 1.0));
                float normalW = nrd_compute_weight(angle, diffNormalWeightParam, 0.0);

                // Reference lines 419-433: specular
                {
                    vec4  sampleSpec     = texelFetch(nrd_spec_illum_prev, p, 0);
                    float sampleSpec1st  = nrd_luminance(sampleSpec.rgb);
                    float sampleSpec2nd  = sampleSpec.a;
                    // Reference line 424: specularW = normalW * depthW (depthW = 1.0)
                    float specW = normalW;
                    specW *= nrd_material_weight(centerMaterialID, sampleMaterialVal);
                    sumWSpec        += specW;
                    sumSpecIllum    += sampleSpec.rgb * specW;
                    sumSpec1stMoment += sampleSpec1st * specW;
                    sumSpec2ndMoment += sampleSpec2nd * specW;
                }

                // Reference lines 436-451: diffuse
                {
                    vec4  sampleDiff     = texelFetch(nrd_diff_illum_prev, p, 0);
                    float sampleDiff1st  = nrd_luminance(sampleDiff.rgb);
                    float sampleDiff2nd  = sampleDiff.a;
                    // Reference line 441: diffuseW = normalW * depthW (depthW = 1.0)
                    float diffW = normalW;
                    diffW *= nrd_material_weight(centerMaterialID, sampleMaterialVal);
                    sumWDiff        += diffW;
                    sumDiffIllum    += sampleDiff.rgb * diffW;
                    sumDiff1stMoment += sampleDiff1st * diffW;
                    sumDiff2ndMoment += sampleDiff2nd * diffW;
                }
            }
        }

        // Reference line 455: boost = max(1.0, 4.0 / (historyLength + 1.0))
        float boost = max(1.0, 4.0 / (historyLength + 1.0));

        // Reference lines 457-467: specular output
        sumWSpec = max(sumWSpec, 1e-6);
        sumSpecIllum    /= sumWSpec;
        sumSpec1stMoment /= sumWSpec;
        sumSpec2ndMoment /= sumWSpec;
        float specVariance   = max(0.0, sumSpec2ndMoment - sumSpec1stMoment * sumSpec1stMoment);
        specVariance *= boost;
        // .a invariant: write secondMoment, not variance.
        // The variance is only boosted for display; we reconstruct secondMoment as:
        //   secondMoment = variance + luma^2
        float specOutLuma    = nrd_luminance(sumSpecIllum);
        float specOutSecondMoment = specVariance + specOutLuma * specOutLuma;
        nrd_spec_atrous_out = vec4(sumSpecIllum, specOutSecondMoment);

        // Reference lines 470-480: diffuse output
        sumWDiff = max(sumWDiff, 1e-6);
        sumDiffIllum    /= sumWDiff;
        sumDiff1stMoment /= sumWDiff;
        sumDiff2ndMoment /= sumWDiff;
        float diffVariance   = max(0.0, sumDiff2ndMoment - sumDiff1stMoment * sumDiff1stMoment);
        diffVariance *= boost;
        float diffOutLuma    = nrd_luminance(sumDiffIllum);
        float diffOutSecondMoment = diffVariance + diffOutLuma * diffOutLuma;
        nrd_diff_atrous_out = vec4(sumDiffIllum, diffOutSecondMoment);
    }
}
