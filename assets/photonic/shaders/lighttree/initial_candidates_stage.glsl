#ifndef PHOTONICS_INITIAL_CANDIDATES_STAGE_GLSL
#define PHOTONICS_INITIAL_CANDIDATES_STAGE_GLSL

#include "/photonics/lighttree/restir_gi_initial_sampling_impl.glsl"
#include "/photonics/lighttree/initial_candidates_outputs.glsl"
#include "/photonics/lighttree/initial_candidates_reconnection.glsl"
#include "/photonics/lighttree/initial_candidates_path_state.glsl"
#include "/photonics/lighttree/initial_candidates_reservoir.glsl"

void InitialCandidates_tracePrimaryMiss(
    inout RTXDI_DIReservoir currReservoir,
    inout ReconnectionData currReconnectionData,
    inout PathState path)
{
    path.reservoir = RTXDI_EmptyDIReservoir();
    path.reconnection = ReconnectionData_init();
    path.selectedLightSample = RAB_EmptyLightSample();
    path.selectedIrradiance = vec3(0.0f);
    path.selectedEarlyThroughput = vec3(0.0f);
    InitialCandidates_addCandidateReservoir(currReservoir, currReconnectionData, path);
}

void InitialCandidates_tracePath(
    const RTXDI_Parameters params,
    inout RTXDI_DIReservoir currReservoir,
    inout ReconnectionData currReconnectionData,
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
        path.time,
        path.selectedLightSample,
        path.selectedIrradiance,
        path.selectedEarlyThroughput
    );

    path.reconnection = ReconnectionData_init();

    InitialCandidates_addCandidateReservoir(currReservoir, currReconnectionData, path);
}

void InitialCandidates_run(ivec2 pixel)
{
    if (!lt_is_viewport_uv_in_bounds(pixel))
    {
        InitialCandidates_storeEmptyReservoir();
        return;
    }

    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    ivec2 reservoirPosition = RTXDI_PixelPosToReservoirPos(pixel, int(runtimeParameters.activeCheckerboardField));
    if (!lt_is_active_reservoir_lane(reservoirPosition))
    {
        InitialCandidates_storeEmptyReservoir();
        return;
    }

    const RTXDI_Parameters params = lt_build_restir_di_parameters();
    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);

    RTXDI_DIReservoir currReservoir = RTXDI_EmptyDIReservoir();
    ReconnectionData currReconnectionData = ReconnectionData_init();

    for (uint sampleIdx = 0u; sampleIdx < uint(kSamplesPerPixel); ++sampleIdx)
    {
        PathState path;
        InitialCandidates_generatePath(path, pixel, sampleIdx, surface);
        InitialCandidates_tracePath(params, currReservoir, currReconnectionData, path);
    }

    InitialCandidates_finalizeSelectedReservoir(
        params.initialSamplingParams,
        pixel,
        surface,
        currReservoir,
        currReconnectionData
    );

    InitialCandidates_storeReservoir(currReservoir, currReconnectionData);
}

#endif
