#ifndef PHOTONICS_RESTIR_DI_RESERVOIR_PACKING_GLSL
#define PHOTONICS_RESTIR_DI_RESERVOIR_PACKING_GLSL

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

vec4 rtxdi_pack_reservoir_meta_with_transport(
    RTXDI_DIReservoir reservoir,
    float transportAux0,
    float transportAux1)
{
    return vec4(
        reservoir.canonicalWeight,
        transportAux0,
        transportAux1,
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

    rtxdi_unpack_reservoir_payload(
        reservoir,
        lightData,
        color,
        sampleData,
        meta
    );

    if (!lt_area_has_valid_domain(reservoir)) {
        reservoir.pixelSampleUV = vec2(-1.0f);
        reservoir.lensSampleUV = vec2(-1.0f);
    }
}

#endif
