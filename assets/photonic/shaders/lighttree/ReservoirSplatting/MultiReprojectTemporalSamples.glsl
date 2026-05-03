#ifndef PHOTONICS_RESERVOIR_SPLATTING_MULTI_REPROJECT_TEMPORAL_SAMPLES_GLSL
#define PHOTONICS_RESERVOIR_SPLATTING_MULTI_REPROJECT_TEMPORAL_SAMPLES_GLSL

#include "/photonics/lighttree/restir_di_multi_temporal_reproject_bridge.glsl"

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_REPROJECT_STAGE)
bool lt_multi_temporal_reproject_partition(
    ReconnectionData prevReconnection,
    ivec2 sourcePixel,
    uint partitionIndex,
    out float newTime,
    out vec2 newFractionalPixel,
    out vec3 rayOrigin,
    out vec3 rayDirection,
    out float traceDistance,
    out bool hitDistantLight)
{
    float fractionalTime = lt_multi_temporal_partition_fraction(prevReconnection.time);
    newTime = lt_multi_temporal_partition_time(fractionalTime, partitionIndex);

    HitInfo resolvedFirstHit = lt_scatter_resolve_reconnection_first_hit(
        prevReconnection,
        sourcePixel,
        true
    );
    bool hitValid = resolvedFirstHit.viewDepth > 0.0f
        && any(greaterThan(abs(resolvedFirstHit.worldPos), vec3(0.0f)));

    rayOrigin = lt_temporal_camera_pos(newTime);
    rayDirection = vec3(0.0f);
    traceDistance = 0.0f;
    hitDistantLight = false;
    newFractionalPixel = vec2(-1.0f);

    if (hitValid)
    {
        vec3 toPrimaryHit = resolvedFirstHit.worldPos - rayOrigin;
        traceDistance = length(toPrimaryHit);
        if (!(traceDistance > 1e-6f))
        {
            return false;
        }

        rayDirection = toPrimaryHit / traceDistance;
    }
    else if (prevReconnection.lightIsDistant)
    {
        rayDirection = -normalize(prevReconnection.firstWi);
        traceDistance = 3.402823466e+38f;
        hitDistantLight = true;
    }
    else
    {
        return false;
    }

    vec3 cameraForward = normalize(lt_temporal_camera_w(newTime));
    float d = dot(rayDirection, cameraForward);
    if (d <= 1e-3f)
    {
        return false;
    }

    d *= lt_di_temporal_camera_tan_fov_y();
    vec3 cameraU = normalize(lt_temporal_camera_u(newTime));
    vec3 cameraV = normalize(lt_temporal_camera_v(newTime));
    vec2 offset = vec2(dot(rayDirection, cameraU), -dot(rayDirection, cameraV));
    vec2 ndc = vec2(0.5f, 0.5f) + offset / vec2(d * lt_di_temporal_camera_aspect_ratio(), d);
    newFractionalPixel = ndc * vec2(viewWidth, viewHeight);
    if (any(lessThan(newFractionalPixel, vec2(0.0f)))
        || any(greaterThanEqual(newFractionalPixel, vec2(viewWidth, viewHeight))))
    {
        rayDirection = vec3(0.0f);
        rayOrigin = vec3(0.0f);
        traceDistance = 0.0f;
        hitDistantLight = false;
        newFractionalPixel = vec2(-1.0f);
        return false;
    }

    return true;
}

void MultiReprojectTemporalSamples_run(
    ivec2 pixel)
{
    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return;
    }

    RTXDI_DIReservoir prevReservoir = lt_multi_temporal_load_previous_reservoir(pixel);
    if (all(equal(PathReservoir_getIntegrand(prevReservoir), vec3(0.0f)))) {
        return;
    }

    ReconnectionData prevReconnection = RestirDI_loadPreviousFrameReconnection(pixel);
    for (uint partitionIndex = 0u; partitionIndex < lt_multi_temporal_partition_count(); ++partitionIndex) {
        float newTime;
        vec2 newFractionalPixel;
        vec3 rayOrigin;
        vec3 rayDirection;
        float traceDistance;
        bool hitDistantLight;
        if (!lt_multi_temporal_reproject_partition(
            prevReconnection,
            pixel,
            partitionIndex,
            newTime,
            newFractionalPixel,
            rayOrigin,
            rayDirection,
            traceDistance,
            hitDistantLight
        )) {
            continue;
        }

        ivec2 newPixel = ivec2(floor(newFractionalPixel));
        if (!lt_is_viewport_uv_in_bounds(newPixel)) {
            continue;
        }

        if (!lt_scatter_trace_reconnection_visibility(
                rayOrigin,
                rayDirection,
                hitDistantLight ? traceDistance : (0.999f * traceDistance),
                !hitDistantLight)) {
            continue;
        }

        lt_multi_temporal_scatter_append_contributor(partitionIndex, newPixel, pixel);
    }
}
#endif

#endif
