#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 position_frag_out;
layout(location = 1) out vec4 normal_frag_out;
layout(location = 2) out vec4 mapped_normal_frag_out;
layout(location = 3) out vec4 direct_frag_out;
layout(location = 4) out vec4 direct_soft_frag_out;

#include "/photonics/common/header.glsl"

// Samplers NOT already declared in lighttree/samplers.glsl — declare only the extras here
uniform sampler2D stage_radiosity_position;
uniform sampler2D stage_radiosity_normal;

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
        direct_frag_out = vec4(0.0f);
        direct_soft_frag_out = vec4(0.0f);
        return;
    }

    vec4 stagePosition = texelFetch(stage_radiosity_position, tex_coord, 0);
    vec4 stageNormal = texelFetch(stage_radiosity_normal, tex_coord, 0);
    vec4 stageMappedNormal = texelFetch(stage_radiosity_mapped_normal, tex_coord, 0);
    vec4 rawDirect = texelFetch(stage_radiosity_direct, tex_coord, 0);
    vec4 prevSoft = load_previous_direct_soft(stagePosition.xyz, stageNormal.xyz);

    position_frag_out = stagePosition;
    normal_frag_out = stageNormal;
    mapped_normal_frag_out = stageMappedNormal;
    direct_frag_out = vec4(rawDirect.rgb, ph_luminance(rawDirect.rgb) > 0.0f ? 1.0f : 0.0f);
    direct_soft_frag_out = vec4(prevSoft.rgb + rawDirect.rgb, prevSoft.a + 1.0f);
}
