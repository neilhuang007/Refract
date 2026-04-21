#version 430

// Reference stage 3 -- SpatialResampling::run

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;
layout(location = 3) out vec4 reconnection0_frag_out;
layout(location = 4) out vec4 reconnection1_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/restir_di_bridge.glsl"

void storeSpatialResamplingResult(
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

void storeEmptySpatialResamplingResult()
{
    storeSpatialResamplingResult(
        RTXDI_EmptyDIReservoir(),
        ReservoirSplattingReconnectionData_init()
    );
}

void main()
{
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    storeEmptySpatialResamplingResult();

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

    RTXDI_RandomSamplerState randomSampler = RTXDI_InitRandomSampler(
        uvec2(pixel),
        runtimeParameters.frameIndex,
        RTXDI_DI_SPATIAL_RESAMPLING_RANDOM_SEED
    );
    const RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    RAB_Surface centerSurface = RAB_GetGBufferSurface(pixel, false);
    RTXDI_DIReservoir currReservoir = RTXDI_EmptyDIReservoir();
    ReservoirSplattingReconnectionData currReconnectionData = ReservoirSplattingReconnectionData_init();

    if (RAB_IsSurfaceValid(centerSurface))
    {
        RTXDI_DIReservoir centralReservoir = RTXDI_LoadDIReservoir(
            restirDI.reservoirBufferParams,
            uvec2(reservoirPosition),
            restirDI.bufferIndices.spatialResamplingInputBufferIndex
        );

        if (RTXDI_IsValidDIReservoir(centralReservoir))
        {
            currReservoir = lt_di_spatial_resampling_stage(
                pixel,
                centerSurface,
                centralReservoir,
                randomSampler,
                currReconnectionData
            );
        }
    }

    storeSpatialResamplingResult(currReservoir, currReconnectionData);
}
