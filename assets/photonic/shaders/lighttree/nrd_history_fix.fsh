#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_historyfix_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D direct_historyfix_input;
uniform sampler2D nrd_history_length_tex;

const float direct_history_fix_frame_num = 4.0;
const float direct_history_fix_base_stride = 14.0;
const float direct_history_fix_normal_power = 8.0;
const float direct_depth_threshold = 0.003;
const float direct_min_weight = 1e-4;

// Reference: MirrorUv — reflects OOB taps back into the screen instead of wasting them on clamped border pixels
vec2 nrd_mirror_uv(vec2 uv) {
    return 1.0 - abs(1.0 - fract(uv * 0.5) * 2.0);
}

void main() {
    if (!is_in_world()) {
        direct_historyfix_out = vec4(0.0);
        return;
    }

    vec4 centerSignal = texelFetch(direct_historyfix_input, tex_coord, 0);
    NrdDirectHistorySample centerHistory = nrd_unpack_direct_history(centerSignal);
    float historyLength = nrd_decoded_history(texelFetch(nrd_history_length_tex, tex_coord, 0));
    if (historyLength > direct_history_fix_frame_num || direct_history_fix_frame_num == 1.0) {
        direct_historyfix_out = nrd_pack_direct_history(centerHistory.radiance, centerHistory.secondMoment);
        return;
    }

    vec3 centerPosition = texelFetch(radiosity_position, tex_coord, 0).xyz;
    vec3 centerGeometryNormal = nrd_safe_normal(texelFetch(radiosity_normal, tex_coord, 0).xyz);
    vec3 centerMappedNormal = nrd_select_surface_normal(
        centerGeometryNormal,
        texelFetch(radiosity_mapped_normal, tex_coord, 0).xyz
    );
    vec4 centerMaterial = texelFetch(radiosity_material, tex_coord, 0);

    float strideValue = max(1.0, round(direct_history_fix_base_stride / (1.0 + historyLength)));
    int stride = int(strideValue);
    ivec2 texSize = textureSize(direct_historyfix_input, 0);

    vec3 weightedColor = centerHistory.radiance;
    float weightedSecondMoment = centerHistory.secondMoment;
    float totalWeight = 1.0;

    for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
            if (dx == 0 && dy == 0) {
                continue;
            }
            ivec2 offset = ivec2(dx * stride, dy * stride);
            vec2 uv = (vec2(tex_coord + offset) + 0.5) / vec2(texSize);
            uv = nrd_mirror_uv(uv);
            ivec2 sampleCoord = ivec2(uv * vec2(texSize));
            vec4 sampleSignal = texelFetch(direct_historyfix_input, sampleCoord, 0);
            NrdDirectHistorySample sampleHistory = nrd_unpack_direct_history(sampleSignal);
            vec3 samplePosition = texelFetch(radiosity_position, sampleCoord, 0).xyz;
            vec3 sampleGeometryNormal = nrd_safe_normal(texelFetch(radiosity_normal, sampleCoord, 0).xyz);
            vec3 sampleMappedNormal = nrd_select_surface_normal(
                sampleGeometryNormal,
                texelFetch(radiosity_mapped_normal, sampleCoord, 0).xyz
            );

            float geometryWeight = nrd_plane_distance_weight(centerPosition, centerGeometryNormal, samplePosition, direct_depth_threshold);
            float normalWeight = nrd_normal_weight(centerMappedNormal, sampleMappedNormal, direct_history_fix_normal_power);
            vec4 sampleMaterial = texelFetch(radiosity_material, sampleCoord, 0);
            float materialWeight = nrd_material_weight(centerMaterial, sampleMaterial);
            float weight = geometryWeight * normalWeight * materialWeight;
            if (weight <= direct_min_weight) {
                continue;
            }

            weightedColor += sampleHistory.radiance * weight;
            weightedSecondMoment += sampleHistory.secondMoment * weight;
            totalWeight += weight;
        }
    }

    vec3 resolvedRadiance = weightedColor / totalWeight;
    float resolvedSecondMoment = weightedSecondMoment / totalWeight;
    direct_historyfix_out = nrd_pack_direct_history(resolvedRadiance, resolvedSecondMoment);
}
