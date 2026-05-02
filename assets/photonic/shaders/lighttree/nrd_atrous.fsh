#version 430

// NRD RELAX A-trous passes 2-5 (strides 2, 4, 8, 16). Fused diff + spec.
// Reference: RELAX_Atrous.cs.hlsl
//
// Reads from ping or pong (Java rebinds nrd_diff_atrous_input / nrd_spec_atrous_input
// to the correct ping/pong buffer each pass).
//
// .a invariant (contract section 11.6, RELAX_Atrous.cs.hlsl accumulation block):
//   Input  .a = secondMoment (E[luma^2]).
//   Variance is computed INTERNALLY as max(secondMoment - luma*luma, 0).
//   Output .a = filtered secondMoment, using w^2 weighting identical to reference.
//   The reference pattern (RELAX_Atrous.cs.hlsl:93, 123, 198, 225):
//     sumIllumAnd2ndMoment += float4(w.xxx, w*w) * sampleData
//     output = sum / float4(sumW.xxx, sumW*sumW)
//   This correctly renormalises the 2nd-moment accumulation.
//   DO NOT write variance into .a.

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_diff_atrous_out;
layout(location = 1) out vec4 nrd_spec_atrous_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

// Samplers declared in samplers.glsl (via header.glsl → photonics.glsl → ph_samplers.glsl → samplers.glsl):
//   nrd_diff_atrous_input, nrd_spec_atrous_input

uniform int   direct_atrous_step_size;    // 2, 4, 8, 16 for passes 2-5
uniform int   direct_atrous_is_last_pass; // 1 on last pass; shader output unchanged;
                                           // Java routes to final FBO based on this

// NRD RELAX constants — no confidence pipeline, no SH mode
// Reference: RELAX_Atrous.cs.hlsl
const float gaussian3x3[2] = float[](0.44198, 0.27901);

// gSpecMaxLuminanceRelativeDifference: -log(saturate(minLumaWeight=0)) -> +Inf; use 1e9
const float gSpecMaxLuminanceRelativeDifference = 1e9;
const float gDiffMaxLuminanceRelativeDifference = 1e9;

// gRoughnessEdgeStoppingRelaxation default = 0.3 (RELAX_Config.hlsli)
// Reference: RELAX_Atrous.cs.hlsl:175
const float gRoughnessEdgeStoppingRelaxation = 0.3;
// gNormalEdgeStoppingRelaxation default = 0.3
const float gNormalEdgeStoppingRelaxation = 0.3;
// gRoughnessEdgeStoppingEnabled = true
const bool  gRoughnessEdgeStoppingEnabled = true;

// Specular reprojection confidence: pipeline deleted, use 1.0 (fully confident).
// Reference: RELAX_Atrous.cs.hlsl:62-65 — only applied for stepSize <= 4.
const float specReprojectionConfidenceRaw = 1.0;
// gLuminanceEdgeStoppingRelaxation default = 0.0 (RELAX_Config.hlsli)
const float gLuminanceEdgeStoppingRelaxation = 0.0;

// ---------------------------------------------------------------------------
// Unsigned hash for random offset dithering.
// Reference: RELAX_Atrous.cs.hlsl:139-141 Rng::Hash::Initialize / GetFloat2.
// ---------------------------------------------------------------------------
uint nrd_pcg_hash(uint x) {
    x ^= x >> 16u;
    x *= 0x45d9f3bu;
    x ^= x >> 16u;
    return x;
}

void main() {
    // ---------------------------------------------------------------------------
    // Tile-based early out.
    // Reference: RELAX_Atrous.cs.hlsl:27-29
    // ---------------------------------------------------------------------------
    float isSky = texelFetch(nrd_in_tiles, tex_coord >> 4, 0).r;
    if (isSky > 0.5) {
        discard;
    }

    // Reference: RELAX_Atrous.cs.hlsl:32-34
    vec3  centerPosition = texelFetch(radiosity_position, tex_coord, 0).xyz;
    float centerViewZ    = nrd_compute_view_z(centerPosition);
    if (centerViewZ > ph_nrd_denoising_range) {
        discard;
    }

    ivec2 texSize = textureSize(nrd_diff_atrous_input, 0);

    // Reference: RELAX_Atrous.cs.hlsl:38-42
    vec3  centerGeomNormal   = nrd_safe_normal(texelFetch(radiosity_normal,        tex_coord, 0).xyz);
    vec3  centerMappedNormal = nrd_select_surface_normal(centerGeomNormal,
                                   texelFetch(radiosity_mapped_normal, tex_coord, 0).xyz);
    vec4  centerMaterial     = texelFetch(radiosity_material, tex_coord, 0);
    float centerRoughness    = clamp(centerMaterial.x, 0.0, 1.0);

    // Reference: RELAX_Atrous.cs.hlsl:42
    float historyLength = nrd_decoded_history(texelFetch(nrd_history_length, tex_coord, 0));

    // Reference: RELAX_Atrous.cs.hlsl:45-50
    // Weight strictness increases as A-trous step size increases.
    float diffuseLobeAngleFraction = ph_nrd_lobe_angle_fraction / sqrt(float(max(direct_atrous_step_size, 1)));
    diffuseLobeAngleFraction = mix(0.99, diffuseLobeAngleFraction, clamp(historyLength / 5.0, 0.0, 1.0));

    // ---------------------------------------------------------------------------
    // Specular setup (reference lines 52-97)
    // ---------------------------------------------------------------------------
    vec4  centerSpecData      = texelFetch(nrd_spec_atrous_input, tex_coord, 0);
    float centerSpecLuminance = nrd_luminance(centerSpecData.rgb);
    // .a = secondMoment; compute variance internally
    float centerSpecVar       = max(centerSpecData.a - centerSpecLuminance * centerSpecLuminance, 0.0);
    float specPhiLInv         = 1.0 / max(1e-4, ph_nrd_phi_luminance_spec * sqrt(centerSpecVar));

    // Reference line 58: GetRoughnessWeightParams
    vec2 roughnessWeightParams = nrd_roughness_weight_params(centerRoughness, ph_nrd_roughness_fraction);

    // Reference lines 59-60: simplified lobe fraction (no confidence)
    float diffLobeAngleFractionForSimplifiedSpec = diffuseLobeAngleFraction;
    float specularLobeAngleFraction = ph_nrd_lobe_angle_fraction;

    // Reference lines 63-65: specularLuminanceWeightRelaxation
    // Confidence pipeline deleted; specReprojectionConfidenceRaw = 1.0 always.
    // Reference: lerp(1.0, specReprojectionConfidence, gLuminanceEdgeStoppingRelaxation)
    // With gLuminanceEdgeStoppingRelaxation = 0 -> relaxation = 1.0 always.
    float specLuminanceWeightRelaxation = 1.0;
    if (direct_atrous_step_size <= 4) {
        specLuminanceWeightRelaxation = mix(1.0, specReprojectionConfidenceRaw, gLuminanceEdgeStoppingRelaxation);
    }

    // Reference line 82: specularNormalWeightParamSimplified
    float specNormalWeightParamSimplified = nrd_normal_weight_param(1.0, diffLobeAngleFractionForSimplifiedSpec);
    // Reference lines 83-90: GetNormalWeightParams_ATrous
    vec2 specNormalWeightParams = nrd_spec_normal_weight_params_atrous(
        centerRoughness, historyLength, specReprojectionConfidenceRaw,
        gNormalEdgeStoppingRelaxation, specularLobeAngleFraction, ph_nrd_spec_lobe_angle_slack
    );

    // Reference lines 92-93: initialise accumulators with centre pixel.
    // Centre kernel weight = gaussian3x3[0]^2 = 0.44198^2
    float centerKernelW = gaussian3x3[0] * gaussian3x3[0];
    // Reference line 93: sumSpecularIlluminationAndVariance = center * float4(w.xxx, w*w)
    float sumWSpec = centerKernelW;
    vec4  sumSpecIllumAnd2ndMoment = centerSpecData * vec4(vec3(centerKernelW), centerKernelW * centerKernelW);

    vec3 centerV = -normalize(centerPosition - world_camera_position);

    // ---------------------------------------------------------------------------
    // Diffuse setup (reference lines 100-127)
    // ---------------------------------------------------------------------------
    vec4  centerDiffData      = texelFetch(nrd_diff_atrous_input, tex_coord, 0);
    float centerDiffLuminance = nrd_luminance(centerDiffData.rgb);
    float centerDiffVar       = max(centerDiffData.a - centerDiffLuminance * centerDiffLuminance, 0.0);
    float diffPhiLInv         = 1.0 / max(1e-4, ph_nrd_phi_luminance_diff * sqrt(centerDiffVar));

    // No confidence pipeline: diffuseLuminanceWeightRelaxation = 1.0
    float diffLuminanceWeightRelaxation = 1.0;
    // Reference line 120: GetNormalWeightParam2(1.0, diffuseLobeAngleFraction)
    float diffNormalWeightParam = nrd_normal_weight_param(1.0, diffuseLobeAngleFraction);

    // Reference lines 122-123: initialise with centre
    float sumWDiff = centerKernelW;
    vec4  sumDiffIllumAnd2ndMoment = centerDiffData * vec4(vec3(centerKernelW), centerKernelW * centerKernelW);

    // Reference line 133: depthThreshold
    float depthThreshold = ph_nrd_depth_threshold * centerViewZ;

    // Reference lines 136-141: random offset for large step sizes
    ivec2 sampleOffset = ivec2(0);
    if (direct_atrous_step_size > 4) {
        // Reference: Rng::Hash::Initialize(pixelPos, gFrameIndex); GetFloat2()
        uint seed = uint(tex_coord.x) + uint(tex_coord.y) * uint(texSize.x)
                  + uint(frameCounter) * 16777259u;
        uint h = nrd_pcg_hash(seed);
        vec2 rnd = vec2(float(h & 0xFFFFu), float((h >> 16u) & 0xFFFFu)) / 65535.0;
        // Reference: offset = int2(gStepSize.xx * 0.5 * (Rng::Hash::GetFloat2() - 0.5))
        sampleOffset = ivec2(vec2(direct_atrous_step_size) * 0.5 * (rnd - 0.5));
    }

    // ---------------------------------------------------------------------------
    // 3x3 sample loop, skipping centre (reference lines 143-232).
    // ---------------------------------------------------------------------------
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            // Reference line 149: skip centre
            if (i == 0 && j == 0) continue;

            // Reference line 152
            ivec2 p        = tex_coord + sampleOffset + ivec2(i, j) * direct_atrous_step_size;
            bool  isInside = all(greaterThanEqual(p, ivec2(0))) && all(lessThan(p, texSize));
            float kernel   = gaussian3x3[abs(i)] * gaussian3x3[abs(j)];

            ivec2 sampleCoord = clamp(p, ivec2(0), texSize - ivec2(1));

            // Reference lines 157-161: fetch normal, roughness, viewZ
            vec4  sampleMatData      = texelFetch(radiosity_material,       sampleCoord, 0);
            float sampleRoughness    = clamp(sampleMatData.x, 0.0, 1.0);
            vec3  sampleGeomNormal   = nrd_safe_normal(texelFetch(radiosity_normal,        sampleCoord, 0).xyz);
            vec3  sampleMappedNormal = nrd_select_surface_normal(sampleGeomNormal,
                                           texelFetch(radiosity_mapped_normal, sampleCoord, 0).xyz);
            vec3  sampleWorldPos     = texelFetch(radiosity_position,       sampleCoord, 0).xyz;
            float sampleViewZ        = nrd_compute_view_z(sampleWorldPos);

            // Reference lines 166-169: geometry weight
            float geometryW = nrd_plane_distance_weight(centerPosition, centerMappedNormal,
                                                        sampleWorldPos, depthThreshold);
            geometryW *= kernel;
            // Reference line 169: gate on isInside and denoising range
            geometryW *= float(isInside && (sampleViewZ <= ph_nrd_denoising_range));

            // -----------------------------------------------------------------
            // Specular tap (reference lines 171-202)
            // -----------------------------------------------------------------
            {
                // Reference line 175: sampleV = -normalize(sampleWorldPos + relax * centerWorldPos)
                vec3 sampleV = -normalize(sampleWorldPos - world_camera_position
                                         + gRoughnessEdgeStoppingRelaxation * (centerPosition - world_camera_position));

                // Reference lines 178-181
                float normalWSpecSimplified = nrd_normal_weight_atrous(centerMappedNormal, sampleMappedNormal,
                                                                        specNormalWeightParamSimplified);
                float normalWSpecFull = nrd_spec_normal_weight_atrous_full(specNormalWeightParams,
                                            centerMappedNormal, sampleMappedNormal, centerV, sampleV);
                float roughnessWSpec  = nrd_compute_weight(sampleRoughness,
                                            roughnessWeightParams.x, roughnessWeightParams.y);

                // Reference line 184
                float wSpec = geometryW * (gRoughnessEdgeStoppingEnabled
                    ? (normalWSpecFull * roughnessWSpec)
                    : normalWSpecSimplified);
                wSpec *= nrd_material_weight(centerMaterial, sampleMatData);

                // Reference lines 186-201: luminance weight (fetched only if wSpec > 1e-4)
                if (wSpec > 1e-4) {
                    vec4  sampleSpecData = texelFetch(nrd_spec_atrous_input, sampleCoord, 0);
                    float sampleSpecLuma = nrd_luminance(sampleSpecData.rgb);

                    // Reference lines 191-195
                    float specLumaW = abs(centerSpecLuminance - sampleSpecLuma) * specPhiLInv;
                    specLumaW = min(gSpecMaxLuminanceRelativeDifference, specLumaW);
                    specLumaW *= specLuminanceWeightRelaxation;
                    wSpec *= exp(-specLumaW);

                    // Reference line 197-198: accumulate with float4(w.xxx, w*w)
                    // .a (secondMoment) weighted by w*w, rgb weighted by w
                    sumWSpec += wSpec;
                    sumSpecIllumAnd2ndMoment += vec4(sampleSpecData.rgb * wSpec,
                                                     sampleSpecData.a  * wSpec * wSpec);
                }
            }

            // -----------------------------------------------------------------
            // Diffuse tap (reference lines 204-229)
            // -----------------------------------------------------------------
            {
                // Reference lines 207-208
                float normalWDiff = nrd_normal_weight_atrous(centerMappedNormal, sampleMappedNormal,
                                                              diffNormalWeightParam);

                // Reference line 211
                float wDiff = geometryW * normalWDiff;
                wDiff *= nrd_material_weight(centerMaterial, sampleMatData);

                // Reference lines 213-228: luminance weight (fetched only if wDiff > 1e-4)
                if (wDiff > 1e-4) {
                    vec4  sampleDiffData = texelFetch(nrd_diff_atrous_input, sampleCoord, 0);
                    float sampleDiffLuma = nrd_luminance(sampleDiffData.rgb);

                    // Reference lines 218-221
                    float diffLumaW = abs(centerDiffLuminance - sampleDiffLuma) * diffPhiLInv;
                    diffLumaW = min(gDiffMaxLuminanceRelativeDifference, diffLumaW);
                    diffLumaW *= diffLuminanceWeightRelaxation;
                    wDiff *= exp(-diffLumaW);

                    // Reference line 223-225: accumulate with float4(w.xxx, w*w)
                    // .a (secondMoment) weighted by w*w, rgb weighted by w
                    sumWDiff += wDiff;
                    sumDiffIllumAnd2ndMoment += vec4(sampleDiffData.rgb * wDiff,
                                                     sampleDiffData.a  * wDiff * wDiff);
                }
            }
        }
    }

    // ---------------------------------------------------------------------------
    // Normalise and write output (reference lines 234-258).
    // Reference: filteredSpec = sumSpec / float4(sumWSpec.xxx, sumWSpec * sumWSpec)
    // .a invariant: output is secondMoment (NOT variance, NOT history length).
    // The reference stores currHistoryLength - 1 into .w on gIsLastPass == 1,
    // but that is only used by NRD internally; Java handles FBO routing on last
    // pass. We always write secondMoment to keep the invariant across all passes.
    // ---------------------------------------------------------------------------
    vec4 filteredSpec = sumSpecIllumAnd2ndMoment / vec4(vec3(sumWSpec), sumWSpec * sumWSpec);
    vec4 filteredDiff = sumDiffIllumAnd2ndMoment / vec4(vec3(sumWDiff), sumWDiff * sumWDiff);

    nrd_diff_atrous_out = filteredDiff;
    nrd_spec_atrous_out = filteredSpec;
}
