#ifndef PHOTONICS_RESTIR_DI_RESOLVE_GLSL
#define PHOTONICS_RESTIR_DI_RESOLVE_GLSL

// Reference stage 4 helper surface for ResolveReSTIR::execute.

#include "/photonics/lighttree/restir_di_bridge.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

void ResolveReSTIR_load_curr_reservoir(
    ivec2 reservoirPosition,
    out RTXDI_DIReservoir currReservoir)
{
    RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    currReservoir = RTXDI_LoadDIReservoir(
        restirDI.reservoirBufferParams,
        uvec2(reservoirPosition),
        lt_get_final_shading_input_buffer_index()
    );
}

float ResolveReSTIR_computeUCW(
    RTXDI_DIReservoir currReservoir)
{
    return PathReservoir_computeStoredUCW(currReservoir);
}

vec3 ResolveReSTIR(
    RTXDI_DIReservoir currReservoir)
{
    return PathReservoir_getIntegrand(currReservoir)
        * ResolveReSTIR_computeUCW(currReservoir);
}

struct ResolveReSTIRLobes
{
    vec3 diffuseDemodulated;
    vec3 specularDemodulated;
};

const float ResolveReSTIR_nrd_spec_fp16_safe_luma = 248.0f;

float ResolveReSTIR_surfaceMetalness(RAB_Surface surface)
{
    vec3 denominator = max(surface.material.diffuseAlbedo - vec3(0.04f), vec3(1e-4f));
    vec3 metalness = clamp(
        (surface.material.specularF0 - vec3(0.04f)) / denominator,
        vec3(0.0f),
        vec3(1.0f)
    );
    return clamp(ph_luminance(metalness), 0.0f, 1.0f);
}

vec3 ResolveReSTIR_diffuseDemodulation(RAB_Surface surface)
{
    return nrd_compute_diffuse_demodulation(surface.material.diffuseAlbedo);
}

vec3 ResolveReSTIR_specularDemodulation(RAB_Surface surface)
{
    return nrd_compute_specular_demodulation(
        surface.material.diffuseAlbedo,
        ResolveReSTIR_surfaceMetalness(surface)
    );
}

vec3 ResolveReSTIR_clampSpecularForRelax(vec3 demodulatedSpecular)
{
    demodulatedSpecular = max(demodulatedSpecular, vec3(0.0f));
    float specularLuma = nrd_luminance(demodulatedSpecular);
    if (specularLuma > ResolveReSTIR_nrd_spec_fp16_safe_luma)
    {
        demodulatedSpecular *= ResolveReSTIR_nrd_spec_fp16_safe_luma / max(specularLuma, 1e-6f);
    }
    return demodulatedSpecular;
}

ResolveReSTIRLobes ResolveReSTIR_fallbackDiffuseLobes(
    RAB_Surface surface,
    vec3 resolvedColor)
{
    ResolveReSTIRLobes lobes;
    lobes.diffuseDemodulated = nrd_safe_demodulate(
        max(resolvedColor, vec3(0.0f)),
        ResolveReSTIR_diffuseDemodulation(surface)
    );
    lobes.specularDemodulated = vec3(0.0f);
    return lobes;
}

ResolveReSTIRLobes ResolveReSTIR_splitForNRD(
    RAB_Surface surface,
    RTXDI_DIReservoir currReservoir)
{
    vec3 storedIntegrand = max(PathReservoir_getIntegrand(currReservoir), vec3(0.0f));
    float ucw = ResolveReSTIR_computeUCW(currReservoir);
    vec3 resolvedColor = storedIntegrand * ucw;

    if (!RAB_IsSurfaceValid(surface)
        || !RTXDI_IsValidDIReservoir(currReservoir)
        || ucw <= 0.0f
        || ph_luminance(storedIntegrand) <= 0.0f)
    {
        return ResolveReSTIR_fallbackDiffuseLobes(surface, resolvedColor);
    }

    // fast_random is diagnostic and stores incident radiance without the BRDF
    // decomposition needed for NRD lobe packing.
    if (ph_restir_local_light_sampling_mode == float(RTXDI_LOCAL_LIGHT_SAMPLING_FAST_RANDOM))
    {
        return ResolveReSTIR_fallbackDiffuseLobes(surface, resolvedColor);
    }

    RAB_LightSample lightSample = light_sample_decode(currReservoir, surface, false);
    if (lightSample.index < 0)
    {
        return ResolveReSTIR_fallbackDiffuseLobes(surface, resolvedColor);
    }

    LtSplitRadiance unshadowed = lt_shade_surface_split(surface, lightSample);
    vec3 unshadowedCombined =
        unshadowed.diffuse * surface.material.diffuseAlbedo
        + unshadowed.specular;
    float unshadowedLuma = ph_luminance(max(unshadowedCombined, vec3(0.0f)));
    if (unshadowedLuma <= 1e-6f)
    {
        return ResolveReSTIR_fallbackDiffuseLobes(surface, resolvedColor);
    }

    float storedLuma = ph_luminance(storedIntegrand);
    vec3 lumaScale = vec3(storedLuma / max(unshadowedLuma, 1e-6f));
    vec3 channelScale = storedIntegrand / max(unshadowedCombined, vec3(1e-6f));
    vec3 visibleScale = lumaScale;
    visibleScale.x = (unshadowedCombined.x > 1e-6f) ? channelScale.x : lumaScale.x;
    visibleScale.y = (unshadowedCombined.y > 1e-6f) ? channelScale.y : lumaScale.y;
    visibleScale.z = (unshadowedCombined.z > 1e-6f) ? channelScale.z : lumaScale.z;
    visibleScale = max(visibleScale, vec3(0.0f));

    vec3 visibleDiffuseDemodulated = unshadowed.diffuse * visibleScale * ucw;
    vec3 visibleSpecular = unshadowed.specular * visibleScale * ucw;

    ResolveReSTIRLobes lobes;
    lobes.diffuseDemodulated = max(visibleDiffuseDemodulated, vec3(0.0f));
    lobes.specularDemodulated = ResolveReSTIR_clampSpecularForRelax(
        nrd_safe_demodulate(
            max(visibleSpecular, vec3(0.0f)),
            ResolveReSTIR_specularDemodulation(surface)
        )
    );
    return lobes;
}

#endif
