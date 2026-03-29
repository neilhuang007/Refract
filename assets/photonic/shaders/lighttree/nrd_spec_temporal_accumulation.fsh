#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 spec_noisy_out;
layout(location = 1) out vec4 spec_responsive_out;
layout(location = 2) out vec4 spec_slow_out;
layout(location = 3) out vec4 spec_fast_out;
layout(location = 4) out vec4 spec_history_length_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform float ph_debug_disable_temporal_reset;
uniform float ph_nrd_max_accumulated_frame_num;
uniform float ph_nrd_max_fast_accumulated_frame_num;
uniform float ph_nrd_depth_threshold;
// NRD checkerboard reconstruction: when checkerboard rendering is active, inactive pixels
// receive zero radiance from shade_samples. Reconstruct from geometry-aware neighbors
// before temporal accumulation, matching NRD RELAX's built-in checkerboard support.

// --- NRD RELAX constants ---
const float RELAX_NORMAL_ULP_VAL          = 1.5 / 255.0;
const float NRD_MAX_ALLOWED_VMB_ACCEL     = 3.0;  // NRD_MAX_ALLOWED_VIRTUAL_MOTION_ACCELERATION
const float NRD_ROUGHNESS_FRACTION        = 0.15; // gRoughnessFraction: controls relaxed roughness weight
const float NRD_SPEC_VARIANCE_BOOST       = 1.0;  // gSpecVarianceBoost

// NRD Common.hlsli:331 - ComputeParallaxInPixels
// Returns parallax magnitude in pixels using world-position shift through previous MVP.
float spec_compute_parallax_in_pixels(vec3 currentPosition, vec3 cameraDelta) {
    vec3 shiftedPos = currentPosition + cameraDelta;
    vec2 shiftedPx = ph_reprojectf(
        previous_modelview_projection,
        shiftedPos,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    );
    vec2 currentPx = vec2(tex_coord) + 0.5;
    return length(shiftedPx - currentPx);
}

// Project a world position through previous_modelview_projection and return pixel coords.
// ph_reprojectf returns pixel coords in [0, viewWidth*PH_RENDER_SCALE] x [0, viewHeight*PH_RENDER_SCALE].
vec2 spec_project_to_prev_pixels(vec3 worldPos) {
    return ph_reprojectf(
        previous_modelview_projection,
        worldPos,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    );
}

// Convert pixel coords (as used by ph_reprojectf output) to normalized UV [0,1].
vec2 spec_pixels_to_uv(vec2 px) {
    return px / (vec2(viewWidth, viewHeight) * PH_RENDER_SCALE);
}

// NRD RELAX per-tap disocclusion check using world-space plane distance.
// Used for both SMB and VMB footprint validation.
// Returns 1.0 if the tap is valid, 0.0 otherwise.
float spec_check_tap(ivec2 tapCoord, ivec2 bufTexSize,
    vec3 currentPosition, vec3 currentNormal, vec4 currentMaterial,
    float disocclusionThreshold)
{
    if (any(lessThan(tapCoord, ivec2(0))) || any(greaterThanEqual(tapCoord, bufTexSize))) {
        return 0.0;
    }

    // Checkerboard validity: previous frame taps on inactive pixels hold stale/zero data.
    if (!nrd_is_active_checkerboard_pixel(tapCoord, true, ph_restir_active_checkerboard_field)) {
        return 0.0;
    }

    vec4 prevMaterial = texelFetch(prev_radiosity_material, tapCoord, 0);
    if (nrd_material_weight(currentMaterial, prevMaterial) <= 0.0) {
        return 0.0;
    }

    vec3 prevPosition = texelFetch(prev_radiosity_position, tapCoord, 0).xyz;
    return nrd_is_reprojection_tap_valid(currentPosition, prevPosition, currentNormal, disocclusionThreshold);
}

vec4 spec_load_stage_spec_signal(ivec2 pixelCoord) {
    vec4 encodedSignal = texelFetch(stage_radiosity_direct_specular, pixelCoord, 0);
    if (ph_restir_active_checkerboard_field != 0
        && !nrd_is_active_checkerboard_pixel(pixelCoord, false, ph_restir_active_checkerboard_field)) {
        encodedSignal = nrd_reconstruct_checkerboard_signal(
            stage_radiosity_direct_specular,
            pixelCoord,
            stage_radiosity_position,
            stage_radiosity_normal
        );
    }
    return encodedSignal;
}

vec3 spec_stabilize_current_radiance(ivec2 pixelCoord, vec4 centerMaterial, vec3 centerRadiance) {
    if (any(isnan(centerRadiance)) || any(isinf(centerRadiance))) {
        return vec3(0.0);
    }

    centerRadiance = max(centerRadiance, vec3(0.0));
    float centerLuma = nrd_luminance(centerRadiance);
    ivec2 texSize = textureSize(stage_radiosity_direct_specular, 0);

    int compatibleSamples = 0;
    float maxNeighborLuma = -1.0;
    float minNeighborLuma = 1e30;
    vec3 maxNeighborRadiance = centerRadiance;
    vec3 minNeighborRadiance = centerRadiance;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) {
                continue;
            }

            ivec2 sampleCoord = pixelCoord + ivec2(dx, dy);
            if (any(lessThan(sampleCoord, ivec2(0))) || any(greaterThanEqual(sampleCoord, texSize))) {
                continue;
            }

            vec4 sampleMaterial = texelFetch(stage_radiosity_material, sampleCoord, 0);
            if (nrd_material_weight(centerMaterial, sampleMaterial) <= 0.0) {
                continue;
            }

            vec3 sampleRadiance = nrd_unpack_direct_signal(spec_load_stage_spec_signal(sampleCoord)).radiance;
            if (any(isnan(sampleRadiance)) || any(isinf(sampleRadiance))) {
                continue;
            }

            sampleRadiance = max(sampleRadiance, vec3(0.0));
            float sampleLuma = nrd_luminance(sampleRadiance);
            compatibleSamples++;

            if (sampleLuma > maxNeighborLuma) {
                maxNeighborLuma = sampleLuma;
                maxNeighborRadiance = sampleRadiance;
            }
            if (sampleLuma < minNeighborLuma) {
                minNeighborLuma = sampleLuma;
                minNeighborRadiance = sampleRadiance;
            }
        }
    }

    vec3 stabilizedRadiance = centerRadiance;
    if (compatibleSamples > 0) {
        if (centerLuma > maxNeighborLuma) {
            stabilizedRadiance = maxNeighborRadiance;
        } else if (centerLuma < minNeighborLuma) {
            stabilizedRadiance = minNeighborRadiance;
        }
    }

    return max(stabilizedRadiance, vec3(0.0));
}

void spec_reset_outputs() {
    spec_noisy_out          = vec4(0.0);
    spec_responsive_out     = vec4(0.0);
    spec_slow_out           = vec4(0.0);
    spec_fast_out           = vec4(0.0);
    spec_history_length_out = vec4(0.0);
}

void main() {
    if (!is_in_world()) {
        spec_reset_outputs();
        return;
    }

    // -------------------------------------------------------------------------
    // Setup: fetch current frame data
    // -------------------------------------------------------------------------
    // Checkerboard reconstruction: inactive pixels have zero radiance from shade_samples.
    // Reconstruct from geometry-aware neighbors before temporal accumulation.
    vec4 rawSpec = spec_load_stage_spec_signal(tex_coord);
    NrdDirectSignal currentSpec     = nrd_unpack_direct_signal(rawSpec);
    vec4  currentMaterial           = texelFetch(stage_radiosity_material,      tex_coord, 0);
    vec3  currentPosition           = texelFetch(stage_radiosity_position,       tex_coord, 0).xyz;
    vec3  currentGeometryNormal     = texelFetch(stage_radiosity_normal,         tex_coord, 0).xyz;
    vec3  currentNormal = nrd_select_surface_normal(
        currentGeometryNormal,
        texelFetch(stage_radiosity_mapped_normal, tex_coord, 0).xyz
    );
    float currentRoughness = currentMaterial.r; // roughness packed in .r

    currentSpec.radiance = spec_stabilize_current_radiance(tex_coord, currentMaterial, currentSpec.radiance);

    NrdDirectHistorySample currentHistory = nrd_direct_history_from_radiance(currentSpec.radiance);

    if (any(isnan(currentSpec.radiance)) || isnan(currentHistory.secondMoment)) {
        spec_reset_outputs();
        return;
    }

    // -------------------------------------------------------------------------
    // NRD RELAX: averaged normal over 3x3 neighborhood (RELAX_TemporalAccumulation.cs.hlsl:439-457)
    // Divided by 9.0 (not normalized), used for modified roughness and reprojection validation.
    // -------------------------------------------------------------------------
    vec3 currentNormalAveraged = currentNormal;
    for (int ny = -1; ny <= 1; ny++) {
        for (int nx = -1; nx <= 1; nx++) {
            if (nx == 0 && ny == 0) continue;
            ivec2 nCoord = tex_coord + ivec2(nx, ny);
            ivec2 texSizeN = textureSize(stage_radiosity_normal, 0);
            if (any(lessThan(nCoord, ivec2(0))) || any(greaterThanEqual(nCoord, texSizeN))) continue;
            vec3 sn = nrd_select_surface_normal(
                texelFetch(stage_radiosity_normal,        nCoord, 0).xyz,
                texelFetch(stage_radiosity_mapped_normal, nCoord, 0).xyz
            );
            currentNormalAveraged += sn;
        }
    }
    currentNormalAveraged /= 9.0; // intentionally NOT normalized; used for nrd_modified_roughness_from_normal_variance

    float currentRoughnessModified = nrd_modified_roughness_from_normal_variance(currentRoughness, currentNormalAveraged);

    // -------------------------------------------------------------------------
    // View direction and NoV
    // -------------------------------------------------------------------------
    vec3  viewDir     = currentPosition - world_camera_position;
    float viewDistance = max(length(viewDir), 1e-3);
    viewDir /= viewDistance;
    vec3  V    = -viewDir;
    float NoV  = abs(dot(currentNormal, V));

    // -------------------------------------------------------------------------
    // Parallax (camera translation)
    // -------------------------------------------------------------------------
    vec3  cameraDelta           = world_camera_position - previous_world_camera_position;
    float smbParallaxInPixels1  = spec_compute_parallax_in_pixels(currentPosition,  cameraDelta);
    float smbParallaxInPixels2  = spec_compute_parallax_in_pixels(currentPosition, -cameraDelta);
    float smbParallaxInPixelsMax = max(smbParallaxInPixels1, smbParallaxInPixels2);
    float smbParallaxInPixelsMin = min(smbParallaxInPixels1, smbParallaxInPixels2);

    // -------------------------------------------------------------------------
    // Surface motion based (SMB) reprojection UV (in pixel coords)
    // -------------------------------------------------------------------------
    // Motion vector convention: .xy = previousPixel - currentPixelCenter (see light_tree_sampling_stage.fsh).
    // To recover previousPixel: currentPixelCenter + motion.xy. Must ADD, not subtract.
    vec4 motionVector = texelFetch(radiosity_motion, tex_coord, 0);
    vec2 reprojectionPx = motionVector.a > 0.5
        ? (vec2(tex_coord) + vec2(0.5) + motionVector.xy)
        : spec_project_to_prev_pixels(currentPosition + currentNormal * 0.01);

    // -------------------------------------------------------------------------
    // NRD RELAX disocclusion threshold (scaled by NoV and parallax)
    // -------------------------------------------------------------------------
    float NoVfactor            = mix(mix(0.05, 1.0, NoV), 1.0, clamp(smbParallaxInPixelsMax / 30.0, 0.0, 1.0));
    float disocclusionScale    = 1.0 / max(NoVfactor, 0.05);
    float disocclusionThreshold = ph_nrd_depth_threshold * viewDistance * disocclusionScale;

    // -------------------------------------------------------------------------
    // Pixel size (world-space size of one pixel at current depth) — approximation
    // -------------------------------------------------------------------------
    float pixelSize = viewDistance / max(0.5 * viewHeight, 1.0);

    // -------------------------------------------------------------------------
    // SMB bilinear footprint
    // -------------------------------------------------------------------------
    vec2  smbPixelPosFloat = reprojectionPx;
    vec2  prevUVSMB = spec_pixels_to_uv(reprojectionPx);
    ivec2 smbBilinearOrigin = ivec2(floor(smbPixelPosFloat - 0.5));
    vec2  smbBilinearWeights = fract(smbPixelPosFloat - 0.5);
    ivec2 texSize = textureSize(prev_radiosity_position, 0);

    float smbFx = smbBilinearWeights.x;
    float smbFy = smbBilinearWeights.y;
    vec4  smbStandardWeights = vec4(
        (1.0 - smbFx) * (1.0 - smbFy),
        smbFx         * (1.0 - smbFy),
        (1.0 - smbFx) * smbFy,
        smbFx         * smbFy
    );

    ivec2 smbTap00 = smbBilinearOrigin;
    ivec2 smbTap10 = smbBilinearOrigin + ivec2(1, 0);
    ivec2 smbTap01 = smbBilinearOrigin + ivec2(0, 1);
    ivec2 smbTap11 = smbBilinearOrigin + ivec2(1, 1);

    vec4 smbTapValid;
    smbTapValid.x = spec_check_tap(smbTap00, texSize, currentPosition, currentNormal, currentMaterial, disocclusionThreshold);
    smbTapValid.y = spec_check_tap(smbTap10, texSize, currentPosition, currentNormal, currentMaterial, disocclusionThreshold);
    smbTapValid.z = spec_check_tap(smbTap01, texSize, currentPosition, currentNormal, currentMaterial, disocclusionThreshold);
    smbTapValid.w = spec_check_tap(smbTap11, texSize, currentPosition, currentNormal, currentMaterial, disocclusionThreshold);

    // NRD RELAX backface rejection (SMB): reject if previous normal faces away from current normal
    // smbPixelPosFloat is already in [0, texSize) pixel space; divide by texSize to get UV.
    vec2 smbNormalUv = smbPixelPosFloat / vec2(textureSize(prev_radiosity_normal, 0));
    vec3 prevNormalSmb = nrd_select_surface_normal(
        texture(prev_radiosity_normal,        smbNormalUv).xyz,
        texture(prev_radiosity_mapped_normal, smbNormalUv).xyz
    );
    vec3 reprojNormal = normalize(currentNormalAveraged);
    if (dot(reprojNormal, prevNormalSmb) < 0.0) {
        smbTapValid = vec4(0.0);
    }

    vec4  smbCustomWeights = smbStandardWeights * smbTapValid;
    float smbSumCustom     = dot(smbCustomWeights, vec4(1.0));
    bool  smbCanReproject  = smbSumCustom > 1e-4;
    float smbFootprintQuality = smbCanReproject ? smbSumCustom : 0.0;
    if (smbCanReproject) smbCustomWeights /= smbSumCustom;

    float smbReprojectionFound = smbCanReproject ? 1.0 : 0.0;

    // NRD RELAX: footprint stretching avoidance
    vec3  prevWorldPosSMB = texture(prev_radiosity_position, smbNormalUv).xyz;
    vec3  Vprev           = normalize(prevWorldPosSMB - previous_world_camera_position);
    float NoVprev         = abs(dot(currentNormal, Vprev));
    float sizeQuality     = (NoVprev + 1e-3) / (NoV + 1e-3);
    sizeQuality *= sizeQuality;
    sizeQuality *= sizeQuality;
    smbFootprintQuality *= mix(0.1, 1.0, clamp(sizeQuality, 0.0, 1.0));

    // -------------------------------------------------------------------------
    // SMB history sampling — slow + fast + history length + accumulated hit distance
    // -------------------------------------------------------------------------
    vec4  smbPrevSlow       = vec4(0.0);
    vec4  smbPrevFast       = vec4(0.0);
    vec4  smbPrevHistoryVec = vec4(0.0);
    float smbPrevHitT       = 0.0;

    if (smbCanReproject) {
        if (smbCustomWeights.x > 0.0) {
            smbPrevSlow       += texelFetch(prev_spec_slow_input,           smbTap00, 0) * smbCustomWeights.x;
            smbPrevFast       += texelFetch(prev_spec_fast_input,           smbTap00, 0) * smbCustomWeights.x;
            smbPrevHistoryVec += texelFetch(prev_spec_history_length_input,  smbTap00, 0) * smbCustomWeights.x;
        }
        if (smbCustomWeights.y > 0.0) {
            smbPrevSlow       += texelFetch(prev_spec_slow_input,           smbTap10, 0) * smbCustomWeights.y;
            smbPrevFast       += texelFetch(prev_spec_fast_input,           smbTap10, 0) * smbCustomWeights.y;
            smbPrevHistoryVec += texelFetch(prev_spec_history_length_input,  smbTap10, 0) * smbCustomWeights.y;
        }
        if (smbCustomWeights.z > 0.0) {
            smbPrevSlow       += texelFetch(prev_spec_slow_input,           smbTap01, 0) * smbCustomWeights.z;
            smbPrevFast       += texelFetch(prev_spec_fast_input,           smbTap01, 0) * smbCustomWeights.z;
            smbPrevHistoryVec += texelFetch(prev_spec_history_length_input,  smbTap01, 0) * smbCustomWeights.z;
        }
        if (smbCustomWeights.w > 0.0) {
            smbPrevSlow       += texelFetch(prev_spec_slow_input,           smbTap11, 0) * smbCustomWeights.w;
            smbPrevFast       += texelFetch(prev_spec_fast_input,           smbTap11, 0) * smbCustomWeights.w;
            smbPrevHistoryVec += texelFetch(prev_spec_history_length_input,  smbTap11, 0) * smbCustomWeights.w;
        }

        // NRD keeps the accumulated reflection hit distance in a separate history
        // buffer. This integration stores it in spec history confidence .g.
        smbPrevHitT =
            texelFetch(spec_history_confidence_input, smbTap00, 0).g * smbCustomWeights.x +
            texelFetch(spec_history_confidence_input, smbTap10, 0).g * smbCustomWeights.y +
            texelFetch(spec_history_confidence_input, smbTap01, 0).g * smbCustomWeights.z +
            texelFetch(spec_history_confidence_input, smbTap11, 0).g * smbCustomWeights.w;
        smbPrevHitT = max(0.001, smbPrevHitT);
    }

    // -------------------------------------------------------------------------
    // History length (SMB-based, as in NRD reference)
    // -------------------------------------------------------------------------
    float decodedPrevHistory = nrd_decoded_history(smbPrevHistoryVec);
    float historyLength      = decodedPrevHistory + 1.0;
    historyLength = min(RELAX_MAX_ACCUM_FRAME_NUM, historyLength);

    // Footprint quality shortens history (NRD ref line 568-572)
    if (smbFootprintQuality < 1.0) {
        historyLength *= sqrt(smbFootprintQuality);
        historyLength  = max(historyLength, 1.0);
    }

    // -------------------------------------------------------------------------
    // Temporal reset
    // -------------------------------------------------------------------------
    bool temporalReset = light_reload && (ph_debug_disable_temporal_reset < 0.5);
    if (temporalReset) historyLength = 1.0;

    // -------------------------------------------------------------------------
    // Confidence-scaled max accumulated frame nums
    // -------------------------------------------------------------------------
    float specConfidence        = clamp(texture(spec_confidence_input, prevUVSMB).g, 0.0, 1.0);
    float specMaxAccumFrameNum  = ph_nrd_max_accumulated_frame_num  * specConfidence;
    float specMaxFastAccumFrame = ph_nrd_max_fast_accumulated_frame_num * specConfidence;

    float specHistoryFrames          = min(specMaxAccumFrameNum,  historyLength);
    float specHistoryResponsiveFrames = min(specMaxFastAccumFrame, historyLength);

    // -------------------------------------------------------------------------
    // Specular hit distance (minimum over 3x3 neighborhood, NRD ref line 650)
    // -------------------------------------------------------------------------
    float hitDist = currentSpec.hitDistance;
    {
        float minHitDist = (hitDist == 0.0) ? 1e30 : hitDist;
        ivec2 localTexSize = textureSize(stage_radiosity_direct_specular, 0);
        for (int ny = -1; ny <= 1; ny++) {
            for (int nx = -1; nx <= 1; nx++) {
                if (nx == 0 && ny == 0) continue;
                ivec2 nc = tex_coord + ivec2(nx, ny);
                if (any(lessThan(nc, ivec2(0))) || any(greaterThanEqual(nc, localTexSize))) continue;
                float ht = texelFetch(stage_radiosity_direct_specular, nc, 0).a;
                if (ht > 0.0) minHitDist = min(minHitDist, ht);
            }
        }
        hitDist = (minHitDist >= 1e30) ? 0.0 : minHitDist;
    }

    // -------------------------------------------------------------------------
    // Curvature estimation along the direction of motion (NRD ref lines 652-736)
    // We approximate curvature using neighbor normals/positions at +x and +y.
    // NRD uses shared memory; we use texelFetch on the current-frame buffers.
    // -------------------------------------------------------------------------
    float curvature = 0.0;
    {
        // deltaUv: direction of motion in pixel space (NRD ref lines 657-660)
        // uvForZeroParallax = prevUVSMB (in pixel coords)
        vec2 prevPosPx = spec_project_to_prev_pixels(prevWorldPosSMB + cameraDelta);
        vec2 deltaUvPx = smbPixelPosFloat - prevPosPx;
        float parallaxLen1 = max(smbParallaxInPixels1, 1.0 / 256.0);
        vec2  deltaUvNorm  = deltaUvPx / parallaxLen1; // normalized direction

        // Build a stable camera-space right/up basis for single-pixel ray offsets.
        // rightWS and upWS are world-space tangent vectors perpendicular to V,
        // scaled so that one unit corresponds to one pixel at the current view distance.
        float invViewH = 1.0 / max(viewHeight * PH_RENDER_SCALE, 1.0);
        vec3  rightWS;
        if (abs(dot(V, vec3(0.0, 1.0, 0.0))) > 0.99) {
            rightWS = normalize(cross(V, vec3(1.0, 0.0, 0.0)));
        } else {
            rightWS = normalize(cross(V, vec3(0.0, 1.0, 0.0)));
        }
        vec3 upWS = normalize(cross(rightWS, V));

        // Plane constant for line-plane intersection: dot(P, currentNormal) = planeD
        float planeD = dot(currentNormal, currentPosition - world_camera_position);

        // 10 edge: neighbor at tex_coord + ivec2(1, 0)
        vec3 n10, x10;
        {
            ivec2 nc10      = tex_coord + ivec2(1, 0);
            ivec2 localSize = textureSize(stage_radiosity_normal, 0);
            if (any(lessThan(nc10, ivec2(0))) || any(greaterThanEqual(nc10, localSize))) {
                n10 = currentNormal;
            } else {
                n10 = nrd_select_surface_normal(
                    texelFetch(stage_radiosity_normal,        nc10, 0).xyz,
                    texelFetch(stage_radiosity_mapped_normal, nc10, 0).xyz
                );
            }
            // Ray from camera through neighbor pixel (offset +1 pixel right in screen space)
            vec3  ray10Dir = normalize(V + rightWS * invViewH * viewDistance);
            float t10Denom = dot(currentNormal, ray10Dir);
            float t10 = abs(t10Denom) > 1e-6 ? planeD / t10Denom : viewDistance;
            x10 = world_camera_position + ray10Dir * t10;
        }

        // 01 edge: neighbor at tex_coord + ivec2(0, 1)
        vec3 n01, x01;
        {
            ivec2 nc01      = tex_coord + ivec2(0, 1);
            ivec2 localSize = textureSize(stage_radiosity_normal, 0);
            if (any(lessThan(nc01, ivec2(0))) || any(greaterThanEqual(nc01, localSize))) {
                n01 = currentNormal;
            } else {
                n01 = nrd_select_surface_normal(
                    texelFetch(stage_radiosity_normal,        nc01, 0).xyz,
                    texelFetch(stage_radiosity_mapped_normal, nc01, 0).xyz
                );
            }
            // Ray from camera through neighbor pixel (offset +1 pixel up in screen space)
            vec3  ray01Dir = normalize(V + upWS * invViewH * viewDistance);
            float t01Denom = dot(currentNormal, ray01Dir);
            float t01 = abs(t01Denom) > 1e-6 ? planeD / t01Denom : viewDistance;
            x01 = world_camera_position + ray01Dir * t01;
        }

        // Motion-direction weights (NRD ref line 685-686)
        vec2 wAbs = abs(deltaUvNorm) + (1.0 / 256.0);
        vec2 w    = wAbs / (wAbs.x + wAbs.y);

        vec3 xMix = x10 * w.x + x01 * w.y;
        vec3 nMix = normalize(n10 * w.x + n01 * w.y);

        // High-parallax flattening (NRD ref lines 691-720)
        float edgeFix           = 1.0 - nrd_pow5(NoV); // 1 - Pow5(NoV)
        float deltaUvLenFixed   = smbParallaxInPixelsMin; // "min" for camera-attached objects
        deltaUvLenFixed        *= 1.0 + edgeFix;

        if (deltaUvLenFixed > 1.0) {
            vec2  motionPxHigh = vec2(tex_coord) + 0.5 + deltaUvLenFixed * deltaUvNorm;
            ivec2 motionCoord  = ivec2(floor(motionPxHigh));
            ivec2 localSize    = textureSize(stage_radiosity_normal, 0);
            if (all(greaterThanEqual(motionCoord, ivec2(0))) && all(lessThan(motionCoord, localSize))) {
                vec3  xHigh = texelFetch(stage_radiosity_position, motionCoord, 0).xyz;
                vec3  nHigh = nrd_select_surface_normal(
                    texelFetch(stage_radiosity_normal,        motionCoord, 0).xyz,
                    texelFetch(stage_radiosity_mapped_normal, motionCoord, 0).xyz
                );
                float frustumSize = min(viewWidth, viewHeight) * pixelSize;
                float planeDistHigh = abs(dot(xHigh - currentPosition, currentNormal));
                float geomThreshold = 0.005 * frustumSize; // NRD_CURVATURE_HIGH_PARALLAX_DISOCCLUSION_THRESHOLD ~= 0.005
                if (planeDistHigh < geomThreshold) {
                    nMix = nHigh;
                    xMix = xHigh;
                }
            }
        }

        // Estimate curvature for the edge {xMix, currentPosition} (NRD ref line 724-726)
        vec3  edge      = xMix - currentPosition;
        float edgeLenSq = dot(edge, edge);
        if (edgeLenSq > 1e-10) {
            curvature = dot(nMix - currentNormal, edge) / edgeLenSq;
        }

        // Correction for very negative curvature (NRD ref lines 729-735)
        if (curvature < 0.0) {
            vec3  xvirtTest = nrd_get_xvirtual(hitDist, curvature, currentPosition, currentPosition, currentNormal, V, currentRoughness);
            vec2  uvTest    = spec_pixels_to_uv(spec_project_to_prev_pixels(xvirtTest));
            vec2  uvCurr    = spec_pixels_to_uv(spec_project_to_prev_pixels(currentPosition));
            float a         = length((uvTest - uvCurr) * vec2(viewWidth, viewHeight) * PH_RENDER_SCALE);
            if (a >= NRD_MAX_ALLOWED_VMB_ACCEL * smbParallaxInPixelsMax + 1.0 / (viewWidth * PH_RENDER_SCALE)) {
                curvature = 0.0;
            }
        }
    }

    // -------------------------------------------------------------------------
    // Virtual world position (NRD ref line 738)
    // -------------------------------------------------------------------------
    vec3 virtualWorldPos = nrd_get_xvirtual(
        hitDist, curvature,
        currentPosition, prevWorldPosSMB,
        currentNormal, V, currentRoughness
    );

    // -------------------------------------------------------------------------
    // VMB reprojection: project virtualWorldPos through previous MVP
    // -------------------------------------------------------------------------
    vec2 vmbPixelPosFloat  = spec_project_to_prev_pixels(virtualWorldPos);
    ivec2 vmbBilinearOrigin = ivec2(floor(vmbPixelPosFloat - 0.5));
    vec2  vmbBilinearWeights = fract(vmbPixelPosFloat - 0.5);
    vec2  prevUVVMB           = spec_pixels_to_uv(vmbPixelPosFloat);

    ivec2 vmbTap00 = vmbBilinearOrigin;
    ivec2 vmbTap10 = vmbBilinearOrigin + ivec2(1, 0);
    ivec2 vmbTap01 = vmbBilinearOrigin + ivec2(0, 1);
    ivec2 vmbTap11 = vmbBilinearOrigin + ivec2(1, 1);

    vec4 vmbTapValid;
    vmbTapValid.x = spec_check_tap(vmbTap00, texSize, currentPosition, currentNormal, currentMaterial, disocclusionThreshold);
    vmbTapValid.y = spec_check_tap(vmbTap10, texSize, currentPosition, currentNormal, currentMaterial, disocclusionThreshold);
    vmbTapValid.z = spec_check_tap(vmbTap01, texSize, currentPosition, currentNormal, currentMaterial, disocclusionThreshold);
    vmbTapValid.w = spec_check_tap(vmbTap11, texSize, currentPosition, currentNormal, currentMaterial, disocclusionThreshold);

    // VMB reprojection found only if ALL four taps valid (NRD ref line 351)
    float vmbReprojectionFound = (dot(vmbTapValid, vec4(1.0)) > 3.5) ? 1.0 : 0.0;

    float vmbFx = vmbBilinearWeights.x;
    float vmbFy = vmbBilinearWeights.y;
    vec4  vmbStandardWeights = vec4(
        (1.0 - vmbFx) * (1.0 - vmbFy),
        vmbFx         * (1.0 - vmbFy),
        (1.0 - vmbFx) * vmbFy,
        vmbFx         * vmbFy
    );
    vec4  vmbCustomWeights = vmbStandardWeights * vmbTapValid;
    float vmbSumCustom     = dot(vmbCustomWeights, vec4(1.0));
    bool  vmbCanSample     = vmbSumCustom > 1e-4;
    if (vmbCanSample) vmbCustomWeights /= vmbSumCustom;

    // VMB history sampling
    vec4  vmbPrevSlow  = vec4(0.0);
    vec4  vmbPrevFast  = vec4(0.0);
    vec3  prevNormalVMB    = currentNormal;
    float prevRoughnessVMB = 0.0;
    float prevHitTVMB      = viewDistance; // default: gDenoisingRange approximation

    if (vmbCanSample) {
        if (vmbCustomWeights.x > 0.0) {
            vmbPrevSlow += texelFetch(prev_spec_slow_input, vmbTap00, 0) * vmbCustomWeights.x;
            vmbPrevFast += texelFetch(prev_spec_fast_input, vmbTap00, 0) * vmbCustomWeights.x;
        }
        if (vmbCustomWeights.y > 0.0) {
            vmbPrevSlow += texelFetch(prev_spec_slow_input, vmbTap10, 0) * vmbCustomWeights.y;
            vmbPrevFast += texelFetch(prev_spec_fast_input, vmbTap10, 0) * vmbCustomWeights.y;
        }
        if (vmbCustomWeights.z > 0.0) {
            vmbPrevSlow += texelFetch(prev_spec_slow_input, vmbTap01, 0) * vmbCustomWeights.z;
            vmbPrevFast += texelFetch(prev_spec_fast_input, vmbTap01, 0) * vmbCustomWeights.z;
        }
        if (vmbCustomWeights.w > 0.0) {
            vmbPrevSlow += texelFetch(prev_spec_slow_input, vmbTap11, 0) * vmbCustomWeights.w;
            vmbPrevFast += texelFetch(prev_spec_fast_input, vmbTap11, 0) * vmbCustomWeights.w;
        }

        // Sample prev normal and roughness at VMB UV (bilinear)
        vec2 vmbNormalUv = prevUVVMB;
        vec3 vmbPrevGeoN  = texture(prev_radiosity_normal,        vmbNormalUv).xyz;
        vec3 vmbPrevMapN  = texture(prev_radiosity_mapped_normal,  vmbNormalUv).xyz;
        prevNormalVMB     = nrd_select_surface_normal(vmbPrevGeoN, vmbPrevMapN);
        vec4 vmbPrevMat   = texture(prev_radiosity_material,       vmbNormalUv);
        prevRoughnessVMB  = vmbPrevMat.r;
        prevHitTVMB       = max(0.001, texture(spec_history_confidence_input, prevUVVMB).g);
    }

    // -------------------------------------------------------------------------
    // Virtual history amount — dominant factor (NRD ref lines 774-820)
    // -------------------------------------------------------------------------
    float dominantFactor     = nrd_specular_dominant_factor(currentNormal, V, currentRoughnessModified);
    float virtualHistoryAmount = vmbReprojectionFound * dominantFactor;

    // Back-facing rejection (NRD ref line 781)
    virtualHistoryAmount *= (dot(prevNormalVMB, normalize(currentNormalAveraged)) > 0.0) ? 1.0 : 0.0;

    // Curvature angle and normal weight (NRD ref lines 784-794)
    vec2  uvDiff              = prevUVVMB - prevUVSMB;
    float uvDiffLengthInPixels = length(uvDiff * vec2(viewWidth, viewHeight) * PH_RENDER_SCALE);

    float tanCurvature   = abs(curvature * pixelSize);
    tanCurvature        *= max(uvDiffLengthInPixels / max(NoV, 0.01), 1.0);
    float curvatureAngle = atan(tanCurvature);

    float lobeHalfAngle  = max(atan(nrd_spec_lobe_tan_half_angle(currentRoughnessModified, 0.5)), RELAX_NORMAL_ULP_VAL);
    float normalWeight   = nrd_encoding_aware_normal_weight(currentNormal, prevNormalVMB, lobeHalfAngle, curvatureAngle, RELAX_NORMAL_ULP_VAL);
    virtualHistoryAmount *= mix(1.0 - clamp(uvDiffLengthInPixels, 0.0, 1.0), 1.0, normalWeight);

    // Roughness weight (NRD ref lines 797-800)
    vec2  relaxedRoughnessParams = nrd_relaxed_roughness_weight_params(currentRoughness * currentRoughness, NRD_ROUGHNESS_FRACTION);
    float virtualRoughnessWeight = nrd_compute_weight(prevRoughnessVMB * prevRoughnessVMB, relaxedRoughnessParams.x, relaxedRoughnessParams.y);
    virtualRoughnessWeight       = mix(1.0 - clamp(uvDiffLengthInPixels, 0.0, 1.0), 1.0, virtualRoughnessWeight);
    virtualHistoryAmount        *= virtualRoughnessWeight;
    float specVMBConfidence      = virtualRoughnessWeight * 0.9 + 0.1;

    // "Looking back" 1 and 2 frames (NRD ref lines 803-820)
    {
        vec2 uvDiffNorm = uvDiff;
        float uvDiffLenSq = dot(uvDiffNorm, uvDiffNorm);
        if (uvDiffLenSq > 1e-12) {
            uvDiffNorm *= inversesqrt(uvDiffLenSq + 1e-12);
        }
        // Scale step: saturate(uvDiffLengthInPixels / 0.1) + uvDiffLengthInPixels / 2.0
        // Convert step from pixel-space to UV-space:
        vec2 uvStep = uvDiffNorm / max(vec2(viewWidth, viewHeight) * PH_RENDER_SCALE, vec2(1.0));
        uvStep *= (clamp(uvDiffLengthInPixels / 0.1, 0.0, 1.0) + uvDiffLengthInPixels * 0.5);

        vec2 backUV1 = prevUVVMB + 1.0 * uvStep;
        vec2 backUV2 = prevUVVMB + 2.0 * uvStep;

        // Sample back normals and roughness
        vec3  backNorm1 = nrd_select_surface_normal(
            texture(prev_radiosity_normal,        backUV1).xyz,
            texture(prev_radiosity_mapped_normal, backUV1).xyz
        );
        vec4  backMat1  = texture(prev_radiosity_material, backUV1);
        float backRough1 = backMat1.r;

        vec3  backNorm2 = nrd_select_surface_normal(
            texture(prev_radiosity_normal,        backUV2).xyz,
            texture(prev_radiosity_mapped_normal, backUV2).xyz
        );
        vec4  backMat2  = texture(prev_radiosity_material, backUV2);
        float backRough2 = backMat2.r;

        bool inScreen1 = all(greaterThan(backUV1, vec2(0.0))) && all(lessThan(backUV1, vec2(1.0)));
        bool inScreen2 = all(greaterThan(backUV2, vec2(0.0))) && all(lessThan(backUV2, vec2(1.0)));

        float prevPrevNormalWeight = 1.0;
        if (inScreen1) prevPrevNormalWeight *= nrd_encoding_aware_normal_weight(prevNormalVMB, backNorm1, lobeHalfAngle, curvatureAngle * 2.0, RELAX_NORMAL_ULP_VAL);
        if (inScreen2) prevPrevNormalWeight *= nrd_encoding_aware_normal_weight(prevNormalVMB, backNorm2, lobeHalfAngle, curvatureAngle * 3.0, RELAX_NORMAL_ULP_VAL);

        virtualHistoryAmount *= 0.33 + 0.67 * prevPrevNormalWeight;
        specVMBConfidence    *= 0.33 + 0.67 * prevPrevNormalWeight;

        // Roughness 1 and 2 frames back (NRD ref lines 818-820)
        float rw  = nrd_compute_weight(backRough1 * backRough1, relaxedRoughnessParams.x, relaxedRoughnessParams.y);
        rw       *= nrd_compute_weight(backRough2 * backRough2, relaxedRoughnessParams.x, relaxedRoughnessParams.y);
        virtualHistoryAmount *= rw * 0.9 + 0.1;
    }

    // -------------------------------------------------------------------------
    // Hit distance confidence (NRD ref lines 822-849)
    // -------------------------------------------------------------------------
    float SMC        = nrd_spec_magic_curve(currentRoughnessModified);
    float hitDistC   = mix(currentSpec.hitDistance, smbPrevHitT, SMC);
    float hitDist1TL = nrd_apply_thin_lens_equation(hitDistC, curvature);
    float hitDist2TL = nrd_apply_thin_lens_equation(prevHitTVMB, curvature);
    float maxDistTL  = max(hitDist1TL, hitDist2TL);
    float dHitT      = abs(hitDist1TL - hitDist2TL);
    float dHitTMult  = mix(20.0, 0.0, SMC);
    float virtualHistoryHitDistConf = 1.0 - clamp(dHitTMult * dHitT / (viewDistance + maxDistTL), 0.0, 1.0);
    virtualHistoryHitDistConf = mix(virtualHistoryHitDistConf, 1.0, SMC);

    // Virtual UV discrepancy confidence (NRD ref lines 833-849)
    {
        // gHistory_SpecFast.a tracks the previous frame's local hit distance, not
        // the accumulated reflection hit distance.
        float hitDistForTrackingPrev = max(vmbPrevFast.a, 0.001);
        vec3  prevVirtualWorldPos = nrd_get_xvirtual(
            hitDistForTrackingPrev, curvature,
            currentPosition, prevWorldPosSMB,
            currentNormal, V, currentRoughness
        );
        vec2  prevUVVMBTest = spec_pixels_to_uv(spec_project_to_prev_pixels(prevVirtualWorldPos));

        float percentOfVolume   = 0.6;
        float lobeTanHalfAngle  = nrd_spec_lobe_tan_half_angle(currentRoughness, percentOfVolume);
        float pixSizeInv        = 1.0 / max(viewWidth * PH_RENDER_SCALE, 1.0);
        lobeTanHalfAngle        = max(lobeTanHalfAngle, 0.5 * pixSizeInv);

        float virtualPosLen     = length(virtualWorldPos - world_camera_position);
        float prevVirtualPosLen = length(prevVirtualWorldPos - world_camera_position);
        float maxVirtDist       = max(virtualPosLen, prevVirtualPosLen);
        float pixelSizeAtVirt   = maxVirtDist / max(0.5 * viewHeight, 1.0);
        float unproj1           = min(hitDist, max(hitDistForTrackingPrev, 0.001)) /
                                  max(pixelSizeAtVirt, 1e-6);
        float lobeRadiusInPixels = lobeTanHalfAngle * unproj1;

        float deltaParallaxPx = length((prevUVVMBTest - prevUVVMB) * vec2(viewWidth, viewHeight) * PH_RENDER_SCALE);
        virtualHistoryHitDistConf *= 1.0 - smoothstep(0.0, lobeRadiusInPixels + 0.25, deltaParallaxPx);
    }

    // -------------------------------------------------------------------------
    // SMB confidence (NRD ref lines 852-853)
    // -------------------------------------------------------------------------
    // lobeHalfAngle already computed above
    float specSMBConfidence = smbReprojectionFound *
        nrd_encoding_aware_normal_weight(V, Vprev, lobeHalfAngle * NoV, 0.0, 0.0);

    // -------------------------------------------------------------------------
    // Fallback: reduce VMB if VMB confidence < SMB confidence (NRD ref line 902)
    // -------------------------------------------------------------------------
    virtualHistoryAmount *= clamp(specVMBConfidence / (specSMBConfidence + NRD_EPS), 0.0, 1.0);

    // -------------------------------------------------------------------------
    // SMB accumulation (NRD ref lines 855-875)
    // -------------------------------------------------------------------------
    float specSMBAlpha          = 1.0 - specSMBConfidence;
    float specSMBResponsiveAlpha = 1.0 - specSMBConfidence;
    specSMBAlpha          = max(specSMBAlpha, 1.0 / (1.0 + specHistoryFrames));
    specSMBResponsiveAlpha = max(specSMBAlpha, 1.0 / (1.0 + specHistoryResponsiveFrames));

    // If no SMB reprojection, blend at full alpha (reset)
    if (!smbCanReproject || temporalReset) {
        specSMBAlpha          = 1.0;
        specSMBResponsiveAlpha = 1.0;
    }

    vec4 accumulatedSpecSMB;
    accumulatedSpecSMB.rgb = mix(smbPrevSlow.rgb, currentHistory.radiance, specSMBAlpha);
    accumulatedSpecSMB.a   = mix(smbPrevHitT, currentSpec.hitDistance, max(specSMBAlpha, 0.1));
    float accumulatedSpecM2SMB  = mix(smbPrevSlow.a, currentHistory.secondMoment, specSMBAlpha);
    vec3  accumulatedSpecSMBFast = mix(smbPrevFast.rgb, currentHistory.radiance, specSMBResponsiveAlpha);

    // -------------------------------------------------------------------------
    // VMB accumulation (NRD ref lines 878-899)
    // -------------------------------------------------------------------------
    float specVMBAlpha          = 1.0 - specVMBConfidence;
    float specVMBResponsiveAlpha = 1.0 - specVMBConfidence * virtualHistoryHitDistConf;
    float specVMBHitTAlpha       = specVMBResponsiveAlpha;

    specVMBAlpha          = max(specVMBAlpha, 1.0 / (1.0 + specHistoryFrames));
    specVMBResponsiveAlpha = max(specVMBResponsiveAlpha, 1.0 / (1.0 + specHistoryResponsiveFrames));
    specVMBHitTAlpha       = max(specVMBHitTAlpha, 1.0 / (1.0 + specHistoryFrames));

    if (!vmbCanSample || temporalReset) {
        specVMBAlpha          = 1.0;
        specVMBResponsiveAlpha = 1.0;
        specVMBHitTAlpha       = 1.0;
    }

    vec4 accumulatedSpecVMB;
    accumulatedSpecVMB.rgb = mix(vmbPrevSlow.rgb, currentHistory.radiance, specVMBAlpha);
    accumulatedSpecVMB.a   = mix(prevHitTVMB, currentSpec.hitDistance, max(specVMBHitTAlpha, 0.1));
    float accumulatedSpecM2VMB  = mix(vmbPrevSlow.a, currentHistory.secondMoment, specVMBAlpha);
    vec3  accumulatedSpecVMBFast = mix(vmbPrevFast.rgb, currentHistory.radiance, specVMBResponsiveAlpha);

    // -------------------------------------------------------------------------
    // Dual-path blend (NRD ref lines 901-934)
    // -------------------------------------------------------------------------
    float accumulatedReflectionHitT = mix(accumulatedSpecSMB.a, accumulatedSpecVMB.a, virtualHistoryAmount);

    vec3  accumulatedSpecRadiance         = mix(accumulatedSpecSMB.rgb,  accumulatedSpecVMB.rgb,  virtualHistoryAmount);
    vec3  accumulatedSpecRadianceFast     = mix(accumulatedSpecSMBFast,  accumulatedSpecVMBFast,  virtualHistoryAmount);
    float accumulatedSpec2ndMoment        = mix(accumulatedSpecM2SMB,    accumulatedSpecM2VMB,    virtualHistoryAmount);

    // Specular history confidence output (NRD ref line 926)
    float specularHistoryConfidence = mix(specSMBConfidence, specVMBConfidence, virtualHistoryAmount);

    // Variance boost when 2nd moment is zero (NRD ref line 927)
    if (accumulatedSpec2ndMoment == 0.0) {
        accumulatedSpec2ndMoment = NRD_SPEC_VARIANCE_BOOST * (1.0 - specularHistoryConfidence);
    }

    // -------------------------------------------------------------------------
    // Pack outputs
    // NRD RELAX output layout in this integration:
    //   spec_noisy_out              = current noisy signal (radiance + secondMoment)
    //   spec_responsive_out.r       = specularHistoryConfidence for A-trous
    //   spec_responsive_out.g       = accumulated reflection hit distance for next-frame temporal reuse
    //   spec_responsive_out.a       = 1.0 sentinel
    //   spec_slow_out               = slow accumulated radiance + secondMoment
    //   spec_fast_out.rgb           = fast accumulated radiance
    //   spec_fast_out.a             = current-frame local hit distance (NRD SpecFast contract)
    //   spec_history_length_out     = encoded history length
    // -------------------------------------------------------------------------
    vec4 noisySignal = nrd_pack_direct_history(currentHistory.radiance, currentHistory.secondMoment);

    spec_noisy_out          = noisySignal;
    spec_responsive_out     = vec4(specularHistoryConfidence, accumulatedReflectionHitT, 0.0, 1.0);
    spec_slow_out           = vec4(accumulatedSpecRadiance, accumulatedSpec2ndMoment);
    spec_fast_out           = vec4(accumulatedSpecRadianceFast, hitDist);
    spec_history_length_out = vec4(nrd_encoded_history(historyLength), 0.0, 0.0, 1.0);
}
