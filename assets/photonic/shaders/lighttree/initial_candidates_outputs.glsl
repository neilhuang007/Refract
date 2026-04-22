#ifndef PHOTONICS_INITIAL_CANDIDATES_OUTPUTS_GLSL
#define PHOTONICS_INITIAL_CANDIDATES_OUTPUTS_GLSL

void InitialCandidates_storeReservoir(
    RTXDI_DIReservoir reservoir,
    ReservoirSplattingReconnectionData reconnectionData)
{
    float transportAux0;
    float transportAux1;
    scatter_pack_reconnection_fields(
        reconnectionData.firstHit.worldPos,
        reconnectionData.firstHit.viewDepth,
        reconnectionData.lightPdf,
        reconnectionData.time,
        reconnectionData.irradiance,
        reconnectionData.subPixel,
        reconnectionData.subPixelJacobian,
        reconnectionData.lensVertexJacobian,
        reconnectionData.secondaryPathJacobian,
        reconnectionData.firstHit.faceId,
        reconnectionData.pathLength,
        reconnectionData.firstBSDFComponentType,
        reconnectionData.secondBSDFComponentType,
        reconnectionData.transmissionEvent,
        reconnectionData.lightIsNEE,
        reconnectionData.lightIsDistant,
        transportAux0,
        transportAux1,
        reconnection0_frag_out,
        reconnection1_frag_out
    );

    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = PathReservoir_packMeta(reservoir);
}

void InitialCandidates_storeEmptyReservoir()
{
    InitialCandidates_storeReservoir(
        RTXDI_EmptyDIReservoir(),
        ReservoirSplattingReconnectionData_init()
    );
}

#endif
