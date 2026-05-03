#ifndef PHOTONICS_RESTIR_DI_MULTI_TEMPORAL_REPROJECT_BRIDGE_GLSL
#define PHOTONICS_RESTIR_DI_MULTI_TEMPORAL_REPROJECT_BRIDGE_GLSL

// Minimal direct-only bridge for MultiReprojectTemporalSamples. The full
// reuse/scatter stack declares enough unrelated SSBOs to exceed fragment-stage
// storage-buffer limits on Iris, so this pass keeps only the buffers it appends.

#include "/photonics/lighttree/restir_di_temporal_camera.glsl"
#include "/photonics/lighttree/restir_di_reservoir_payload.glsl"
#include "/photonics/lighttree/restir_di_reconnection_payload.glsl"
#include "/photonics/lighttree/restir_di_reconnection_packing.glsl"
#include "/photonics/lighttree/restir_di_temporal_buffer_bridge.glsl"

bool lt_is_viewport_uv_in_bounds(ivec2 uv)
{
    return all(greaterThanEqual(uv, ivec2(0)))
        && all(lessThan(uv, ivec2(int(viewWidth), int(viewHeight))));
}

bool lt_is_viewport_uv_in_bounds(vec2 uv)
{
    return all(greaterThanEqual(uv, vec2(0.0f)))
        && all(lessThan(uv, vec2(viewWidth, viewHeight)));
}

vec3 lt_temporal_camera_pos(float time)
{
    return lt_di_temporal_camera_pos_at_time(time);
}

vec3 lt_temporal_camera_u(float time)
{
    return lt_di_temporal_camera_u_at_time(time);
}

vec3 lt_temporal_camera_v(float time)
{
    return lt_di_temporal_camera_v_at_time(time);
}

vec3 lt_temporal_camera_w(float time)
{
    return lt_di_temporal_camera_w_at_time(time);
}

RTXDI_DIReservoir lt_multi_temporal_load_previous_reservoir(ivec2 pixel)
{
    RTXDI_DIReservoir reservoir = RTXDI_EmptyDIReservoir();
    rtxdi_unpack_reservoir_payload(
        reservoir,
        texelFetch(prev_radiosity_reservoirs, pixel, 0),
        texelFetch(prev_radiosity_reservoir_samples, pixel, 0),
        texelFetch(prev_radiosity_reservoir_meta, pixel, 0)
    );
    return reservoir;
}

ReconnectionData RestirDI_loadPreviousFrameReconnection(ivec2 pixelPosition)
{
    ReconnectionData reconnectionData;
    scatter_load_prev_reconnection(pixelPosition, reconnectionData);
    return reconnectionData;
}

bool lt_multi_temporal_hit_matches_previous_surface_identity(HitInfo hitInfo, ivec2 pixel)
{
    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return false;
    }

    vec4 identityData = texelFetch(prev_radiosity_identity, pixel, 0);
    uint packedIdentity = uint(round(identityData.w));
    return hitInfo.faceId == (packedIdentity & 0x7u)
        && hitInfo.materialId == (packedIdentity >> 3u);
}

HitInfo lt_scatter_resolve_reconnection_first_hit(
    ReconnectionData reconnectionData,
    ivec2 sourcePixel,
    bool sourcePreviousFrame)
{
    HitInfo resolvedHit = reconnectionData.firstHit;
    if (!(resolvedHit.viewDepth > 0.0f) || !sourcePreviousFrame) {
        return resolvedHit;
    }

    if (!lt_multi_temporal_hit_matches_previous_surface_identity(resolvedHit, sourcePixel)) {
        return resolvedHit;
    }

    vec4 positionData = texelFetch(prev_radiosity_position, sourcePixel, 0);
    if (!(positionData.w > 0.0f)) {
        return resolvedHit;
    }

    resolvedHit.worldPos = positionData.xyz;
    resolvedHit.viewDepth = positionData.w;
    return resolvedHit;
}

bool lt_scatter_trace_reconnection_visibility(
    vec3 rayOriginW,
    vec3 rayDirW,
    float traceMaxDistance,
    bool isReprojection)
{
    float rayMin = (isReprojection && traceMaxDistance < 1e4f)
        ? (0.001f * (traceMaxDistance / 0.999f))
        : 0.001f;
    ray.origin = rayOriginW;
    ray.direction = rayDirW;
    ray_min_trace_distance = rayMin;
    ray_max_trace_distance = traceMaxDistance;
    trace_ray(ray, true);
    bool unoccluded = !ray.result_hit && ray_distance_limit_reached;
    ray_min_trace_distance = 0.0f;
    ray_max_trace_distance = -1.0f;
    return unoccluded;
}

uint lt_temporal_scatter_cell_index_from_pixel(ivec2 pixelPosition)
{
    uint width = uint(max(int(viewWidth), 1));
    uint height = uint(max(int(viewHeight), 1));
    uint x = uint(clamp(pixelPosition.x, 0, int(width) - 1));
    uint y = uint(clamp(pixelPosition.y, 0, int(height) - 1));
    return y * width + x;
}

#include "/photonics/lighttree/restir_di_multi_temporal_records.glsl"

#endif
