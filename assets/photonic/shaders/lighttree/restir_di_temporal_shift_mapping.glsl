#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_SHIFT_MAPPING_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_SHIFT_MAPPING_GLSL

float lt_di_temporal_camera_aperture_radius();
float lt_di_temporal_artificial_frame_time();
float lt_di_temporal_shutter_speed();
vec3 lt_di_temporal_camera_u();
vec3 lt_di_temporal_camera_v();
vec3 lt_di_temporal_camera_w();
vec3 lt_di_temporal_previous_camera_u();
vec3 lt_di_temporal_previous_camera_v();
vec3 lt_di_temporal_previous_camera_w();

ShiftedPathData lt_temporal_empty_shifted_path()
{
    ShiftedPathData shiftedPathData;
    shiftedPathData.primaryHit = HitInfo_empty();
    shiftedPathData.fractionalPixel = vec2(-1.0f);
    shiftedPathData.lensSample = vec2(0.0f);
    shiftedPathData.firstRayDir = vec3(0.0f);
    shiftedPathData.subPixelJacobian = 1.0f;
    shiftedPathData.lensVertexJacobian = 1.0f;
    shiftedPathData.secondaryPathJacobian = 1.0f;
    shiftedPathData.radiance = vec3(0.0f);
    return shiftedPathData;
}

vec4 lt_temporal_load_surface_identity(ivec2 pixel, bool previousFrame)
{
    return scatter_load_surface_identity(pixel, previousFrame);
}

RAB_Surface lt_temporal_load_surface(ivec2 pixel, bool previousFrame)
{
    return previousFrame
        ? lt_load_previous_surface(pixel)
        : RAB_GetGBufferSurface(pixel, false);
}

HitInfo lt_temporal_make_shifted_hit_info(
    ivec2 pixel,
    RAB_Surface surface,
    bool previousFrame)
{
    HitInfo hitInfo = HitInfo_empty();
    vec4 identityData = lt_temporal_load_surface_identity(pixel, previousFrame);
    uint packedIdentity = uint(round(identityData.w));
    hitInfo.worldPos = surface.worldPos;
    hitInfo.viewDepth = surface.viewDepth;
    hitInfo.faceId = packedIdentity & 0x7u;
    hitInfo.materialId = packedIdentity >> 3u;
    return hitInfo;
}

vec2 lt_temporal_fractional_pixel_to_uv(vec2 fractionalPixel)
{
    return fractionalPixel / vec2(viewWidth, viewHeight);
}

vec3 lt_temporal_camera_pos(bool targetPreviousFrame)
{
    return targetPreviousFrame ? previous_world_camera_position : world_camera_position;
}

vec3 lt_temporal_camera_pos(float time)
{
    return lt_di_temporal_camera_pos_at_time(time);
}

vec3 lt_temporal_camera_u(bool targetPreviousFrame)
{
    return targetPreviousFrame ? lt_di_temporal_previous_camera_u() : lt_di_temporal_camera_u();
}

vec3 lt_temporal_camera_u(float time)
{
    return lt_di_temporal_camera_u_at_time(time);
}

vec3 lt_temporal_camera_v(bool targetPreviousFrame)
{
    return targetPreviousFrame ? lt_di_temporal_previous_camera_v() : lt_di_temporal_camera_v();
}

vec3 lt_temporal_camera_v(float time)
{
    return lt_di_temporal_camera_v_at_time(time);
}

vec3 lt_temporal_camera_w(bool targetPreviousFrame)
{
    return targetPreviousFrame ? lt_di_temporal_previous_camera_w() : lt_di_temporal_camera_w();
}

vec3 lt_temporal_camera_w(float time)
{
    return lt_di_temporal_camera_w_at_time(time);
}

vec3 lt_temporal_camera_forward(bool targetPreviousFrame)
{
    return normalize(lt_temporal_camera_w(targetPreviousFrame));
}

vec3 lt_temporal_camera_forward(float time)
{
    return normalize(lt_temporal_camera_w(time));
}

vec3 lt_temporal_lens_world_offset(bool targetPreviousFrame, vec2 lensSample);
vec3 lt_temporal_lens_world_offset(float time, vec2 lensSample);

vec3 lt_temporal_camera_origin(bool targetPreviousFrame, vec2 lensSample)
{
    return lt_temporal_camera_pos(targetPreviousFrame)
        + lt_temporal_lens_world_offset(targetPreviousFrame, lensSample);
}

vec3 lt_temporal_camera_origin(float time, vec2 lensSample)
{
    return lt_temporal_camera_pos(time)
        + lt_temporal_lens_world_offset(time, lensSample);
}

vec3 lt_temporal_lens_world_offset(bool targetPreviousFrame, vec2 lensSample)
{
    float apertureRadius = lt_di_temporal_camera_aperture_radius();
    if (apertureRadius <= 0.0f)
    {
        return vec3(0.0f);
    }

    return apertureRadius
        * (lensSample.x * normalize(lt_temporal_camera_u(targetPreviousFrame))
            + lensSample.y * normalize(lt_temporal_camera_v(targetPreviousFrame)));
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

vec3 lt_temporal_film_world(bool targetPreviousFrame, vec2 fractionalPixel)
{
    vec2 pixelUv = lt_temporal_fractional_pixel_to_uv(fractionalPixel);
    vec2 ndc = vec2(2.0f, -2.0f) * pixelUv + vec2(-1.0f, 1.0f);
    return lt_temporal_camera_pos(targetPreviousFrame)
        + ndc.x * lt_temporal_camera_u(targetPreviousFrame)
        + ndc.y * lt_temporal_camera_v(targetPreviousFrame)
        + lt_temporal_camera_w(targetPreviousFrame);
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

bool lt_temporal_has_primary_hit(HitInfo hitInfo)
{
    return hitInfo.viewDepth > 0.0f
        && any(greaterThan(abs(hitInfo.worldPos), vec3(0.0f)));
}

bool lt_temporal_hit_env_map(ReconnectionData reconnectionData)
{
    return (reconnectionData.pathLength == 1u) && reconnectionData.lightIsDistant;
}

bool lt_temporal_hit_primary_light(ReconnectionData reconnectionData)
{
    return (reconnectionData.pathLength == 1u) && !reconnectionData.lightIsDistant;
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
    float cosNormal = dot(-rayDir, primaryHitNormalW);
    float cosSensor = dot(cameraForward, rayDir);
    return abs(cosNormal / (dist * dist)) / abs(pow(cosSensor, 3.0f));
}

float lt_temporal_compute_lens_vertex_copy_jacobian(
    vec3 primaryHitPosW,
    vec3 primaryHitNormalW,
    vec3 rayOriginW,
    vec3 rayDir,
    vec3 cameraPosW,
    vec3 cameraForward,
    float time)
{
    float dist = length(primaryHitPosW - rayOriginW);
    float cosNormal = dot(-rayDir, primaryHitNormalW);
    float cosSensor = dot(cameraForward, rayDir);
    float focalDistance = length(lt_temporal_camera_w(time));
    float camZ = dot(primaryHitPosW - cameraPosW, cameraForward);
    float d0 = focalDistance / abs(camZ) * dist;
    float d1 = dist - d0;

    return (d0 * d0) / (d1 * d1) * abs(cosNormal) / abs(cosSensor);
}

float lt_temporal_compute_primary_hit_reconnection_jacobian(
    vec3 primaryHitPosW,
    vec3 primaryHitNormalW,
    vec3 rayDir,
    vec3 cameraPosW,
    vec3 cameraForward,
    float rayT,
    float time)
{
    float cosNormal = dot(rayDir, primaryHitNormalW);
    float cosSensor = dot(cameraForward, rayDir);
    float focalDistance = length(lt_temporal_camera_w(time));
    float camZ = dot(primaryHitPosW - cameraPosW, cameraForward);
    float d0 = focalDistance / abs(camZ) * rayT;
    float d1 = rayT - d0;
    return (d0 * d0) / (d1 * d1) * abs(cosNormal) / abs(cosSensor);
}

float lt_temporal_compute_env_map_subpixel_jacobian(
    vec3 rayDir,
    vec3 cameraForward)
{
    float cosSensor = dot(cameraForward, rayDir);
    return 1.0f / abs(pow(cosSensor, 3.0f));
}

float lt_temporal_compute_env_map_lens_vertex_jacobian(
    vec3 rayDir,
    vec3 cameraForward,
    float time)
{
    float cosSensor = dot(cameraForward, rayDir);
    float focalDistance = length(lt_temporal_camera_w(time));
    float d0 = focalDistance / dot(cameraForward, rayDir);
    return (d0 * d0) / abs(cosSensor);
}

bool lt_temporal_trace_visibility_ray(
    vec3 rayOriginW,
    vec3 rayDirW,
    float traceMinDistance,
    float traceMaxDistance)
{
    ray.origin = rayOriginW;
    ray.direction = rayDirW;
    ray_min_trace_distance = traceMinDistance;
    ray_max_trace_distance = traceMaxDistance;
    trace_ray(ray, true);
    bool unoccluded = !ray.result_hit && ray_distance_limit_reached;
    ray_min_trace_distance = 0.0f;
    ray_max_trace_distance = -1.0f;
    return unoccluded;
}

bool lt_temporal_trace_visibility_ray(
    vec3 rayOriginW,
    vec3 rayDirW,
    float traceMaxDistance)
{
    return lt_temporal_trace_visibility_ray(rayOriginW, rayDirW, 0.001f, traceMaxDistance);
}

vec3 lt_temporal_handle_reconnection_primary_light(RTXDI_DIReservoir sourceReservoir)
{
    return PathReservoir_getIntegrand(sourceReservoir);
}

vec3 lt_temporal_handle_reconnection_env_map(RTXDI_DIReservoir sourceReservoir)
{
    return PathReservoir_getIntegrand(sourceReservoir);
}

vec3 lt_temporal_path_reconnection_shift(
    ReconnectionData reconnectionData,
    RTXDI_DIReservoir sourceReservoir,
    RAB_Surface shiftedSurface,
    bool sourcePreviousFrame,
    bool targetPreviousFrame,
    out float secondaryPathJacobian)
{
    secondaryPathJacobian = 1.0f;
    if (!RAB_IsSurfaceValid(shiftedSurface))
    {
        return vec3(0.0f);
    }

    RAB_LightSample shiftedLight = lt_decode_reservoir_sample_for_frame(
        sourceReservoir,
        shiftedSurface,
        sourcePreviousFrame,
        targetPreviousFrame
    );
    if (shiftedLight.index < 0 || shiftedLight.solidAnglePdf <= 0.0f)
    {
        return vec3(0.0f);
    }

    secondaryPathJacobian = scatter_resolve_secondary_path_jacobian(
        shiftedSurface,
        sourceReservoir,
        shiftedLight
    );
    return pathReconnectionShift(reconnectionData, shiftedSurface, shiftedLight);
}

ShiftedPathData scatterReprojectionShift(
    inout RTXDI_RandomSamplerState rng,
    inout ReconnectionData reconnectionData,
    float time,
    HitInfo primaryHit,
    vec2 lensSample,
    RTXDI_DIReservoir sourceReservoir,
    bool sourcePreviousFrame,
    bool targetPreviousFrame,
    bool skipVisibilityCheck)
{
    ShiftedPathData shiftedPath = lt_temporal_empty_shifted_path();

    bool hitEnvMap = lt_temporal_hit_env_map(reconnectionData);
    if (!hitEnvMap && !lt_temporal_has_primary_hit(primaryHit))
    {
        return shiftedPath;
    }

    lt_next_random(rng);

    vec3 cameraPosW = lt_temporal_camera_origin(time, lensSample);
    vec3 cameraU = normalize(lt_temporal_camera_u(time));
    vec3 cameraV = normalize(lt_temporal_camera_v(time));
    vec3 cameraForward = lt_temporal_camera_forward(time);

    vec3 rayDir = vec3(0.0f);
    float hitDistance = 1e5f;
    if (hitEnvMap)
    {
        if (dot(reconnectionData.firstWi, reconnectionData.firstWi) <= 1e-12f)
        {
            return shiftedPath;
        }

        rayDir = -normalize(reconnectionData.firstWi);
    }
    else
    {
        vec3 toPrimaryHit = primaryHit.worldPos - cameraPosW;
        hitDistance = length(toPrimaryHit);
        if (hitDistance < 1e-6f)
        {
            return shiftedPath;
        }

        rayDir = toPrimaryHit / hitDistance;
    }

    vec3 camRay = vec3(
        dot(cameraU, rayDir),
        dot(cameraV, rayDir),
        dot(cameraForward, rayDir)
    );
    if (camRay.z <= 1e-3f)
    {
        return shiftedPath;
    }

    float apertureRadius = lt_di_temporal_camera_aperture_radius();
    vec2 lensLocal = apertureRadius * lensSample;
    float focalDistance = length(lt_temporal_camera_w(time));
    vec2 film = lensLocal + focalDistance * (camRay.xy / camRay.z);
    vec2 ndc = film / vec2(
        length(lt_temporal_camera_u(time)),
        length(lt_temporal_camera_v(time))
    );
    vec2 newFractionalPixel =
        (vec2(0.5f, -0.5f) * ndc + vec2(0.5f, 0.5f)) * vec2(viewWidth, viewHeight);
    if (any(lessThan(newFractionalPixel, vec2(0.0f)))
        || any(greaterThanEqual(newFractionalPixel, vec2(viewWidth, viewHeight))))
    {
        return shiftedPath;
    }

    if (!skipVisibilityCheck
        && !lt_temporal_trace_visibility_ray(
            cameraPosW,
            rayDir,
            0.001f,
            hitEnvMap ? hitDistance : (0.999f * hitDistance)))
    {
        return shiftedPath;
    }

    shiftedPath.primaryHit = primaryHit;
    shiftedPath.primaryHit.viewDepth = hitEnvMap ? 0.0f : hitDistance;
    shiftedPath.fractionalPixel = newFractionalPixel;
    shiftedPath.lensSample = lensSample;
    shiftedPath.firstRayDir = rayDir;

    if (hitEnvMap)
    {
        shiftedPath.subPixelJacobian = lt_temporal_compute_env_map_subpixel_jacobian(
            rayDir,
            cameraForward
        );
        shiftedPath.lensVertexJacobian = lt_temporal_compute_env_map_lens_vertex_jacobian(
            rayDir,
            cameraForward,
            time
        );
        shiftedPath.radiance = lt_temporal_handle_reconnection_env_map(sourceReservoir);
        return shiftedPath;
    }

    ivec2 landingPixel = ivec2(floor(newFractionalPixel));
    RAB_Surface landingSurface = lt_temporal_load_surface(landingPixel, targetPreviousFrame);
    if (!RAB_IsSurfaceValid(landingSurface))
    {
        return shiftedPath;
    }

    vec3 primaryHitNormalW = scatter_decode_surface_face_normal(primaryHit.faceId);
    RAB_Surface shiftedSurface = landingSurface;
    shiftedSurface.worldPos = primaryHit.worldPos;
    shiftedSurface.geoNormal = primaryHitNormalW;
    shiftedSurface.normal = primaryHitNormalW;
    shiftedSurface.viewDir = -rayDir;
    shiftedSurface.viewDepth = hitDistance;

    shiftedPath.subPixelJacobian = lt_temporal_compute_subpixel_jacobian(
        primaryHit.worldPos,
        primaryHitNormalW,
        cameraPosW,
        rayDir,
        cameraForward
    );
    shiftedPath.lensVertexJacobian = lt_temporal_compute_lens_vertex_copy_jacobian(
        primaryHit.worldPos,
        primaryHitNormalW,
        cameraPosW,
        rayDir,
        lt_temporal_camera_pos(time),
        cameraForward,
        time
    );

    if (lt_temporal_hit_primary_light(reconnectionData))
    {
        shiftedPath.radiance = lt_temporal_handle_reconnection_primary_light(sourceReservoir);
        return shiftedPath;
    }

    shiftedPath.radiance = lt_temporal_path_reconnection_shift(
        reconnectionData,
        sourceReservoir,
        shiftedSurface,
        sourcePreviousFrame,
        targetPreviousFrame,
        shiftedPath.secondaryPathJacobian
    );
    return shiftedPath;
}

ShiftedPathData scatterReprojectionShift(
    inout RTXDI_RandomSamplerState rng,
    inout ReconnectionData reconnectionData,
    float time,
    HitInfo primaryHit,
    vec2 lensSample,
    RTXDI_DIReservoir sourceReservoir,
    bool skipVisibilityCheck)
{
    return scatterReprojectionShift(
        rng,
        reconnectionData,
        time,
        primaryHit,
        lensSample,
        sourceReservoir,
        false,
        false,
        skipVisibilityCheck
    );
}

ShiftedPathData scatterReprojectionShift(
    inout RTXDI_RandomSamplerState rng,
    inout ReconnectionData reconnectionData,
    float time,
    HitInfo primaryHit,
    vec2 lensSample,
    RTXDI_DIReservoir sourceReservoir)
{
    return scatterReprojectionShift(
        rng,
        reconnectionData,
        time,
        primaryHit,
        lensSample,
        sourceReservoir,
        false,
        false,
        false
    );
}

ShiftedPathData gatherLensVertexCopyShift(
    inout RTXDI_RandomSamplerState rng,
    inout ReconnectionData reconnectionData,
    float time,
    vec2 fractionalPixel,
    vec2 lensSample,
    RTXDI_DIReservoir sourceReservoir,
    bool sourcePreviousFrame,
    bool targetPreviousFrame)
{
    ShiftedPathData shiftedPath = lt_temporal_empty_shifted_path();

    if (!lt_is_viewport_uv_in_bounds(fractionalPixel))
    {
        return shiftedPath;
    }

    lt_next_random(rng);

    bool hitEnvMap = lt_temporal_hit_env_map(reconnectionData);
    vec3 rayOriginW = lt_temporal_camera_origin(time, lensSample);
    vec3 cameraForward = lt_temporal_camera_forward(time);
    if (hitEnvMap)
    {
        vec3 filmWorld = lt_temporal_film_world(time, fractionalPixel);
        vec3 toFilm = filmWorld - rayOriginW;
        float filmDistance = length(toFilm);
        if (filmDistance < 1e-6f)
        {
            return shiftedPath;
        }

        vec3 rayDir = toFilm / filmDistance;
        if (!lt_temporal_trace_visibility_ray(rayOriginW, rayDir, 0.001f, 1e5f))
        {
            return shiftedPath;
        }

        shiftedPath.fractionalPixel = fractionalPixel;
        shiftedPath.lensSample = lensSample;
        shiftedPath.firstRayDir = rayDir;
        shiftedPath.subPixelJacobian = lt_temporal_compute_env_map_subpixel_jacobian(
            rayDir,
            cameraForward
        );
        shiftedPath.lensVertexJacobian = lt_temporal_compute_env_map_lens_vertex_jacobian(
            rayDir,
            cameraForward,
            time
        );
        shiftedPath.radiance = lt_temporal_handle_reconnection_env_map(sourceReservoir);
        return shiftedPath;
    }

    ivec2 landingPixel = ivec2(floor(fractionalPixel));
    RAB_Surface landingSurface = lt_temporal_load_surface(landingPixel, targetPreviousFrame);
    if (!RAB_IsSurfaceValid(landingSurface))
    {
        return shiftedPath;
    }

    HitInfo primaryHit = lt_temporal_make_shifted_hit_info(
        landingPixel,
        landingSurface,
        targetPreviousFrame
    );
    vec3 primaryHitPosW = landingSurface.worldPos;
    vec3 primaryHitNormalW = landingSurface.geoNormal;

    vec3 toHit = primaryHitPosW - rayOriginW;
    float hitDistance = length(toHit);
    if (hitDistance < 1e-6f)
    {
        return shiftedPath;
    }

    vec3 rayDir = toHit / hitDistance;
    if (!lt_temporal_trace_visibility_ray(
            rayOriginW,
            rayDir,
            0.001f,
            0.999f * hitDistance))
    {
        return shiftedPath;
    }

    RAB_Surface shiftedSurface = landingSurface;
    shiftedSurface.viewDir = -rayDir;
    shiftedSurface.viewDepth = hitDistance;

    shiftedPath.primaryHit = primaryHit;
    shiftedPath.primaryHit.viewDepth = hitDistance;
    shiftedPath.fractionalPixel = fractionalPixel;
    shiftedPath.lensSample = lensSample;
    shiftedPath.firstRayDir = rayDir;
    shiftedPath.subPixelJacobian = lt_temporal_compute_subpixel_jacobian(
        primaryHitPosW,
        primaryHitNormalW,
        rayOriginW,
        rayDir,
        cameraForward
    );
    shiftedPath.lensVertexJacobian = lt_temporal_compute_lens_vertex_copy_jacobian(
        primaryHitPosW,
        primaryHitNormalW,
        rayOriginW,
        rayDir,
        lt_temporal_camera_pos(time),
        cameraForward,
        time
    );

    if (lt_temporal_hit_primary_light(reconnectionData))
    {
        shiftedPath.radiance = lt_temporal_handle_reconnection_primary_light(sourceReservoir);
        return shiftedPath;
    }

    shiftedSurface.worldPos = primaryHitPosW;
    shiftedSurface.geoNormal = primaryHitNormalW;
    shiftedSurface.normal = landingSurface.normal;
    shiftedPath.radiance = lt_temporal_path_reconnection_shift(
        reconnectionData,
        sourceReservoir,
        shiftedSurface,
        sourcePreviousFrame,
        targetPreviousFrame,
        shiftedPath.secondaryPathJacobian
    );
    return shiftedPath;
}

ShiftedPathData gatherLensVertexCopyShift(
    inout RTXDI_RandomSamplerState rng,
    inout ReconnectionData reconnectionData,
    float time,
    vec2 fractionalPixel,
    vec2 lensSample,
    RTXDI_DIReservoir sourceReservoir)
{
    return gatherLensVertexCopyShift(
        rng,
        reconnectionData,
        time,
        fractionalPixel,
        lensSample,
        sourceReservoir,
        false,
        false
    );
}

ShiftedPathData gatherPrimaryHitReconnectionShift(
    inout RTXDI_RandomSamplerState rng,
    inout ReconnectionData reconnectionData,
    float time,
    vec2 fractionalPixel,
    HitInfo primaryHit,
    RTXDI_DIReservoir sourceReservoir,
    bool sourcePreviousFrame,
    bool targetPreviousFrame)
{
    ShiftedPathData shiftedPath = lt_temporal_empty_shifted_path();
    bool hitEnvMap = lt_temporal_hit_env_map(reconnectionData);

    if (!lt_is_viewport_uv_in_bounds(fractionalPixel))
    {
        return shiftedPath;
    }

    if (!hitEnvMap && !lt_temporal_has_primary_hit(primaryHit))
    {
        return shiftedPath;
    }

    lt_next_random(rng);

    vec3 cameraPosW = lt_temporal_camera_pos(time);
    vec3 cameraU = normalize(lt_temporal_camera_u(time));
    vec3 cameraV = normalize(lt_temporal_camera_v(time));
    vec3 cameraForward = lt_temporal_camera_forward(time);
    vec3 filmWorld = lt_temporal_film_world(time, fractionalPixel);

    vec3 primaryHitPosW = vec3(0.0f);
    vec3 primaryHitNormalW = vec3(0.0f);
    vec3 rayDir = vec3(0.0f);
    if (hitEnvMap)
    {
        if (dot(reconnectionData.firstWi, reconnectionData.firstWi) <= 1e-12f)
        {
            return shiftedPath;
        }

        rayDir = -normalize(reconnectionData.firstWi);
        primaryHitPosW = filmWorld + rayDir;
    }
    else
    {
        primaryHitPosW = primaryHit.worldPos;
        primaryHitNormalW = scatter_decode_surface_face_normal(primaryHit.faceId);

        vec3 toPrimaryHit = primaryHitPosW - filmWorld;
        float filmDistance = length(toPrimaryHit);
        if (filmDistance < 1e-6f)
        {
            return shiftedPath;
        }

        rayDir = toPrimaryHit / filmDistance;
    }

    float cosSensor = dot(cameraForward, rayDir);
    if (cosSensor <= 1e-4f)
    {
        return shiftedPath;
    }

    float camZ = dot(primaryHitPosW - cameraPosW, cameraForward);
    float rayT = camZ / cosSensor;
    vec3 rayOrigin = primaryHitPosW - rayT * rayDir;
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
        if (!hitEnvMap)
        {
            rayDir = normalize(primaryHitPosW - rayOrigin);
        }
    }

    float hitDistance = length(primaryHitPosW - rayOrigin);
    if (hitDistance < 1e-6f)
    {
        return shiftedPath;
    }

    float rayMin = hitEnvMap ? 0.001f : (0.001f * hitDistance);
    float rayMax = hitEnvMap ? 1e5f : (0.999f * hitDistance);
    if (!lt_temporal_trace_visibility_ray(rayOrigin, rayDir, rayMin, rayMax))
    {
        return shiftedPath;
    }

    shiftedPath.primaryHit = primaryHit;
    shiftedPath.primaryHit.viewDepth = hitEnvMap ? 0.0f : hitDistance;
    shiftedPath.fractionalPixel = fractionalPixel;
    shiftedPath.lensSample = lensLocalNormalized;
    shiftedPath.firstRayDir = rayDir;

    if (hitEnvMap)
    {
        shiftedPath.subPixelJacobian = lt_temporal_compute_env_map_subpixel_jacobian(
            rayDir,
            cameraForward
        );
        shiftedPath.lensVertexJacobian = lt_temporal_compute_env_map_lens_vertex_jacobian(
            rayDir,
            cameraForward,
            time
        );
        shiftedPath.radiance = lt_temporal_handle_reconnection_env_map(sourceReservoir);
        return shiftedPath;
    }

    ivec2 landingPixel = ivec2(floor(fractionalPixel));
    RAB_Surface primaryHitSurface = lt_temporal_load_surface(landingPixel, targetPreviousFrame);
    if (!RAB_IsSurfaceValid(primaryHitSurface))
    {
        return shiftedPath;
    }

    RAB_Surface shiftedSurface = primaryHitSurface;
    shiftedSurface.worldPos = primaryHitPosW;
    shiftedSurface.geoNormal = primaryHitNormalW;
    shiftedSurface.normal = primaryHitNormalW;
    shiftedSurface.viewDir = -rayDir;
    shiftedSurface.viewDepth = hitDistance;

    shiftedPath.subPixelJacobian = lt_temporal_compute_subpixel_jacobian(
        primaryHitPosW,
        primaryHitNormalW,
        rayOrigin,
        rayDir,
        cameraForward
    );
    shiftedPath.lensVertexJacobian = lt_temporal_compute_primary_hit_reconnection_jacobian(
        primaryHitPosW,
        primaryHitNormalW,
        rayDir,
        cameraPosW,
        cameraForward,
        rayT,
        time
    );

    if (lt_temporal_hit_primary_light(reconnectionData))
    {
        shiftedPath.radiance = lt_temporal_handle_reconnection_primary_light(sourceReservoir);
        return shiftedPath;
    }

    shiftedPath.radiance = lt_temporal_path_reconnection_shift(
        reconnectionData,
        sourceReservoir,
        shiftedSurface,
        sourcePreviousFrame,
        targetPreviousFrame,
        shiftedPath.secondaryPathJacobian
    );
    return shiftedPath;
}

ShiftedPathData gatherPrimaryHitReconnectionShift(
    inout RTXDI_RandomSamplerState rng,
    inout ReconnectionData reconnectionData,
    float time,
    vec2 fractionalPixel,
    HitInfo primaryHit,
    RTXDI_DIReservoir sourceReservoir)
{
    return gatherPrimaryHitReconnectionShift(
        rng,
        reconnectionData,
        time,
        fractionalPixel,
        primaryHit,
        sourceReservoir,
        false,
        false
    );
}

ReconnectionData ReconnectionData_update(
    ReconnectionData source,
    ShiftedPathData shiftedPath)
{
    ReconnectionData updated = source;
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
