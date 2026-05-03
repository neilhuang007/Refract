#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 position_frag_out;
layout(location = 1) out vec4 normal_frag_out;
layout(location = 2) out vec4 mapped_normal_frag_out;
layout(location = 3) out vec4 albedo_frag_out;
layout(location = 4) out vec4 material_frag_out;
layout(location = 5) out vec4 identity_frag_out;
layout(location = 6) out vec4 direct_frag_out;
layout(location = 7) out vec4 direct_soft_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/common/light_blend_regions.glsl"
#include "/photonics/lighttree/nrd_material_id.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

// Samplers NOT already declared in lighttree/samplers.glsl -- declare only the extras here
uniform sampler2D denoised_direct_diffuse;
uniform sampler2D denoised_direct_specular;

// uniform float ph_debug_view_mode;
// Declared upstream via /photonics/lighttree/samplers.glsl included from common/header.glsl.
uniform float ph_restir_enable_denoiser_packing;

vec4 lt_extract_accumulation_material(vec2 uv) {
    vec4 spec = texture(specular, uv);
    return nrd_pack_surface_material(spec);
}

vec4 lt_load_stage_direct_lobe(sampler2D stageTexture, ivec2 pixelPosition) {
    if (ph_restir_active_checkerboard_field != 0) {
        ivec2 texSize = textureSize(stageTexture, 0);
        ivec2 ownerCoord = nrd_get_checkerboard_owner_pixel(
            pixelPosition,
            false,
            ph_restir_active_checkerboard_field,
            texSize
        );
        vec4 signal = texelFetch(stageTexture, ownerCoord, 0);
        return signal;
    }
    return texelFetch(stageTexture, pixelPosition, 0);
}

vec4 lt_load_stage_gbuffer_like(sampler2D textureSampler, ivec2 pixelPosition) {
    ivec2 sampleCoord = pixelPosition;
    if (ph_restir_active_checkerboard_field != 0) {
        sampleCoord = nrd_get_checkerboard_owner_pixel(
            pixelPosition,
            false,
            ph_restir_active_checkerboard_field,
            textureSize(textureSampler, 0)
        );
    }
    return texelFetch(textureSampler, sampleCoord, 0);
}

vec4 lt_load_current_gbuffer_like(sampler2D textureSampler, ivec2 pixelPosition) {
    return texelFetch(textureSampler, pixelPosition, 0);
}

void main() {
    if (!is_in_world()) {
        position_frag_out = vec4(0.0f);
        normal_frag_out = vec4(0.0f);
        mapped_normal_frag_out = vec4(0.0f);
        albedo_frag_out = vec4(0.0f);
        material_frag_out = vec4(0.0f);
        identity_frag_out = vec4(0.0f);
        direct_frag_out = vec4(0.0f);
        direct_soft_frag_out = vec4(0.0f);
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

    bool useDenoisedDirect = ph_restir_enable_denoiser_packing >= 0.5f;
    ivec2 shadingCoord = useDenoisedDirect ? tex_coord : ownerCoord;

    vec4 stagePosition = useDenoisedDirect
        ? lt_load_current_gbuffer_like(stage_radiosity_position, tex_coord)
        : lt_load_stage_gbuffer_like(stage_radiosity_position, tex_coord);
    vec4 stageNormal = useDenoisedDirect
        ? lt_load_current_gbuffer_like(stage_radiosity_normal, tex_coord)
        : lt_load_stage_gbuffer_like(stage_radiosity_normal, tex_coord);
    vec4 stageMappedNormal = useDenoisedDirect
        ? lt_load_current_gbuffer_like(stage_radiosity_mapped_normal, tex_coord)
        : lt_load_stage_gbuffer_like(stage_radiosity_mapped_normal, tex_coord);
    vec4 stageAlbedo = useDenoisedDirect
        ? lt_load_current_gbuffer_like(stage_radiosity_albedo, tex_coord)
        : lt_load_stage_gbuffer_like(stage_radiosity_albedo, tex_coord);

    vec2 uv = (vec2(shadingCoord) + vec2(0.5)) / vec2(viewWidth, viewHeight);
    vec4 stageMaterial = lt_extract_accumulation_material(uv);
    vec4 stageIdentity = useDenoisedDirect
        ? lt_load_current_gbuffer_like(stage_radiosity_identity, tex_coord)
        : lt_load_stage_gbuffer_like(stage_radiosity_identity, tex_coord);

    vec4 directDiffuse = lt_load_stage_direct_lobe(stage_radiosity_direct, tex_coord);
    vec4 directSpecular = lt_load_stage_direct_lobe(stage_radiosity_direct_specular, tex_coord);
    float directHitDistance = max(directDiffuse.a, directSpecular.a);

    vec3 directCombined;
    vec3 accumulatedDirect;
    if (ph_debug_view_mode > 0.5f) {
        directCombined = directDiffuse.rgb;
        accumulatedDirect = directCombined;
    } else {
        if (useDenoisedDirect) {
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
        accumulatedDirect = directCombined;
    }

    position_frag_out = stagePosition;
    normal_frag_out = stageNormal;
    mapped_normal_frag_out = stageMappedNormal;
    albedo_frag_out = stageAlbedo;
    material_frag_out = stageMaterial;
    identity_frag_out = stageIdentity;
    direct_frag_out = vec4(accumulatedDirect, directHitDistance);
    direct_soft_frag_out = vec4(directCombined, 1.0f);
}
