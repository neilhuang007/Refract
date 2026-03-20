#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_atrous_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D direct_atrous_input;
uniform sampler2D nrd_history_length_tex;
uniform int direct_atrous_step_size;
uniform float ph_nrd_depth_threshold;

const float direct_phi_luminance = 2.0;
const float direct_lobe_angle_fraction = 0.5;

// NRD RELAX: max luminance relative difference cap (RELAX_Atrous.cs.hlsl:219)
const float gDiffMaxLuminanceRelativeDifference = 10.0;
// NRD RELAX: confidence-driven luminance edge-stopping relaxation scalar
const float gConfidenceDrivenLuminanceRelaxation = 0.5;

const float gaussian3x3[2] = float[](0.44198, 0.27901);

uint nrd_hash(uint x) {
    x ^= x >> 16u;
    x *= 0x45d9f3bu;
    x ^= x >> 16u;
    return x;
}

// Reference: diffuseLobeAngleFraction / sqrt(stepSize), relaxed by history,
// then GetNormalWeightParam2(1.0, fraction) → 1/max(atan(tanHalf), RELAX_NORMAL_ULP)
// NRD RELAX confidence-driven relaxation (RELAX_Atrous.cs.hlsl:111-114):
// lerp(1.0, lobeAngleFraction, diffuseConfidence) — low confidence → fraction → 1.0 (permissive)
float direct_normal_weight_param(float historyLength, float diffuseConfidence) {
    float normalFraction = direct_lobe_angle_fraction / sqrt(float(max(direct_atrous_step_size, 1)));
    float historyFactor = clamp(historyLength / 5.0, 0.0, 1.0);
    float relaxedFraction = mix(0.99, normalFraction, historyFactor);
    // NRD RELAX: lerp toward 1.0 as confidence decreases (more permissive normal filter)
    float confidenceRelaxedFraction = mix(1.0, relaxedFraction, diffuseConfidence);
    return nrd_normal_weight_param(1.0, confidenceRelaxedFraction);
}

void main() {
    if (!is_in_world()) {
        direct_atrous_out = vec4(0.0);
        return;
    }

    vec4 centerData = texelFetch(direct_atrous_input, tex_coord, 0);
    vec4 centerMaterial = texelFetch(radiosity_material, tex_coord, 0);
    vec3 centerColor = centerData.rgb;
    float centerLuma = nrd_luminance(centerColor);
    // NRD RELAX: do not clamp history to >= 1.0 — use raw decoded value
    float historyLength = nrd_decoded_history(texelFetch(nrd_history_length_tex, tex_coord, 0));

    vec3 centerPosition = texelFetch(radiosity_position, tex_coord, 0).xyz;
    vec3 centerGeometryNormal = nrd_safe_normal(texelFetch(radiosity_normal, tex_coord, 0).xyz);
    vec3 centerMappedNormal = nrd_select_surface_normal(centerGeometryNormal, texelFetch(radiosity_mapped_normal, tex_coord, 0).xyz);

    // NRD RELAX: confidence-driven normal and luminance relaxation (RELAX_Atrous.cs.hlsl:111-114, 219)
    float diffuseConfidence = texelFetch(diffuse_confidence_input, tex_coord, 0).r;

    float centerWeight = gaussian3x3[0] * gaussian3x3[0];
    vec3 sumColor = centerColor * centerWeight;
    // NRD RELAX: .a channel is variance, not raw second moment
    float centerVariance = max(centerData.a, 0.0);
    float sumVariance = centerVariance * centerWeight * centerWeight;
    float sumWeight = centerWeight;
    float normalWeightParam = direct_normal_weight_param(historyLength, diffuseConfidence);
    float lumaSigma = direct_phi_luminance * sqrt(max(centerVariance, 1e-6));

    ivec2 textureSizeValue = textureSize(direct_atrous_input, 0);

    // Random offset to reduce ringing at large step sizes (matches NRD reference)
    ivec2 sampleOffset = ivec2(0);
    if (direct_atrous_step_size > 4) {
        uint seed = uint(tex_coord.x) + uint(tex_coord.y) * uint(textureSizeValue.x) + uint(frameCounter) * 16777259u;
        uint h = nrd_hash(seed);
        vec2 rnd = vec2(float(h & 0xFFFFu), float((h >> 16u) & 0xFFFFu)) / 65535.0;
        sampleOffset = ivec2(vec2(direct_atrous_step_size) * 0.5 * (rnd - 0.5));
    }

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) {
                continue;
            }

            ivec2 sampleCoord = tex_coord + sampleOffset + ivec2(dx, dy) * direct_atrous_step_size;
            bool isOutOfBounds = any(lessThan(sampleCoord, ivec2(0))) || any(greaterThanEqual(sampleCoord, textureSizeValue));
            if (isOutOfBounds) {
                continue;
            }

            vec4 sampleData = texelFetch(direct_atrous_input, sampleCoord, 0);
            vec4 sampleMaterial = texelFetch(radiosity_material, sampleCoord, 0);
            vec3 sampleRadiance = sampleData.rgb;
            vec3 samplePosition = texelFetch(radiosity_position, sampleCoord, 0).xyz;
            vec3 sampleGeometryNormal = nrd_safe_normal(texelFetch(radiosity_normal, sampleCoord, 0).xyz);
            vec3 sampleMappedNormal = nrd_select_surface_normal(
                sampleGeometryNormal,
                texelFetch(radiosity_mapped_normal, sampleCoord, 0).xyz
            );

            // NRD RELAX: use mapped normal for plane distance test (same normal used for angular test)
            float centerViewDist = max(length(centerPosition - world_camera_position), 1e-3);
            float geometryWeight = nrd_plane_distance_weight(centerPosition, centerMappedNormal, samplePosition, ph_nrd_depth_threshold * centerViewDist);
            float normalWeight = nrd_normal_weight_atrous(centerMappedNormal, sampleMappedNormal, normalWeightParam);
            float materialWeight = nrd_material_weight(centerMaterial, sampleMaterial);
            if (materialWeight <= 0.0) {
                continue;
            }
            float sampleLuma = nrd_luminance(sampleRadiance);

            // NRD RELAX luminance weight: exp(-min(|ΔL|/sigma, maxRelDiff) * relaxation)
            // (RELAX_Atrous.cs.hlsl:219) — relaxation scales toward permissive as confidence drops
            float diffusePhiLInv = 1.0 / max(lumaSigma, 1e-7);
            float lumaDiff = abs(centerLuma - sampleLuma) * diffusePhiLInv;
            float cappedLumaDiff = min(lumaDiff, gDiffMaxLuminanceRelativeDifference);
            float lumaRelaxation = mix(1.0, gConfidenceDrivenLuminanceRelaxation, 1.0 - diffuseConfidence);
            float lumaWeight = exp(-cappedLumaDiff * lumaRelaxation);

            float kernelWeight = gaussian3x3[abs(dx)] * gaussian3x3[abs(dy)];
            float weight = geometryWeight * normalWeight * materialWeight * lumaWeight * kernelWeight;
            if (weight <= 1e-4) {
                continue;
            }

            float sampleVariance = max(sampleData.a, 0.0);
            sumColor += sampleRadiance * weight;
            sumVariance += sampleVariance * weight * weight;
            sumWeight += weight;
        }
    }

    vec3 resolvedColor = sumColor / max(sumWeight, 1e-4);
    // NRD RELAX: variance is w^2-weighted, normalized by total weight squared
    float resolvedVariance = sumVariance / max(sumWeight * sumWeight, 1e-8);
    // NRD RELAX: always write filtered variance in .a — no special last-pass branch.
    // History length is a separate resource and is not written by the A-trous pass.
    direct_atrous_out = vec4(resolvedColor, resolvedVariance);
}
