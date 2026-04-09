#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_noisy_out;
layout(location = 1) out vec4 direct_responsive_out;
layout(location = 2) out vec4 direct_slow_out;
layout(location = 3) out vec4 direct_fast_out;
layout(location = 4) out vec4 direct_history_length_out;

#include "/photonics/common/header.glsl"
#include "/photonics/common/light_blend_regions.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform float ph_debug_disable_temporal_reset;
uniform float ph_debug_enable_direct_temporal_accumulation;
uniform float ph_nrd_max_accumulated_frame_num;
uniform float ph_nrd_max_fast_accumulated_frame_num;
uniform float ph_nrd_depth_threshold;

uniform sampler2D prev_direct_slow_input;
uniform sampler2D prev_direct_fast_input;
uniform sampler2D prev_direct_history_length_input;

// NRD checkerboard support uses the owning active pixel for all current-frame fetches,
// matching RTXDI checkerboard activation/addressing instead of reconstructing neighbors.

// NRD Common.hlsli:331 - ComputeParallaxInPixels
// Computes parallax by projecting the surface position with a camera offset into clip space
// and measuring the UV difference in pixels.
// Temporal reprojection must use stable pixel mapping here; feeding per-frame TAA jitter
// into the previous-frame lookup makes static pixels walk between history texels and never settle.
float direct_compute_parallax_in_pixels(ivec2 currentPixelCoord, vec3 currentPosition, vec3 cameraDelta) {
    vec3 shiftedPos = currentPosition + cameraDelta;
    vec2 shiftedUv = ph_reprojectf(
        previous_modelview_projection,
        shiftedPos,
        vec2(viewWidth, viewHeight),
        vec2(0.0f)
    ) / vec2(viewWidth, viewHeight);
    vec2 currentUv = (vec2(currentPixelCoord) + 0.5) / vec2(viewWidth, viewHeight);
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

    ivec2 ownerTapCoord = nrd_get_checkerboard_owner_pixel(
        tapCoord,
        true,
        ph_restir_active_checkerboard_field,
        texSize
    );

    vec4 prevMaterial = texelFetch(prev_radiosity_material, ownerTapCoord, 0);
    if (nrd_material_weight(currentMaterial, prevMaterial) <= 0.0) {
        return 0.0;
    }

    vec3 prevPosition = texelFetch(prev_radiosity_position, ownerTapCoord, 0).xyz;
    float planeDist = abs(dot(prevPosition - currentPosition, currentNormal));
    return planeDist <= tapDisocclusionThreshold ? 1.0 : 0.0;
}

ivec2 direct_previous_owner_tap(ivec2 tapCoord, ivec2 texSize) {
    return nrd_get_checkerboard_owner_pixel(
        tapCoord,
        true,
        ph_restir_active_checkerboard_field,
        texSize
    );
}

ivec2 direct_current_owner_tap(ivec2 tapCoord, ivec2 texSize) {
    return nrd_get_checkerboard_owner_pixel(
        tapCoord,
        false,
        ph_restir_active_checkerboard_field,
        texSize
    );
}

vec4 direct_bilinear_fetch_prev_vec4(
    sampler2D tex,
    ivec2 tap00,
    ivec2 tap10,
    ivec2 tap01,
    ivec2 tap11,
    vec4 weights,
    ivec2 texSize
) {
    return nrd_bilinear_custom_vec4(
        texelFetch(tex, direct_previous_owner_tap(tap00, texSize), 0),
        texelFetch(tex, direct_previous_owner_tap(tap10, texSize), 0),
        texelFetch(tex, direct_previous_owner_tap(tap01, texSize), 0),
        texelFetch(tex, direct_previous_owner_tap(tap11, texSize), 0),
        weights
    );
}

vec3 direct_bilinear_fetch_prev_normal(
    ivec2 tap00,
    ivec2 tap10,
    ivec2 tap01,
    ivec2 tap11,
    vec4 weights,
    ivec2 texSize
) {
    vec4 prevGeoNormal = direct_bilinear_fetch_prev_vec4(
        prev_radiosity_normal,
        tap00,
        tap10,
        tap01,
        tap11,
        weights,
        texSize
    );
    vec4 prevMappedNormal = direct_bilinear_fetch_prev_vec4(
        prev_radiosity_mapped_normal,
        tap00,
        tap10,
        tap01,
        tap11,
        weights,
        texSize
    );
    return nrd_select_surface_normal(prevGeoNormal.xyz, prevMappedNormal.xyz);
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

    ivec2 ownerCoord = tex_coord;
    if (ph_restir_active_checkerboard_field != 0) {
        ownerCoord = nrd_get_checkerboard_owner_pixel(
            tex_coord,
            false,
            ph_restir_active_checkerboard_field,
            textureSize(stage_radiosity_position, 0)
        );
    }

    // --- Setup: fetch current frame data ---
    // Under checkerboard, temporal accumulation operates on the owning active lane.
    vec4 rawDirect = texelFetch(stage_radiosity_direct, ownerCoord, 0);
    NrdDirectSignal currentDirect = nrd_unpack_direct_signal(rawDirect);
    vec4 currentMaterial = texelFetch(stage_radiosity_material, ownerCoord, 0);
    vec3 currentPosition = texelFetch(stage_radiosity_position, ownerCoord, 0).xyz;
    vec3 currentGeometryNormal = texelFetch(stage_radiosity_normal, ownerCoord, 0).xyz;
    vec3 currentNormal = nrd_select_surface_normal(
        currentGeometryNormal,
        texelFetch(stage_radiosity_mapped_normal, ownerCoord, 0).xyz
    );

    // NRD RELAX reference line 439-457: average normal over 3x3 neighborhood.
    // Reference starts with currentNormal (center pixel), adds 8 neighbors, then divides by 9.
    // The divide-by-9 happens before normalization (reference line 457: currentNormalAveraged /= 9.0).
    vec3 avgNormal = currentNormal;
    ivec2 texSizeLocal = textureSize(stage_radiosity_normal, 0);
    for (int ny = -1; ny <= 1; ny++) {
        for (int nx = -1; nx <= 1; nx++) {
            if (nx == 0 && ny == 0) continue;
            ivec2 nCoord = ownerCoord + ivec2(nx, ny);
            if (any(lessThan(nCoord, ivec2(0))) || any(greaterThanEqual(nCoord, texSizeLocal))) continue;
            ivec2 sampleCoord = direct_current_owner_tap(nCoord, texSizeLocal);
            vec3 sn = nrd_select_surface_normal(
                texelFetch(stage_radiosity_normal, sampleCoord, 0).xyz,
                texelFetch(stage_radiosity_mapped_normal, sampleCoord, 0).xyz
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
    float smbParallaxInPixels1 = direct_compute_parallax_in_pixels(ownerCoord, currentPosition, cameraDelta);
    float smbParallaxInPixels2 = direct_compute_parallax_in_pixels(ownerCoord, currentPosition, -cameraDelta);
    float smbParallaxInPixelsMax = max(smbParallaxInPixels1, smbParallaxInPixels2);
    float smbParallaxInPixelsMin = min(smbParallaxInPixels1, smbParallaxInPixels2);

    // --- Reprojection UV (keep as float; do NOT truncate yet) ---
    // Motion vector convention: .xy = previousPixel - currentPixelCenter (see light_tree_sampling_stage.fsh).
    // To recover previousPixel: currentPixelCenter + motion.xy. Must ADD, not subtract.
    vec4 motionVector = texelFetch(radiosity_motion, ownerCoord, 0);
    vec2 reprojectionUv = motionVector.a > 0.5
        ? (vec2(ownerCoord) + vec2(0.5) + motionVector.xy)
        : ph_reprojectf(
            previous_modelview_projection,
            currentPosition + currentNormal * 0.01,
            vec2(viewWidth, viewHeight),
            vec2(0.0f)
        );

    // --- NRD RELAX bilinear setup ---
    vec2 prevPixelPosFloat = reprojectionUv;
    ivec2 prevTextureSize = textureSize(prev_radiosity_position, 0);
    ivec2 bilinearOrigin = ivec2(floor(prevPixelPosFloat - 0.5));
    vec2 bilinearWeights = fract(prevPixelPosFloat - 0.5);
    ivec2 texSize = prevTextureSize;
    vec2 prevUVSMB = reprojectionUv / vec2(texSize);

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

    vec4 normalizedBilinearWeights = canReproject
        ? (bilinearCustomWeights / sumCustomWeights)
        : vec4(0.0);

    // --- NRD RELAX backface rejection: bilinear sample of previous normal at reprojection center ---
    // Sample the actual 2x2 footprint, then map each tap to the previous frame's checkerboard owner.
    vec3 prevNormalFiltered = direct_bilinear_fetch_prev_normal(
        tap00,
        tap10,
        tap01,
        tap11,
        normalizedBilinearWeights,
        texSize
    );
    // Reference lines 145-150: reject all taps if previous normal backfaces current reprojection normal.
    if (canReproject && dot(reprojectionNormal, prevNormalFiltered) < 0.0) {
        bilinearTapsValid = vec4(0.0);
        bilinearCustomWeights = vec4(0.0);
        normalizedBilinearWeights = vec4(0.0);
        sumCustomWeights = 0.0;
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
        bilinearCustomWeights = normalizedBilinearWeights;
    }

    // --- NRD RELAX footprint stretching detection (reference lines 558-563) ---
    // Penalizes reprojection when the previous viewpoint was nearly grazing vs current.
    // sizeQuality + abs(orthoMode): orthoMode = 0 here so the +0.0 is a no-op (documented).
    vec4 prevWorldPosVec = direct_bilinear_fetch_prev_vec4(
        prev_radiosity_position,
        tap00,
        tap10,
        tap01,
        tap11,
        bilinearCustomWeights,
        texSize
    );
    vec3 prevWorldPos = prevWorldPosVec.xyz;
    vec3 Vprev = normalize(prevWorldPos - previous_world_camera_position);
    float NoVprev = abs(dot(currentNormal, Vprev));
    float sizeQuality = (NoVprev + 1e-3) / (NoV + 1e-3);
    sizeQuality *= sizeQuality;
    sizeQuality *= sizeQuality;
    // Reference line 563: saturate(sizeQuality + abs(gOrthoMode)) — orthoMode=0 so +0.0.
    footprintQuality *= mix(0.1, 1.0, clamp(sizeQuality + 0.0, 0.0, 1.0));

    // --- Temporal accumulation ---
    bool temporalReset = (light_reload && (ph_debug_disable_temporal_reset < 0.5))
        || ph_dirty_region_factor(currentPosition) > 0.0;

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
        float h00 = nrd_decoded_history(texelFetch(prev_direct_history_length_input, direct_previous_owner_tap(tap00, texSize), 0));
        float h10 = nrd_decoded_history(texelFetch(prev_direct_history_length_input, direct_previous_owner_tap(tap10, texSize), 0));
        float h01 = nrd_decoded_history(texelFetch(prev_direct_history_length_input, direct_previous_owner_tap(tap01, texSize), 0));
        float h11 = nrd_decoded_history(texelFetch(prev_direct_history_length_input, direct_previous_owner_tap(tap11, texSize), 0));
        float decodedPrevHistory = nrd_bilinear_custom_float(h00, h10, h01, h11, bilinearCustomWeights);

        // Reference lines 554-555: historyLength = historyLength + 1.0, then clamp to max.
        historyLength = min(decodedPrevHistory + 1.0, directMaxHistoryLength);

        // --- Weighted bilinear fetch of slow/fast history buffers across 4 taps ---
        vec4 prevSlow = vec4(0.0);
        vec4 prevFast = vec4(0.0);

        if (bilinearCustomWeights.x > 0.0) {
            prevSlow += texelFetch(prev_direct_slow_input, direct_previous_owner_tap(tap00, texSize), 0) * bilinearCustomWeights.x;
            prevFast += texelFetch(prev_direct_fast_input, direct_previous_owner_tap(tap00, texSize), 0) * bilinearCustomWeights.x;
        }
        if (bilinearCustomWeights.y > 0.0) {
            prevSlow += texelFetch(prev_direct_slow_input, direct_previous_owner_tap(tap10, texSize), 0) * bilinearCustomWeights.y;
            prevFast += texelFetch(prev_direct_fast_input, direct_previous_owner_tap(tap10, texSize), 0) * bilinearCustomWeights.y;
        }
        if (bilinearCustomWeights.z > 0.0) {
            prevSlow += texelFetch(prev_direct_slow_input, direct_previous_owner_tap(tap01, texSize), 0) * bilinearCustomWeights.z;
            prevFast += texelFetch(prev_direct_fast_input, direct_previous_owner_tap(tap01, texSize), 0) * bilinearCustomWeights.z;
        }
        if (bilinearCustomWeights.w > 0.0) {
            prevSlow += texelFetch(prev_direct_slow_input, direct_previous_owner_tap(tap11, texSize), 0) * bilinearCustomWeights.w;
            prevFast += texelFetch(prev_direct_fast_input, direct_previous_owner_tap(tap11, texSize), 0) * bilinearCustomWeights.w;
        }

        float diffConfidence = clamp(textureLod(diffuse_confidence_input, prevUVSMB, 0.0).r, 0.0, 1.0);
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
