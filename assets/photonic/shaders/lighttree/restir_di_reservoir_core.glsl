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

RTXDI_DIReservoir RTXDI_EmptyDIReservoir();
bool RTXDI_IsValidDIReservoir(RTXDI_DIReservoir reservoir);

const uint RTXDI_PackedDIReservoir_VisibilityMask = 0x3ffffu;
const uint RTXDI_PackedDIReservoir_VisibilityChannelMax = 0x3fu;
const uint RTXDI_PackedDIReservoir_VisibilityChannelShift = 6u;
const uint RTXDI_PackedDIReservoir_MShift = 18u;
const uint RTXDI_PackedDIReservoir_MaxMUint = 0x3fffu;
const uint RTXDI_PackedDIReservoir_MaxM = RTXDI_PackedDIReservoir_MaxMUint;
const uint RTXDI_DIReservoir_LightValidBit = 0x80000000u;
const uint RTXDI_DIReservoir_LightIndexMask = 0x7fffffffu;

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

// Primary -- matches RTXDI naming (RTXDI_DIReservoir.hlsli: RTXDI_EmptyDIReservoir)
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

// Backward-compat alias
RTXDI_DIReservoir rtxdi_empty_reservoir() {
    return RTXDI_EmptyDIReservoir();
}

// Primary -- matches RTXDI semantics: only checks light index validity (RTXDI_DIReservoir.hlsli: lightData != 0)
bool RTXDI_IsValidDIReservoir(RTXDI_DIReservoir reservoir) {
    return reservoir.lightData != 0u;
}

// Stricter photonics validity check -- also requires M > 0 and weightSum > 0.
// Kept separate from RTXDI_IsValidDIReservoir for callers that need it.
bool rtxdi_is_valid_reservoir(RTXDI_DIReservoir reservoir) {
    return reservoir.lightData != 0u && reservoir.M > 0.0f && reservoir.weightSum > 0.0f;
}

// Accessor wrappers -- naming parity with RTXDI's RTXDI_DIReservoir.hlsli accessor functions.
int RTXDI_GetDIReservoirLightIndex(RTXDI_DIReservoir reservoir) {
    return rtxdi_get_light_index(reservoir);
}

vec2 RTXDI_GetDIReservoirSampleUV(RTXDI_DIReservoir reservoir) {
    return rtxdi_get_sample_uv(reservoir);
}

float RTXDI_GetDIReservoirInvPdf(RTXDI_DIReservoir reservoir) {
    return reservoir.weightSum;
}

Light lt_decode_reservoir_light(RTXDI_DIReservoir reservoir, bool remap) {
    int index = rtxdi_get_light_index(reservoir);
    if (index < 0) {
        return lt_invalid_light();
    }

    if (remap) {
        if (index < 0 || index >= ph_lights_array_mapping.length()) {
            index = -1;
        } else {
            index = ph_lights_array_mapping[index];
        }
        if (index < 0 || index >= ph_light_count) {
            return lt_invalid_light();
        }
    }

    if (index < 0 || index >= ph_light_count) {
        return lt_invalid_light();
    }

    return load_light(index);
}

RAB_LightInfo lt_decode_previous_reservoir_light(RTXDI_DIReservoir reservoir) {
    int lightIndex = rtxdi_get_light_index(reservoir);
    if (lightIndex < 0) {
        return lt_invalid_light();
    }

    return load_previous_light(lightIndex);
}

RAB_LightSample light_sample_decode(RTXDI_DIReservoir reservoir, RAB_Surface surface, bool remap) {
    Light light = lt_decode_reservoir_light(reservoir, remap);
    if (light.index < 0) {
        return lt_null_sample();
    }

    vec3 lightPosition = lt_sample_light_position_from_uv(
        light,
        rtxdi_get_sample_uv(reservoir),
        lt_surface_ray_origin(lt_surface_rt_pos(surface), surface.geoNormal)
    );
    return light_sample_new_at_position(light, lightPosition, surface);
}

RAB_LightSample light_sample_decode_previous(RTXDI_DIReservoir reservoir, RAB_Surface surface) {
    RAB_LightInfo light = lt_decode_previous_reservoir_light(reservoir);
    if (light.index < 0) {
        return lt_null_sample();
    }

    vec3 lightPosition = lt_sample_light_position_from_uv(
        light,
        rtxdi_get_sample_uv(reservoir),
        lt_surface_ray_origin(lt_surface_rt_pos(surface), surface.geoNormal)
    );
    return light_sample_new_at_position(light, lightPosition, surface);
}

int lt_translate_reservoir_light_index_between_frames(int lightIndex, bool reservoirPreviousFrame, bool targetPreviousFrame) {
    if (lightIndex < 0) {
        return -1;
    }

    if (reservoirPreviousFrame == targetPreviousFrame) {
        return lightIndex;
    }

    return RAB_TranslateLightIndex(lightIndex, !reservoirPreviousFrame);
}

RTXDI_DIReservoir lt_translate_reservoir_between_frames(
    RTXDI_DIReservoir reservoir,
    bool reservoirPreviousFrame,
    bool targetPreviousFrame)
{
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        return reservoir;
    }

    int translatedLightIndex = lt_translate_reservoir_light_index_between_frames(
        rtxdi_get_light_index(reservoir),
        reservoirPreviousFrame,
        targetPreviousFrame
    );

    if (translatedLightIndex < 0) {
        return RTXDI_EmptyDIReservoir();
    }

    rtxdi_set_light_index(reservoir, translatedLightIndex);
    return reservoir;
}

RAB_LightSample lt_decode_reservoir_sample_for_frame(
    RTXDI_DIReservoir reservoir,
    RAB_Surface surface,
    bool reservoirPreviousFrame,
    bool targetPreviousFrame)
{
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        return lt_null_sample();
    }

    int translatedLightIndex = lt_translate_reservoir_light_index_between_frames(
        rtxdi_get_light_index(reservoir),
        reservoirPreviousFrame,
        targetPreviousFrame
    );
    if (translatedLightIndex < 0) {
        return lt_null_sample();
    }

    RAB_LightInfo light = targetPreviousFrame
        ? load_previous_light(translatedLightIndex)
        : load_light(translatedLightIndex);
    if (light.index < 0) {
        return lt_null_sample();
    }

    vec3 lightPosition = lt_sample_light_position_from_uv(
        light,
        rtxdi_get_sample_uv(reservoir),
        lt_surface_ray_origin(lt_surface_rt_pos(surface), surface.geoNormal)
    );
    return light_sample_new_at_position(light, lightPosition, surface);
}

RAB_LightSample light_sample_decode_at(float value, vec2 sampleUv, RAB_Surface surface, bool remap) {
    RTXDI_DIReservoir replayReservoir;
    replayReservoir.lightData = 0u;
    replayReservoir.uvData = 0u;
    replayReservoir.weightSum = 0.0;
    replayReservoir.targetPdf = 0.0;
    replayReservoir.M = 0.0;
    replayReservoir.packedVisibility = 0u;
    replayReservoir.age = 0u;
    replayReservoir.spatialDistance = ivec2(0);
    replayReservoir.canonicalWeight = 0.0;
    replayReservoir.transportAux0 = 0.0;
    replayReservoir.transportAux1 = 0.0;
    replayReservoir.pixelSampleUV = vec2(0.5f);
    replayReservoir.lensSampleUV = vec2(0.5f);
    replayReservoir.pathSample = 2u;
    rtxdi_set_light_index(replayReservoir, int(round(value)));
    rtxdi_set_sample_uv(replayReservoir, sampleUv);
    return light_sample_decode(replayReservoir, surface, remap);
}

RAB_LightSample light_sample_decode_at(float value, RAB_Surface surface, bool remap) {
    return light_sample_decode_at(value, vec2(0.0f), surface, remap);
}

bool lt_pick_uniform_light(out int lightIndex, out float lightPdf) {
    lightIndex = -1;
    lightPdf = 0.0f;

    if (ph_light_count <= 0) {
        return false;
    }

    lightIndex = rand_next_int(0, ph_light_count);
    lightPdf = 1.0f / float(max(ph_light_count, 1));
    return lightIndex >= 0 && lightIndex < ph_light_count;
}

bool lt_pick_power_light(out int lightIndex, out float lightPdf) {
    lightIndex = -1;
    lightPdf = 0.0f;

    if (ph_light_count <= 0) {
        return false;
    }

    float totalWeight = ph_global_light_cdf_data[ph_light_count - 1];
    if (totalWeight <= 1e-6f) {
        return lt_pick_uniform_light(lightIndex, lightPdf);
    }

    float draw = rand_next_float() * totalWeight;
    int low = 0;
    int high = ph_light_count - 1;
    while (low < high) {
        int mid = (low + high) >> 1;
        if (ph_global_light_cdf_data[mid] < draw) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }

    float prevCdf = low > 0 ? ph_global_light_cdf_data[low - 1] : 0.0f;
    float weight = ph_global_light_cdf_data[low] - prevCdf;
    if (weight <= 1e-6f) {
        return lt_pick_uniform_light(lightIndex, lightPdf);
    }

    lightIndex = low;
    lightPdf = max(weight / totalWeight, 1e-6f);
    return true;
}
