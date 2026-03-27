#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 position_frag_out;
layout(location = 1) out vec4 normal_frag_out;
layout(location = 2) out vec4 mapped_normal_frag_out;
layout(location = 3) out vec4 albedo_frag_out;
layout(location = 4) out vec4 material_frag_out;
layout(location = 5) out vec4 direct_frag_out;
layout(location = 6) out vec4 direct_soft_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_material_id.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

// Samplers NOT already declared in lighttree/samplers.glsl — declare only the extras here
uniform sampler2D denoised_direct_diffuse;
uniform sampler2D denoised_direct_specular;

// Debug: when enabled, light_reload is ignored and temporal history is never wiped
uniform float ph_debug_disable_temporal_reset;
uniform float ph_restir_enable_denoiser_packing;

const float lt_reproject_normal_threshold = 0.99f;
const float lt_reproject_position_threshold_sq = 0.35f;

vec4 lt_extract_accumulation_material(vec2 uv) {
    vec4 spec = texture(specular, uv);
    float smoothness = clamp(spec.r, 0.0, 1.0);
    float roughness = clamp(1.0 - smoothness, 0.0, 1.0);
    float metallic = clamp(spec.g, 0.0, 1.0);
    float emission = clamp(spec.a, 0.0, 1.0);
    return vec4(roughness, metallic, emission, nrd_encode_material_id(nrd_derive_material_id(spec)));
}

bool is_valid_reprojection(ivec2 prevUv, ivec2 textureBounds) {
    bool lightReloadActive = light_reload && (ph_debug_disable_temporal_reset < 0.5f);
    return !lightReloadActive
        && all(greaterThanEqual(prevUv, ivec2(0)))
        && all(lessThan(prevUv, textureBounds));
}

bool lt_is_valid_direct_soft_reprojection(vec2 reprojectionUv, vec3 currentPosition, vec3 currentNormal) {
    ivec2 prevUv = ivec2(reprojectionUv);
    ivec2 textureBounds = textureSize(prev_radiosity_position, 0);
    if (!is_valid_reprojection(prevUv, textureBounds)) {
        return false;
    }

    vec3 previousNormal = texelFetch(prev_radiosity_normal, prevUv, 0).xyz;
    if (dot(previousNormal, currentNormal) <= lt_reproject_normal_threshold) {
        return false;
    }

    vec3 previousPosition = texelFetch(prev_radiosity_position, prevUv, 0).xyz;
    vec3 positionDelta = previousPosition - currentPosition;
    return dot(positionDelta, positionDelta) <= lt_reproject_position_threshold_sq;
}

vec4 load_previous_direct_soft(vec3 stagePosition, vec3 stageNormal) {
    // Soft reprojection uses zero jitter (not TAA jitter) for stable pixel mapping.
    // TAA jitter changes every frame and can cause ivec2 truncation to hit adjacent
    // pixels, failing the tight validation thresholds and resetting the accumulation.
    vec2 reprojectionUv = ph_reprojectf(
        previous_modelview_projection,
        stagePosition + stageNormal * 0.01f,
        vec2(viewWidth, viewHeight),
        vec2(0.0f)
    );

    if (!lt_is_valid_direct_soft_reprojection(reprojectionUv, stagePosition, stageNormal)) {
        return vec4(0.0f);
    }

    ivec2 prevUv = ivec2(reprojectionUv);
    vec4 prevSoft = texelFetch(prev_radiosity_direct_soft, prevUv, 0);
    return (prevSoft.a > 0.0f && !any(isnan(prevSoft))) ? prevSoft : vec4(0.0f);
}

bool lt_is_active_checkerboard_pixel(ivec2 pixelPosition, int activeCheckerboardField) {
    if (activeCheckerboardField == 0) {
        return true;
    }

    return ((pixelPosition.x + pixelPosition.y) & 1) == (activeCheckerboardField & 1);
}

ivec2 lt_other_checkerboard_pixel(ivec2 pixelPosition, int activeCheckerboardField) {
    ivec2 otherFieldPixelPosition = pixelPosition;
    otherFieldPixelPosition.x += ((activeCheckerboardField == 1) == ((pixelPosition.y & 1) != 0)) ? 1 : -1;
    return otherFieldPixelPosition;
}

vec4 lt_load_stage_direct_lobe(sampler2D stageTexture, ivec2 pixelPosition, int activeCheckerboardField) {
    if (activeCheckerboardField == 0
        || lt_is_active_checkerboard_pixel(pixelPosition, activeCheckerboardField)) {
        return texelFetch(stageTexture, pixelPosition, 0);
    }

    // Reconstruct inactive checkerboard pixels before accumulation so the compatibility
    // direct/direct_soft outputs are not left as alternating sparse fields.
    return nrd_reconstruct_checkerboard_signal(
        stageTexture,
        pixelPosition,
        stage_radiosity_position,
        stage_radiosity_normal
    );
}

vec3 lt_safe_normalize(vec3 value, vec3 fallbackValue) {
    float valueLengthSq = dot(value, value);
    if (valueLengthSq > 1e-6f) {
        return value * inversesqrt(valueLengthSq);
    }

    float fallbackLengthSq = dot(fallbackValue, fallbackValue);
    if (fallbackLengthSq > 1e-6f) {
        return fallbackValue * inversesqrt(fallbackLengthSq);
    }

    return vec3(0.0f, 1.0f, 0.0f);
}

vec3 lt_unpack_stage_direct_radiance(vec4 encodedSignal, vec3 remodulationFactor) {
    if (ph_restir_enable_denoiser_packing < 0.5f) {
        return encodedSignal.rgb;
    }

    return nrd_safe_remodulate(nrd_unpack_direct_signal(encodedSignal).radiance, remodulationFactor);
}

void main() {
    if (!is_in_world()) {
        position_frag_out = vec4(0.0f);
        normal_frag_out = vec4(0.0f);
        mapped_normal_frag_out = vec4(0.0f);
        albedo_frag_out = vec4(0.0f);
        material_frag_out = vec4(0.0f);
        direct_frag_out = vec4(0.0f);
        direct_soft_frag_out = vec4(0.0f);
        return;
    }

    vec4 stagePosition = texelFetch(stage_radiosity_position, tex_coord, 0);
    vec4 stageNormal = texelFetch(stage_radiosity_normal, tex_coord, 0);
    vec4 stageMappedNormal = texelFetch(stage_radiosity_mapped_normal, tex_coord, 0);
    vec4 stageAlbedo = texelFetch(stage_radiosity_albedo, tex_coord, 0);
    vec2 uv = (vec2(tex_coord) + vec2(0.5)) / vec2(viewWidth, viewHeight);
    vec4 stageMaterial = lt_extract_accumulation_material(uv);
    int activeCheckerboardField = int(ph_restir_active_checkerboard_field);
    vec4 directDiffuse = lt_load_stage_direct_lobe(stage_radiosity_direct, tex_coord, activeCheckerboardField);
    vec4 directSpecular = lt_load_stage_direct_lobe(stage_radiosity_direct_specular, tex_coord, activeCheckerboardField);
    vec4 prevSoft = load_previous_direct_soft(stagePosition.xyz, stageNormal.xyz);
    float directHitDistance = max(directDiffuse.a, directSpecular.a);
    // The compat soft path uses the denoised diffuse from the A-trous filter for stability.
    // Raw per-frame specular is too noisy for the running average and causes visible jitter.
    // When denoiser is off, use the raw combined signal as before.
    vec3 directCombined;
    if (ph_restir_enable_denoiser_packing >= 0.5f) {
        directCombined = texelFetch(denoised_direct_diffuse, tex_coord, 0).rgb;
    } else {
        directCombined = directDiffuse.rgb + directSpecular.rgb;
    }

    position_frag_out = stagePosition;
    normal_frag_out = stageNormal;
    mapped_normal_frag_out = stageMappedNormal;
    albedo_frag_out = stageAlbedo;
    material_frag_out = stageMaterial;
    direct_frag_out = vec4(directCombined, directHitDistance);
    direct_soft_frag_out = vec4(prevSoft.rgb + directCombined, prevSoft.a + 1.0f);
}
