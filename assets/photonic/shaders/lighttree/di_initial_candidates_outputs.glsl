#ifndef PHOTONICS_DI_INITIAL_CANDIDATES_OUTPUTS_GLSL
#define PHOTONICS_DI_INITIAL_CANDIDATES_OUTPUTS_GLSL

void InitialCandidates_storeReservoir(
    RTXDI_DIReservoir reservoir,
    ReservoirSplattingReconnectionData reconnectionData)
{
    float transportAux0;
    float transportAux1;
    float packedMeta;
    uint packedMetaUint;
    uint packedFlags;
    uint transmissionBit;
    vec2 packedTimeIrradiance;
    vec2 packedLightPdfAndSubPixelJacobian;
    vec2 packedJacobians;

    packedMetaUint = 0u;
    packedFlags = 0u;
    transmissionBit = 0u;

    if (reconnectionData.lightIsNEE) {
        packedFlags |= SCATTER_RECONNECTION_FLAG_LIGHT_IS_NEE;
    }
    if (reconnectionData.lightIsDistant) {
        packedFlags |= SCATTER_RECONNECTION_FLAG_LIGHT_IS_DISTANT;
    }
    if (reconnectionData.transmissionEvent) {
        transmissionBit = 1u;
    }

    packedMetaUint |= (reconnectionData.firstHit.faceId & SCATTER_RECONNECTION_FACE_MASK) << SCATTER_RECONNECTION_FACE_SHIFT;
    packedMetaUint |= (packedFlags & SCATTER_RECONNECTION_FLAGS_MASK) << SCATTER_RECONNECTION_FLAGS_SHIFT;
    packedMetaUint |= (reconnectionData.pathLength & SCATTER_RECONNECTION_PATH_LENGTH_MASK) << SCATTER_RECONNECTION_PATH_LENGTH_SHIFT;
    packedMetaUint |= (reconnectionData.firstBSDFComponentType & SCATTER_RECONNECTION_FIRST_BSDF_MASK) << SCATTER_RECONNECTION_FIRST_BSDF_SHIFT;
    packedMetaUint |= (reconnectionData.secondBSDFComponentType & SCATTER_RECONNECTION_SECOND_BSDF_MASK) << SCATTER_RECONNECTION_SECOND_BSDF_SHIFT;
    packedMetaUint |= transmissionBit << 16u;

    transportAux0 = scatter_pack_reconnection_proposal_pdf(reconnectionData.lightPdf);
    packedTimeIrradiance = vec2(
        clamp(reconnectionData.time, 0.0f, 1.0f),
        clamp(ph_luminance(max(reconnectionData.irradiance, vec3(0.0f))), 0.0f, 65504.0f)
    );
    transportAux1 = scatter_pack_half2(packedTimeIrradiance);

    reconnection0_frag_out = vec4(reconnectionData.firstHit.worldPos, reconnectionData.firstHit.viewDepth);
    packedMeta = uintBitsToFloat(packedMetaUint);
    packedLightPdfAndSubPixelJacobian = vec2(
        clamp(reconnectionData.lightPdf, 0.0f, 65504.0f),
        clamp(reconnectionData.subPixelJacobian, 0.0f, 65504.0f)
    );
    packedJacobians = vec2(
        clamp(reconnectionData.subPixelJacobian, 0.0f, 65504.0f),
        clamp(reconnectionData.secondaryPathJacobian, 0.0f, 65504.0f)
    );

    reconnection1_frag_out.x = scatter_pack_half2(packedLightPdfAndSubPixelJacobian);
    reconnection1_frag_out.y = packedMeta;
    reconnection1_frag_out.z = scatter_pack_half2(clamp(reconnectionData.subPixel, vec2(0.0f), vec2(1.0f)));
    reconnection1_frag_out.w = scatter_pack_half2(packedJacobians);

    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta_with_transport(reservoir, transportAux0, transportAux1);
}

void InitialCandidates_storeEmptyReservoir()
{
    InitialCandidates_storeReservoir(
        RTXDI_EmptyDIReservoir(),
        ReservoirSplattingReconnectionData_init()
    );
}

#endif

