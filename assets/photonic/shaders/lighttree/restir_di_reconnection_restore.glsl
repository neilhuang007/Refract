#ifndef PHOTONICS_RESTIR_DI_RECONNECTION_RESTORE_GLSL
#define PHOTONICS_RESTIR_DI_RECONNECTION_RESTORE_GLSL

bool RestirDI_hasStoredPrimaryHit(ReconnectionData reconnection)
{
    return reconnection.firstHit.viewDepth > 0.0f
        && any(greaterThan(abs(reconnection.firstHit.worldPos), vec3(0.0f)));
}

bool RestirDI_hasStoredSecondHit(ReconnectionData reconnection)
{
    return reconnection.pathLength > 1u
        && any(greaterThan(abs(reconnection.secondHit.worldPos), vec3(0.0f)));
}

bool RestirDI_hasStoredRadiometry(ReconnectionData reconnection)
{
    return reconnection.pathLength > 1u
        && (reconnection.lightPdf > 0.0f
            || any(greaterThan(reconnection.irradiance, vec3(0.0f)))
            || any(greaterThan(reconnection.earlyThroughput, vec3(0.0f)))
            || dot(reconnection.secondWo, reconnection.secondWo) > 1e-12f
            || RestirDI_hasStoredSecondHit(reconnection));
}

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

    reconnection.subPixel = PathReservoir_getSubPixel(reservoir, pixelPosition);
    reconnection.lensSample = PathReservoir_getLensSample(reservoir);
    reconnection.time = lt_path_sample_time(reservoir.pathSample);

    bool hasStoredPrimaryHit = RestirDI_hasStoredPrimaryHit(reconnection);
    bool hasStoredRadiometry = RestirDI_hasStoredRadiometry(reconnection);

    RAB_Surface surface = previousFrame
        ? lt_load_previous_surface(pixelPosition)
        : RAB_GetGBufferSurface(pixelPosition, false);
    bool surfaceValid = RAB_IsSurfaceValid(surface);

    if (!hasStoredPrimaryHit && surfaceValid)
    {
        vec4 identityData = scatter_load_surface_identity(pixelPosition, previousFrame);
        uint packedIdentity = uint(round(identityData.w));
        reconnection.firstHit.worldPos = surface.worldPos;
        reconnection.firstHit.viewDepth = surface.viewDepth;
        reconnection.firstHit.faceId = packedIdentity & 0x7u;
        reconnection.firstHit.materialId = packedIdentity >> 3u;
        reconnection.firstBSDFComponentType = scatter_resolve_first_bsdf_component_type(surface);
        hasStoredPrimaryHit = true;
    }

    vec3 firstRayOrigin = scatter_resolve_camera_origin_at_time(
        reconnection.time,
        reconnection.lensSample
    );
    if (dot(reconnection.firstWi, reconnection.firstWi) <= 1e-12f && hasStoredPrimaryHit)
    {
        vec3 firstWi = firstRayOrigin - reconnection.firstHit.worldPos;
        float firstWiLengthSq = dot(firstWi, firstWi);
        reconnection.firstWi = (firstWiLengthSq > 1e-12f)
            ? firstWi * inversesqrt(firstWiLengthSq)
            : vec3(0.0f);
    }

    int reservoirLightIndex = RTXDI_GetReservoirLightIndexForFrame(
        reservoir,
        previousFrame,
        previousFrame
    );
    if (reservoirLightIndex >= 0)
    {
        reconnection.secondHit.materialId = uint(reservoirLightIndex);
    }

    if (!hasStoredRadiometry)
    {
        if (!surfaceValid)
        {
            return hasStoredPrimaryHit;
        }

        RAB_LightSample lightSample = lt_decode_reservoir_sample_for_frame(
            reservoir,
            surface,
            previousFrame,
            previousFrame
        );
        if (lightSample.index < 0)
        {
            reconnection.pathLength = 1u;
            reconnection.secondHit = HitInfo_empty();
            reconnection.secondBSDFComponentType = 0u;
            reconnection.secondWo = vec3(0.0f);
            reconnection.lightIsNEE = false;
            reconnection.lightIsDistant = false;
            reconnection.lightPdf = 0.0f;
            reconnection.irradiance = vec3(0.0f);
            reconnection.earlyThroughput = vec3(0.0f);
            reconnection.secondaryPathJacobian = 1.0f;
            return false;
        }

        reconnection.pathLength = 2u;
        reconnection.secondHit.worldPos = lightSample.position;
        reconnection.secondHit.viewDepth = 0.0f;
        reconnection.secondHit.faceId = 0u;
        reconnection.secondBSDFComponentType = scatter_resolve_second_bsdf_component_type(lightSample);
        reconnection.secondWo = (distance(lightSample.position, surface.worldPos) > 1e-6f)
            ? normalize(lightSample.position - surface.worldPos)
            : vec3(0.0f);
        reconnection.lightIsNEE = RAB_IsAnalyticLightSample(lightSample);
        reconnection.lightIsDistant = !reconnection.lightIsNEE;
        reconnection.lightPdf = scatter_resolve_light_pdf(reservoir, lightSample);
        reconnection.irradiance = scatter_resolve_irradiance(surface, reservoir, lightSample);
        reconnection.earlyThroughput = scatter_resolve_early_throughput(surface, reservoir, lightSample);
        return true;
    }

    if (dot(reconnection.secondWo, reconnection.secondWo) <= 1e-12f
        && hasStoredPrimaryHit
        && RestirDI_hasStoredSecondHit(reconnection))
    {
        vec3 secondWo = reconnection.secondHit.worldPos - reconnection.firstHit.worldPos;
        float secondWoLengthSq = dot(secondWo, secondWo);
        reconnection.secondWo = (secondWoLengthSq > 1e-12f)
            ? secondWo * inversesqrt(secondWoLengthSq)
            : vec3(0.0f);
    }

    return true;
}

ReconnectionData RestirDI_loadPreviousFrameReconnection(ivec2 pixelPosition)
{
    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixelPosition)
    );
    ReconnectionData reconnection;
    // prev_scatter_reconnection* are half-width when checkerboard is active; halve x.
    ivec2 reservoirPos = RTXDI_PixelPosToReservoirPos(pixelPosition, ph_restir_active_checkerboard_field);
    scatter_unpack_reconnection(
        texelFetch(prev_scatter_reconnection0, reservoirPos, 0),
        texelFetch(prev_scatter_reconnection1, reservoirPos, 0),
        texelFetch(prev_scatter_reconnection2, reservoirPos, 0),
        texelFetch(prev_scatter_reconnection3, reservoirPos, 0),
        texelFetch(prev_scatter_reconnection4, reservoirPos, 0),
        0.0f,
        0.0f,
        reconnection
    );
    RestirDI_restoreReconnectionRadiometry(pixelPosition, true, prevReservoir, reconnection);
    return reconnection;
}

bool RestirDI_restoreTemporalIntermediateReconnection(
    ivec2 pixelPosition,
    RTXDI_DIReservoir reservoir,
    inout ReconnectionData reconnection)
{
    if (!lt_is_viewport_uv_in_bounds(pixelPosition) || !RTXDI_IsValidDIReservoir(reservoir))
    {
        return false;
    }

    reconnection.subPixel = PathReservoir_getSubPixel(reservoir, pixelPosition);
    reconnection.lensSample = PathReservoir_getLensSample(reservoir);
    reconnection.time = lt_path_sample_time(reservoir.pathSample);

    int reservoirLightIndex = RTXDI_GetReservoirLightIndexForFrame(
        reservoir,
        true,
        true
    );
    if (reservoirLightIndex >= 0)
    {
        reconnection.secondHit.materialId = uint(reservoirLightIndex);
    }

    if (dot(reconnection.firstWi, reconnection.firstWi) <= 1e-12f
        && dot(reconnection.firstHit.worldPos, reconnection.firstHit.worldPos) > 0.0f)
    {
        vec3 firstRayOrigin = scatter_resolve_camera_origin_at_time(
            reconnection.time,
            reconnection.lensSample
        );
        vec3 firstWi = firstRayOrigin - reconnection.firstHit.worldPos;
        float firstWiLengthSq = dot(firstWi, firstWi);
        reconnection.firstWi = (firstWiLengthSq > 1e-12f)
            ? firstWi * inversesqrt(firstWiLengthSq)
            : vec3(0.0f);
    }

    return true;
}

ReconnectionData RestirDI_loadPreviousTemporalReconnection(ivec2 pixelPosition)
{
    RTXDI_DIReservoir temporalReservoir = RTXDI_EmptyDIReservoir();
    // temporal_gather_intermediate_* are half-width when checkerboard is active; halve x.
    ivec2 reservoirPos = RTXDI_PixelPosToReservoirPos(pixelPosition, ph_restir_active_checkerboard_field);
    rtxdi_unpack_reservoir_at_surface(
        temporalReservoir,
        texelFetch(temporal_gather_intermediate_reservoir_data, reservoirPos, 0),
        texelFetch(temporal_gather_intermediate_reservoir_sample, reservoirPos, 0),
        texelFetch(temporal_gather_intermediate_reservoir_meta, reservoirPos, 0),
        RAB_EmptySurface(),
        false
    );

    ReconnectionData reconnection;
    scatter_unpack_reconnection(
        texelFetch(temporal_gather_intermediate_reconnection0, reservoirPos, 0),
        texelFetch(temporal_gather_intermediate_reconnection1, reservoirPos, 0),
        texelFetch(temporal_gather_intermediate_reconnection2, reservoirPos, 0),
        texelFetch(temporal_gather_intermediate_reconnection3, reservoirPos, 0),
        texelFetch(temporal_gather_intermediate_reconnection4, reservoirPos, 0),
        0.0f,
        0.0f,
        reconnection
    );
    RestirDI_restoreTemporalIntermediateReconnection(pixelPosition, temporalReservoir, reconnection);
    return reconnection;
}

ReconnectionData RestirDI_loadGatherIntermediateReconnection(ivec2 pixelPosition)
{
    return RestirDI_loadPreviousTemporalReconnection(pixelPosition);
}

#endif
