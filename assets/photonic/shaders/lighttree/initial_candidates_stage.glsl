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
}

void InitialCandidates_handleHit(inout PathState path)
{
    const RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    path.reservoir = RTXDI_SampleLightsForSurface(
        path.rng,
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

    vec3 visibility = max(rtxdi_unpack_visibility(path.reservoir.packedVisibility), vec3(0.0f));
    path.reconnection = InitialCandidates_buildSelectedReconnection(
        path.surface,
        path.reservoir,
        path.selectedLightSample,
        PathState_getPixel(path),
        visibility
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
    for (int sampleIdx = kSamplesPerPixel - 1; sampleIdx >= 0; --sampleIdx)
    {
        PathState path;
        InitialCandidates_generatePath(path, pixel, uint(sampleIdx));
        InitialCandidates_tracePath(path);
        InitialCandidates_addCandidateReservoir(currReservoir, currReconnectionData, path);
    }

    InitialCandidates_finalizeReservoir(currReservoir, currReconnectionData);
    InitialCandidates_storeReservoir(currReservoir, currReconnectionData);
}

#endif
