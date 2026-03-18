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

const float direct_max_history = 48.0;
const float direct_max_fast_history = 16.0;
const float direct_min_history = 1.0;
const float direct_depth_threshold = 0.01;
const float direct_normal_threshold = 0.85;
const float direct_motion_reset_threshold = 12.0;
const float direct_antilag_threshold_scale = 2.0;
const float direct_antilag_boost = 0.35;

bool ph_surface_positions_compatible(vec3 currentPosition, vec3 previousPosition, float thresholdSq) {
    vec3 delta = previousPosition - currentPosition;
    return dot(delta, delta) <= thresholdSq;
}

bool direct_is_valid_reprojection(
    vec2 reprojectionUv,
    vec3 currentPosition,
    vec3 currentNormal,
    vec4 currentMaterial,
    vec4 currentMotion,
    out ivec2 previousUv
) {
    previousUv = ivec2(reprojectionUv);
    ivec2 previousTextureSize = textureSize(prev_radiosity_position, 0);
    bool isInBounds = all(greaterThanEqual(previousUv, ivec2(0)))
        && all(lessThan(previousUv, previousTextureSize));
    if (!isInBounds) {
        return false;
    }

    vec3 previousNormal = nrd_safe_normal(texelFetch(prev_radiosity_normal, previousUv, 0).xyz);
    if (dot(previousNormal, currentNormal) < direct_normal_threshold) {
        return false;
    }

    vec4 previousMaterial = texelFetch(prev_radiosity_material, previousUv, 0);
    if (nrd_material_weight(currentMaterial, previousMaterial) <= 0.0) {
        return false;
    }

    vec4 previousMotion = texelFetch(prev_radiosity_motion, previousUv, 0);
    if (abs(currentMotion.z - previousMotion.z) > direct_motion_reset_threshold) {
        return false;
    }

    vec3 previousPosition = texelFetch(prev_radiosity_position, previousUv, 0).xyz;
    float planeWeight = nrd_plane_distance_weight(currentPosition, currentNormal, previousPosition, direct_depth_threshold);
    return planeWeight > 0.05 || ph_surface_positions_compatible(currentPosition, previousPosition, 0.35);
}

float direct_compute_history_limit(vec4 materialData, vec4 motionData) {
    float roughness = clamp(materialData.x, 0.0, 1.0);
    float metallic = clamp(materialData.y, 0.0, 1.0);
    float emission = clamp(materialData.z, 0.0, 1.0);
    float motionLength = clamp(motionData.z / 32.0, 0.0, 1.0);
    float specularSensitivity = mix(1.0, 0.45, metallic);
    float roughnessScale = mix(0.35, 1.0, roughness * roughness);
    float emissiveScale = mix(1.0, 0.7, emission);
    float motionScale = mix(1.0, 0.3, motionLength);
    return clamp(direct_max_history * specularSensitivity * roughnessScale * emissiveScale * motionScale, 4.0, direct_max_history);
}

float direct_compute_fast_history_limit(float historyLimit) {
    return min(historyLimit, direct_max_fast_history);
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

    vec4 currentDirect = texelFetch(stage_radiosity_direct, tex_coord, 0);
    vec4 currentMaterial = texelFetch(radiosity_material, tex_coord, 0);
    vec4 currentMotion = texelFetch(radiosity_motion, tex_coord, 0);
    vec3 currentPosition = texelFetch(stage_radiosity_position, tex_coord, 0).xyz;
    vec3 currentNormal = nrd_safe_normal(texelFetch(stage_radiosity_normal, tex_coord, 0).xyz);
    float currentConfidence = texelFetch(direct_confidence_input, tex_coord, 0).r;

    if (any(isnan(currentDirect))) {
        direct_reset_outputs();
        return;
    }

    vec2 reprojectionUv = ph_reprojectf(
        previous_modelview_projection,
        currentPosition + currentNormal * 0.01,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    );

    ivec2 previousUv = ivec2(0);
    bool temporalReset = light_reload && (ph_debug_disable_temporal_reset < 0.5);
    bool canReproject = direct_is_valid_reprojection(reprojectionUv, currentPosition, currentNormal, currentMaterial, currentMotion, previousUv);

    vec4 noisySignal = currentDirect;
    vec4 responsiveSignal = currentDirect;
    vec4 slowSignal = currentDirect;
    vec4 fastSignal = currentDirect;
    float historyLimit = direct_compute_history_limit(currentMaterial, currentMotion);
    float historyLength = 1.0;

    if (!temporalReset && canReproject) {
        vec4 previousResponsive = texelFetch(prev_direct_responsive_input, previousUv, 0);
        vec4 previousSlow = texelFetch(prev_direct_slow_input, previousUv, 0);
        vec4 previousFast = texelFetch(prev_direct_fast_input, previousUv, 0);
        vec4 previousHistory = texelFetch(prev_direct_history_length_input, previousUv, 0);
        float previousConfidence = texelFetch(prev_direct_confidence_input, previousUv, 0).r;

        float decodedPreviousHistory = nrd_decoded_history(previousHistory);
        float confidenceBlend = clamp(max(currentConfidence, previousConfidence), 0.0, 1.0);
        historyLength = min(decodedPreviousHistory + mix(0.5, 1.0, confidenceBlend), historyLimit);

        float fastHistoryLimit = direct_compute_fast_history_limit(historyLimit);
        float slowAlpha = 1.0 / max(historyLength, direct_min_history);
        float fastHistory = min(decodedPreviousHistory + 1.0, fastHistoryLimit);
        float fastAlpha = 1.0 / max(fastHistory, direct_min_history);

        vec3 currentYCoCg = nrd_rgb_to_ycocg(currentDirect.rgb);
        vec3 previousSlowYCoCg = nrd_rgb_to_ycocg(previousSlow.rgb);
        float difference = abs(currentYCoCg.x - previousSlowYCoCg.x);
        float threshold = max(nrd_luminance(currentDirect.rgb), nrd_luminance(previousSlow.rgb)) * direct_antilag_threshold_scale + 1e-4;
        float acceleration = clamp(difference / threshold, 0.0, 1.0) * direct_antilag_boost;

        responsiveSignal = mix(previousResponsive, currentDirect, slowAlpha);
        slowSignal = mix(previousSlow, currentDirect, clamp(slowAlpha + acceleration, 0.0, 1.0));
        fastSignal = mix(previousFast, currentDirect, fastAlpha);
        noisySignal = currentDirect;
    }

    direct_noisy_out = noisySignal;
    direct_responsive_out = responsiveSignal;
    direct_slow_out = slowSignal;
    direct_fast_out = fastSignal;
    direct_history_length_out = vec4(nrd_encoded_history(historyLength), 0.0, 0.0, 1.0);
}



