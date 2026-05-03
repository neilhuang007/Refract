#version 430

// ---------------------------------------------------------------------------
// nrd_hitdist_reconstruction.fsh
//
// Mirror of RELAX_HitDistReconstruction.cs.hlsl.
//
// The reference uses shared memory (groupshared float4 s_Normal_Roughness and
// groupshared float3 s_HitDist_ViewZ) to cache the neighbourhood.  Fragment
// shaders cannot use groupshared memory; we substitute direct texelFetch calls
// for each neighbour, which is the only structural deviation.
//
// NRD_BORDER = 1 → 3x3 kernel.  When ph_nrd_hitdist_reconstruction == 2.0,
// NRD_BORDER = 2 → 5x5 kernel (MODE_5X5 permutation in reference).
//
// Output:
//   nrd_diff_recon_out  (location 0) — diffuse   rgb + reconstructed hitDist
//   nrd_spec_recon_out  (location 1) — specular  rgb + reconstructed hitDist
//
// Reference: RELAX_HitDistReconstruction.cs.hlsl:45-158
// ---------------------------------------------------------------------------

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_diff_recon_out;
layout(location = 1) out vec4 nrd_spec_recon_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

void main() {
    ivec2 pixelPos = tex_coord;

    // RELAX_HitDistReconstruction.cs.hlsl:52-58 -- tile-based early out.
    // Reference reads isSky = gIn_Tiles[pixelPos >> 4].
    ivec2 tileCoord = pixelPos >> 4;
    float isSky = texelFetch(nrd_in_tiles, tileCoord, 0).r;
    if (isSky > 0.5) {
        nrd_diff_recon_out = vec4(0.0);
        nrd_spec_recon_out = vec4(0.0);
        return;
    }

    // Read center G-buffer values.
    // RELAX_HitDistReconstruction.cs.hlsl:61-71
    vec3 centerWorldPos = texelFetch(radiosity_position, pixelPos, 0).xyz;
    float centerViewZ = nrd_compute_view_z(centerWorldPos);

    // RELAX_HitDistReconstruction.cs.hlsl:64-66 -- early out for out-of-range center
    if (centerViewZ >= ph_nrd_denoising_range) {
        nrd_diff_recon_out = texelFetch(nrd_in_diff_radiance_hitdist, pixelPos, 0);
        nrd_spec_recon_out = texelFetch(nrd_in_spec_radiance_hitdist, pixelPos, 0);
        return;
    }

    vec3 centerNormal = nrd_safe_normal(texelFetch(radiosity_normal, pixelPos, 0).xyz);
    vec4 centerMaterial = texelFetch(radiosity_material, pixelPos, 0);
    float centerRoughness = centerMaterial.x;

    vec4 centerDiffSample = texelFetch(nrd_in_diff_radiance_hitdist, pixelPos, 0);
    vec4 centerSpecSample = texelFetch(nrd_in_spec_radiance_hitdist, pixelPos, 0);

    float centerDiffHitDist = centerDiffSample.a;
    float centerSpecHitDist = centerSpecSample.a;

    // RELAX_HitDistReconstruction.cs.hlsl:77-91
    // specularNormalWeightParam = GetNormalWeightParam(1.0, 1.0, centerRoughness)
    //   => nrd_normal_weight_param(centerRoughness, lobeAngleFraction=1.0)
    float specNormalWeightParam = nrd_normal_weight_param(centerRoughness, 1.0);

    // relaxedRoughnessWeightParams = GetRelaxedRoughnessWeightParams(centerRoughness*centerRoughness)
    float m = centerRoughness * centerRoughness;
    vec2 relaxedRoughnessWeightParams = nrd_get_relaxed_roughness_weight_params(m);

    // diffuseNormalWeightParam = GetNormalWeightParam(1.0, 1.0) [roughness=1.0]
    float diffNormalWeightParam = nrd_normal_weight_param(1.0, 1.0);

    // Centre pixel bias: weight 1000 if hitDist is non-zero (reference line 80,89)
    float sumSpecWeight = 1000.0 * float(centerSpecHitDist != 0.0);
    float sumSpecHitDist = centerSpecHitDist * sumSpecWeight;

    float sumDiffWeight = 1000.0 * float(centerDiffHitDist != 0.0);
    float sumDiffHitDist = centerDiffHitDist * sumDiffWeight;

    // Determine kernel radius: 1 for 3x3, 2 for 5x5.
    // RELAX_HitDistReconstruction.cs.hlsl: NRD_BORDER = 1 (3x3) or 2 (5x5).
    // Reference uses compile-time MODE_5X5 define; we branch on the uniform.
    int border = (ph_nrd_hitdist_reconstruction >= 1.95) ? 2 : 1;

    // Pixel UV for screen boundary test (reference line 51)
    vec2 pixelUv = (vec2(pixelPos) + vec2(0.5)) / vec2(viewWidth, viewHeight);

    // RELAX_HitDistReconstruction.cs.hlsl:93-145 -- neighbour loop
    for (int dy = 0; dy <= border * 2; dy++) {
        for (int dx = 0; dx <= border * 2; dx++) {
            ivec2 o = ivec2(dx, dy) - ivec2(border);
            if (o.x == 0 && o.y == 0) continue;

            ivec2 samplePos = clamp(pixelPos + o, ivec2(0), ivec2(int(viewWidth) - 1, int(viewHeight) - 1));

            vec3 sampleWorldPos = texelFetch(radiosity_position, samplePos, 0).xyz;
            float sampleViewZ = nrd_compute_view_z(sampleWorldPos);
            vec3 sampleNormal = nrd_safe_normal(texelFetch(radiosity_normal, samplePos, 0).xyz);

            float cosA = dot(centerNormal, sampleNormal);
            // RELAX_HitDistReconstruction.cs.hlsl:111: Math::AcosApprox(cosa)
            // Math::AcosApprox(x) ≈ sqrt(2.0 * max(0, 1.0 - x)) (accurate for |x| <= 1)
            float angle = sqrt(2.0 * max(0.0, 1.0 - cosA));

            vec2 sampleUv = (vec2(samplePos) + vec2(0.5)) / vec2(viewWidth, viewHeight);

            // RELAX_HitDistReconstruction.cs.hlsl:113-116 combined weight
            float w = nrd_is_in_screen_nearest(sampleUv);
            w *= (sampleViewZ < ph_nrd_denoising_range) ? 1.0 : 0.0;
            w *= nrd_gaussian_weight(length(vec2(o)) * 0.5);   // GetGaussianWeight(|o|*0.5)
            w *= nrd_bilateral_weight(sampleViewZ, centerViewZ); // GetBilateralWeight

            // Denanify: if w == 0 the sample is irrelevant; treat as zero to match
            // "Denanify(w, x)" macro (Common.hlsli:227)

            // --- Specular ---
            // RELAX_HitDistReconstruction.cs.hlsl:118-130
            float specWeight = w;
            specWeight *= nrd_compute_weight(angle, specNormalWeightParam, 0.0);
            specWeight *= nrd_compute_weight(m, relaxedRoughnessWeightParams.x, relaxedRoughnessWeightParams.y);

            float sampleSpecHitDist = (specWeight == 0.0) ? 0.0 :
                texelFetch(nrd_in_spec_radiance_hitdist, samplePos, 0).a;
            specWeight *= float(sampleSpecHitDist != 0.0);

            sumSpecHitDist += sampleSpecHitDist * specWeight;
            sumSpecWeight  += specWeight;

            // --- Diffuse ---
            // RELAX_HitDistReconstruction.cs.hlsl:132-142
            float diffWeight = w;
            diffWeight *= nrd_compute_weight(angle, diffNormalWeightParam, 0.0);

            float sampleDiffHitDist = (diffWeight == 0.0) ? 0.0 :
                texelFetch(nrd_in_diff_radiance_hitdist, samplePos, 0).a;
            diffWeight *= float(sampleDiffHitDist != 0.0);

            sumDiffHitDist += sampleDiffHitDist * diffWeight;
            sumDiffWeight  += diffWeight;
        }
    }

    // RELAX_HitDistReconstruction.cs.hlsl:147-156
    sumSpecHitDist /= max(sumSpecWeight, 1e-6);
    sumDiffHitDist /= max(sumDiffWeight, 1e-6);

    nrd_spec_recon_out = vec4(centerSpecSample.rgb, sumSpecHitDist);
    nrd_diff_recon_out = vec4(centerDiffSample.rgb, sumDiffHitDist);
}
