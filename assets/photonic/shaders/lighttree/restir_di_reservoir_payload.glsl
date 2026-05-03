#ifndef PHOTONICS_RESTIR_DI_RESERVOIR_PAYLOAD_GLSL
#define PHOTONICS_RESTIR_DI_RESERVOIR_PAYLOAD_GLSL

struct RTXDI_DIReservoir {
    uint lightData;
    uint uvData;
    float weightSum;
    float targetPdf;
    float M;
    uint packedVisibility;
    ivec2 spatialDistance;
    uint age;
    float canonicalWeight;
    float transportAux0;
    float transportAux1;
    vec2 pixelSampleUV;
    vec2 lensSampleUV;
    uint pathSample;
};

const uint LT_PATH_SAMPLE_CONFIDENCE_SHIFT = 21u;
const uint LT_PATH_SAMPLE_CONFIDENCE_BITS = 11u;
const uint LT_PATH_SAMPLE_CONFIDENCE_MASK = (1u << LT_PATH_SAMPLE_CONFIDENCE_BITS) - 1u;
const uint LT_PATH_SAMPLE_PAYLOAD_MASK = (1u << LT_PATH_SAMPLE_CONFIDENCE_SHIFT) - 1u;
const float LT_PATH_SAMPLE_CONFIDENCE_MAX = 20.0f;

const uint RTXDI_PackedDIReservoir_VisibilityMask = 0x3ffffu;
const uint RTXDI_PackedDIReservoir_VisibilityChannelMax = 0x3fu;
const uint RTXDI_PackedDIReservoir_VisibilityChannelShift = 6u;
const uint RTXDI_PackedDIReservoir_MShift = 18u;
const uint RTXDI_PackedDIReservoir_MaxMUint = 0x3fffu;
const uint RTXDI_PackedDIReservoir_MaxM = RTXDI_PackedDIReservoir_MaxMUint;
const uint RTXDI_DIReservoir_LightValidBit = 0x80000000u;
const uint RTXDI_DIReservoir_LightIndexMask = 0x7fffffffu;

const int RTXDI_PackedDIReservoir_DistanceChannelBits = 8;
const int RTXDI_PackedDIReservoir_DistanceXShift = 0;
const int RTXDI_PackedDIReservoir_DistanceYShift = 8;
const int RTXDI_PackedDIReservoir_AgeShift = 16;
const uint RTXDI_PackedDIReservoir_MaxAge = 0xffu;
const uint RTXDI_PackedDIReservoir_DistanceMask = (1u << RTXDI_PackedDIReservoir_DistanceChannelBits) - 1u;
const int RTXDI_PackedDIReservoir_MaxDistance = int((1u << (RTXDI_PackedDIReservoir_DistanceChannelBits - 1)) - 1u);

float lt_path_sample_confidence(uint pathSample) {
    uint packedConfidence = (pathSample >> LT_PATH_SAMPLE_CONFIDENCE_SHIFT) & LT_PATH_SAMPLE_CONFIDENCE_MASK;
    return (float(packedConfidence) / float(LT_PATH_SAMPLE_CONFIDENCE_MASK)) * LT_PATH_SAMPLE_CONFIDENCE_MAX;
}

uint lt_path_sample_set_confidence_bits(uint pathSample, float confidence) {
    uint packedConfidence = min(
        uint(round(clamp(confidence, 0.0f, LT_PATH_SAMPLE_CONFIDENCE_MAX) * float(LT_PATH_SAMPLE_CONFIDENCE_MASK) / LT_PATH_SAMPLE_CONFIDENCE_MAX)),
        LT_PATH_SAMPLE_CONFIDENCE_MASK
    );
    return (pathSample & LT_PATH_SAMPLE_PAYLOAD_MASK) | (packedConfidence << LT_PATH_SAMPLE_CONFIDENCE_SHIFT);
}

vec3 PathReservoir_getIntegrand(RTXDI_DIReservoir reservoir) {
    return vec3(
        reservoir.canonicalWeight,
        reservoir.transportAux0,
        reservoir.transportAux1
    );
}

void PathReservoir_setIntegrand(inout RTXDI_DIReservoir reservoir, vec3 integrand) {
    reservoir.canonicalWeight = integrand.x;
    reservoir.transportAux0 = integrand.y;
    reservoir.transportAux1 = integrand.z;
}

float PathReservoir_getConfidence(RTXDI_DIReservoir reservoir) {
    return lt_path_sample_confidence(reservoir.pathSample);
}

void PathReservoir_setConfidence(inout RTXDI_DIReservoir reservoir, float confidence) {
    reservoir.pathSample = lt_path_sample_set_confidence_bits(reservoir.pathSample, confidence);
}

float PathReservoir_getTotalWeight(RTXDI_DIReservoir reservoir) {
    return reservoir.weightSum;
}

void PathReservoir_setTotalWeight(inout RTXDI_DIReservoir reservoir, float totalWeight) {
    reservoir.weightSum = totalWeight;
}

float PathReservoir_computeUCW(RTXDI_DIReservoir reservoir) {
    vec3 integrand = PathReservoir_getIntegrand(reservoir);
    float pHat = ph_luminance(integrand);
    return (pHat <= 0.0f) ? 0.0f : PathReservoir_getTotalWeight(reservoir) / pHat;
}

float PathReservoir_computeStoredUCW(RTXDI_DIReservoir reservoir) {
    return PathReservoir_computeUCW(reservoir);
}

uint rtxdi_make_light_data(int lightIndex) {
    return (lightIndex < 0)
        ? 0u
        : (uint(lightIndex) & RTXDI_DIReservoir_LightIndexMask) | RTXDI_DIReservoir_LightValidBit;
}

int rtxdi_decode_light_index(uint lightData) {
    return ((lightData & RTXDI_DIReservoir_LightValidBit) == 0u)
        ? -1
        : int(lightData & RTXDI_DIReservoir_LightIndexMask);
}

uint rtxdi_pack_sample_uv(vec2 sampleUv) {
    uint packedX = uint(clamp(sampleUv.x, 0.0f, 1.0f) * 65535.0f + 0.5f);
    uint packedY = uint(clamp(sampleUv.y, 0.0f, 1.0f) * 65535.0f + 0.5f);
    return packedX | (packedY << 16u);
}

vec2 rtxdi_unpack_sample_uv(uint packedUv) {
    return vec2(float(packedUv & 0xffffu), float((packedUv >> 16u) & 0xffffu)) / 65535.0f;
}

int rtxdi_get_light_index(RTXDI_DIReservoir reservoir) {
    return rtxdi_decode_light_index(reservoir.lightData);
}

void rtxdi_set_light_index(inout RTXDI_DIReservoir reservoir, int lightIndex) {
    reservoir.lightData = rtxdi_make_light_data(lightIndex);
}

vec2 rtxdi_get_sample_uv(RTXDI_DIReservoir reservoir) {
    return rtxdi_unpack_sample_uv(reservoir.uvData);
}

void rtxdi_set_sample_uv(inout RTXDI_DIReservoir reservoir, vec2 sampleUv) {
    reservoir.uvData = rtxdi_pack_sample_uv(sampleUv);
}

RTXDI_DIReservoir RTXDI_EmptyDIReservoir() {
    RTXDI_DIReservoir r;
    r.lightData = 0u;
    r.uvData = 0u;
    r.weightSum = 0.0;
    r.targetPdf = 0.0;
    r.M = 0.0;
    r.packedVisibility = 0u;
    r.age = 0u;
    r.spatialDistance = ivec2(0);
    r.canonicalWeight = 0.0;
    r.transportAux0 = 0.0;
    r.transportAux1 = 0.0;
    r.pixelSampleUV = vec2(-1.0f);
    r.lensSampleUV = vec2(-1.0f);
    r.pathSample = 2u;
    return r;
}

bool RTXDI_IsValidDIReservoir(RTXDI_DIReservoir reservoir) {
    return reservoir.lightData != 0u;
}

bool rtxdi_is_valid_reservoir(RTXDI_DIReservoir reservoir) {
    return reservoir.lightData != 0u && reservoir.M > 0.0f && reservoir.weightSum > 0.0f;
}

int RTXDI_GetDIReservoirLightIndex(RTXDI_DIReservoir reservoir) {
    return rtxdi_get_light_index(reservoir);
}

vec2 RTXDI_GetDIReservoirSampleUV(RTXDI_DIReservoir reservoir) {
    return rtxdi_get_sample_uv(reservoir);
}

float RTXDI_GetDIReservoirInvPdf(RTXDI_DIReservoir reservoir) {
    return reservoir.weightSum;
}

void rtxdi_unpack_age_distance(uint packedValue, out uint age, out ivec2 sd) {
    int sxShift = 32 - RTXDI_PackedDIReservoir_DistanceXShift - RTXDI_PackedDIReservoir_DistanceChannelBits;
    int syShift = 32 - RTXDI_PackedDIReservoir_DistanceYShift - RTXDI_PackedDIReservoir_DistanceChannelBits;
    int signExtendShift = 32 - RTXDI_PackedDIReservoir_DistanceChannelBits;
    int isx = int(packedValue << sxShift) >> signExtendShift;
    int isy = int(packedValue << syShift) >> signExtendShift;
    age = (packedValue >> RTXDI_PackedDIReservoir_AgeShift) & RTXDI_PackedDIReservoir_MaxAge;
    sd = ivec2(isx, isy);
}

void rtxdi_unpack_reservoir_payload(
    inout RTXDI_DIReservoir reservoir,
    uint lightData,
    vec4 color,
    vec4 sampleData,
    vec4 meta)
{
    reservoir.lightData = lightData;
    reservoir.uvData = floatBitsToUint(sampleData.x);
    reservoir.pixelSampleUV = rtxdi_unpack_sample_uv(floatBitsToUint(sampleData.y));
    reservoir.lensSampleUV = rtxdi_unpack_sample_uv(floatBitsToUint(sampleData.z));
    reservoir.pathSample = floatBitsToUint(sampleData.w);
    reservoir.weightSum = color.y;
    reservoir.targetPdf = color.z;

    uint packedVisibilityAndM = floatBitsToUint(color.w);
    reservoir.M = float((packedVisibilityAndM >> RTXDI_PackedDIReservoir_MShift) & RTXDI_PackedDIReservoir_MaxMUint);
    reservoir.packedVisibility = packedVisibilityAndM & RTXDI_PackedDIReservoir_VisibilityMask;
    rtxdi_unpack_age_distance(floatBitsToUint(meta.w), reservoir.age, reservoir.spatialDistance);
    reservoir.canonicalWeight = meta.x;
    reservoir.transportAux0 = meta.y;
    reservoir.transportAux1 = meta.z;

    if (isinf(reservoir.weightSum) || isnan(reservoir.weightSum)) {
        reservoir = RTXDI_EmptyDIReservoir();
    }
}

void rtxdi_unpack_reservoir_payload(
    inout RTXDI_DIReservoir reservoir,
    vec4 color,
    vec4 sampleData,
    vec4 meta)
{
    rtxdi_unpack_reservoir_payload(
        reservoir,
        floatBitsToUint(color.x),
        color,
        sampleData,
        meta
    );
}

#endif
