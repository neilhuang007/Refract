#ifndef PHOTONICS_RESTIR_DI_SCATTER_IMPL_GLSL
#define PHOTONICS_RESTIR_DI_SCATTER_IMPL_GLSL
// ============================================================================
// This module contains the reusable helper functions that support the full
// Reservoir Splatting temporal stage family implemented by the active bridge:
//   * CollectTemporalSamples
//   * GatherTemporalResampling
//   * ReprojectTemporalSamples
//   * SortReprojectedReservoirs
//   * ScatterTemporalResampling
//   * MultiReprojectTemporalSamples
//   * MultiSortReprojectedReservoirs
//   * MultiScatterTemporalResampling
//   * ShiftMapping.slang::scatterReprojectionShift analogs
//
// The bridge exports the stage entry points directly and this file owns the
// shared shift mappings, MIS terms, and confidence bookkeeping used by those
// stages without introducing local behavioral adaptations.
// ============================================================================

// ---------------------------------------------------------------------------
// Small helpers -- confidence cap, pHat, and reservoir-domain ergonomics.
// ---------------------------------------------------------------------------

// camera.cameraW normalization used in scatterReprojectionShift.
vec3 lt_current_camera_forward() {
    return normalize(mat3(gbufferModelView) * vec3(0.0f, 0.0f, -1.0f));
}
vec3 lt_previous_camera_forward() {
    return normalize(mat3(gbufferPreviousModelView) * vec3(0.0f, 0.0f, -1.0f));
}

float lt_scatter_reservoir_confidence(RTXDI_DIReservoir reservoir, ScatterReconnectionData reconnection) {
    return PathReservoir_getConfidence(reservoir);
}

float lt_scatter_radiance_phat(vec3 radiance) {
    return ph_luminance(max(radiance, vec3(0.0f)));
}

// Reference parity (ScatterTemporalResampling.rt.slang:88,130):
//   shiftedJacobian = (shifted.subPixelJacobian * shifted.secondaryPathJacobian)
//                   / (base.subPixelJacobian * base.secondaryPathJacobian)
// Returns 0 when the base path is degenerate so the calling MIS math clamps to 0.
float lt_scatter_shift_jacobian_ratio(
    float shiftedSubPixelJacobian,
    float shiftedSecondaryPathJacobian,
    float baseSubPixelJacobian,
    float baseSecondaryPathJacobian)
{
    float baseJ = baseSubPixelJacobian * baseSecondaryPathJacobian;
    if (baseJ <= 1e-10f) {
        return 0.0f;
    }
    float shiftedJ = shiftedSubPixelJacobian * shiftedSecondaryPathJacobian;
    float ratio = shiftedJ / baseJ;
    return (isnan(ratio) || isinf(ratio) || ratio < 0.0f) ? 0.0f : ratio;
}

// ---------------------------------------------------------------------------
// `ShiftedPathData` analog.  Mirrors the output of scatterReprojectionShift
// from ShiftMapping.slang:301-421 in OpenGL/GLSL form.  We do not attempt to
// carry the full path state (the port is DI-only, pathLength == 1 or 2),
// only the fields the MIS / addSampleFromReservoir logic needs.
// ---------------------------------------------------------------------------

struct LtScatterShiftedPath {
    bool  valid;
    ReservoirSplattingHitInfo firstHit;
    vec2  fractionalPixel;
    vec2  lensSample;
    vec3  firstRayDir;
    vec3  radiance;
    float subPixelJacobian;
    float secondaryPathJacobian;
    float lensVertexJacobian;
};

LtScatterShiftedPath lt_scatter_empty_shifted_path() {
    LtScatterShiftedPath s;
    s.valid = false;
    s.firstHit = ReservoirSplattingHitInfo_empty();
    s.fractionalPixel = vec2(0.0f);
    s.lensSample = vec2(0.5f);
    s.firstRayDir = vec3(0.0f);
    s.radiance = vec3(0.0f);
    s.subPixelJacobian = 1.0f;
    s.secondaryPathJacobian = 1.0f;
    s.lensVertexJacobian = 1.0f;
    return s;
}

bool lt_scatter_trace_reconnection_visibility(
    vec3 rayOriginW,
    vec3 rayDirW,
    float traceMaxDistance)
{
    ray.origin = rayOriginW;
    ray.direction = rayDirW;
    ray_min_trace_distance = 0.001f;
    ray_max_trace_distance = max(traceMaxDistance, ray_min_trace_distance);
    trace_ray(ray, true);
    bool unoccluded = !ray.result_hit && ray_distance_limit_reached;
    ray_min_trace_distance = 0.0f;
    ray_max_trace_distance = -1.0f;
    return unoccluded;
}

// ---------------------------------------------------------------------------
// scatterReprojectionShift analog (ShiftMapping.slang:301-421).
//
// Shifts a reconnection's primary hit into the given target camera domain
// (current or previous frame), computing the fractional pixel the hit lands
// on and re-evaluating the radiance / Jacobians under the target surface.
// Performs a visibility trace from the target camera origin to the first
// hit (or along firstWi for distant lights).  The caller supplies the target
// surface that will receive the shifted reservoir's shading: for the
// previous-domain shift during canonical MIS the target surface is the prev
// g-buffer surface at floor(fractionalPixel); for the current-domain shift
// of a prev contributor the target surface is the current g-buffer surface
// at the resolve pixel.
//
// Returns `valid = false` when any of the reference's early-out conditions
// triggers (no primary hit, point behind camera, reprojection off-screen,
// visibility ray blocked, or degenerate geometry).
// ---------------------------------------------------------------------------
bool scatter_project_reconnection_to_frame(
    ScatterReconnectionData reconnection,
    bool previousFrame,
    out vec2 projectedPixel,
    out vec3 rayOrigin,
    out vec3 rayDirection,
    out float traceMaxDistance,
    out bool hitDistantLight);

vec2 lt_scatter_project_to_previous_frame(vec3 worldPos)
{
    vec4 clip = gbufferPreviousProjection * (gbufferPreviousModelView * vec4(worldPos, 1.0f));
    if (clip.w <= 1e-6f) {
        return vec2(-1.0f);
    }
    vec3 ndc = clip.xyz / clip.w;
    if (abs(ndc.x) > 1.0f || abs(ndc.y) > 1.0f || ndc.z < -1.0f || ndc.z > 1.0f) {
        return vec2(-1.0f);
    }
    return (ndc.xy * 0.5f + 0.5f) * vec2(viewWidth, viewHeight);
}

bool scatter_project_reconnection_to_previous_frame(
    ScatterReconnectionData reconnection,
    out vec2 projectedPixel,
    out vec3 rayOrigin,
    out vec3 rayDirection,
    out float traceMaxDistance,
    out bool hitDistantLight)
{
    return scatter_project_reconnection_to_frame(
        reconnection,
        true,
        projectedPixel,
        rayOrigin,
        rayDirection,
        traceMaxDistance,
        hitDistantLight
    );
}

bool scatter_project_reconnection_to_current_frame(
    ScatterReconnectionData reconnection,
    out vec2 projectedPixel,
    out vec3 rayOrigin,
    out vec3 rayDirection,
    out float traceMaxDistance,
    out bool hitDistantLight)
{
    return scatter_project_reconnection_to_frame(
        reconnection,
        false,
        projectedPixel,
        rayOrigin,
        rayDirection,
        traceMaxDistance,
        hitDistantLight
    );
}

bool scatter_project_reconnection_to_frame(
    ScatterReconnectionData reconnectionData,
    bool previousFrame,
    out vec2 projectedPixel,
    out vec3 rayOrigin,
    out vec3 rayDirection,
    out float traceMaxDistance,
    out bool hitDistantLight)
{
    projectedPixel = vec2(-1.0f);
    rayOrigin = previousFrame ? previous_world_camera_position : world_camera_position;
    rayDirection = vec3(0.0f);
    traceMaxDistance = 0.0f;
    hitDistantLight = false;

    bool hasPrimaryHit = reconnectionData.firstHit.viewDepth > 0.0f
        && any(greaterThan(abs(reconnectionData.firstHit.worldPos), vec3(0.0f)));

    if (hasPrimaryHit)
    {
        vec3 hitPosition = reconnectionData.firstHit.worldPos;
        rayDirection = normalize(hitPosition - rayOrigin);
        traceMaxDistance = length(hitPosition - rayOrigin);
        if (!(traceMaxDistance > 1e-5f))
        {
            return false;
        }

        projectedPixel = previousFrame
            ? lt_scatter_project_to_previous_frame(hitPosition)
            : scatter_forward_project_to_current_frame(hitPosition);
        return projectedPixel.x >= 0.0f && projectedPixel.y >= 0.0f;
    }

    if (!reconnectionData.lightIsDistant)
    {
        return false;
    }

    rayDirection = -normalize(reconnectionData.firstWi);
    traceMaxDistance = 1e5f;
    vec3 farPoint = rayOrigin + rayDirection * traceMaxDistance;
    projectedPixel = previousFrame
        ? lt_scatter_project_to_previous_frame(farPoint)
        : scatter_forward_project_to_current_frame(farPoint);
    hitDistantLight = true;
    return projectedPixel.x >= 0.0f && projectedPixel.y >= 0.0f;
}

bool lt_scatter_reprojection_shift(
    ScatterReconnectionData reconnectionData,
    RTXDI_DIReservoir sourceReservoir,
    bool targetPreviousFrame,
    RAB_Surface targetSurface,
    out LtScatterShiftedPath shifted)
{
    shifted = lt_scatter_empty_shifted_path();

    if (!RAB_IsSurfaceValid(targetSurface)) {
        return false;
    }

    vec2 projectedPixelF;
    vec3 projectedRayOrigin;
    vec3 projectedRayDirection;
    float projectedTraceMaxDistance;
    bool projectedHitDistantLight;
    bool reprojectOk = targetPreviousFrame
        ? scatter_project_reconnection_to_previous_frame(
            reconnectionData,
            projectedPixelF,
            projectedRayOrigin,
            projectedRayDirection,
            projectedTraceMaxDistance,
            projectedHitDistantLight)
        : scatter_project_reconnection_to_current_frame(
            reconnectionData,
            projectedPixelF,
            projectedRayOrigin,
            projectedRayDirection,
            projectedTraceMaxDistance,
            projectedHitDistantLight);

    if (!reprojectOk) {
        return false;
    }

    ivec2 landingPixel = ivec2(floor(projectedPixelF));
    if (!lt_is_viewport_uv_in_bounds(landingPixel)) {
        return false;
    }

    float visibilityTraceDistance = projectedHitDistantLight
        ? projectedTraceMaxDistance
        : (0.999f * projectedTraceMaxDistance);
    if (!lt_scatter_trace_reconnection_visibility(
            projectedRayOrigin,
            projectedRayDirection,
            visibilityTraceDistance)) {
        return false;
    }

    if (!scatter_reconnection_matches_surface(reconnectionData, landingPixel, targetSurface, targetPreviousFrame)) {
        return false;
    }

    vec3 cameraPos = targetPreviousFrame ? previous_world_camera_position : world_camera_position;
    vec3 cameraForward = targetPreviousFrame ? lt_previous_camera_forward() : lt_current_camera_forward();
    float subPixelJacobian = scatter_compute_subpixel_jacobian(
        reconnectionData.firstHit.worldPos,
        targetSurface.geoNormal,
        cameraPos,
        cameraForward
    );

    shifted.valid = true;
    shifted.firstHit = reconnectionData.firstHit;
    shifted.fractionalPixel = projectedPixelF;
    shifted.lensSample = clamp(reconnectionData.lensSample, vec2(0.0f), vec2(1.0f));
    shifted.firstRayDir = projectedRayDirection;
    shifted.subPixelJacobian = max(subPixelJacobian, 1e-10f);
    shifted.lensVertexJacobian = max(reconnectionData.lensVertexJacobian, 1e-10f);
    shifted.radiance = PathReservoir_getIntegrand(sourceReservoir);
    shifted.secondaryPathJacobian = max(reconnectionData.secondaryPathJacobian, 1e-10f);
    return true;
}

// Helper around the frame-camera-position uniforms.
vec3 lt_scatter_camera_pos_for_frame(bool previousFrame) {
    return previousFrame ? previous_world_camera_position : world_camera_position;
}

RAB_Surface lt_scatter_build_shifted_primary_surface(
    ScatterReconnectionData sourceReconnection,
    RAB_Surface matchedSurface,
    vec3 firstRayDirection,
    bool targetPreviousFrame)
{
    RAB_Surface shiftedSurface = matchedSurface;
    vec3 cameraPos = lt_scatter_camera_pos_for_frame(targetPreviousFrame);
    shiftedSurface.worldPos = sourceReconnection.firstHit.worldPos;
    shiftedSurface.viewDir = -normalize(firstRayDirection);
    shiftedSurface.viewDepth = length(sourceReconnection.firstHit.worldPos - cameraPos);
    return shiftedSurface;
}

bool lt_scatter_update_shifted_reservoir(
    ScatterReconnectionData sourceReconnection,
    RTXDI_DIReservoir sourceReservoir,
    bool sourcePreviousFrame,
    bool targetPreviousFrame,
    RAB_Surface targetSurface,
    ivec2 targetPixel,
    out LtScatterShiftedPath shifted,
    out RTXDI_DIReservoir shiftedReservoir,
    out ScatterReconnectionData shiftedReconnection,
    out float shiftedJacobian);

RAB_Surface lt_scatter_load_target_surface(
    ivec2 pixel,
    bool previousFrame)
{
    return previousFrame
        ? lt_load_previous_surface(pixel)
        : RAB_GetGBufferSurface(pixel, false);
}

bool lt_scatter_update_shifted_reservoir_to_previous_frame(
    ScatterReconnectionData sourceReconnection,
    RTXDI_DIReservoir sourceReservoir,
    bool sourcePreviousFrame,
    out LtScatterShiftedPath shifted,
    out RTXDI_DIReservoir shiftedReservoir,
    out ScatterReconnectionData shiftedReconnection,
    out float shiftedJacobian)
{
    shifted = lt_scatter_empty_shifted_path();
    shiftedReservoir = RTXDI_EmptyDIReservoir();
    shiftedReconnection = scatter_empty_reconnection();
    shiftedJacobian = 0.0f;

    vec2 projectedPixel;
    vec3 rayOrigin;
    vec3 rayDirection;
    float traceMaxDistance;
    bool hitDistantLight;
    if (!scatter_project_reconnection_to_previous_frame(
            sourceReconnection,
            projectedPixel,
            rayOrigin,
            rayDirection,
            traceMaxDistance,
            hitDistantLight)) {
        return false;
    }

    ivec2 targetPixel = ivec2(floor(projectedPixel));
    if (!lt_is_viewport_uv_in_bounds(targetPixel)) {
        return false;
    }

    RAB_Surface targetSurface = lt_scatter_load_target_surface(targetPixel, true);
    if (!RAB_IsSurfaceValid(targetSurface)) {
        return false;
    }

    return lt_scatter_update_shifted_reservoir(
        sourceReconnection,
        sourceReservoir,
        sourcePreviousFrame,
        true,
        targetSurface,
        targetPixel,
        shifted,
        shiftedReservoir,
        shiftedReconnection,
        shiftedJacobian
    );
}

// ---------------------------------------------------------------------------
// Shifted-reservoir update + evaluation.
//
// For a reservoir + reconnection pair captured in the source frame, produces:
//   * `shiftedReservoir`      -- the reservoir with its light index translated
//                                 to the target frame and its domain samples
//                                 repointed at the shifted pixel
//   * `shiftedReconnection`   -- reconnection with its primary-hit position,
//                                 firstWi, subPixel, jacobians, and integrand
//                                 re-evaluated against the target surface
//   * `shiftedJacobian`       -- ratio (dst / src) of (subPixel * secondary)
//
// Reference analog:
//   scatterReprojectionShift(...) -> shifted path
//   prevReconnection.update(shiftedPrev)
//   prevReservoir.setSubPixel(shiftedPrev.fractionalPixel)
//
// Returns false when the shift is degenerate (prev integrand 0, missing light
// in target frame, visibility trace blocked, or zero target pHat).
// ---------------------------------------------------------------------------
// Matches ShiftMapping.slang::scatterReprojectionShift (the reservoir-shift
// half; `scatter_reproject_reconnection_to_frame` in reuse_bridge.glsl covers
// the geometry-only reprojection step). The helper name is intentionally based
// on the reference update semantics instead of a generic "translate" label.
bool lt_scatter_update_shifted_reservoir(
    ScatterReconnectionData sourceReconnection,
    RTXDI_DIReservoir       sourceReservoir,
    bool                    sourcePreviousFrame,
    bool                    targetPreviousFrame,
    RAB_Surface             targetSurface,
    ivec2                   targetPixel,
    out LtScatterShiftedPath shifted,
    out RTXDI_DIReservoir    shiftedReservoir,
    out ScatterReconnectionData shiftedReconnection,
    out float               shiftedJacobian)
{
    shifted = lt_scatter_empty_shifted_path();
    shiftedReservoir = RTXDI_EmptyDIReservoir();
    shiftedReconnection = scatter_empty_reconnection();
    shiftedJacobian = 0.0f;

    if (lt_scatter_radiance_phat(PathReservoir_getIntegrand(sourceReservoir)) <= 0.0f) {
        return false;
    }
    if (sourceReconnection.subPixelJacobian <= 1e-10f
     || sourceReconnection.secondaryPathJacobian <= 1e-10f)
    {
        return false;
    }

    if (!lt_scatter_reprojection_shift(
        sourceReconnection,
        sourceReservoir,
        targetPreviousFrame,
        targetSurface,
        shifted)) {
        return false;
    }

    // Translate the source reservoir's light index into the target frame's
    // light list.  For the Minecraft port this also supplies the remapped
    // light used to shade the integrand.
    shiftedReservoir = lt_translate_reservoir_between_frames(
        sourceReservoir,
        sourcePreviousFrame,
        targetPreviousFrame
    );
    if (!RTXDI_IsValidDIReservoir(shiftedReservoir)) {
        return false;
    }

    // The shifted reservoir now sits in the target pixel's cell with a
    // subPixel == fract(shiftedCurr.fractionalPixel) (reference parity --
    // ScatterTemporalResampling.rt.slang:139 sets it from prevReconnection
    // after update(shiftedPrev); ShiftMapping.slang writes shifted.fractionalPixel
    // into the selected reservoir's subPixel after the shift is finalized).
    vec2 shiftedSubPixel = clamp(fract(shifted.fractionalPixel), vec2(0.0f), vec2(1.0f - 1e-5f));
    PathReservoir_setSubPixel(shiftedReservoir, targetPixel, shiftedSubPixel);
    shiftedReservoir.lensSampleUV = clamp(sourceReconnection.lensSample, vec2(0.0f), vec2(1.0f));
    lt_area_finalize_candidate(shiftedReservoir, targetPixel, shiftedReservoir.pathSample);

    RAB_Surface shiftedPrimarySurface = lt_scatter_build_shifted_primary_surface(
        sourceReconnection,
        targetSurface,
        shifted.firstRayDir,
        targetPreviousFrame
    );

    RAB_LightSample shiftedLight = lt_decode_reservoir_sample_for_frame(
        shiftedReservoir,
        shiftedPrimarySurface,
        sourcePreviousFrame,
        targetPreviousFrame
    );
    if (shiftedLight.index < 0) {
        return false;
    }

    float targetPdf = lt_surface_target_pdf(shiftedPrimarySurface, shiftedLight);
    if (targetPdf <= 0.0f) {
        return false;
    }
    shiftedReservoir.targetPdf = targetPdf;

    vec3 shiftedIntegrand = max(lt_shade_surface_light_sample(shiftedPrimarySurface, shiftedLight), vec3(0.0f));
    float secondaryPathJacobian = scatter_resolve_secondary_path_jacobian(
        shiftedPrimarySurface,
        shiftedReservoir,
        shiftedLight
    );
    shifted.radiance = shiftedIntegrand;
    shifted.secondaryPathJacobian = secondaryPathJacobian;

    shiftedJacobian = lt_scatter_shift_jacobian_ratio(
        shifted.subPixelJacobian,
        secondaryPathJacobian,
        sourceReconnection.subPixelJacobian,
        sourceReconnection.secondaryPathJacobian
    );
    if (shiftedJacobian <= 0.0f) {
        return false;
    }

    // Reference parity (ScatterTemporalResampling.rt.slang:136):
    //   prevReconnection.update(shiftedPrev)
    // which overwrites the reconnection's hit position, incident dir,
    // subPixel, lensSample, and jacobians with the shifted values.  We mirror
    // that here so the caller receives a reconnection suitable for storage
    // into the resolved reservoir's sidecar.  We do NOT mutate age or
    // spatialDistance (the reference does neither).
    shiftedReconnection = sourceReconnection;
    shiftedReconnection.firstHit.worldPos = sourceReconnection.firstHit.worldPos;
    shiftedReconnection.firstWi = -normalize(shifted.firstRayDir);
    shiftedReconnection.subPixel = shiftedSubPixel;
    shiftedReconnection.lensSample = shifted.lensSample;
    shiftedReconnection.subPixelJacobian = max(shifted.subPixelJacobian, 1e-10f);
    shiftedReconnection.lensVertexJacobian = max(shifted.lensVertexJacobian, 1e-10f);
    shiftedReconnection.secondaryPathJacobian = max(secondaryPathJacobian, 1e-10f);
    shiftedReconnection.firstHit.faceId = uint(round(scatter_load_surface_identity(targetPixel, targetPreviousFrame).w));
    shiftedReconnection.secondHit.faceId = shiftedReconnection.firstHit.faceId;
    shiftedReconnection.time = sourceReconnection.time;
    return true;
}

// ---------------------------------------------------------------------------
// MIS (Reference parity: ScatterTemporalResampling.rt.slang:80-148).
//
// Canonical current-sample MIS:
//     m1 = luminance(currReservoir.integrand) * currReservoir.confidence
//     m2 = luminance(shiftedCurr.radiance) * shiftedJacobian * prevReservoir.confidence
//   -> currSampleMIS = m1 / (m1 + m2)
//
// Previous-sample MIS (per contributor):
//     m1 = luminance(shiftedPrev.radiance) * shiftedJacobian * currReservoir.confidence
//     m2 = luminance(prevReservoir.integrand) * prevReservoir.confidence
//   -> prevSampleMIS = m2 / (m1 + m2)
// ---------------------------------------------------------------------------

float lt_scatter_canonical_mis(
    float currIntegrandPHat,
    float currConfidence,
    float shiftedCurrRadiancePHat,
    float shiftedJacobian,
    float prevConfidence,
    bool  shiftedValid)
{
    float m1 = currIntegrandPHat * currConfidence;
    if (m1 <= 0.0f) {
        return 0.0f;
    }
    float m2 = shiftedValid
        ? (shiftedCurrRadiancePHat * shiftedJacobian * prevConfidence)
        : 0.0f;
    if (isnan(m2) || isinf(m2) || m2 < 0.0f) {
        m2 = 0.0f;
    }
    float denom = m1 + m2;
    return (denom > 0.0f) ? (m1 / denom) : 0.0f;
}

// ---------------------------------------------------------------------------
// UCW extraction helper -- `PathReservoir::computeUCW` (Reservoir.slang:112-116).
//
//   pHat = luminance(integrand)
//   return (pHat == 0) ? 0 : totalWeight / pHat
//
// The Photonics port now follows a single DI contract across the scatter path:
//
//   * Initial-sampling output   : weightSum = totalWeight.
//   * Temporal-scatter output   : weightSum = totalWeight.
//   * Spatial-resampling output : weightSum = totalWeight / (neighbors + 1).
//   * Previous-frame history    : weightSum = totalWeight (copied from spatial).
//
// Therefore every scatter-stage caller recovers `other.computeUCW()` the same
// way as the reference: `reservoir.weightSum / luminance(storedIntegrand)`.
// ---------------------------------------------------------------------------
float lt_scatter_compute_ucw(
    RTXDI_DIReservoir reservoir,
    vec3              storedIntegrand)
{
    float pHatStored = lt_scatter_radiance_phat(storedIntegrand);
    if (pHatStored <= 0.0f) {
        return 0.0f;
    }
    float totalWeight = max(reservoir.weightSum, 0.0f);
    if (totalWeight <= 0.0f) {
        return 0.0f;
    }
    float ucw = totalWeight / pHatStored;
    return (isnan(ucw) || isinf(ucw) || ucw < 0.0f) ? 0.0f : ucw;
}

// ---------------------------------------------------------------------------
// addSampleFromReservoir (Reservoir.slang:83-96 PathReservoir::addSampleFromReservoir).
//
// Reference behaviour:
//   w = mis * luminance(pHat) * other.computeUCW() * jacobian
//   totalWeight += w
//   if (rng * totalWeight < w):
//       this.integrand = pHat                             // = candidate radiance
//       this.subPixel  = other.subPixel
//       (plus other carrier fields)
//   this.confidence = min(confidenceCap, this.confidence + other.confidence)
//
// The port decouples UCW extraction from this helper so callers can feed the
// correct form for their reservoir flavour (initial-sampling UCW vs
// spatial/previous-frame totalWeight) -- see
// `lt_scatter_compute_ucw` above.  The accumulated
// `state.weightSum` is left in reference `totalWeight` form; the DI resolve
// pass (restir_di_resolve.glsl:86-99) applies the final `totalWeight / pHat`
// division at shading time.  No RTXDI_FinalizeResampling is performed.
// ---------------------------------------------------------------------------
bool lt_scatter_add_sample_from_reservoir(
    inout RTXDI_DIReservoir state,
    inout float            stateConfidence,
    float                  misWeight,
    vec3                   pHat,
    float                  jacobian,
    float                  otherUcw,
    float                  otherConfidence,
    RTXDI_DIReservoir      otherReservoir,
    inout RTXDI_RandomSamplerState rng)
{
    float pHatLum = lt_scatter_radiance_phat(pHat);
    float candidateWeight = max(misWeight, 0.0f) * pHatLum * max(otherUcw, 0.0f) * max(jacobian, 0.0f);
    if (isnan(candidateWeight) || isinf(candidateWeight) || candidateWeight < 0.0f) {
        candidateWeight = 0.0f;
    }
    PathReservoir_setTotalWeight(state, PathReservoir_getTotalWeight(state) + candidateWeight);

    bool selected = (candidateWeight > 0.0f)
        && RTXDI_IsValidDIReservoir(otherReservoir)
        && (lt_next_random(rng) * PathReservoir_getTotalWeight(state) < candidateWeight);
    if (selected) {
        state.lightData         = otherReservoir.lightData;
        state.uvData            = otherReservoir.uvData;
        state.targetPdf         = otherReservoir.targetPdf;
        state.packedVisibility  = otherReservoir.packedVisibility;
        state.age               = otherReservoir.age;
        state.spatialDistance   = otherReservoir.spatialDistance;
        PathReservoir_setIntegrand(state, pHat);
        state.pixelSampleUV     = otherReservoir.pixelSampleUV;
        state.lensSampleUV      = otherReservoir.lensSampleUV;
        state.pathSample        = otherReservoir.pathSample;
    }

    // Reference addSampleFromReservoir unconditionally bumps confidence.
    // The caller (resolve stage) later overwrites state.M with the motion-
    // vector bilinear newConfidence, matching ScatterTemporalResampling.rt.slang:170.
    stateConfidence = min(
        SCATTER_RECONNECTION_CONFIDENCE_MAX,
        stateConfidence + scatter_clamp_reconnection_confidence(otherConfidence)
    );

    return selected;
}

// ---------------------------------------------------------------------------
// Cell-space atomic scatter append (Reference: ReprojectTemporalSamples.rt.slang:161-174).
//
//   uint index = atomicAdd(globalCounters[kCounterIndexDataCount], 1);
//   uint cellIndex = atomicAdd(cellCounters[linearizedIndex], 1);
//   reservoirIndices[index] = uint2(linearizedIndex, cellIndex);
//   scatteredReservoirs[index] = pixel;
// ---------------------------------------------------------------------------
void lt_reproject_temporal_samples_append_record(ivec2 pixel, ivec2 newPixel) {
    if (!lt_is_viewport_uv_in_bounds(newPixel) || !lt_is_viewport_uv_in_bounds(pixel)) {
        return;
    }

    uint linearizedIndex = uint(newPixel.y * viewWidth + newPixel.x);
    uint cellIndex = lt_reproject_temporal_samples_cell_counter_atomic_add(linearizedIndex, 1u);
    uint index = lt_reproject_temporal_samples_global_counter_atomic_add(
        LT_TEMPORAL_SCATTER_COUNTER_INDEX_DATA_COUNT,
        1u
    );
    lt_reproject_temporal_samples_store_reservoir_index(index, uvec2(linearizedIndex, cellIndex));
    lt_reproject_temporal_samples_store_scattered_reservoir(index, uvec2(pixel));
}

// ===========================================================================
// Stage 2c (ScatterTemporalResampling.rt.slang) helpers.
//
// The reference's `run(pixel)` body is structurally simple:
//   1. Load the current reservoir/reconnection, compute currSampleMIS via a
//      current -> previous shift.
//   2. Seed the destination state with addSampleFromReservoir(currSampleMIS,
//      currReservoir).  Snapshot its confidence as newConfidence.
//   3. Walk sortedReservoirs[cellOffset + i], shift each prev -> current,
//      compute prevSampleMIS via m1/m2, and addSampleFromReservoir.
//   4. Overwrite dstReservoir.confidence with the motion-vector bilinear
//      accumulation against prevReservoirs[neighbor].
//
// The helpers below isolate each step so the entry point in reuse_bridge.glsl
// is a linear transliteration of ScatterTemporalResampling::run.
// ===========================================================================

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)

// ---------------------------------------------------------------------------
// Build the current-frame canonical sample for this pixel.
//
// Mirrors ScatterTemporalResampling.rt.slang:77-79 exactly:
//   currReservoir = currReservoirs[reservoirIdx]
//   currReconnection = currReconnectionData[reservoirIdx]
//
// The stage consumes the published Stage-1 sidecar snapshot directly through
// the shared current-stage reconnection samplers. No canonical rebuild is
// permitted here because the reference never resamples the current candidate
// in this pass, and doing so reintroduces pHat jitter / blur.
// Returns valid=false when the carried integrand is zero.
// ---------------------------------------------------------------------------
struct LtScatterCurrentSample {
    bool                                  isValid;
    bool                                  hasPositivePHat;
    RTXDI_DIReservoir                     reservoir;
    ReservoirSplattingReconnectionData    reconnectionData;
    float                                 confidence;
};

float ScatterTemporalResampling_load_previous_reservoir_confidence(
    ivec2 neighborPixel);

RTXDI_DIReservoir lt_ScatterTemporalResampling_load_current_reservoir(
    ivec2 pixel);

LtScatterCurrentSample lt_ScatterTemporalResampling_load_current_sample(
    uint reservoirIdx,
    ivec2 pixel,
    RAB_Surface surface,
    RTXDI_DIReservoir currReservoir);

float ScatterTemporalResampling_compute_curr_sample_mis(
    LtScatterCurrentSample currSample,
    ivec2 pixel,
    RAB_Surface surface);

bool ScatterTemporalResampling_process_contributor(
    inout RTXDI_DIReservoir dstReservoir,
    inout ScatterReconnectionData dstReconnectionData,
    inout float newConfidence,
    ivec2 scatteredPixel,
    ivec2 pixel,
    RTXDI_DIReservoir currReservoir,
    ScatterReconnectionData currReconnectionData,
    float currReservoirConfidence,
    inout RTXDI_RandomSamplerState sg);

float ScatterTemporalResampling_motion_vector_confidence(
    ivec2 pixel,
    float newConfidence);

RTXDI_DIReservoir lt_ScatterTemporalResampling_load_current_reservoir(
    ivec2 pixel)
{
    return RTXDI_LoadDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel),
        lt_build_restir_di_parameters().bufferIndices.initialSamplingOutputBufferIndex
    );
}

LtScatterCurrentSample lt_scatter_make_empty_current_sample() {
    LtScatterCurrentSample currentSample;
    currentSample.isValid = false;
    currentSample.hasPositivePHat = false;
    currentSample.reservoir = RTXDI_EmptyDIReservoir();
    currentSample.reconnectionData = ReservoirSplattingReconnectionData_init();
    currentSample.confidence = 0.0f;
    return currentSample;
}

float ScatterTemporalResampling_motion_vector_confidence(
    ivec2 pixel,
    float newConfidence)
{
    vec2 prevPixel = lt_temporal_previous_pixel_center(pixel) - vec2(0.5f);
    ivec2 topLeft = ivec2(floor(prevPixel));
    vec2 fractionalCoord = clamp(prevPixel - vec2(topLeft), vec2(0.0f), vec2(1.0f));

    for (int y = 0; y < 2; ++y) {
        for (int x = 0; x < 2; ++x) {
            ivec2 neighborPixel = topLeft + ivec2(x, y);
            if (!lt_is_viewport_uv_in_bounds(neighborPixel)) {
                continue;
            }

            float bilinearWeight =
                ((x == 0) ? (1.0f - fractionalCoord.x) : fractionalCoord.x) *
                ((y == 0) ? (1.0f - fractionalCoord.y) : fractionalCoord.y);
            newConfidence += bilinearWeight * ScatterTemporalResampling_load_previous_reservoir_confidence(neighborPixel);
        }
    }

    return min(newConfidence, SCATTER_RECONNECTION_CONFIDENCE_MAX);
}

LtScatterCurrentSample lt_ScatterTemporalResampling_load_current_sample(
    uint reservoirIdx,
    ivec2 pixel,
    RAB_Surface surface,
    RTXDI_DIReservoir currReservoir)
{
    LtScatterCurrentSample currentSample = lt_scatter_make_empty_current_sample();
    currentSample.reservoir = currReservoir;
    if (!RTXDI_IsValidDIReservoir(currReservoir) || !RAB_IsSurfaceValid(surface)) {
        return currentSample;
    }

    // Reference parity: load the Stage-1 current-frame reconnection snapshot
    // that was published by the Java pipeline before Stage 2c. This mirrors the
    // structured-buffer read of currReconnectionData[reservoirIdx] exactly.
    ivec2 reservoirPosition = ivec2(
        int(reservoirIdx % uint(viewWidth)),
        int(reservoirIdx / uint(viewWidth))
    );
    vec4 reconnection0 = texelFetch(current_stage_reconnection0, reservoirPosition, 0);
    vec4 reconnection1 = texelFetch(current_stage_reconnection1, reservoirPosition, 0);
    vec4 reservoirMeta = texelFetch(radiosity_proposal_reservoir_meta, reservoirPosition, 0);
    vec4 sampleData    = texelFetch(radiosity_proposal_reservoir_samples, reservoirPosition, 0);
    ReservoirSplattingReconnectionData storedReconnection;
    scatter_unpack_reconnection(
        reconnection0,
        reconnection1,
        sampleData,
        reservoirMeta.y,
        reservoirMeta.z,
        storedReconnection
    );
    RestirDI_restoreReconnectionRadiometry(reservoirPosition, false, currentSample.reservoir, storedReconnection);
    currentSample.confidence = lt_scatter_reservoir_confidence(currentSample.reservoir, storedReconnection);
    currentSample.isValid = true;
    currentSample.reconnectionData = storedReconnection;
    currentSample.hasPositivePHat = ph_luminance(PathReservoir_getIntegrand(currentSample.reservoir)) > 0.0f;
    return currentSample;
}

// ---------------------------------------------------------------------------
// Canonical current-sample MIS (Reference: ScatterTemporalResampling.rt.slang:80-104).
//
// Shifts the current reservoir/reconnection into the previous-frame domain,
// reads prevReservoirs[linearizePixel(floor(shiftedCurr.fractionalPixel))] for
// its confidence, and computes `currSampleMIS = m1 / (m1 + m2)`.
//
// Returns 1.0 when:
//   * the candidate is not valid (reference's `else`-branch)
//   * the current->previous reprojection falls off-screen
//     (reference's `validateIntegerPixelBounds(scatteredPixel) == false`
//      drops m2 to 0 -> MIS = m1/(m1+0) = 1 regardless of m1)
//   * the shift itself fails (shiftedCurr.valid=false -> radiance=0 -> m2=0)
// Returns 0.0 when m1 is 0 (integrand is zero or confidence is zero).
// ---------------------------------------------------------------------------
// Current-sample MIS in the shape used by ScatterTemporalResampling::run(pixel).
float ScatterTemporalResampling_compute_curr_sample_mis(
    LtScatterCurrentSample currSample,
    ivec2 pixel,
    RAB_Surface surface)
{
    if (!currSample.isValid || !currSample.hasPositivePHat) {
        return 1.0f;
    }

    LtScatterShiftedPath shiftedCurr;
    RTXDI_DIReservoir shiftedReservoir;
    ScatterReconnectionData shiftedReconnection;
    float shiftedJacobian;
    if (!lt_scatter_update_shifted_reservoir_to_previous_frame(
            currSample.reconnectionData,
            currSample.reservoir,
            false,
            shiftedCurr,
            shiftedReservoir,
            shiftedReconnection,
            shiftedJacobian)) {
        return 1.0f;
    }

    ivec2 scatteredPixel = ivec2(floor(shiftedCurr.fractionalPixel));
    if (!lt_is_viewport_uv_in_bounds(scatteredPixel)) {
        return 1.0f;
    }

    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(scatteredPixel)
    );
    float prevReservoirConfidence = ScatterTemporalResampling_load_previous_reservoir_confidence(scatteredPixel);

    return lt_scatter_canonical_mis(
        lt_scatter_radiance_phat(PathReservoir_getIntegrand(currSample.reservoir)),
        currSample.confidence,
        lt_scatter_radiance_phat(shiftedCurr.radiance),
        shiftedJacobian,
        RTXDI_IsValidDIReservoir(prevReservoir) ? prevReservoirConfidence : 0.0f,
        true
    );
}

bool ScatterTemporalResampling_process_contributor(
    inout RTXDI_DIReservoir dstReservoir,
    inout ScatterReconnectionData dstReconnectionData,
    inout float newConfidence,
    ivec2 scatteredPixel,
    ivec2 pixel,
    RTXDI_DIReservoir currReservoir,
    ScatterReconnectionData currReconnectionData,
    float currReservoirConfidence,
    inout RTXDI_RandomSamplerState sg)
{
    RAB_Surface scatteredSurface = lt_load_surface(scatteredPixel);
    if (!RAB_IsSurfaceValid(scatteredSurface)) {
        return false;
    }

    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(scatteredPixel)
    );
    if (!RTXDI_IsValidDIReservoir(prevReservoir)) {
        return false;
    }

    ScatterReconnectionData prevReconnectionData = RestirDI_loadPreviousFrameReconnection(scatteredPixel);
    float prevReservoirConfidence = ScatterTemporalResampling_load_previous_reservoir_confidence(scatteredPixel);
    RAB_Surface targetSurface = RAB_GetGBufferSurface(pixel, false);
    if (!RAB_IsSurfaceValid(targetSurface)) {
        return false;
    }

    LtScatterShiftedPath shiftedPrev;
    RTXDI_DIReservoir shiftedReservoir;
    ScatterReconnectionData shiftedPrevReconnectionData;
    float shiftedJacobian;
    if (!lt_scatter_update_shifted_reservoir(
            prevReconnectionData,
            prevReservoir,
            true,
            false,
            targetSurface,
            pixel,
            shiftedPrev,
            shiftedReservoir,
            shiftedPrevReconnectionData,
            shiftedJacobian)) {
        return false;
    }

    float prevSampleMIS = 0.0f;
    if (ph_luminance(PathReservoir_getIntegrand(prevReservoir)) > 0.0f) {
        float m1 = lt_scatter_radiance_phat(shiftedPrev.radiance)
            * shiftedJacobian
            * currReservoirConfidence;
        float m2 = lt_scatter_radiance_phat(PathReservoir_getIntegrand(prevReservoir))
            * prevReservoirConfidence;
        float denominator = m1 + m2;
        prevSampleMIS = (denominator > 0.0f) ? (m2 / denominator) : 0.0f;
    }

    float contributorConfidence = newConfidence;
    bool prevSelected = lt_scatter_add_sample_from_reservoir(
        dstReservoir,
        contributorConfidence,
        prevSampleMIS,
        shiftedPrev.radiance,
        shiftedJacobian,
        lt_scatter_compute_ucw(prevReservoir, PathReservoir_getIntegrand(prevReservoir)),
        prevReservoirConfidence,
        shiftedReservoir,
        sg
    );
    if (prevSelected) {
        dstReconnectionData = shiftedPrevReconnectionData;
    }
    return prevSelected;
}
//   if (length(motionVector) < 1e-6) motionVector = 0
//   prevPixel = float2(pixel) + motionVector * float2(frameDim)
//   topLeft = int2(floor(prevPixel))
//   frac = saturate(prevPixel - float2(topLeft))
//   for (x,y in {0,1}):
//       bw = lerp(1-x, x, frac.x) * lerp(1-y, y, frac.y)
//       newConfidence += bw * prevReservoirs[neighbor].confidence
//   dstReservoir.confidence = min(confidenceCap, newConfidence)
//
// `lt_temporal_previous_pixel_center` already applies the motion-vector
// delta (returns `pixel + 0.5 + motionVector`).  Subtracting 0.5 recovers
// the reference's `prevPixel = pixel + motionVector * frameDim`.
// Returns the new confidence clamped to SCATTER_RECONNECTION_CONFIDENCE_MAX.
// ---------------------------------------------------------------------------
// Loads previous-frame confidence directly from the previous reservoir buffer,
// matching prevReservoirs[neighborIndex].confidence in the reference stage.
float ScatterTemporalResampling_load_previous_reservoir_confidence(
    ivec2 neighborPixel)
{
    if (!lt_is_viewport_uv_in_bounds(neighborPixel)) {
        return 0.0f;
    }

    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(neighborPixel)
    );

    ReservoirSplattingReconnectionData prevReconnectionData = RestirDI_loadPreviousFrameReconnection(neighborPixel);
    return lt_scatter_reservoir_confidence(prevReservoir, prevReconnectionData);
}


#endif // PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS

#endif // PHOTONICS_RESTIR_DI_SCATTER_IMPL_GLSL
