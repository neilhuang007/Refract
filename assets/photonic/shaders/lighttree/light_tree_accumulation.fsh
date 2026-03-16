#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 position_frag_out;
layout(location = 1) out vec4 normal_frag_out;
layout(location = 2) out vec4 direct_frag_out;
layout(location = 3) out vec4 direct_soft_frag_out;

#include "/photonics/common/header.glsl"

// Read position/normal from the stage buffer (written by sampling pass)
uniform sampler2D stage_radiosity_position;
uniform sampler2D stage_radiosity_normal;

// Read denoised direct from the NRD pipeline
uniform sampler2D nrd_denoised_direct;

// Read previous compat soft for temporal blending
uniform sampler2D prev_radiosity_direct_soft;

void main() {
    if (!is_in_world()) {
        position_frag_out = vec4(0.0f);
        normal_frag_out = vec4(0.0f);
        direct_frag_out = vec4(0.0f);
        direct_soft_frag_out = vec4(0.0f);
        return;
    }

    vec4 stagePosition = texelFetch(stage_radiosity_position, tex_coord, 0);
    vec4 stageNormal = texelFetch(stage_radiosity_normal, tex_coord, 0);
    vec4 accumulatedDirect = texelFetch(nrd_denoised_direct, tex_coord, 0);

    float history = max(accumulatedDirect.a, 1.0f);
    vec3 resolvedDirect = accumulatedDirect.rgb;
    vec3 directSum = resolvedDirect * history;

    position_frag_out = stagePosition;
    normal_frag_out = stageNormal;
    direct_frag_out = vec4(resolvedDirect, history > 0.0f ? 1.0f : 0.0f);
    direct_soft_frag_out = vec4(directSum, history);
}
