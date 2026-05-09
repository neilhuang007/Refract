#version 430

// Copy post-clamping slow history into the public NRD output buffers.
// This breaks read/write feedback before AntiFirefly and gives the atrous chain
// a stable pre-firefly source.

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_out_diff_radiance_hitdist_out;
layout(location = 1) out vec4 nrd_out_spec_radiance_hitdist_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

void main() {
    ivec2 pixelPos = tex_coord;
    float isSky = texelFetch(nrd_in_tiles, pixelPos >> 4, 0).r;

    if (isSky > 0.5) {
        nrd_out_diff_radiance_hitdist_out = vec4(0.0);
        nrd_out_spec_radiance_hitdist_out = vec4(0.0);
        return;
    }

    nrd_out_diff_radiance_hitdist_out = texelFetch(nrd_diff_illum_prev, pixelPos, 0);
    nrd_out_spec_radiance_hitdist_out = texelFetch(nrd_spec_illum_prev, pixelPos, 0);
}
