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

    return lt_light_sample_incident_radiance(surface, lightSample);
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

const float SCATTER_RECONNECTION_RAY_T_MAX = 3.402823466e+38f;

float PathTracer_evalMIS(float n0, float p0, float n1, float p1)
{
    float q0 = n0 * p0;
    float q1 = n1 * p1;
    float denom = q0 + q1;
    return denom > 0.0f ? (q0 / denom) : 0.0f;
}

float PathTracer_evalDiffusePdf(RAB_Surface sd, vec3 wo)
{
    float nDotWo = max(dot(sd.normal, normalize(wo)), 0.0f);
    return nDotWo / lt_pi;
}

float PathTracer_evalSpecularPdf(RAB_Surface sd, vec3 wo)
{
    vec3 lightDir = normalize(wo);
    vec3 viewDir = normalize(sd.viewDir);
    float nDotL = dot(sd.normal, lightDir);
    float nDotV = dot(sd.normal, viewDir);
    if (nDotL <= 0.0f || nDotV <= 0.0f)
    {
        return 0.0f;
    }

    vec3 halfVector = normalize(viewDir + lightDir);
    float nDotH = max(dot(sd.normal, halfVector), 0.0f);
    float roughness = clamp(sd.material.roughness, lt_min_roughness, 1.0f);
    float distribution = lt_distribution_ggx(nDotH, roughness);
    float alpha = max(roughness * roughness, 0.02f);
    float k = alpha * 0.5f;
    float geometry1 = nDotV / max(nDotV * (1.0f - k) + k, 1e-6f);
    return distribution * geometry1 / max(4.0f * nDotV, 1e-6f);
}

LightBrdf PathTracer_evalSurfaceBSDF(RAB_Surface sd, vec3 wo)
{
    return lt_evaluate_surface_brdf_with_view(sd, wo, sd.viewDir);
}

vec3 PathTracer_evalLobeSpecificBSDF(
    RAB_Surface sd,
    vec3 wo,
    uint bsdfComponentType)
{
    LightBrdf bsdf = PathTracer_evalSurfaceBSDF(sd, wo);
    if (bsdfComponentType == SCATTER_BSDF_COMPONENT_DIFFUSE)
    {
        return bsdf.demodulatedDiffuse * sd.material.diffuseAlbedo;
    }
    if (bsdfComponentType == SCATTER_BSDF_COMPONENT_SPECULAR)
    {
        return bsdf.specular;
    }

    return vec3(0.0f);
}

float PathTracer_evalLobeSpecificPdf(
    RAB_Surface sd,
    vec3 wo,
    uint bsdfComponentType)
{
    if (bsdfComponentType == SCATTER_BSDF_COMPONENT_DIFFUSE)
    {
        return PathTracer_evalDiffusePdf(sd, wo);
    }
    if (bsdfComponentType == SCATTER_BSDF_COMPONENT_SPECULAR)
    {
        return PathTracer_evalSpecularPdf(sd, wo);
    }

    return 0.0f;
}

vec3 PathTracer_evalTotalBSDF(RAB_Surface sd, vec3 wo)
{
    LightBrdf bsdf = PathTracer_evalSurfaceBSDF(sd, wo);
    return bsdf.demodulatedDiffuse * sd.material.diffuseAlbedo + bsdf.specular;
}

float PathTracer_evalTotalPdf(RAB_Surface sd, vec3 wo)
{
    float diffusePdf = PathTracer_evalDiffusePdf(sd, wo);
    float specularPdf = PathTracer_evalSpecularPdf(sd, wo);
    float diffuseProbability = lt_surface_diffuse_probability_with_view(sd, sd.viewDir);
    return mix(specularPdf, diffusePdf, diffuseProbability);
}

struct PathTracerReconnectionHit
{
    bool isActive;
    vec3 thp;
    float dstJacobian;
};

PathTracerReconnectionHit PathTracer_handleReconnectionHit(
    ReconnectionData reconnectionData,
    RAB_Surface sd,
    RAB_LightSample shiftedLight)
{
    PathTracerReconnectionHit path;
    path.isActive = false;
    path.thp = vec3(1.0f);
    path.dstJacobian = 1.0f;

    if (!RAB_IsSurfaceValid(sd) || shiftedLight.index < 0)
    {
        return path;
    }

    bool secondHitIsDistant = (reconnectionData.pathLength == 2u)
        && reconnectionData.lightIsDistant;
    vec3 nextDir = secondHitIsDistant
        ? normalize(reconnectionData.secondWo)
        : normalize(shiftedLight.position - sd.worldPos);
    float rayLength = secondHitIsDistant
        ? SCATTER_RECONNECTION_RAY_T_MAX
        : (0.999f * distance(shiftedLight.position, sd.worldPos));
    if (dot(nextDir, nextDir) <= 1e-12f)
    {
        return path;
    }

    float visibilityHitDistance = 0.0f;
    vec3 visibility = lt_trace_final_visibility_with_offset(
        shiftedLight,
        sd,
        0.0f,
        visibilityHitDistance
    );
    if (!any(greaterThan(visibility, vec3(0.0f))))
    {
        return path;
    }

    vec3 lobeSpecificBsdf = PathTracer_evalLobeSpecificBSDF(
        sd,
        nextDir,
        reconnectionData.firstBSDFComponentType
    );
    float lobeSpecificPdf = PathTracer_evalLobeSpecificPdf(
        sd,
        nextDir,
        reconnectionData.firstBSDFComponentType
    );
    vec3 totalBsdf = PathTracer_evalTotalBSDF(sd, nextDir);
    float totalPdf = PathTracer_evalTotalPdf(sd, nextDir);

    if (reconnectionData.pathLength == 2u)
    {
        float lightPdf = reconnectionData.lightPdf / path.dstJacobian;
        if (reconnectionData.lightIsNEE)
        {
            if (!any(greaterThan(totalBsdf, vec3(0.0f))) || totalPdf == 0.0f || lightPdf <= 0.0f)
            {
                return path;
            }

            path.dstJacobian *= lightPdf;
            float misWeight = PathTracer_evalMIS(1.0f, lightPdf, 1.0f, totalPdf);
            path.thp *= (totalBsdf / lightPdf) * misWeight;
        }
        else
        {
            if (!any(greaterThan(lobeSpecificBsdf, vec3(0.0f))) || lobeSpecificPdf == 0.0f || lightPdf <= 0.0f)
            {
                return path;
            }

            path.dstJacobian *= lobeSpecificPdf;
            float misWeight = PathTracer_evalMIS(1.0f, totalPdf, 1.0f, lightPdf);
            path.thp *= (lobeSpecificBsdf / lobeSpecificPdf) * misWeight;
        }
    }
    else
    {
        if (!any(greaterThan(lobeSpecificBsdf, vec3(0.0f))) || lobeSpecificPdf == 0.0f)
        {
            return path;
        }

        path.dstJacobian *= lobeSpecificPdf;
        path.thp *= lobeSpecificBsdf / lobeSpecificPdf;
    }

    path.isActive = any(greaterThan(path.thp, vec3(0.0f))) && rayLength > 0.0f;
    return path;
}

vec3 pathReconnectionShift(
    ReconnectionData reconnectionData,
    RAB_Surface shiftedSurface,
    RAB_LightSample shiftedLight,
    out float dstJacobian)
{
    dstJacobian = 1.0f;
    PathTracerReconnectionHit path = PathTracer_handleReconnectionHit(
        reconnectionData,
        shiftedSurface,
        shiftedLight
    );
    dstJacobian = path.dstJacobian;
    if (!path.isActive)
    {
        return vec3(0.0f);
    }

    return path.thp * reconnectionData.irradiance;
}

vec3 pathReconnectionShift(
    ReconnectionData reconnectionData,
    RAB_Surface shiftedSurface,
    RAB_LightSample shiftedLight)
{
    float dstJacobian = 1.0f;
    return pathReconnectionShift(
        reconnectionData,
        shiftedSurface,
        shiftedLight,
        dstJacobian
    );
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
    vec3 secondPos = (lightSample.index >= 0) ? lightSample.position : vec3(0.0f);
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
    d.secondHit.viewDepth = 0.0f;
    d.secondHit.faceId = 0u;
    d.secondHit.materialId = (lightSample.index >= 0) ? uint(max(reservoirLightIndex, 0)) : 0u;
    d.secondBSDFComponentType = scatter_resolve_second_bsdf_component_type(lightSample);
    d.secondWo = (lightSample.index >= 0 && distance(secondPos, surface.worldPos) > 1e-6f)
        ? normalize(secondPos - surface.worldPos)
        : vec3(0.0f);

    d.transmissionEvent = false;
    d.lightIsNEE = lightIsAnalytic;
    d.lightIsDistant = (lightSample.index >= 0) && !lightIsAnalytic;
    d.lightPdf = scatter_resolve_light_pdf(reservoir, lightSample);

    d.subPixelJacobian = (subPixelJacobian > 0.0f)
        ? subPixelJacobian
        : scatter_resolve_subpixel_jacobian(surface, d.time, d.lensSample);
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
