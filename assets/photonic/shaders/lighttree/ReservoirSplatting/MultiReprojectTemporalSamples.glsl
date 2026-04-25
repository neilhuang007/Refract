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
float lt_multi_temporal_reproject_partition(
    ScatterReconnectionData prevReconnection,
    uint partitionIndex,
    out vec2 newFractionalPixel,
    out bool hitValid,
    out vec3 rayOrigin,
    out vec3 rayDirection,
    out float traceDistance,
    out bool hitDistantLight)
{
    float fractionalTime = lt_multi_temporal_partition_fraction(prevReconnection.time);
    float newTime = lt_multi_temporal_partition_time(fractionalTime, partitionIndex);
    ScatterReconnectionData partitionedReconnection = prevReconnection;
    partitionedReconnection.time = newTime;
    hitValid = prevReconnection.firstHit.viewDepth > 0.0f
        && any(greaterThan(abs(prevReconnection.firstHit.worldPos), vec3(0.0f)));

    if (!scatter_project_reconnection_to_current_frame(
            partitionedReconnection,
            newFractionalPixel,
            rayOrigin,
            rayDirection,
            traceDistance,
            hitDistantLight)) {
        rayDirection = vec3(0.0f);
        rayOrigin = vec3(0.0f);
        traceDistance = 0.0f;
        hitDistantLight = false;
        newFractionalPixel = vec2(-1.0f);
    }
    return newTime;
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

    ScatterReconnectionData prevReconnection = RestirDI_loadPreviousFrameReconnection(pixel);
    for (uint partitionIndex = 0u; partitionIndex < lt_multi_temporal_partition_count(); ++partitionIndex) {
        vec2 newFractionalPixel;
        bool hitValid;
        vec3 rayOrigin;
        vec3 rayDirection;
        float traceDistance;
        bool hitDistantLight;
        float newTime = lt_multi_temporal_reproject_partition(
            prevReconnection,
            partitionIndex,
            newFractionalPixel,
            hitValid,
            rayOrigin,
            rayDirection,
            traceDistance,
            hitDistantLight
        );
        if (newFractionalPixel.x < 0.0f || newFractionalPixel.y < 0.0f) {
            continue;
        }

        ivec2 newPixel = ivec2(floor(newFractionalPixel));
        if (!lt_is_viewport_uv_in_bounds(newPixel)) {
            continue;
        }

        vec3 normalizedRayDirection = normalize(rayDirection);
        vec3 cameraForward = normalize(mat3(gbufferModelView) * vec3(0.0f, 0.0f, -1.0f));
        float cameraFacing = dot(normalizedRayDirection, cameraForward);
        if (cameraFacing <= 0.001f) {
            continue;
        }

        ScatterReconnectionData partitionedReconnection = prevReconnection;
        partitionedReconnection.time = newTime;
        if (!hitValid && !partitionedReconnection.lightIsDistant) {
            continue;
        }
        if (!lt_scatter_trace_reconnection_visibility(
                rayOrigin,
                rayDirection,
                hitDistantLight ? traceDistance : (0.999f * traceDistance))) {
            continue;
        }

        lt_multi_temporal_scatter_append_contributor(partitionIndex, newPixel, pixel);
    }
}
#endif

#endif
