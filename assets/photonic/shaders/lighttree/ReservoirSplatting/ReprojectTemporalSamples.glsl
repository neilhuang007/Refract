#ifndef PHOTONICS_RESERVOIR_SPLATTING_REPROJECT_TEMPORAL_SAMPLES_GLSL
#define PHOTONICS_RESERVOIR_SPLATTING_REPROJECT_TEMPORAL_SAMPLES_GLSL

#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"
#include "/photonics/lighttree/restir_di_spatial_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_shared.glsl"
#include "/photonics/lighttree/restir_di_temporal_shift_mapping.glsl"
#include "/photonics/lighttree/restir_di_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_common.glsl"

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

    ReconnectionData prevReconnection = RestirDI_loadPreviousFrameReconnection(pixel);
    vec2 newFractionalPixel;
    vec3 rayOrigin;
    vec3 rayDirection;
    float traceDistance;
    bool hitDistantLight;
    if (!scatter_project_reconnection_to_current_frame(
            prevReconnection,
            newFractionalPixel,
            rayOrigin,
            rayDirection,
            traceDistance,
            hitDistantLight)) {
        return;
    }

    float visibilityTraceDistance = hitDistantLight
        ? traceDistance
        : (0.999f * traceDistance);
    if (!lt_scatter_trace_reconnection_visibility(
            rayOrigin,
            rayDirection,
            visibilityTraceDistance,
            !hitDistantLight)) {
        return;
    }

    ivec2 newPixel = ivec2(floor(newFractionalPixel));
    lt_reproject_temporal_samples_append_record(pixel, newPixel);
}
#endif

#endif
