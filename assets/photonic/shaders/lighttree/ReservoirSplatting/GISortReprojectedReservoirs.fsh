#version 430
#define PH_GI_TEMPORAL_GLOBAL_COUNTER_BUFFER 1
#define PH_GI_TEMPORAL_RECORD_BUFFER 1
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

    ivec2 reservoirSize = ivec2(max(int(viewWidth), 1), max(int(viewHeight), 1));
    uint index = uint(gl_FragCoord.y) * uint(reservoirSize.x) + uint(gl_FragCoord.x);
    if (index >= uint(reservoirSize.x) * uint(reservoirSize.y)) {
        return;
    }

    gi_temporal_splat_sort_record(index);
}
