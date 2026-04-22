#ifndef PHOTONICS_DI_INITIAL_CANDIDATES_SAMPLING_GLSL
#define PHOTONICS_DI_INITIAL_CANDIDATES_SAMPLING_GLSL

void addCandidateReservoir(
    ivec2 pixel,
    RAB_Surface surface,
    inout RTXDI_DIReservoir currReservoir,
    inout ReservoirSplattingReconnectionData currReconnectionData)
{
    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    const RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    const uint sampleIdx = 0u;
    const float sampleMIS = 1.0f;

    RTXDI_RandomSamplerState sg = RTXDI_InitRandomSampler(
        uvec2(pixel),
        runtimeParameters.frameIndex,
        RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED + sampleIdx * 0x9e3779b9u
    );
    RTXDI_RandomSamplerState coherentSg = RTXDI_InitRandomSampler(
        uvec2(pixel / RTXDI_TILE_SIZE_IN_PIXELS),
        sampleIdx,
        RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED
    );

    currReservoir = RTXDI_EmptyDIReservoir();
    currReconnectionData = ReservoirSplattingReconnectionData_init();

    RAB_LightSample selectedLightSample = RAB_EmptyLightSample();
    RTXDI_DIReservoir candidateReservoir = InitialCandidates_SampleLightsForSurface(
        sg,
        coherentSg,
        surface,
        restirDI.initialSamplingParams,
        selectedLightSample
    );

    if (!RTXDI_IsValidDIReservoir(candidateReservoir))
    {
        return;
    }

    ReservoirSplattingReconnectionData selectedReconnection = InitialCandidates_buildSelectedReconnection(
        surface,
        candidateReservoir,
        selectedLightSample,
        pixel
    );
    bool selected = PathReservoir_add(currReservoir, lt_next_random(sg), sampleMIS, candidateReservoir);
    if (selected)
    {
        PathReservoir_setSubPixel(currReservoir, pixel, selectedReconnection.subPixel);
        currReconnectionData = selectedReconnection;
    }
    PathReservoir_setConfidence(currReservoir, 1.0f);
}

#endif
