#ifndef PHOTONICS_INITIAL_CANDIDATES_RESERVOIR_GLSL
#define PHOTONICS_INITIAL_CANDIDATES_RESERVOIR_GLSL

float InitialCandidates_CandidateReservoir_totalWeight(RTXDI_DIReservoir candidateReservoir)
{
    return max(candidateReservoir.weightSum, 0.0f) * max(candidateReservoir.targetPdf, 0.0f);
}

bool InitialCandidates_PathReservoir_add(
    inout RTXDI_DIReservoir pathReservoir,
    float random,
    float sampleMIS,
    RTXDI_DIReservoir candidateReservoir)
{
    float weight = sampleMIS * InitialCandidates_CandidateReservoir_totalWeight(candidateReservoir);
    pathReservoir.weightSum += weight;
    pathReservoir.M = min(pathReservoir.M + 1.0f, SCATTER_RECONNECTION_CONFIDENCE_MAX);

    bool selected = (random * pathReservoir.weightSum < weight);
    if (selected) {
        pathReservoir.lightData = candidateReservoir.lightData;
        pathReservoir.uvData = candidateReservoir.uvData;
        pathReservoir.targetPdf = candidateReservoir.targetPdf;
        pathReservoir.packedVisibility = candidateReservoir.packedVisibility;
        pathReservoir.age = candidateReservoir.age;
        pathReservoir.spatialDistance = candidateReservoir.spatialDistance;
        pathReservoir.canonicalWeight = candidateReservoir.canonicalWeight;
        pathReservoir.transportAux0 = candidateReservoir.transportAux0;
        pathReservoir.transportAux1 = candidateReservoir.transportAux1;
        pathReservoir.pixelSampleUV = candidateReservoir.pixelSampleUV;
        pathReservoir.lensSampleUV = candidateReservoir.lensSampleUV;
        pathReservoir.pathSample = candidateReservoir.pathSample;
    }

    return selected;
}

bool InitialCandidates_addCandidateReservoir(
    inout RTXDI_DIReservoir currReservoir,
    inout ReservoirSplattingReconnectionData currReconnectionData,
    PathState path)
{
    bool isFirstSample = (PathState_getSampleIdx(path) == 0u);
    RTXDI_DIReservoir existingReservoir = isFirstSample ? RTXDI_EmptyDIReservoir() : currReservoir;
    bool selected = InitialCandidates_PathReservoir_add(
        existingReservoir,
        lt_next_random(path.rng),
        1.0f / float(kSamplesPerPixel),
        path.candidateReservoir
    );
    existingReservoir.M = RTXDI_IsValidDIReservoir(existingReservoir) ? 1.0f : 0.0f;

    currReservoir = existingReservoir;
    ReservoirSplattingReconnectionData existingReconnection = isFirstSample
        ? ReservoirSplattingReconnectionData_init()
        : currReconnectionData;
    currReconnectionData = selected ? path.selectedReconnection : existingReconnection;
    return selected;
}

void InitialCandidates_finalizeReservoir(
    inout RTXDI_DIReservoir currReservoir,
    inout ReservoirSplattingReconnectionData currReconnectionData)
{
    if (!RTXDI_IsValidDIReservoir(currReservoir)) {
        currReconnectionData = ReservoirSplattingReconnectionData_init();
    }
}

#endif
