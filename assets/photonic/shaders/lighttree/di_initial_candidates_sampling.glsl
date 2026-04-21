#ifndef PHOTONICS_DI_INITIAL_CANDIDATES_SAMPLING_GLSL
#define PHOTONICS_DI_INITIAL_CANDIDATES_SAMPLING_GLSL

RTXDI_DIReservoir addCandidateReservoir(
    RAB_Surface surface,
    ivec2 pixel,
    RTXDI_Parameters restirDI,
    RTXDI_RuntimeParameters runtimeParameters,
    out ReservoirSplattingReconnectionData reconnectionData)
{
    const uint sampleIdx = 0u;
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

    RAB_LightSample selectedLightSample = RAB_EmptyLightSample();
    RTXDI_DIReservoir reservoir = RTXDI_SampleLightsForSurface(
        sg,
        coherentSg,
        surface,
        restirDI.initialSamplingParams,
        selectedLightSample
    );

    if (!RTXDI_IsValidDIReservoir(reservoir))
    {
        reconnectionData = ReservoirSplattingReconnectionData_init();
        return RTXDI_EmptyDIReservoir();
    }

    vec3 visibilityRgb = max(rtxdi_unpack_visibility(reservoir.packedVisibility), vec3(0.0f));
    reconnectionData = buildInitialSelectedReconnection(
        surface,
        reservoir,
        selectedLightSample,
        pixel,
        visibilityRgb
    );

    reservoir.M = 1.0f;
    return reservoir;
}

#endif
