#ifndef PHOTONICS_RESTIR_DI_RECONNECTION_PAYLOAD_GLSL
#define PHOTONICS_RESTIR_DI_RECONNECTION_PAYLOAD_GLSL

// Reference-parity ReconnectionData (ReconnectionData.slang:89-166).
// Field order, names, types and default values MUST match the Slang reference.
struct HitInfo {
    vec3 worldPos;
    float viewDepth;
    uint faceId;
    uint materialId;
};

HitInfo HitInfo_empty() {
    HitInfo h;
    h.worldPos = vec3(0.0f);
    h.viewDepth = 0.0f;
    h.faceId = 0u;
    h.materialId = 0u;
    return h;
}

struct ShiftedPathData {
    HitInfo primaryHit;
    vec2 fractionalPixel;
    vec2 lensSample;
    vec3 firstRayDir;
    float subPixelJacobian;
    float lensVertexJacobian;
    float secondaryPathJacobian;
    vec3 radiance;
};

struct ReconnectionData {
    vec2 subPixel;
    vec2 lensSample;
    float time;
    uint pathLength;
    HitInfo firstHit;
    uint firstBSDFComponentType;
    vec3 firstWi;
    HitInfo secondHit;
    uint secondBSDFComponentType;
    vec3 secondWo;
    bool transmissionEvent;
    bool lightIsNEE;
    bool lightIsDistant;
    float lightPdf;
    float subPixelJacobian;
    float lensVertexJacobian;
    float secondaryPathJacobian;
    vec3 irradiance;
    vec3 earlyThroughput;
};

ReconnectionData ReconnectionData_init() {
    ReconnectionData d;
    d.subPixel = vec2(0.5f, 0.5f);
    d.lensSample = vec2(0.0f, 0.0f);
    d.time = 0.0f;
    d.pathLength = 0u;
    d.firstHit = HitInfo_empty();
    d.firstBSDFComponentType = 0u;
    d.firstWi = vec3(0.0f, 0.0f, 0.0f);
    d.secondHit = HitInfo_empty();
    d.secondBSDFComponentType = 0u;
    d.secondWo = vec3(0.0f, 0.0f, 0.0f);
    d.transmissionEvent = false;
    d.lightIsNEE = false;
    d.lightIsDistant = false;
    d.lightPdf = 0.0f;
    d.subPixelJacobian = 1.0f;
    d.lensVertexJacobian = 1.0f;
    d.secondaryPathJacobian = 1.0f;
    d.irradiance = vec3(0.0f, 0.0f, 0.0f);
    d.earlyThroughput = vec3(1.0f, 1.0f, 1.0f);
    return d;
}

const uint SCATTER_RECONNECTION_FLAG_LIGHT_IS_NEE = 1u << 0u;
const uint SCATTER_RECONNECTION_FLAG_LIGHT_IS_DISTANT = 1u << 1u;
const uint SCATTER_RECONNECTION_FLAG_FIRST_WI_VALID = 1u << 2u;
const uint SCATTER_RECONNECTION_FLAG_SECOND_WO_VALID = 1u << 3u;
const uint SCATTER_RECONNECTION_EVENT_TRANSMISSION = 1u << 0u;
const uint SCATTER_BSDF_COMPONENT_DIFFUSE = 0u;
const uint SCATTER_BSDF_COMPONENT_SPECULAR = 1u;
const float PATH_RESERVOIR_CONFIDENCE_CAP = 20.0f;
#define SCATTER_RECONNECTION_CONFIDENCE_MAX PATH_RESERVOIR_CONFIDENCE_CAP
const uint SCATTER_RECONNECTION_VIEW_DEPTH_MASK = 0x0000FFFFu;
const uint SCATTER_RECONNECTION_CONFIDENCE_MASK = 0x00000FFFu;
const uint SCATTER_RECONNECTION_CONFIDENCE_SHIFT = 16u;
const uint SCATTER_RECONNECTION_FLAGS_MASK = 0xFu;
const uint SCATTER_RECONNECTION_FLAGS_SHIFT = 0u;
const uint SCATTER_RECONNECTION_PATH_LENGTH_MASK = 0x3Fu;
const uint SCATTER_RECONNECTION_PATH_LENGTH_SHIFT = 4u;
const uint SCATTER_RECONNECTION_FIRST_BSDF_MASK = 0x3u;
const uint SCATTER_RECONNECTION_FIRST_BSDF_SHIFT = 10u;
const uint SCATTER_RECONNECTION_SECOND_BSDF_MASK = 0x3u;
const uint SCATTER_RECONNECTION_SECOND_BSDF_SHIFT = 12u;
const uint SCATTER_RECONNECTION_TRANSMISSION_SHIFT = 14u;
const uint SCATTER_RECONNECTION_TIME_SHIFT = 15u;
const uint SCATTER_RECONNECTION_TIME_MASK = 0x1FFu;
const uint SCATTER_RECONNECTION_FACE_MASK = 0x7u;
const uint SCATTER_RECONNECTION_FIRST_FACE_SHIFT = 24u;
const uint SCATTER_RECONNECTION_SECOND_FACE_SHIFT = 27u;

float scatter_pack_half2(vec2 value) {
    return uintBitsToFloat(packHalf2x16(value));
}

vec2 scatter_unpack_half2(float packedValue) {
    return unpackHalf2x16(floatBitsToUint(packedValue));
}

uint scatter_pack_reconnection_time_bits(float time)
{
    float clampedTime = clamp(time, 0.0f, 1.0f);
    return min(uint(round(clampedTime * float(SCATTER_RECONNECTION_TIME_MASK))), SCATTER_RECONNECTION_TIME_MASK);
}

float scatter_unpack_reconnection_time_bits(uint packedMeta)
{
    return float((packedMeta >> SCATTER_RECONNECTION_TIME_SHIFT) & SCATTER_RECONNECTION_TIME_MASK)
        / float(SCATTER_RECONNECTION_TIME_MASK);
}

#endif
