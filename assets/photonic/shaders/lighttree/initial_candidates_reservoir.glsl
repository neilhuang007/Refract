#ifndef PHOTONICS_INITIAL_CANDIDATES_RESERVOIR_GLSL
#define PHOTONICS_INITIAL_CANDIDATES_RESERVOIR_GLSL

bool InitialCandidates_addCandidateReservoir(
    inout RTXDI_DIReservoir currReservoir,
    inout ReservoirSplattingReconnectionData currReconnectionData,
    PathState path)
{
    bool isFirstSample = (PathState_getSampleIdx(path) == (uint(kSamplesPerPixel) - 1u));
    RTXDI_DIReservoir existingReservoir = isFirstSample ? RTXDI_EmptyDIReservoir() : currReservoir;
    bool selected = PathReservoir_add(
        existingReservoir,
        lt_next_random(path.sg),
        1.0f / float(kSamplesPerPixel),
        path.reservoir
    );
    if (selected) {
        PathReservoir_setSubPixel(existingReservoir, PathState_getPixel(path), path.subPixel);
    }
    PathReservoir_setConfidence(existingReservoir, 1.0f);

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
    if (!RTXDI_IsValidDIReservoir(currReservoir)) {
        currReconnectionData = ReservoirSplattingReconnectionData_init();
        lt_area_seed_domain_samples(currReservoir, lt_fragment_pixel_pos(), currReservoir.pathSample);
        PathReservoir_setConfidence(currReservoir, 1.0f);
    }
}

#endif
