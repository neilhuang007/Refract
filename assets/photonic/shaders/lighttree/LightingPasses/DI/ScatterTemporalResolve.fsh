#version 430
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS 1
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY 1

// Reference stage 2e -- ScatterTemporalResampling::run

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;
layout(location = 3) out vec4 reconnection0_frag_out;
layout(location = 4) out vec4 reconnection1_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/restir_di_temporal_bridge.glsl"

void storeScatterTemporalResamplingResult(
    RTXDI_DIReservoir reservoir,
    ReservoirSplattingReconnectionData reconnectionData)
{
    float sidecarTransportAux0;
    float sidecarTransportAux1;
    scatter_pack_reconnection(
        reconnectionData,
        sidecarTransportAux0,
        sidecarTransportAux1,
        reconnection0_frag_out,
        reconnection1_frag_out
    );
    reservoir.transportAux0 = sidecarTransportAux0;
    reservoir.transportAux1 = sidecarTransportAux1;

    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(reservoir);
}

void storeEmptyScatterTemporalResamplingResult()
{
    storeScatterTemporalResamplingResult(RTXDI_EmptyDIReservoir(), ReservoirSplattingReconnectionData_init());
}

void main()
{
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    if (!RTXDI_IsActiveCheckerboardPixel(pixel, int(ph_restir_active_checkerboard_field))) {
        storeEmptyScatterTemporalResamplingResult();
        return;
    }

    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    ivec2 reservoirPosition = RTXDI_PixelPosToReservoirPos(pixel, int(runtimeParameters.activeCheckerboardField));
    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        storeEmptyScatterTemporalResamplingResult();
        return;
    }

    const RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);

    RTXDI_DIReservoir currReservoir = RTXDI_LoadDIReservoir(
        restirDI.reservoirBufferParams,
        uvec2(reservoirPosition),
        restirDI.bufferIndices.initialSamplingOutputBufferIndex
    );

    RTXDI_RandomSamplerState randomSampler = RTXDI_InitRandomSampler(
        uvec2(pixel),
        runtimeParameters.frameIndex,
        RTXDI_DI_SPATIAL_RESAMPLING_RANDOM_SEED + 47u
    );

    ReservoirSplattingReconnectionData currReconnectionData = ReservoirSplattingReconnectionData_init();
    RTXDI_DIReservoir dstReservoir = lt_di_scatter_temporal_resampling_stage(
        pixel,
        currReconnectionData
    );

    storeScatterTemporalResamplingResult(dstReservoir, currReconnectionData);
}

