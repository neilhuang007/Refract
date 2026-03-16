#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 filtered_direct_frag_out;

#include "/photonics/common/header.glsl"

uniform sampler2D radiosity_lighting;
uniform sampler2D radiosity_lighting_variance;
uniform sampler2D radiosity_position;
uniform sampler2D radiosity_normal;

const float lt_filter_sigma_normal = 128.0f;
const float lt_filter_sigma_position = 4.0f;
const float lt_filter_sigma_luma = 4.0f;
const float lt_filter_min_confidence = 0.3f;
const int lt_filter_radius = 2;

float lt_filter_luminance(vec3 color) {
    return dot(color, vec3(0.2126f, 0.7152f, 0.0722f));
}

void main() {
    vec4 centerLighting = texelFetch(radiosity_lighting, tex_coord, 0);
    vec4 centerVariance = texelFetch(radiosity_lighting_variance, tex_coord, 0);
    vec3 centerPosition = texelFetch(radiosity_position, tex_coord, 0).xyz;
    vec3 centerNormal = texelFetch(radiosity_normal, tex_coord, 0).xyz;

    float confidence = centerVariance.w;
    float centerLuma = lt_filter_luminance(centerLighting.rgb);

    if (confidence >= lt_filter_min_confidence || centerLighting.a <= 0.0f) {
        filtered_direct_frag_out = vec4(centerLighting.rgb, centerLighting.a);
        return;
    }

    float filterStrength = 1.0f - (confidence / lt_filter_min_confidence);

    vec3 sumColor = vec3(0.0f);
    float sumWeight = 0.0f;

    float varianceSigma = max(sqrt(centerVariance.z), 0.001f) * lt_filter_sigma_luma;

    for (int dy = -lt_filter_radius; dy <= lt_filter_radius; dy++) {
        for (int dx = -lt_filter_radius; dx <= lt_filter_radius; dx++) {
            ivec2 sampleCoord = tex_coord + ivec2(dx, dy);

            vec4 sampleLighting = texelFetch(radiosity_lighting, sampleCoord, 0);
            vec3 samplePosition = texelFetch(radiosity_position, sampleCoord, 0).xyz;
            vec3 sampleNormal = texelFetch(radiosity_normal, sampleCoord, 0).xyz;

            if (sampleLighting.a <= 0.0f) continue;

            float normalDot = max(dot(centerNormal, sampleNormal), 0.0f);
            float normalWeight = pow(normalDot, lt_filter_sigma_normal);

            vec3 posDiff = samplePosition - centerPosition;
            float posDist2 = dot(posDiff, posDiff);
            float posWeight = exp(-posDist2 / lt_filter_sigma_position);

            float sampleLuma = lt_filter_luminance(sampleLighting.rgb);
            float lumaDiff = abs(sampleLuma - centerLuma);
            float lumaWeight = exp(-lumaDiff * lumaDiff / (varianceSigma * varianceSigma));

            float weight = normalWeight * posWeight * lumaWeight;
            sumColor += sampleLighting.rgb * weight;
            sumWeight += weight;
        }
    }

    if (sumWeight > 0.0f) {
        vec3 filteredColor = sumColor / sumWeight;
        vec3 result = mix(centerLighting.rgb, filteredColor, filterStrength);
        filtered_direct_frag_out = vec4(result, centerLighting.a);
        return;
    }

    filtered_direct_frag_out = vec4(centerLighting.rgb, centerLighting.a);
}
