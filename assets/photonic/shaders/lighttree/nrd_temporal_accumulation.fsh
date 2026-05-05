#version 430
// RELAX DiffuseSpecular - Fused Temporal Accumulation
// Photonics port of RELAX_TemporalAccumulation.cs.hlsl (NRD reference).
//
// DEVIATIONS FROM REFERENCE (fragment shader vs compute shader):
//   1. No GatherRed / GroupSharedMemory: bilinear-only filter replaces bicubic; 3x3 normal
//      average and minHitDist done via 9 individual texelFetch calls instead of smem.
//   2. Motion vectors: Photonics writes motion.xy = prevPixelCenter - currPixelCenter in pixel
//      space (not UV-space). We divide by rectSize to recover UV offset.
//   3. World positions: absolute world space. We compute viewZ as distance from camera.
//   4. No gCameraDelta: approximated from world_camera_position - previous_world_camera_position.
//   5. No gOrthoMode: assumed perspective (gOrthoMode == 0 always).
//   6. No gFramerateScale: use 1.0.
//   7. No gCheckerboardResolveAccumSpeed: use 0.5.
//   8. No gStrandMaterialID / gCameraAttachedReflectionMaterialID: omitted.
//   9. gSpecMinMaterial / gDiffMinMaterial: use NRD_DEFAULT_MIN_MATERIAL (0.0).
//  10. gHasHistoryConfidence, gHasDisocclusionThresholdMix: not available, assumed false.
//  11. gResolutionScalePrev: assumed 1.0 (no DLSS scaling).
//  12. ComputeParallaxInPixels: implemented inline from reference Common.hlsli.

in vec4 direction_vert_out;

// -----------------------------------------------------------------------
// 7 MRT outputs per contract section 7
// -----------------------------------------------------------------------
layout(location = 0) out vec4 nrd_history_length_out;        // R8   .r = historyLength/255
layout(location = 1) out vec4 nrd_diff_illum_ping_out;       // RGBA16F slow diff: rgb + 2ndMoment
layout(location = 2) out vec4 nrd_spec_illum_ping_out;       // RGBA16F slow spec: rgb + 2ndMoment
layout(location = 3) out vec4 nrd_diff_illum_pong_out;       // RGBA16F responsive diff: rgb + 0
layout(location = 4) out vec4 nrd_spec_illum_pong_out;       // RGBA16F responsive spec: rgb + hitDist
layout(location = 5) out vec4 nrd_reflection_hit_t_curr_out; // R16F   .r = accumulatedReflectionHitT
layout(location = 6) out vec4 nrd_spec_reproj_confidence_out;// R8     .r = specularHistoryConfidence

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

// -----------------------------------------------------------------------
// Helper: convert pixel coords to UV
// -----------------------------------------------------------------------
vec2 nrd_ta_px_to_uv(ivec2 px) {
    return (vec2(px) + 0.5) / vec2(viewWidth, viewHeight);
}

// -----------------------------------------------------------------------
// Helper: project a world position to previous-frame UV
// -----------------------------------------------------------------------
vec2 nrd_ta_project_prev(vec3 worldPos) {
    vec4 clip = previous_modelview_projection * vec4(worldPos, 1.0);
    if (abs(clip.w) < 1e-6) return vec2(-1.0);
    return clip.xy / clip.w * 0.5 + 0.5;
}

// -----------------------------------------------------------------------
// Helper: compute parallax in pixels (Common.hlsli ComputeParallaxInPixels)
// prevWorldPos: surface position in previous frame world space
// prevUV: the expected previous UV for this surface
// -----------------------------------------------------------------------
float nrd_ta_parallax_px(vec3 prevWorldPos, vec2 prevUV, vec2 rectSize) {
    vec4 clipPosPrev = previous_modelview_projection * vec4(prevWorldPos, 1.0);
    if (abs(clipPosPrev.w) < 1e-6) return 0.0;
    vec2 uvPrev = clipPosPrev.xy / clipPosPrev.w * 0.5 + 0.5;
    return length((uvPrev - prevUV) * rectSize);
}

// -----------------------------------------------------------------------
// Helper: bilinear prev sample (vec4) using custom weights from 2x2 origin
// -----------------------------------------------------------------------
vec4 nrd_ta_bilinear_prev_vec4(sampler2D tex, ivec2 origin, vec4 weights) {
    ivec2 sz = textureSize(tex, 0);
    return nrd_bilinear_custom_vec4(
        texelFetch(tex, clamp(origin,             ivec2(0), sz-1), 0),
        texelFetch(tex, clamp(origin+ivec2(1,0),  ivec2(0), sz-1), 0),
        texelFetch(tex, clamp(origin+ivec2(0,1),  ivec2(0), sz-1), 0),
        texelFetch(tex, clamp(origin+ivec2(1,1),  ivec2(0), sz-1), 0),
        weights);
}

// Helper: bilinear prev .r channel
float nrd_ta_bilinear_prev_r(sampler2D tex, ivec2 origin, vec4 weights) {
    ivec2 sz = textureSize(tex, 0);
    return nrd_bilinear_custom_float(
        texelFetch(tex, clamp(origin,             ivec2(0), sz-1), 0).r,
        texelFetch(tex, clamp(origin+ivec2(1,0),  ivec2(0), sz-1), 0).r,
        texelFetch(tex, clamp(origin+ivec2(0,1),  ivec2(0), sz-1), 0).r,
        texelFetch(tex, clamp(origin+ivec2(1,1),  ivec2(0), sz-1), 0).r,
        weights);
}

// -----------------------------------------------------------------------
// Compute bilinear custom weights from fractional position and validity mask.
// RELAX_Common.hlsli Filtering::GetBilinearCustomWeights
// -----------------------------------------------------------------------
vec4 nrd_ta_bilinear_weights(vec2 frac, vec4 tapsValid) {
    float wx = frac.x, wy = frac.y;
    vec4 w;
    w.x = (1.0-wx)*(1.0-wy);
    w.y = wx*(1.0-wy);
    w.z = (1.0-wx)*wy;
    w.w = wx*wy;
    return w * tapsValid;
}

// -----------------------------------------------------------------------
// Load previous world pos tap (for VMB disocclusion check)
// -----------------------------------------------------------------------
vec3 nrd_ta_prev_world_pos(ivec2 px) {
    ivec2 sz = textureSize(prev_radiosity_position, 0);
    return texelFetch(prev_radiosity_position, clamp(px, ivec2(0), sz-1), 0).xyz;
}

// -----------------------------------------------------------------------
// SMB: Load surface-motion-based previous data.
// Reference: loadSurfaceMotionBasedPrevData (RELAX_TemporalAccumulation.cs.hlsl:45-233)
// Returns smbReprojFound (0 = not found, 1 = bilinear found).
// Bicubic collapsed to bilinear-with-custom-weights (deviation #1).
// -----------------------------------------------------------------------
float nrd_ta_load_smb(
    vec3  prevWorldPos,
    vec2  prevUVSMB,
    vec3  currWorldPos,
    float currLinearZ,
    vec3  currNormalAvg,
    float NoV,
    float smbParallaxMax,
    vec4  currMaterial,
    float disocclusionThresh,
    out float footprintQuality,
    out float historyLength,
    out vec4  prevDiffIllum,
    out vec3  prevDiffResponsive,
    out vec4  prevSpecIllum,
    out vec3  prevSpecResponsive,
    out float prevReflHitT
) {
    vec2 rectSize = vec2(viewWidth, viewHeight);
    vec2 prevPixelPosFloat = prevUVSMB * rectSize;
    ivec2 bilinearOrigin   = ivec2(floor(prevPixelPosFloat - 0.5));
    vec2  bilinearWeights  = fract(prevPixelPosFloat - 0.5);

    // Disocclusion threshold scaled by slope (reference lines 112-117)
    float pixelSize = currLinearZ / min(rectSize.x, rectSize.y);
    float frustumSize = pixelSize * min(rectSize.x, rectSize.y);
    float slopeScale  = 1.0 / mix(mix(0.05, 1.0, NoV), 1.0, clamp(smbParallaxMax / 30.0, 0.0, 1.0));
    float smbDisoccThresh = clamp(disocclusionThresh * slopeScale, 0.0, 1.0) * frustumSize;

    // Screen validity (reference line 116)
    vec4 screenValid = nrd_is_in_screen_bilinear(vec2(bilinearOrigin), rectSize);

    // Tap plane-distance validity (reference lines 120-137)
    vec4 tapsValid;
    {
        ivec2 psz = textureSize(prev_radiosity_position, 0);
        tapsValid.x = nrd_is_reprojection_tap_valid(currWorldPos,
            texelFetch(prev_radiosity_position, clamp(bilinearOrigin+ivec2(0,0), ivec2(0), psz-1), 0).xyz,
            currNormalAvg, smbDisoccThresh);
        tapsValid.y = nrd_is_reprojection_tap_valid(currWorldPos,
            texelFetch(prev_radiosity_position, clamp(bilinearOrigin+ivec2(1,0), ivec2(0), psz-1), 0).xyz,
            currNormalAvg, smbDisoccThresh);
        tapsValid.z = nrd_is_reprojection_tap_valid(currWorldPos,
            texelFetch(prev_radiosity_position, clamp(bilinearOrigin+ivec2(0,1), ivec2(0), psz-1), 0).xyz,
            currNormalAvg, smbDisoccThresh);
        tapsValid.w = nrd_is_reprojection_tap_valid(currWorldPos,
            texelFetch(prev_radiosity_position, clamp(bilinearOrigin+ivec2(1,1), ivec2(0), psz-1), 0).xyz,
            currNormalAvg, smbDisoccThresh);

        ivec2 msz = textureSize(prev_radiosity_material, 0);
        tapsValid.x *= nrd_material_weight(currMaterial, texelFetch(prev_radiosity_material, clamp(bilinearOrigin+ivec2(0,0), ivec2(0), msz-1), 0));
        tapsValid.y *= nrd_material_weight(currMaterial, texelFetch(prev_radiosity_material, clamp(bilinearOrigin+ivec2(1,0), ivec2(0), msz-1), 0));
        tapsValid.z *= nrd_material_weight(currMaterial, texelFetch(prev_radiosity_material, clamp(bilinearOrigin+ivec2(0,1), ivec2(0), msz-1), 0));
        tapsValid.w *= nrd_material_weight(currMaterial, texelFetch(prev_radiosity_material, clamp(bilinearOrigin+ivec2(1,1), ivec2(0), msz-1), 0));
    }
    tapsValid *= screenValid;

    // Backface rejection via bilinear-averaged prev normal (reference lines 140-150)
    {
        ivec2 nsz = textureSize(prev_radiosity_normal, 0);
        ivec2 ctr = bilinearOrigin + ivec2(1,1);
        vec3 prevNormalFlat = nrd_safe_normal(texelFetch(prev_radiosity_normal, clamp(ctr, ivec2(0), nsz-1), 0).xyz);
        if (dot(currNormalAvg, prevNormalFlat) < 0.0) {
            tapsValid = vec4(0.0);
        }
    }

    vec4  customWeights = nrd_ta_bilinear_weights(bilinearWeights, tapsValid);
    bool  anyValid      = any(greaterThan(tapsValid, vec4(0.0)));

    prevDiffIllum      = anyValid ? max(nrd_ta_bilinear_prev_vec4(nrd_diff_illum_prev, bilinearOrigin, customWeights), vec4(0.0)) : vec4(0.0);
    prevDiffResponsive = anyValid ? max(nrd_ta_bilinear_prev_vec4(nrd_diff_illum_responsive_prev, bilinearOrigin, customWeights).rgb, vec3(0.0)) : vec3(0.0);
    prevSpecIllum      = anyValid ? max(nrd_ta_bilinear_prev_vec4(nrd_spec_illum_prev, bilinearOrigin, customWeights), vec4(0.0)) : vec4(0.0);
    prevSpecResponsive = anyValid ? max(nrd_ta_bilinear_prev_vec4(nrd_spec_illum_responsive_prev, bilinearOrigin, customWeights).rgb, vec3(0.0)) : vec3(0.0);

    // History length (reference lines 208-214)
    historyLength = anyValid
        ? nrd_ta_bilinear_prev_r(nrd_history_length_prev, bilinearOrigin, customWeights) * 255.0
        : 0.0;

    // Reflection hit T (reference lines 216-219)
    prevReflHitT = anyValid
        ? max(0.001, nrd_ta_bilinear_prev_r(nrd_reflection_hit_t_prev, bilinearOrigin, customWeights))
        : 0.001;

    // Footprint quality: sum of bilinear custom weights (reference line 223)
    footprintQuality = anyValid ? dot(customWeights, vec4(1.0)) : 0.0;

    return anyValid ? 1.0 : 0.0;
}

bool nrd_ta_history_sample_valid(vec3 historyRgb, vec3 currentRgb) {
    if (any(isnan(historyRgb)) || any(isinf(historyRgb))) {
        return false;
    }
    if (any(isnan(currentRgb)) || any(isinf(currentRgb))) {
        return false;
    }

    historyRgb = max(historyRgb, vec3(0.0f));
    currentRgb = max(currentRgb, vec3(0.0f));
    float historyLuma = nrd_luminance(historyRgb);
    float currentLuma = nrd_luminance(currentRgb);
    if (!(historyLuma > 0.0f) || isnan(historyLuma) || isinf(historyLuma)) {
        return false;
    }

    float maxAllowedLuma = max(currentLuma * 8.0f, currentLuma + 4.0f);
    return historyLuma <= maxAllowedLuma;
}

bool nrd_ta_history_sample_valid(vec4 historySample, vec4 currentSample) {
    if (historySample.a <= 0.0f || any(isnan(historySample)) || any(isinf(historySample))) {
        return false;
    }
    if (any(isnan(currentSample)) || any(isinf(currentSample))) {
        return false;
    }

    return nrd_ta_history_sample_valid(historySample.rgb, currentSample.rgb);
}

// -----------------------------------------------------------------------
// VMB: Load virtual-motion-based previous specular data.
// Reference: loadVirtualMotionBasedPrevData (RELAX_TemporalAccumulation.cs.hlsl:237-352)
// Returns vmbReprojFound: 1.0 only if ALL 4 bilinear taps are valid (reference line 351).
// -----------------------------------------------------------------------
float nrd_ta_load_vmb(
    vec3  currWorldPos,
    vec3  currNormal,
    float currLinearZ,
    vec3  virtualWorldPos,
    vec4  currMaterial,
    float disocclusionThresh,
    out vec4  prevSpecIllum,
    out vec4  prevSpecResponsive,
    out vec3  prevNormal,
    out float prevRoughness,
    out float prevReflHitT,
    out vec2  prevUVVMB
) {
    vec2 rectSize = vec2(viewWidth, viewHeight);
    prevUVVMB = nrd_ta_project_prev(virtualWorldPos);

    vec2  prevVirtualPixelPosFloat = prevUVVMB * rectSize;
    ivec2 bilinearOrigin           = ivec2(floor(prevVirtualPixelPosFloat - 0.5));
    vec2  bilinearWeights          = fract(prevVirtualPixelPosFloat - 0.5);

    // Disocclusion threshold: perspective (reference line 275)
    float vmbDisoccThresh = disocclusionThresh * currLinearZ;

    // Screen validity
    vec4 screenValid = nrd_is_in_screen_bilinear(vec2(bilinearOrigin), rectSize);

    // Camera delta correction (reference line 272: currentWorldPos -= gCameraDelta)
    vec3 cameraDelta           = world_camera_position - previous_world_camera_position;
    vec3 currWorldPosCentered  = currWorldPos - cameraDelta;

    // Tap validity (reference lines 285-293)
    vec4 tapsValid;
    tapsValid.x = nrd_is_reprojection_tap_valid(currWorldPosCentered, nrd_ta_prev_world_pos(bilinearOrigin+ivec2(0,0)), currNormal, vmbDisoccThresh);
    tapsValid.y = nrd_is_reprojection_tap_valid(currWorldPosCentered, nrd_ta_prev_world_pos(bilinearOrigin+ivec2(1,0)), currNormal, vmbDisoccThresh);
    tapsValid.z = nrd_is_reprojection_tap_valid(currWorldPosCentered, nrd_ta_prev_world_pos(bilinearOrigin+ivec2(0,1)), currNormal, vmbDisoccThresh);
    tapsValid.w = nrd_is_reprojection_tap_valid(currWorldPosCentered, nrd_ta_prev_world_pos(bilinearOrigin+ivec2(1,1)), currNormal, vmbDisoccThresh);

    // Material check (reference line 294)
    {
        ivec2 msz = textureSize(prev_radiosity_material, 0);
        tapsValid.x *= nrd_material_weight(currMaterial, texelFetch(prev_radiosity_material, clamp(bilinearOrigin+ivec2(0,0), ivec2(0), msz-1), 0));
        tapsValid.y *= nrd_material_weight(currMaterial, texelFetch(prev_radiosity_material, clamp(bilinearOrigin+ivec2(1,0), ivec2(0), msz-1), 0));
        tapsValid.z *= nrd_material_weight(currMaterial, texelFetch(prev_radiosity_material, clamp(bilinearOrigin+ivec2(0,1), ivec2(0), msz-1), 0));
        tapsValid.w *= nrd_material_weight(currMaterial, texelFetch(prev_radiosity_material, clamp(bilinearOrigin+ivec2(1,1), ivec2(0), msz-1), 0));
    }
    tapsValid *= screenValid;

    // Safe defaults (reference lines 297-305)
    prevSpecIllum      = vec4(0.0);
    prevSpecResponsive = vec4(0.0);
    prevNormal         = currNormal;
    prevRoughness      = 0.0;
    prevReflHitT       = ph_nrd_denoising_range;

    if (!any(greaterThan(tapsValid, vec4(0.0)))) {
        return 0.0;
    }

    vec4 customWeights = nrd_ta_bilinear_weights(bilinearWeights, tapsValid);

    prevSpecIllum      = max(nrd_ta_bilinear_prev_vec4(nrd_spec_illum_prev, bilinearOrigin, customWeights), vec4(0.0));
    prevSpecResponsive = max(nrd_ta_bilinear_prev_vec4(nrd_spec_illum_responsive_prev, bilinearOrigin, customWeights), vec4(0.0));

    // prev hit T (reference line 340-341)
    prevReflHitT = max(0.001, texture(nrd_reflection_hit_t_prev, prevUVVMB).r);

    // prev normal and roughness (reference lines 343-347)
    prevNormal    = nrd_safe_normal(texture(prev_radiosity_normal, prevUVVMB).rgb);
    prevRoughness = texture(prev_radiosity_material, prevUVVMB).r;

    // All taps valid required (reference line 351)
    return all(greaterThan(tapsValid, vec4(0.0))) ? 1.0 : 0.0;
}

// -----------------------------------------------------------------------
// main()
// -----------------------------------------------------------------------
void main() {
    // Tile early-out (contract section 7; reference line 376)
    if (texelFetch(nrd_in_tiles, tex_coord >> 4, 0).r > 0.5) discard;

    vec2 rectSize = vec2(viewWidth, viewHeight);
    vec2 pixelUV  = nrd_ta_px_to_uv(tex_coord);

    // Current G-buffer (reference lines 391-400)
    vec3 currWorldPos  = texelFetch(radiosity_position, tex_coord, 0).xyz;
    float currLinearZ  = nrd_compute_view_z(currWorldPos);
    if (currLinearZ >= ph_nrd_denoising_range) discard;

    ivec2 ownerPx = nrd_get_current_checkerboard_owner_pixel(tex_coord, ivec2(viewWidth, viewHeight));
    vec4 currMaterial   = texelFetch(radiosity_material, ownerPx, 0);
    float currRoughness = currMaterial.r;
    vec3 currNormal = nrd_select_surface_normal(
        texelFetch(radiosity_normal, ownerPx, 0).xyz,
        texelFetch(radiosity_mapped_normal, ownerPx, 0).xyz);

    vec3  V   = normalize(world_camera_position - currWorldPos);
    float NoV = abs(dot(currNormal, V));

    // Noisy inputs from prepass (reference lines 422-433)
    vec4 diffuseIllumination  = texelFetch(nrd_out_diff_radiance_hitdist, tex_coord, 0);
    vec4 specularIllumination = texelFetch(nrd_out_spec_radiance_hitdist, tex_coord, 0);

    // 3x3 normal average and minHitDist (reference lines 437-457; smem replaced by texelFetch)
    float minHitDist3x3    = specularIllumination.a > 0.0 ? specularIllumination.a : NRD_INF;
    vec3  currNormalAveraged = currNormal;
    for (int di = -1; di <= 1; di++) {
        for (int dj = -1; dj <= 1; dj++) {
            if (di == 0 && dj == 0) continue;
            ivec2 nbr = tex_coord + ivec2(di, dj);
            float nh  = texelFetch(nrd_out_spec_radiance_hitdist, nbr, 0).a;
            minHitDist3x3 = min(minHitDist3x3, nh > 0.0 ? nh : NRD_INF);
            currNormalAveraged += nrd_select_surface_normal(
                texelFetch(radiosity_normal, nbr, 0).xyz,
                texelFetch(radiosity_mapped_normal, nbr, 0).xyz);
        }
    }
    currNormalAveraged /= 9.0;

    float currentRoughnessModified = nrd_modified_roughness_from_normal_variance(currRoughness, currNormalAveraged);

    // 2nd moments (reference lines 464-471)
    float specular2ndMoment = nrd_luminance(specularIllumination.rgb);
    specular2ndMoment *= specular2ndMoment;
    float diffuse2ndMoment  = nrd_luminance(diffuseIllumination.rgb);
    diffuse2ndMoment  *= diffuse2ndMoment;

    // Motion vector -> prevUVSMB.
    //
    // Photonics convention (see ph_core.glsl: ph_compute_temporal_motion):
    //   mv4.xy = previousPixel - currentPixelCenter (pixel-space delta)
    //   mv4.z  = previousLinearDepth - currentLinearDepth
    //   mv4.a  = 1.0 when the projection is valid, 0.0 when invalid (clip w<=0 etc.)
    //
    // This is equivalent to NRD's gMvScale.w == 0 path (pixel/UV-space motion).
    // We never have a world-space MV; the reference's `gMvScale.w != 0` branch is
    // intentionally absent.
    vec4 mv4 = texelFetch(radiosity_motion, tex_coord, 0);
    vec3 mv  = mv4.xyz;

    vec3 prevWorldPos;
    vec2 prevUVSMB;
    if (mv4.a > 0.5) {
        // Valid MV: prev pixel = curr pixel + pixel-space delta, recover prev world from prev G-buffer.
        prevUVSMB = pixelUV + mv.xy / rectSize;
        ivec2 prevPxNear = ivec2(prevUVSMB * rectSize);
        ivec2 psz = textureSize(prev_radiosity_position, 0);
        prevPxNear = clamp(prevPxNear, ivec2(0), psz - 1);
        prevWorldPos = texelFetch(prev_radiosity_position, prevPxNear, 0).xyz;
    } else {
        // Invalid MV (e.g., behind camera last frame): project current world pos into prev clip.
        prevWorldPos = currWorldPos;
        prevUVSMB    = nrd_ta_project_prev(prevWorldPos);
    }

    // Parallax (reference lines 475-479)
    vec3  cameraDelta         = world_camera_position - previous_world_camera_position;
    float smbParallax1        = nrd_ta_parallax_px(prevWorldPos + cameraDelta, prevUVSMB, rectSize);
    float smbParallax2        = nrd_ta_parallax_px(prevWorldPos - cameraDelta, pixelUV,   rectSize);
    float smbParallaxMax      = max(smbParallax1, smbParallax2);
    float smbParallaxMin      = min(smbParallax1, smbParallax2);

    // SMB (reference lines 499-551)
    float footprintQuality;
    float historyLength;
    vec4  prevDiffIllumSMB;
    vec3  prevDiffResponsiveSMB;
    vec4  prevSpecIllumSMB;
    vec3  prevSpecResponsiveSMB;
    float prevReflHitTSMB;

    float smbReprojFound = nrd_ta_load_smb(
        prevWorldPos, prevUVSMB,
        currWorldPos, currLinearZ, normalize(currNormalAveraged),
        NoV, smbParallaxMax, currMaterial,
        ph_nrd_disocclusion_threshold,
        footprintQuality, historyLength,
        prevDiffIllumSMB, prevDiffResponsiveSMB,
        prevSpecIllumSMB, prevSpecResponsiveSMB, prevReflHitTSMB);

    if (smbReprojFound > 0.0) {
        bool validSurfaceHistory =
            nrd_ta_history_sample_valid(prevDiffIllumSMB, diffuseIllumination)
            && nrd_ta_history_sample_valid(prevDiffResponsiveSMB, diffuseIllumination.rgb)
            && nrd_ta_history_sample_valid(prevSpecIllumSMB, specularIllumination)
            && nrd_ta_history_sample_valid(prevSpecResponsiveSMB, specularIllumination.rgb)
            && historyLength > 0.0
            && !isnan(historyLength)
            && !isinf(historyLength);
        if (!validSurfaceHistory) {
            smbReprojFound = 0.0;
            footprintQuality = 0.0;
            historyLength = 0.0;
            prevDiffIllumSMB = vec4(0.0);
            prevDiffResponsiveSMB = vec3(0.0);
            prevSpecIllumSMB = vec4(0.0);
            prevSpecResponsiveSMB = vec3(0.0);
            prevReflHitTSMB = 0.001;
        }
    }

    // History length adjustments (reference lines 554-585)
    historyLength = min(historyLength + 1.0, RELAX_MAX_ACCUM_FRAME_NUM);

    // Footprint stretching fix (reference lines 558-563)
    vec3  Vprev    = -normalize(prevWorldPos - cameraDelta - previous_world_camera_position);
    float NoVprev  = abs(dot(currNormal, Vprev));
    float sizeQ    = (NoVprev + 1e-3) / (NoV + 1e-3);
    sizeQ *= sizeQ; sizeQ *= sizeQ;
    footprintQuality *= mix(0.1, 1.0, clamp(sizeQ, 0.0, 1.0));

    // History shortening (reference lines 567-572)
    if (footprintQuality < 1.0) {
        historyLength *= sqrt(footprintQuality);
        historyLength  = max(historyLength, 1.0);
    }

    // History reset (reference line 575)
    if (ph_nrd_reset_history != 0.0) historyLength = 1.0;

    // Clamp history to max (reference lines 578-585; diff==spec max here)
    historyLength = min(historyLength, 1.0 + ph_nrd_max_accumulated_frame_num);

    // Diffuse temporal accumulation (reference lines 590-631)
    float diffuseAlpha = (smbReprojFound > 0.0)
        ? max(1.0 / (ph_nrd_max_accumulated_frame_num + 1.0),      1.0 / historyLength)
        : 1.0;
    float diffuseAlphaResponsive = (smbReprojFound > 0.0)
        ? max(1.0 / (ph_nrd_max_fast_accumulated_frame_num + 1.0), 1.0 / historyLength)
        : 1.0;

    vec4 accumulatedDiffIllum = mix(prevDiffIllumSMB,
        vec4(diffuseIllumination.rgb, diffuse2ndMoment), diffuseAlpha);
    vec3 accumulatedDiffResponsive = mix(prevDiffResponsiveSMB,
        diffuseIllumination.rgb, diffuseAlphaResponsive);

    // Specular frame counts (reference lines 644-648)
    float specHistoryFrames   = min(ph_nrd_max_accumulated_frame_num,      historyLength);
    float specHistoryFastFrms = min(ph_nrd_max_fast_accumulated_frame_num, historyLength);

    float hitDist = minHitDist3x3 == NRD_INF ? 0.0 : minHitDist3x3;

    // Curvature estimation (reference lines 652-736)
    float curvature = 0.0;
    {
        vec2 uvForZeroParallax = prevUVSMB;
        vec2 prevWorldInClip   = nrd_ta_project_prev(prevWorldPos + cameraDelta);
        vec2 deltaUv = uvForZeroParallax - prevWorldInClip;
        deltaUv *= rectSize;
        deltaUv /= max(smbParallax1, 1.0 / 256.0);

        float pixelSize  = currLinearZ / min(rectSize.x, rectSize.y);
        vec3  camPos     = world_camera_position;

        // 10 edge (reference lines 663-671)
        vec3 n10     = nrd_select_surface_normal(texelFetch(radiosity_normal, tex_coord+ivec2(1,0), 0).xyz,
                                                  texelFetch(radiosity_mapped_normal, tex_coord+ivec2(1,0), 0).xyz);
        vec3 x10_raw = texelFetch(radiosity_position, tex_coord+ivec2(1,0), 0).xyz;
        vec3 v10     = normalize(x10_raw - camPos);
        float d10    = dot(currNormal, v10);
        vec3 x10     = abs(d10) > 1e-6 ? camPos + v10 * dot(currWorldPos - camPos, currNormal) / d10 : x10_raw;

        // 01 edge (reference lines 673-681)
        vec3 n01     = nrd_select_surface_normal(texelFetch(radiosity_normal, tex_coord+ivec2(0,1), 0).xyz,
                                                  texelFetch(radiosity_mapped_normal, tex_coord+ivec2(0,1), 0).xyz);
        vec3 x01_raw = texelFetch(radiosity_position, tex_coord+ivec2(0,1), 0).xyz;
        vec3 v01     = normalize(x01_raw - camPos);
        float d01    = dot(currNormal, v01);
        vec3 x01     = abs(d01) > 1e-6 ? camPos + v01 * dot(currWorldPos - camPos, currNormal) / d01 : x01_raw;

        // Mix (reference lines 685-689)
        vec2 w = abs(deltaUv) + 1.0/256.0;
        w /= w.x + w.y;
        vec3 xm = x10*w.x + x01*w.y;
        vec3 nm = normalize(n10*w.x + n01*w.y);

        // High parallax replacement (reference lines 691-721)
        float edgeFix = 1.0 - nrd_pow5(NoV);
        float dither  = fract(float((tex_coord.x ^ tex_coord.y ^ frameCounter) & 0xFFFF) * 0.61803398875);
        float deltaUvLenFixed = smbParallaxMin;
        deltaUvLenFixed *= 1.0 + edgeFix * (1.0 + 1.0 * dither);
        vec2 motionUVHigh = pixelUV + deltaUvLenFixed * deltaUv / rectSize;
        motionUVHigh = (floor(motionUVHigh * rectSize) + 0.5) / rectSize;

        if (deltaUvLenFixed > 1.0 && nrd_is_in_screen_nearest(motionUVHigh) > 0.5) {
            ivec2 highPx   = clamp(ivec2(motionUVHigh * rectSize), ivec2(0), ivec2(viewWidth-1, viewHeight-1));
            vec3  xHigh    = texelFetch(radiosity_position, highPx, 0).xyz;
            vec3  nHigh    = nrd_select_surface_normal(texelFetch(radiosity_normal, highPx, 0).xyz,
                                                        texelFetch(radiosity_mapped_normal, highPx, 0).xyz);

            float frustumSize = min(rectSize.x, rectSize.y) * pixelSize;
            float geomThresh  = NRD_CURVATURE_HIGH_PARALLAX_DISOCCLUSION_THRESHOLD * frustumSize;
            float NoX         = dot(currNormal, xHigh - currWorldPos);
            float geomWeight  = nrd_compute_weight(NoX, 1.0 / max(geomThresh, 1e-6), 0.0);
            bool  cmp         = geomWeight > 0.5;
            nm = cmp ? nHigh : nm;
            xm = cmp ? xHigh : xm;
        }

        // Curvature from edge (reference lines 723-726)
        vec3  edge      = xm - currWorldPos;
        float edgeLenSq = dot(edge, edge);
        curvature = edgeLenSq > 1e-12 ? dot(nm - currNormal, edge) / edgeLenSq : 0.0;

        // Negative curvature clamp (reference lines 728-735)
        if (curvature < 0.0) {
            vec2  uv1  = nrd_ta_project_prev(nrd_get_xvirtual(hitDist, curvature, currWorldPos, currWorldPos, currNormal, V, currRoughness));
            vec2  uv2  = nrd_ta_project_prev(currWorldPos);
            float accel = length((uv1 - uv2) * rectSize);
            if (accel >= NRD_MAX_ALLOWED_VIRTUAL_MOTION_ACCELERATION * smbParallaxMax + 1.0/rectSize.x) {
                curvature = 0.0;
            }
        }
    }

    // Virtual world position (reference line 738)
    vec3 virtualWorldPos = nrd_get_xvirtual(hitDist, curvature, currWorldPos, prevWorldPos, currNormal, V, currRoughness);

    // VMB reprojection (reference lines 741-771)
    vec4  prevSpecIllumVMB;
    vec4  prevSpecResponsiveVMB;
    vec3  prevNormalVMB;
    float prevRoughnessVMB;
    float prevReflHitTVMB;
    vec2  prevUVVMB;

    float vmbReprojFound = nrd_ta_load_vmb(
        currWorldPos, currNormal, currLinearZ,
        virtualWorldPos, currMaterial,
        ph_nrd_disocclusion_threshold,
        prevSpecIllumVMB, prevSpecResponsiveVMB,
        prevNormalVMB, prevRoughnessVMB, prevReflHitTVMB, prevUVVMB);

    if (vmbReprojFound > 0.0) {
        bool validVirtualHistory =
            nrd_ta_history_sample_valid(prevSpecIllumVMB, specularIllumination)
            && nrd_ta_history_sample_valid(prevSpecResponsiveVMB, specularIllumination.rgb);
        if (!validVirtualHistory) {
            vmbReprojFound = 0.0;
            prevSpecIllumVMB = vec4(0.0);
            prevSpecResponsiveVMB = vec4(0.0);
            prevNormalVMB = currNormal;
            prevRoughnessVMB = currRoughness;
            prevReflHitTVMB = 0.001;
            prevUVVMB = prevUVSMB;
        }
    }

    // Virtual history amount (reference lines 773-801)
    float dominantFactor      = nrd_specular_dominant_factor(currNormal, V, currentRoughnessModified);
    float virtualHistoryAmount = vmbReprojFound * dominantFactor;

    // Back-facing check (reference line 781)
    virtualHistoryAmount *= float(dot(prevNormalVMB, currNormalAveraged) > 0.0);

    // Curvature angle (reference lines 784-789)
    vec2  uvDiff               = prevUVVMB - prevUVSMB;
    float uvDiffLengthInPixels = length(uvDiff * rectSize);
    float tanCurvature         = abs(curvature * currLinearZ / min(rectSize.x, rectSize.y));
    tanCurvature *= max(uvDiffLengthInPixels / max(NoV, 0.01), 1.0);
    float curvatureAngle = atan(tanCurvature);

    // Normal weight (reference lines 792-794)
    float lobeHalfAngle = max(atan(nrd_spec_lobe_tan_half_angle(currentRoughnessModified, 0.75)), RELAX_NORMAL_ULP);
    float normalWeight  = nrd_encoding_aware_normal_weight(currNormal, prevNormalVMB, lobeHalfAngle, curvatureAngle, RELAX_NORMAL_ULP);
    virtualHistoryAmount *= mix(1.0 - clamp(uvDiffLengthInPixels, 0.0, 1.0), 1.0, normalWeight);

    // Roughness weight (reference lines 797-801)
    vec2  relaxedRWP          = nrd_relaxed_roughness_weight_params(currRoughness * currRoughness, ph_nrd_roughness_fraction);
    float virtualRoughnessW   = nrd_compute_weight(prevRoughnessVMB * prevRoughnessVMB, relaxedRWP.x, relaxedRWP.y);
    virtualRoughnessW         = mix(1.0 - clamp(uvDiffLengthInPixels, 0.0, 1.0), 1.0, virtualRoughnessW);
    virtualHistoryAmount *= virtualRoughnessW;
    float specVMBConfidence   = virtualRoughnessW * 0.9 + 0.1;

    // Looking back 1 and 2 frames (reference lines 803-820)
    vec2  uvDiffN = uvDiff * inversesqrt(max(dot(uvDiff, uvDiff), 1e-20));
    uvDiffN /= rectSize;
    uvDiffN *= clamp(uvDiffLengthInPixels / 0.1, 0.0, 1.0) + uvDiffLengthInPixels / 2.0;
    vec2  backUV1 = prevUVVMB + 1.0 * uvDiffN;
    vec2  backUV2 = prevUVVMB + 2.0 * uvDiffN;
    vec3  backN1  = nrd_safe_normal(texture(prev_radiosity_normal, backUV1).rgb);
    vec3  backN2  = nrd_safe_normal(texture(prev_radiosity_normal, backUV2).rgb);
    float backR1  = texture(prev_radiosity_material, backUV1).r;
    float backR2  = texture(prev_radiosity_material, backUV2).r;
    float ppNW =
        (nrd_is_in_screen_nearest(backUV1) > 0.5 ? nrd_encoding_aware_normal_weight(prevNormalVMB, backN1, lobeHalfAngle, curvatureAngle*2.0, RELAX_NORMAL_ULP) : 1.0) *
        (nrd_is_in_screen_nearest(backUV2) > 0.5 ? nrd_encoding_aware_normal_weight(prevNormalVMB, backN2, lobeHalfAngle, curvatureAngle*3.0, RELAX_NORMAL_ULP) : 1.0);
    virtualHistoryAmount *= 0.33 + 0.67 * ppNW;
    specVMBConfidence    *= 0.33 + 0.67 * ppNW;
    float rw = nrd_compute_weight(backR1*backR1, relaxedRWP.x, relaxedRWP.y)
             * nrd_compute_weight(backR2*backR2, relaxedRWP.x, relaxedRWP.y);
    virtualHistoryAmount *= rw * 0.9 + 0.1;

    // Virtual history confidence - hit distance (reference lines 822-831)
    float SMC       = nrd_spec_magic_curve(currentRoughnessModified);
    float hitDistC  = mix(specularIllumination.a, prevReflHitTSMB, SMC);
    float hd1       = nrd_apply_thin_lens_equation(hitDistC, curvature);
    float hd2       = nrd_apply_thin_lens_equation(prevReflHitTVMB, curvature);
    float maxHD     = max(hd1, hd2);
    float vhHitDistConf = 1.0 - clamp(mix(20.0, 0.0, SMC) * abs(hd1-hd2) / (currLinearZ + maxHD), 0.0, 1.0);
    vhHitDistConf   = mix(vhHitDistConf, 1.0, SMC);

    // Virtual history confidence - UV discrepancy (reference lines 833-849)
    float hitDistForTrackingPrev = prevSpecResponsiveVMB.a;
    vec3  prevVirtualWorldPos    = nrd_get_xvirtual(hitDistForTrackingPrev, curvature, currWorldPos, prevWorldPos, currNormal, V, currRoughness);
    vec2  prevUVVMBTest          = nrd_ta_project_prev(prevVirtualWorldPos);
    float lobeTHArw              = max(nrd_spec_lobe_tan_half_angle(currRoughness, 0.6), 0.5/rectSize.x);
    float unproj1                = min(hitDist, hitDistForTrackingPrev) /
        max(max(length(virtualWorldPos), length(prevVirtualWorldPos)) / min(rectSize.x, rectSize.y), 1e-6);
    float lobeRadiusPx           = lobeTHArw * unproj1;
    float deltaParallaxPx        = length((prevUVVMBTest - prevUVVMB) * rectSize);
    vhHitDistConf *= smoothstep(lobeRadiusPx + 0.25, 0.0, deltaParallaxPx);

    // SMB specular confidence (reference lines 851-858)
    float specSMBConfidence = (smbReprojFound > 0.0 ? 1.0 : 0.0) *
        nrd_encoding_aware_normal_weight(V, Vprev, lobeHalfAngle * NoV, 0.0, 0.0);

    float specSMBAlpha           = max(1.0 - specSMBConfidence, 1.0 / (1.0 + specHistoryFrames));
    float specSMBResponsiveAlpha = max(1.0 - specSMBConfidence, 1.0 / (1.0 + specHistoryFastFrms));

    // SMB accumulation (reference lines 871-875)
    vec4 accSpecSMB;
    accSpecSMB.rgb = mix(prevSpecIllumSMB.rgb, specularIllumination.rgb, specSMBAlpha);
    accSpecSMB.a   = mix(prevReflHitTSMB, specularIllumination.a, max(specSMBAlpha, 0.1));
    float accSpecM2SMB      = mix(prevSpecIllumSMB.a, specular2ndMoment, specSMBAlpha);
    vec3  accSpecSMBResp    = mix(prevSpecResponsiveSMB, specularIllumination.rgb, specSMBResponsiveAlpha);

    // VMB specular alpha (reference lines 877-893)
    float specVMBAlpha          = max(1.0 - specVMBConfidence, 1.0 / (1.0 + specHistoryFrames));
    float specVMBResponsiveAlpha= max(1.0 - specVMBConfidence * vhHitDistConf, 1.0 / (1.0 + specHistoryFastFrms));
    float specVMBHitTAlpha      = max(1.0 - specVMBConfidence * vhHitDistConf, 1.0 / (1.0 + specHistoryFrames));

    // VMB accumulation (reference lines 895-899)
    vec4 accSpecVMB;
    accSpecVMB.rgb = mix(prevSpecIllumVMB.rgb, specularIllumination.rgb, specVMBAlpha);
    accSpecVMB.a   = mix(prevReflHitTVMB, specularIllumination.a, max(specVMBHitTAlpha, 0.1));
    float accSpecM2VMB      = mix(prevSpecIllumVMB.a, specular2ndMoment, specVMBAlpha);
    vec3  accSpecVMBResp    = mix(prevSpecResponsiveVMB.rgb, specularIllumination.rgb, specVMBResponsiveAlpha);

    // Fallback to SMB if VMB confidence lower (reference line 902)
    virtualHistoryAmount *= clamp(specVMBConfidence / (specSMBConfidence + NRD_EPS), 0.0, 1.0);

    // Blend SMB + VMB (reference lines 905-910)
    float accReflHitT  = mix(accSpecSMB.a, accSpecVMB.a, virtualHistoryAmount);
    vec3  accSpecIllum = mix(accSpecSMB.rgb, accSpecVMB.rgb, virtualHistoryAmount);
    vec3  accSpecResp  = mix(accSpecSMBResp, accSpecVMBResp, virtualHistoryAmount);
    float accSpec2ndM  = mix(accSpecM2SMB, accSpecM2VMB, virtualHistoryAmount);

    // Zero-sample variance boost (reference lines 926-927)
    float specHistConf = mix(specSMBConfidence, specVMBConfidence, virtualHistoryAmount);
    if (accSpec2ndM == 0.0)
        accSpec2ndM = NRD_SPEC_VARIANCE_BOOST * (1.0 - specHistConf);

    // Write 7 outputs (contract section 7)
    nrd_history_length_out        = vec4(nrd_encoded_history(historyLength), 0.0, 0.0, 0.0);
    nrd_diff_illum_ping_out       = accumulatedDiffIllum;
    nrd_spec_illum_ping_out       = vec4(accSpecIllum, accSpec2ndM);
    nrd_diff_illum_pong_out       = vec4(accumulatedDiffResponsive, 0.0);
    nrd_spec_illum_pong_out       = vec4(accSpecResp, hitDist);
    nrd_reflection_hit_t_curr_out = vec4(accReflHitT, 0.0, 0.0, 0.0);
    nrd_spec_reproj_confidence_out= vec4(specHistConf, 0.0, 0.0, 0.0);
}
