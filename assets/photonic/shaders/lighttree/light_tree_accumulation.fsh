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
#include "/photonics/common/light_blend_regions.glsl"
#include "/photonics/lighttree/nrd_material_id.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

// Samplers NOT already declared in lighttree/samplers.glsl — declare only the extras here
uniform sampler2D denoised_direct_diffuse;
uniform sampler2D denoised_direct_specular;

// Debug: when enabled, light_reload is ignored and temporal history is never wiped
uniform float ph_debug_disable_temporal_reset;
// uniform float ph_debug_view_mode;
// Declared upstream via /photonics/lighttree/samplers.glsl included from common/header.glsl.
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
    if (ph_dirty_region_factor(stagePosition) > 0.0f) {
        return vec4(0.0f);
    }

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

vec4 lt_load_stage_direct_lobe(sampler2D stageTexture, ivec2 pixelPosition) {
    if (ph_restir_active_checkerboard_field != 0) {
        return nrd_reconstruct_checkerboard_signal(
            stageTexture,
            pixelPosition,
            stage_radiosity_position,
            stage_radiosity_normal
        );
    }
    return texelFetch(stageTexture, pixelPosition, 0);
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
    vec4 directDiffuse = lt_load_stage_direct_lobe(stage_radiosity_direct, tex_coord);
    vec4 directSpecular = lt_load_stage_direct_lobe(stage_radiosity_direct_specular, tex_coord);
    float directHitDistance = max(directDiffuse.a, directSpecular.a);

    vec3 directCombined;
    vec4 prevSoft = vec4(0.0f);
    if (ph_debug_view_mode > 0.5f) {
        directCombined = directDiffuse.rgb;
        prevSoft = vec4(directCombined, 0.0f);
    } else {
        prevSoft = load_previous_direct_soft(stagePosition.xyz, stageNormal.xyz);
        if (ph_restir_enable_denoiser_packing >= 0.5f) {
            vec3 denoisedDiffuseDemodulated = texelFetch(denoised_direct_diffuse, tex_coord, 0).rgb;
            vec3 denoisedSpecularDemodulated = texelFetch(denoised_direct_specular, tex_coord, 0).rgb;
            vec3 diffuseRemodulation = max(stageAlbedo.rgb, vec3(0.02f));
            vec3 specularRemodulation = nrd_compute_specular_demodulation(stageAlbedo.rgb, stageMaterial.g);
            vec3 denoisedDiffuse = nrd_safe_remodulate(denoisedDiffuseDemodulated, diffuseRemodulation);
            vec3 denoisedSpecular = nrd_safe_remodulate(denoisedSpecularDemodulated, specularRemodulation);
            directCombined = denoisedDiffuse + denoisedSpecular;
        } else {
            directCombined = directDiffuse.rgb + directSpecular.rgb;
        }
    }

    position_frag_out = stagePosition;
    normal_frag_out = stageNormal;
    mapped_normal_frag_out = stageMappedNormal;
    albedo_frag_out = stageAlbedo;
    material_frag_out = stageMaterial;
    direct_frag_out = vec4(directCombined, directHitDistance);
    direct_soft_frag_out = vec4(prevSoft.rgb + directCombined, prevSoft.a + 1.0f);
}
