#include "/photonics/lighttree/restir_di_reservoir_payload.glsl"

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
    replayReservoir.lensSampleUV = vec2(0.0f);
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

#if defined(PH_LIGHTTREE_ENABLE_POWER_LIGHT_CDF) && !PH_LIGHTTREE_ENABLE_POWER_LIGHT_CDF
    return lt_pick_uniform_light(lightIndex, lightPdf);
#else
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
#endif
}
