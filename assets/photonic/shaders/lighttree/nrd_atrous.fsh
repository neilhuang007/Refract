#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_atrous_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D direct_atrous_input;
uniform sampler2D nrd_history_length_tex;

uniform int direct_atrous_step_size;
uniform int direct_atrous_is_last_pass;

const float direct_depth_threshold = 0.003;
const float direct_phi_luminance = 2.0;
const float direct_lobe_angle_fraction = 0.5;

const float gaussian3x3[2] = float[](0.44198, 0.27901);

uint nrd_hash(uint x) {
    x ^= x >> 16u;
    x *= 0x45d9f3bu;
    x ^= x >> 16u;
    return x;
}

// Reference: diffuseLobeAngleFraction / sqrt(stepSize), relaxed by history,
// then GetNormalWeightParam2(1.0, fraction) → 1/max(atan(tanHalf), RELAX_NORMAL_ULP)
float direct_normal_weight_param(float historyLength) {
    float normalFraction = direct_lobe_angle_fraction / sqrt(float(max(direct_atrous_step_size, 1)));
    float historyFactor = clamp(historyLength / 5.0, 0.0, 1.0);
    float relaxedFraction = mix(0.99, normalFraction, historyFactor);
    return nrd_normal_weight_param(1.0, relaxedFraction);
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
    float historyLength = max(nrd_decoded_history(texelFetch(nrd_history_length_tex, tex_coord, 0)), 1.0);

    vec3 centerPosition = texelFetch(radiosity_position, tex_coord, 0).xyz;
    vec3 centerGeometryNormal = nrd_safe_normal(texelFetch(radiosity_normal, tex_coord, 0).xyz);
    vec3 centerMappedNormal = nrd_select_surface_normal(centerGeometryNormal, texelFetch(radiosity_mapped_normal, tex_coord, 0).xyz);

    float centerWeight = gaussian3x3[0] * gaussian3x3[0];
    vec3 sumColor = centerColor * centerWeight;
    float sumMoment = centerData.a * centerWeight * centerWeight;
    float sumWeight = centerWeight;
    float normalWeightParam = direct_normal_weight_param(historyLength);
    // Reference uses sqrt(2ndMoment) directly as sigma proxy, not sqrt(variance).
    // This produces a larger sigma → more permissive luminance weights → more blurring.
    float lumaSigma = max(direct_phi_luminance * sqrt(max(centerData.a, 0.0)), 1e-4);

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

            float geometryWeight = nrd_plane_distance_weight(centerPosition, centerGeometryNormal, samplePosition, direct_depth_threshold);
            float normalWeight = nrd_normal_weight_atrous(centerMappedNormal, sampleMappedNormal, normalWeightParam);
            float materialWeight = nrd_material_weight(centerMaterial, sampleMaterial);
            float sampleLuma = nrd_luminance(sampleRadiance);
            float lumaWeight = nrd_luminance_weight(centerLuma, sampleLuma, lumaSigma);
            float kernelWeight = gaussian3x3[abs(dx)] * gaussian3x3[abs(dy)];
            float weight = geometryWeight * normalWeight * materialWeight * lumaWeight * kernelWeight;
            if (weight <= 1e-4) {
                continue;
            }

            sumColor += sampleRadiance * weight;
            sumMoment += sampleData.a * weight * weight;
            sumWeight += weight;
        }
    }

    vec3 resolvedColor = sumColor / max(sumWeight, 1e-4);
    float resolvedLuma = nrd_luminance(resolvedColor);
    float resolvedSecondMoment = max(sumMoment / max(sumWeight * sumWeight, 1e-4), resolvedLuma * resolvedLuma);
    direct_atrous_out = vec4(resolvedColor, resolvedSecondMoment);

    if (direct_atrous_is_last_pass == 1) {
        direct_atrous_out.a = resolvedSecondMoment;
    }
}
