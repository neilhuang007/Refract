#version 430

// RELAX hit-distance reconstruction adapted to the fragment pipeline.
// The Java renderer currently disables this pass, but the shader still needs
// to exist and compile because the renderer owns a program for it.

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_diff_recon_out;
layout(location = 1) out vec4 nrd_spec_recon_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

void main() {
    ivec2 pixelPos = tex_coord;
    float isSky = texelFetch(nrd_in_tiles, pixelPos >> 4, 0).r;

    if (isSky > 0.5) {
        nrd_diff_recon_out = vec4(0.0);
        nrd_spec_recon_out = vec4(0.0);
        return;
    }

    vec3 centerWorldPos = texelFetch(radiosity_position, pixelPos, 0).xyz;
    float centerViewZ = nrd_compute_view_z(centerWorldPos);
    vec4 centerDiffSample = texelFetch(nrd_in_diff_radiance_hitdist, pixelPos, 0);
    vec4 centerSpecSample = texelFetch(nrd_in_spec_radiance_hitdist, pixelPos, 0);

    if (centerViewZ >= ph_nrd_denoising_range) {
        nrd_diff_recon_out = centerDiffSample;
        nrd_spec_recon_out = centerSpecSample;
        return;
    }

    ivec2 texSize = textureSize(nrd_in_diff_radiance_hitdist, 0);
    vec3 centerNormal = nrd_safe_normal(texelFetch(radiosity_normal, pixelPos, 0).xyz);
    vec4 centerMaterial = texelFetch(radiosity_material, pixelPos, 0);
    float centerRoughness = clamp(centerMaterial.x, 0.0, 1.0);

    float specNormalWeightParam = nrd_normal_weight_param(centerRoughness, 1.0);
    float diffNormalWeightParam = nrd_normal_weight_param(1.0, 1.0);
    vec2 relaxedRoughnessWeightParams =
        nrd_get_relaxed_roughness_weight_params(centerRoughness * centerRoughness);

    float centerDiffHitDist = centerDiffSample.a;
    float centerSpecHitDist = centerSpecSample.a;
    float sumSpecWeight = 1000.0 * float(centerSpecHitDist != 0.0);
    float sumSpecHitDist = centerSpecHitDist * sumSpecWeight;
    float sumDiffWeight = 1000.0 * float(centerDiffHitDist != 0.0);
    float sumDiffHitDist = centerDiffHitDist * sumDiffWeight;

    int border = (ph_nrd_hitdist_reconstruction >= 1.95) ? 2 : 1;

    for (int dy = -border; dy <= border; dy++) {
        for (int dx = -border; dx <= border; dx++) {
            ivec2 o = ivec2(dx, dy);
            if (o.x == 0 && o.y == 0) {
                continue;
            }

            ivec2 unclampedPos = pixelPos + o;
            bool isInside = all(greaterThanEqual(unclampedPos, ivec2(0))) &&
                            all(lessThan(unclampedPos, texSize));
            ivec2 samplePos = clamp(unclampedPos, ivec2(0), texSize - ivec2(1));

            vec3 sampleWorldPos = texelFetch(radiosity_position, samplePos, 0).xyz;
            float sampleViewZ = nrd_compute_view_z(sampleWorldPos);
            vec3 sampleNormal = nrd_safe_normal(texelFetch(radiosity_normal, samplePos, 0).xyz);
            float angle = sqrt(2.0 * max(0.0, 1.0 - dot(centerNormal, sampleNormal)));

            float w = isInside ? 1.0 : 0.0;
            w *= (sampleViewZ < ph_nrd_denoising_range) ? 1.0 : 0.0;
            w *= nrd_gaussian_weight(length(vec2(o)) * 0.5);
            w *= nrd_bilateral_weight(sampleViewZ, centerViewZ);

            float specWeight = w;
            specWeight *= nrd_compute_weight(angle, specNormalWeightParam, 0.0);
            specWeight *= nrd_compute_weight(
                centerRoughness * centerRoughness,
                relaxedRoughnessWeightParams.x,
                relaxedRoughnessWeightParams.y
            );
            float sampleSpecHitDist = (specWeight == 0.0) ? 0.0 :
                texelFetch(nrd_in_spec_radiance_hitdist, samplePos, 0).a;
            specWeight *= float(sampleSpecHitDist != 0.0);
            sumSpecHitDist += sampleSpecHitDist * specWeight;
            sumSpecWeight += specWeight;

            float diffWeight = w;
            diffWeight *= nrd_compute_weight(angle, diffNormalWeightParam, 0.0);
            float sampleDiffHitDist = (diffWeight == 0.0) ? 0.0 :
                texelFetch(nrd_in_diff_radiance_hitdist, samplePos, 0).a;
            diffWeight *= float(sampleDiffHitDist != 0.0);
            sumDiffHitDist += sampleDiffHitDist * diffWeight;
            sumDiffWeight += diffWeight;
        }
    }

    nrd_diff_recon_out = vec4(centerDiffSample.rgb, sumDiffHitDist / max(sumDiffWeight, 1e-6));
    nrd_spec_recon_out = vec4(centerSpecSample.rgb, sumSpecHitDist / max(sumSpecWeight, 1e-6));
}
