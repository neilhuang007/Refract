#version 430
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS 1
#define PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_REPROJECT_STAGE 1

in vec4 direction_vert_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/ReservoirSplatting/MultiReprojectTemporalSamples.glsl"

void main()
{
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    if (!lt_is_viewport_uv_in_bounds(pixel))
    {
        return;
    }

    MultiReprojectTemporalSamples_run(pixel);
}
