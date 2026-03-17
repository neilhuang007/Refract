#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_diff_slow_out;
layout(location = 1) out vec4 nrd_diff_fast_out;
layout(location = 2) out vec4 nrd_history_length_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D stage_radiosity_position;
uniform sampler2D stage_radiosity_normal;

uniform sampler2D prev_nrd_diff_slow;
uniform sampler2D prev_nrd_diff_fast;
uniform sampler2D prev_nrd_history_length;

// Debug: when enabled, light_reload is ignored and temporal history is never wiped
uniform float ph_debug_disable_temporal_reset;

const float nrd_diff_max_accumulated_frames = 30.0f;
const float nrd_diff_max_fast_accumulated_frames = 6.0f;
const float nrd_disocclusion_threshold = 0.01f;
const float nrd_normal_threshold = 0.9f;
const float nrd_position_compatibility_threshold_sq = 0.35f;
const float nrd_history_length_scale = 255.0f;

float nrd_decode_history_length(vec4 encodedHistory) {
    return clamp(encodedHistory.r * nrd_history_length_scale, 0.0f, nrd_history_length_scale);
}

vec4 nrd_encode_history_length(float historyLength) {
    float encodedHistory = clamp(historyLength / nrd_history_length_scale, 0.0f, 1.0f);
    return vec4(encodedHistory, 0.0f, 0.0f, 1.0f);
}

bool nrd_is_valid_reprojection(
    vec2 reprojectionUv,
    vec3 currentPosition,
    vec3 currentNormal,
    out ivec2 previousUv
) {
    previousUv = ivec2(reprojectionUv);

    ivec2 previousTextureSize = textureSize(prev_radiosity_position, 0);
    bool isInBounds = all(greaterThanEqual(previousUv, ivec2(0)))
        && all(lessThan(previousUv, previousTextureSize));
    if (!isInBounds) {
        return false;
    }

    vec3 previousNormal = texelFetch(prev_radiosity_normal, previousUv, 0).xyz;
    if (dot(previousNormal, currentNormal) < nrd_normal_threshold) {
        return false;
    }

    vec3 previousPosition = texelFetch(prev_radiosity_position, previousUv, 0).xyz;
    float currentViewZ = length(currentPosition - world_camera_position);
    float planeDistanceWeight = nrd_get_plane_distance_weight(
        currentPosition,
        currentNormal,
        currentViewZ,
        previousPosition,
        nrd_disocclusion_threshold
    );

    if (planeDistanceWeight > 0.0f) {
        return true;
    }

    return ph_surface_positions_compatible(
        currentPosition,
        previousPosition,
        nrd_position_compatibility_threshold_sq
    );
}

void nrd_reset_history(vec3 currentNoisy) {
    float currentLuminance = nrd_luminance(currentNoisy);
    float secondMoment = currentLuminance * currentLuminance;

    nrd_diff_slow_out = vec4(currentNoisy, secondMoment);
    nrd_diff_fast_out = vec4(currentNoisy, 1.0f);
    nrd_history_length_out = nrd_encode_history_length(1.0f);
}

void main() {
    if (!is_in_world()) {
        nrd_diff_slow_out = vec4(0.0f);
        nrd_diff_fast_out = vec4(0.0f);
        nrd_history_length_out = vec4(0.0f);
        return;
    }

    vec4 currentDirect = texelFetch(stage_radiosity_direct, tex_coord, 0);
    vec3 currentPosition = texelFetch(stage_radiosity_position, tex_coord, 0).xyz;
    vec3 currentNormal = normalize(texelFetch(stage_radiosity_normal, tex_coord, 0).xyz);

    if (currentDirect.a <= 0.0f || any(isnan(currentDirect)) || any(isnan(currentPosition)) || any(isnan(currentNormal))) {
        nrd_diff_slow_out = vec4(0.0f);
        nrd_diff_fast_out = vec4(0.0f);
        nrd_history_length_out = vec4(0.0f);
        return;
    }

    vec2 reprojectionUv = ph_reprojectf(
        previous_modelview_projection,
        currentPosition + currentNormal * 0.01f,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    );

    ivec2 previousUv = ivec2(0);
    bool lightReloadActive = light_reload && (ph_debug_disable_temporal_reset < 0.5f);
    bool canReuseHistory = !lightReloadActive
        && nrd_is_valid_reprojection(reprojectionUv, currentPosition, currentNormal, previousUv);

    if (!canReuseHistory) {
        nrd_reset_history(currentDirect.rgb);
        return;
    }

    vec4 previousSlow = texelFetch(prev_nrd_diff_slow, previousUv, 0);
    vec4 previousFast = texelFetch(prev_nrd_diff_fast, previousUv, 0);
    float previousHistoryLength = nrd_decode_history_length(texelFetch(prev_nrd_history_length, previousUv, 0));

    bool hasValidHistory = previousHistoryLength > 0.0f
        && !any(isnan(previousSlow))
        && !any(isnan(previousFast));
    if (!hasValidHistory) {
        nrd_reset_history(currentDirect.rgb);
        return;
    }

    float historyLength = min(previousHistoryLength + 1.0f, nrd_history_length_scale);
    float slowAlpha = 1.0f / min(historyLength, nrd_diff_max_accumulated_frames);
    float fastAlpha = 1.0f / min(historyLength, nrd_diff_max_fast_accumulated_frames);

    vec3 slowResult = mix(previousSlow.rgb, currentDirect.rgb, slowAlpha);
    vec3 fastResult = mix(previousFast.rgb, currentDirect.rgb, fastAlpha);
    float currentLuminance = nrd_luminance(currentDirect.rgb);
    float secondMoment = mix(previousSlow.a, currentLuminance * currentLuminance, slowAlpha);

    nrd_diff_slow_out = vec4(slowResult, secondMoment);
    nrd_diff_fast_out = vec4(fastResult, 1.0f);
    nrd_history_length_out = nrd_encode_history_length(historyLength);
}
