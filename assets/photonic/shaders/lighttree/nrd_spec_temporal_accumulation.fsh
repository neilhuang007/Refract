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

uniform sampler2D prev_spec_slow_input;
uniform sampler2D prev_spec_fast_input;
uniform sampler2D prev_spec_history_length_input;

// NRD NOTE (checkerboard): NRD RELAX supports checkerboard rendering (reconstruct missing pixels
// from neighbors before temporal accumulation). Minecraft does not use checkerboard rendering,
// so this step is intentionally omitted.

// NRD Common.hlsli:331 - ComputeParallaxInPixels
float spec_compute_parallax_in_pixels(vec3 currentPosition, vec3 cameraDelta) {
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
float spec_check_tap(ivec2 tapCoord, ivec2 texSize,
    vec3 currentPosition, vec3 currentNormal, vec4 currentMaterial,
    float disocclusionThreshold)
{
    if (any(lessThan(tapCoord, ivec2(0))) || any(greaterThanEqual(tapCoord, texSize))) {
        return 0.0;
    }

    vec4 prevMaterial = texelFetch(prev_radiosity_material, tapCoord, 0);
    if (nrd_material_weight(currentMaterial, prevMaterial) <= 0.0) {
        return 0.0;
    }

    vec3 prevPosition = texelFetch(prev_radiosity_position, tapCoord, 0).xyz;
    if (abs(dot(prevPosition - currentPosition, currentNormal)) > disocclusionThreshold) {
        return 0.0;
    }

    return 1.0;
}

void spec_reset_outputs() {
    spec_noisy_out = vec4(0.0);
    spec_responsive_out = vec4(0.0);
    spec_slow_out = vec4(0.0);
    spec_fast_out = vec4(0.0);
    spec_history_length_out = vec4(0.0);
}

void main() {
    if (!is_in_world()) {
        spec_reset_outputs();
        return;
    }

    // --- Setup: fetch current frame specular data ---
    NrdDirectSignal currentSpec = nrd_unpack_direct_signal(texelFetch(stage_radiosity_direct_specular, tex_coord, 0));
    vec4 currentMaterial = texelFetch(stage_radiosity_material, tex_coord, 0);
    vec3 currentPosition = texelFetch(stage_radiosity_position, tex_coord, 0).xyz;
    vec3 currentGeometryNormal = texelFetch(stage_radiosity_normal, tex_coord, 0).xyz;
    vec3 currentNormal = nrd_select_surface_normal(
        currentGeometryNormal,
        texelFetch(stage_radiosity_mapped_normal, tex_coord, 0).xyz
    );

    // NRD RELAX: average normal over 3x3 neighborhood for reprojection validation only.
    vec3 avgNormal = vec3(0.0);
    for (int ny = -1; ny <= 1; ny++) {
        for (int nx = -1; nx <= 1; nx++) {
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
    vec3 reprojectionNormal = normalize(avgNormal);

    NrdDirectHistorySample currentHistory = nrd_direct_history_from_radiance(currentSpec.radiance);

    if (any(isnan(currentSpec.radiance)) || isnan(currentHistory.secondMoment)) {
        spec_reset_outputs();
        return;
    }

    // --- View info: NoV for disocclusion scaling ---
    vec3 viewDir = currentPosition - world_camera_position;
    float viewDistance = max(length(viewDir), 1e-3);
    viewDir /= viewDistance;
    float NoV = abs(dot(currentNormal, viewDir));

    // --- Parallax (camera translation delta) ---
    vec3 cameraDelta = world_camera_position - previous_world_camera_position;
    float smbParallaxInPixels1 = spec_compute_parallax_in_pixels(currentPosition, cameraDelta);
    float smbParallaxInPixels2 = spec_compute_parallax_in_pixels(currentPosition, -cameraDelta);
    float smbParallaxInPixelsMax = max(smbParallaxInPixels1, smbParallaxInPixels2);

    // --- Reprojection UV ---
    vec4 motionVector = texelFetch(radiosity_motion, tex_coord, 0);
    vec2 reprojectionUv = motionVector.a > 0.5
        ? (vec2(tex_coord) + vec2(0.5) - motionVector.xy)
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

    // --- NRD RELAX disocclusion threshold scaled by NoV and pixel parallax ---
    float NoVfactor = mix(mix(0.05, 1.0, NoV), 1.0, clamp(smbParallaxInPixelsMax / 30.0, 0.0, 1.0));
    float disocclusionScale = 1.0 / max(NoVfactor, 0.05);
    float disocclusionThreshold = ph_nrd_depth_threshold * viewDistance * disocclusionScale;

    // --- Standard bilinear weights ---
    float fx = bilinearWeights.x;
    float fy = bilinearWeights.y;
    vec4 standardWeights = vec4(
        (1.0 - fx) * (1.0 - fy),
        fx         * (1.0 - fy),
        (1.0 - fx) * fy,
        fx         * fy
    );

    // --- Per-tap validity ---
    ivec2 tap00 = bilinearOrigin;
    ivec2 tap10 = bilinearOrigin + ivec2(1, 0);
    ivec2 tap01 = bilinearOrigin + ivec2(0, 1);
    ivec2 tap11 = bilinearOrigin + ivec2(1, 1);

    vec4 tapValid;
    tapValid.x = spec_check_tap(tap00, texSize, currentPosition, currentNormal, currentMaterial, disocclusionThreshold);
    tapValid.y = spec_check_tap(tap10, texSize, currentPosition, currentNormal, currentMaterial, disocclusionThreshold);
    tapValid.z = spec_check_tap(tap01, texSize, currentPosition, currentNormal, currentMaterial, disocclusionThreshold);
    tapValid.w = spec_check_tap(tap11, texSize, currentPosition, currentNormal, currentMaterial, disocclusionThreshold);

    // --- NRD RELAX backface rejection ---
    vec2 prevNormalUv = (prevPixelPosFloat + 0.5) / vec2(textureSize(prev_radiosity_normal, 0));
    vec3 prevNormalBilinear = texture(prev_radiosity_normal, prevNormalUv).xyz;
    vec3 prevMappedNormalBilinear = texture(prev_radiosity_mapped_normal, prevNormalUv).xyz;
    vec3 prevNormalFiltered = nrd_select_surface_normal(prevNormalBilinear, prevMappedNormalBilinear);
    if (dot(reprojectionNormal, prevNormalFiltered) < 0.0) {
        tapValid = vec4(0.0);
    }

    // --- Custom bilinear weights accounting for per-tap validity ---
    vec4 customWeights = standardWeights * tapValid;
    float sumCustom = dot(customWeights, vec4(1.0));
    bool canReproject = sumCustom > 1e-4;
    float footprintQuality = canReproject ? sumCustom : 0.0;
    if (canReproject) customWeights /= sumCustom;

    // --- NRD RELAX footprint stretching detection ---
    vec3 prevWorldPos = texture(prev_radiosity_position, prevNormalUv).xyz;
    vec3 Vprev = normalize(prevWorldPos - previous_world_camera_position);
    float NoVprev = abs(dot(currentNormal, Vprev));
    float sizeQuality = (NoVprev + 1e-3) / (NoV + 1e-3);
    sizeQuality *= sizeQuality;
    sizeQuality *= sizeQuality;
    footprintQuality *= mix(0.1, 1.0, clamp(sizeQuality, 0.0, 1.0));

    // --- Temporal accumulation ---
    bool temporalReset = light_reload && (ph_debug_disable_temporal_reset < 0.5);

    float specMaxHistoryLength = ph_nrd_max_accumulated_frame_num + 1.0;
    vec4 noisySignal = nrd_pack_direct_history(currentHistory.radiance, currentHistory.secondMoment);
    vec4 slowSignal = noisySignal;
    vec4 fastSignal = noisySignal;

    float historyLength = 1.0;
    float slowMaxAccumulatedFrameNum = ph_nrd_max_accumulated_frame_num;
    float fastMaxAccumulatedFrameNum = ph_nrd_max_fast_accumulated_frame_num;

    if (!temporalReset && canReproject) {
        vec4 prevSlow = vec4(0.0);
        vec4 prevFast = vec4(0.0);
        vec4 prevHistoryVec = vec4(0.0);
        vec4 prevConfidenceVec = vec4(0.0);

        if (customWeights.x > 0.0) {
            prevSlow       += texelFetch(prev_spec_slow_input,          tap00, 0) * customWeights.x;
            prevFast       += texelFetch(prev_spec_fast_input,          tap00, 0) * customWeights.x;
            prevHistoryVec += texelFetch(prev_spec_history_length_input, tap00, 0) * customWeights.x;
            prevConfidenceVec += texelFetch(prev_direct_confidence_input, tap00, 0) * customWeights.x;
        }
        if (customWeights.y > 0.0) {
            prevSlow       += texelFetch(prev_spec_slow_input,          tap10, 0) * customWeights.y;
            prevFast       += texelFetch(prev_spec_fast_input,          tap10, 0) * customWeights.y;
            prevHistoryVec += texelFetch(prev_spec_history_length_input, tap10, 0) * customWeights.y;
            prevConfidenceVec += texelFetch(prev_direct_confidence_input, tap10, 0) * customWeights.y;
        }
        if (customWeights.z > 0.0) {
            prevSlow       += texelFetch(prev_spec_slow_input,          tap01, 0) * customWeights.z;
            prevFast       += texelFetch(prev_spec_fast_input,          tap01, 0) * customWeights.z;
            prevHistoryVec += texelFetch(prev_spec_history_length_input, tap01, 0) * customWeights.z;
            prevConfidenceVec += texelFetch(prev_direct_confidence_input, tap01, 0) * customWeights.z;
        }
        if (customWeights.w > 0.0) {
            prevSlow       += texelFetch(prev_spec_slow_input,          tap11, 0) * customWeights.w;
            prevFast       += texelFetch(prev_spec_fast_input,          tap11, 0) * customWeights.w;
            prevHistoryVec += texelFetch(prev_spec_history_length_input, tap11, 0) * customWeights.w;
            prevConfidenceVec += texelFetch(prev_direct_confidence_input, tap11, 0) * customWeights.w;
        }

        float decodedPrevHistory = nrd_decoded_history(prevHistoryVec);
        historyLength = min(decodedPrevHistory + 1.0, specMaxHistoryLength);

        // NRD confidence: channel G = specular confidence (channel R = diffuse confidence)
        float historyConfidence = clamp(prevConfidenceVec.g, 0.0, 1.0);
        slowMaxAccumulatedFrameNum *= historyConfidence;
        fastMaxAccumulatedFrameNum *= historyConfidence;

        if (footprintQuality < 1.0) {
            historyLength *= sqrt(footprintQuality);
            historyLength = max(historyLength, 1.0);
        }

        float slowAlpha = max(1.0 / (slowMaxAccumulatedFrameNum + 1.0), 1.0 / historyLength);
        float fastAlpha = max(1.0 / (fastMaxAccumulatedFrameNum + 1.0), 1.0 / historyLength);

        slowSignal = nrd_mix_direct_history(prevSlow, currentHistory, slowAlpha);
        fastSignal = nrd_mix_direct_history(prevFast, currentHistory, fastAlpha);
    }

    vec4 responsiveSignal = fastSignal;

    spec_noisy_out          = noisySignal;
    spec_responsive_out     = responsiveSignal;
    spec_slow_out           = slowSignal;
    spec_fast_out           = fastSignal;
    spec_history_length_out = vec4(nrd_encoded_history(historyLength), 0.0, 0.0, 1.0);
}
