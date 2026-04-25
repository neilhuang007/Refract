#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_REPROJECT_SORT_PIPELINE_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_REPROJECT_SORT_PIPELINE_GLSL

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)
#include "/photonics/lighttree/restir_di_temporal.glsl"

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_REPROJECT_STAGE)
#include "/photonics/lighttree/ReservoirSplatting/MultiReprojectTemporalSamples.glsl"
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

    lt_reproject_temporal_samples_append_record(pixel, newPixel);
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
