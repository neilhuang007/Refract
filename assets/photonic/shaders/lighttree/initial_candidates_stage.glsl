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
    inout RAB_LightSample currSelectedLightSample,
    inout vec3 currSelectedIrradiance,
    inout vec3 currSelectedEarlyThroughput,
    inout PathState path)
{
    path.reservoir = RTXDI_EmptyDIReservoir();
    path.reconnection = ReconnectionData_init();
    path.selectedLightSample = RAB_EmptyLightSample();
    path.selectedIrradiance = vec3(0.0f);
    path.selectedEarlyThroughput = vec3(0.0f);
    InitialCandidates_addCandidateReservoir(
        currReservoir,
        currReconnectionData,
        currSelectedLightSample,
        currSelectedIrradiance,
        currSelectedEarlyThroughput,
        path
    );
}

void InitialCandidates_tracePath(
    const RTXDI_Parameters params,
    inout RTXDI_DIReservoir currReservoir,
    inout ReconnectionData currReconnectionData,
    inout RAB_LightSample currSelectedLightSample,
    inout vec3 currSelectedIrradiance,
    inout vec3 currSelectedEarlyThroughput,
    inout PathState path)
{
    if (!RAB_IsSurfaceValid(path.surface))
    {
        InitialCandidates_tracePrimaryMiss(
            currReservoir,
            currReconnectionData,
            currSelectedLightSample,
            currSelectedIrradiance,
            currSelectedEarlyThroughput,
            path
        );
        return;
    }

    path.reservoir = InitialCandidates_SampleLightsForSurface(
        path.sg,
        path.coherentRng,
        path.regirLookupRng,
        path.surface,
        params.initialSamplingParams,
        path.time,
        path.selectedLightSample,
        path.selectedIrradiance,
        path.selectedEarlyThroughput
    );

    path.reconnection = ReconnectionData_init();

    InitialCandidates_addCandidateReservoir(
        currReservoir,
        currReconnectionData,
        currSelectedLightSample,
        currSelectedIrradiance,
        currSelectedEarlyThroughput,
        path
    );
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

    // Opt #7: ReGIR cell occupancy short-circuit. When the active local-light
    // sampling mode is REGIR_RIS, the cell resolves on the first lookup, and
    // every slot in that cell stored a zero-weight proposal (build-time RIS
    // found no light with non-zero target pdf for the cell volume), the per-
    // path RIS loop below would only ever pick empty slots and produce an
    // empty reservoir. finalizeSelectedReservoir then resets that reservoir to
    // RTXDI_EmptyDIReservoir() before storing, so writing the empty reservoir
    // directly is bit-identical to running the full pipeline -- it just skips
    // kSamplesPerPixel cell relookups, kSamplesPerPixel * numLocalLightSamples
    // unsuccessful slot reads, and the path-state RNG initialization.
    //
    // Safety conditions:
    //   1. Surface must be valid -- otherwise the per-sample tracePath path
    //      already short-circuits to tracePrimaryMiss (writes empty), so we'd
    //      gain nothing and the ReGIR probe would dereference invalid worldPos.
    //   2. Active sampling mode must be REGIR_RIS. POWER_RIS / FAST_RANDOM /
    //      UNIFORM ignore ReGIR cell occupancy and could still pick lights.
    //   3. numLocalLightSamples > 0. With zero local-light samples there's no
    //      RIS work to skip and no reservoir for ReGIR cell occupancy to
    //      affect.
    //   4. numInfiniteLightSamples / numEnvironmentSamples / numBrdfSamples
    //      must all be zero. Those code paths run independently of the ReGIR
    //      cell and could still find non-empty samples even when the cell is
    //      empty -- skipping them would silently drop their contribution.
    //   5. ReGIR cell lookup must SUCCEED. On miss, the existing pipeline
    //      falls back to POWER_RIS or UNIFORM (see
    //      RTXDI_InitializeLocalLightSelectionContextReGIRRIS), so we keep the
    //      slow path in that case rather than incorrectly emitting empty.
    //
    // The probe RNG state is intentionally a separate copy: each per-path
    // regirLookupRng is re-initialized from (pixel, frameIndex) inside
    // InitialCandidates_generatePath, so advancing the probe state has no
    // effect on downstream samples that take the regular path.
    if (RAB_IsSurfaceValid(surface)
        && params.initialSamplingParams.localLightSamplingMode == uint(RTXDI_LOCAL_LIGHT_SAMPLING_REGIR_RIS)
        && params.initialSamplingParams.numLocalLightSamples > 0u
        && params.initialSamplingParams.numInfiniteLightSamples == 0u
        && params.initialSamplingParams.numEnvironmentSamples == 0u
        && params.initialSamplingParams.numBrdfSamples == 0u)
    {
        RTXDI_RandomSamplerState probeRng = RTXDI_InitReGIRLookupRandomSampler(
            uvec2(pixel),
            runtimeParameters.frameIndex);
        int probeCellIndex = -1;
        bool cellResolved = regir_resolve_cell(
            surface.worldPos,
            RAB_GetSurfaceNormal(surface),
            probeRng,
            probeCellIndex);
        if (cellResolved && probeCellIndex >= 0 && !regir_cell_has_any_light(probeCellIndex))
        {
            InitialCandidates_storeEmptyReservoir();
            return;
        }
    }

    RTXDI_DIReservoir currReservoir = RTXDI_EmptyDIReservoir();
    ReconnectionData currReconnectionData = ReconnectionData_init();
    RAB_LightSample currSelectedLightSample = RAB_EmptyLightSample();
    vec3 currSelectedIrradiance = vec3(0.0f);
    vec3 currSelectedEarlyThroughput = vec3(0.0f);

    for (uint sampleIdx = 0u; sampleIdx < uint(kSamplesPerPixel); ++sampleIdx)
    {
        PathState path;
        InitialCandidates_generatePath(path, pixel, sampleIdx, surface);
        InitialCandidates_tracePath(
            params,
            currReservoir,
            currReconnectionData,
            currSelectedLightSample,
            currSelectedIrradiance,
            currSelectedEarlyThroughput,
            path
        );
    }

    InitialCandidates_finalizeSelectedReservoir(
        params.initialSamplingParams,
        pixel,
        surface,
        currSelectedLightSample,
        currSelectedIrradiance,
        currSelectedEarlyThroughput,
        currReservoir,
        currReconnectionData
    );

    InitialCandidates_storeReservoir(currReservoir, currReconnectionData);
}

#endif
