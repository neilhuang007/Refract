#ifndef PHOTONICS_RESTIR_DI_RECONNECTION_SURFACE_GLSL
#define PHOTONICS_RESTIR_DI_RECONNECTION_SURFACE_GLSL

vec4 scatter_load_surface_identity(ivec2 uv, bool previousFrame)
{
    return previousFrame
        ? texelFetch(prev_radiosity_identity, uv, 0)
        : texelFetch(radiosity_identity, uv, 0);
}

#if !defined(PH_LIGHTTREE_RECONNECTION_PACK_ONLY)

vec2 scatter_load_gather_floating_coords(ivec2 uv)
{
    return lt_load_floating_coords(uv);
}

bool scatter_reconnection_matches_surface(
    ReservoirSplattingReconnectionData reconnection,
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    bool previousFrame)
{
    vec4 currentIdentity = scatter_load_surface_identity(pixelPosition, previousFrame);
    uint currentFaceId = uint(round(currentIdentity.w));

    float maxDepth = max(reconnection.firstHit.viewDepth, currentSurface.viewDepth);
    float depthTolerance = max(1e-4f, 1e-3f * maxDepth);
    float worldTolerance = max(1e-4f, 1e-3f * maxDepth);
    float worldDistance = distance(reconnection.firstHit.worldPos, currentSurface.worldPos);
    bool depthCompatible = abs(reconnection.firstHit.viewDepth - currentSurface.viewDepth) <= depthTolerance;
    bool faceCompatible = reconnection.firstHit.faceId == currentFaceId;
    bool positionCompatible = worldDistance <= worldTolerance;

    return depthCompatible && faceCompatible && positionCompatible;
}

bool scatter_reconnection_matches_surface(
    ReservoirSplattingReconnectionData reconnection,
    ivec2 pixelPosition,
    RAB_Surface currentSurface)
{
    return scatter_reconnection_matches_surface(reconnection, pixelPosition, currentSurface, false);
}

vec2 scatter_forward_project_to_current_frame(vec3 worldPos)
{
    vec4 clipPos = modelview_projection * vec4(worldPos, 1.0f);
    if (clipPos.w <= 0.0f) {
        return vec2(-1.0f);
    }

    vec3 ndc = clipPos.xyz / clipPos.w;
    if (any(greaterThan(abs(ndc.xy), vec2(1.0f)))) {
        return vec2(-1.0f);
    }

    return (ndc.xy * 0.5f + 0.5f) * vec2(viewWidth, viewHeight);
}

float scatter_compute_subpixel_jacobian(
    vec3 primaryHitPos,
    vec3 primaryHitNormal,
    vec3 cameraPos,
    vec3 cameraForward)
{
    vec3 toHit = primaryHitPos - cameraPos;
    float dist = length(toHit);
    if (dist < 1e-6f) {
        return 1.0f;
    }

    vec3 rayDir = toHit / dist;
    float cosNormal = abs(dot(-rayDir, primaryHitNormal));
    float cosSensor = max(abs(dot(cameraForward, rayDir)), 1e-6f);
    float jacobian = cosNormal / (dist * dist * cosSensor * cosSensor * cosSensor);
    return max(jacobian, 1e-10f);
}

float scatter_compute_scatter_jacobian(
    float srcSubPixelJacobian,
    float dstSubPixelJacobian,
    float srcSecondaryPathJacobian,
    float dstSecondaryPathJacobian)
{
    float srcJ = srcSubPixelJacobian * srcSecondaryPathJacobian;
    float dstJ = dstSubPixelJacobian * dstSecondaryPathJacobian;
    if (srcJ < 1e-10f) {
        return 1.0f;
    }

    return clamp(dstJ / srcJ, 1e-4f, 1e4f);
}

float scatter_resolve_stored_subpixel_jacobian(
    ReservoirSplattingReconnectionData reconnection,
    RAB_Surface fallbackSurface,
    vec3 fallbackCameraPos,
    vec3 fallbackCameraForward)
{
    bool hasStoredJacobian = reconnection.firstHit.viewDepth > 0.0f
        && any(greaterThan(abs(reconnection.firstHit.worldPos), vec3(0.0f)))
        && reconnection.subPixelJacobian > 1e-10f;
    if (hasStoredJacobian) {
        return reconnection.subPixelJacobian;
    }

    return scatter_compute_subpixel_jacobian(
        fallbackSurface.worldPos,
        fallbackSurface.geoNormal,
        fallbackCameraPos,
        fallbackCameraForward
    );
}

float scatter_resolve_stored_secondary_jacobian(ReservoirSplattingReconnectionData reconnection)
{
    return max(reconnection.secondaryPathJacobian, 1e-10f);
}

#endif
