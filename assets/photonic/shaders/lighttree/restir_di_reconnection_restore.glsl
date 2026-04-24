#ifndef PHOTONICS_RESTIR_DI_RECONNECTION_RESTORE_GLSL
#define PHOTONICS_RESTIR_DI_RECONNECTION_RESTORE_GLSL

#ifndef temporal_gather_previous_reservoir_data
#define temporal_gather_previous_reservoir_data temporal_gather_intermediate_reservoir_data
#endif
#ifndef temporal_gather_previous_reservoir_sample
#define temporal_gather_previous_reservoir_sample temporal_gather_intermediate_reservoir_sample
#endif
#ifndef temporal_gather_previous_reservoir_meta
#define temporal_gather_previous_reservoir_meta temporal_gather_intermediate_reservoir_meta
#endif
#ifndef temporal_gather_previous_reconnection0
#define temporal_gather_previous_reconnection0 temporal_gather_intermediate_reconnection0
#endif
#ifndef temporal_gather_previous_reconnection1
#define temporal_gather_previous_reconnection1 temporal_gather_intermediate_reconnection1
#endif
#ifndef temporal_gather_previous_reconnection2
#define temporal_gather_previous_reconnection2 temporal_gather_intermediate_reconnection2
#endif
#ifndef temporal_gather_previous_reconnection3
#define temporal_gather_previous_reconnection3 temporal_gather_intermediate_reconnection3
#endif
#ifndef temporal_gather_previous_reconnection4
#define temporal_gather_previous_reconnection4 temporal_gather_intermediate_reconnection4
#endif

bool RestirDI_restoreReconnectionRadiometry(
    ivec2 pixelPosition,
    bool previousFrame,
    RTXDI_DIReservoir reservoir,
    inout ReservoirSplattingReconnectionData reconnection)
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

    if (!(reconnection.firstHit.viewDepth > 0.0f))
    {
        reconnection.firstHit.viewDepth = surface.viewDepth;
    }
    if (!(reconnection.secondHit.viewDepth > 0.0f))
    {
        reconnection.secondHit.viewDepth = max(reconnection.firstHit.viewDepth, surface.viewDepth);
    }

    return true;
}

ScatterReconnectionData RestirDI_loadPreviousFrameReconnection(ivec2 pixelPosition)
{
    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixelPosition)
    );
    ScatterReconnectionData reconnection;
    scatter_unpack_reconnection(
        texelFetch(previous_frame_reconnection0, pixelPosition, 0),
        texelFetch(previous_frame_reconnection1, pixelPosition, 0),
        texelFetch(previous_frame_reconnection2, pixelPosition, 0),
        texelFetch(previous_frame_reconnection3, pixelPosition, 0),
        texelFetch(previous_frame_reconnection4, pixelPosition, 0),
        0.0f,
        0.0f,
        reconnection
    );
    RestirDI_restoreReconnectionRadiometry(pixelPosition, true, prevReservoir, reconnection);
    return reconnection;
}

ScatterReconnectionData RestirDI_loadPreviousTemporalReconnection(ivec2 pixelPosition)
{
    vec4 prevReservoirMeta = texelFetch(temporal_gather_previous_reservoir_meta, pixelPosition, 0);
    RTXDI_DIReservoir prevReservoir = RTXDI_EmptyDIReservoir();
    rtxdi_unpack_reservoir_at_surface(
        prevReservoir,
        texelFetch(temporal_gather_previous_reservoir_data, pixelPosition, 0),
        texelFetch(temporal_gather_previous_reservoir_sample, pixelPosition, 0),
        prevReservoirMeta,
        RAB_EmptySurface(),
        false
    );

    ScatterReconnectionData reconnection;
    scatter_unpack_reconnection(
        texelFetch(temporal_gather_previous_reconnection0, pixelPosition, 0),
        texelFetch(temporal_gather_previous_reconnection1, pixelPosition, 0),
        texelFetch(temporal_gather_previous_reconnection2, pixelPosition, 0),
        texelFetch(temporal_gather_previous_reconnection3, pixelPosition, 0),
        texelFetch(temporal_gather_previous_reconnection4, pixelPosition, 0),
        0.0f,
        0.0f,
        reconnection
    );
    RestirDI_restoreReconnectionRadiometry(pixelPosition, true, prevReservoir, reconnection);
    return reconnection;
}

ScatterReconnectionData RestirDI_loadGatherIntermediateReconnection(ivec2 pixelPosition)
{
    return RestirDI_loadPreviousTemporalReconnection(pixelPosition);
}

#endif
