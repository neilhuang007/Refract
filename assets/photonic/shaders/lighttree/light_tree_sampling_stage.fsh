#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 position_frag_out;
layout(location = 1) out vec4 normal_frag_out;
layout(location = 2) out vec4 mapped_normal_frag_out;
layout(location = 3) out vec4 albedo_frag_out;
layout(location = 4) out vec4 motion_frag_out;

#include "/photonics/common/header.glsl"

void storeEmptySurfaceOutputs() {
    position_frag_out = vec4(0.0f);
    normal_frag_out = vec4(0.0f);
    mapped_normal_frag_out = vec4(0.0f);
    albedo_frag_out = vec4(0.0f);
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

    vec2 previousPixel = ph_reprojectf(
        previous_modelview_projection,
        world_pos,
        vec2(viewWidth, viewHeight),
        vec2(0.0f)
    );
    float currentLinearDepth = length(world_pos - world_camera_position);
    float expectedPrevLinearDepth = length(world_pos - previous_world_camera_position);
    motion_frag_out = vec4(previousPixel - pixelPosition, expectedPrevLinearDepth - currentLinearDepth, 1.0f);
}
