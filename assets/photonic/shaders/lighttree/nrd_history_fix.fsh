#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_historyfix_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D direct_historyfix_input;
uniform sampler2D nrd_history_length_tex;

const float direct_history_fix_frame_num = 6.0;
const float direct_history_fix_base_stride = 10.0;
const float direct_history_fix_normal_power = 12.0;
const float direct_depth_threshold = 0.01;
const float direct_min_weight = 1e-4;

ivec2 direct_clamp_texel(ivec2 sampleCoord, ivec2 texSize) {
    return clamp(sampleCoord, ivec2(0), texSize - 1);
}

void main() {
    if (!is_in_world()) {
        direct_historyfix_out = vec4(0.0);
        return;
    }

    vec4 centerSignal = texelFetch(direct_historyfix_input, tex_coord, 0);
    float historyLength = nrd_decoded_history(texelFetch(nrd_history_length_tex, tex_coord, 0));
    vec3 centerAlbedo = clamp(texelFetch(colortex10, tex_coord, 0).rgb, vec3(0.04), vec3(1.0));
    vec3 centerRadiance = nrd_safe_demodulate(centerSignal.rgb, nrd_compute_diffuse_demodulation(centerAlbedo));
    if (historyLength <= 0.0) {
        direct_historyfix_out = vec4(0.0);
        return;
    }
    if (historyLength > direct_history_fix_frame_num) {
        direct_historyfix_out = centerSignal;
        return;
    }

    vec3 centerPosition = texelFetch(radiosity_position, tex_coord, 0).xyz;
    vec3 centerGeometryNormal = nrd_safe_normal(texelFetch(radiosity_normal, tex_coord, 0).xyz);
    vec3 centerMappedNormal = nrd_safe_normal(texelFetch(radiosity_mapped_normal, tex_coord, 0).xyz);

    float strideValue = max(1.0, round(direct_history_fix_base_stride / (1.0 + historyLength)));
    int stride = int(strideValue);
    ivec2 texSize = textureSize(direct_historyfix_input, 0);

    vec3 weightedColor = centerRadiance;
    float weightedMoment = centerSignal.a;
    float totalWeight = 1.0;

    for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
            if (dx == 0 && dy == 0) {
                continue;
            }
            if (abs(dx) + abs(dy) == 4) {
                continue;
            }

            ivec2 offset = ivec2(dx * stride, dy * stride);
            ivec2 sampleCoord = direct_clamp_texel(tex_coord + offset, texSize);
            vec4 sampleSignal = texelFetch(direct_historyfix_input, sampleCoord, 0);
            float sampleHistoryLength = nrd_decoded_history(texelFetch(nrd_history_length_tex, sampleCoord, 0));
            if (sampleHistoryLength <= 0.0) {
                continue;
            }

            vec3 samplePosition = texelFetch(radiosity_position, sampleCoord, 0).xyz;
            vec3 sampleMappedNormal = nrd_safe_normal(texelFetch(radiosity_mapped_normal, sampleCoord, 0).xyz);

            float geometryWeight = nrd_plane_distance_weight(centerPosition, centerGeometryNormal, samplePosition, direct_depth_threshold);
            float normalWeight = nrd_normal_weight(centerMappedNormal, sampleMappedNormal, direct_history_fix_normal_power);
            float historyWeight = clamp(sampleHistoryLength / direct_history_fix_frame_num, 0.0, 1.0);
            float weight = geometryWeight * normalWeight * historyWeight;
            if (weight <= direct_min_weight) {
                continue;
            }

            vec3 sampleAlbedo = clamp(texelFetch(colortex10, sampleCoord, 0).rgb, vec3(0.04), vec3(1.0));
            vec3 sampleRadiance = nrd_safe_demodulate(sampleSignal.rgb, nrd_compute_diffuse_demodulation(sampleAlbedo));
            weightedColor += sampleRadiance * weight;
            weightedMoment += sampleSignal.a * weight;
            totalWeight += weight;
        }
    }

    direct_historyfix_out = vec4(nrd_safe_remodulate(weightedColor / totalWeight, nrd_compute_diffuse_demodulation(centerAlbedo)), weightedMoment / totalWeight);
}

