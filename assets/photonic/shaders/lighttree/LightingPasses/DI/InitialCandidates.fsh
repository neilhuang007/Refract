#version 430

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;
layout(location = 3) out vec4 reconnection0_frag_out;
layout(location = 4) out vec4 reconnection1_frag_out;
layout(location = 5) out vec4 reconnection2_frag_out;
layout(location = 6) out vec4 reconnection3_frag_out;
layout(location = 7) out vec4 reconnection4_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/initial_candidates_stage.glsl"

void main()
{
    ivec2 reservoirPos = ivec2(gl_FragCoord.xy);
    int activeField = int(ph_restir_active_checkerboard_field);
    ivec2 pixel = (activeField == 0)
        ? reservoirPos
        : RTXDI_ReservoirPosToPixelPos(reservoirPos, activeField);
    InitialCandidates_run(pixel);
}
