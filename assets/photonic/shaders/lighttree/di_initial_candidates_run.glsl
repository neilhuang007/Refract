#ifndef PHOTONICS_DI_INITIAL_CANDIDATES_RUN_GLSL
#define PHOTONICS_DI_INITIAL_CANDIDATES_RUN_GLSL

void tracePath(
    ivec2 pixel,
    RTXDI_Parameters restirDI,
    RTXDI_RuntimeParameters runtimeParameters)
{
    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);
    if (!RAB_IsSurfaceValid(surface))
    {
        storeEmptyInitialCandidatesResult();
        return;
    }

    ReservoirSplattingReconnectionData reconnectionData = ReservoirSplattingReconnectionData_init();
    RTXDI_DIReservoir reservoir = addCandidateReservoir(
        surface,
        pixel,
        restirDI,
        runtimeParameters,
        reconnectionData
    );
    storeInitialCandidatesResult(reservoir, reconnectionData);
}

void run(ivec2 pixel)
{
    storeEmptyInitialCandidatesResult();

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

    const RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    tracePath(pixel, restirDI, runtimeParameters);
}

#endif
