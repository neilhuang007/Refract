#ifndef PHOTONICS_RESTIR_DI_RECONNECTION_RESTORE_GLSL
#define PHOTONICS_RESTIR_DI_RECONNECTION_RESTORE_GLSL

bool RestirDI_restoreReconnectionRadiometry(
    ivec2 pixelPosition,
    bool previousFrame,
    RTXDI_DIReservoir reservoir,
    inout ReservoirSplattingReconnectionData reconnection)
{
    reconnection.firstWi = normalize(
        (previousFrame ? previous_world_camera_position : world_camera_position)
        - reconnection.firstHit.worldPos
    );

    if (!lt_is_viewport_uv_in_bounds(pixelPosition) || !RTXDI_IsValidDIReservoir(reservoir)) {
        reconnection.irradiance = vec3(0.0f);
        reconnection.earlyThroughput = vec3(1.0f);
        return false;
    }

    RAB_Surface surface = RAB_GetGBufferSurface(pixelPosition, previousFrame);
    if (!RAB_IsSurfaceValid(surface)) {
        reconnection.irradiance = vec3(0.0f);
        reconnection.earlyThroughput = vec3(1.0f);
        return false;
    }

    RAB_LightSample lightSample = lt_decode_reservoir_sample_for_frame(
        reservoir,
        surface,
        previousFrame,
        previousFrame
    );
    if (lightSample.index < 0) {
        reconnection.irradiance = vec3(0.0f);
        reconnection.earlyThroughput = vec3(1.0f);
        return false;
    }

    reconnection.lightPdf = scatter_resolve_light_pdf(reservoir, lightSample);
    reconnection.irradiance = scatter_resolve_irradiance(surface, lightSample);
    reconnection.earlyThroughput = scatter_resolve_early_throughput(surface, lightSample);
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
        texelFetch(prev_radiosity_reservoir_samples, pixelPosition, 0),
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
        texelFetch(temporal_gather_intermediate_reservoir_sample, pixelPosition, 0),
        intermediateReservoirMeta.y,
        intermediateReservoirMeta.z,
        reconnection
    );

    ivec2 sourcePreviousPixel = ivec2(round(scatter_load_gather_floating_coords(pixelPosition)));
    RestirDI_restoreReconnectionRadiometry(sourcePreviousPixel, true, intermediateReservoir, reconnection);
    return reconnection;
}

#endif
