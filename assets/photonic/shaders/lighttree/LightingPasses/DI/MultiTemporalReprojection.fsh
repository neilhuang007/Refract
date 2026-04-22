#version 430
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS 1
#define PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_REPROJECT_STAGE 1

in vec4 direction_vert_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/ReservoirSplatting/MultiReprojectTemporalSamples.glsl"

void MultiReprojectTemporalSamples_execute(ivec2 pixel)
{
    MultiReprojectTemporalSamples_run(pixel);
}

void main()
{
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    if (!lt_is_viewport_uv_in_bounds(pixel))
    {
        return;
    }

    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    ivec2 reservoirPosition = RTXDI_PixelPosToReservoirPos(pixel, int(runtimeParameters.activeCheckerboardField));
    if (!lt_is_active_reservoir_lane(reservoirPosition))
    {
        return;
    }

    MultiReprojectTemporalSamples_execute(pixel);
}
