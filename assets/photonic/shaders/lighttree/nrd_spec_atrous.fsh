#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 spec_atrous_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D spec_atrous_input;
uniform sampler2D spec_history_length_input;
uniform int direct_atrous_step_size;
uniform float ph_nrd_depth_threshold;

// NRD RELAX defaults (NRDSettings.h RelaxSettings):
// specularPhiLuminance default = 1.0
const float spec_phi_luminance = 1.0;
const float spec_lobe_angle_fraction = 0.5;

// NRD RELAX: max luminance relative difference cap.
// Reference: -log(saturate(specularMinLuminanceWeight)) where minLuminanceWeight=0.0 (default) -> +Inf.
// Use a large finite value to match uncapped behaviour.
const float gSpecMaxLuminanceRelativeDifference = 1e9;
// NRD RELAX default: confidenceDrivenLuminanceEdgeStoppingRelaxation = 0.0 -- disabled.
const float gConfidenceDrivenLuminanceRelaxation = 0.0;
// NRD RELAX default: roughnessFraction = 0.15
const float gRoughnessFraction = 0.15;
// NRD RELAX default: specularLobeAngleSlack = 0.15 degrees -> converted to radians (Relax.cpp:141 radians())
const float gSpecLobeAngleSlack = 0.002618;
// NRD RELAX default: roughnessEdgeStoppingRelaxation = 1.0
const float gRoughnessEdgeStoppingRelaxation = 1.0;
// NRD RELAX default: normalEdgeStoppingRelaxation = 0.3
const float gNormalEdgeStoppingRelaxation = 0.3;
const bool gRoughnessEdgeStoppingEnabled = true;

const float gaussian3x3[2] = float[](0.44198, 0.27901);

uint spec_hash(uint x) {
    x ^= x >> 16u;
    x *= 0x45d9f3bu;
    x ^= x >> 16u;
    return x;
}

void main() {
    if (!is_in_world()) {
        spec_atrous_out = vec4(0.0);
        return;
    }

    vec4 centerData = texelFetch(spec_atrous_input, tex_coord, 0);
    vec4 centerMaterial = texelFetch(radiosity_material, tex_coord, 0);
    float centerRoughness = clamp(centerMaterial.x, 0.0, 1.0);
    vec3 centerColor = centerData.rgb;
    float centerLuma = nrd_luminance(centerColor);
    float historyLength = nrd_decoded_history(texelFetch(spec_history_length_input, tex_coord, 0));

    vec3 centerPosition = texelFetch(radiosity_position, tex_coord, 0).xyz;
    vec3 centerGeometryNormal = nrd_safe_normal(texelFetch(radiosity_normal, tex_coord, 0).xyz);
    vec3 centerMappedNormal = nrd_select_surface_normal(centerGeometryNormal, texelFetch(radiosity_mapped_normal, tex_coord, 0).xyz);

    // NRD RELAX uses the temporal reprojection confidence to tune specular edge stopping.
    float specReprojectionConfidence = clamp(texelFetch(spec_reprojection_confidence_input, tex_coord, 0).r, 0.0, 1.0);

    // NRD RELAX: view vector for specular normal weight (RELAX_Atrous.cs.hlsl:132)
    vec3 centerV = -normalize(centerPosition - world_camera_position);

    // NRD RELAX: diffuse-like simplified normal weight param (fallback when roughness edge-stopping disabled)
    float diffuseLobeAngleFraction = spec_lobe_angle_fraction / sqrt(float(max(direct_atrous_step_size, 1)));
    diffuseLobeAngleFraction = mix(0.99, diffuseLobeAngleFraction, clamp(historyLength / 5.0, 0.0, 1.0));
    float specNormalWeightParamSimplified = nrd_normal_weight_param(1.0, diffuseLobeAngleFraction);

    // NRD RELAX: full specular normal weight params with roughness-aware cone (RELAX_Atrous.cs.hlsl:83-90)
    float specLobeAngleFraction = spec_lobe_angle_fraction;
    vec2 specNormalWeightParams = nrd_spec_normal_weight_params_atrous(
        centerRoughness, historyLength, specReprojectionConfidence,
        gNormalEdgeStoppingRelaxation, specLobeAngleFraction, gSpecLobeAngleSlack
    );

    // NRD RELAX: roughness weight params (RELAX_Atrous.cs.hlsl:58)
    vec2 roughnessWeightParams = nrd_roughness_weight_params(centerRoughness, gRoughnessFraction);

    // NRD RELAX: luminance relaxation (RELAX_Atrous.cs.hlsl:63-65)
    // Reference: specularLuminanceWeightRelaxation = lerp(1.0, specReprojConfidence, gLuminanceEdgeStoppingRelaxation)
    // Low confidence -> relaxation closer to 1.0 -> stricter; high confidence -> closer to specConfidence
    float specLuminanceWeightRelaxation = 1.0;
    if (direct_atrous_step_size <= 4)
        specLuminanceWeightRelaxation = mix(1.0, specReprojectionConfidence, gConfidenceDrivenLuminanceRelaxation);

    float centerWeight = gaussian3x3[0] * gaussian3x3[0];
    vec3 sumColor = centerColor * centerWeight;
    // NRD RELAX: .a channel is the temporally accumulated second moment of luminance (E[luma^2]).
    // Variance = E[luma^2] - E[luma]^2 (standard variance formula).
    float centerVariance = max(centerData.a - centerLuma * centerLuma, 0.0);
    float sumVariance = centerVariance * centerWeight * centerWeight;
    float sumWeight = centerWeight;
    float lumaSigma = spec_phi_luminance * sqrt(max(centerVariance, 1e-6));
    float specPhiLInv = 1.0 / max(lumaSigma, 1e-4);

    ivec2 textureSizeValue = textureSize(spec_atrous_input, 0);
    float centerViewDist = max(length(centerPosition - world_camera_position), 1e-3);
    float depthThreshold = ph_nrd_depth_threshold * centerViewDist;

    // Random offset to reduce ringing at large step sizes
    ivec2 sampleOffset = ivec2(0);
    if (direct_atrous_step_size > 4) {
        uint seed = uint(tex_coord.x) + uint(tex_coord.y) * uint(textureSizeValue.x) + uint(frameCounter) * 16777259u;
        uint h = spec_hash(seed);
        vec2 rnd = vec2(float(h & 0xFFFFu), float((h >> 16u) & 0xFFFFu)) / 65535.0;
        sampleOffset = ivec2(vec2(direct_atrous_step_size) * 0.5 * (rnd - 0.5));
    }

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) {
                continue;
            }

            ivec2 sampleCoord = tex_coord + sampleOffset + ivec2(dx, dy) * direct_atrous_step_size;
            if (any(lessThan(sampleCoord, ivec2(0))) || any(greaterThanEqual(sampleCoord, textureSizeValue))) {
                continue;
            }

            vec4 sampleData = texelFetch(spec_atrous_input, sampleCoord, 0);
            vec4 sampleMaterial = texelFetch(radiosity_material, sampleCoord, 0);
            float sampleRoughness = clamp(sampleMaterial.x, 0.0, 1.0);
            vec3 sampleRadiance = sampleData.rgb;
            vec3 samplePosition = texelFetch(radiosity_position, sampleCoord, 0).xyz;
            vec3 sampleGeometryNormal = nrd_safe_normal(texelFetch(radiosity_normal, sampleCoord, 0).xyz);
            vec3 sampleMappedNormal = nrd_select_surface_normal(
                sampleGeometryNormal,
                texelFetch(radiosity_mapped_normal, sampleCoord, 0).xyz
            );

            // NRD RELAX: geometry weight (RELAX_Atrous.cs.hlsl:168)
            float geometryWeight = nrd_plane_distance_weight(centerPosition, centerMappedNormal, samplePosition, depthThreshold);
            float kernelWeight = gaussian3x3[abs(dx)] * gaussian3x3[abs(dy)];
            geometryWeight *= kernelWeight;

            // NRD RELAX: view-direction relaxation for specular (RELAX_Atrous.cs.hlsl:176)
            vec3 sampleV = -normalize(samplePosition - world_camera_position + gRoughnessEdgeStoppingRelaxation * (centerPosition - world_camera_position));

            // NRD RELAX: specular normal weight - full vs simplified (RELAX_Atrous.cs.hlsl:179-185)
            float normalWSpecularSimplified = nrd_normal_weight_atrous(centerMappedNormal, sampleMappedNormal, specNormalWeightParamSimplified);
            float normalWSpecularFull = nrd_spec_normal_weight_atrous_full(specNormalWeightParams, centerMappedNormal, sampleMappedNormal, centerV, sampleV);
            float roughnessWSpecular = nrd_compute_weight(sampleRoughness, roughnessWeightParams.x, roughnessWeightParams.y);

            float normalAndRoughnessWeight = gRoughnessEdgeStoppingEnabled
                ? (normalWSpecularFull * roughnessWSpecular)
                : normalWSpecularSimplified;

            float materialWeight = nrd_material_weight(centerMaterial, sampleMaterial);

            float wSpecular = geometryWeight * normalAndRoughnessWeight * materialWeight;
            if (wSpecular <= 1e-4) {
                continue;
            }

            float sampleLuma = nrd_luminance(sampleRadiance);

            // NRD RELAX luminance weight (RELAX_Atrous.cs.hlsl:192-196)
            float lumaDiff = abs(centerLuma - sampleLuma) * specPhiLInv;
            float cappedLumaDiff = min(lumaDiff, gSpecMaxLuminanceRelativeDifference);
            wSpecular *= exp(-cappedLumaDiff * specLuminanceWeightRelaxation);

            float sampleVariance = max(sampleData.a - sampleLuma * sampleLuma, 0.0);
            sumColor += sampleRadiance * wSpecular;
            sumVariance += sampleVariance * wSpecular * wSpecular;
            sumWeight += wSpecular;
        }
    }

    vec3 resolvedColor = sumColor / max(sumWeight, 1e-4);
    float resolvedVariance = sumVariance / max(sumWeight * sumWeight, 1e-8);
    spec_atrous_out = vec4(resolvedColor, resolvedVariance);
}
