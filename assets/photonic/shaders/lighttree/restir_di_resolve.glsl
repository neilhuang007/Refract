#ifndef PHOTONICS_RESTIR_DI_RESOLVE_GLSL
#define PHOTONICS_RESTIR_DI_RESOLVE_GLSL

// Reference stage module: ResolveReSTIR.cs.slang.

#include "/photonics/lighttree/restir_di_bridge.glsl"

struct ResolveReSTIRShading {
    vec3 diffuse;
    vec3 specular;
    float hitDistance;
};

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

vec3 ResolveReSTIR_safe_component_divide(vec3 numerator, vec3 denominator)
{
    return vec3(
        denominator.x > 0.0f ? numerator.x / denominator.x : 0.0f,
        denominator.y > 0.0f ? numerator.y / denominator.y : 0.0f,
        denominator.z > 0.0f ? numerator.z / denominator.z : 0.0f
    );
}

vec3 ResolveReSTIR_split_fraction(vec3 numerator, vec3 denominator)
{
    return clamp(
        ResolveReSTIR_safe_component_divide(max(numerator, vec3(0.0f)), max(denominator, vec3(0.0f))),
        vec3(0.0f),
        vec3(1.0f)
    );
}

vec3 ResolveReSTIR(
    RTXDI_DIReservoir currReservoir)
{
    // RTXDI final-visibility contract: integrand is unshadowed (Le * BRDF only),
    // packedVisibility carries the RGB transmittance from the visibility ray
    // (or vec3(1.0) when initial visibility was disabled). Multiply here so that
    // colored-glass tint, smoke transmittance, etc. reach the final color.
    vec3 visibility = rtxdi_get_visibility(currReservoir);
    return PathReservoir_getIntegrand(currReservoir)
        * ResolveReSTIR_computeUCW(currReservoir)
        * visibility;
}

bool ResolveReSTIR_shade(
    RTXDI_DIReservoir currReservoir,
    RAB_Surface surface,
    out ResolveReSTIRShading shading)
{
    shading.diffuse = vec3(0.0f);
    shading.specular = vec3(0.0f);
    shading.hitDistance = 0.0f;

    if (!RAB_IsSurfaceValid(surface) || !RTXDI_IsValidDIReservoir(currReservoir)) {
        return false;
    }

    float ucw = ResolveReSTIR_computeUCW(currReservoir);
    if (!(ucw > 0.0f) || isnan(ucw) || isinf(ucw)) {
        return false;
    }

    RAB_LightInfo lightInfo = RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(currReservoir), false);
    RAB_LightSample lightSample = RAB_SamplePolymorphicLight(
        lightInfo,
        surface,
        RTXDI_GetDIReservoirSampleUV(currReservoir)
    );
    lightSample.solidAnglePdf = lt_debug_resolve_solid_angle_pdf(lightSample.solidAnglePdf);
    if (lightSample.index < 0 || !(lightSample.solidAnglePdf > 0.0f)) {
        return false;
    }

    vec3 resolvedRadiance = max(ResolveReSTIR(currReservoir), vec3(0.0f));
    LtSplitRadiance splitRadiance = lt_shade_surface_split(surface, lightSample);
    vec3 diffuseCombined = max(splitRadiance.diffuse * surface.material.diffuseAlbedo, vec3(0.0f));
    vec3 specularCombined = max(splitRadiance.specular, vec3(0.0f));
    vec3 lobeCombined = diffuseCombined + specularCombined;
    vec3 diffuseFraction = ResolveReSTIR_split_fraction(diffuseCombined, lobeCombined);
    vec3 resolvedDiffuseCombined = resolvedRadiance * diffuseFraction;

    shading.diffuse = ResolveReSTIR_safe_component_divide(
        resolvedDiffuseCombined,
        max(surface.material.diffuseAlbedo, vec3(0.0f))
    );
    shading.specular = max(resolvedRadiance - resolvedDiffuseCombined, vec3(0.0f));
    shading.hitDistance = length(lightSample.position + world_offset - surface.worldPos);

    return !any(isnan(shading.diffuse))
        && !any(isnan(shading.specular))
        && !isnan(shading.hitDistance)
        && !isinf(shading.hitDistance);
}

bool ResolveReSTIR_execute(
    ivec2 reservoirPosition,
    RAB_Surface surface,
    out RTXDI_DIReservoir currReservoir,
    out ResolveReSTIRShading shading)
{
    ResolveReSTIR_load_curr_reservoir(reservoirPosition, currReservoir);
    return ResolveReSTIR_shade(currReservoir, surface, shading);
}

#endif
