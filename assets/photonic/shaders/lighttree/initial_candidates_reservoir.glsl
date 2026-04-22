#ifndef PHOTONICS_INITIAL_CANDIDATES_RESERVOIR_GLSL
#define PHOTONICS_INITIAL_CANDIDATES_RESERVOIR_GLSL

bool InitialCandidates_addCandidateReservoir(
    inout RTXDI_DIReservoir currReservoir,
    inout ReservoirSplattingReconnectionData currReconnectionData,
    PathState path)
{
    bool isFirstSample = (PathState_getSampleIdx(path) == uint(kSamplesPerPixel - 1));
    RTXDI_DIReservoir existingReservoir = isFirstSample ? RTXDI_EmptyDIReservoir() : currReservoir;
    bool selected = PathReservoir_add(
        existingReservoir,
        lt_next_random(path.rng),
        1.0f / float(kSamplesPerPixel),
        path.reservoir
    );

    currReservoir = existingReservoir;
    ReservoirSplattingReconnectionData existingReconnection = isFirstSample
        ? ReservoirSplattingReconnectionData_init()
        : currReconnectionData;
    currReconnectionData = selected ? path.reconnection : existingReconnection;
    return selected;
}

void InitialCandidates_finalizeReservoir(
    inout RTXDI_DIReservoir currReservoir,
    inout ReservoirSplattingReconnectionData currReconnectionData)
{
    currReservoir.M = max(currReservoir.M, 1.0f);
    if (!RTXDI_IsValidDIReservoir(currReservoir)) {
        currReconnectionData = ReservoirSplattingReconnectionData_init();
    }
}

#endif
