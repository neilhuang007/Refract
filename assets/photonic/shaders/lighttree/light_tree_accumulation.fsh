#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 position_frag_out;
layout(location = 1) out vec4 normal_frag_out;
layout(location = 2) out vec4 mapped_normal_frag_out;
layout(location = 3) out vec4 albedo_frag_out;
layout(location = 4) out vec4 material_frag_out;
layout(location = 5) out vec4 direct_frag_out;
layout(location = 6) out vec4 direct_soft_frag_out;

#include "/photonics/common/header.glsl"

// Samplers NOT already declared in lighttree/samplers.glsl — declare only the extras here

// Debug: when enabled, light_reload is ignored and temporal history is never wiped
uniform float ph_debug_disable_temporal_reset;

bool is_valid_reprojection(ivec2 prevUv, ivec2 textureBounds) {
    bool lightReloadActive = light_reload && (ph_debug_disable_temporal_reset < 0.5f);
    return !lightReloadActive
        && all(greaterThanEqual(prevUv, ivec2(0)))
        && all(lessThan(prevUv, textureBounds));
}

vec4 load_previous_direct_soft(vec3 stagePosition, vec3 stageNormal) {
    vec2 reprojectionUv = ph_reprojectf(
        previous_modelview_projection,
        stagePosition + stageNormal * 0.01f,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    );

    ivec2 prevUv = ivec2(reprojectionUv);
    ivec2 textureBounds = textureSize(prev_radiosity_direct_soft, 0);
    if (!is_valid_reprojection(prevUv, textureBounds)) {
        return vec4(0.0f);
    }

    vec4 prevSoft = texelFetch(prev_radiosity_direct_soft, prevUv, 0);
    return any(isnan(prevSoft)) ? vec4(0.0f) : prevSoft;
}

void main() {
    if (!is_in_world()) {
        position_frag_out = vec4(0.0f);
        normal_frag_out = vec4(0.0f);
        mapped_normal_frag_out = vec4(0.0f);
        albedo_frag_out = vec4(0.0f);
        material_frag_out = vec4(0.0f);
        direct_frag_out = vec4(0.0f);
        direct_soft_frag_out = vec4(0.0f);
        return;
    }

    vec4 stagePosition = texelFetch(stage_radiosity_position, tex_coord, 0);
    vec4 stageNormal = texelFetch(stage_radiosity_normal, tex_coord, 0);
    vec4 stageMappedNormal = texelFetch(stage_radiosity_mapped_normal, tex_coord, 0);
    vec4 stageAlbedo = texelFetch(stage_radiosity_albedo, tex_coord, 0);
    vec4 stageMaterial = texelFetch(stage_radiosity_material, tex_coord, 0);
    vec4 directDiffuse = texelFetch(stage_radiosity_direct, tex_coord, 0);
    vec4 directSpecular = texelFetch(stage_radiosity_direct_specular, tex_coord, 0);
    vec4 prevSoft = load_previous_direct_soft(stagePosition.xyz, stageNormal.xyz);

    position_frag_out = stagePosition;
    normal_frag_out = stageNormal;
    mapped_normal_frag_out = stageMappedNormal;
    albedo_frag_out = stageAlbedo;
    material_frag_out = stageMaterial;
    direct_frag_out = directDiffuse + directSpecular;
    direct_soft_frag_out = vec4(prevSoft.rgb + directDiffuse.rgb + directSpecular.rgb, prevSoft.a + 1.0f);
}
