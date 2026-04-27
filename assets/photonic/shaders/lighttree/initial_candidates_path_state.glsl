#ifndef PHOTONICS_INITIAL_CANDIDATES_PATH_STATE_GLSL
#define PHOTONICS_INITIAL_CANDIDATES_PATH_STATE_GLSL

const int kSamplesPerPixel = (PH_LIGHTTREE_INITIAL_SAMPLES > 0 ? PH_LIGHTTREE_INITIAL_SAMPLES : 1);

struct PathState
{
    uint id;
    float time;
    RAB_Surface surface;
    RTXDI_RandomSamplerState sg;
    RTXDI_RandomSamplerState coherentRng;
    RTXDI_DIReservoir reservoir;
    ReconnectionData reconnection;
    RAB_LightSample selectedLightSample;
    vec3 selectedIrradiance;
    vec3 selectedEarlyThroughput;
};

uint PathState_getSampleIdx(PathState path)
{
    return path.id >> 24u;
}

ivec2 PathState_getPixel(PathState path)
{
    return ivec2(int(path.id & 0xfffu), int((path.id >> 12u) & 0xfffu));
}

uint InitialCandidates_makePathID(ivec2 pixel, uint sampleIdx)
{
    return uint(pixel.x) | (uint(pixel.y) << 12u) | (sampleIdx << 24u);
}

void InitialCandidates_generatePath(out PathState path, ivec2 pixel, uint sampleIdx, RAB_Surface surface)
{
    const RTXDI_RuntimeParameters runtimeParameters = lt_build_runtime_parameters();
    path.id = InitialCandidates_makePathID(pixel, sampleIdx);
    path.surface = surface;
    path.sg = RTXDI_InitRandomSampler(
        uvec2(pixel),
        runtimeParameters.frameIndex,
        RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED + path.id
    );
    path.coherentRng = RTXDI_InitRandomSampler(
        uvec2(pixel / RTXDI_TILE_SIZE_IN_PIXELS),
        sampleIdx,
        RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED
    );
    path.time = lt_next_random(path.sg) * ph_reservoir_splatting_shutter_speed;
    path.reservoir = RTXDI_EmptyDIReservoir();
    path.reconnection = ReconnectionData_init();
    path.selectedLightSample = RAB_EmptyLightSample();
    path.selectedIrradiance = vec3(0.0f);
    path.selectedEarlyThroughput = vec3(0.0f);
}

#endif
