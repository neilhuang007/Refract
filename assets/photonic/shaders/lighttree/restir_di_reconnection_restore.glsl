#ifndef PHOTONICS_RESTIR_DI_RECONNECTION_RESTORE_GLSL
#define PHOTONICS_RESTIR_DI_RECONNECTION_RESTORE_GLSL

bool RestirDI_restoreReconnectionRadiometry(
    ivec2 pixelPosition,
    bool previousFrame,
    RTXDI_DIReservoir reservoir,
    inout ReconnectionData reconnection)
{
    if (!lt_is_viewport_uv_in_bounds(pixelPosition) || !RTXDI_IsValidDIReservoir(reservoir))
    {
        return false;
    }

    RAB_Surface surface = previousFrame
        ? lt_load_previous_surface(pixelPosition)
        : RAB_GetGBufferSurface(pixelPosition, false);
    if (!RAB_IsSurfaceValid(surface))
    {
        return false;
    }

    reconnection.subPixel = PathReservoir_getSubPixel(reservoir, pixelPosition);
    reconnection.lensSample = PathReservoir_getLensSample(reservoir);
    reconnection.time = lt_path_sample_time(reservoir.pathSample);

    return true;
}

ReconnectionData RestirDI_loadPreviousFrameReconnection(ivec2 pixelPosition)
{
    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixelPosition)
    );
    ReconnectionData reconnection;
    scatter_unpack_reconnection(
        texelFetch(prev_scatter_reconnection0, pixelPosition, 0),
        texelFetch(prev_scatter_reconnection1, pixelPosition, 0),
        texelFetch(prev_scatter_reconnection2, pixelPosition, 0),
        texelFetch(prev_scatter_reconnection3, pixelPosition, 0),
        texelFetch(prev_scatter_reconnection4, pixelPosition, 0),
        0.0f,
        0.0f,
        reconnection
    );
    RestirDI_restoreReconnectionRadiometry(pixelPosition, true, prevReservoir, reconnection);
    return reconnection;
}

ReconnectionData RestirDI_loadPreviousTemporalReconnection(ivec2 pixelPosition)
{
    ReconnectionData reconnection;
    scatter_unpack_reconnection(
        texelFetch(temporal_gather_intermediate_reconnection0, pixelPosition, 0),
        texelFetch(temporal_gather_intermediate_reconnection1, pixelPosition, 0),
        texelFetch(temporal_gather_intermediate_reconnection2, pixelPosition, 0),
        texelFetch(temporal_gather_intermediate_reconnection3, pixelPosition, 0),
        texelFetch(temporal_gather_intermediate_reconnection4, pixelPosition, 0),
        0.0f,
        0.0f,
        reconnection
    );
    return reconnection;
}

ReconnectionData RestirDI_loadGatherIntermediateReconnection(ivec2 pixelPosition)
{
    return RestirDI_loadPreviousTemporalReconnection(pixelPosition);
}

#endif
