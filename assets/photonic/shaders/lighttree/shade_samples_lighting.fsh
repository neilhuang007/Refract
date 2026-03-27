#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_diffuse_frag_out;
layout(location = 1) out vec4 direct_specular_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform float ph_restir_enable_final_visibility;
uniform float ph_restir_reuse_final_visibility;
uniform float ph_restir_enable_denoiser_packing;
uniform float ph_restir_temporal_visibility_shortcut;

void storeEmptyShadeOutputs() {
    direct_diffuse_frag_out = vec4(0.0f);
    direct_specular_frag_out = vec4(0.0f);
}

void main() {
    ivec2 pixelPosition = tex_coord;
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        storeEmptyShadeOutputs();
        return;
    }

    if (!RTXDI_IsActiveCheckerboardPixel(pixelPosition, false, ph_restir_active_checkerboard_field)) {
        storeEmptyShadeOutputs();
        return;
    }

    DirectSurface currentSurface = lt_load_surface(pixelPosition);
    if (!lt_is_valid_surface(currentSurface)) {
        storeEmptyShadeOutputs();
        return;
    }

    ivec2 reservoirPos = RTXDI_PixelPosToReservoirPos(pixelPosition, ph_restir_active_checkerboard_field);
    Reservoir reservoir = rtxdi_empty_reservoir();
    rtxdi_unpack_reservoir_at_surface(
        reservoir,
        texelFetch(radiosity_reservoirs, reservoirPos, 0),
        texelFetch(radiosity_reservoir_samples, reservoirPos, 0),
        texelFetch(radiosity_reservoir_meta, reservoirPos, 0),
        currentSurface,
        false
    );

    vec3 shadedDiffuse = vec3(0.0f);
    vec3 shadedSpecular = vec3(0.0f);
    float directHitDistance = 0.0f;

    bool enableFinalVisibility = (ph_restir_enable_final_visibility < -1.5) ? false : true;
    bool reuseFinalVisibility = (ph_restir_reuse_final_visibility < -1.5) ? false : true;
    bool discardIfInvisible = (ph_restir_temporal_visibility_shortcut < -0.5)
        ? false
        : (ph_restir_temporal_visibility_shortcut >= 0.5);

    bool hasValidReservoir = RTXDI_IsValidDIReservoir(reservoir) && reservoir.weightSum > 0.0f;
    if (hasValidReservoir) {
        if (!enableFinalVisibility) {
            LightSample shadeSample = light_sample_decode(reservoir, currentSurface, false);
            if (shadeSample.index >= 0 && shadeSample.solidAnglePdf > 0.0f) {
                shadeSample.color *= RTXDI_GetDIReservoirInvPdf(reservoir) / shadeSample.solidAnglePdf;
                LtSplitRadiance splitShade = lt_shade_surface_split(currentSurface, shadeSample);
                shadedDiffuse = splitShade.diffuse;
                shadedSpecular = splitShade.specular;
                directHitDistance = length(shadeSample.position + world_offset - currentSurface.worldPos);
            }
        } else if (reuseFinalVisibility && rtxdi_has_reusable_visibility(reservoir)) {
            vec3 visRgb = rtxdi_get_visibility(reservoir);
            if (rtxdi_is_visible(reservoir)) {
                LightSample shadeSample = light_sample_decode(reservoir, currentSurface, false);
                if (shadeSample.index >= 0 && shadeSample.solidAnglePdf > 0.0f) {
                    shadeSample.color *= visRgb * (RTXDI_GetDIReservoirInvPdf(reservoir) / shadeSample.solidAnglePdf);
                    LtSplitRadiance splitShade = lt_shade_surface_split(currentSurface, shadeSample);
                    shadedDiffuse = splitShade.diffuse;
                    shadedSpecular = splitShade.specular;
                    directHitDistance = length(shadeSample.position + world_offset - currentSurface.worldPos);
                }
            }
        } else {
            LightSample traceSample = light_sample_decode(reservoir, currentSurface, false);
            if (traceSample.index >= 0) {
                // RTXDI GetFinalVisibility uses a 0.01 ray offset for final shading.
                float hitDist = 0.0f;
                vec3 visRgb = lt_trace_final_visibility_with_offset(traceSample, currentSurface, 0.01f, hitDist);
                bool isVisible = ph_luminance(visRgb) > 0.0f && traceSample.index >= 0;
                RTXDI_StoreVisibilityInDIReservoir(reservoir, visRgb, discardIfInvisible);
                if (isVisible && traceSample.solidAnglePdf > 0.0f) {
                    traceSample.color *= visRgb * (RTXDI_GetDIReservoirInvPdf(reservoir) / traceSample.solidAnglePdf);
                    LtSplitRadiance splitShade = lt_shade_surface_split(currentSurface, traceSample);
                    shadedDiffuse = splitShade.diffuse;
                    shadedSpecular = splitShade.specular;
                    directHitDistance = length(traceSample.position + world_offset - currentSurface.worldPos);
                }
            }
        }
    }

    if (ph_restir_enable_denoiser_packing >= 0.5f) {
        vec3 N = currentSurface.shadingNormal;
        vec3 V = normalize(world_camera_position - currentSurface.worldPos);
        float roughness = clamp(currentSurface.material.x, 0.0, 1.0);
        float metallic = clamp(currentSurface.material.y, 0.0, 1.0);
        vec3 Rf0 = mix(vec3(0.04), clamp(currentSurface.albedo, vec3(0.0), vec3(1.0)), metallic);
        vec3 diffDemod, specDemod;
        nrd_material_factors(N, V, currentSurface.albedo, Rf0, roughness, diffDemod, specDemod);
        direct_diffuse_frag_out = nrd_pack_direct_signal(nrd_safe_demodulate(shadedDiffuse, diffDemod), directHitDistance);
        direct_specular_frag_out = nrd_pack_direct_signal(nrd_safe_demodulate(shadedSpecular, specDemod), directHitDistance);
    } else {
        direct_diffuse_frag_out = vec4(shadedDiffuse, directHitDistance);
        direct_specular_frag_out = vec4(shadedSpecular, directHitDistance);
    }
}
