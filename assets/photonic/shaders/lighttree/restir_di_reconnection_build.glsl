#ifndef PHOTONICS_RESTIR_DI_RECONNECTION_BUILD_GLSL
#define PHOTONICS_RESTIR_DI_RECONNECTION_BUILD_GLSL

#include "/photonics/lighttree/restir_di_temporal_dof.glsl"

float scatter_resolve_light_pdf(RTXDI_DIReservoir reservoir, RAB_LightSample lightSample)
{
    if (!RTXDI_IsValidDIReservoir(reservoir) || lightSample.index < 0) {
        return 0.0f;
    }

    return lightSample.solidAnglePdf;
}

vec3 scatter_resolve_visibility(RTXDI_DIReservoir reservoir)
{
    return rtxdi_unpack_visibility(reservoir.packedVisibility);
}

vec3 scatter_resolve_irradiance(
    RAB_Surface surface,
    RTXDI_DIReservoir reservoir,
    RAB_LightSample lightSample)
{
    if (!RTXDI_IsValidDIReservoir(reservoir) || lightSample.index < 0) {
        return vec3(0.0f);
    }

    return lt_light_sample_incident_radiance(surface, lightSample)
        * scatter_resolve_visibility(reservoir);
}

vec3 scatter_resolve_early_throughput(
    RAB_Surface surface,
    RTXDI_DIReservoir reservoir,
    RAB_LightSample lightSample)
{
    if (!RTXDI_IsValidDIReservoir(reservoir) || lightSample.index < 0) {
        return vec3(0.0f);
    }

    return lt_surface_early_throughput(surface, lightSample);
}

vec3 pathReconnectionShift(
    ReconnectionData reconnectionData,
    RAB_Surface shiftedSurface,
    RAB_LightSample shiftedLight)
{
    if (!RAB_IsSurfaceValid(shiftedSurface) || shiftedLight.index < 0) {
        return vec3(0.0f);
    }

    vec3 visibility = vec3(1.0f);
    if (ph_restir_local_light_sampling_mode != float(RTXDI_LOCAL_LIGHT_SAMPLING_FAST_RANDOM))
    {
        float visibilityHitDistance = 0.0f;
        visibility = lt_trace_final_visibility_with_offset(
            shiftedLight,
            shiftedSurface,
            0.0f,
            visibilityHitDistance
        );
    }

    vec3 shiftedIrradiance =
        lt_light_sample_incident_radiance(shiftedSurface, shiftedLight) * visibility;
    vec3 shiftedEarlyThroughput =
        (ph_restir_local_light_sampling_mode == float(RTXDI_LOCAL_LIGHT_SAMPLING_FAST_RANDOM))
            ? vec3(1.0f)
            : lt_surface_early_throughput(shiftedSurface, shiftedLight);
    return shiftedEarlyThroughput * shiftedIrradiance;
}

float scatter_resolve_secondary_path_jacobian_from_reconnection(
    RAB_Surface surface,
    RAB_LightSample lightSample,
    vec3 secondPos,
    vec3 earlyThroughput,
    vec3 irradiance)
{
    if (lightSample.index < 0) {
        return 1.0f;
    }

    return lightSample.solidAnglePdf;
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

vec3 scatter_resolve_camera_origin_at_time(float time, vec2 lensSample)
{
    vec3 cameraPos = lt_di_temporal_camera_pos_at_time(time);
    float apertureRadius = lt_di_temporal_camera_aperture_radius();
    if (apertureRadius <= 0.0f)
    {
        return cameraPos;
    }

    vec3 cameraU = normalize(lt_di_temporal_camera_u_at_time(time));
    vec3 cameraV = normalize(lt_di_temporal_camera_v_at_time(time));
    return cameraPos + apertureRadius * (lensSample.x * cameraU + lensSample.y * cameraV);
}

float scatter_resolve_subpixel_jacobian(
    RAB_Surface surface,
    float time,
    vec2 lensSample)
{
    vec3 cameraOrigin = scatter_resolve_camera_origin_at_time(time, lensSample);
    vec3 toPrimaryHit = surface.worldPos - cameraOrigin;
    float hitDistance = length(toPrimaryHit);
    if (hitDistance < 1e-6f)
    {
        return 1.0f;
    }

    vec3 rayDir = toPrimaryHit / hitDistance;
    float cosNormal = abs(dot(-rayDir, surface.geoNormal));
    float cosSensor = abs(dot(normalize(lt_di_temporal_camera_w_at_time(time)), rayDir));
    if (cosSensor < 1e-6f)
    {
        return 1.0f;
    }

    return cosNormal / (hitDistance * hitDistance * cosSensor * cosSensor * cosSensor);
}

ReconnectionData ReconnectionData_build(
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
    ReconnectionData d = ReconnectionData_init();
    vec4 identityData = scatter_load_surface_identity(pixelPosition, false);
    vec3 secondPos = (lightSample.index >= 0) ? lightSample.position : surface.worldPos;
    bool lightIsAnalytic = (lightSample.index >= 0) && RAB_IsAnalyticLightSample(lightSample);
    int reservoirLightIndex = RTXDI_GetReservoirLightIndexForFrame(reservoir, false, false);

    d.subPixel = scatter_resolve_reservoir_subpixel(reservoir, pixelPosition);
    d.lensSample = PathReservoir_getLensSample(reservoir);
    d.time = time;

    d.pathLength = (lightSample.index >= 0) ? 2u : 1u;

    d.firstHit.worldPos = surface.worldPos;
    d.firstHit.viewDepth = surface.viewDepth;
    uint packedIdentity = uint(round(identityData.w));
    d.firstHit.faceId = packedIdentity & 0x7u;
    d.firstHit.materialId = packedIdentity >> 3u;
    d.firstBSDFComponentType = scatter_resolve_first_bsdf_component_type(surface);
    vec3 firstRayOrigin = scatter_resolve_camera_origin_at_time(d.time, d.lensSample);
    vec3 firstWi = firstRayOrigin - surface.worldPos;
    float firstWiLengthSq = dot(firstWi, firstWi);
    d.firstWi = (firstWiLengthSq > 1e-12f)
        ? firstWi * inversesqrt(firstWiLengthSq)
        : vec3(0.0f);

    d.secondHit.worldPos = secondPos;
    d.secondHit.viewDepth = (lightSample.index >= 0) ? 0.0f : surface.viewDepth;
    d.secondHit.faceId = 0u;
    d.secondHit.materialId = uint(max(reservoirLightIndex, 0));
    d.secondBSDFComponentType = scatter_resolve_second_bsdf_component_type(lightSample);
    d.secondWo = (lightSample.index >= 0 && distance(secondPos, surface.worldPos) > 1e-6f)
        ? normalize(secondPos - surface.worldPos)
        : vec3(0.0f);

    d.transmissionEvent = false;
    d.lightIsNEE = lightIsAnalytic;
    d.lightIsDistant = (lightSample.index >= 0) && !lightIsAnalytic;
    d.lightPdf = scatter_resolve_light_pdf(reservoir, lightSample);

    d.subPixelJacobian = scatter_resolve_subpixel_jacobian(surface, d.time, d.lensSample);
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

ReconnectionData ReconnectionData_build(
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
