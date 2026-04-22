#ifndef PHOTONICS_INITIAL_CANDIDATES_RESERVOIR_GLSL
#define PHOTONICS_INITIAL_CANDIDATES_RESERVOIR_GLSL

void InitialCandidates_addCandidateReservoir(
    inout RTXDI_DIReservoir currReservoir,
    inout ReservoirSplattingReconnectionData currReconnectionData,
    PathState path)
{
    const bool isFirstSample = (PathState_getSampleIdx(path) == (uint(kSamplesPerPixel) - 1u));
    RTXDI_DIReservoir existingReservoir = isFirstSample ? RTXDI_EmptyDIReservoir() : currReservoir;
    bool selected = PathReservoir_add(
        existingReservoir,
        lt_next_random(path.sg),
        1.0f / float(kSamplesPerPixel),
        path.reservoir
    );

    vec2 subPixel = selected
        ? path.reconnection.subPixel
        : PathReservoir_getSubPixel(existingReservoir, PathState_getPixel(path));
    PathReservoir_setSubPixel(existingReservoir, PathState_getPixel(path), subPixel);
    PathReservoir_setConfidence(existingReservoir, 1.0f);

    currReservoir = existingReservoir;

    ReservoirSplattingReconnectionData existingReconnection = isFirstSample
        ? ReservoirSplattingReconnectionData_init()
        : currReconnectionData;
    currReconnectionData = selected ? path.reconnection : existingReconnection;
}

#endif
