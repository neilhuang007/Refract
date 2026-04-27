#ifndef PHOTONICS_RESERVOIR_SPLATTING_MULTI_REPROJECT_TEMPORAL_SAMPLES_GLSL
#define PHOTONICS_RESERVOIR_SPLATTING_MULTI_REPROJECT_TEMPORAL_SAMPLES_GLSL

#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"
#include "/photonics/lighttree/restir_di_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_spatial_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_shared.glsl"
#include "/photonics/lighttree/restir_di_temporal_shift_mapping.glsl"
#include "/photonics/lighttree/restir_di_temporal.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_common.glsl"

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_REPROJECT_STAGE)
bool lt_multi_temporal_reproject_partition(
    ReconnectionData prevReconnection,
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

    bool hitValid = prevReconnection.firstHit.viewDepth > 0.0f
        && any(greaterThan(abs(prevReconnection.firstHit.worldPos), vec3(0.0f)));

    rayOrigin = lt_temporal_camera_origin(newTime, prevReconnection.lensSample);
    rayDirection = vec3(0.0f);
    traceDistance = 0.0f;
    hitDistantLight = false;
    newFractionalPixel = vec2(-1.0f);
    float apertureRadius = lt_di_temporal_camera_aperture_radius();
    vec2 lensLocal = apertureRadius * prevReconnection.lensSample;

    if (hitValid)
    {
        vec3 toPrimaryHit = prevReconnection.firstHit.worldPos - rayOrigin;
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
        traceDistance = 1e5f;
        hitDistantLight = true;
    }
    else
    {
        return false;
    }

    vec3 cameraU = normalize(lt_temporal_camera_u(newTime));
    vec3 cameraV = normalize(lt_temporal_camera_v(newTime));
    vec3 cameraForward = lt_temporal_camera_forward(newTime);
    vec3 camRay = vec3(
        dot(cameraU, rayDirection),
        dot(cameraV, rayDirection),
        dot(cameraForward, rayDirection)
    );
    if (camRay.z <= 1e-3f)
    {
        return false;
    }

    float focalDistance = length(lt_temporal_camera_w(newTime));
    vec2 film = lensLocal + focalDistance * (camRay.xy / camRay.z);
    vec2 ndc = film / vec2(
        length(lt_temporal_camera_u(newTime)),
        length(lt_temporal_camera_v(newTime))
    );
    newFractionalPixel =
        (vec2(0.5f, -0.5f) * ndc + vec2(0.5f, 0.5f)) * vec2(viewWidth, viewHeight);
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

    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel)
    );
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
