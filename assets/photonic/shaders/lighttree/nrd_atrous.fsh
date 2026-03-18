#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_atrous_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D direct_atrous_input;
uniform sampler2D nrd_history_length_tex;

uniform int direct_atrous_step_size;
uniform int direct_atrous_is_last_pass;

const float direct_depth_threshold = 0.01;
const float direct_phi_luminance = 4.0;
const float direct_lobe_angle_fraction = 0.5;

const float gaussian3x3[2] = float[](0.44198, 0.27901);

float direct_normal_power(float historyLength) {
    float normalFraction = direct_lobe_angle_fraction / sqrt(float(max(direct_atrous_step_size, 1)));
    float historyFactor = clamp(historyLength / 5.0, 0.0, 1.0);
    float relaxedFraction = mix(0.99, normalFraction, historyFactor);
    return 1.0 / max(relaxedFraction, 0.001);
}

void main() {
    if (!is_in_world()) {
        direct_atrous_out = vec4(0.0);
        return;
    }

    vec4 centerData = texelFetch(direct_atrous_input, tex_coord, 0);
    vec3 centerAlbedo = clamp(texelFetch(colortex10, tex_coord, 0).rgb, vec3(0.04), vec3(1.0));
    vec4 centerMaterial = texelFetch(radiosity_material, tex_coord, 0);
    vec3 centerColor = nrd_safe_demodulate(centerData.rgb, nrd_compute_diffuse_demodulation(centerAlbedo));
    float centerLuma = nrd_luminance(centerColor);
    float historyLength = max(nrd_decoded_history(texelFetch(nrd_history_length_tex, tex_coord, 0)), 1.0);

    vec3 centerPosition = texelFetch(radiosity_position, tex_coord, 0).xyz;
    vec3 centerGeometryNormal = nrd_safe_normal(texelFetch(radiosity_normal, tex_coord, 0).xyz);
    vec3 centerMappedNormal = nrd_safe_normal(texelFetch(radiosity_mapped_normal, tex_coord, 0).xyz);

    float centerWeight = gaussian3x3[0] * gaussian3x3[0];
    vec3 sumColor = centerColor * centerWeight;
    float sumMoment = centerData.a * centerWeight * centerWeight;
    float sumWeight = centerWeight;
    float normalPower = direct_normal_power(historyLength);
    float lumaSigma = max(direct_phi_luminance / sqrt(max(historyLength, 1.0)), 1e-4);

    ivec2 textureSizeValue = textureSize(direct_atrous_input, 0);

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) {
                continue;
            }

            ivec2 sampleCoord = tex_coord + ivec2(dx, dy) * direct_atrous_step_size;
            bool isOutOfBounds = any(lessThan(sampleCoord, ivec2(0))) || any(greaterThanEqual(sampleCoord, textureSizeValue));
            if (isOutOfBounds) {
                continue;
            }

            vec4 sampleData = texelFetch(direct_atrous_input, sampleCoord, 0);
            vec3 sampleAlbedo = clamp(texelFetch(colortex10, sampleCoord, 0).rgb, vec3(0.04), vec3(1.0));
            vec3 sampleRadiance = nrd_safe_demodulate(sampleData.rgb, nrd_compute_diffuse_demodulation(sampleAlbedo));
            vec3 samplePosition = texelFetch(radiosity_position, sampleCoord, 0).xyz;
            vec3 sampleMappedNormal = nrd_safe_normal(texelFetch(radiosity_mapped_normal, sampleCoord, 0).xyz);

            float geometryWeight = nrd_plane_distance_weight(centerPosition, centerGeometryNormal, samplePosition, direct_depth_threshold);
            float normalWeight = nrd_normal_weight(centerMappedNormal, sampleMappedNormal, normalPower);
            float sampleLuma = nrd_luminance(sampleRadiance);
            float lumaWeight = nrd_luminance_weight(centerLuma, sampleLuma, lumaSigma);
            float kernelWeight = gaussian3x3[abs(dx)] * gaussian3x3[abs(dy)];
            float weight = geometryWeight * normalWeight * lumaWeight * kernelWeight;
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
    direct_atrous_out = vec4(nrd_safe_remodulate(resolvedColor, nrd_compute_diffuse_demodulation(centerAlbedo)), resolvedSecondMoment);

    if (direct_atrous_is_last_pass == 1) {
        direct_atrous_out.a = resolvedSecondMoment;
    }
}
