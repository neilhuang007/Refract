#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 material_frag_out;
layout(location = 1) out vec4 motion_frag_out;
layout(location = 2) out vec4 direct_confidence_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D prev_direct_noisy_input;

vec4 ph_extract_material(vec2 uv) {
    vec4 spec = texture(specular, uv);
    float smoothness = clamp(spec.r, 0.0, 1.0);
    float roughness = clamp(1.0 - smoothness, 0.0, 1.0);
    float metallic = clamp(spec.g, 0.0, 1.0);
    float emission = clamp(spec.a, 0.0, 1.0);
    return vec4(roughness, metallic, emission, smoothness);
}

vec4 ph_extract_motion(vec3 worldPosition, vec3 worldNormal) {
    vec2 currentPixel = vec2(tex_coord) + vec2(0.5);
    vec2 previousPixel = ph_reprojectf(
        previous_modelview_projection,
        worldPosition + worldNormal * 0.01,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    );

    vec2 motion = currentPixel - previousPixel;
    float motionLength = length(motion);
    float validity = float(all(greaterThanEqual(previousPixel, vec2(0.0)))
        && all(lessThan(previousPixel, vec2(viewWidth, viewHeight))));
    return vec4(motion, motionLength, validity);
}

ivec2 ph_clamp_previous_uv(vec2 previousPixel, ivec2 textureSizeValue) {
    return clamp(ivec2(previousPixel), ivec2(0), textureSizeValue - 1);
}

vec4 ph_extract_direct_features(vec3 currentDirect, vec3 previousDirect, float previousHistoryLength, float hitDistance, float viewDistance) {
    float hitDistanceWeight = nrd_hit_distance_confidence(hitDistance, viewDistance);
    float temporalStability = nrd_gradient_to_confidence(previousDirect, currentDirect, previousHistoryLength, 48.0);
    float historyWeight = nrd_confidence_from_history(previousHistoryLength, 48.0);
    float accumulationSpeed = mix(0.25, 1.0, hitDistanceWeight * max(temporalStability, historyWeight));
    return nrd_pack_direct_features(hitDistance, hitDistanceWeight, temporalStability, accumulationSpeed);
}

void main() {
    if (!is_in_world()) {
        material_frag_out = vec4(0.0);
        motion_frag_out = vec4(0.0);
        direct_confidence_frag_out = vec4(0.0);
        return;
    }

    vec3 stagePosition = texelFetch(stage_radiosity_position, tex_coord, 0).xyz;
    vec3 stageGeometryNormal = texelFetch(stage_radiosity_normal, tex_coord, 0).xyz;
    vec3 stageMappedNormal = texelFetch(stage_radiosity_mapped_normal, tex_coord, 0).xyz;
    vec3 reprojectionNormal = nrd_select_surface_normal(stageGeometryNormal, stageMappedNormal);
    vec2 uv = (vec2(tex_coord) + vec2(0.5)) / vec2(viewWidth, viewHeight);
    vec2 previousPixel = ph_reprojectf(
        previous_modelview_projection,
        stagePosition + normalize(reprojectionNormal) * 0.01,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    );
    ivec2 previousUv = ph_clamp_previous_uv(previousPixel, textureSize(prev_radiosity_direct, 0));
    bool hasPreviousSample = all(greaterThanEqual(previousPixel, vec2(0.0)))
        && all(lessThan(previousPixel, vec2(viewWidth, viewHeight)));

    material_frag_out = ph_extract_material(uv);
    motion_frag_out = ph_extract_motion(stagePosition, normalize(reprojectionNormal));

    NrdDirectSignal currentDirectSignal = nrd_unpack_direct_signal(texelFetch(stage_radiosity_direct, tex_coord, 0));
    NrdDirectSignal previousDirectSignal = hasPreviousSample
        ? nrd_unpack_direct_signal(texelFetch(prev_direct_noisy_input, previousUv, 0))
        : NrdDirectSignal(vec3(0.0), 0.0);
    float previousHistoryLength = hasPreviousSample
        ? nrd_decoded_history(texelFetch(prev_direct_history_length_input, previousUv, 0))
        : 0.0;
    float viewDistance = length(stagePosition - world_camera_position);
    direct_confidence_frag_out = ph_extract_direct_features(
        currentDirectSignal.radiance,
        previousDirectSignal.radiance,
        previousHistoryLength,
        currentDirectSignal.hitDistance,
        viewDistance
    );
}
