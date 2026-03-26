#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 position_frag_out;
layout(location = 1) out vec4 normal_frag_out;
layout(location = 2) out vec4 mapped_normal_frag_out;
layout(location = 3) out vec4 albedo_frag_out;
layout(location = 4) out vec4 material_frag_out;
layout(location = 5) out vec4 motion_frag_out;

#include "/photonics/common/header.glsl"

vec4 lt_extract_stage_material() {
    vec2 uv = (vec2(tex_coord) + vec2(0.5f)) / vec2(viewWidth, viewHeight);
    vec4 spec = texture(specular, uv);
    float smoothness = clamp(spec.r, 0.0f, 1.0f);
    float roughness = clamp(1.0f - smoothness, 0.0f, 1.0f);
    float metallic = clamp(spec.g, 0.0f, 1.0f);
    float emission = clamp(spec.a, 0.0f, 1.0f);
    return vec4(roughness, metallic, emission, smoothness);
}

void storeEmptySurfaceOutputs() {
    position_frag_out = vec4(0.0f);
    normal_frag_out = vec4(0.0f);
    mapped_normal_frag_out = vec4(0.0f);
    albedo_frag_out = vec4(0.0f);
    material_frag_out = vec4(0.0f);
    motion_frag_out = vec4(0.0f);
}

void main() {
    ivec2 pixelPosition = tex_coord;
    if (pixelPosition.x < 0 || pixelPosition.y < 0 || pixelPosition.x >= int(viewWidth) || pixelPosition.y >= int(viewHeight) || !is_in_world()) {
        storeEmptySurfaceOutputs();
        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);

    position_frag_out = vec4(world_pos, 1.0f);
    normal_frag_out = vec4(block_normal, 1.0f);
    mapped_normal_frag_out = vec4(normal, 1.0f);
    albedo_frag_out = vec4(albedo, 1.0f);
    material_frag_out = lt_extract_stage_material();

    vec2 previousPixel = ph_reprojectf(
        previous_modelview_projection,
        world_pos,
        vec2(viewWidth, viewHeight),
        vec2(0.0f)
    );
    vec2 currentPixelCenter = vec2(pixelPosition) + vec2(0.5f);
    float currentLinearDepth = ph_linear_view_depth(modelview_projection, world_pos);
    float expectedPrevLinearDepth = ph_linear_view_depth(previous_modelview_projection, world_pos);
    motion_frag_out = vec4(previousPixel - currentPixelCenter, expectedPrevLinearDepth - currentLinearDepth, 1.0f);
}
