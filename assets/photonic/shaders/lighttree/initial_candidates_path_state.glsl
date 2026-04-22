#ifndef PHOTONICS_INITIAL_CANDIDATES_PATH_STATE_GLSL
#define PHOTONICS_INITIAL_CANDIDATES_PATH_STATE_GLSL

const int kSamplesPerPixel = (PH_LIGHTTREE_INITIAL_SAMPLES > 0 ? PH_LIGHTTREE_INITIAL_SAMPLES : 1);

struct PathState
{
    ivec2 pixel;
    uint sampleIdx;
    uint pathID;
    RAB_Surface surface;
    RTXDI_RandomSamplerState rng;
    RTXDI_RandomSamplerState coherentRng;
    RTXDI_DIReservoir candidateReservoir;
    ReservoirSplattingReconnectionData selectedReconnection;
    RAB_LightSample selectedLightSample;
};

uint PathState_getSampleIdx(PathState path)
{
    return path.sampleIdx;
}

ivec2 PathState_getPixel(PathState path)
{
    return path.pixel;
}

uint InitialCandidates_makePathID(ivec2 pixel, uint sampleIdx)
{
    return uint(pixel.x) | (uint(pixel.y) << 12u) | (sampleIdx << 24u);
}

void InitialCandidates_generatePath(out PathState path, ivec2 pixel, uint sampleIdx)
{
    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    path.pixel = pixel;
    path.sampleIdx = sampleIdx;
    path.pathID = InitialCandidates_makePathID(pixel, sampleIdx);
    path.surface = RAB_GetGBufferSurface(pixel, false);
    path.rng = RTXDI_InitRandomSampler(
        uvec2(pixel),
        runtimeParameters.frameIndex,
        RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED + path.pathID
    );
    path.coherentRng = RTXDI_InitRandomSampler(
        uvec2(pixel / RTXDI_TILE_SIZE_IN_PIXELS),
        sampleIdx,
        RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED
    );
    path.candidateReservoir = RTXDI_EmptyDIReservoir();
    path.selectedReconnection = ReservoirSplattingReconnectionData_init();
    path.selectedLightSample = RAB_EmptyLightSample();
}

#endif
