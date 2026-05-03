#version 430
#define PH_GI_TEMPORAL_GLOBAL_COUNTER_BUFFER 1
#define PH_GI_TEMPORAL_CELL_COUNTER_BUFFER 1
#define PH_GI_TEMPORAL_SORT_BUFFERS 1

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/ReservoirSplatting/GITemporalSplatting.glsl"

void main()
{
    reservoir_frag_out = vec4(0.0f);
    reservoir_sample_frag_out = vec4(0.0f);
    reservoir_meta_frag_out = vec4(0.0f);

    ivec2 pixel = ivec2(gl_FragCoord.xy);
    if (!gi_temporal_splat_in_bounds(pixel)) {
        return;
    }

    gi_temporal_splat_compute_cell_offset(pixel);
}
