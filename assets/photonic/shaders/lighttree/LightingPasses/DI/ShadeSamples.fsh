#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_diffuse_frag_out;
layout(location = 1) out vec4 direct_specular_frag_out;
layout(location = 2) out vec4 reservoir_frag_out;
layout(location = 3) out vec4 reservoir_sample_frag_out;
layout(location = 4) out vec4 reservoir_meta_frag_out;
layout(location = 5) out vec4 direct_combined_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/restir_di_resolve.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

#include "/photonics/lighttree/lt_debug.glsl"

void storeEmptyShadeOutputs() {
    direct_diffuse_frag_out = vec4(0.0f);
    direct_specular_frag_out = vec4(0.0f);
    direct_combined_frag_out = vec4(0.0f);
}

void storeDIReservoir(RTXDI_DIReservoir reservoir) {
    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = PathReservoir_packMeta(reservoir);
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
    ivec2 pixel = lt_fragment_pixel_pos();
    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        storeEmptyShadeOutputs();
        storeDIReservoir(RTXDI_EmptyDIReservoir());
        return;
    }

    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);
    if (!RAB_IsSurfaceValid(surface)) {
        storeEmptyShadeOutputs();
        storeDIReservoir(RTXDI_EmptyDIReservoir());
        return;
    }

    if (ph_debug_view_mode > 0.5f) {
        int debugMode = int(ph_debug_view_mode + 0.5f);
        vec3 debugColor = vec3(1.0f, 0.0f, 1.0f);

        if (debugMode == 1) {
            float dist = length(surface.worldPos - ph_regir_grid_center);
            float t = clamp(dist / 256.0f, 0.0f, 1.0f);
            debugColor = lt_debug_heat_ramp(t);
        } else if (debugMode == 2) {
            // Hash-grid: hit/miss visualization. Green = cell built this frame, red = miss.
            int bucket = regir_normal_to_bucket(RAB_GetSurfaceNormal(surface));
            ivec3 cellCoord = ivec3(floor(surface.worldPos / ph_regir_hash_cell_size));
            int slot = regir_hash_lookup(cellCoord, bucket);
            debugColor = (slot >= 0) ? vec3(0.0f, 1.0f, 0.0f) : vec3(1.0f, 0.0f, 0.0f);
        } else if (debugMode == 3) {
            // Hash-grid: per-cell colour from the slot index, gives a stable
            // per-cell hue that lets you see cell boundaries on surfaces.
            int bucket = regir_normal_to_bucket(RAB_GetSurfaceNormal(surface));
            ivec3 cellCoord = ivec3(floor(surface.worldPos / ph_regir_hash_cell_size));
            int slot = regir_hash_lookup(cellCoord, bucket);
            if (slot < 0) {
                debugColor = vec3(0.0f);
            } else {
                float h = float(slot) / float(max(ph_regir_hash_table_size, 1));
                debugColor = vec3(fract(h * 13.0), fract(h * 47.0), fract(h * 91.0));
            }
        } else if (debugMode == 4) {
            debugColor = lt_debug_color_regir_coverage(surface);
        } else if (debugMode == 6) {
            ivec2 reservoirPos = lt_debug_reservoir_pos_for_pixel(pixel, int(params.activeCheckerboardField));
            debugColor = lt_debug_color_visibility_classification(reservoirPos, surface);
        } else if (debugMode == 7) {
            ivec2 reservoirPos = lt_debug_reservoir_pos_for_pixel(pixel, int(params.activeCheckerboardField));
            debugColor = lt_debug_color_selected_light_distance(reservoirPos, surface);
        } else if (debugMode == 8) {
            ivec2 reservoirPos = lt_debug_reservoir_pos_for_pixel(pixel, int(params.activeCheckerboardField));
            debugColor = lt_debug_color_reservoir_inv_pdf(reservoirPos);
        } else if (debugMode == 9) {
            ivec2 reservoirPos = lt_debug_reservoir_pos_for_pixel(pixel, int(params.activeCheckerboardField));
            debugColor = lt_debug_color_reservoir_target_pdf(reservoirPos);
        } else if (debugMode == 10) {
            ivec2 reservoirPos = lt_debug_reservoir_pos_for_pixel(pixel, int(params.activeCheckerboardField));
            debugColor = lt_debug_color_selected_solid_angle_pdf(reservoirPos, surface);
        } else if (debugMode == 11) {
            ivec2 reservoirPos = lt_debug_reservoir_pos_for_pixel(pixel, int(params.activeCheckerboardField));
            debugColor = lt_debug_color_selected_incident_radiance(reservoirPos, surface);
        } else if (debugMode == 12) {
            ivec2 reservoirPos = lt_debug_reservoir_pos_for_pixel(pixel, int(params.activeCheckerboardField));
            debugColor = lt_debug_color_selected_brdf_response(reservoirPos, surface);
        } else if (debugMode == 13) {
            debugColor = lt_debug_color_regir_grid_binding(surface);
        }

        direct_diffuse_frag_out = vec4(debugColor, 1.0f);
        direct_specular_frag_out = vec4(0.0f);
        direct_combined_frag_out = vec4(debugColor, 1.0f);
        storeDIReservoir(RTXDI_EmptyDIReservoir());
        return;
    }

    bool isActiveCheckerboardPixel = RTXDI_IsActiveCheckerboardPixel(pixel, false, int(params.activeCheckerboardField));
    if (!isActiveCheckerboardPixel) {
        storeEmptyShadeOutputs();
        storeDIReservoir(RTXDI_EmptyDIReservoir());
        return;
    }

    ivec2 reservoirPosition = RTXDI_PixelPosToReservoirPos(pixel, int(params.activeCheckerboardField));

    RTXDI_DIReservoir currReservoir;
    ResolveReSTIR_load_curr_reservoir(reservoirPosition, currReservoir);
    if (!RTXDI_IsValidDIReservoir(currReservoir)) {
        storeEmptyShadeOutputs();
        storeDIReservoir(currReservoir);
        return;
    }

    ResolveReSTIRShading shading;
    if (!ResolveReSTIR_shade(currReservoir, surface, shading)) {
        storeEmptyShadeOutputs();
        storeDIReservoir(currReservoir);
        return;
    }

    vec3 demodulatedSpecular = shading.specular / max(lt_surface_f0(surface), vec3(0.01f));
    demodulatedSpecular = ph_clamp_specular_for_relax(demodulatedSpecular);

    vec3 diffuseSignal = nrd_clamp_direct_firefly(shading.diffuse);
    vec3 specularSignal = nrd_clamp_direct_firefly(demodulatedSpecular);
    vec3 combinedDirect =
        nrd_safe_remodulate(diffuseSignal, nrd_compute_diffuse_demodulation(surface.material.diffuseAlbedo)) +
        nrd_safe_remodulate(specularSignal, max(lt_surface_f0(surface), vec3(0.01f)));

    direct_diffuse_frag_out = nrd_pack_direct_signal(diffuseSignal, shading.hitDistance);
    direct_specular_frag_out = nrd_pack_direct_signal(specularSignal, shading.hitDistance);
    direct_combined_frag_out = vec4(clamp(combinedDirect, vec3(0.0f), vec3(NRD_FP16_MAX)), shading.hitDistance);

    storeDIReservoir(currReservoir);
}
