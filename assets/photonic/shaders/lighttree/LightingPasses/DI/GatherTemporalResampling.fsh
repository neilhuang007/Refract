#version 430
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS 1
#define PH_LIGHTTREE_ENABLE_TEMPORAL_GATHER_STAGE 1

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;
layout(location = 3) out vec4 reconnection0_frag_out;
layout(location = 4) out vec4 reconnection1_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/restir_di_temporal_bridge.glsl"

void storeGatherTemporalResamplingResult(
    RTXDI_DIReservoir reservoir,
    ReservoirSplattingReconnectionData reconnectionData)
{
    float transportAux0;
    float transportAux1;
    scatter_pack_reconnection(
        reconnectionData,
        transportAux0,
        transportAux1,
        reconnection0_frag_out,
        reconnection1_frag_out
    );

    reservoir.transportAux0 = transportAux0;
    reservoir.transportAux1 = transportAux1;
    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(reservoir);
}

void storeEmptyGatherTemporalResamplingResult()
{
    storeGatherTemporalResamplingResult(RTXDI_EmptyDIReservoir(), ReservoirSplattingReconnectionData_init());
}

void run(ivec2 pixel)
{
    ReservoirSplattingReconnectionData currReconnectionData = ReservoirSplattingReconnectionData_init();
    RTXDI_DIReservoir currReservoir = lt_di_gather_temporal_resampling_stage(pixel, currReconnectionData);
    storeGatherTemporalResamplingResult(currReservoir, currReconnectionData);
}

void main()
{
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    storeEmptyGatherTemporalResamplingResult();

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

    run(pixel);
}
