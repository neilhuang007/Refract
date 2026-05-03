#version 430
#define PH_GI_TEMPORAL_GLOBAL_COUNTER_BUFFER 1
#define PH_GI_TEMPORAL_CELL_COUNTER_BUFFER 1
#define PH_GI_TEMPORAL_RECORD_BUFFER 1

in vec4 direction_vert_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/restir_gi_bridge.glsl"
#include "/photonics/lighttree/ReservoirSplatting/GITemporalSplatting.glsl"

bool gi_temporal_splat_visibility_to_previous_hit(RAB_Surface previousSurface)
{
    vec3 targetRtPos = lt_surface_rt_pos(previousSurface);
    vec3 rayDelta = targetRtPos - rt_camera_position;
    float rayLength = length(rayDelta);
    if (rayLength <= 1e-4f) {
        return false;
    }

    ray.origin = rt_camera_position;
    ray.direction = rayDelta / rayLength;
    ray_target = ivec3(-9999);
    ray_ignore_block_id = -1;
    ray_min_trace_distance = 0.001f;
    ray_max_trace_distance = rayLength * 0.999f;
    trace_ray(ray, true);
    ray_target = ivec3(-9999);
    ray_ignore_block_id = -1;
    ray_min_trace_distance = 0.0f;
    ray_max_trace_distance = -1.0f;
    return lt_visibility_trace_is_unoccluded();
}

void main()
{
    ivec2 sourcePixel = ivec2(gl_FragCoord.xy);
    if (!lt_is_viewport_uv_in_bounds(sourcePixel)) {
        return;
    }

    int activeCheckerboardField = int(ph_restir_active_checkerboard_field);
    if (!RTXDI_IsActiveCheckerboardPixel(sourcePixel, true, activeCheckerboardField)) {
        return;
    }

    RAB_Surface previousSurface = lt_load_previous_surface(sourcePixel);
    if (!lt_is_valid_surface(previousSurface)) {
        return;
    }

    int previousCheckerboardField = lt_previous_checkerboard_field(activeCheckerboardField);
    ivec2 sourceReservoirPos = RTXDI_PixelPosToReservoirPos(sourcePixel, previousCheckerboardField);
    RTXDI_GIReservoir previousReservoir = RTXDI_LoadPreviousGIReservoir(sourceReservoirPos, previousCheckerboardField);
    if (!RTXDI_IsValidGIReservoir(previousReservoir)) {
        return;
    }

    vec4 currentClip = modelview_projection * vec4(previousSurface.worldPos, 1.0f);
    if (!ph_is_valid_clip_projection(currentClip)) {
        return;
    }

    currentClip.xyz /= currentClip.w;
    if (!all(lessThan(abs(currentClip.xy), vec2(1.0f))) || currentClip.w <= 0.0f) {
        return;
    }

    ivec2 targetPixel = ivec2((currentClip.xy * 0.5f + 0.5f) * vec2(viewWidth, viewHeight));
    if (!lt_is_viewport_uv_in_bounds(targetPixel)) {
        return;
    }

    if (!gi_temporal_splat_visibility_to_previous_hit(previousSurface)) {
        return;
    }

    RTXDI_ActivateCheckerboardPixel(targetPixel, false, activeCheckerboardField);
    if (!lt_is_viewport_uv_in_bounds(targetPixel)) {
        return;
    }

    ivec2 targetReservoirPos = RTXDI_PixelPosToReservoirPos(targetPixel, activeCheckerboardField);
    if (!lt_is_active_reservoir_lane(targetReservoirPos)) {
        return;
    }

    gi_temporal_splat_append_source(sourcePixel, targetReservoirPos);
}
