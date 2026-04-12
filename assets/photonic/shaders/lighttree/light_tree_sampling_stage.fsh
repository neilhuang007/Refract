#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 position_frag_out;
layout(location = 1) out vec4 normal_frag_out;
layout(location = 2) out vec4 mapped_normal_frag_out;
layout(location = 3) out vec4 albedo_frag_out;
layout(location = 4) out vec4 material_frag_out;
layout(location = 5) out vec4 identity_frag_out;
layout(location = 6) out vec4 motion_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_material_id.glsl"

vec4 lt_extract_stage_material() {
    vec2 uv = (vec2(tex_coord) + vec2(0.5f)) / vec2(viewWidth, viewHeight);
    vec4 spec = texture(specular, uv);
    // Match the denoiser-facing material contract used everywhere else.
    return nrd_pack_surface_material(spec);
}

float lt_encode_surface_face(vec3 geometryNormal) {
    vec3 absNormal = abs(geometryNormal);
    if (absNormal.x >= absNormal.y && absNormal.x >= absNormal.z) {
        return geometryNormal.x >= 0.0f ? 0.0f : 1.0f;
    }
    if (absNormal.y >= absNormal.z) {
        return geometryNormal.y >= 0.0f ? 2.0f : 3.0f;
    }
    return geometryNormal.z >= 0.0f ? 4.0f : 5.0f;
}

vec4 lt_build_surface_identity(vec3 worldPosValue, vec3 geometryNormalValue) {
    return vec4(fract(worldPosValue), lt_encode_surface_face(geometryNormalValue));
}

void storeEmptySurfaceOutputs() {
    position_frag_out = vec4(0.0f);
    normal_frag_out = vec4(0.0f);
    mapped_normal_frag_out = vec4(0.0f);
    albedo_frag_out = vec4(0.0f);
    material_frag_out = vec4(0.0f);
    identity_frag_out = vec4(0.0f);
    motion_frag_out = vec4(0.0f);
}

void main() {
    ivec2 pixelPosition = tex_coord;
    if (pixelPosition.x < 0 || pixelPosition.y < 0 || pixelPosition.x >= int(viewWidth) || pixelPosition.y >= int(viewHeight) || !is_in_world()) {
        storeEmptySurfaceOutputs();
        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);

    // Store linear view depth in .w for temporal neighbor validation (RTXDI: RAB_GetSurfaceLinearDepth).
    // Avoids the unproject→reproject round-trip error that produces a ~1.58x depth ratio mismatch.
    position_frag_out = vec4(world_pos, ph_linear_view_depth(modelview_projection, world_pos));
    normal_frag_out = vec4(block_normal, 1.0f);
    mapped_normal_frag_out = vec4(normal, 1.0f);
    albedo_frag_out = vec4(albedo, 1.0f);
    material_frag_out = lt_extract_stage_material();
    identity_frag_out = lt_build_surface_identity(world_pos, block_normal);

    vec2 currentPixelCenter = vec2(pixelPosition) + vec2(0.5f);
    motion_frag_out = ph_compute_temporal_motion(
        world_pos,
        currentPixelCenter,
        vec2(viewWidth, viewHeight)
    );
}
