#ifndef PHOTONICS_DI_INITIAL_CANDIDATES_RUN_GLSL
#define PHOTONICS_DI_INITIAL_CANDIDATES_RUN_GLSL

void tracePath(ivec2 pixel)
{
    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);
    if (!RAB_IsSurfaceValid(surface))
    {
        InitialCandidates_storeEmptyReservoir();
        return;
    }

    RTXDI_DIReservoir currReservoir = RTXDI_EmptyDIReservoir();
    ReservoirSplattingReconnectionData currReconnectionData = ReservoirSplattingReconnectionData_init();
    addCandidateReservoir(
        pixel,
        surface,
        currReservoir,
        currReconnectionData
    );
    InitialCandidates_storeReservoir(currReservoir, currReconnectionData);
}

void execute(ivec2 pixel)
{
    InitialCandidates_storeEmptyReservoir();

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

    tracePath(pixel);
}

void run(ivec2 pixel)
{
    execute(pixel);
}

#endif

