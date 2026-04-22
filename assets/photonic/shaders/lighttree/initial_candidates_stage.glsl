#ifndef PHOTONICS_INITIAL_CANDIDATES_STAGE_GLSL
#define PHOTONICS_INITIAL_CANDIDATES_STAGE_GLSL

#include "/photonics/lighttree/restir_gi_initial_sampling_impl.glsl"
#include "/photonics/lighttree/initial_candidates_outputs.glsl"
#include "/photonics/lighttree/initial_candidates_reconnection.glsl"
#include "/photonics/lighttree/initial_candidates_path_state.glsl"
#include "/photonics/lighttree/initial_candidates_reservoir.glsl"

void InitialCandidates_tracePrimaryMiss(
    inout RTXDI_DIReservoir currReservoir,
    inout ReservoirSplattingReconnectionData currReconnectionData,
    inout PathState path)
{
    path.reservoir = RTXDI_EmptyDIReservoir();
    path.reconnection = ReservoirSplattingReconnectionData_init();
    path.selectedLightSample = RAB_EmptyLightSample();
    InitialCandidates_addCandidateReservoir(currReservoir, currReconnectionData, path);
}

void InitialCandidates_tracePath(
    const RTXDI_Parameters params,
    inout RTXDI_DIReservoir currReservoir,
    inout ReservoirSplattingReconnectionData currReconnectionData,
    inout PathState path)
{
    if (!RAB_IsSurfaceValid(path.surface))
    {
        InitialCandidates_tracePrimaryMiss(currReservoir, currReconnectionData, path);
        return;
    }

    path.reservoir = InitialCandidates_SampleLightsForSurface(
        path.sg,
        path.coherentRng,
        path.surface,
        params.initialSamplingParams,
        path.selectedLightSample
    );

    path.reconnection = RTXDI_IsValidDIReservoir(path.reservoir)
        ? InitialCandidates_buildSelectedReconnection(
            path.surface,
            path.reservoir,
            path.selectedLightSample,
            PathState_getPixel(path)
        )
        : ReservoirSplattingReconnectionData_init();

    InitialCandidates_addCandidateReservoir(currReservoir, currReconnectionData, path);
}

void InitialCandidates_run(ivec2 pixel)
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

    const RTXDI_Parameters params = lt_build_restir_di_parameters();
    RTXDI_DIReservoir currReservoir = RTXDI_EmptyDIReservoir();
    ReservoirSplattingReconnectionData currReconnectionData = ReservoirSplattingReconnectionData_init();

    for (uint sampleIdx = 0u; sampleIdx < uint(kSamplesPerPixel); ++sampleIdx)
    {
        PathState path;
        InitialCandidates_generatePath(path, pixel, sampleIdx);
        InitialCandidates_tracePath(params, currReservoir, currReconnectionData, path);
    }

    InitialCandidates_storeReservoir(currReservoir, currReconnectionData);
}

#endif
