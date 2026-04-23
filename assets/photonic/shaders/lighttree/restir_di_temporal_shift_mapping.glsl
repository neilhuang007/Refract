#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_SHIFT_MAPPING_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_SHIFT_MAPPING_GLSL

ShiftedPathData lt_temporal_empty_shifted_path()
{
    ShiftedPathData shiftedPathData;
    shiftedPathData.primaryHit = ReservoirSplattingHitInfo_empty();
    shiftedPathData.fractionalPixel = vec2(-1.0f);
    shiftedPathData.lensSample = vec2(0.0f);
    shiftedPathData.firstRayDir = vec3(0.0f);
    shiftedPathData.subPixelJacobian = 1.0f;
    shiftedPathData.lensVertexJacobian = 1.0f;
    shiftedPathData.secondaryPathJacobian = 1.0f;
    shiftedPathData.radiance = vec3(0.0f);
    return shiftedPathData;
}

ReservoirSplattingHitInfo lt_temporal_make_shifted_hit_info(ivec2 pixel, RAB_Surface surface)
{
    ReservoirSplattingHitInfo hitInfo = ReservoirSplattingHitInfo_empty();
    vec4 identityData = scatter_load_surface_identity(pixel, false);
    hitInfo.worldPos = surface.worldPos;
    hitInfo.viewDepth = surface.viewDepth;
    hitInfo.faceId = uint(round(identityData.w));
    return hitInfo;
}

vec2 lt_temporal_fractional_pixel_to_uv(vec2 fractionalPixel)
{
    return clamp(
        fractionalPixel / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0)),
        vec2(0.0f),
        vec2(1.0f)
    );
}

vec3 lt_temporal_camera_pos(float time)
{
    return world_camera_position;
}

vec3 lt_temporal_camera_u(float time)
{
    return lt_di_temporal_camera_u();
}

vec3 lt_temporal_camera_v(float time)
{
    return lt_di_temporal_camera_v();
}

vec3 lt_temporal_camera_w(float time)
{
    return lt_di_temporal_camera_w();
}

vec3 lt_temporal_camera_forward(float time)
{
    return normalize(lt_temporal_camera_w(time));
}

vec3 lt_temporal_lens_world_offset(float time, vec2 lensSample)
{
    float apertureRadius = lt_di_temporal_camera_aperture_radius();
    if (apertureRadius <= 0.0f)
    {
        return vec3(0.0f);
    }

    return apertureRadius
        * (lensSample.x * normalize(lt_temporal_camera_u(time))
            + lensSample.y * normalize(lt_temporal_camera_v(time)));
}

vec3 lt_temporal_film_world(float time, vec2 fractionalPixel)
{
    vec2 pixelUv = lt_temporal_fractional_pixel_to_uv(fractionalPixel);
    vec2 ndc = vec2(2.0f, -2.0f) * pixelUv + vec2(-1.0f, 1.0f);
    return lt_temporal_camera_pos(time)
        + ndc.x * lt_temporal_camera_u(time)
        + ndc.y * lt_temporal_camera_v(time)
        + lt_temporal_camera_w(time);
}

float lt_temporal_compute_subpixel_jacobian(
    vec3 primaryHitPosW,
    vec3 primaryHitNormalW,
    vec3 rayOriginW,
    vec3 rayDir,
    vec3 cameraForward)
{
    vec3 toHit = primaryHitPosW - rayOriginW;
    float dist = length(toHit);
    if (dist < 1e-6f)
    {
        return 1.0f;
    }

    float cosNormal = abs(dot(-rayDir, primaryHitNormalW));
    float cosSensor = max(abs(dot(cameraForward, rayDir)), 1e-6f);
    float jacobian = cosNormal / (dist * dist * cosSensor * cosSensor * cosSensor);
    return max(jacobian, 1e-10f);
}

float lt_temporal_compute_lens_vertex_jacobian(
    vec3 primaryHitPosW,
    vec3 primaryHitNormalW,
    vec3 rayOriginW,
    vec3 rayDir,
    vec3 cameraForward)
{
    vec3 toHit = primaryHitPosW - rayOriginW;
    float dist = length(toHit);
    if (dist < 1e-6f)
    {
        return 1.0f;
    }

    float cosNormal = abs(dot(rayDir, primaryHitNormalW));
    float cosSensor = max(abs(dot(cameraForward, rayDir)), 1e-6f);
    float focalDistance = length(lt_temporal_camera_w(0.0f));
    float camZ = max(abs(dot(toHit, cameraForward)), 1e-6f);
    float d0 = focalDistance / camZ * dist;
    float d1 = max(dist - d0, 1e-6f);

    float jacobian = (d0 * d0) / (d1 * d1) * cosNormal / cosSensor;
    return max(jacobian, 1e-10f);
}

bool lt_temporal_trace_reconnection_visibility(
    vec3 rayOriginW,
    vec3 rayDirW,
    float traceMaxDistance)
{
    ray.origin = rayOriginW;
    ray.direction = rayDirW;
    ray_min_trace_distance = 0.001f;
    ray_max_trace_distance = max(traceMaxDistance, 0.0f);
    trace_ray(ray, true);
    bool unoccluded = !ray.result_hit && ray_distance_limit_reached;
    ray_min_trace_distance = 0.0f;
    ray_max_trace_distance = -1.0f;
    return unoccluded;
}

vec3 lt_temporal_path_reconnection_shift(
    RTXDI_DIReservoir sourceReservoir,
    RAB_Surface shiftedSurface)
{
    if (!RTXDI_IsValidDIReservoir(sourceReservoir))
    {
        return vec3(0.0f);
    }

    RAB_LightSample shiftedLight = lt_decode_reservoir_sample_for_frame(
        sourceReservoir,
        shiftedSurface,
        false,
        false
    );
    if (shiftedLight.index < 0 || shiftedLight.solidAnglePdf <= 0.0f)
    {
        return vec3(0.0f);
    }

    return max(lt_shade_surface_light_sample(shiftedSurface, shiftedLight), vec3(0.0f));
}

ShiftedPathData gatherLensVertexCopyShift(
    inout RTXDI_RandomSamplerState rng,
    inout ReservoirSplattingReconnectionData reconnectionData,
    float time,
    vec2 fractionalPixel,
    vec2 lensSample,
    RTXDI_DIReservoir sourceReservoir)
{
    ShiftedPathData shiftedPath = lt_temporal_empty_shifted_path();

    if (!lt_is_viewport_uv_in_bounds(fractionalPixel))
    {
        return shiftedPath;
    }

    lt_next_random(rng);

    ivec2 landingPixel = clamp(
        ivec2(floor(fractionalPixel)),
        ivec2(0),
        ivec2(int(viewWidth) - 1, int(viewHeight) - 1)
    );
    RAB_Surface landingSurface = RAB_GetGBufferSurface(landingPixel, false);
    if (!RAB_IsSurfaceValid(landingSurface))
    {
        return shiftedPath;
    }

    vec3 cameraPosW = lt_temporal_camera_pos(time) + lt_temporal_lens_world_offset(time, lensSample);
    vec3 cameraForward = lt_temporal_camera_forward(time);
    vec3 primaryHitPosW = landingSurface.worldPos;
    vec3 primaryHitNormalW = landingSurface.geoNormal;

    vec3 toHit = primaryHitPosW - cameraPosW;
    float hitDistance = length(toHit);
    if (hitDistance < 1e-6f)
    {
        return shiftedPath;
    }

    vec3 rayDir = toHit / hitDistance;

    shiftedPath.primaryHit = lt_temporal_make_shifted_hit_info(landingPixel, landingSurface);
    shiftedPath.fractionalPixel = fractionalPixel;
    shiftedPath.lensSample = lensSample;
    shiftedPath.firstRayDir = rayDir;
    shiftedPath.subPixelJacobian = lt_temporal_compute_subpixel_jacobian(
        primaryHitPosW,
        primaryHitNormalW,
        cameraPosW,
        rayDir,
        cameraForward
    );
    shiftedPath.lensVertexJacobian = lt_temporal_compute_lens_vertex_jacobian(
        primaryHitPosW,
        primaryHitNormalW,
        cameraPosW,
        rayDir,
        cameraForward
    );
    shiftedPath.secondaryPathJacobian = scatter_resolve_secondary_path_jacobian(
        landingSurface,
        sourceReservoir,
        lt_decode_reservoir_sample_for_frame(sourceReservoir, landingSurface, false, false)
    );
    shiftedPath.radiance = lt_temporal_path_reconnection_shift(sourceReservoir, landingSurface);
    return shiftedPath;
}

ShiftedPathData gatherPrimaryHitReconnectionShift(
    inout RTXDI_RandomSamplerState rng,
    inout ReservoirSplattingReconnectionData reconnectionData,
    float time,
    vec2 fractionalPixel,
    ReservoirSplattingHitInfo primaryHit,
    RTXDI_DIReservoir sourceReservoir)
{
    ShiftedPathData shiftedPath = lt_temporal_empty_shifted_path();

    if (!lt_is_viewport_uv_in_bounds(fractionalPixel))
    {
        return shiftedPath;
    }

    if (dot(primaryHit.worldPos, primaryHit.worldPos) <= 0.0f)
    {
        return shiftedPath;
    }

    lt_next_random(rng);

    vec3 cameraPosW = lt_temporal_camera_pos(time);
    vec3 cameraU = normalize(lt_temporal_camera_u(time));
    vec3 cameraV = normalize(lt_temporal_camera_v(time));
    vec3 cameraForward = lt_temporal_camera_forward(time);
    vec3 filmWorld = lt_temporal_film_world(time, fractionalPixel);

    vec3 toPrimaryHit = primaryHit.worldPos - filmWorld;
    float hitDistance = length(toPrimaryHit);
    if (hitDistance < 1e-6f)
    {
        return shiftedPath;
    }

    vec3 rayDir = toPrimaryHit / hitDistance;
    float cosSensor = dot(cameraForward, rayDir);
    if (cosSensor <= 1e-4f)
    {
        return shiftedPath;
    }

    float camZ = dot(primaryHit.worldPos - cameraPosW, cameraForward);
    float rayT = camZ / cosSensor;
    vec3 rayOrigin = primaryHit.worldPos - rayT * rayDir;
    float apertureRadius = lt_di_temporal_camera_aperture_radius();
    vec2 lensLocalNormalized = vec2(0.0f);
    if (apertureRadius > 0.0f)
    {
        vec3 lensOffsetWorld = rayOrigin - cameraPosW;
        lensLocalNormalized = vec2(
            dot(lensOffsetWorld, cameraU),
            dot(lensOffsetWorld, cameraV)
        ) / apertureRadius;
        if (length(lensLocalNormalized) > 1.0f)
        {
            return shiftedPath;
        }
    }
    else
    {
        rayOrigin = cameraPosW;
        rayDir = normalize(primaryHit.worldPos - rayOrigin);
        hitDistance = length(primaryHit.worldPos - rayOrigin);
    }

    if (!lt_temporal_trace_reconnection_visibility(rayOrigin, rayDir, 0.999f * hitDistance))
    {
        return shiftedPath;
    }

    ivec2 landingPixel = clamp(
        ivec2(floor(fractionalPixel)),
        ivec2(0),
        ivec2(int(viewWidth) - 1, int(viewHeight) - 1)
    );
    RAB_Surface primaryHitSurface = RAB_GetGBufferSurface(landingPixel, false);
    if (!RAB_IsSurfaceValid(primaryHitSurface))
    {
        return shiftedPath;
    }
    if (!scatter_reconnection_matches_surface(reconnectionData, landingPixel, primaryHitSurface, false))
    {
        return shiftedPath;
    }

    vec3 primaryHitNormalW = primaryHitSurface.geoNormal;
    RAB_Surface shiftedSurface = primaryHitSurface;
    shiftedSurface.worldPos = primaryHit.worldPos;
    shiftedSurface.geoNormal = primaryHitNormalW;
    shiftedSurface.normal = primaryHitNormalW;
    shiftedSurface.viewDir = -rayDir;
    shiftedSurface.viewDepth = hitDistance;

    shiftedPath.primaryHit = primaryHit;
    shiftedPath.primaryHit.viewDepth = hitDistance;
    shiftedPath.fractionalPixel = fractionalPixel;
    shiftedPath.lensSample = lensLocalNormalized;
    shiftedPath.firstRayDir = rayDir;
    shiftedPath.subPixelJacobian = lt_temporal_compute_subpixel_jacobian(
        primaryHit.worldPos,
        primaryHitNormalW,
        rayOrigin,
        rayDir,
        cameraForward
    );
    shiftedPath.lensVertexJacobian = lt_temporal_compute_lens_vertex_jacobian(
        primaryHit.worldPos,
        primaryHitNormalW,
        rayOrigin,
        rayDir,
        cameraForward
    );
    shiftedPath.secondaryPathJacobian = scatter_resolve_secondary_path_jacobian(
        shiftedSurface,
        sourceReservoir,
        lt_decode_reservoir_sample_for_frame(sourceReservoir, shiftedSurface, false, false)
    );
    shiftedPath.radiance = lt_temporal_path_reconnection_shift(sourceReservoir, shiftedSurface);
    return shiftedPath;
}

ReservoirSplattingReconnectionData ReconnectionData_update(
    ReservoirSplattingReconnectionData source,
    ShiftedPathData shiftedPath)
{
    ReservoirSplattingReconnectionData updated = source;
    updated.firstHit = shiftedPath.primaryHit;
    updated.firstWi = -shiftedPath.firstRayDir;
    updated.subPixel = shiftedPath.fractionalPixel - floor(shiftedPath.fractionalPixel);
    updated.lensSample = shiftedPath.lensSample;
    updated.subPixelJacobian = shiftedPath.subPixelJacobian;
    updated.lensVertexJacobian = shiftedPath.lensVertexJacobian;
    updated.secondaryPathJacobian = shiftedPath.secondaryPathJacobian;
    return updated;
}

#endif
