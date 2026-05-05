#ifndef PHOTONICS_INITIAL_CANDIDATES_RESERVOIR_GLSL
#define PHOTONICS_INITIAL_CANDIDATES_RESERVOIR_GLSL

void InitialCandidates_addCandidateReservoir(
    inout RTXDI_DIReservoir currReservoir,
    inout ReconnectionData currReconnectionData,
    inout RAB_LightSample currSelectedLightSample,
    inout vec3 currSelectedIrradiance,
    inout vec3 currSelectedEarlyThroughput,
    PathState path)
{
    const bool isFirstSample = (PathState_getSampleIdx(path) == 0u);
    RTXDI_DIReservoir existingReservoir = isFirstSample ? RTXDI_EmptyDIReservoir() : currReservoir;
    bool selected = PathReservoir_add(
        existingReservoir,
        lt_next_random(path.sg),
        1.0f / float(kSamplesPerPixel),
        path.reservoir
    );

    ivec2 pixel = PathState_getPixel(path);
    if (selected) {
        PathReservoir_setSubPixel(existingReservoir, pixel, PathReservoir_getSubPixel(path.reservoir, pixel));
        currSelectedLightSample = path.selectedLightSample;
        currSelectedIrradiance = path.selectedIrradiance;
        currSelectedEarlyThroughput = path.selectedEarlyThroughput;
    }
    PathReservoir_setConfidence(existingReservoir, 1.0f);

    currReservoir = existingReservoir;

    ReconnectionData existingReconnection = isFirstSample
        ? ReconnectionData_init()
        : currReconnectionData;
    currReconnectionData = selected ? path.reconnection : existingReconnection;
}

#endif
