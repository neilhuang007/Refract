#ifndef PHOTONICS_INITIAL_CANDIDATES_STAGE_GLSL
#define PHOTONICS_INITIAL_CANDIDATES_STAGE_GLSL

#include "/photonics/lighttree/restir_gi_initial_sampling_impl.glsl"
#include "/photonics/lighttree/initial_candidates_outputs.glsl"
#include "/photonics/lighttree/initial_candidates_reconnection.glsl"
#include "/photonics/lighttree/initial_candidates_path_state.glsl"
#include "/photonics/lighttree/initial_candidates_reservoir.glsl"

void InitialCandidates_handlePrimaryMiss(inout PathState path)
{
    path.reservoir = RTXDI_EmptyDIReservoir();
    path.reconnection = ReservoirSplattingReconnectionData_init();
    path.selectedLightSample = RAB_EmptyLightSample();
    lt_area_seed_domain_samples(path.reservoir, PathState_getPixel(path), 0u);
}

void InitialCandidates_handleHit(inout PathState path)
{
    const RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    path.reservoir = InitialCandidates_SampleLightsForSurface(
        path.sg,
        path.coherentRng,
        path.surface,
        restirDI.initialSamplingParams,
        path.selectedLightSample
    );

    if (!RTXDI_IsValidDIReservoir(path.reservoir))
    {
        path.reconnection = ReservoirSplattingReconnectionData_init();
        return;
    }

    path.reconnection = InitialCandidates_buildSelectedReconnection(
        path.surface,
        path.reservoir,
        path.selectedLightSample,
        PathState_getPixel(path)
    );
}

void InitialCandidates_tracePath(inout PathState path)
{
    if (!RAB_IsSurfaceValid(path.surface))
    {
        InitialCandidates_handlePrimaryMiss(path);
        return;
    }

    InitialCandidates_handleHit(path);
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

    RTXDI_DIReservoir currReservoir = RTXDI_EmptyDIReservoir();
    ReservoirSplattingReconnectionData currReconnectionData = ReservoirSplattingReconnectionData_init();
    for (uint sampleIdx = 0u; sampleIdx < uint(kSamplesPerPixel); ++sampleIdx)
    {
        PathState path;
        InitialCandidates_generatePath(path, pixel, sampleIdx);
        InitialCandidates_tracePath(path);
        InitialCandidates_addCandidateReservoir(currReservoir, currReconnectionData, path);
    }

    InitialCandidates_finalizeReservoir(currReservoir, currReconnectionData);
    InitialCandidates_storeReservoir(currReservoir, currReconnectionData);
}

#endif
