#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_REPROJECT_SORT_PIPELINE_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_REPROJECT_SORT_PIPELINE_GLSL

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)
#include "/photonics/lighttree/restir_di_temporal.glsl"

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_REPROJECT_STAGE)
float lt_multi_temporal_reproject_partition(
    ScatterReconnectionData prevReconnection,
    uint partitionIndex,
    out vec2 newFractionalPixel,
    out bool hitValid,
    out vec3 rayDirection)
{
    float fractionalTime = lt_multi_temporal_partition_fraction(prevReconnection.time);
    float newTime = lt_multi_temporal_partition_time(fractionalTime, partitionIndex);
    hitValid = prevReconnection.firstHit.viewDepth > 0.0f
        && any(greaterThan(abs(prevReconnection.firstHit.worldPos), vec3(0.0f)));

    vec3 rayOrigin;
    float traceDistance;
    bool hitDistantLight;
    if (!scatter_project_reconnection_to_current_frame(
            prevReconnection,
            newFractionalPixel,
            rayOrigin,
            rayDirection,
            traceDistance,
            hitDistantLight)) {
        rayDirection = vec3(0.0f);
        newFractionalPixel = vec2(-1.0f);
    }
    return newTime;
}

void MultiReprojectTemporalSamples_run(
    ivec2 pixel)
{
    if (ph_scatter_temporal_enabled <= 0.5f || ph_debug_enable_direct_temporal_reuse < 0.5f) {
        return;
    }

    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return;
    }

    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel)
    );
    if (!RTXDI_IsValidDIReservoir(prevReservoir)) {
        return;
    }

    ScatterReconnectionData prevReconnection = RestirDI_loadPreviousFrameReconnection(pixel);
    RAB_Surface prevSurface = lt_load_previous_surface(pixel);
    for (uint partitionIndex = 0u; partitionIndex < lt_multi_temporal_partition_count(); ++partitionIndex) {
        vec2 newFractionalPixel;
        bool hitValid;
        vec3 rayDirection;
        float newTime = lt_multi_temporal_reproject_partition(
            prevReconnection,
            partitionIndex,
            newFractionalPixel,
            hitValid,
            rayDirection
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

        RAB_Surface currentSurface = RAB_GetGBufferSurface(newPixel, false);
        if (!RAB_IsSurfaceValid(currentSurface)) {
            continue;
        }

        ScatterReconnectionData partitionedReconnection = prevReconnection;
        partitionedReconnection.time = newTime;
        if (hitValid) {
            if (!lt_area_is_temporal_neighbor_valid(currentSurface, prevSurface, partitionedReconnection, newPixel)) {
                continue;
            }
        } else if (!partitionedReconnection.lightIsDistant) {
            continue;
        }

        lt_multi_temporal_scatter_append_contributor(partitionIndex, newPixel, pixel);
    }
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_REPROJECT_STAGE)
void ReprojectTemporalSamples_run(
    ivec2 pixel)
{
    if (ph_scatter_temporal_enabled <= 0.5f || ph_debug_enable_direct_temporal_reuse < 0.5f) {
        return;
    }

    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return;
    }

    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel)
    );
    if (!RTXDI_IsValidDIReservoir(prevReservoir)) {
        return;
    }

    ScatterReconnectionData prevReconnection = RestirDI_loadPreviousFrameReconnection(pixel);

    bool hasPrimaryHit = prevReconnection.firstHit.viewDepth > 0.0f;
    vec2 newFractionalPixel = vec2(-1.0f);
    vec3 rayOrigin = vec3(0.0f);
    vec3 rayDirection = vec3(0.0f);
    float traceDistance = 0.0f;
    bool hitDistantLight = false;
    if (!scatter_project_reconnection_to_current_frame(
            prevReconnection,
            newFractionalPixel,
            rayOrigin,
            rayDirection,
            traceDistance,
            hitDistantLight)) {
        return;
    }

    if (newFractionalPixel.x < 0.0f || newFractionalPixel.y < 0.0f) {
        return;
    }

    ivec2 newPixel = ivec2(floor(newFractionalPixel));
    if (!lt_is_viewport_uv_in_bounds(newPixel)) {
        return;
    }

    if (hasPrimaryHit) {
        if (traceDistance <= 1e-5f) {
            return;
        }

        ray.origin = rayOrigin;
        ray.direction = rayDirection;
        ray_target = ivec3(floor(prevReconnection.firstHit.worldPos));
        ray_ignore_block_id = -1;
        ray_stop_on_target = true;
        ray_min_trace_distance = 0.001f * traceDistance;
        ray_max_trace_distance = max(ray_min_trace_distance, 0.999f * traceDistance);
        trace_ray(ray, true);
        ray_target = ivec3(-9999);
        ray_ignore_block_id = -1;
        ray_stop_on_target = false;
        ray_min_trace_distance = 0.0f;
        ray_max_trace_distance = -1.0f;
        if (!lt_visibility_trace_is_unoccluded()) {
            return;
        }
    }

    lt_temporal_scatter_append_contributor(newPixel, pixel, 1.0f);
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY)
void computeCellOffsetsStage(
    ivec2 pixel)
{
    if (ph_scatter_temporal_enabled <= 0.5f) {
        return;
    }

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
    return;
#else
    SortReprojectedReservoirs_computeCellOffsets(pixel);
#endif
}
#else
void computeCellOffsetsStage(
    ivec2 pixel)
{
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
void sortCellDataStage(
    uint index)
{
    if (ph_scatter_temporal_enabled <= 0.5f) {
        return;
    }

    SortReprojectedReservoirs_sortCellData(index);
}
#endif

#endif

#endif
