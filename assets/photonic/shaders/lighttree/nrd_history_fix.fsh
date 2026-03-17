#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_history_fix_out;

#include "/photonics/common/header.glsl"

uniform sampler2D nrd_diff_input;
uniform sampler2D nrd_history_length_tex;

const float nrd_history_fix_frame_num = 6.0;
const float nrd_history_fix_base_stride = 14.0;
const float nrd_history_fix_normal_power = 8.0;
const float nrd_depth_threshold = 0.01;
const float nrd_min_weight = 1e-4;

ivec2 nrd_clamp_texel(ivec2 sampleCoord, ivec2 texSize) {
    return clamp(sampleCoord, ivec2(0), texSize - 1);
}

float nrd_safe_history_length(vec4 encodedHistory) {
    return clamp(encodedHistory.r * 255.0, 0.0, 255.0);
}

float nrd_plane_distance_weight(vec3 centerPosition, vec3 centerNormal, vec3 samplePosition) {
    float centerDistance = max(length(centerPosition), 1e-3);
    float planeDistance = abs(dot(samplePosition - centerPosition, centerNormal));
    float threshold = nrd_depth_threshold * centerDistance;
    return exp(-planeDistance / max(threshold, 1e-6));
}

float nrd_normal_similarity_weight(vec3 centerNormal, vec3 sampleNormal) {
    float normalDot = max(0.01, dot(centerNormal, sampleNormal));
    return pow(normalDot, nrd_history_fix_normal_power);
}

void main() {
    if (!is_in_world()) {
        nrd_history_fix_out = vec4(0.0);
        return;
    }

    vec4 centerSignal = texelFetch(nrd_diff_input, tex_coord, 0);
    float historyLength = nrd_safe_history_length(texelFetch(nrd_history_length_tex, tex_coord, 0));
    if (historyLength > nrd_history_fix_frame_num) {
        nrd_history_fix_out = centerSignal;
        return;
    }

    vec3 centerPosition = texelFetch(radiosity_position, tex_coord, 0).xyz;
    vec3 centerGeometryNormal = normalize(texelFetch(radiosity_normal, tex_coord, 0).xyz);
    vec3 centerMappedNormal = normalize(texelFetch(radiosity_mapped_normal, tex_coord, 0).xyz);
    if (dot(centerGeometryNormal, centerGeometryNormal) <= 1e-6 || dot(centerMappedNormal, centerMappedNormal) <= 1e-6) {
        nrd_history_fix_out = centerSignal;
        return;
    }

    float strideValue = max(1.0, round(nrd_history_fix_base_stride / (1.0 + historyLength)));
    int stride = int(strideValue);
    ivec2 texSize = textureSize(nrd_diff_input, 0);

    vec4 weightedSum = centerSignal;
    float totalWeight = 1.0;

    for (int dy = -3; dy <= 3; dy++) {
        for (int dx = -3; dx <= 3; dx++) {
            if (dx == 0 && dy == 0) {
                continue;
            }

            ivec2 offset = ivec2(dx * stride, dy * stride);
            ivec2 sampleCoord = nrd_clamp_texel(tex_coord + offset, texSize);
            vec3 samplePosition = texelFetch(radiosity_position, sampleCoord, 0).xyz;
            vec3 sampleMappedNormal = normalize(texelFetch(radiosity_mapped_normal, sampleCoord, 0).xyz);

            float geometryWeight = nrd_plane_distance_weight(centerPosition, centerGeometryNormal, samplePosition);
            float normalWeight = nrd_normal_similarity_weight(centerMappedNormal, sampleMappedNormal);

            // Prefer converged neighbors (high history) over other new pixels
            float sampleHistoryLength = nrd_safe_history_length(texelFetch(nrd_history_length_tex, sampleCoord, 0));
            float historyWeight = clamp(sampleHistoryLength / 10.0, 0.0, 1.0);

            float weight = geometryWeight * normalWeight * historyWeight;
            if (weight <= nrd_min_weight) {
                continue;
            }

            weightedSum += texelFetch(nrd_diff_input, sampleCoord, 0) * weight;
            totalWeight += weight;
        }
    }

    nrd_history_fix_out = weightedSum / max(totalWeight, 1e-6);
}
