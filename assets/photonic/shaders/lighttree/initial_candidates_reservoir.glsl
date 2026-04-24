#ifndef PHOTONICS_INITIAL_CANDIDATES_RESERVOIR_GLSL
#define PHOTONICS_INITIAL_CANDIDATES_RESERVOIR_GLSL

void InitialCandidates_addCandidateReservoir(
    inout RTXDI_DIReservoir currReservoir,
    inout ReservoirSplattingReconnectionData currReconnectionData,
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
    ReservoirSplattingReconnectionData selectedReconnection = selected && RTXDI_IsValidDIReservoir(path.reservoir)
        ? InitialCandidates_buildSelectedReconnection(
            path.surface,
            path.reservoir,
            path.selectedLightSample,
            pixel,
            path.time,
            path.selectedIrradiance,
            path.selectedEarlyThroughput
        )
        : path.reconnection;

    vec2 subPixel = selected
        ? selectedReconnection.subPixel
        : PathReservoir_getSubPixel(existingReservoir, pixel);
    PathReservoir_setSubPixel(existingReservoir, pixel, subPixel);
    PathReservoir_setConfidence(existingReservoir, 1.0f);

    currReservoir = existingReservoir;

    ReservoirSplattingReconnectionData existingReconnection = isFirstSample
        ? ReservoirSplattingReconnectionData_init()
        : currReconnectionData;
    currReconnectionData = selected ? selectedReconnection : existingReconnection;
}

#endif
