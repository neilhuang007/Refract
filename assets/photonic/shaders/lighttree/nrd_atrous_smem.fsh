#version 430

// First RELAX A-trous pass. The shader keeps .a as second moment throughout
// the atrous chain; variance is derived only for weighting.

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_diff_atrous_out;
layout(location = 1) out vec4 nrd_spec_atrous_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform int direct_atrous_step_size;
uniform int direct_atrous_is_last_pass;

const float gaussian3x3[2] = float[](0.44198, 0.27901);
const float gHistoryThreshold = 6.0;
const float gSpecMaxLuminanceRelativeDifference = 1e9;
const float gDiffMaxLuminanceRelativeDifference = 1e9;
const float gRoughnessEdgeStoppingRelaxation = 0.3;
const float gNormalEdgeStoppingRelaxation = 0.3;
const bool gRoughnessEdgeStoppingEnabled = true;
const float specReprojectionConfidence = 1.0;

void nrd_write_zero_atrous() {
    nrd_diff_atrous_out = vec4(0.0);
    nrd_spec_atrous_out = vec4(0.0);
}

void computeVariance(
    ivec2 centerCoord,
    sampler2D diffTex,
    sampler2D specTex,
    ivec2 texSize,
    out float diffVariance,
    out float specVariance
) {
    vec4 diffSum = vec4(0.0);
    vec4 specSum = vec4(0.0);

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            ivec2 p = clamp(centerCoord + ivec2(dx, dy), ivec2(0), texSize - ivec2(1));
            float k = (abs(dx) == 0 && abs(dy) == 0) ? 0.25
                    : (abs(dx) == 1 && abs(dy) == 1) ? 0.0625
                    : 0.125;
            diffSum += texelFetch(diffTex, p, 0) * k;
            specSum += texelFetch(specTex, p, 0) * k;
        }
    }

    float diff1stMoment = nrd_luminance(diffSum.rgb);
    float spec1stMoment = nrd_luminance(specSum.rgb);
    diffVariance = max(0.0, diffSum.a - diff1stMoment * diff1stMoment);
    specVariance = max(0.0, specSum.a - spec1stMoment * spec1stMoment);
}

void main() {
    float isSky = texelFetch(nrd_in_tiles, tex_coord >> 4, 0).r;
    if (isSky > 0.5) {
        nrd_write_zero_atrous();
        return;
    }

    ivec2 texSize = textureSize(nrd_diff_illum_prev, 0);
    vec3 centerPosition = texelFetch(radiosity_position, tex_coord, 0).xyz;
    float centerViewZ = nrd_compute_view_z(centerPosition);
    if (centerViewZ > ph_nrd_denoising_range) {
        nrd_write_zero_atrous();
        return;
    }

    vec3 centerGeomNormal = nrd_safe_normal(texelFetch(radiosity_normal, tex_coord, 0).xyz);
    vec3 centerMappedNormal =
        nrd_select_surface_normal(centerGeomNormal, texelFetch(radiosity_mapped_normal, tex_coord, 0).xyz);
    vec4 centerMaterial = texelFetch(radiosity_material, tex_coord, 0);
    float centerRoughness = clamp(centerMaterial.x, 0.0, 1.0);
    float historyLength = nrd_decoded_history(texelFetch(nrd_history_length, tex_coord, 0));

    if (historyLength >= gHistoryThreshold) {
        float centerDiffVar;
        float centerSpecVar;
        computeVariance(tex_coord, nrd_diff_illum_prev, nrd_spec_illum_prev, texSize, centerDiffVar, centerSpecVar);

        vec4 centerDiffData = texelFetch(nrd_diff_illum_prev, tex_coord, 0);
        vec4 centerSpecData = texelFetch(nrd_spec_illum_prev, tex_coord, 0);
        float centerDiffLuminance = nrd_luminance(centerDiffData.rgb);
        float centerSpecLuminance = nrd_luminance(centerSpecData.rgb);
        float diffPhiLInv = 1.0 / max(1e-4, ph_nrd_phi_luminance_diff * sqrt(centerDiffVar));
        float specPhiLInv = 1.0 / max(1e-4, ph_nrd_phi_luminance_spec * sqrt(centerSpecVar));

        float diffuseLobeAngleFraction = ph_nrd_lobe_angle_fraction;
        float diffNormalWeightParam = nrd_normal_weight_param(1.0, diffuseLobeAngleFraction);
        vec2 roughnessWeightParams = nrd_roughness_weight_params(centerRoughness, ph_nrd_roughness_fraction);
        float specNormalWeightParamSimplified = nrd_normal_weight_param(1.0, diffuseLobeAngleFraction);
        vec2 specNormalWeightParams = nrd_spec_normal_weight_params_atrous(
            centerRoughness,
            historyLength,
            specReprojectionConfidence,
            gNormalEdgeStoppingRelaxation,
            ph_nrd_lobe_angle_fraction,
            ph_nrd_spec_lobe_angle_slack
        );

        vec3 centerV = -normalize(centerPosition - world_camera_position);
        float depthThreshold = ph_nrd_depth_threshold * centerViewZ;
        float sumWDiff = 0.0;
        float sumWSpec = 0.0;
        vec4 sumDiffIllumAnd2ndMoment = vec4(0.0);
        vec4 sumSpecIllumAnd2ndMoment = vec4(0.0);

        for (int j = -1; j <= 1; j++) {
            for (int i = -1; i <= 1; i++) {
                bool isCenter = (i == 0 && j == 0);
                ivec2 p = tex_coord + ivec2(i, j);
                bool isInside = all(greaterThanEqual(p, ivec2(0))) && all(lessThan(p, texSize));
                float kernel = isInside ? gaussian3x3[abs(i)] * gaussian3x3[abs(j)] : 0.0;
                if (kernel == 0.0) {
                    continue;
                }

                ivec2 sampleCoord = clamp(p, ivec2(0), texSize - ivec2(1));
                vec4 sampleMaterial = texelFetch(radiosity_material, sampleCoord, 0);
                float sampleRoughness = clamp(sampleMaterial.x, 0.0, 1.0);
                vec3 sampleGeomNormal = nrd_safe_normal(texelFetch(radiosity_normal, sampleCoord, 0).xyz);
                vec3 sampleMappedNormal = nrd_select_surface_normal(
                    sampleGeomNormal,
                    texelFetch(radiosity_mapped_normal, sampleCoord, 0).xyz
                );
                vec3 sampleWorldPos = texelFetch(radiosity_position, sampleCoord, 0).xyz;

                float geometryW =
                    nrd_plane_distance_weight(centerPosition, centerMappedNormal, sampleWorldPos, depthThreshold) *
                    kernel;

                vec3 sampleV = -normalize(
                    sampleWorldPos - world_camera_position +
                    gRoughnessEdgeStoppingRelaxation * (centerPosition - world_camera_position)
                );
                float normalWSpecSimplified =
                    nrd_normal_weight_atrous(centerMappedNormal, sampleMappedNormal, specNormalWeightParamSimplified);
                float normalWSpecFull = nrd_spec_normal_weight_atrous_full(
                    specNormalWeightParams,
                    centerMappedNormal,
                    sampleMappedNormal,
                    centerV,
                    sampleV
                );
                float roughnessWSpec =
                    nrd_compute_weight(sampleRoughness, roughnessWeightParams.x, roughnessWeightParams.y);
                vec4 sampleSpecData = texelFetch(nrd_spec_illum_prev, sampleCoord, 0);
                float specLumaW =
                    abs(centerSpecLuminance - nrd_luminance(sampleSpecData.rgb)) * specPhiLInv;
                specLumaW = min(gSpecMaxLuminanceRelativeDifference, specLumaW);

                float wSpec = geometryW * exp(-specLumaW);
                wSpec *= gRoughnessEdgeStoppingEnabled ?
                    (normalWSpecFull * roughnessWSpec) :
                    normalWSpecSimplified;
                wSpec *= nrd_material_weight(centerMaterial, sampleMaterial);
                wSpec = isCenter ? kernel : wSpec;
                sumWSpec += wSpec;
                sumSpecIllumAnd2ndMoment += vec4(sampleSpecData.rgb * wSpec, sampleSpecData.a * wSpec * wSpec);

                float normalWDiff = nrd_normal_weight_atrous(
                    centerMappedNormal,
                    sampleMappedNormal,
                    diffNormalWeightParam
                );
                vec4 sampleDiffData = texelFetch(nrd_diff_illum_prev, sampleCoord, 0);
                float diffLumaW =
                    abs(centerDiffLuminance - nrd_luminance(sampleDiffData.rgb)) * diffPhiLInv;
                diffLumaW = min(gDiffMaxLuminanceRelativeDifference, diffLumaW);

                float wDiff = geometryW * normalWDiff * exp(-diffLumaW);
                wDiff *= nrd_material_weight(centerMaterial, sampleMaterial);
                wDiff = isCenter ? kernel : wDiff;
                sumWDiff += wDiff;
                sumDiffIllumAnd2ndMoment += vec4(sampleDiffData.rgb * wDiff, sampleDiffData.a * wDiff * wDiff);
            }
        }

        sumWSpec = max(sumWSpec, 1e-6);
        sumWDiff = max(sumWDiff, 1e-6);
        nrd_spec_atrous_out = vec4(
            sumSpecIllumAnd2ndMoment.rgb / sumWSpec,
            sumSpecIllumAnd2ndMoment.a / (sumWSpec * sumWSpec)
        );
        nrd_diff_atrous_out = vec4(
            sumDiffIllumAnd2ndMoment.rgb / sumWDiff,
            sumDiffIllumAnd2ndMoment.a / (sumWDiff * sumWDiff)
        );
        return;
    }

    float diffNormalWeightParam = nrd_normal_weight_param(1.0, ph_nrd_lobe_angle_fraction);
    float sumWDiff = 0.0;
    float sumWSpec = 0.0;
    vec3 sumDiffIllum = vec3(0.0);
    vec3 sumSpecIllum = vec3(0.0);
    float sumDiff1stMoment = 0.0;
    float sumSpec1stMoment = 0.0;
    float sumDiff2ndMoment = 0.0;
    float sumSpec2ndMoment = 0.0;

    for (int cy = -2; cy <= 2; cy++) {
        for (int cx = -2; cx <= 2; cx++) {
            ivec2 p = clamp(tex_coord + ivec2(cx, cy), ivec2(0), texSize - ivec2(1));
            vec3 sampleGeomNormal = nrd_safe_normal(texelFetch(radiosity_normal, p, 0).xyz);
            vec3 sampleMappedNormal =
                nrd_select_surface_normal(sampleGeomNormal, texelFetch(radiosity_mapped_normal, p, 0).xyz);
            vec4 sampleMaterial = texelFetch(radiosity_material, p, 0);
            float angle = acos(clamp(dot(centerMappedNormal, sampleMappedNormal), -1.0, 1.0));
            float normalW = nrd_compute_weight(angle, diffNormalWeightParam, 0.0);
            float materialW = nrd_material_weight(centerMaterial, sampleMaterial);

            vec4 sampleSpec = texelFetch(nrd_spec_illum_prev, p, 0);
            float specW = normalW * materialW;
            float sampleSpec1st = nrd_luminance(sampleSpec.rgb);
            sumWSpec += specW;
            sumSpecIllum += sampleSpec.rgb * specW;
            sumSpec1stMoment += sampleSpec1st * specW;
            sumSpec2ndMoment += sampleSpec.a * specW;

            vec4 sampleDiff = texelFetch(nrd_diff_illum_prev, p, 0);
            float diffW = normalW * materialW;
            float sampleDiff1st = nrd_luminance(sampleDiff.rgb);
            sumWDiff += diffW;
            sumDiffIllum += sampleDiff.rgb * diffW;
            sumDiff1stMoment += sampleDiff1st * diffW;
            sumDiff2ndMoment += sampleDiff.a * diffW;
        }
    }

    float boost = max(1.0, 4.0 / (historyLength + 1.0));

    sumWSpec = max(sumWSpec, 1e-6);
    sumSpecIllum /= sumWSpec;
    sumSpec1stMoment /= sumWSpec;
    sumSpec2ndMoment /= sumWSpec;
    float specVariance = max(0.0, sumSpec2ndMoment - sumSpec1stMoment * sumSpec1stMoment) * boost;
    float specOutLuma = nrd_luminance(sumSpecIllum);
    nrd_spec_atrous_out = vec4(sumSpecIllum, specVariance + specOutLuma * specOutLuma);

    sumWDiff = max(sumWDiff, 1e-6);
    sumDiffIllum /= sumWDiff;
    sumDiff1stMoment /= sumWDiff;
    sumDiff2ndMoment /= sumWDiff;
    float diffVariance = max(0.0, sumDiff2ndMoment - sumDiff1stMoment * sumDiff1stMoment) * boost;
    float diffOutLuma = nrd_luminance(sumDiffIllum);
    nrd_diff_atrous_out = vec4(sumDiffIllum, diffVariance + diffOutLuma * diffOutLuma);
}
