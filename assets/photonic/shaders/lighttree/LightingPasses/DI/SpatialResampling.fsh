#version 430

// Reference stage 6 -- SpatialResampling::run

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
#include "/photonics/lighttree/restir_di_bridge.glsl"

void storeSpatialResamplingResult(
    RTXDI_DIReservoir reservoir,
    ReservoirSplattingReconnectionData reconnectionData)
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
            currReservoir = SpatialResampling_run(
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
