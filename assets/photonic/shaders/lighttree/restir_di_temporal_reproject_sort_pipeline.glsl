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
    out vec3 rayOrigin,
    out vec3 rayDirection,
    out float traceDistance,
    out bool hitDistantLight)
{
    float fractionalTime = lt_multi_temporal_partition_fraction(prevReconnection.time);
    float newTime = lt_multi_temporal_partition_time(fractionalTime, partitionIndex);
    hitValid = prevReconnection.firstHit.viewDepth > 0.0f
        && any(greaterThan(abs(prevReconnection.firstHit.worldPos), vec3(0.0f)));

    if (!scatter_project_reconnection_to_current_frame(
            prevReconnection,
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

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_REPROJECT_STAGE)
void ReprojectTemporalSamples_run(
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

    if (!hitDistantLight && traceDistance <= 1e-5f) {
        return;
    }
    if (!lt_scatter_trace_reconnection_visibility(
            rayOrigin,
            rayDirection,
            hitDistantLight ? traceDistance : (0.999f * traceDistance))) {
        return;
    }

    lt_temporal_scatter_append_contributor(newPixel, pixel, 1.0f);
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY)
void computeCellOffsetsStage(
    ivec2 pixel)
{
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
    SortReprojectedReservoirs_sortCellData(index);
}
#endif

#endif

#endif
