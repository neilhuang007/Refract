float scatter_pack_reconnection_proposal_pdf(float proposalPdf) {
    return max(proposalPdf, 0.0f);
}

float scatter_unpack_reconnection_proposal_pdf(float packedValue) {
    return max(packedValue, 0.0f);
}

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

uint scatter_pack_reconnection_meta(ReconnectionData reconnectionData)
{
    uint packedFlags = 0u;
    uint packedMeta = 0u;

    if (reconnectionData.lightIsNEE) {
        packedFlags |= SCATTER_RECONNECTION_FLAG_LIGHT_IS_NEE;
    }
    if (reconnectionData.lightIsDistant) {
        packedFlags |= SCATTER_RECONNECTION_FLAG_LIGHT_IS_DISTANT;
    }
    if (dot(reconnectionData.firstWi, reconnectionData.firstWi) > 1e-12f) {
        packedFlags |= SCATTER_RECONNECTION_FLAG_FIRST_WI_VALID;
    }
    if (dot(reconnectionData.secondWo, reconnectionData.secondWo) > 1e-12f) {
        packedFlags |= SCATTER_RECONNECTION_FLAG_SECOND_WO_VALID;
    }

    packedMeta |= (reconnectionData.firstHit.faceId & SCATTER_RECONNECTION_FACE_MASK) << SCATTER_RECONNECTION_FACE_SHIFT;
    packedMeta |= (reconnectionData.secondHit.faceId & SCATTER_RECONNECTION_FACE_MASK) << SCATTER_RECONNECTION_SECOND_FACE_SHIFT;
    packedMeta |= (packedFlags & SCATTER_RECONNECTION_FLAGS_MASK) << SCATTER_RECONNECTION_FLAGS_SHIFT;
    packedMeta |= (reconnectionData.pathLength & SCATTER_RECONNECTION_PATH_LENGTH_MASK) << SCATTER_RECONNECTION_PATH_LENGTH_SHIFT;
    packedMeta |= (reconnectionData.firstBSDFComponentType & SCATTER_RECONNECTION_FIRST_BSDF_MASK) << SCATTER_RECONNECTION_FIRST_BSDF_SHIFT;
    packedMeta |= (reconnectionData.secondBSDFComponentType & SCATTER_RECONNECTION_SECOND_BSDF_MASK) << SCATTER_RECONNECTION_SECOND_BSDF_SHIFT;
    packedMeta |= (reconnectionData.transmissionEvent ? 1u : 0u) << SCATTER_RECONNECTION_TRANSMISSION_SHIFT;
    return packedMeta;
}

void scatter_unpack_reconnection_meta(
    uint packedMeta,
    inout ReconnectionData reconnectionData)
{
    uint packedFlags = (packedMeta >> SCATTER_RECONNECTION_FLAGS_SHIFT) & SCATTER_RECONNECTION_FLAGS_MASK;

    reconnectionData.firstHit.faceId = (packedMeta >> SCATTER_RECONNECTION_FACE_SHIFT) & SCATTER_RECONNECTION_FACE_MASK;
    reconnectionData.secondHit.faceId = (packedMeta >> SCATTER_RECONNECTION_SECOND_FACE_SHIFT) & SCATTER_RECONNECTION_FACE_MASK;
    reconnectionData.lightIsNEE = (packedFlags & SCATTER_RECONNECTION_FLAG_LIGHT_IS_NEE) != 0u;
    reconnectionData.lightIsDistant = (packedFlags & SCATTER_RECONNECTION_FLAG_LIGHT_IS_DISTANT) != 0u;
    reconnectionData.pathLength = (packedMeta >> SCATTER_RECONNECTION_PATH_LENGTH_SHIFT) & SCATTER_RECONNECTION_PATH_LENGTH_MASK;
    reconnectionData.firstBSDFComponentType = (packedMeta >> SCATTER_RECONNECTION_FIRST_BSDF_SHIFT) & SCATTER_RECONNECTION_FIRST_BSDF_MASK;
    reconnectionData.secondBSDFComponentType = (packedMeta >> SCATTER_RECONNECTION_SECOND_BSDF_SHIFT) & SCATTER_RECONNECTION_SECOND_BSDF_MASK;
    reconnectionData.transmissionEvent = ((packedMeta >> SCATTER_RECONNECTION_TRANSMISSION_SHIFT) & 0x1u) != 0u;

    if ((packedFlags & SCATTER_RECONNECTION_FLAG_FIRST_WI_VALID) == 0u) {
        reconnectionData.firstWi = vec3(0.0f);
    }
    if ((packedFlags & SCATTER_RECONNECTION_FLAG_SECOND_WO_VALID) == 0u) {
        reconnectionData.secondWo = vec3(0.0f);
    }
}

void scatter_pack_reconnection_data(
    ReconnectionData reconnectionData,
    out float transportAux0,
    out float transportAux1,
    out vec4 data0,
    out vec4 data1,
    out vec4 data2,
    out vec4 data3,
    out vec4 data4)
{
    transportAux0 = scatter_pack_half2(vec2(
        clamp(reconnectionData.lightPdf, 0.0f, 65504.0f),
        clamp(reconnectionData.subPixelJacobian, 0.0f, 65504.0f)
    ));
    transportAux1 = scatter_pack_half2(vec2(
        clamp(reconnectionData.lensVertexJacobian, 0.0f, 65504.0f),
        clamp(reconnectionData.secondaryPathJacobian, 0.0f, 65504.0f)
    ));

    data0 = vec4(reconnectionData.firstHit.worldPos, transportAux0);
    data1 = vec4(reconnectionData.secondHit.worldPos, transportAux1);
    data2 = vec4(
        reconnectionData.irradiance,
        uintBitsToFloat(scatter_pack_reconnection_meta(reconnectionData))
    );
    data3 = vec4(reconnectionData.earlyThroughput, reconnectionData.time);
    data4 = vec4(
        scatter_pack_half2(clamp(reconnectionData.subPixel, vec2(0.0f), vec2(1.0f))),
        scatter_pack_half2(clamp(reconnectionData.lensSample, vec2(0.0f), vec2(1.0f))),
        scatter_pack_unit_vector(reconnectionData.firstWi),
        scatter_pack_unit_vector(reconnectionData.secondWo)
    );
}

#define scatter_pack_reconnection_fields(reconnectionData, transportAux0, transportAux1, data0, data1, data2, data3, data4) \
    scatter_pack_reconnection_data(reconnectionData, transportAux0, transportAux1, data0, data1, data2, data3, data4)

#if !defined(PH_LIGHTTREE_RECONNECTION_PACK_ONLY)

void scatter_unpack_reconnection(
    vec4 data0,
    vec4 data1,
    vec4 data2,
    vec4 data3,
    vec4 data4,
    float transportAux0,
    float transportAux1,
    out ReconnectionData reconnectionData)
{
    vec2 packedLightPdfSubPixelJacobian;
    vec2 packedLensJacobians;
    bool hasPackedTransport;
    float packedTransportAux0;
    float packedTransportAux1;

    packedTransportAux0 = (data0.w != 0.0f || data1.w != 0.0f) ? data0.w : transportAux0;
    packedTransportAux1 = (data0.w != 0.0f || data1.w != 0.0f) ? data1.w : transportAux1;
    packedLightPdfSubPixelJacobian = scatter_unpack_half2(packedTransportAux0);
    packedLensJacobians = scatter_unpack_half2(packedTransportAux1);
    hasPackedTransport = packedTransportAux0 != 0.0f || packedTransportAux1 != 0.0f;
    reconnectionData = ReconnectionData_init();

    reconnectionData.firstHit.worldPos = data0.xyz;
    reconnectionData.firstHit.viewDepth = 0.0f;
    reconnectionData.secondHit.worldPos = data1.xyz;
    reconnectionData.secondHit.viewDepth = 0.0f;
    reconnectionData.irradiance = data2.xyz;
    reconnectionData.earlyThroughput = data3.xyz;
    reconnectionData.time = clamp(data3.w, 0.0f, 1.0f);
    reconnectionData.subPixel = clamp(scatter_unpack_half2(data4.x), vec2(0.0f), vec2(1.0f));
    reconnectionData.lensSample = clamp(scatter_unpack_half2(data4.y), vec2(0.0f), vec2(1.0f));
    reconnectionData.firstWi = scatter_unpack_unit_vector(data4.z);
    reconnectionData.secondWo = scatter_unpack_unit_vector(data4.w);
    if (hasPackedTransport)
    {
        reconnectionData.lightPdf = scatter_unpack_reconnection_proposal_pdf(max(packedLightPdfSubPixelJacobian.x, 0.0f));
        reconnectionData.subPixelJacobian = max(packedLightPdfSubPixelJacobian.y, 1e-10f);
        reconnectionData.lensVertexJacobian = max(packedLensJacobians.x, 1e-10f);
        reconnectionData.secondaryPathJacobian = max(packedLensJacobians.y, 1e-10f);
    }
    scatter_unpack_reconnection_meta(floatBitsToUint(data2.w), reconnectionData);
}

void scatter_load_gather_intermediate_reconnection(ivec2 uv, out ScatterReconnectionData reconnection) {
    vec4 intermediateReservoirMeta;

    intermediateReservoirMeta = texelFetch(temporal_gather_intermediate_reservoir_meta, uv, 0);
    scatter_unpack_reconnection(
        texelFetch(temporal_gather_intermediate_reconnection0, uv, 0),
        texelFetch(temporal_gather_intermediate_reconnection1, uv, 0),
        texelFetch(temporal_gather_intermediate_reconnection2, uv, 0),
        texelFetch(temporal_gather_intermediate_reconnection3, uv, 0),
        texelFetch(temporal_gather_intermediate_reconnection4, uv, 0),
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
        texelFetch(previous_frame_reconnection2, uv, 0),
        texelFetch(previous_frame_reconnection3, uv, 0),
        texelFetch(previous_frame_reconnection4, uv, 0),
        prevReservoirMeta.y,
        prevReservoirMeta.z,
        reconnection
    );
}

#else

void scatter_pack_reconnection_fields_legacy_signature(
    vec3 firstHitWorldPos,
    float firstHitViewDepth,
    float lightPdf,
    float time,
    vec3 irradiance,
    vec2 subPixel,
    float subPixelJacobian,
    float lensVertexJacobian,
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
    out vec4 data1,
    out vec4 data2,
    out vec4 data3,
    out vec4 data4)
{
    ReconnectionData reconnectionData = ReconnectionData_init();
    reconnectionData.firstHit.worldPos = firstHitWorldPos;
    reconnectionData.firstHit.viewDepth = firstHitViewDepth;
    reconnectionData.firstHit.faceId = firstHitFaceId;
    reconnectionData.secondHit.faceId = firstHitFaceId;
    reconnectionData.lightPdf = lightPdf;
    reconnectionData.time = time;
    reconnectionData.irradiance = irradiance;
    reconnectionData.subPixel = subPixel;
    reconnectionData.subPixelJacobian = subPixelJacobian;
    reconnectionData.lensVertexJacobian = lensVertexJacobian;
    reconnectionData.secondaryPathJacobian = secondaryPathJacobian;
    reconnectionData.pathLength = pathLength;
    reconnectionData.firstBSDFComponentType = firstBSDFComponentType;
    reconnectionData.secondBSDFComponentType = secondBSDFComponentType;
    reconnectionData.transmissionEvent = transmissionEvent;
    reconnectionData.lightIsNEE = lightIsNEE;
    reconnectionData.lightIsDistant = lightIsDistant;
    scatter_pack_reconnection_data(
        reconnectionData,
        transportAux0,
        transportAux1,
        data0,
        data1,
        data2,
        data3,
        data4
    );
}

#endif
