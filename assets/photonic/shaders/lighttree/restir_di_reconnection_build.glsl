#ifndef PHOTONICS_RESTIR_DI_RECONNECTION_BUILD_GLSL
#define PHOTONICS_RESTIR_DI_RECONNECTION_BUILD_GLSL

float scatter_resolve_light_pdf(RTXDI_DIReservoir reservoir, RAB_LightSample lightSample)
{
    if (!RTXDI_IsValidDIReservoir(reservoir) || lightSample.index < 0) {
        return 0.0f;
    }

    return max(lightSample.solidAnglePdf, 0.0f);
}

vec3 scatter_resolve_visibility(RTXDI_DIReservoir reservoir)
{
    return max(rtxdi_unpack_visibility(reservoir.packedVisibility), vec3(0.0f));
}

vec3 scatter_resolve_irradiance(
    RAB_Surface surface,
    RTXDI_DIReservoir reservoir,
    RAB_LightSample lightSample)
{
    if (!RTXDI_IsValidDIReservoir(reservoir) || lightSample.index < 0) {
        return vec3(0.0f);
    }

    return max(
        lt_light_sample_incident_radiance(surface, lightSample)
            * scatter_resolve_visibility(reservoir),
        vec3(0.0f)
    );
}

vec3 scatter_resolve_early_throughput(
    RAB_Surface surface,
    RTXDI_DIReservoir reservoir,
    RAB_LightSample lightSample)
{
    if (!RTXDI_IsValidDIReservoir(reservoir) || lightSample.index < 0) {
        return vec3(0.0f);
    }

    return max(lt_surface_early_throughput(surface, lightSample), vec3(0.0f));
}

vec3 pathReconnectionShift(
    ReservoirSplattingReconnectionData reconnectionData,
    RAB_Surface shiftedSurface,
    RAB_LightSample shiftedLight)
{
    if (!RAB_IsSurfaceValid(shiftedSurface) || shiftedLight.index < 0) {
        return vec3(0.0f);
    }

    if (reconnectionData.pathLength == 1u) {
        return max(reconnectionData.irradiance, vec3(0.0f));
    }

    vec3 shiftedEarlyThroughput = lt_surface_early_throughput(shiftedSurface, shiftedLight);
    return max(shiftedEarlyThroughput * reconnectionData.irradiance, vec3(0.0f));
}

float scatter_resolve_secondary_path_jacobian_from_reconnection(
    RAB_Surface surface,
    RAB_LightSample lightSample,
    vec3 secondPos,
    vec3 earlyThroughput,
    vec3 irradiance)
{
    surface = surface;
    secondPos = secondPos;
    earlyThroughput = earlyThroughput;
    irradiance = irradiance;

    if (lightSample.index < 0) {
        return 1.0f;
    }

    return max(lightSample.solidAnglePdf, 1e-10f);
}

float scatter_resolve_secondary_path_jacobian(
    RAB_Surface surface,
    RTXDI_DIReservoir reservoir,
    RAB_LightSample lightSample)
{
    if (lightSample.index < 0) {
        return 1.0f;
    }

    vec3 secondPos = lightSample.position;
    vec3 earlyThroughput = scatter_resolve_early_throughput(surface, reservoir, lightSample);
    vec3 irradiance = scatter_resolve_irradiance(surface, reservoir, lightSample);
    return scatter_resolve_secondary_path_jacobian_from_reconnection(
        surface,
        lightSample,
        secondPos,
        earlyThroughput,
        irradiance
    );
}

vec2 scatter_resolve_reservoir_subpixel(RTXDI_DIReservoir reservoir, ivec2 pixelPosition)
{
    return PathReservoir_getSubPixel(reservoir, pixelPosition);
}

uint scatter_resolve_first_bsdf_component_type(RAB_Surface surface)
{
    return lt_surface_diffuse_probability(surface) >= 0.5f
        ? SCATTER_BSDF_COMPONENT_DIFFUSE
        : SCATTER_BSDF_COMPONENT_SPECULAR;
}

uint scatter_resolve_second_bsdf_component_type(RAB_LightSample lightSample)
{
    return lightSample.index >= 0 ? SCATTER_BSDF_COMPONENT_DIFFUSE : 0u;
}

uint scatter_resolve_reconnection_flags(RAB_LightSample lightSample)
{
    uint flags = 0u;
    if (RAB_IsAnalyticLightSample(lightSample)) {
        flags |= SCATTER_RECONNECTION_FLAG_LIGHT_IS_NEE;
    } else if (lightSample.solidAnglePdf > 0.0f
        && ph_luminance(max(lightSample.color, vec3(0.0f))) > 0.0f)
    {
        flags |= SCATTER_RECONNECTION_FLAG_LIGHT_IS_DISTANT;
    }

    return flags;
}

ReservoirSplattingReconnectionData ReconnectionData_build(
    RAB_Surface surface,
    RTXDI_DIReservoir reservoir,
    RAB_LightSample lightSample,
    ivec2 pixelPosition,
    float time,
    float confidenceIgnored,
    float subPixelJacobian,
    vec3 irradiance,
    vec3 earlyThroughput)
{
    ReservoirSplattingReconnectionData d = ReservoirSplattingReconnectionData_init();
    vec4 identityData = scatter_load_surface_identity(pixelPosition, false);
    irradiance = max(irradiance, vec3(0.0f));
    earlyThroughput = max(earlyThroughput, vec3(0.0f));
    vec3 secondPos = (lightSample.index >= 0) ? lightSample.position : surface.worldPos;
    bool lightIsAnalytic = (lightSample.index >= 0) && RAB_IsAnalyticLightSample(lightSample);

    d.subPixel = PathReservoir_getSubPixel(reservoir, pixelPosition);
    d.lensSample = lt_area_has_valid_domain(reservoir)
        ? clamp(reservoir.lensSampleUV, vec2(0.0f), vec2(1.0f))
        : lt_area_default_lens_sample();
    d.time = clamp(time, 0.0f, 1.0f);

    d.pathLength = (lightSample.index >= 0) ? 2u : 1u;

    d.firstHit.worldPos = surface.worldPos;
    d.firstHit.viewDepth = surface.viewDepth;
    d.firstHit.faceId = uint(round(identityData.w));
    d.firstBSDFComponentType = scatter_resolve_first_bsdf_component_type(surface);
    d.firstWi = normalize(world_camera_position - surface.worldPos);

    d.secondHit.worldPos = secondPos;
    d.secondHit.viewDepth = surface.viewDepth;
    d.secondHit.faceId = uint(round(identityData.w));
    d.secondBSDFComponentType = scatter_resolve_second_bsdf_component_type(lightSample);
    d.secondWo = (lightSample.index >= 0 && distance(secondPos, surface.worldPos) > 1e-6f)
        ? normalize(secondPos - surface.worldPos)
        : vec3(0.0f);

    d.transmissionEvent = false;
    d.lightIsNEE = lightIsAnalytic;
    d.lightIsDistant = (lightSample.index >= 0) && !lightIsAnalytic;
    d.lightPdf = scatter_resolve_light_pdf(reservoir, lightSample);

    d.subPixelJacobian = max(subPixelJacobian, 1e-10f);
    d.lensVertexJacobian = 1.0f;
    d.secondaryPathJacobian = scatter_resolve_secondary_path_jacobian_from_reconnection(
        surface,
        lightSample,
        secondPos,
        earlyThroughput,
        irradiance
    );
    d.irradiance = irradiance;
    d.earlyThroughput = earlyThroughput;

    return d;
}

ReservoirSplattingReconnectionData ReconnectionData_build(
    RAB_Surface surface,
    RTXDI_DIReservoir reservoir,
    RAB_LightSample lightSample,
    ivec2 pixelPosition,
    float time,
    float confidenceIgnored,
    float subPixelJacobian)
{
    return ReconnectionData_build(
        surface,
        reservoir,
        lightSample,
        pixelPosition,
        time,
        confidenceIgnored,
        subPixelJacobian,
        scatter_resolve_irradiance(surface, reservoir, lightSample),
        scatter_resolve_early_throughput(surface, reservoir, lightSample)
    );
}

#endif
