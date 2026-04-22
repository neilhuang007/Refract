float scatter_pack_reconnection_proposal_pdf(float proposalPdf) {
    return max(proposalPdf, 0.0f);
}

float scatter_unpack_reconnection_proposal_pdf(float packedValue) {
    return max(packedValue, 0.0f);
}

#if !defined(PH_LIGHTTREE_RECONNECTION_PACK_ONLY)

vec2 rtxdi_unpack_sample_uv(uint packedUv);

float scatter_pack_unit_vector(vec3 direction) {
    float directionLengthSq = dot(direction, direction);
    vec3 n;
    vec2 p;

    n = directionLengthSq > 1e-12f
        ? direction * inversesqrt(directionLengthSq)
        : vec3(0.0f, 0.0f, 1.0f);
    p = n.xy / (abs(n.x) + abs(n.y) + abs(n.z));
    if (n.z < 0.0f) {
        p = (1.0f - abs(p.yx)) * sign(p.xy);
    }
    return scatter_pack_half2(clamp(p, vec2(-1.0f), vec2(1.0f)));
}

vec3 scatter_unpack_unit_vector(float packedValue) {
    vec2 p = scatter_unpack_half2(packedValue);
    vec3 n;

    n = vec3(p.x, p.y, 1.0f - abs(p.x) - abs(p.y));
    if (n.z < 0.0f) {
        n.xy = (1.0f - abs(n.yx)) * sign(n.xy);
    }
    return normalize(n);
}

vec3 scatter_pack_relative_second_pos(vec3 worldPos, vec3 secondPos) {
    return secondPos - worldPos;
}

vec3 scatter_unpack_relative_second_pos(vec3 worldPos, vec3 packedSecondPos) {
    return worldPos + packedSecondPos;
}

float scatter_clamp_reconnection_confidence(float confidence) {
    return clamp(confidence, 0.0f, PATH_RESERVOIR_CONFIDENCE_CAP);
}

float scatter_encode_reconnection_face(uint faceId) {
    return float(faceId & SCATTER_RECONNECTION_FACE_MASK);
}

uint scatter_decode_reconnection_face(float encodedFace) {
    return uint(clamp(round(encodedFace), 0.0f, float(SCATTER_RECONNECTION_FACE_MASK)));
}

#define scatter_reconnection_integrand(d) max((d).irradiance * (d).earlyThroughput, vec3(0.0f))

void scatter_pack_reconnection_fields(
    vec3 firstHitWorldPos,
    float firstHitViewDepth,
    float lightPdf,
    float time,
    vec3 irradiance,
    vec2 subPixel,
    float subPixelJacobian,
    float secondaryPathJacobian,
    uint firstHitFaceId,
    uint pathLength,
    uint firstBSDFComponentType,
    uint secondBSDFComponentType,
    bool transmissionEvent,
    bool lightIsNEE,
    bool lightIsDistant,
    out float transportAux0,
    out float transportAux1,
    out vec4 data0,
    out vec4 data1)
{
    uint packedMeta = 0u;
    uint packedFlags = 0u;
    uint transmissionBit = transmissionEvent ? 1u : 0u;

    if (lightIsNEE) {
        packedFlags |= SCATTER_RECONNECTION_FLAG_LIGHT_IS_NEE;
    }
    if (lightIsDistant) {
        packedFlags |= SCATTER_RECONNECTION_FLAG_LIGHT_IS_DISTANT;
    }

    packedMeta |= (firstHitFaceId & SCATTER_RECONNECTION_FACE_MASK) << SCATTER_RECONNECTION_FACE_SHIFT;
    packedMeta |= (packedFlags & SCATTER_RECONNECTION_FLAGS_MASK) << SCATTER_RECONNECTION_FLAGS_SHIFT;
    packedMeta |= (pathLength & SCATTER_RECONNECTION_PATH_LENGTH_MASK) << SCATTER_RECONNECTION_PATH_LENGTH_SHIFT;
    packedMeta |= (firstBSDFComponentType & SCATTER_RECONNECTION_FIRST_BSDF_MASK) << SCATTER_RECONNECTION_FIRST_BSDF_SHIFT;
    packedMeta |= (secondBSDFComponentType & SCATTER_RECONNECTION_SECOND_BSDF_MASK) << SCATTER_RECONNECTION_SECOND_BSDF_SHIFT;
    packedMeta |= transmissionBit << 16u;

    transportAux0 = scatter_pack_reconnection_proposal_pdf(lightPdf);
    transportAux1 = scatter_pack_half2(vec2(
        clamp(time, 0.0f, 1.0f),
        clamp(ph_luminance(max(irradiance, vec3(0.0f))), 0.0f, 65504.0f)
    ));

    data0 = vec4(firstHitWorldPos, firstHitViewDepth);
    data1 = vec4(
        scatter_pack_half2(vec2(
            clamp(lightPdf, 0.0f, 65504.0f),
            clamp(subPixelJacobian, 0.0f, 65504.0f)
        )),
        uintBitsToFloat(packedMeta),
        scatter_pack_half2(clamp(subPixel, vec2(0.0f), vec2(1.0f))),
        scatter_pack_half2(vec2(
            clamp(subPixelJacobian, 0.0f, 65504.0f),
            clamp(secondaryPathJacobian, 0.0f, 65504.0f)
        ))
    );
}

void scatter_unpack_reconnection(
    vec4 data0,
    vec4 data1,
    vec4 sampleData,
    float transportAux0,
    float transportAux1,
    out ReservoirSplattingReconnectionData d)
{
    uint packedMeta;
    uint packedFlags;
    vec2 packedTimeIrradiance;
    vec2 packedJacobians;

    packedMeta = floatBitsToUint(data1.y);
    packedFlags = (packedMeta >> SCATTER_RECONNECTION_FLAGS_SHIFT) & SCATTER_RECONNECTION_FLAGS_MASK;
    packedTimeIrradiance = scatter_unpack_half2(transportAux1);
    packedJacobians = scatter_unpack_half2(data1.w);
    d = ReservoirSplattingReconnectionData_init();

    d.firstHit.worldPos = data0.xyz;
    d.firstHit.viewDepth = data0.w;
    d.firstHit.faceId = (packedMeta >> SCATTER_RECONNECTION_FACE_SHIFT) & SCATTER_RECONNECTION_FACE_MASK;
    d.lightPdf = scatter_unpack_reconnection_proposal_pdf(transportAux0);
    d.lightIsNEE = (packedFlags & SCATTER_RECONNECTION_FLAG_LIGHT_IS_NEE) != 0u;
    d.lightIsDistant = (packedFlags & SCATTER_RECONNECTION_FLAG_LIGHT_IS_DISTANT) != 0u;
    d.pathLength = (packedMeta >> SCATTER_RECONNECTION_PATH_LENGTH_SHIFT) & SCATTER_RECONNECTION_PATH_LENGTH_MASK;
    d.firstBSDFComponentType = (packedMeta >> SCATTER_RECONNECTION_FIRST_BSDF_SHIFT) & SCATTER_RECONNECTION_FIRST_BSDF_MASK;
    d.secondBSDFComponentType = (packedMeta >> SCATTER_RECONNECTION_SECOND_BSDF_SHIFT) & SCATTER_RECONNECTION_SECOND_BSDF_MASK;
    d.transmissionEvent = ((packedMeta >> 16u) & 0x1u) != 0u;
    d.subPixel = clamp(scatter_unpack_half2(data1.z), vec2(0.0f), vec2(1.0f));
    d.lensSample = clamp(rtxdi_unpack_sample_uv(floatBitsToUint(sampleData.z)), vec2(0.0f), vec2(1.0f));
    d.time = clamp(packedTimeIrradiance.x, 0.0f, 1.0f);
    d.subPixelJacobian = max(packedJacobians.x, 1e-10f);
    d.secondaryPathJacobian = max(packedJacobians.y, 1e-10f);
    d.firstWi = normalize(world_camera_position - d.firstHit.worldPos);

    // DI never reconstructs a deeper path from this storage; keep the unused
    // secondary-hit payload at the constructor defaults.
    d.secondHit = ReservoirSplattingHitInfo_empty();
    d.secondHit.faceId = d.firstHit.faceId;
    d.secondWo = vec3(0.0f);
    d.irradiance = vec3(max(packedTimeIrradiance.y, 0.0f));
    d.earlyThroughput = vec3(1.0f);
}

void scatter_load_gather_intermediate_reconnection(ivec2 uv, out ScatterReconnectionData reconnection) {
    vec4 intermediateReservoirMeta;

    intermediateReservoirMeta = texelFetch(temporal_gather_intermediate_reservoir_meta, uv, 0);
    scatter_unpack_reconnection(
        texelFetch(temporal_gather_intermediate_reconnection0, uv, 0),
        texelFetch(temporal_gather_intermediate_reconnection1, uv, 0),
        texelFetch(temporal_gather_intermediate_reservoir_sample, uv, 0),
        intermediateReservoirMeta.y,
        intermediateReservoirMeta.z,
        reconnection
    );
}

void scatter_load_prev_reconnection(ivec2 uv, out ScatterReconnectionData reconnection) {
    vec4 prevReservoirMeta;

    prevReservoirMeta = texelFetch(prev_radiosity_reservoir_meta, uv, 0);
    scatter_unpack_reconnection(
        texelFetch(previous_frame_reconnection0, uv, 0),
        texelFetch(previous_frame_reconnection1, uv, 0),
        texelFetch(prev_radiosity_reservoir_samples, uv, 0),
        prevReservoirMeta.y,
        prevReservoirMeta.z,
        reconnection
    );
}

#endif
