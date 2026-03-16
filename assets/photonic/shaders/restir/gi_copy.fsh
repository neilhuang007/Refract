#version 430

/*
    -- INPUT VARIABLES --
*/
in vec4 direction_vert_out;

/*
    -- OUTPUT VARIABLES --
*/
layout(location = 0) out vec4 gi_reservoir_pos_frag_out;
layout(location = 1) out vec4 gi_reservoir_normal_frag_out;
layout(location = 2) out vec4 gi_reservoir_radiance_frag_out;
layout(location = 3) out vec4 gi_reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"

uniform sampler2D stage_radiosity_gi_reservoir_pos;
uniform sampler2D stage_radiosity_gi_reservoir_normal;
uniform sampler2D stage_radiosity_gi_reservoir_radiance;
uniform sampler2D stage_radiosity_gi_reservoir_meta;

void main() {
    gi_reservoir_pos_frag_out = texelFetch(stage_radiosity_gi_reservoir_pos, tex_coord, 0);
    gi_reservoir_normal_frag_out = texelFetch(stage_radiosity_gi_reservoir_normal, tex_coord, 0);
    gi_reservoir_radiance_frag_out = texelFetch(stage_radiosity_gi_reservoir_radiance, tex_coord, 0);
    gi_reservoir_meta_frag_out = texelFetch(stage_radiosity_gi_reservoir_meta, tex_coord, 0);
}
