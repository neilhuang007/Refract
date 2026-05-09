#version 430
#define PH_LIGHTTREE_ENABLE_TEMPORAL_GATHER_STAGE 1

in vec4 direction_vert_out;

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
#include "/photonics/lighttree/restir_di_gather_temporal_stage.glsl"

void storeGatherTemporalResamplingResult(
    RTXDI_DIReservoir reservoir,
    ReconnectionData reconnectionData)
{
    float reconnectionTransportAux0;
    float reconnectionTransportAux1;
    scatter_pack_reconnection_fields(
        reconnectionData,
        reconnectionTransportAux0,
        reconnectionTransportAux1,
        reconnection0_frag_out,
        reconnection1_frag_out,
        reconnection2_frag_out,
        reconnection3_frag_out,
        reconnection4_frag_out
    );

    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = PathReservoir_packMeta(reservoir);
}

void storeEmptyGatherTemporalResamplingResult()
{
    storeGatherTemporalResamplingResult(RTXDI_EmptyDIReservoir(), ReconnectionData_init());
}

void main()
{
    ivec2 reservoirPos = ivec2(gl_FragCoord.xy);
    int activeField = int(ph_restir_active_checkerboard_field);
    ivec2 pixel = (activeField == 0)
        ? reservoirPos
        : RTXDI_ReservoirPosToPixelPos(reservoirPos, activeField);
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

    ReconnectionData currReconnectionData = ReconnectionData_init();
    RTXDI_DIReservoir currReservoir = GatherTemporalResampling_run(pixel, currReconnectionData);
    storeGatherTemporalResamplingResult(currReservoir, currReconnectionData);
}
