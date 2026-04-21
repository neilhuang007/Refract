#version 430
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS 1

// Reference stage 2c -- ReprojectTemporalSamples::run

in vec4 direction_vert_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/restir_di_temporal_bridge.glsl"

void main()
{
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return;
    }

    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    ivec2 reservoirPosition = RTXDI_PixelPosToReservoirPos(pixel, int(runtimeParameters.activeCheckerboardField));
    if (!lt_is_active_reservoir_lane(reservoirPosition)) {
        return;
    }

    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);
    RTXDI_RandomSamplerState randomSampler = lt_init_random_sampler(uvec2(pixel), runtimeParameters.frameIndex, 7u);
    lt_di_reproject_temporal_samples(pixel, surface, randomSampler);
}


