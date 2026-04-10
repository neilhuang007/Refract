#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_diffuse_frag_out;
layout(location = 1) out vec4 direct_specular_frag_out;
layout(location = 2) out vec4 reservoir_frag_out;
layout(location = 3) out vec4 reservoir_sample_frag_out;
layout(location = 4) out vec4 reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D direct_initial_debug_input;

const float ph_nrd_spec_fp16_safe_luma = 248.0;

vec3 ph_clamp_specular_for_relax(vec3 demodulatedSpecular) {
    demodulatedSpecular = max(demodulatedSpecular, vec3(0.0));
    float specularLuma = nrd_luminance(demodulatedSpecular);
    if (specularLuma > ph_nrd_spec_fp16_safe_luma) {
        demodulatedSpecular *= ph_nrd_spec_fp16_safe_luma / max(specularLuma, 1e-6);
    }
    return demodulatedSpecular;
}

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

vec3 lt_debug_color_initial_reason(int reason) {
    switch (reason) {
        case 0: return vec3(0.0f);
        case 1: return vec3(0.7f, 0.7f, 0.0f);
        case 2: return vec3(1.0f, 0.5f, 0.0f);
        case 3: return vec3(1.0f, 0.0f, 1.0f);
        case 4: return vec3(1.0f, 0.0f, 0.0f);
        case 5: return vec3(0.8f, 0.2f, 0.2f);
        case 6: return vec3(0.2f, 0.4f, 1.0f);
        case 7: return vec3(1.0f, 1.0f, 0.0f);
        case 8: return vec3(0.0f, 1.0f, 1.0f);
        case 9: return vec3(0.6f, 0.0f, 1.0f);
        case 10: return vec3(0.0f, 1.0f, 0.0f);
        default: return vec3(1.0f, 0.0f, 1.0f);
    }
}

vec3 lt_debug_color_regir_coverage(RAB_Surface surface) {
    float nominalHalfExtent = float(ph_regir_grid_cells.x) * ph_regir_cell_size * 0.5f;
    float jitterMargin = ph_regir_sampling_jitter * ph_regir_cell_size * 0.5f;
    vec3 delta = abs(surface.worldPos - ph_regir_grid_center);
    bool insideNominal = all(lessThanEqual(delta, vec3(nominalHalfExtent)));
    bool insideExpanded = all(lessThanEqual(delta, vec3(nominalHalfExtent + jitterMargin)));

    if (insideNominal) {
        return vec3(0.0f, 1.0f, 0.0f);
    }
    if (insideExpanded) {
        return vec3(1.0f, 1.0f, 0.0f);
    }
    return vec3(1.0f, 0.0f, 0.0f);
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
        restirDI.bufferIndices.shadingInputBufferIndex
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
        restirDI.bufferIndices.shadingInputBufferIndex
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
        restirDI.bufferIndices.shadingInputBufferIndex
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

void storeEmptyShadeOutputs() {
    direct_diffuse_frag_out = vec4(0.0f);
    direct_specular_frag_out = vec4(0.0f);
}

void storeDIReservoir(RTXDI_DIReservoir reservoir) {
    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(reservoir);
}

ivec2 lt_get_checkerboard_shading_pixel(ivec2 pixelPosition, int activeCheckerboardField) {
    ivec2 shadingPixel = pixelPosition;
    RTXDI_ActivateCheckerboardPixel(shadingPixel, false, activeCheckerboardField);
    shadingPixel.x = clamp(shadingPixel.x, 0, int(viewWidth) - 1);
    shadingPixel.y = clamp(shadingPixel.y, 0, int(viewHeight) - 1);
    return shadingPixel;
}

void main() {
    const RTXDI_RuntimeParameters params = lt_build_runtime_parameters();
    ivec2 pixelPosition = lt_fragment_pixel_pos();
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        storeEmptyShadeOutputs();
        storeDIReservoir(RTXDI_EmptyDIReservoir());
        return;
    }

    RAB_Surface pixelSurface = RAB_GetGBufferSurface(pixelPosition, false);
    if (!RAB_IsSurfaceValid(pixelSurface)) {
        storeEmptyShadeOutputs();
        storeDIReservoir(RTXDI_EmptyDIReservoir());
        return;
    }

    if (ph_debug_view_mode > 0.5f) {
        int debugMode = int(ph_debug_view_mode + 0.5f);
        vec3 debugColor = vec3(1.0f, 0.0f, 1.0f);

        if (debugMode == 1) {
            float dist = length(pixelSurface.worldPos - ph_regir_grid_center);
            float t = clamp(dist / 256.0f, 0.0f, 1.0f);
            debugColor = lt_debug_heat_ramp(t);
        } else if (debugMode == 2) {
            ivec3 cellCoord;
            bool inside = regir_world_to_cell(pixelSurface.worldPos, cellCoord);
            debugColor = inside ? vec3(0.0f, 1.0f, 0.0f) : vec3(1.0f, 0.0f, 0.0f);
        } else if (debugMode == 3) {
            ivec3 cellCoord;
            bool inside = regir_world_to_cell(pixelSurface.worldPos, cellCoord);
            debugColor = inside ? vec3(cellCoord) / vec3(ph_regir_grid_cells) : vec3(0.0f);
        } else if (debugMode == 4) {
            debugColor = lt_debug_color_regir_coverage(pixelSurface);
        } else if (debugMode == 5) {
            ivec2 reservoirPos = lt_debug_reservoir_pos_for_pixel(pixelPosition, int(params.activeCheckerboardField));
            vec4 initialDebug = texelFetch(direct_initial_debug_input, reservoirPos, 0);
            int reason = int(round(initialDebug.x));
            float proposalValid = clamp(initialDebug.z, 0.0f, 1.0f);
            float candidateFraction = clamp(initialDebug.y, 0.0f, 1.0f);
            debugColor = clamp(
                lt_debug_color_initial_reason(reason) * (0.35f + 0.65f * proposalValid) + vec3(0.1f * candidateFraction),
                vec3(0.0f),
                vec3(1.0f)
            );
        } else if (debugMode == 6) {
            ivec2 reservoirPos = lt_debug_reservoir_pos_for_pixel(pixelPosition, int(params.activeCheckerboardField));
            debugColor = lt_debug_color_visibility_classification(reservoirPos, pixelSurface);
        } else if (debugMode == 7) {
            ivec2 reservoirPos = lt_debug_reservoir_pos_for_pixel(pixelPosition, int(params.activeCheckerboardField));
            debugColor = lt_debug_color_selected_light_distance(reservoirPos, pixelSurface);
        } else if (debugMode == 8) {
            ivec2 reservoirPos = lt_debug_reservoir_pos_for_pixel(pixelPosition, int(params.activeCheckerboardField));
            debugColor = lt_debug_color_reservoir_inv_pdf(reservoirPos);
        } else if (debugMode == 9) {
            ivec2 reservoirPos = lt_debug_reservoir_pos_for_pixel(pixelPosition, int(params.activeCheckerboardField));
            debugColor = lt_debug_color_reservoir_target_pdf(reservoirPos);
        } else if (debugMode == 10) {
            ivec2 reservoirPos = lt_debug_reservoir_pos_for_pixel(pixelPosition, int(params.activeCheckerboardField));
            debugColor = lt_debug_color_selected_solid_angle_pdf(reservoirPos, pixelSurface);
        } else if (debugMode == 11) {
            ivec2 reservoirPos = lt_debug_reservoir_pos_for_pixel(pixelPosition, int(params.activeCheckerboardField));
            debugColor = lt_debug_color_selected_incident_radiance(reservoirPos, pixelSurface);
        } else if (debugMode == 12) {
            ivec2 reservoirPos = lt_debug_reservoir_pos_for_pixel(pixelPosition, int(params.activeCheckerboardField));
            debugColor = lt_debug_color_selected_brdf_response(reservoirPos, pixelSurface);
        }

        direct_diffuse_frag_out = vec4(debugColor, 1.0f);
        direct_specular_frag_out = vec4(0.0f);
        storeDIReservoir(RTXDI_EmptyDIReservoir());
        return;
    }

    bool isActiveCheckerboardPixel = RTXDI_IsActiveCheckerboardPixel(pixelPosition, false, int(params.activeCheckerboardField));
    if (!isActiveCheckerboardPixel) {
        storeEmptyShadeOutputs();
        storeDIReservoir(RTXDI_EmptyDIReservoir());
        return;
    }

    ivec2 shadingPixelPosition = pixelPosition;
    ivec2 GlobalIndex = RTXDI_PixelPosToReservoirPos(shadingPixelPosition, int(params.activeCheckerboardField));

    RAB_Surface surface = RAB_GetGBufferSurface(shadingPixelPosition, false);
    if (!RAB_IsSurfaceValid(surface)) {
        storeEmptyShadeOutputs();
        storeDIReservoir(RTXDI_EmptyDIReservoir());
        return;
    }

    const RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    const RTXDI_VisibilityReuseParameters visibilityReuseParams = lt_build_visibility_reuse_parameters();

    RTXDI_DIReservoir reservoir = RTXDI_LoadDIReservoir(
        restirDI.reservoirBufferParams,
        uvec2(GlobalIndex),
        restirDI.bufferIndices.shadingInputBufferIndex
    );

    vec3 shadedDiffuse = vec3(0.0f);
    vec3 shadedSpecular = vec3(0.0f);
    float directHitDistance = 0.0f;

    bool enableFinalVisibility = restirDI.shadingParams.enableFinalVisibility != 0u;
    bool reuseFinalVisibility = restirDI.shadingParams.reuseFinalVisibility != 0u;
    bool enableVisibilityTransmittance = true;
    bool discardIfInvisible = false;

    if (RTXDI_IsValidDIReservoir(reservoir))
    {
        RAB_LightInfo lightInfo = RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(reservoir), false);
        RAB_LightSample lightSample = RAB_SamplePolymorphicLight(
            lightInfo,
            surface,
            RTXDI_GetDIReservoirSampleUV(reservoir)
        );

        if (!enableFinalVisibility) {
            if (lightSample.index >= 0 && lightSample.solidAnglePdf > 0.0f) {
                lightSample.color *= RTXDI_GetDIReservoirInvPdf(reservoir) / lightSample.solidAnglePdf;
                LtSplitRadiance splitShade = lt_shade_surface_split(surface, lightSample);
                shadedDiffuse = splitShade.diffuse;
                shadedSpecular = splitShade.specular;
                directHitDistance = length(lightSample.position + world_offset - surface.worldPos);
            }
        } else {
            vec3 visibility = vec3(0.0f);
            bool hasStoredVisibility = reuseFinalVisibility && RTXDI_GetDIReservoirVisibility(reservoir, visibilityReuseParams, visibility);

            if (!enableVisibilityTransmittance && hasStoredVisibility && rtxdi_is_visible(reservoir)) {
                visibility = vec3(1.0f);
            }

            if (hasStoredVisibility && rtxdi_is_visible(reservoir)) {
                if (lightSample.index >= 0 && lightSample.solidAnglePdf > 0.0f) {
                    lightSample.color *= visibility * (RTXDI_GetDIReservoirInvPdf(reservoir) / lightSample.solidAnglePdf);
                    LtSplitRadiance splitShade = lt_shade_surface_split(surface, lightSample);
                    shadedDiffuse = splitShade.diffuse;
                    shadedSpecular = splitShade.specular;
                    directHitDistance = length(lightSample.position + world_offset - surface.worldPos);
                }
            } else if (lightSample.index >= 0 && lightSample.solidAnglePdf > 0.0f) {
                float hitDist = 0.0f;
                vec3 tracedVisibility = lt_trace_final_visibility_with_offset(lightSample, surface, 0.01f, hitDist);
                bool isVisible = ph_luminance(tracedVisibility) > 0.0f && lightSample.index >= 0;
                vec3 storedVisibility = enableVisibilityTransmittance ? tracedVisibility : (isVisible ? vec3(1.0f) : vec3(0.0f));
                RTXDI_StoreVisibilityInDIReservoir(reservoir, storedVisibility, discardIfInvisible);

                if (isVisible) {
                    vec3 shadingVisibility = enableVisibilityTransmittance ? tracedVisibility : storedVisibility;
                    lightSample.color *= shadingVisibility * (RTXDI_GetDIReservoirInvPdf(reservoir) / lightSample.solidAnglePdf);
                    LtSplitRadiance splitShade = lt_shade_surface_split(surface, lightSample);
                    shadedDiffuse = splitShade.diffuse;
                    shadedSpecular = splitShade.specular;
                    directHitDistance = length(lightSample.position + world_offset - surface.worldPos);
                }
            }
        }
    }

    if (restirDI.shadingParams.enableDenoiserInputPacking != 0u) {
        vec3 demodSpecular = shadedSpecular / max(vec3(0.01f), surface.material.specularF0);
        demodSpecular = ph_clamp_specular_for_relax(demodSpecular);
        direct_diffuse_frag_out = nrd_pack_direct_signal(shadedDiffuse, directHitDistance);
        direct_specular_frag_out = nrd_pack_direct_signal(demodSpecular, directHitDistance);
    } else {
        direct_diffuse_frag_out = vec4(shadedDiffuse, directHitDistance);
        direct_specular_frag_out = vec4(shadedSpecular, directHitDistance);
    }

    if (isActiveCheckerboardPixel) {
        storeDIReservoir(reservoir);
    } else {
        storeDIReservoir(RTXDI_EmptyDIReservoir());
    }
}
