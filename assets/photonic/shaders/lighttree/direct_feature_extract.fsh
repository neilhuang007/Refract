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
    return vec4(roughness, 0.0, 0.0, nrd_encode_material_id(NRD_MATERIAL_ID_DISABLED));
}

void main() {
    if (!is_in_world()) {
        material_frag_out = vec4(0.0);
        direct_confidence_frag_out = vec4(0.0);
        return;
    }

    vec2 uv = (vec2(tex_coord) + vec2(0.5)) / vec2(viewWidth, viewHeight);
    material_frag_out = ph_extract_material(uv);
    direct_confidence_frag_out = vec4(0.0);
}
