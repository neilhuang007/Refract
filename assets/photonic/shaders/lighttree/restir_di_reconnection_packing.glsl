float scatter_pack_reconnection_proposal_pdf(float proposalPdf) {
    return proposalPdf;
}

float scatter_unpack_reconnection_proposal_pdf(float packedValue) {
    return packedValue;
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

#define scatter_reconnection_integrand(d) max((d).irradiance * (d).earlyThroughput, vec3(0.0f))

uint scatter_pack_reconnection_faces(ReconnectionData reconnectionData)
{
    return (reconnectionData.firstHit.faceId & 0xFFFFu)
        | ((reconnectionData.secondHit.faceId & 0xFFFFu) << 16u);
}

void scatter_unpack_reconnection_faces(uint packedFaces, inout ReconnectionData reconnectionData)
{
    reconnectionData.firstHit.faceId = packedFaces & 0xFFFFu;
    reconnectionData.secondHit.faceId = (packedFaces >> 16u) & 0xFFFFu;
}

uint scatter_pack_reconnection_identity(ReconnectionData reconnectionData)
{
    // The texture-backed DI path stores only the 5 RGBA payloads below.
    // Unlike the Falcor structured-buffer layout, there is no persisted aux
    // lane for hit/material identity, so material IDs are reconstructed from
    // the surface/light state when needed.
    return 0u;
}

void scatter_unpack_reconnection_identity(
    uint packedIdentity,
    inout ReconnectionData reconnectionData)
{
    reconnectionData.firstHit.materialId = 0u;
    reconnectionData.secondHit.materialId = 0u;
}

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

    packedMeta |= (packedFlags & SCATTER_RECONNECTION_FLAGS_MASK) << SCATTER_RECONNECTION_FLAGS_SHIFT;
    packedMeta |= (reconnectionData.pathLength & SCATTER_RECONNECTION_PATH_LENGTH_MASK) << SCATTER_RECONNECTION_PATH_LENGTH_SHIFT;
    packedMeta |= (reconnectionData.firstBSDFComponentType & SCATTER_RECONNECTION_FIRST_BSDF_MASK) << SCATTER_RECONNECTION_FIRST_BSDF_SHIFT;
    packedMeta |= (reconnectionData.secondBSDFComponentType & SCATTER_RECONNECTION_SECOND_BSDF_MASK) << SCATTER_RECONNECTION_SECOND_BSDF_SHIFT;
    packedMeta |= (reconnectionData.transmissionEvent ? 1u : 0u) << SCATTER_RECONNECTION_TRANSMISSION_SHIFT;
    packedMeta |= scatter_pack_reconnection_time_bits(reconnectionData.time) << SCATTER_RECONNECTION_TIME_SHIFT;
    packedMeta |= (reconnectionData.firstHit.faceId & SCATTER_RECONNECTION_FACE_MASK) << SCATTER_RECONNECTION_FIRST_FACE_SHIFT;
    packedMeta |= (reconnectionData.secondHit.faceId & SCATTER_RECONNECTION_FACE_MASK) << SCATTER_RECONNECTION_SECOND_FACE_SHIFT;
    return packedMeta;
}

void scatter_unpack_reconnection_meta(
    uint packedMeta,
    inout ReconnectionData reconnectionData)
{
    uint packedFlags = (packedMeta >> SCATTER_RECONNECTION_FLAGS_SHIFT) & SCATTER_RECONNECTION_FLAGS_MASK;

    reconnectionData.lightIsNEE = (packedFlags & SCATTER_RECONNECTION_FLAG_LIGHT_IS_NEE) != 0u;
    reconnectionData.lightIsDistant = (packedFlags & SCATTER_RECONNECTION_FLAG_LIGHT_IS_DISTANT) != 0u;
    reconnectionData.pathLength = (packedMeta >> SCATTER_RECONNECTION_PATH_LENGTH_SHIFT) & SCATTER_RECONNECTION_PATH_LENGTH_MASK;
    reconnectionData.firstBSDFComponentType = (packedMeta >> SCATTER_RECONNECTION_FIRST_BSDF_SHIFT) & SCATTER_RECONNECTION_FIRST_BSDF_MASK;
    reconnectionData.secondBSDFComponentType = (packedMeta >> SCATTER_RECONNECTION_SECOND_BSDF_SHIFT) & SCATTER_RECONNECTION_SECOND_BSDF_MASK;
    reconnectionData.transmissionEvent = ((packedMeta >> SCATTER_RECONNECTION_TRANSMISSION_SHIFT) & 0x1u) != 0u;
    reconnectionData.time = scatter_unpack_reconnection_time_bits(packedMeta);
    reconnectionData.firstHit.faceId = (packedMeta >> SCATTER_RECONNECTION_FIRST_FACE_SHIFT) & SCATTER_RECONNECTION_FACE_MASK;
    reconnectionData.secondHit.faceId = (packedMeta >> SCATTER_RECONNECTION_SECOND_FACE_SHIFT) & SCATTER_RECONNECTION_FACE_MASK;

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
    transportAux0 = 0.0f;
    transportAux1 = 0.0f;

    data0 = vec4(
        reconnectionData.firstHit.worldPos,
        scatter_pack_half2(vec2(
            reconnectionData.firstHit.viewDepth,
            reconnectionData.secondHit.viewDepth
        ))
    );
    data1 = vec4(
        reconnectionData.secondHit.worldPos,
        scatter_pack_half2(vec2(
            reconnectionData.lightPdf,
            reconnectionData.subPixelJacobian
        ))
    );
    data2 = vec4(
        reconnectionData.irradiance,
        uintBitsToFloat(scatter_pack_reconnection_meta(reconnectionData))
    );
    data3 = vec4(
        reconnectionData.earlyThroughput,
        scatter_pack_half2(vec2(
            reconnectionData.lensVertexJacobian,
            reconnectionData.secondaryPathJacobian
        ))
    );
    data4 = vec4(
        scatter_pack_half2(reconnectionData.subPixel),
        scatter_pack_half2(reconnectionData.lensSample),
        scatter_pack_unit_vector(reconnectionData.firstWi),
        scatter_pack_unit_vector(reconnectionData.secondWo)
    );
}

#define scatter_pack_reconnection_fields(reconnectionData, transportAux0, transportAux1, data0, data1, data2, data3, data4) \
    scatter_pack_reconnection_data(reconnectionData, transportAux0, transportAux1, data0, data1, data2, data3, data4)

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
    vec2 packedHitDepths;

    packedLightPdfSubPixelJacobian = scatter_unpack_half2(data1.w);
    packedLensJacobians = scatter_unpack_half2(data3.w);
    packedHitDepths = scatter_unpack_half2(data0.w);
    reconnectionData = ReconnectionData_init();

    reconnectionData.firstHit.worldPos = data0.xyz;
    reconnectionData.firstHit.viewDepth = packedHitDepths.x;
    reconnectionData.secondHit.worldPos = data1.xyz;
    reconnectionData.secondHit.viewDepth = packedHitDepths.y;
    reconnectionData.irradiance = data2.xyz;
    reconnectionData.earlyThroughput = data3.xyz;
    reconnectionData.subPixel = scatter_unpack_half2(data4.x);
    reconnectionData.lensSample = scatter_unpack_half2(data4.y);
    reconnectionData.firstWi = scatter_unpack_unit_vector(data4.z);
    reconnectionData.secondWo = scatter_unpack_unit_vector(data4.w);
    reconnectionData.lightPdf = scatter_unpack_reconnection_proposal_pdf(packedLightPdfSubPixelJacobian.x);
    reconnectionData.subPixelJacobian = packedLightPdfSubPixelJacobian.y;
    reconnectionData.lensVertexJacobian = packedLensJacobians.x;
    reconnectionData.secondaryPathJacobian = packedLensJacobians.y;
    scatter_unpack_reconnection_meta(floatBitsToUint(data2.w), reconnectionData);
    scatter_unpack_reconnection_identity(0u, reconnectionData);
}

void scatter_load_gather_intermediate_reconnection(ivec2 uv, out ReconnectionData reconnection) {
    scatter_unpack_reconnection(
        texelFetch(temporal_gather_intermediate_reconnections, ivec3(uv, 0), 0),
        texelFetch(temporal_gather_intermediate_reconnections, ivec3(uv, 1), 0),
        texelFetch(temporal_gather_intermediate_reconnections, ivec3(uv, 2), 0),
        texelFetch(temporal_gather_intermediate_reconnections, ivec3(uv, 3), 0),
        texelFetch(temporal_gather_intermediate_reconnections, ivec3(uv, 4), 0),
        0.0f,
        0.0f,
        reconnection
    );
}

void scatter_load_prev_reconnection(ivec2 uv, out ReconnectionData reconnection) {
    scatter_unpack_reconnection(
        texelFetch(prev_scatter_reconnections, ivec3(uv, 0), 0),
        texelFetch(prev_scatter_reconnections, ivec3(uv, 1), 0),
        texelFetch(prev_scatter_reconnections, ivec3(uv, 2), 0),
        texelFetch(prev_scatter_reconnections, ivec3(uv, 3), 0),
        texelFetch(prev_scatter_reconnections, ivec3(uv, 4), 0),
        0.0f,
        0.0f,
        reconnection
    );
}
