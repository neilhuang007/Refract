#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_frag_out;
layout(location = 1) out vec4 direct_variance_frag_out;
layout(location = 2) out vec4 handheld_frag_out;
layout(location = 3) out vec4 indirect_frag_out;
layout(location = 4) out vec4 indirect_variance_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/common/light_blend_regions.glsl"
#include "/photonics/lighttree/nrd_common.glsl"


// Debug: when enabled, light_reload is ignored and temporal history is never wiped
uniform float ph_debug_disable_temporal_reset;

const float lt_reproject_normal_threshold = 0.99f;
const float lt_reproject_position_threshold_sq = 0.35f;
const float lt_min_alpha = 0.05f;
const float lt_max_history = 48.0f;
const vec3 lt_luma_coeff = vec3(0.2126f, 0.7152f, 0.0722f);

float lt_luminance(vec3 color) {
    return dot(color, lt_luma_coeff);
}

bool lt_is_valid_history(vec4 historySample) {
    return historySample.a > 0.0f && !any(isnan(historySample));
}

bool lt_is_valid_reprojection(vec2 reprojectionUv, vec3 currentPosition, vec3 currentNormal) {
    ivec2 previousUv = ivec2(round(reprojectionUv));
    ivec2 textureSizeValue = textureSize(prev_radiosity_position, 0);
    if (any(lessThan(previousUv, ivec2(0))) || any(greaterThanEqual(previousUv, textureSizeValue))) {
        return false;
    }

    vec3 previousNormal = texelFetch(prev_radiosity_normal, previousUv, 0).xyz;
    if (dot(previousNormal, currentNormal) <= lt_reproject_normal_threshold) {
        return false;
    }

    vec3 previousPosition = texelFetch(prev_radiosity_position, previousUv, 0).xyz;
    return ph_surface_positions_compatible(currentPosition, previousPosition, lt_reproject_position_threshold_sq);
}

vec2 lt_compute_moments(vec3 color) {
    float luma = lt_luminance(color);
    return vec2(luma, luma * luma);
}

vec3 lt_unpack_direct_radiance(
    vec4 diffuseSample,
    vec4 specularSample,
    vec3 albedo,
    vec4 material
) {
    vec3 diffuseDemodulated = nrd_unpack_direct_signal(diffuseSample).radiance;
    vec3 specularDemodulated = nrd_unpack_direct_signal(specularSample).radiance;
    vec3 diffuseRadiance = nrd_safe_remodulate(
        diffuseDemodulated,
        max(albedo, vec3(NRD_MATERIAL_FACTOR_MIN_SCALE))
    );
    vec3 specularRadiance = nrd_safe_remodulate(
        specularDemodulated,
        nrd_compute_specular_demodulation(albedo, material.g)
    );
    return diffuseRadiance + specularRadiance;
}

vec4 lt_encode_variance(vec2 moments, float history) {
    float variance = max(moments.y - moments.x * moments.x, 0.0f);
    float confidence = clamp((history - 1.0f) / max(lt_max_history - 1.0f, 1.0f), 0.0f, 1.0f);
    return vec4(moments.x, moments.y, variance, confidence);
}

vec4 lt_load_stage_direct_signal(sampler2D stageTexture, ivec2 pixelPosition) {
    if (ph_restir_active_checkerboard_field != 0) {
        ivec2 ownerCoord = nrd_get_checkerboard_owner_pixel(
            pixelPosition,
            false,
            ph_restir_active_checkerboard_field,
            textureSize(stageTexture, 0)
        );
        return texelFetch(stageTexture, ownerCoord, 0);
    }
    return texelFetch(stageTexture, pixelPosition, 0);
}

vec4 lt_load_stage_gbuffer_like(sampler2D stageTexture, ivec2 pixelPosition) {
    if (ph_restir_active_checkerboard_field != 0) {
        ivec2 ownerCoord = nrd_get_checkerboard_owner_pixel(
            pixelPosition,
            false,
            ph_restir_active_checkerboard_field,
            textureSize(stageTexture, 0)
        );
        return texelFetch(stageTexture, ownerCoord, 0);
    }
    return texelFetch(stageTexture, pixelPosition, 0);
}

void lt_accumulate_direct(
    vec4 currentDiffuseSample,
    vec4 currentSpecularSample,
    vec3 currentAlbedo,
    vec4 currentMaterial,
    vec3 currentPosition,
    vec3 currentNormal,
    out vec4 accumulatedSignal,
    out vec4 accumulatedVariance
) {
    vec3 currentDirect = lt_unpack_direct_radiance(
        currentDiffuseSample,
        currentSpecularSample,
        currentAlbedo,
        currentMaterial
    );
    float currentDirectLuma = lt_luminance(currentDirect);
    if (currentDirectLuma <= 0.0f || any(isnan(currentDiffuseSample)) || any(isnan(currentSpecularSample))) {
        accumulatedSignal = vec4(0.0f);
        accumulatedVariance = vec4(0.0f);
        return;
    }

    // Match the stable accumulation path: frame-varying TAA jitter shifts
    // integer reprojection targets between neighboring pixels and injects
    // temporal churn even when geometry and lighting are unchanged.
    vec2 reprojectionUv = ph_reprojectf(
        previous_modelview_projection,
        currentPosition + currentNormal * 0.01f,
        vec2(viewWidth, viewHeight),
        vec2(0.0f)
    );

    float localLightBlend = ph_dirty_region_factor(currentPosition);
    bool lightReloadActive = (light_reload && (ph_debug_disable_temporal_reset < 0.5f))
        || localLightBlend > 0.0f;
    bool canReproject = lt_is_valid_reprojection(reprojectionUv, currentPosition, currentNormal);
    if (lightReloadActive || !canReproject) {
        vec2 currentMoments = lt_compute_moments(currentDirect);
        accumulatedSignal = vec4(currentDirect, 1.0f);
        accumulatedVariance = lt_encode_variance(currentMoments, 1.0f);
        return;
    }

    ivec2 previousUv = ivec2(round(reprojectionUv));
    vec4 previousSignal = texelFetch(prev_radiosity_lighting, previousUv, 0);
    vec4 previousVariance = texelFetch(prev_radiosity_lighting_variance, previousUv, 0);
    if (!lt_is_valid_history(previousSignal)) {
        vec2 currentMoments = lt_compute_moments(currentDirect);
        accumulatedSignal = vec4(currentDirect, 1.0f);
        accumulatedVariance = lt_encode_variance(currentMoments, 1.0f);
        return;
    }

    float history = min(previousSignal.a + 1.0f, lt_max_history);
    float alpha = max(1.0f / history, lt_min_alpha);

    vec3 blendedColor = mix(previousSignal.rgb, currentDirect, alpha);
    vec2 blendedMoments = mix(previousVariance.xy, lt_compute_moments(currentDirect), alpha);

    accumulatedSignal = vec4(blendedColor, history);
    accumulatedVariance = lt_encode_variance(blendedMoments, history);
}

void lt_accumulate_indirect(
    vec4 currentSample,
    vec3 currentPosition,
    vec3 currentNormal,
    out vec4 accumulatedSignal,
    out vec4 accumulatedVariance
) {
    if (currentSample.a <= 0.0f || any(isnan(currentSample))) {
        accumulatedSignal = vec4(0.0f);
        accumulatedVariance = vec4(0.0f);
        return;
    }

    // Keep indirect history addressing aligned with the direct/NRD paths.
    // TAA jitter moves the previous-frame texel lookup between neighbors and
    // destabilizes temporal reuse without representing a semantic scene change.
    vec2 reprojectionUv = ph_reprojectf(
        previous_modelview_projection,
        currentPosition + currentNormal * 0.01f,
        vec2(viewWidth, viewHeight),
        vec2(0.0f)
    );

    float localLightBlend = ph_dirty_region_factor(currentPosition);
    bool lightReloadActive = (light_reload && (ph_debug_disable_temporal_reset < 0.5f))
        || localLightBlend > 0.0f;
    bool canReproject = lt_is_valid_reprojection(reprojectionUv, currentPosition, currentNormal);
    if (lightReloadActive || !canReproject) {
        vec2 currentMoments = lt_compute_moments(currentSample.rgb);
        accumulatedSignal = vec4(currentSample.rgb, 1.0f);
        accumulatedVariance = lt_encode_variance(currentMoments, 1.0f);
        return;
    }

    ivec2 previousUv = ivec2(round(reprojectionUv));
    vec4 previousSignal = texelFetch(prev_radiosity_indirect, previousUv, 0);
    vec4 previousVariance = texelFetch(prev_radiosity_indirect_variance, previousUv, 0);
    if (!lt_is_valid_history(previousSignal)) {
        vec2 currentMoments = lt_compute_moments(currentSample.rgb);
        accumulatedSignal = vec4(currentSample.rgb, 1.0f);
        accumulatedVariance = lt_encode_variance(currentMoments, 1.0f);
        return;
    }

    float history = min(previousSignal.a + 1.0f, lt_max_history);
    float alpha = max(1.0f / history, lt_min_alpha);
    vec3 blendedColor = mix(previousSignal.rgb, currentSample.rgb, alpha);
    vec2 blendedMoments = mix(previousVariance.xy, lt_compute_moments(currentSample.rgb), alpha);

    accumulatedSignal = vec4(blendedColor, history);
    accumulatedVariance = lt_encode_variance(blendedMoments, history);
}

void main() {
    if (!is_in_world()) {
        direct_frag_out = vec4(0.0f);
        direct_variance_frag_out = vec4(0.0f);
        handheld_frag_out = vec4(0.0f);
        indirect_frag_out = vec4(0.0f);
        indirect_variance_frag_out = vec4(0.0f);
        return;
    }

    vec4 currentPosition = lt_load_stage_gbuffer_like(stage_radiosity_position, tex_coord);
    vec4 currentNormal = lt_load_stage_gbuffer_like(stage_radiosity_normal, tex_coord);
    vec4 currentAlbedo = lt_load_stage_gbuffer_like(stage_radiosity_albedo, tex_coord);
    vec4 currentMaterial = lt_load_stage_gbuffer_like(stage_radiosity_material, tex_coord);
    vec4 currentDirect = lt_load_stage_direct_signal(stage_radiosity_direct, tex_coord);
    vec4 currentDirectSpecular = lt_load_stage_direct_signal(stage_radiosity_direct_specular, tex_coord);
    vec4 currentHandheld = lt_load_stage_direct_signal(stage_radiosity_handheld, tex_coord);
    vec4 currentIndirect = texelFetch(stage_radiosity_indirect, tex_coord, 0);

    handheld_frag_out = currentHandheld;

    lt_accumulate_direct(
        currentDirect,
        currentDirectSpecular,
        currentAlbedo.rgb,
        currentMaterial,
        currentPosition.xyz,
        currentNormal.xyz,
        direct_frag_out,
        direct_variance_frag_out
    );

    lt_accumulate_indirect(
        currentIndirect,
        currentPosition.xyz,
        currentNormal.xyz,
        indirect_frag_out,
        indirect_variance_frag_out
    );
}
