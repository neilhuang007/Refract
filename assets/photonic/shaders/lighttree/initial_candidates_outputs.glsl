#ifndef PHOTONICS_INITIAL_CANDIDATES_OUTPUTS_GLSL
#define PHOTONICS_INITIAL_CANDIDATES_OUTPUTS_GLSL

void InitialCandidates_storeReservoir(
    RTXDI_DIReservoir reservoir,
    ReservoirSplattingReconnectionData reconnectionData)
{
    scatter_pack_reconnection_fields(
        reconnectionData,
        reservoir.transportAux0,
        reservoir.transportAux1,
        reconnection0_frag_out,
        reconnection1_frag_out,
        reconnection2_frag_out,
        reconnection3_frag_out,
        reconnection4_frag_out
    );

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
