#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 spec_historyfix_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D spec_historyfix_input;
uniform sampler2D spec_history_length_input;
uniform float ph_nrd_depth_threshold;
uniform float ph_nrd_denoising_range;

const float spec_history_fix_frame_num = 4.0;
const float spec_history_fix_base_stride = 14.0;
const float spec_min_weight = 1e-4;

// Reference: MirrorUv — reflects OOB taps back into the screen instead of wasting them on clamped border pixels
vec2 spec_mirror_uv(vec2 uv) {
    return 1.0 - abs(1.0 - fract(uv * 0.5) * 2.0);
}

void main() {
    if (!is_in_world()) {
        spec_historyfix_out = vec4(0.0);
        return;
    }

    vec4 centerSignal = texelFetch(spec_historyfix_input, tex_coord, 0);
    NrdDirectHistorySample centerHistory = nrd_unpack_direct_history(centerSignal);
    float historyLength = nrd_decoded_history(texelFetch(spec_history_length_input, tex_coord, 0));
    if (historyLength > spec_history_fix_frame_num || spec_history_fix_frame_num == 1.0) {
        spec_historyfix_out = nrd_pack_direct_history(centerHistory.radiance, centerHistory.secondMoment);
        return;
    }

    vec3 centerPosition = texelFetch(radiosity_position, tex_coord, 0).xyz;
    vec3 centerGeometryNormal = nrd_safe_normal(texelFetch(radiosity_normal, tex_coord, 0).xyz);
    vec3 centerMappedNormal = nrd_select_surface_normal(
        centerGeometryNormal,
        texelFetch(radiosity_mapped_normal, tex_coord, 0).xyz
    );
    vec4 centerMaterial = texelFetch(radiosity_material, tex_coord, 0);

    // Roughness is stored in .r channel of the material texture
    float centerRoughness = centerMaterial.r;

    // View vector from surface toward camera (NRD: centerV = -normalize(centerWorldPos) in view-space)
    vec3 centerV = -normalize(centerPosition - world_camera_position);

    // NRD reference defaults for history fix: historyLength=5, confidence=1, normalRelaxation=0,
    // lobeAngleFraction=gLobeAngleFraction(0.5), lobeAngleSlack=gSpecLobeAngleSlack(0.15)
    vec2 specNormalWeightParams = nrd_spec_normal_weight_params_atrous(
        centerRoughness,
        5.0,  // numFramesInHistory — fixed at 5 per NRD reference comment
        1.0,  // specReprojConfidence — 1.0 (no confidence signal in history fix)
        0.0,  // normalEdgeStoppingRelaxation — 0 per reference
        0.5,  // lobeAngleFraction — gLobeAngleFraction default
        0.15  // lobeAngleSlack — gSpecLobeAngleSlack default
    );

    float centerViewDist = max(length(centerPosition - world_camera_position), 1e-3);

    float strideValue = round(spec_history_fix_base_stride / (1.0 + historyLength));
    int stride = max(int(strideValue), 1);
    ivec2 texSize = textureSize(spec_historyfix_input, 0);

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
            uv = spec_mirror_uv(uv);
            ivec2 sampleCoord = ivec2(uv * vec2(texSize));
            vec3 samplePosition = texelFetch(radiosity_position, sampleCoord, 0).xyz;

            // NRD: geometryWeight = 0 when sampleViewZ >= gDenoisingRange (NRD Common.hlsli:244)
            float sampleViewZ = nrd_compute_view_z(samplePosition);
            if (sampleViewZ > ph_nrd_denoising_range || sampleViewZ < 0.001) {
                continue;
            }

            vec4 sampleSignal = texelFetch(spec_historyfix_input, sampleCoord, 0);
            NrdDirectHistorySample sampleHistory = nrd_unpack_direct_history(sampleSignal);
            vec3 sampleGeometryNormal = nrd_safe_normal(texelFetch(radiosity_normal, sampleCoord, 0).xyz);
            vec3 sampleMappedNormal = nrd_select_surface_normal(
                sampleGeometryNormal,
                texelFetch(radiosity_mapped_normal, sampleCoord, 0).xyz
            );

            // NRD: sampleV = -normalize(sampleWorldPos + gRoughnessEdgeStoppingRelaxation * centerWorldPos)
            // In view-space this biases sample view vector toward center, relaxing view-direction rejection.
            // gRoughnessEdgeStoppingRelaxation default = 0.3
            // Translated to world-space: use offsets from camera position.
            vec3 sampleV = -normalize(
                (samplePosition - world_camera_position) + 0.3 * (centerPosition - world_camera_position)
            );

            float geometryWeight = nrd_plane_distance_weight(centerPosition, centerMappedNormal, samplePosition, ph_nrd_depth_threshold * centerViewDist);
            // NRD specular history fix uses roughness-aware specular normal weight (not simple dot-power)
            float normalWeight = nrd_spec_normal_weight_atrous_full(
                specNormalWeightParams, centerMappedNormal, sampleMappedNormal, centerV, sampleV
            );
            vec4 sampleMaterial = texelFetch(radiosity_material, sampleCoord, 0);
            float materialWeight = nrd_material_weight(centerMaterial, sampleMaterial);
            if (materialWeight <= 0.0) {
                continue;
            }
            float weight = geometryWeight * normalWeight * materialWeight;
            if (weight <= spec_min_weight) {
                continue;
            }

            weightedColor += sampleHistory.radiance * weight;
            weightedSecondMoment += sampleHistory.secondMoment * weight;
            totalWeight += weight;
        }
    }

    vec3 resolvedRadiance = weightedColor / totalWeight;
    float resolvedSecondMoment = weightedSecondMoment / totalWeight;
    spec_historyfix_out = nrd_pack_direct_history(resolvedRadiance, resolvedSecondMoment);
}
