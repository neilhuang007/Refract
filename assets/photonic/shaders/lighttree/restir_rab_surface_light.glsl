// A surface is valid if it has a non-zero-length normal (sky/empty pixels have zero normals).
// Matches RAB_IsSurfaceValid semantics from RTXDI (TemporalResampling.hlsli line 94).
bool lt_is_valid_surface(RAB_Surface surface) {
    return surface.viewDepth != BACKGROUND_DEPTH;
}

RAB_Surface RAB_EmptySurface()
{
    return lt_empty_surface();
}

bool RAB_IsSurfaceValid(RAB_Surface surface)
{
    return lt_is_valid_surface(surface);
}

vec3 RAB_GetSurfaceNormal(RAB_Surface surface)
{
    return surface.normal;
}

vec3 RAB_GetSurfaceWorldPos(RAB_Surface surface)
{
    return surface.worldPos;
}

vec3 RAB_GetSurfaceGeoNormal(RAB_Surface surface)
{
    return surface.geoNormal;
}

vec3 RAB_GetSurfaceViewDir(RAB_Surface surface)
{
    return surface.viewDir;
}

float RAB_GetSurfaceLinearDepth(RAB_Surface surface)
{
    return surface.viewDepth;
}

RAB_Material RAB_GetMaterial(RAB_Surface surface)
{
    return surface.material;
}

RAB_Material RAB_GetGBufferMaterial(ivec2 pixelPosition, bool previousFrame)
{
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        return RAB_EmptyMaterial();
    }

    if (previousFrame) {
        return lt_make_material(
            texelFetch(prev_radiosity_material, pixelPosition, 0),
            clamp(texelFetch(prev_radiosity_albedo, pixelPosition, 0).rgb, vec3(0.04f), vec3(1.0f))
        );
    }

    return lt_make_material(
        texelFetch(radiosity_material, pixelPosition, 0),
        clamp(texelFetch(radiosity_albedo, pixelPosition, 0).rgb, vec3(0.04f), vec3(1.0f))
    );
}

RAB_Surface RAB_GetGBufferSurface(ivec2 pixelPosition, bool previousFrame)
{
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        return RAB_EmptySurface();
    }

    return previousFrame
        ? lt_load_previous_surface(pixelPosition)
        : lt_load_surface(pixelPosition);
}

int RAB_TranslateLightIndex(int lightIndex, bool previousFrame)
{
    if (lightIndex < 0) {
        return -1;
    }

    if (previousFrame) {
        if (lightIndex >= ph_light_reverse_mapping.length()) {
            return -1;
        }

        return ph_light_reverse_mapping[lightIndex];
    }

    if (lightIndex >= ph_lights_array_mapping.length()) {
        return -1;
    }

    int mappedLightIndex = ph_lights_array_mapping[lightIndex];
    if (mappedLightIndex < 0 || mappedLightIndex >= ph_light_count) {
        return -1;
    }

    return mappedLightIndex;
}

RAB_LightInfo RAB_EmptyLightInfo()
{
    return lt_invalid_light();
}

RAB_LightSample RAB_EmptyLightSample()
{
    return lt_null_sample();
}

RAB_LightInfo RAB_LoadLightInfo(int lightIndex, bool previousFrame)
{
    if (lightIndex < 0) {
        return RAB_EmptyLightInfo();
    }

    return previousFrame
        ? load_previous_light(lightIndex)
        : (lightIndex < ph_light_count ? load_light(lightIndex) : RAB_EmptyLightInfo());
}

RAB_LightInfo RAB_LoadCompactLightInfo(uint risBufferPtr, int lightIndex)
{
    if (lightIndex < 0) {
        return RAB_EmptyLightInfo();
    }

    return load_compact_light(risBufferPtr, lightIndex);
}

RAB_LightSample RAB_SamplePolymorphicLight(Light light, RAB_Surface surface, vec2 sampleUv)
{
    if (light.index < 0) {
        return RAB_EmptyLightSample();
    }

    vec3 lightPosition = lt_sample_light_position_from_uv(
        light,
        sampleUv,
        lt_surface_ray_origin(lt_surface_rt_pos(surface), surface.geoNormal)
    );
    return light_sample_new_at_position(light, lightPosition, surface);
}

float RAB_GetLightSampleTargetPdfForSurface(RAB_LightSample lightSample, RAB_Surface surface)
{
    return lt_surface_target_pdf(surface, lightSample);
}
