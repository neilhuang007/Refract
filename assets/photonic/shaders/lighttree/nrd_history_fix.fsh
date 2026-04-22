#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_historyfix_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D direct_historyfix_input;
uniform sampler2D nrd_history_length_tex;
uniform float ph_debug_enable_direct_history_fix;
uniform float ph_nrd_depth_threshold;
uniform float ph_nrd_denoising_range;

const float direct_history_fix_frame_num = 4.0;
const float direct_history_fix_base_stride = 14.0;
const float direct_history_fix_normal_power = 8.0;
const float direct_min_weight = 1e-4;

// Reference: MirrorUv -- reflects OOB taps back into the screen instead of wasting them on clamped border pixels
vec2 nrd_mirror_uv(vec2 uv) {
    return 1.0 - abs(1.0 - fract(uv * 0.5) * 2.0);
}

void main() {
    if (!is_in_world()) {
        direct_historyfix_out = vec4(0.0);
        return;
    }

    if (ph_debug_enable_direct_history_fix < 0.5) {
        direct_historyfix_out = texelFetch(direct_historyfix_input, tex_coord, 0);
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

    float centerViewDist = max(length(centerPosition - world_camera_position), 1e-3);

    // NRD: round(baseStride / (1 + historyLength)) -- no explicit lower bound of 1
    float strideValue = round(direct_history_fix_base_stride / (1.0 + historyLength));
    int stride = max(int(strideValue), 1);
    ivec2 texSize = textureSize(direct_historyfix_input, 0);

    vec3 weightedColor = centerHistory.radiance;
    float weightedSecondMoment = centerHistory.secondMoment;
    float totalWeight = 1.0;

    // NRD: skip center pixel when centerViewZ > gDenoisingRange. We approximate with normal validity.
    // Per-tap denoising-range rejection also approximated via geometry/normal/material gates.
    for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
            if (dx == 0 && dy == 0) {
                continue;
            }
            ivec2 offset = ivec2(dx * stride, dy * stride);
            vec2 uv = (vec2(tex_coord + offset) + 0.5) / vec2(texSize);
            uv = nrd_mirror_uv(uv);
            ivec2 sampleCoord = ivec2(uv * vec2(texSize));
            vec3 samplePosition = texelFetch(radiosity_position, sampleCoord, 0).xyz;

            // NRD: geometryWeight = 0 when sampleViewZ >= gDenoisingRange (NRD Common.hlsli:244)
            float sampleViewZ = nrd_compute_view_z(samplePosition);
            if (sampleViewZ > ph_nrd_denoising_range || sampleViewZ < 0.001) {
                continue;
            }

            vec4 sampleSignal = texelFetch(direct_historyfix_input, sampleCoord, 0);
            NrdDirectHistorySample sampleHistory = nrd_unpack_direct_history(sampleSignal);
            vec3 sampleGeometryNormal = nrd_safe_normal(texelFetch(radiosity_normal, sampleCoord, 0).xyz);
            vec3 sampleMappedNormal = nrd_select_surface_normal(
                sampleGeometryNormal,
                texelFetch(radiosity_mapped_normal, sampleCoord, 0).xyz
            );

            // NRD uses same unpacked normal for both plane-distance and angular tests
            // nrd_normal_weight clamps power to max(power, 0.01) matching reference getDiffuseNormalWeight
            float geometryWeight = nrd_plane_distance_weight(centerPosition, centerMappedNormal, samplePosition, ph_nrd_depth_threshold * centerViewDist);
            float normalWeight = nrd_normal_weight(centerMappedNormal, sampleMappedNormal, max(direct_history_fix_normal_power, 0.01));
            vec4 sampleMaterial = texelFetch(radiosity_material, sampleCoord, 0);
            float materialWeight = nrd_material_weight(centerMaterial, sampleMaterial);
            if (materialWeight <= 0.0) {
                continue;
            }
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
