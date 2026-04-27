#version 430
#define PH_LIGHTTREE_ENABLE_TEMPORAL_COLLECT_STAGE 1

in vec4 direction_vert_out;

layout(location = 0) out vec4 intermediate_reservoir_frag_out;
layout(location = 1) out vec4 intermediate_reservoir_sample_frag_out;
layout(location = 2) out vec4 intermediate_reservoir_meta_frag_out;
layout(location = 3) out vec4 intermediate_reconnection0_frag_out;
layout(location = 4) out vec4 intermediate_reconnection1_frag_out;
layout(location = 5) out vec4 intermediate_reconnection2_frag_out;
layout(location = 6) out vec4 intermediate_reconnection3_frag_out;
layout(location = 7) out vec4 intermediate_reconnection4_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/restir_di_temporal_buffer_bridge.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/ReservoirSplatting/CollectTemporalSamples.glsl"

void main()
{
    ivec2 currPixel = ivec2(gl_FragCoord.xy);
    CollectTemporalSamples_store_empty_result();

    if (!lt_is_viewport_uv_in_bounds(currPixel))
    {
        return;
    }

    CollectTemporalSamples_execute(currPixel);
}
