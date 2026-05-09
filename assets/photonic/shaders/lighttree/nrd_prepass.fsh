#version 430

// RELAX pre-pass adapted to the fragment pipeline.
// It reads the raw demodulated direct diffuse/specular signals and writes the
// noisy inputs consumed by temporal accumulation.

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_diff_prepass_out;
layout(location = 1) out vec4 nrd_spec_prepass_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

float ph_pixel_radius_to_world(float pixelRadius, float viewZ) {
    float minDim = min(viewWidth, viewHeight);
    return pixelRadius * (viewZ / max(minDim, 1.0));
}

void main() {
    ivec2 pixelPos = tex_coord;
    float isSky = texelFetch(nrd_in_tiles, pixelPos >> 4, 0).r;

    if (isSky > 0.5) {
        nrd_diff_prepass_out = vec4(0.0);
        nrd_spec_prepass_out = vec4(0.0);
        return;
    }

    vec3 centerWorldPos = texelFetch(radiosity_position, pixelPos, 0).xyz;
    float centerViewZ = nrd_compute_view_z(centerWorldPos);
    if (centerViewZ >= ph_nrd_denoising_range) {
        nrd_diff_prepass_out = vec4(0.0);
        nrd_spec_prepass_out = vec4(0.0);
        return;
    }

    vec3 centerNormal = nrd_safe_normal(texelFetch(radiosity_normal, pixelPos, 0).xyz);
    vec4 centerMaterial = texelFetch(radiosity_material, pixelPos, 0);
    float centerRoughness = clamp(centerMaterial.x, 0.0, 1.0);

    vec4 rotator = nrd_get_kernel_rotation(frameCounter);
    ivec2 texSize = textureSize(nrd_in_diff_radiance_hitdist, 0);
    ivec2 diffCenter = nrd_get_current_checkerboard_owner_pixel(pixelPos, texSize);
    ivec2 specCenter = nrd_get_current_checkerboard_owner_pixel(pixelPos, texSize);

    vec4 diffuseIllumination = texelFetch(nrd_in_diff_radiance_hitdist, diffCenter, 0);
    vec4 specularIllumination = texelFetch(nrd_in_spec_radiance_hitdist, specCenter, 0);
    diffuseIllumination = clamp(diffuseIllumination, vec4(0.0), vec4(NRD_FP16_MAX));
    specularIllumination = clamp(specularIllumination, vec4(0.0), vec4(NRD_FP16_MAX));
    specularIllumination.a = min(ph_nrd_denoising_range, specularIllumination.a);

    if (ph_nrd_diff_prepass_blur_radius > 0.0) {
        float frustumSize = ph_pixel_radius_to_world(min(viewWidth, viewHeight), centerViewZ);
        float hitDistForRadius = (diffuseIllumination.a == 0.0) ? 1.0 : diffuseIllumination.a;
        float hitDistFactor = clamp(hitDistForRadius / max(frustumSize, 1e-6), 0.0, 1.0);
        float blurRadius = ph_nrd_diff_prepass_blur_radius * hitDistFactor;
        if (diffuseIllumination.a == 0.0) {
            blurRadius = max(blurRadius, 1.0);
        }

        float normalWeightParam = nrd_normal_weight_param(1.0, 0.25 * ph_nrd_lobe_angle_fraction);
        vec2 hitDistWeightParams = nrd_hit_distance_weight_params(diffuseIllumination.a, 1.0 / 9.0);
        float weightSum = 1.0;

        for (int i = 0; i < 8; i++) {
            vec3 offset = nrd_poisson8[i];
            vec2 rotatedOffset = nrd_rotate_vector(rotator, offset.xy);
            vec2 samplePixel = vec2(pixelPos) + 0.5 + rotatedOffset * blurRadius;
            samplePixel = floor(samplePixel) + 0.5;

            vec2 sampleUv = samplePixel / vec2(viewWidth, viewHeight);
            ivec2 sampleCoord = clamp(ivec2(samplePixel), ivec2(0), texSize - ivec2(1));

            vec3 sampleNormal = nrd_safe_normal(texelFetch(radiosity_normal, sampleCoord, 0).xyz);
            vec3 sampleWorldPos = texelFetch(radiosity_position, sampleCoord, 0).xyz;
            float sampleViewZ = nrd_compute_view_z(sampleWorldPos);

            float sampleWeight = nrd_is_in_screen_nearest(sampleUv);
            sampleWeight *= (sampleViewZ < ph_nrd_denoising_range) ? 1.0 : 0.0;
            sampleWeight *= nrd_material_weight(centerMaterial, texelFetch(radiosity_material, sampleCoord, 0));
            sampleWeight *= nrd_plane_distance_weight_normalized(
                centerWorldPos, centerNormal, sampleWorldPos, centerViewZ, ph_nrd_depth_threshold);

            float cosA = clamp(dot(centerNormal, sampleNormal), -1.0, 1.0);
            float angle = sqrt(2.0 * max(0.0, 1.0 - cosA));
            sampleWeight *= nrd_compute_weight(angle, normalWeightParam, 0.0);

            ivec2 diffSampleCoord = nrd_get_current_checkerboard_owner_pixel(sampleCoord, texSize);
            vec4 sampleDiff = (sampleWeight == 0.0) ? vec4(0.0) :
                texelFetch(nrd_in_diff_radiance_hitdist, diffSampleCoord, 0);

            sampleWeight *= mix(0.2, 1.0,
                nrd_compute_exponential_weight(sampleDiff.a, hitDistWeightParams.x, hitDistWeightParams.y));
            sampleWeight *= nrd_gaussian_weight(offset.z);

            diffuseIllumination += sampleDiff * sampleWeight;
            weightSum += sampleWeight;
        }

        diffuseIllumination /= max(weightSum, 1e-6);
    }

    if (ph_nrd_spec_prepass_blur_radius > 0.0) {
        vec3 viewVector = nrd_safe_normal(world_camera_position - centerWorldPos);
        vec3 dominantDir = nrd_specular_dominant_direction(centerNormal, viewVector, centerRoughness);
        float noD = abs(dot(centerNormal, dominantDir));

        float frustumSize = ph_pixel_radius_to_world(min(viewWidth, viewHeight), centerViewZ);
        float specHitDistForRadius = (specularIllumination.a == 0.0) ? 1.0 : specularIllumination.a;
        float hitDistFactor = clamp((specHitDistForRadius * noD) / max(frustumSize, 1e-6), 0.0, 1.0);
        float smc = nrd_spec_magic_curve(centerRoughness);
        float blurRadius = ph_nrd_spec_prepass_blur_radius * hitDistFactor * smc;

        float lobeTanHalfAngle = nrd_spec_lobe_tan_half_angle(centerRoughness, 0.75);
        float lobeRadius = specHitDistForRadius * noD * lobeTanHalfAngle;
        float pxToWorld = ph_pixel_radius_to_world(1.0, centerViewZ + specHitDistForRadius * noD);
        float minBlurRadius = lobeRadius / max(pxToWorld, 1e-6);
        blurRadius = min(blurRadius, minBlurRadius);
        if (specularIllumination.a == 0.0) {
            blurRadius = max(blurRadius, 1.0);
        }

        float normalWeightParam = nrd_normal_weight_param(centerRoughness, 0.5 * ph_nrd_lobe_angle_fraction);
        vec2 hitDistWeightParams = nrd_hit_distance_weight_params(specularIllumination.a, 1.0 / 9.0);
        vec2 roughnessWeightParams = nrd_roughness_weight_params(centerRoughness, ph_nrd_roughness_fraction);
        float specMinHitDistWeight = (specularIllumination.a == 0.0) ? 1.0 : 0.2 * smc;
        float specHitT = (specularIllumination.a == 0.0) ? ph_nrd_denoising_range : specularIllumination.a;
        float noV = abs(dot(centerNormal, viewVector));
        float minHitT = (specHitT == 0.0) ? NRD_INF : specHitT;
        float weightSum = 1.0;

        for (int i = 0; i < 8; i++) {
            vec3 offset = nrd_poisson8[i];
            vec2 rotatedOffset = nrd_rotate_vector(rotator, offset.xy);
            vec2 samplePixel = vec2(pixelPos) + 0.5 + rotatedOffset * blurRadius;
            samplePixel = floor(samplePixel) + 0.5;

            vec2 sampleUv = samplePixel / vec2(viewWidth, viewHeight);
            ivec2 sampleCoord = clamp(ivec2(samplePixel), ivec2(0), texSize - ivec2(1));

            vec3 sampleNormal = nrd_safe_normal(texelFetch(radiosity_normal, sampleCoord, 0).xyz);
            vec4 sampleMaterial = texelFetch(radiosity_material, sampleCoord, 0);
            float sampleRoughness = clamp(sampleMaterial.x, 0.0, 1.0);
            vec3 sampleWorldPos = texelFetch(radiosity_position, sampleCoord, 0).xyz;
            float sampleViewZ = nrd_compute_view_z(sampleWorldPos);

            float sampleWeight = nrd_is_in_screen_nearest(sampleUv);
            sampleWeight *= (sampleViewZ < ph_nrd_denoising_range) ? 1.0 : 0.0;
            sampleWeight *= nrd_material_weight(centerMaterial, sampleMaterial);
            sampleWeight *= nrd_compute_weight(sampleRoughness, roughnessWeightParams.x, roughnessWeightParams.y);

            float cosA = clamp(dot(centerNormal, sampleNormal), -1.0, 1.0);
            float angle = sqrt(2.0 * max(0.0, 1.0 - cosA));
            sampleWeight *= nrd_compute_weight(angle, normalWeightParam, 0.0);
            sampleWeight *= nrd_plane_distance_weight_normalized(
                centerWorldPos, centerNormal, sampleWorldPos, centerViewZ, ph_nrd_depth_threshold);

            ivec2 specSampleCoord = nrd_get_current_checkerboard_owner_pixel(sampleCoord, texSize);
            vec4 sampleSpec = (sampleWeight == 0.0) ? vec4(0.0) :
                texelFetch(nrd_in_spec_radiance_hitdist, specSampleCoord, 0);

            if (sampleWeight * noV > 0.5) {
                minHitT = min(minHitT, (sampleSpec.a == 0.0) ? NRD_INF : sampleSpec.a);
            }

            sampleWeight *= mix(specMinHitDistWeight, 1.0,
                nrd_compute_exponential_weight(sampleSpec.a, hitDistWeightParams.x, hitDistWeightParams.y));
            sampleWeight *= nrd_gaussian_weight(offset.z);

            float d = length(sampleWorldPos - centerWorldPos);
            float t = sampleSpec.a / max(specularIllumination.a + d, 1e-6);
            float roughnessStep = clamp((centerRoughness - 0.5) / 0.5, 0.0, 1.0);
            sampleWeight *= mix(clamp(t, 0.0, 1.0), 1.0, roughnessStep);

            specularIllumination.rgb += sampleSpec.rgb * sampleWeight;
            weightSum += sampleWeight;
        }

        specularIllumination.rgb /= max(weightSum, 1e-6);
        specularIllumination.a = (minHitT >= NRD_INF * 0.5) ? 0.0 : minHitT;
    }

    nrd_diff_prepass_out = clamp(diffuseIllumination, vec4(0.0), vec4(NRD_FP16_MAX));
    nrd_spec_prepass_out = clamp(specularIllumination, vec4(0.0), vec4(NRD_FP16_MAX));
}
