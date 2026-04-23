const int RTXDI_PackedDIReservoir_DistanceChannelBits = 8;
const int RTXDI_PackedDIReservoir_DistanceXShift = 0;
const int RTXDI_PackedDIReservoir_DistanceYShift = 8;
const int RTXDI_PackedDIReservoir_AgeShift = 16;
const uint RTXDI_PackedDIReservoir_MaxAge = 0xffu;
const uint RTXDI_PackedDIReservoir_DistanceMask = (1u << RTXDI_PackedDIReservoir_DistanceChannelBits) - 1u;
const int RTXDI_PackedDIReservoir_MaxDistance = int((1u << (RTXDI_PackedDIReservoir_DistanceChannelBits - 1)) - 1u);

vec3 rtxdi_unpack_visibility(uint packedVisibility) {
    return vec3(
        float(packedVisibility & RTXDI_PackedDIReservoir_VisibilityChannelMax),
        float((packedVisibility >> RTXDI_PackedDIReservoir_VisibilityChannelShift) & RTXDI_PackedDIReservoir_VisibilityChannelMax),
        float((packedVisibility >> (RTXDI_PackedDIReservoir_VisibilityChannelShift * 2u)) & RTXDI_PackedDIReservoir_VisibilityChannelMax)
    ) / float(RTXDI_PackedDIReservoir_VisibilityChannelMax);
}

uint rtxdi_pack_visibility(vec3 visibility) {
    vec3 clampedVisibility = clamp(visibility, vec3(0.0f), vec3(1.0f));
    uvec3 encodedVisibility = uvec3(clampedVisibility * float(RTXDI_PackedDIReservoir_VisibilityChannelMax));
    return encodedVisibility.x
        | (encodedVisibility.y << RTXDI_PackedDIReservoir_VisibilityChannelShift)
        | (encodedVisibility.z << (RTXDI_PackedDIReservoir_VisibilityChannelShift * 2u));
}

vec4 rtxdi_pack_reservoir(RTXDI_DIReservoir reservoir) {
    uint packedM = min(uint(reservoir.M), RTXDI_PackedDIReservoir_MaxMUint);
    return vec4(
        uintBitsToFloat(reservoir.lightData),
        reservoir.weightSum,
        reservoir.targetPdf,
        uintBitsToFloat(reservoir.packedVisibility | (packedM << RTXDI_PackedDIReservoir_MShift))
    );
}

vec4 rtxdi_pack_reservoir_sample(RTXDI_DIReservoir reservoir) {
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        return vec4(0.0f);
    }

    return vec4(
        uintBitsToFloat(reservoir.uvData),
        uintBitsToFloat(rtxdi_pack_sample_uv(reservoir.pixelSampleUV)),
        uintBitsToFloat(rtxdi_pack_sample_uv(reservoir.lensSampleUV)),
        uintBitsToFloat(reservoir.pathSample)
    );
}

uint rtxdi_pack_age_distance(uint age, ivec2 sd) {
    ivec2 clampedSpatialDistance = clamp(
        sd,
        ivec2(-RTXDI_PackedDIReservoir_MaxDistance),
        ivec2(RTXDI_PackedDIReservoir_MaxDistance)
    );
    uint clampedAge = min(age, RTXDI_PackedDIReservoir_MaxAge);

    return ((uint(clampedSpatialDistance.x) & RTXDI_PackedDIReservoir_DistanceMask) << RTXDI_PackedDIReservoir_DistanceXShift)
        | ((uint(clampedSpatialDistance.y) & RTXDI_PackedDIReservoir_DistanceMask) << RTXDI_PackedDIReservoir_DistanceYShift)
        | (clampedAge << RTXDI_PackedDIReservoir_AgeShift);
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

vec4 rtxdi_pack_reservoir_meta_with_transport(
    RTXDI_DIReservoir reservoir,
    float transportAux0,
    float transportAux1)
{
    return vec4(
        reservoir.canonicalWeight,
        reservoir.transportAux0,
        reservoir.transportAux1,
        uintBitsToFloat(rtxdi_pack_age_distance(reservoir.age, reservoir.spatialDistance))
    );
}

vec4 rtxdi_pack_reservoir_meta(RTXDI_DIReservoir reservoir) {
    return vec4(
        reservoir.canonicalWeight,
        reservoir.transportAux0,
        reservoir.transportAux1,
        uintBitsToFloat(rtxdi_pack_age_distance(reservoir.age, reservoir.spatialDistance))
    );
}

vec4 PathReservoir_packMeta(RTXDI_DIReservoir reservoir) {
    return rtxdi_pack_reservoir_meta(reservoir);
}

void rtxdi_unpack_reservoir_at_surface(
    inout RTXDI_DIReservoir reservoir,
    vec4 color,
    vec4 sampleData,
    vec4 meta,
    RAB_Surface surface,
    bool remap)
{
    uint lightData = floatBitsToUint(color.x);

    if (remap) {
        int index = rtxdi_decode_light_index(lightData);
        if (index >= 0 && index < ph_lights_array_mapping.length()) {
            index = ph_lights_array_mapping[index];
        }
        if (index < 0 || index >= ph_light_count) {
            lightData = 0u;
        } else {
            lightData = rtxdi_make_light_data(index);
        }
    }
    // When remap=false, lightData preserves the previous-frame packed ID and validity bit.
    // RTXDI_LoadDIReservoir does not validate -- remapping happens separately at the call site.

    reservoir.lightData = lightData;
    reservoir.uvData = floatBitsToUint(sampleData.x);
    reservoir.pixelSampleUV = rtxdi_unpack_sample_uv(floatBitsToUint(sampleData.y));
    reservoir.lensSampleUV = rtxdi_unpack_sample_uv(floatBitsToUint(sampleData.z));
    reservoir.pathSample = floatBitsToUint(sampleData.w);
    reservoir.weightSum = color.y;
    reservoir.targetPdf = color.z;
    uint packedVisibilityAndM = floatBitsToUint(color.w);
    reservoir.M = float((packedVisibilityAndM >> RTXDI_PackedDIReservoir_MShift) & RTXDI_PackedDIReservoir_MaxMUint);

    // Unpack age+spatialDistance from meta.w, matching RTXDI distanceAge packing.
    // packedVisibility lives in color.w with M, matching RTXDI_PackedDIReservoir::mVisibility.
    uint packedDistanceAge = floatBitsToUint(meta.w);
    reservoir.packedVisibility = packedVisibilityAndM & RTXDI_PackedDIReservoir_VisibilityMask;
    rtxdi_unpack_age_distance(packedDistanceAge, reservoir.age, reservoir.spatialDistance);
    reservoir.canonicalWeight = meta.x;
    reservoir.transportAux0 = meta.y;
    reservoir.transportAux1 = meta.z;

    if (!lt_area_has_valid_domain(reservoir)) {
        reservoir.pixelSampleUV = vec2(-1.0f);
        reservoir.lensSampleUV = vec2(-1.0f);
    }

    // RTXDI_UnpackDIReservoir sanitization (ReservoirStorage.hlsli lines 88-91):
    //   if (isinf(res.weightSum) || isnan(res.weightSum)) { res = RTXDI_EmptyDIReservoir(); }
    // RTXDI only checks weightSum, not targetPdf. Match exactly.
    if (isinf(reservoir.weightSum) || isnan(reservoir.weightSum)) {
        reservoir = RTXDI_EmptyDIReservoir();
    }
}
