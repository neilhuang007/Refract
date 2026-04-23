#ifndef PHOTONICS_RESTIR_DI_RECONNECTION_RESTORE_GLSL
#define PHOTONICS_RESTIR_DI_RECONNECTION_RESTORE_GLSL

bool RestirDI_restoreReconnectionRadiometry(
    ivec2 pixelPosition,
    bool previousFrame,
    RTXDI_DIReservoir reservoir,
    inout ReservoirSplattingReconnectionData reconnection)
{
    if (!lt_is_viewport_uv_in_bounds(pixelPosition) || !RTXDI_IsValidDIReservoir(reservoir)) {
        return false;
    }

    RAB_Surface sourceSurface = RAB_GetGBufferSurface(pixelPosition, previousFrame);
    if (!RAB_IsSurfaceValid(sourceSurface)) {
        return false;
    }

    if (dot(reconnection.firstHit.worldPos, reconnection.firstHit.worldPos) <= 0.0f) {
        reconnection.firstHit.worldPos = sourceSurface.worldPos;
    }
    reconnection.firstHit.viewDepth = sourceSurface.viewDepth;
    reconnection.secondHit.viewDepth = sourceSurface.viewDepth;
    return true;
}

ScatterReconnectionData RestirDI_loadPreviousFrameReconnection(ivec2 pixelPosition)
{
    vec4 prevReservoirMeta = texelFetch(prev_radiosity_reservoir_meta, pixelPosition, 0);
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
        prevReservoirMeta.y,
        prevReservoirMeta.z,
        reconnection
    );
    RestirDI_restoreReconnectionRadiometry(pixelPosition, true, prevReservoir, reconnection);
    return reconnection;
}

ScatterReconnectionData RestirDI_loadGatherIntermediateReconnection(ivec2 pixelPosition)
{
    vec4 intermediateReservoirMeta = texelFetch(temporal_gather_intermediate_reservoir_meta, pixelPosition, 0);
    RTXDI_DIReservoir intermediateReservoir = RTXDI_EmptyDIReservoir();
    rtxdi_unpack_reservoir_at_surface(
        intermediateReservoir,
        texelFetch(temporal_gather_intermediate_reservoir_data, pixelPosition, 0),
        texelFetch(temporal_gather_intermediate_reservoir_sample, pixelPosition, 0),
        intermediateReservoirMeta,
        RAB_EmptySurface(),
        false
    );

    ScatterReconnectionData reconnection;
    scatter_unpack_reconnection(
        texelFetch(temporal_gather_intermediate_reconnection0, pixelPosition, 0),
        texelFetch(temporal_gather_intermediate_reconnection1, pixelPosition, 0),
        texelFetch(temporal_gather_intermediate_reconnection2, pixelPosition, 0),
        texelFetch(temporal_gather_intermediate_reconnection3, pixelPosition, 0),
        texelFetch(temporal_gather_intermediate_reconnection4, pixelPosition, 0),
        intermediateReservoirMeta.y,
        intermediateReservoirMeta.z,
        reconnection
    );
    RestirDI_restoreReconnectionRadiometry(pixelPosition, true, intermediateReservoir, reconnection);
    return reconnection;
}

#endif
