#version 430
#define PH_LIGHTTREE_ENABLE_LOCAL_LIGHT_SAMPLING_BUFFERS 0
#define PH_LIGHTTREE_ENABLE_POWER_LIGHT_CDF 0
#define PH_LIGHTTREE_ENABLE_SPATIAL_NEIGHBOR_OFFSETS 0
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS 1
#define PH_LIGHTTREE_ENABLE_TEMPORAL_REPROJECT_STAGE 1

in vec4 direction_vert_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/ReservoirSplatting/ReprojectTemporalSamples.glsl"

void main()
{
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    if (!lt_is_viewport_uv_in_bounds(pixel))
    {
        return;
    }

    ReprojectTemporalSamples_run(pixel);
}
