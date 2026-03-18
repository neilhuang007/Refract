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

uniform sampler2D prev_direct_responsive_input;
uniform sampler2D prev_direct_slow_input;
uniform sampler2D prev_direct_fast_input;

const float direct_max_accumulated_frame_num = 30.0;
const float direct_max_fast_accumulated_frame_num = 6.0;
const float direct_max_history_length = direct_max_accumulated_frame_num + 1.0;
const float direct_depth_threshold = 0.01;
const float direct_normal_threshold = 0.9;

// ReBLUR (Zhdan, Ray Tracing Gems II, Listing 49-3):
// Parallax = tan(acos(dot(V, Vprev))), measures angular change in viewing direction.
// Zero for pure camera rotation (diffuse lighting unchanged), increases with camera
// translation relative to surface distance.
float direct_compute_parallax(vec3 currentPosition, vec3 cameraDelta) {
    vec3 toSurface = currentPosition - world_camera_position;
    float distSq = dot(toSurface, toSurface);
    if (distSq < 1e-6) return 0.0;

    vec3 V = toSurface * inversesqrt(distSq);
    vec3 Vprev = normalize(toSurface + cameraDelta);
    float cosa = clamp(dot(V, Vprev), 0.0, 1.0);
    return sqrt(1.0 - cosa * cosa) / max(cosa, 1e-6);
}

bool ph_surface_positions_compatible(vec3 currentPosition, vec3 previousPosition, float thresholdSq) {
    vec3 delta = previousPosition - currentPosition;
    return dot(delta, delta) <= thresholdSq;
}

// NRD RELAX per-tap disocclusion check.
// Returns 1.0 if the tap is valid for reprojection, 0.0 otherwise.
float direct_check_tap(ivec2 tapCoord, ivec2 texSize,
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

    // --- Setup: fetch current frame data ---
    NrdDirectSignal currentDirect = nrd_unpack_direct_signal(texelFetch(stage_radiosity_direct, tex_coord, 0));
    vec4 currentMaterial = texelFetch(stage_radiosity_material, tex_coord, 0);
    vec3 currentPosition = texelFetch(stage_radiosity_position, tex_coord, 0).xyz;
    vec3 currentGeometryNormal = texelFetch(stage_radiosity_normal, tex_coord, 0).xyz;
    vec3 currentNormal = nrd_select_surface_normal(
        currentGeometryNormal,
        texelFetch(stage_radiosity_mapped_normal, tex_coord, 0).xyz
    );
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
    float parallax = direct_compute_parallax(currentPosition, cameraDelta);

    // --- Reprojection UV (keep as float; do NOT truncate yet) ---
    vec2 reprojectionUv = ph_reprojectf(
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
    // NRD: 1/lerp(lerp(0.05, 1.0, NoV), 1.0, saturate(pixelParallax/30.0))
    // Approximate pixel parallax from angular: saturate(parallax * 10.0)
    float NoVfactor = mix(max(NoV, 0.05), 1.0, clamp(parallax * 10.0, 0.0, 1.0));
    float disocclusionScale = 1.0 / max(NoVfactor, 0.05);
    float disocclusionThreshold = direct_depth_threshold * viewDistance * disocclusionScale;

    // --- Standard bilinear weights ---
    float fx = bilinearWeights.x;
    float fy = bilinearWeights.y;
    vec4 standardWeights = vec4(
        (1.0 - fx) * (1.0 - fy),
        fx         * (1.0 - fy),
        (1.0 - fx) * fy,
        fx         * fy
    );

    // --- Per-tap validity (NRD RELAX bilinear disocclusion check) ---
    ivec2 tap00 = bilinearOrigin;
    ivec2 tap10 = bilinearOrigin + ivec2(1, 0);
    ivec2 tap01 = bilinearOrigin + ivec2(0, 1);
    ivec2 tap11 = bilinearOrigin + ivec2(1, 1);

    vec4 tapValid;
    tapValid.x = direct_check_tap(tap00, texSize, currentPosition, currentNormal, currentMaterial, disocclusionThreshold);
    tapValid.y = direct_check_tap(tap10, texSize, currentPosition, currentNormal, currentMaterial, disocclusionThreshold);
    tapValid.z = direct_check_tap(tap01, texSize, currentPosition, currentNormal, currentMaterial, disocclusionThreshold);
    tapValid.w = direct_check_tap(tap11, texSize, currentPosition, currentNormal, currentMaterial, disocclusionThreshold);

    // --- Global backface rejection (NRD RELAX lines 140-150) ---
    // Average previous normals from valid taps; if averaged normal backfaces current, reject all.
    vec3 prevNormalAvg = vec3(0.0);
    float normalWSum = 0.0;

    if (tapValid.x > 0.0) {
        prevNormalAvg += nrd_select_surface_normal(
            texelFetch(prev_radiosity_normal, tap00, 0).xyz,
            texelFetch(prev_radiosity_mapped_normal, tap00, 0).xyz
        ) * standardWeights.x;
        normalWSum += standardWeights.x;
    }
    if (tapValid.y > 0.0) {
        prevNormalAvg += nrd_select_surface_normal(
            texelFetch(prev_radiosity_normal, tap10, 0).xyz,
            texelFetch(prev_radiosity_mapped_normal, tap10, 0).xyz
        ) * standardWeights.y;
        normalWSum += standardWeights.y;
    }
    if (tapValid.z > 0.0) {
        prevNormalAvg += nrd_select_surface_normal(
            texelFetch(prev_radiosity_normal, tap01, 0).xyz,
            texelFetch(prev_radiosity_mapped_normal, tap01, 0).xyz
        ) * standardWeights.z;
        normalWSum += standardWeights.z;
    }
    if (tapValid.w > 0.0) {
        prevNormalAvg += nrd_select_surface_normal(
            texelFetch(prev_radiosity_normal, tap11, 0).xyz,
            texelFetch(prev_radiosity_mapped_normal, tap11, 0).xyz
        ) * standardWeights.w;
        normalWSum += standardWeights.w;
    }

    if (normalWSum > 0.0) {
        prevNormalAvg /= normalWSum;
        if (dot(currentNormal, prevNormalAvg) < 0.0) {
            tapValid = vec4(0.0);
        }
    }

    // --- Custom bilinear weights accounting for per-tap validity ---
    vec4 customWeights = standardWeights * tapValid;
    float sumCustom = dot(customWeights, vec4(1.0));
    bool canReproject = sumCustom > 1e-4;
    float footprintQuality = canReproject ? sumCustom : 0.0;
    if (canReproject) customWeights /= sumCustom;

    // --- NRD RELAX footprint stretching detection (lines 557-563) ---
    // Penalizes reprojection when the previous viewpoint was nearly grazing vs current.
    vec3 Vprev = normalize(currentPosition - previous_world_camera_position);
    float NoVprev = abs(dot(currentNormal, Vprev));
    float sizeQuality = (NoVprev + 1e-3) / (NoV + 1e-3);
    sizeQuality *= sizeQuality;
    sizeQuality *= sizeQuality;
    footprintQuality *= mix(0.1, 1.0, clamp(sizeQuality, 0.0, 1.0));

    // --- Temporal accumulation ---
    bool temporalReset = light_reload && (ph_debug_disable_temporal_reset < 0.5);

    vec4 noisySignal = nrd_pack_direct_history(currentHistory.radiance, currentHistory.secondMoment);
    vec4 slowSignal = noisySignal;
    vec4 fastSignal = noisySignal;

    float historyLength = 1.0;

    if (!temporalReset && canReproject) {
        // Weighted bilinear fetch of history buffers across 4 taps.
        vec4 prevSlow = vec4(0.0);
        vec4 prevFast = vec4(0.0);
        vec4 prevHistoryVec = vec4(0.0);

        if (customWeights.x > 0.0) {
            prevSlow       += texelFetch(prev_direct_slow_input,          tap00, 0) * customWeights.x;
            prevFast       += texelFetch(prev_direct_fast_input,          tap00, 0) * customWeights.x;
            prevHistoryVec += texelFetch(prev_direct_history_length_input, tap00, 0) * customWeights.x;
        }
        if (customWeights.y > 0.0) {
            prevSlow       += texelFetch(prev_direct_slow_input,          tap10, 0) * customWeights.y;
            prevFast       += texelFetch(prev_direct_fast_input,          tap10, 0) * customWeights.y;
            prevHistoryVec += texelFetch(prev_direct_history_length_input, tap10, 0) * customWeights.y;
        }
        if (customWeights.z > 0.0) {
            prevSlow       += texelFetch(prev_direct_slow_input,          tap01, 0) * customWeights.z;
            prevFast       += texelFetch(prev_direct_fast_input,          tap01, 0) * customWeights.z;
            prevHistoryVec += texelFetch(prev_direct_history_length_input, tap01, 0) * customWeights.z;
        }
        if (customWeights.w > 0.0) {
            prevSlow       += texelFetch(prev_direct_slow_input,          tap11, 0) * customWeights.w;
            prevFast       += texelFetch(prev_direct_fast_input,          tap11, 0) * customWeights.w;
            prevHistoryVec += texelFetch(prev_direct_history_length_input, tap11, 0) * customWeights.w;
        }

        float decodedPrevHistory = nrd_decoded_history(prevHistoryVec);
        historyLength = min(decodedPrevHistory + 1.0, direct_max_history_length);

        // NRD RELAX footprint quality shortening (lines 567-572):
        // Partial footprints accumulate less history to prevent ghosting.
        if (footprintQuality < 1.0) {
            historyLength *= sqrt(footprintQuality);
            historyLength = max(historyLength, 1.0);
        }

        float slowAlpha = max(1.0 / (direct_max_accumulated_frame_num + 1.0), 1.0 / historyLength);
        float fastAlpha = max(1.0 / (direct_max_fast_accumulated_frame_num + 1.0), 1.0 / historyLength);

        slowSignal = nrd_mix_direct_history(prevSlow, currentHistory, slowAlpha);
        fastSignal = nrd_mix_direct_history(prevFast, currentHistory, fastAlpha);
    }

    // Responsive is identical to slow (NRD RELAX: no separate responsive path for direct).
    // This replaces the dead-code self-feedback from the previous implementation.
    vec4 responsiveSignal = slowSignal;

    direct_noisy_out          = noisySignal;
    direct_responsive_out     = responsiveSignal;
    direct_slow_out           = slowSignal;
    direct_fast_out           = fastSignal;
    direct_history_length_out = vec4(nrd_encoded_history(historyLength), 0.0, 0.0, 1.0);
}
