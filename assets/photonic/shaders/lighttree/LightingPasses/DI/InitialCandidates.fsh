#version 430

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;
layout(location = 3) out vec4 reconnection0_frag_out;
layout(location = 4) out vec4 reconnection1_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#define PH_LIGHTTREE_RECONNECTION_PACK_ONLY 1
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/initial_candidates_stage.glsl"

void main()
{
    InitialCandidates_run(ivec2(gl_FragCoord.xy));
}
