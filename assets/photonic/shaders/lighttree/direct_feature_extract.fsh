#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 material_frag_out;
layout(location = 1) out vec4 direct_confidence_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

vec4 ph_extract_material(vec2 uv) {
    vec4 spec = texture(specular, uv);
    float smoothness = clamp(spec.r, 0.0, 1.0);
    float roughness = clamp(1.0 - smoothness, 0.0, 1.0);
    float metallic = clamp(spec.g, 0.0, 1.0);
    float emission = clamp(spec.a, 0.0, 1.0);
    return vec4(roughness, metallic, emission, nrd_encode_material_id(nrd_derive_material_id(spec)));
}

float ph_compute_specular_confidence(float roughness, vec3 directSpecularRadiance) {
    float hasSpecularSignal = step(1e-5, nrd_luminance(max(directSpecularRadiance, vec3(0.0))));
    float glossConfidence = 1.0 - roughness;
    return clamp(max(glossConfidence, hasSpecularSignal), 0.0, 1.0);
}

vec4 ph_extract_direct_confidence(vec2 uv, vec4 material) {
    ivec2 pixelCoord = ivec2(uv * vec2(viewWidth, viewHeight));
    vec4 directDiffuseSignal = texture(stage_radiosity_direct, uv);
    vec4 directSpecularSignal = texture(stage_radiosity_direct_specular, uv);
    if (ph_restir_active_checkerboard_field != 0
        && !nrd_is_active_checkerboard_pixel(pixelCoord, false, ph_restir_active_checkerboard_field)) {
        directDiffuseSignal = nrd_reconstruct_checkerboard_signal(
            stage_radiosity_direct,
            pixelCoord,
            stage_radiosity_position,
            stage_radiosity_normal
        );
        directSpecularSignal = nrd_reconstruct_checkerboard_signal(
            stage_radiosity_direct_specular,
            pixelCoord,
            stage_radiosity_position,
            stage_radiosity_normal
        );
    }

    vec3 directDiffuseRadiance = nrd_unpack_direct_signal(directDiffuseSignal).radiance;
    vec3 directSpecularRadiance = nrd_unpack_direct_signal(directSpecularSignal).radiance;
    float roughness = clamp(material.r, 0.0, 1.0);
    float diffuseSignalStrength = nrd_luminance(max(directDiffuseRadiance, vec3(0.0)));
    float diffuseConfidence = clamp(diffuseSignalStrength / (diffuseSignalStrength + 0.1), 0.2, 1.0);
    float specularConfidence = ph_compute_specular_confidence(roughness, directSpecularRadiance);
    return vec4(diffuseConfidence, specularConfidence, specularConfidence, 0.0);
}

void main() {
    if (!is_in_world()) {
        material_frag_out = vec4(0.0);
        direct_confidence_frag_out = vec4(0.0);
        return;
    }

    vec2 uv = (vec2(tex_coord) + vec2(0.5)) / vec2(viewWidth, viewHeight);
    material_frag_out = ph_extract_material(uv);
    direct_confidence_frag_out = ph_extract_direct_confidence(uv, material_frag_out);
}
