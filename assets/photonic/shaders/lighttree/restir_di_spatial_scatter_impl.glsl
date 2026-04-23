#ifndef PHOTONICS_RESTIR_DI_SPATIAL_SCATTER_IMPL_GLSL
#define PHOTONICS_RESTIR_DI_SPATIAL_SCATTER_IMPL_GLSL

#include "/photonics/lighttree/restir_di_temporal_dof.glsl"

// ============================================================================
// GLSL port of SpatialResampling.rt.slang helpers
// (reference/repos/Reservoir-Splatting/Source/RenderPasses/ReservoirSplatting/ShiftMapping.slang).
//
// The slang reference relies on two shift helpers:
//   * gatherLensVertexCopyShift        -- re-traces a primary ray through
//     `fractionalPixel` with the stored lens sample, producing a new primary
//     hit. The lens vertex Jacobian is INTENTIONALLY NOT applied because the
//     lens sample is kept fixed.
//   * gatherPrimaryHitReconnectionShift -- keeps the stored primary hit and
//     solves for a new implicit lens position on the aperture. The lens vertex
//     Jacobian IS applied when combining shift ratios.
//
// Minecraft uses a pinhole camera (`apertureRadius == 0`), so the two shifts
// collapse onto each other -- the ray origin in both cases is the current
// camera position (there is no lens aperture to choose from). To preserve
// exact parity with the reference when future DoF is added we still carry
// the `d0*d0/(d1*d1) * |cosNormal|/|cosSensor|` lens vertex Jacobian formula
// and let the caller decide whether to apply it.
//
// These helpers are algorithm-only utilities; they neither allocate nor bind
// additional state and never write to any sampler. They MUST NOT be used
// outside Stage 3 (spatial resampling).
// ============================================================================

// Reference parity note:
//   The reference `SampleGenerator` is used to seed `path.sg` inside each
//   shift. We emulate that with our `RTXDI_RandomSamplerState` because the
//   draws become part of the reconstructed light sample's unit-interval UV
//   -- our light samples are analytic point lights and ignore UV, so the exact
//   consumption count of the random stream inside `gatherX` is not observable
//   by the light-sample outputs. We still advance the RNG to match control
//   flow with the reference shift.
struct SpatialShiftedPathData {
    vec3  radiance;                 // f / p after reconnection (identical to reference ShiftedPathData.radiance)
    vec2  fractionalPixel;          // subpixel-weighted pixel where the shift lands (float pixel coords)
    vec2  lensSample;               // lens-domain sample carried by the shifted path (0.5 for pinhole)
    ReservoirSplattingHitInfo primaryHit; // reference-aligned first-hit payload carried across stages
    vec3  primaryHitNormal;         // world-space first hit geometric normal
    vec3  firstRayDir;              // normalized primary ray direction at the new film point
    vec2  subPixel;                 // fract-part of `fractionalPixel`; mirrors reference sp.subPixel
    float subPixelJacobian;         // |cos_normal| / (d^2 * |cos_sensor|^3)
    float lensVertexJacobian;       // d0^2 / d1^2 * |cos_normal| / |cos_sensor|  (1.0 for the lens-copy branch after ratio cancellation)
    float secondaryPathJacobian;    // secondary reconnection Jacobian (area-measure geometry term)
    bool  isValid;                  // whether the shift succeeded (visibility + bounds)
};

SpatialShiftedPathData spatial_empty_shifted_path()
{
    SpatialShiftedPathData s;
    s.radiance              = vec3(0.0f);
    s.fractionalPixel       = vec2(-1.0f);
    s.lensSample            = vec2(0.0f);
    s.primaryHit            = ReservoirSplattingHitInfo_empty();
    s.primaryHitNormal      = vec3(0.0f, 1.0f, 0.0f);
    s.firstRayDir           = vec3(0.0f, 0.0f, -1.0f);
    s.subPixel              = vec2(0.0f);
    s.subPixelJacobian      = 1.0f;
    s.lensVertexJacobian    = 1.0f;
    s.secondaryPathJacobian = 1.0f;
    s.isValid               = false;
    return s;
}

ReservoirSplattingHitInfo spatial_make_shifted_hit_info(ivec2 pixel, RAB_Surface surface)
{
    ReservoirSplattingHitInfo hitInfo = ReservoirSplattingHitInfo_empty();
    vec4 identityData = scatter_load_surface_identity(pixel, false);
    hitInfo.worldPos = surface.worldPos;
    hitInfo.viewDepth = surface.viewDepth;
    hitInfo.faceId = uint(round(identityData.w));
    return hitInfo;
}

// Converts a fractional pixel coordinate to a normalized [0,1]^2 pixel-sample
// UV. Matches the reference film sampling: the film origin is the upper-left
// corner of the pixel, so (fractionalPixel / frameDim) lies in [0,1].
vec2 spatial_fractional_pixel_to_uv(vec2 fractionalPixel)
{
    return clamp(
        fractionalPixel / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0)),
        vec2(0.0f),
        vec2(1.0f)
    );
}

vec3 spatial_camera_pos(float time)
{
    return world_camera_position;
}

vec3 spatial_camera_u(float time)
{
    return lt_di_temporal_camera_u();
}

vec3 spatial_camera_v(float time)
{
    return lt_di_temporal_camera_v();
}

vec3 spatial_camera_w(float time)
{
    return lt_di_temporal_camera_w();
}

vec3 spatial_camera_forward(float time)
{
    return normalize(spatial_camera_w(time));
}

vec3 spatial_lens_world_offset(float time, vec2 lensSample)
{
    float apertureRadius = lt_di_temporal_camera_aperture_radius();
    if (apertureRadius <= 0.0f)
    {
        return vec3(0.0f);
    }

    return apertureRadius
        * (lensSample.x * normalize(spatial_camera_u(time))
            + lensSample.y * normalize(spatial_camera_v(time)));
}

vec3 spatial_film_world(float time, vec2 fractionalPixel)
{
    vec2 p = spatial_fractional_pixel_to_uv(fractionalPixel);
    vec2 ndc = vec2(2.0f, -2.0f) * p + vec2(-1.0f, 1.0f);
    return spatial_camera_pos(time)
        + ndc.x * spatial_camera_u(time)
        + ndc.y * spatial_camera_v(time)
        + spatial_camera_w(time);
}

// Reference: ShiftMapping.slang:141,278
float spatial_compute_subpixel_jacobian(
    vec3 primaryHitPosW,
    vec3 primaryHitNormalW,
    vec3 rayOriginW,
    vec3 rayDir,
    vec3 camForward)
{
    vec3 toHit = primaryHitPosW - rayOriginW;
    float dist = length(toHit);
    if (dist < 1e-6f) return 1.0f;

    float cosNormal = abs(dot(-rayDir, primaryHitNormalW));
    float cosSensor = max(abs(dot(camForward, rayDir)), 1e-6f);

    float jacobian = cosNormal / (dist * dist * cosSensor * cosSensor * cosSensor);
    return max(jacobian, 1e-10f);
}

// Reference: ShiftMapping.slang:144-146,280-282
//   d0 = length(cameraW) / |camZ| * dist            (focal-plane crossing distance)
//   d1 = dist - d0                                  (pixel-to-hit distance)
//   J_lens = (d0^2 / d1^2) * |cosNormal| / |cosSensor|
// For an ideal pinhole camera, length(cameraW) corresponds to the film-plane
// separation. We bake that constant into `focalDistance` = 1.0 for consistency
// with area_compute_jacobian_eval_data_at_base. The ratio cancels between
// source and shifted copies, so the exact constant is a parity hinge only
// when DoF is introduced.
float spatial_compute_lens_vertex_jacobian(
    vec3 primaryHitPosW,
    vec3 primaryHitNormalW,
    vec3 rayOriginW,
    vec3 rayDir,
    float time,
    vec3 camForward)
{
    vec3 toHit = primaryHitPosW - rayOriginW;
    float dist = length(toHit);
    if (dist < 1e-6f) return 1.0f;

    float cosNormal = abs(dot(rayDir, primaryHitNormalW));
    float cosSensor = max(abs(dot(camForward, rayDir)), 1e-6f);

    float focalDistance = length(spatial_camera_w(time));
    float camZ = max(abs(dot(toHit, camForward)), 1e-6f);
    float d0 = focalDistance / camZ * dist;
    float d1 = max(dist - d0, 1e-6f);

    float j = (d0 * d0) / (d1 * d1) * cosNormal / cosSensor;
    return max(j, 1e-10f);
}

// Trace a visibility ray to the recorded primary hit. Returns true when the
// primary hit is still the closest blocker along the ray.
//
// The voxel tracer uses a bounded segment; a blocker between origin and
// `targetPosW` fails the check. A reconnection "near" the target cell is
// accepted, matching `scatter_reproject_reconnection_to_frame`.
bool spatial_trace_reconnection_visibility(
    vec3 rayOriginW,
    vec3 rayDirW,
    float traceMaxDistance)
{
    ray.origin           = rayOriginW;
    ray.direction        = rayDirW;
    ray_min_trace_distance = 0.001f;
    ray_max_trace_distance = max(traceMaxDistance, 0.0f);
    trace_ray(ray, true);
    bool unoccluded = !ray.result_hit && ray_distance_limit_reached;
    ray_min_trace_distance = 0.0f;
    ray_max_trace_distance = -1.0f;
    return unoccluded;
}

// Recompute the integrand `L_e * f * cos / pdf` for the shifted path.
//
// This is the GLSL analog of `handleReconnectionPrimaryLight`
// (the `pathLength == 1` branch of `gatherX`) composed with
// `pathReconnectionShift` for length-2 direct-illumination paths.
// Minecraft DI stores a single NEE light per reservoir, so the
// "secondary" reconnection collapses to:
//   * decode the light (with per-frame remap) at the SHIFTED surface
//   * evaluate f * cos / pdf via lt_shade_surface_light_sample
vec3 spatial_reconnect_and_evaluate_radiance(
    RTXDI_DIReservoir sourceReservoir,
    RAB_Surface shiftedSurface)
{
    if (!RTXDI_IsValidDIReservoir(sourceReservoir)) {
        return vec3(0.0f);
    }

    RAB_LightSample shiftedLight = lt_decode_reservoir_sample_for_frame(
        sourceReservoir,
        shiftedSurface,
        false,   // source is current-frame (spatial stage operates within a frame)
        false    // target is current-frame as well
    );
    if (shiftedLight.index < 0 || shiftedLight.solidAnglePdf <= 0.0f) {
        return vec3(0.0f);
    }

    return max(lt_shade_surface_light_sample(shiftedSurface, shiftedLight), vec3(0.0f));
}

// ----------------------------------------------------------------------------
// gatherLensVertexCopyShift -- reference SpatialResampling.rt.slang:131
// ----------------------------------------------------------------------------
// Re-trace a primary ray through the virtual film at `fractionalPixel` with
// the source's stored lens sample. For pinhole camera, the lens sample is
// ignored (aperture radius == 0) and the ray origin is `world_camera_position`.
// Instead of issuing a new ray trace we read the G-buffer at the rounded
// pixel -- that is the Minecraft-style analog of "trace the primary ray".
//
// The returned `primaryHit` is the G-buffer hit position at the landing
// pixel; if the landing pixel is out-of-bounds or hits the sky, the shift
// fails.
SpatialShiftedPathData spatial_gather_lens_vertex_copy_shift(
    inout RTXDI_RandomSamplerState           rng,
    ReservoirSplattingReconnectionData       sourceReconnection,
    float                                    time,                       // retained for parity; unused for pinhole
    vec2                                     fractionalPixel,
    vec2                                     lensSample,
    RTXDI_DIReservoir                        sourceReservoir)
{
    SpatialShiftedPathData shifted = spatial_empty_shifted_path();

    if (!lt_is_viewport_uv_in_bounds(fractionalPixel)) {
        return shifted;
    }

    // Advance RNG in lockstep with the reference to keep downstream samplers
    // observing the same stream position.
    lt_next_random(rng);

    ivec2 landingPixel = ivec2(floor(fractionalPixel));
    landingPixel = clamp(landingPixel, ivec2(0), ivec2(int(viewWidth) - 1, int(viewHeight) - 1));

    RAB_Surface landingSurface = RAB_GetGBufferSurface(landingPixel, false);
    if (!RAB_IsSurfaceValid(landingSurface)) {
        return shifted;
    }

    vec3 cameraPosW   = spatial_camera_pos(time) + spatial_lens_world_offset(time, lensSample);
    vec3 camForward   = spatial_camera_forward(time);
    vec3 hitPosW      = landingSurface.worldPos;
    vec3 hitNormalW   = landingSurface.geoNormal;

    vec3 toHit = hitPosW - cameraPosW;
    float dist = length(toHit);
    if (dist < 1e-6f) {
        return shifted;
    }
    vec3 rayDir = toHit / dist;

    shifted.primaryHit            = spatial_make_shifted_hit_info(landingPixel, landingSurface);
    shifted.primaryHitNormal      = hitNormalW;
    shifted.firstRayDir           = rayDir;
    shifted.fractionalPixel       = fractionalPixel;
    shifted.lensSample            = lensSample;
    shifted.subPixel              = clamp(fractionalPixel - floor(fractionalPixel), vec2(0.0f), vec2(1.0f));
    shifted.subPixelJacobian      = spatial_compute_subpixel_jacobian(
        hitPosW, hitNormalW, cameraPosW, rayDir, camForward);
    shifted.lensVertexJacobian    = spatial_compute_lens_vertex_jacobian(
        hitPosW, hitNormalW, cameraPosW, rayDir, time, camForward);
    shifted.secondaryPathJacobian = scatter_resolve_secondary_path_jacobian(
        landingSurface,
        sourceReservoir,
        lt_decode_reservoir_sample_for_frame(sourceReservoir, landingSurface, false, false)
    );

    // Radiance recomputation at the new first hit -- this matches the reference's
    // `gPathTracer.handleReconnectionPrimaryLight(path)` for pathLength==1
    // and `pathReconnectionShift` for pathLength==2 DI. Both collapse to
    // `f * L * cos / pdf` evaluated at the shifted surface for Minecraft DI.
    shifted.radiance = spatial_reconnect_and_evaluate_radiance(sourceReservoir, landingSurface);
    shifted.isValid  = true;
    return shifted;
}

// ----------------------------------------------------------------------------
// gatherPrimaryHitReconnectionShift -- reference SpatialResampling.rt.slang:132,183
// ----------------------------------------------------------------------------
// Keep the stored primary hit (`primaryHit = sourceReconnection.worldPos`)
// and solve for a new lens-plane intersection that still views the hit from
// `fractionalPixel`. For pinhole camera the lens plane collapses to the
// camera position, so the only failure modes are (a) off-screen film,
// (b) primaryHit behind the camera, (c) visibility blocker between camera
// and primaryHit.
SpatialShiftedPathData spatial_gather_primary_hit_reconnection_shift(
    inout RTXDI_RandomSamplerState           rng,
    ReservoirSplattingReconnectionData       sourceReconnection,
    float                                    time,                       // retained for parity; unused for pinhole
    vec2                                     fractionalPixel,
    vec3                                     primaryHitPosW,
    RTXDI_DIReservoir                        sourceReservoir)
{
    SpatialShiftedPathData shifted = spatial_empty_shifted_path();

    if (!lt_is_viewport_uv_in_bounds(fractionalPixel)) {
        return shifted;
    }

    if (dot(primaryHitPosW, primaryHitPosW) <= 0.0f) {
        return shifted;
    }

    lt_next_random(rng);

    vec3 cameraPosW = spatial_camera_pos(time);
    vec3 camU = normalize(spatial_camera_u(time));
    vec3 camV = normalize(spatial_camera_v(time));
    vec3 camForward = spatial_camera_forward(time);
    vec3 filmWorld = spatial_film_world(time, fractionalPixel);

    vec3 toHit = primaryHitPosW - filmWorld;
    float dist = length(toHit);
    if (dist < 1e-6f) {
        return shifted;
    }

    vec3 rayDir = toHit / dist;
    float cosSensor = dot(camForward, rayDir);
    if (cosSensor <= 1e-4f) {
        // primary hit is behind / tangential to the camera plane
        return shifted;
    }

    float camZ = dot(primaryHitPosW - cameraPosW, camForward);
    float rayT = camZ / cosSensor;
    vec3 rayOrigin = primaryHitPosW - rayT * rayDir;
    float apertureRadius = lt_di_temporal_camera_aperture_radius();
    vec2 lensLocalNormalized = vec2(0.0f);
    if (apertureRadius > 0.0f)
    {
        vec3 lensOffsetWorld = rayOrigin - cameraPosW;
        lensLocalNormalized = vec2(
            dot(lensOffsetWorld, camU),
            dot(lensOffsetWorld, camV)
        ) / apertureRadius;
        if (length(lensLocalNormalized) > 1.0f)
        {
            return shifted;
        }
    }
    else
    {
        rayOrigin = cameraPosW;
        rayDir = normalize(primaryHitPosW - rayOrigin);
        dist = length(primaryHitPosW - rayOrigin);
    }

    // Visibility test: the bounded segment from camera to primaryHit must be
    // unoccluded within `0.999 * dist`, matching ShiftMapping.slang:239.
    float traceMaxDistance = 0.999f * dist;
    if (!spatial_trace_reconnection_visibility(rayOrigin, rayDir, traceMaxDistance)) {
        return shifted;
    }

    // For the reconnection branch, the stored primary hit remains authoritative.
    // The landing pixel is used only to recover shading data for THAT exact hit;
    // if it does not resolve to the stored primary surface, the shift fails.
    ivec2 landingPixel = clamp(
        ivec2(floor(fractionalPixel)),
        ivec2(0),
        ivec2(int(viewWidth) - 1, int(viewHeight) - 1)
    );
    RAB_Surface primaryHitSurface = RAB_GetGBufferSurface(landingPixel, false);
    if (!RAB_IsSurfaceValid(primaryHitSurface)) {
        return shifted;
    }
    if (!scatter_reconnection_matches_surface(sourceReconnection, landingPixel, primaryHitSurface, false)) {
        return shifted;
    }

    vec3 primaryHitNormalW = primaryHitSurface.geoNormal;

    // Build a virtual surface at the stored primary hit with the new viewing
    // geometry. This mirrors `loadShadingData(primaryHit, ...)` in the
    // reference while keeping the primary-hit identity fixed to the stored
    // reconnection data.
    RAB_Surface shiftedSurface = primaryHitSurface;
    shiftedSurface.worldPos   = sourceReconnection.firstHit.worldPos;
    shiftedSurface.geoNormal  = primaryHitNormalW;
    shiftedSurface.normal     = primaryHitNormalW;
    shiftedSurface.viewDir    = -rayDir;
    shiftedSurface.viewDepth  = dist;

    shifted.primaryHit            = sourceReconnection.firstHit;
    shifted.primaryHit.viewDepth  = dist;
    shifted.primaryHitNormal      = primaryHitNormalW;
    shifted.firstRayDir           = rayDir;
    shifted.fractionalPixel       = fractionalPixel;
    shifted.lensSample            = lensLocalNormalized;
    shifted.subPixel              = clamp(fractionalPixel - floor(fractionalPixel), vec2(0.0f), vec2(1.0f));
    shifted.subPixelJacobian      = spatial_compute_subpixel_jacobian(
        primaryHitPosW, primaryHitNormalW, rayOrigin, rayDir, camForward);
    shifted.lensVertexJacobian    = spatial_compute_lens_vertex_jacobian(
        primaryHitPosW, primaryHitNormalW, rayOrigin, rayDir, time, camForward);
    shifted.secondaryPathJacobian = scatter_resolve_secondary_path_jacobian(
        shiftedSurface,
        sourceReservoir,
        lt_decode_reservoir_sample_for_frame(sourceReservoir, shiftedSurface, false, false)
    );

    shifted.radiance = spatial_reconnect_and_evaluate_radiance(sourceReservoir, shiftedSurface);
    shifted.isValid  = true;
    return shifted;
}

// Encapsulates ShiftMapping.slang's i < numLensVertexCopyShifts branch so the
// callsite stays close to the reference pseudocode.
SpatialShiftedPathData spatial_gather_shift(
    bool                                     lensVertexCopyShift,
    inout RTXDI_RandomSamplerState           rng,
    ReservoirSplattingReconnectionData       sourceReconnection,
    float                                    time,
    vec2                                     fractionalPixel,
    vec2                                     lensSample,
    vec3                                     primaryHitPosW,
    RTXDI_DIReservoir                        sourceReservoir)
{
    if (lensVertexCopyShift) {
        return spatial_gather_lens_vertex_copy_shift(
            rng, sourceReconnection, time, fractionalPixel, lensSample, sourceReservoir);
    }
    return spatial_gather_primary_hit_reconnection_shift(
        rng, sourceReconnection, time, fractionalPixel, primaryHitPosW, sourceReservoir);
}

// Reference: ShiftMapping.slang:75-79
//   gamma = 0.2 + 6.2 / (r - 5.6)        [clamped to [0.2, 1]]
//   gamma = 1 when r <= 0.2 (small CoC -> always lens-vertex-copy)
vec2 spatial_compute_depth_of_field_gather_shift_probabilities(float circleOfConfusion)
{
    float gamma;
    if (circleOfConfusion <= 0.2f) {
        gamma = 1.0f;
    } else {
        gamma = 0.2f + 6.2f / (circleOfConfusion - 5.6f);
        gamma = clamp(gamma, 0.2f, 1.0f);
    }
    return vec2(gamma, 1.0f - gamma);
}

// Minecraft has a pinhole camera (apertureRadius == 0) so the circle of
// confusion is always zero and gamma == 1. We still recompute the value
// dynamically so a future DoF hookup only needs to feed a non-zero aperture.
float spatial_compute_primary_hit_circle_of_confusion(vec3 primaryHitPosW)
{
    return computePrimaryHitCircleOfConfusion(primaryHitPosW);
}

float spatial_compute_env_map_circle_of_confusion()
{
    return computeEnvMapCircleOfConfusion();
}

#endif
