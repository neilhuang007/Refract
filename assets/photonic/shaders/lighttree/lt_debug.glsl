#ifndef PHOTONICS_LT_DEBUG_GLSL
#define PHOTONICS_LT_DEBUG_GLSL

// ---------------------------------------------------------------------------
// Shared NRD specular clamping constant and helper.
// Consumers must include nrd_common.glsl before this file — nrd_luminance()
// is provided there.
// ---------------------------------------------------------------------------

const float ph_nrd_spec_fp16_safe_luma = 248.0;

// Consumers must include light_tree.glsl before this file — ph_regir_* uniforms,
// RAB_Surface, and RTXDI_* types are provided there.
vec3 ph_clamp_specular_for_relax(vec3 demodulatedSpecular) {
    demodulatedSpecular = max(demodulatedSpecular, vec3(0.0));
    float specularLuma = nrd_luminance(demodulatedSpecular);
    if (specularLuma > ph_nrd_spec_fp16_safe_luma) {
        demodulatedSpecular *= ph_nrd_spec_fp16_safe_luma / max(specularLuma, 1e-6);
    }
    return demodulatedSpecular;
}

// ---------------------------------------------------------------------------
// Debug visualisation helpers — all lt_debug_* functions below.
// ---------------------------------------------------------------------------

vec3 lt_debug_heat_ramp(float t) {
    t = clamp(t, 0.0f, 1.0f);
    return mix(vec3(0.0f, 1.0f, 0.0f), vec3(1.0f, 0.0f, 0.0f), t);
}

float lt_debug_encode_positive_metric(float value, float maxValue) {
    if (!(value > 0.0f) || isnan(value) || isinf(value)) {
        return 0.0f;
    }
    return clamp(log2(value + 1.0f) / log2(maxValue + 1.0f), 0.0f, 1.0f);
}

float lt_debug_encode_small_pdf(float value) {
    if (!(value > 0.0f) || isnan(value) || isinf(value)) {
        return 1.0f;
    }
    return clamp((-log2(clamp(value, 1e-6f, 1.0f))) / 16.0f, 0.0f, 1.0f);
}

ivec2 lt_debug_reservoir_pos_for_pixel(ivec2 pixelPosition, int activeCheckerboardField) {
    ivec2 activePixel = pixelPosition;
    RTXDI_ActivateCheckerboardPixel(activePixel, false, activeCheckerboardField);
    activePixel.x = clamp(activePixel.x, 0, int(viewWidth) - 1);
    activePixel.y = clamp(activePixel.y, 0, int(viewHeight) - 1);
    return RTXDI_PixelPosToReservoirPos(activePixel, activeCheckerboardField);
}

ivec3 lt_debug_regir_build_region_min_cell() {
    int buildRegionCells = max(ph_regir_build_region_cells, 1);
    ivec3 centerCell = ivec3(floor(ph_regir_grid_center / max(ph_regir_hash_cell_size, 1.0e-6f)));
    return centerCell - ivec3(buildRegionCells / 2);
}

bool lt_debug_regir_cell_in_build_region(ivec3 cellCoord) {
    int buildRegionCells = max(ph_regir_build_region_cells, 1);
    ivec3 minCell = lt_debug_regir_build_region_min_cell();
    ivec3 maxCell = minCell + ivec3(buildRegionCells);
    return all(greaterThanEqual(cellCoord, minCell)) && all(lessThan(cellCoord, maxCell));
}

vec3 lt_debug_color_regir_coverage(RAB_Surface surface) {
    ivec3 cellCoord = ivec3(floor(surface.worldPos / max(ph_regir_hash_cell_size, 1.0e-6f)));
    int jitterCells = int(ceil(max(ph_regir_sampling_jitter, 0.0f) * 0.5f));
    ivec3 minCell = lt_debug_regir_build_region_min_cell();
    ivec3 maxCell = minCell + ivec3(max(ph_regir_build_region_cells, 1));
    bool insideNominal = all(greaterThanEqual(cellCoord, minCell)) && all(lessThan(cellCoord, maxCell));
    bool insideExpanded = all(greaterThanEqual(cellCoord, minCell - ivec3(jitterCells)))
        && all(lessThan(cellCoord, maxCell + ivec3(jitterCells)));

    if (insideNominal) {
        return vec3(0.0f, 1.0f, 0.0f);
    }
    if (insideExpanded) {
        return vec3(1.0f, 1.0f, 0.0f);
    }
    return vec3(1.0f, 0.0f, 0.0f);
}

float lt_debug_regir_grid_line_alpha(vec3 worldPos, vec3 surfaceNormal) {
    float cellSize = max(ph_regir_hash_cell_size, 1.0e-6f);
    vec3 cellUv = fract(worldPos / cellSize);
    vec3 edgeDistance = min(cellUv, vec3(1.0f) - cellUv);

    vec3 n = dot(surfaceNormal, surfaceNormal) > 1.0e-8f ? abs(normalize(surfaceNormal)) : vec3(0.0f, 1.0f, 0.0f);
    float nearestEdge;
    if (n.x >= n.y && n.x >= n.z) {
        nearestEdge = min(edgeDistance.y, edgeDistance.z);
    } else if (n.y >= n.z) {
        nearestEdge = min(edgeDistance.x, edgeDistance.z);
    } else {
        nearestEdge = min(edgeDistance.x, edgeDistance.y);
    }

    float lineWidth = clamp(max(max(fwidth(cellUv.x), fwidth(cellUv.y)), fwidth(cellUv.z)) * 2.0f, 0.025f, 0.12f);
    return 1.0f - smoothstep(lineWidth, lineWidth * 1.75f, nearestEdge);
}

int lt_debug_regir_built_bucket_count(ivec3 cellCoord) {
    int builtCount = 0;
    int bucketCount = min(max(ph_regir_hash_normal_buckets, 0), 32);
    for (int bucket = 0; bucket < bucketCount; bucket++) {
        if (regir_hash_lookup(cellCoord, bucket) >= 0) {
            builtCount++;
        }
    }
    return builtCount;
}

vec3 lt_debug_color_regir_grid_binding(RAB_Surface surface) {
    float cellSize = max(ph_regir_hash_cell_size, 1.0e-6f);
    ivec3 cellCoord = ivec3(floor(surface.worldPos / cellSize));
    vec3 surfaceNormal = RAB_GetSurfaceNormal(surface);
    int surfaceBucket = regir_clamp_normal_bucket(regir_normal_to_bucket(surfaceNormal));
    int surfaceSlot = regir_hash_lookup(cellCoord, surfaceBucket);
    int builtBuckets = lt_debug_regir_built_bucket_count(cellCoord);
    bool inBuildRegion = lt_debug_regir_cell_in_build_region(cellCoord);
    ivec2 pixel = lt_fragment_pixel_pos();
    RTXDI_RandomSamplerState debugRegirRng = RTXDI_InitReGIRLookupRandomSampler(
        uvec2(pixel),
        uint(frameCounter));
    int jitteredSlot = -1;
    bool jitteredHit = regir_resolve_cell(surface.worldPos, surfaceNormal, debugRegirRng, jitteredSlot);

    float jitteredSlotHash = (jitteredSlot >= 0)
        ? fract(float(jitteredSlot) * 0.00006103515625f)
        : 0.0f;
    vec3 builtForSurface = mix(vec3(0.02f, 0.16f, 1.0f), vec3(0.0f, 0.78f, 1.0f), jitteredSlotHash);
    vec3 builtForOtherNormal = vec3(0.16f, 0.06f, 0.82f);
    vec3 missingCell = vec3(0.92f, 0.04f, 0.02f);
    vec3 outsideBuild = vec3(0.22f, 0.0f, 0.0f);

    vec3 baseColor = missingCell;
    if (jitteredHit) {
        baseColor = builtForSurface;
    } else if (surfaceSlot >= 0) {
        baseColor = vec3(0.0f, 0.34f, 0.88f);
    } else if (builtBuckets > 0) {
        baseColor = builtForOtherNormal;
    }
    if (!inBuildRegion) {
        baseColor = mix(baseColor, outsideBuild, 0.72f);
    }

    float lineAlpha = lt_debug_regir_grid_line_alpha(surface.worldPos, surfaceNormal);
    vec3 lineColor = jitteredHit ? vec3(0.0f, 0.65f, 1.0f) : vec3(1.0f, 0.18f, 0.02f);
    return mix(baseColor, lineColor, lineAlpha);
}

bool lt_debug_load_selected_light_sample(
    ivec2 reservoirPos,
    RAB_Surface surface,
    out RTXDI_DIReservoir reservoir,
    out RAB_LightSample lightSample
) {
    RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    reservoir = RTXDI_LoadDIReservoir(
        restirDI.reservoirBufferParams,
        uvec2(reservoirPos),
        lt_get_final_shading_input_buffer_index()
    );
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        lightSample = RAB_EmptyLightSample();
        return false;
    }

    RAB_LightInfo lightInfo = RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(reservoir), false);
    lightSample = RAB_SamplePolymorphicLight(
        lightInfo,
        surface,
        RTXDI_GetDIReservoirSampleUV(reservoir)
    );
    return lightSample.index >= 0 && lightSample.solidAnglePdf > 0.0f;
}

vec3 lt_debug_color_visibility_classification(ivec2 reservoirPos, RAB_Surface surface) {
    RTXDI_DIReservoir reservoir;
    RAB_LightSample lightSample;
    if (!lt_debug_load_selected_light_sample(reservoirPos, surface, reservoir, lightSample)) {
        return vec3(0.2f, 0.0f, 0.4f);
    }

    float hitDist = 0.0f;
    vec3 tracedVisibility = lt_trace_final_visibility_with_offset(lightSample, surface, 0.01f, hitDist);
    float distanceT = clamp(log2(hitDist + 1.0f) / log2(129.0f), 0.0f, 1.0f);

    if (ray.result_hit) {
        return vec3(1.0f, 0.15f + 0.85f * distanceT, 0.0f);
    }

    if (ray_distance_limit_reached) {
        float transmittance = clamp(ph_luminance(tracedVisibility), 0.0f, 1.0f);
        return mix(vec3(0.0f, 1.0f, 1.0f), vec3(0.0f, 1.0f, 0.0f), transmittance);
    }

    return vec3(1.0f, 0.0f, 1.0f);
}

vec3 lt_debug_color_selected_light_distance(ivec2 reservoirPos, RAB_Surface surface) {
    RTXDI_DIReservoir reservoir;
    RAB_LightSample lightSample;
    if (!lt_debug_load_selected_light_sample(reservoirPos, surface, reservoir, lightSample)) {
        return vec3(0.2f, 0.0f, 0.4f);
    }

    float lightDistance = length(lightSample.position + world_offset - surface.worldPos);
    float t = clamp(log2(lightDistance + 1.0f) / log2(129.0f), 0.0f, 1.0f);
    return lt_debug_heat_ramp(t);
}

vec3 lt_debug_color_reservoir_inv_pdf(ivec2 reservoirPos) {
    RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    RTXDI_DIReservoir reservoir = RTXDI_LoadDIReservoir(
        restirDI.reservoirBufferParams,
        uvec2(reservoirPos),
        lt_get_final_shading_input_buffer_index()
    );
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        return vec3(0.2f, 0.0f, 0.4f);
    }

    float invPdf = RTXDI_GetDIReservoirInvPdf(reservoir);
    return lt_debug_heat_ramp(lt_debug_encode_positive_metric(invPdf, 1024.0f));
}

vec3 lt_debug_color_reservoir_target_pdf(ivec2 reservoirPos) {
    RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    RTXDI_DIReservoir reservoir = RTXDI_LoadDIReservoir(
        restirDI.reservoirBufferParams,
        uvec2(reservoirPos),
        lt_get_final_shading_input_buffer_index()
    );
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        return vec3(0.2f, 0.0f, 0.4f);
    }

    return lt_debug_heat_ramp(lt_debug_encode_small_pdf(reservoir.targetPdf));
}

vec3 lt_debug_color_selected_solid_angle_pdf(ivec2 reservoirPos, RAB_Surface surface) {
    RTXDI_DIReservoir reservoir;
    RAB_LightSample lightSample;
    if (!lt_debug_load_selected_light_sample(reservoirPos, surface, reservoir, lightSample)) {
        return vec3(0.2f, 0.0f, 0.4f);
    }

    return lt_debug_heat_ramp(lt_debug_encode_small_pdf(lightSample.solidAnglePdf));
}

vec3 lt_debug_color_selected_incident_radiance(ivec2 reservoirPos, RAB_Surface surface) {
    RTXDI_DIReservoir reservoir;
    RAB_LightSample lightSample;
    if (!lt_debug_load_selected_light_sample(reservoirPos, surface, reservoir, lightSample)) {
        return vec3(0.2f, 0.0f, 0.4f);
    }

    float incidentLuma = ph_luminance(max(lt_light_sample_incident_radiance(surface, lightSample), vec3(0.0f)));
    return lt_debug_heat_ramp(lt_debug_encode_positive_metric(incidentLuma, 64.0f));
}

vec3 lt_debug_color_selected_brdf_response(ivec2 reservoirPos, RAB_Surface surface) {
    RTXDI_DIReservoir reservoir;
    RAB_LightSample lightSample;
    if (!lt_debug_load_selected_light_sample(reservoirPos, surface, reservoir, lightSample)) {
        return vec3(0.2f, 0.0f, 0.4f);
    }

    LightBrdf brdf = lt_evaluate_surface_brdf(surface, lightSample.dir);
    float brdfLuma = ph_luminance(max(brdf.demodulatedDiffuse * surface.material.diffuseAlbedo + brdf.specular, vec3(0.0f)));
    return lt_debug_heat_ramp(lt_debug_encode_positive_metric(brdfLuma, 4.0f));
}

#endif // PHOTONICS_LT_DEBUG_GLSL
