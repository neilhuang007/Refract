#version 430
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS 1
#define floating_coords_frag_out temporal_gather_floating_coords_frag_out
#define intermediate_reservoir_frag_out temporal_gather_intermediate_reservoir_frag_out
#define intermediate_reservoir_sample_frag_out temporal_gather_intermediate_reservoir_sample_frag_out
#define intermediate_reservoir_meta_frag_out temporal_gather_intermediate_reservoir_meta_frag_out
#define intermediate_reconnection0_frag_out temporal_gather_intermediate_reconnection0_frag_out
#define intermediate_reconnection1_frag_out temporal_gather_intermediate_reconnection1_frag_out
#define PH_LIGHTTREE_ENABLE_TEMPORAL_COLLECT_STAGE 1

// Reference stage 2a -- CollectTemporalSamples::run

in vec4 direction_vert_out;

layout(location = 0) out vec2 temporal_gather_floating_coords_frag_out;
layout(location = 1) out vec4 temporal_gather_intermediate_reservoir_frag_out;
layout(location = 2) out vec4 temporal_gather_intermediate_reservoir_sample_frag_out;
layout(location = 3) out vec4 temporal_gather_intermediate_reservoir_meta_frag_out;
layout(location = 4) out vec4 temporal_gather_intermediate_reconnection0_frag_out;
layout(location = 5) out vec4 temporal_gather_intermediate_reconnection1_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/restir_di_temporal_bridge.glsl"

void storeEmptyCollectTemporalSamplesResult()
{
    floating_coords_frag_out = vec2(-1.0f);
    intermediate_reservoir_frag_out = rtxdi_pack_reservoir(RTXDI_EmptyDIReservoir());
    intermediate_reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(RTXDI_EmptyDIReservoir());
    intermediate_reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(RTXDI_EmptyDIReservoir());
    intermediate_reconnection0_frag_out = vec4(0.0f);
    intermediate_reconnection1_frag_out = vec4(0.0f);
}

void main()
{
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    storeEmptyCollectTemporalSamplesResult();

    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return;
    }

    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    ivec2 reservoirPosition = RTXDI_PixelPosToReservoirPos(pixel, int(runtimeParameters.activeCheckerboardField));
    if (!lt_is_active_reservoir_lane(reservoirPosition)) {
        return;
    }

    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);
    RTXDI_RandomSamplerState randomSampler = lt_init_random_sampler(uvec2(pixel), runtimeParameters.frameIndex, 11u);
    lt_di_collect_temporal_samples(pixel, surface, randomSampler);
}

