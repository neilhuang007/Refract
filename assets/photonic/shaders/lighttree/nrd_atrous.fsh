#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_atrous_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D nrd_diff_variance_input;
uniform sampler2D nrd_history_length_tex;

uniform int nrd_atrous_step_size;
uniform int nrd_atrous_is_last_pass;

const float nrd_depth_threshold = 0.01;
const float nrd_diff_phi_luminance = 4.0;
const float nrd_lobe_angle_fraction = 0.5;
const float nrd_diff_max_luminance_relative_difference = 10.0;

const float gaussian3x3[2] = float[](0.44198, 0.27901);

float nrd_get_plane_distance_weight(vec3 centerPosition, vec3 centerNormal, vec3 samplePosition) {
    float planeDistance = abs(dot(samplePosition - centerPosition, centerNormal));
    float distanceThreshold = nrd_depth_threshold * max(length(centerPosition), 1e-4);
    return exp(-planeDistance / max(distanceThreshold, 1e-6));
}

float nrd_get_normal_weight(vec3 centerNormal, vec3 sampleNormal, float historyLength) {
    float normalFraction = nrd_lobe_angle_fraction / sqrt(float(max(nrd_atrous_step_size, 1)));
    float historyFactor = clamp(historyLength / 5.0, 0.0, 1.0);
    float relaxedFraction = mix(0.99, normalFraction, historyFactor);
    float normalPower = 1.0 / max(relaxedFraction, 0.001);
    float normalDot = max(0.01, dot(centerNormal, sampleNormal));
    return pow(normalDot, normalPower);
}

float nrd_get_luminance_weight(float centerLuma, float sampleLuma, float centerVariance) {
    float lumaPhi = max(1e-4, nrd_diff_phi_luminance * sqrt(max(centerVariance, 0.0)));
    float lumaDiff = abs(centerLuma - sampleLuma) / lumaPhi;
    float clampedLumaDiff = min(lumaDiff, nrd_diff_max_luminance_relative_difference);
    return exp(-clampedLumaDiff);
}

void main() {
    vec4 centerData = texelFetch(nrd_diff_variance_input, tex_coord, 0);
    vec3 centerColor = centerData.rgb;
    float centerVariance = centerData.a;
    float centerLuma = nrd_luminance(centerColor);

    vec3 centerPosition = texelFetch(radiosity_position, tex_coord, 0).xyz;
    vec3 centerGeometryNormal = texelFetch(radiosity_normal, tex_coord, 0).xyz;
    vec3 centerMappedNormal = texelFetch(radiosity_mapped_normal, tex_coord, 0).xyz;
    float historyLength = 255.0 * texelFetch(nrd_history_length_tex, tex_coord, 0).r;

    float centerWeight = gaussian3x3[0] * gaussian3x3[0];
    vec3 sumColor = centerColor * centerWeight;
    float sumVariance = centerVariance * centerWeight * centerWeight;
    float sumWeight = centerWeight;

    ivec2 textureSizeValue = textureSize(nrd_diff_variance_input, 0);

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) {
                continue;
            }

            ivec2 sampleCoord = tex_coord + ivec2(dx, dy) * nrd_atrous_step_size;
            bool isOutOfBounds = any(lessThan(sampleCoord, ivec2(0))) || any(greaterThanEqual(sampleCoord, textureSizeValue));
            if (isOutOfBounds) {
                continue;
            }

            vec4 sampleData = texelFetch(nrd_diff_variance_input, sampleCoord, 0);
            vec3 samplePosition = texelFetch(radiosity_position, sampleCoord, 0).xyz;
            vec3 sampleMappedNormal = texelFetch(radiosity_mapped_normal, sampleCoord, 0).xyz;

            float geometryWeight = nrd_get_plane_distance_weight(centerPosition, centerGeometryNormal, samplePosition);
            if (geometryWeight == 0.0) {
                continue;
            }

            float normalWeight = nrd_get_normal_weight(centerMappedNormal, sampleMappedNormal, historyLength);
            float sampleLuma = nrd_luminance(sampleData.rgb);
            float luminanceWeight = nrd_get_luminance_weight(centerLuma, sampleLuma, centerVariance);
            float kernelWeight = gaussian3x3[abs(dx)] * gaussian3x3[abs(dy)];
            float weight = geometryWeight * normalWeight * luminanceWeight * kernelWeight;

            if (weight <= 1e-4) {
                continue;
            }

            sumColor += sampleData.rgb * weight;
            sumVariance += sampleData.a * weight * weight;
            sumWeight += weight;
        }
    }

    vec4 result = vec4(sumColor / sumWeight, sumVariance / (sumWeight * sumWeight));
    if (nrd_atrous_is_last_pass == 1) {
        result.a = max(historyLength - 1.0, 0.0);
    }

    nrd_atrous_out = result;
}
