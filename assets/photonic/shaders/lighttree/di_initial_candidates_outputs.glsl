#ifndef PHOTONICS_DI_INITIAL_CANDIDATES_OUTPUTS_GLSL
#define PHOTONICS_DI_INITIAL_CANDIDATES_OUTPUTS_GLSL

void InitialCandidates_storeReservoir(
    RTXDI_DIReservoir reservoir,
    ReservoirSplattingReconnectionData reconnectionData)
{
    float transportAux0;
    float transportAux1;
    scatter_pack_reconnection(
        reconnectionData,
        transportAux0,
        transportAux1,
        reconnection0_frag_out,
        reconnection1_frag_out
    );

    reservoir.transportAux0 = transportAux0;
    reservoir.transportAux1 = transportAux1;
    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(reservoir);
}

void InitialCandidates_storeEmptyReservoir()
{
    InitialCandidates_storeReservoir(
        RTXDI_EmptyDIReservoir(),
        ReservoirSplattingReconnectionData_init()
    );
}

#endif

