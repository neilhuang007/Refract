#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_noisy_out;
layout(location = 1) out vec4 direct_responsive_out;
layout(location = 2) out vec4 direct_slow_out;
layout(location = 3) out vec4 direct_fast_out;
layout(location = 4) out vec4 direct_history_length_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform float ph_debug_disable_temporal_reset;
uniform float ph_debug_enable_direct_temporal_accumulation;
uniform float ph_nrd_max_accumulated_frame_num;
uniform float ph_nrd_max_fast_accumulated_frame_num;
uniform float ph_nrd_depth_threshold;

uniform sampler2D prev_direct_slow_input;
uniform sampler2D prev_direct_fast_input;
uniform sampler2D prev_direct_history_length_input;

// NRD checkerboard reconstruction: when checkerboard rendering is active, inactive pixels
// receive zero radiance from shade_samples. Reconstruct from geometry-aware neighbors
// before temporal accumulation, matching NRD RELAX's built-in checkerboard support.

// NRD Common.hlsli:331 - ComputeParallaxInPixels
// Computes parallax by projecting the surface position with a camera offset into clip space
// and measuring the UV difference in pixels.
float direct_compute_parallax_in_pixels(vec3 currentPosition, vec3 cameraDelta) {
    vec3 shiftedPos = currentPosition + cameraDelta;
    vec2 shiftedUv = ph_reprojectf(
        previous_modelview_projection,
        shiftedPos,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    ) / vec2(viewWidth, viewHeight);
    vec2 currentUv = (vec2(tex_coord) + 0.5) / vec2(viewWidth, viewHeight);
    vec2 parallaxUv = shiftedUv - currentUv;
    return length(parallaxUv * vec2(viewWidth, viewHeight));
}

// NRD RELAX per-tap disocclusion check.
// Returns 1.0 if the tap is valid for reprojection, 0.0 otherwise.
// Uses world-space plane distance against a per-tap scalar threshold (already resolved from vec4).
float direct_check_tap(ivec2 tapCoord, ivec2 texSize,
    vec3 currentPosition, vec3 currentNormal, vec4 currentMaterial,
    float tapDisocclusionThreshold)
{
    if (any(lessThan(tapCoord, ivec2(0))) || any(greaterThanEqual(tapCoord, texSize))) {
        return 0.0;
    }

    // Checkerboard validity: previous frame taps on inactive pixels hold stale/zero data.
    // Match RTXDI Checkerboard.hlsli — reject taps that were inactive in the previous frame.
    if (!nrd_is_active_checkerboard_pixel(tapCoord, true, ph_restir_active_checkerboard_field)) {
        return 0.0;
    }

    vec4 prevMaterial = texelFetch(prev_radiosity_material, tapCoord, 0);
    if (nrd_material_weight(currentMaterial, prevMaterial) <= 0.0) {
        return 0.0;
    }

    vec3 prevPosition = texelFetch(prev_radiosity_position, tapCoord, 0).xyz;
    float planeDist = abs(dot(prevPosition - currentPosition, currentNormal));
    return planeDist <= tapDisocclusionThreshold ? 1.0 : 0.0;
}

void direct_reset_outputs() {
    direct_noisy_out = vec4(0.0);
    direct_responsive_out = vec4(0.0);
    direct_slow_out = vec4(0.0);
    direct_fast_out = vec4(0.0);
    direct_history_length_out = vec4(0.0);
}

void main() {
    if (!is_in_world()) {
        direct_reset_outputs();
        return;
    }

    if (ph_restir_active_checkerboard_field != 0
        && !nrd_is_active_checkerboard_pixel(tex_coord, false, ph_restir_active_checkerboard_field)) {
        direct_reset_outputs();
        return;
    }

    // --- Setup: fetch current frame data ---
    // Under checkerboard, temporal accumulation operates only on active lanes.
    vec4 rawDirect = texelFetch(stage_radiosity_direct, tex_coord, 0);
    NrdDirectSignal currentDirect = nrd_unpack_direct_signal(rawDirect);
    vec4 currentMaterial = texelFetch(stage_radiosity_material, tex_coord, 0);
    vec3 currentPosition = texelFetch(stage_radiosity_position, tex_coord, 0).xyz;
    vec3 currentGeometryNormal = texelFetch(stage_radiosity_normal, tex_coord, 0).xyz;
    vec3 currentNormal = nrd_select_surface_normal(
        currentGeometryNormal,
        texelFetch(stage_radiosity_mapped_normal, tex_coord, 0).xyz
    );

    // NRD RELAX reference line 439-457: average normal over 3x3 neighborhood.
    // Reference starts with currentNormal (center pixel), adds 8 neighbors, then divides by 9.
    // The divide-by-9 happens before normalization (reference line 457: currentNormalAveraged /= 9.0).
    vec3 avgNormal = currentNormal;
    for (int ny = -1; ny <= 1; ny++) {
        for (int nx = -1; nx <= 1; nx++) {
            if (nx == 0 && ny == 0) continue;
            ivec2 nCoord = tex_coord + ivec2(nx, ny);
            ivec2 texSizeLocal = textureSize(stage_radiosity_normal, 0);
            if (any(lessThan(nCoord, ivec2(0))) || any(greaterThanEqual(nCoord, texSizeLocal))) continue;
            vec3 sn = nrd_select_surface_normal(
                texelFetch(stage_radiosity_normal, nCoord, 0).xyz,
                texelFetch(stage_radiosity_mapped_normal, nCoord, 0).xyz
            );
            avgNormal += sn;
        }
    }
    // Reference line 457: divide by 9.0 before normalizing.
    avgNormal /= 9.0;
    vec3 reprojectionNormal = normalize(avgNormal);

    NrdDirectHistorySample currentHistory = nrd_direct_history_from_radiance(currentDirect.radiance);

    if (any(isnan(currentDirect.radiance)) || isnan(currentHistory.secondMoment)) {
        direct_reset_outputs();
        return;
    }

    // --- View info: NoV for disocclusion scaling ---
    vec3 viewDir = currentPosition - world_camera_position;
    float viewDistance = max(length(viewDir), 1e-3);
    viewDir /= viewDistance;
    float NoV = abs(dot(currentNormal, viewDir));

    // --- Parallax (camera translation delta) ---
    vec3 cameraDelta = world_camera_position - previous_world_camera_position;
    // NRD: two parallax estimates, use max for disocclusion and min for other heuristics
    float smbParallaxInPixels1 = direct_compute_parallax_in_pixels(currentPosition, cameraDelta);
    float smbParallaxInPixels2 = direct_compute_parallax_in_pixels(currentPosition, -cameraDelta);
    float smbParallaxInPixelsMax = max(smbParallaxInPixels1, smbParallaxInPixels2);
    float smbParallaxInPixelsMin = min(smbParallaxInPixels1, smbParallaxInPixels2);

    // --- Reprojection UV (keep as float; do NOT truncate yet) ---
    // Motion vector convention: .xy = previousPixel - currentPixelCenter (see light_tree_sampling_stage.fsh).
    // To recover previousPixel: currentPixelCenter + motion.xy. Must ADD, not subtract.
    vec4 motionVector = texelFetch(radiosity_motion, tex_coord, 0);
    vec2 reprojectionUv = motionVector.a > 0.5
        ? (vec2(tex_coord) + vec2(0.5) + motionVector.xy)
        : ph_reprojectf(
            previous_modelview_projection,
            currentPosition + currentNormal * 0.01,
            vec2(viewWidth, viewHeight),
            get_taa_jitter()
        );

    // --- NRD RELAX bilinear setup ---
    vec2 prevPixelPosFloat = reprojectionUv;
    ivec2 bilinearOrigin = ivec2(floor(prevPixelPosFloat - 0.5));
    vec2 bilinearWeights = fract(prevPixelPosFloat - 0.5);
    ivec2 texSize = textureSize(prev_radiosity_position, 0);

    // --- Per-tap disocclusion threshold as vec4 (reference lines 112-117) ---
    float disocclusionThresholdSlopeScale =
        1.0 / max(mix(mix(0.05, 1.0, NoV), 1.0, clamp(smbParallaxInPixelsMax / 30.0, 0.0, 1.0)), 0.05);
    float frustumSize = ph_nrd_depth_threshold * viewDistance;

    // Reference line 115-117: per-tap vec4, gated by IsInScreenBilinear, minus NRD_EPS.
    vec4 screenValidity = nrd_is_in_screen_bilinear(vec2(bilinearOrigin), vec2(texSize));
    vec4 smbDisocclusionThreshold =
        clamp(ph_nrd_depth_threshold * disocclusionThresholdSlopeScale, 0.0, 1.0)
        * frustumSize
        * screenValidity
        - NRD_EPS;

    // --- Tap coordinates ---
    ivec2 tap00 = bilinearOrigin;
    ivec2 tap10 = bilinearOrigin + ivec2(1, 0);
    ivec2 tap01 = bilinearOrigin + ivec2(0, 1);
    ivec2 tap11 = bilinearOrigin + ivec2(1, 1);

    // --- Per-tap validity using per-tap threshold (reference line 125-134) ---
    vec4 bilinearTapsValid;
    bilinearTapsValid.x = direct_check_tap(tap00, texSize, currentPosition, reprojectionNormal, currentMaterial, smbDisocclusionThreshold.x);
    bilinearTapsValid.y = direct_check_tap(tap10, texSize, currentPosition, reprojectionNormal, currentMaterial, smbDisocclusionThreshold.y);
    bilinearTapsValid.z = direct_check_tap(tap01, texSize, currentPosition, reprojectionNormal, currentMaterial, smbDisocclusionThreshold.z);
    bilinearTapsValid.w = direct_check_tap(tap11, texSize, currentPosition, reprojectionNormal, currentMaterial, smbDisocclusionThreshold.w);

    // --- NRD RELAX backface rejection: bilinear sample of previous normal at reprojection center ---
    // NRD samples one bilinearly filtered previous normal at the footprint center.
    vec2 prevNormalUv = prevPixelPosFloat / vec2(textureSize(prev_radiosity_normal, 0));
    vec3 prevNormalBilinear = texture(prev_radiosity_normal, prevNormalUv).xyz;
    vec3 prevMappedNormalBilinear = texture(prev_radiosity_mapped_normal, prevNormalUv).xyz;
    vec3 prevNormalFiltered = nrd_select_surface_normal(prevNormalBilinear, prevMappedNormalBilinear);
    // Reference lines 145-150: reject all taps if previous normal backfaces current reprojection normal.
    if (dot(reprojectionNormal, prevNormalFiltered) < 0.0) {
        bilinearTapsValid = vec4(0.0);
    }

    // --- Bilinear custom weights (reference line 155) ---
    // NRD keeps the masked bilinear weights unnormalized here and lets the sampling
    // helpers normalize later. Footprint quality depends on the pre-normalized sum.
    float fx = bilinearWeights.x;
    float fy = bilinearWeights.y;
    vec4 standardWeights = vec4(
        (1.0 - fx) * (1.0 - fy),
        fx         * (1.0 - fy),
        (1.0 - fx) * fy,
        fx         * fy
    );
    vec4 bilinearCustomWeights = standardWeights * bilinearTapsValid;
    float sumCustomWeights = dot(bilinearCustomWeights, vec4(1.0));
    bool canReproject = sumCustomWeights > 1e-4;
    if (ph_debug_enable_direct_temporal_accumulation < 0.5) {
        canReproject = false;
    }

    // --- Footprint quality (reference line 223) ---
    // bicubicValid = all 4 bilinear taps valid (bicubic equivalent without bicubic infrastructure).
    // footprintQuality = bicubicValid ? 1.0 : dot(bilinearCustomWeights, 1.0)
    // When no taps valid, reprojectionFound = 0 and footprintQuality = 0.
    bool bicubicEquivalentValid = all(equal(bilinearTapsValid, vec4(1.0)));
    float footprintQuality = canReproject
        ? (bicubicEquivalentValid ? 1.0 : sumCustomWeights)
        : 0.0;
    if (canReproject) {
        bilinearCustomWeights /= sumCustomWeights;
    }

    // --- NRD RELAX footprint stretching detection (reference lines 558-563) ---
    // Penalizes reprojection when the previous viewpoint was nearly grazing vs current.
    // sizeQuality + abs(orthoMode): orthoMode = 0 here so the +0.0 is a no-op (documented).
    vec3 prevWorldPos = texture(prev_radiosity_position, prevNormalUv).xyz;
    vec3 Vprev = normalize(prevWorldPos - previous_world_camera_position);
    float NoVprev = abs(dot(currentNormal, Vprev));
    float sizeQuality = (NoVprev + 1e-3) / (NoV + 1e-3);
    sizeQuality *= sizeQuality;
    sizeQuality *= sizeQuality;
    // Reference line 563: saturate(sizeQuality + abs(gOrthoMode)) — orthoMode=0 so +0.0.
    footprintQuality *= mix(0.1, 1.0, clamp(sizeQuality + 0.0, 0.0, 1.0));

    // --- Temporal accumulation ---
    bool temporalReset = light_reload && (ph_debug_disable_temporal_reset < 0.5);

    vec4 noisySignal = nrd_pack_direct_history(currentHistory.radiance, currentHistory.secondMoment);
    vec4 slowSignal = noisySignal;
    vec4 fastSignal = noisySignal;

    float directMaxHistoryLength = ph_nrd_max_accumulated_frame_num + 1.0;
    float historyLength = 1.0;
    float slowMaxAccumulatedFrameNum = ph_nrd_max_accumulated_frame_num;
    float fastMaxAccumulatedFrameNum = ph_nrd_max_fast_accumulated_frame_num;

    if (!temporalReset && canReproject) {
        // --- History length: gather per-tap raw scalars, blend with nrd_bilinear_custom_float ---
        // Reference lines 207-214: gather 4 raw encoded history values (float), then call
        // BilinearWithCustomWeightsImmediateFloat which decodes (multiplies by 255) inside the blend.
        // We decode each tap individually before blending, matching the reference contract.
        float h00 = nrd_decoded_history(texelFetch(prev_direct_history_length_input, tap00, 0));
        float h10 = nrd_decoded_history(texelFetch(prev_direct_history_length_input, tap10, 0));
        float h01 = nrd_decoded_history(texelFetch(prev_direct_history_length_input, tap01, 0));
        float h11 = nrd_decoded_history(texelFetch(prev_direct_history_length_input, tap11, 0));
        float decodedPrevHistory = nrd_bilinear_custom_float(h00, h10, h01, h11, bilinearCustomWeights);

        // Reference lines 554-555: historyLength = historyLength + 1.0, then clamp to max.
        historyLength = min(decodedPrevHistory + 1.0, directMaxHistoryLength);

        // --- Weighted bilinear fetch of slow/fast history buffers across 4 taps ---
        vec4 prevSlow = vec4(0.0);
        vec4 prevFast = vec4(0.0);

        if (bilinearCustomWeights.x > 0.0) {
            prevSlow += texelFetch(prev_direct_slow_input, tap00, 0) * bilinearCustomWeights.x;
            prevFast += texelFetch(prev_direct_fast_input, tap00, 0) * bilinearCustomWeights.x;
        }
        if (bilinearCustomWeights.y > 0.0) {
            prevSlow += texelFetch(prev_direct_slow_input, tap10, 0) * bilinearCustomWeights.y;
            prevFast += texelFetch(prev_direct_fast_input, tap10, 0) * bilinearCustomWeights.y;
        }
        if (bilinearCustomWeights.z > 0.0) {
            prevSlow += texelFetch(prev_direct_slow_input, tap01, 0) * bilinearCustomWeights.z;
            prevFast += texelFetch(prev_direct_fast_input, tap01, 0) * bilinearCustomWeights.z;
        }
        if (bilinearCustomWeights.w > 0.0) {
            prevSlow += texelFetch(prev_direct_slow_input, tap11, 0) * bilinearCustomWeights.w;
            prevFast += texelFetch(prev_direct_fast_input, tap11, 0) * bilinearCustomWeights.w;
        }

        // NRD RELAX reference (RELAX_TemporalAccumulation.cs.hlsl:595-600):
        // Sample diffuse history confidence at the reprojected SMB location.
        float diffConfidence = clamp(texture(diffuse_confidence_input, prevNormalUv).r, 0.0, 1.0);
        slowMaxAccumulatedFrameNum *= diffConfidence;
        fastMaxAccumulatedFrameNum *= diffConfidence;

        // NRD RELAX footprint quality shortening (reference lines 567-572):
        // Partial footprints accumulate less history to prevent ghosting.
        if (footprintQuality < 1.0) {
            historyLength *= sqrt(footprintQuality);
            historyLength = max(historyLength, 1.0);
        }

        float slowAlpha = max(1.0 / (slowMaxAccumulatedFrameNum + 1.0), 1.0 / historyLength);
        float fastAlpha = max(1.0 / (fastMaxAccumulatedFrameNum + 1.0), 1.0 / historyLength);

        slowSignal = nrd_mix_direct_history(prevSlow, currentHistory, slowAlpha);
        fastSignal = nrd_mix_direct_history(prevFast, currentHistory, fastAlpha);
    }

    // NRD RELAX: gOut_DiffFast is the responsive/fast output.
    // Responsive aliases fast signal, matching the reference contract.
    vec4 responsiveSignal = fastSignal;

    direct_noisy_out          = noisySignal;
    direct_responsive_out     = responsiveSignal;
    direct_slow_out           = slowSignal;
    direct_fast_out           = fastSignal;
    direct_history_length_out = vec4(nrd_encoded_history(historyLength), 0.0, 0.0, 1.0);
}
