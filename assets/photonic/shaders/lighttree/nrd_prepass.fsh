#version 430

// ---------------------------------------------------------------------------
// nrd_prepass.fsh
//
// Mirror of RELAX_PrePass.cs.hlsl.
//
// Performs a spatial pre-blur (cross-bilateral Poisson-8 disc) on the raw
// diffuse and specular illumination+hitDist inputs, output to the buffers
// that TemporalAccumulation will read as "noisy" input.
//
// The reference uses:
//   - gIn_Diff / gIn_Spec    → nrd_in_diff_radiance_hitdist / nrd_in_spec_radiance_hitdist
//   - gIn_ViewZ              → derived from radiosity_position
//   - gIn_Normal_Roughness   → radiosity_normal + radiosity_material (.x = roughness)
//
// Deviations from reference (fragment-shader constraints only):
//   1. groupshared SMEM: not available; all neighbourhood reads use texelFetch.
//   2. NRD_FRAME kernel rotation: approximated with golden-angle per frameCounter.
//   3. GetCurrentWorldPosFromClipSpaceXY: Photonics stores world-pos in G-buffer
//      for the centre pixel; neighbour positions reconstructed from sampled viewZ
//      and the centre's camera-relative vector (perspective camera assumption,
//      gOrthoMode == 0 branch of reference).
//   4. Checkerboard: handled via nrd_get_current_checkerboard_owner_pixel() when
//      ph_restir_active_checkerboard_field != 0.  Checkerboard-specific
//      gDiffCheckerboard / gSpecCheckerboard index logic omitted (Photonics
//      does not separate diff/spec checkerboard indices).
//   5. PixelRadiusToWorld approximation: uses min(viewWidth,viewHeight) as
//      "minRectDim" and the reciprocal of the max screen dimension as "unproject".
//
// Reference: RELAX_PrePass.cs.hlsl:24-386
// ---------------------------------------------------------------------------

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_diff_prepass_out;  // RGBA16F → nrdOutDiffRadianceHitDistFb
layout(location = 1) out vec4 nrd_spec_prepass_out;  // RGBA16F → nrdOutSpecRadianceHitDistFb

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

// ---------------------------------------------------------------------------
// Local helpers
// ---------------------------------------------------------------------------

// RELAX_PrePass.cs.hlsl uses gUnproject * min(gRectSize.x, gRectSize.y) for
// PixelRadiusToWorld.  In Photonics the projection matrix is not directly
// available as a scalar unproject factor, so we derive it from the G-buffer.
// We use the ratio: 1 world-unit / viewZ corresponds to roughly
// 2*tan(halfFov)/screenHeight pixels.  We approximate by sampling the
// relationship for the center pixel.
float ph_pixel_radius_to_world(float pixelRadius, float viewZ) {
    // Approximate: tan(halfFovY) ~ 1/max(viewWidth,viewHeight).
    // This matches the reference formula PixelRadiusToWorld(unproject, 0, minDim, viewZ)
    // = pixelRadius * unproject * viewZ  where unproject ~ 1/minDim.
    float minDim = min(viewWidth, viewHeight);
    return pixelRadius * (viewZ / max(minDim, 1.0));
}

// Reconstruct a world-space sample position from its UV and viewZ.
// Reference Common.hlsli:75-79 GetCurrentWorldPosFromClipSpaceXY (gOrthoMode=0).
// We use the center world position to derive the view frustum direction, then
// scale laterally based on UV offset.
vec3 ph_world_pos_from_uv_and_viewz(vec2 sampleUv, float sampleViewZ,
                                     vec3 centerWorldPos, float centerViewZ) {
    // Camera-relative direction of center pixel.
    vec3 centerDir = (centerWorldPos - world_camera_position) / max(centerViewZ, 1e-3);
    // For perspective: world_pos = camera + viewZ * direction_at_uv.
    // direction_at_uv ≈ centerDir + lateral_scale * (uvDelta).
    // We compute this by unproject: lateral correction = uvDelta * frustumScale * viewZ.
    vec2 centerUv = (vec2(tex_coord) + vec2(0.5)) / vec2(viewWidth, viewHeight);
    vec2 uvDelta = sampleUv - centerUv;
    // Scale by 2.0 * tan(halfFov) ≈ 2 / minDim in normalized NDC, then * viewZ.
    float scaleFactor = sampleViewZ * 2.0 / min(viewWidth, viewHeight);
    vec3 samplePos = world_camera_position + centerDir * sampleViewZ
                   + vec3(uvDelta.x, -uvDelta.y, 0.0) * scaleFactor;
    return samplePos;
}

void main() {
    ivec2 pixelPos = tex_coord;

    // RELAX_PrePass.cs.hlsl:30-32 -- tile-based early out
    ivec2 tileCoord = pixelPos >> 4;
    float isSky = texelFetch(nrd_in_tiles, tileCoord, 0).r;
    if (isSky > 0.5) {
        nrd_diff_prepass_out = vec4(0.0);
        nrd_spec_prepass_out = vec4(0.0);
        return;
    }

    // RELAX_PrePass.cs.hlsl:35-37 -- center viewZ early out
    vec3 centerWorldPos = texelFetch(radiosity_position, pixelPos, 0).xyz;
    float centerViewZ = nrd_compute_view_z(centerWorldPos);
    if (centerViewZ >= ph_nrd_denoising_range) {
        nrd_diff_prepass_out = vec4(0.0);
        nrd_spec_prepass_out = vec4(0.0);
        return;
    }

    // RELAX_PrePass.cs.hlsl:74-77 -- center G-buffer
    vec3 centerNormal = nrd_safe_normal(texelFetch(radiosity_normal, pixelPos, 0).xyz);
    vec4 centerMaterial = texelFetch(radiosity_material, pixelPos, 0);
    float centerRoughness = centerMaterial.x;

    vec2 pixelUv = (vec2(pixelPos) + vec2(0.5)) / vec2(viewWidth, viewHeight);

    // RELAX_PrePass.cs.hlsl:80 -- blur kernel rotator (NRD_FRAME mode)
    vec4 rotator = nrd_get_kernel_rotation(frameCounter);

    // -----------------------------------------------------------------------
    // Checkerboard owner pixel for the center (no half-width shift needed when
    // checkerboard is off or when this is the owning field).
    // RELAX_PrePass.cs.hlsl:84-125 checkerboard resolve.
    // -----------------------------------------------------------------------
    ivec2 texSize = textureSize(nrd_in_diff_radiance_hitdist, 0);
    ivec2 diffCenter = nrd_get_current_checkerboard_owner_pixel(pixelPos, texSize);
    ivec2 specCenter = nrd_get_current_checkerboard_owner_pixel(pixelPos, texSize);

    // RELAX_PrePass.cs.hlsl:96 -- read center diffuse illumination
    vec4 diffuseIllumination = texelFetch(nrd_in_diff_radiance_hitdist, diffCenter, 0);

    // RELAX_PrePass.cs.hlsl:233 -- clamp spec hitDist to [0, denoisingRange]
    vec4 specularIllumination = texelFetch(nrd_in_spec_radiance_hitdist, specCenter, 0);
    specularIllumination.a = max(0.0, min(ph_nrd_denoising_range, specularIllumination.a));

    // -----------------------------------------------------------------------
    // Diffuse pre-blur
    // RELAX_PrePass.cs.hlsl:128-211
    // -----------------------------------------------------------------------
    if (ph_nrd_diff_prepass_blur_radius > 0.0) {
        // RELAX_PrePass.cs.hlsl:131-138 -- blur radius
        float frustumSize = ph_pixel_radius_to_world(min(viewWidth, viewHeight), centerViewZ);
        float hitDistForRadius = (diffuseIllumination.a == 0.0) ? 1.0 : diffuseIllumination.a;
        float hitDistFactor = clamp(hitDistForRadius / max(frustumSize, 1e-6), 0.0, 1.0);
        float blurRadius = ph_nrd_diff_prepass_blur_radius * hitDistFactor;
        if (diffuseIllumination.a == 0.0)
            blurRadius = max(blurRadius, 1.0);

        // RELAX_PrePass.cs.hlsl:139-140 -- weights params
        // normalWeightParam = GetNormalWeightParam2(1.0, 0.25 * gLobeAngleFraction)
        float normalWeightParam = nrd_normal_weight_param(1.0, 0.25 * ph_nrd_lobe_angle_fraction);
        // hitDistanceWeightParams = GetHitDistanceWeightParams(diffuseIllumination.w, 1.0/9.0)
        vec2 hitDistWeightParams = nrd_hit_distance_weight_params(diffuseIllumination.a, 1.0 / 9.0);

        float diffMinHitDistWeight = 0.2; // gMinHitDistanceWeight reference default
        float weightSum = 1.0;

        // RELAX_PrePass.cs.hlsl:147-206 -- Poisson-8 spatial blur
        for (int i = 0; i < 8; i++) {
            vec3 offset = nrd_poisson8[i];

            // RELAX_PrePass.cs.hlsl:151-153 -- rotated sample UV in pixel space
            vec2 rotatedOffset = nrd_rotate_vector(rotator, offset.xy);
            vec2 samplePixel = vec2(pixelPos) + 0.5 + rotatedOffset * blurRadius;

            // Snap to pixel centre (reference line 155: uv = floor(uv) + 0.5)
            samplePixel = floor(samplePixel) + 0.5;

            vec2 sampleUv = samplePixel / vec2(viewWidth, viewHeight);
            ivec2 sampleCoord = ivec2(samplePixel);
            sampleCoord = clamp(sampleCoord, ivec2(0), ivec2(int(viewWidth) - 1, int(viewHeight) - 1));

            // RELAX_PrePass.cs.hlsl:170-172 -- fetch sample G-buffer
            vec3 sampleNormal = nrd_safe_normal(texelFetch(radiosity_normal, sampleCoord, 0).xyz);
            vec3 sampleWorldPos = texelFetch(radiosity_position, sampleCoord, 0).xyz;
            float sampleViewZ = nrd_compute_view_z(sampleWorldPos);

            // RELAX_PrePass.cs.hlsl:175-185 -- sample weight
            float sampleWeight = nrd_is_in_screen_nearest(sampleUv);
            sampleWeight *= (sampleViewZ < ph_nrd_denoising_range) ? 1.0 : 0.0;
            // CompareMaterials: material weight (same type = 1.0)
            sampleWeight *= nrd_material_weight(centerMaterial, texelFetch(radiosity_material, sampleCoord, 0));

            // GetPlaneDistanceWeight (ref line 180-185, gOrthoMode==0 → centerViewZ)
            sampleWeight *= nrd_plane_distance_weight_normalized(
                centerWorldPos, centerNormal, sampleWorldPos, centerViewZ, ph_nrd_depth_threshold);

            // RELAX_PrePass.cs.hlsl:187-188 -- normal weight
            float cosA = clamp(dot(centerNormal, sampleNormal), -1.0, 1.0);
            float angle = sqrt(2.0 * max(0.0, 1.0 - cosA)); // Math::AcosApprox
            sampleWeight *= nrd_compute_weight(angle, normalWeightParam, 0.0);

            // RELAX_PrePass.cs.hlsl:190-191 -- fetch diff signal, denanify
            ivec2 diffSampleCoord = nrd_get_current_checkerboard_owner_pixel(sampleCoord, texSize);
            vec4 sampleDiff = (sampleWeight == 0.0) ? vec4(0.0) :
                texelFetch(nrd_in_diff_radiance_hitdist, diffSampleCoord, 0);

            // RELAX_PrePass.cs.hlsl:193-194 -- hitDist weight + gaussian weight
            sampleWeight *= mix(diffMinHitDistWeight, 1.0,
                nrd_compute_exponential_weight(sampleDiff.a, hitDistWeightParams.x, hitDistWeightParams.y));
            sampleWeight *= nrd_gaussian_weight(offset.z); // offset.z = length(offset.xy)

            weightSum += sampleWeight;
            diffuseIllumination += sampleDiff * sampleWeight;
        }

        diffuseIllumination /= weightSum;
    }

    // -----------------------------------------------------------------------
    // Specular pre-blur
    // RELAX_PrePass.cs.hlsl:267-379
    // -----------------------------------------------------------------------
    if (ph_nrd_spec_prepass_blur_radius > 0.0) {
        // View vector (camera-relative, perspective, gOrthoMode == 0)
        // RELAX_PrePass.cs.hlsl:270-271
        vec3 viewVector = nrd_safe_normal(world_camera_position - centerWorldPos);

        // RELAX_PrePass.cs.hlsl:271 -- specular dominant direction
        // ImportanceSampling::GetSpecularDominantDirection returns vec4 (D.xyz, NoD)
        vec3 dominantDir = nrd_specular_dominant_direction(centerNormal, viewVector, centerRoughness);
        float NoD = abs(dot(centerNormal, dominantDir));

        // RELAX_PrePass.cs.hlsl:274-276
        float frustumSize = ph_pixel_radius_to_world(min(viewWidth, viewHeight), centerViewZ);
        float specHitDistForRadius = (specularIllumination.a == 0.0) ? 1.0 : specularIllumination.a;
        float hitDistFactor = clamp((specHitDistForRadius * NoD) / max(frustumSize, 1e-6), 0.0, 1.0);

        // RELAX_PrePass.cs.hlsl:279-286 -- blur radius
        float smc = nrd_spec_magic_curve(centerRoughness);
        float blurRadius = ph_nrd_spec_prepass_blur_radius * hitDistFactor * smc;

        // Lobe-constrained minimum blur radius
        float lobeTanHalfAngle = nrd_spec_lobe_tan_half_angle(centerRoughness, 0.75);
        float lobeRadius = specHitDistForRadius * NoD * lobeTanHalfAngle;
        float pxToWorld = ph_pixel_radius_to_world(1.0, centerViewZ + specHitDistForRadius * NoD);
        float minBlurRadius = lobeRadius / max(pxToWorld, 1e-6);
        blurRadius = min(blurRadius, minBlurRadius);

        if (specularIllumination.a == 0.0)
            blurRadius = max(blurRadius, 1.0);

        // RELAX_PrePass.cs.hlsl:290-294 -- weight params
        // normalWeightParam = GetNormalWeightParam2(centerRoughness, 0.5 * gLobeAngleFraction)
        float normalWeightParam = nrd_normal_weight_param(centerRoughness, 0.5 * ph_nrd_lobe_angle_fraction);
        vec2 hitDistWeightParams = nrd_hit_distance_weight_params(specularIllumination.a, 1.0 / 9.0);
        vec2 roughnessWeightParams = nrd_roughness_weight_params(centerRoughness, ph_nrd_roughness_fraction);

        float specMinHitDistWeight = (specularIllumination.a == 0.0) ? 1.0 : 0.2 * smc;
        float specHitT = (specularIllumination.a == 0.0) ? ph_nrd_denoising_range : specularIllumination.a;

        float NoV = abs(dot(centerNormal, viewVector));
        float minHitT = (specHitT == 0.0) ? NRD_INF : specHitT;
        float weightSum = 1.0;

        // RELAX_PrePass.cs.hlsl:302-373 -- Poisson-8 spatial blur
        for (int i = 0; i < 8; i++) {
            vec3 offset = nrd_poisson8[i];

            vec2 rotatedOffset = nrd_rotate_vector(rotator, offset.xy);
            vec2 samplePixel = vec2(pixelPos) + 0.5 + rotatedOffset * blurRadius;
            samplePixel = floor(samplePixel) + 0.5;

            vec2 sampleUv = samplePixel / vec2(viewWidth, viewHeight);
            ivec2 sampleCoord = ivec2(samplePixel);
            sampleCoord = clamp(sampleCoord, ivec2(0), ivec2(int(viewWidth) - 1, int(viewHeight) - 1));

            vec3 sampleNormal = nrd_safe_normal(texelFetch(radiosity_normal, sampleCoord, 0).xyz);
            vec4 sampleMaterial = texelFetch(radiosity_material, sampleCoord, 0);
            float sampleRoughness = sampleMaterial.x;
            vec3 sampleWorldPos = texelFetch(radiosity_position, sampleCoord, 0).xyz;
            float sampleViewZ = nrd_compute_view_z(sampleWorldPos);

            // RELAX_PrePass.cs.hlsl:333-346 -- sample weight
            float sampleWeight = nrd_is_in_screen_nearest(sampleUv);
            sampleWeight *= (sampleViewZ < ph_nrd_denoising_range) ? 1.0 : 0.0;
            sampleWeight *= nrd_material_weight(centerMaterial, sampleMaterial);
            // Roughness weight: ComputeWeight(sampleRoughness, ...)
            sampleWeight *= nrd_compute_weight(sampleRoughness, roughnessWeightParams.x, roughnessWeightParams.y);

            float cosA = clamp(dot(centerNormal, sampleNormal), -1.0, 1.0);
            float angle = sqrt(2.0 * max(0.0, 1.0 - cosA)); // Math::AcosApprox
            sampleWeight *= nrd_compute_weight(angle, normalWeightParam, 0.0);

            // Plane distance weight (gOrthoMode==0 → centerViewZ)
            sampleWeight *= nrd_plane_distance_weight_normalized(
                centerWorldPos, centerNormal, sampleWorldPos, centerViewZ, ph_nrd_depth_threshold);

            ivec2 specSampleCoord = nrd_get_current_checkerboard_owner_pixel(sampleCoord, texSize);
            vec4 sampleSpec = (sampleWeight == 0.0) ? vec4(0.0) :
                texelFetch(nrd_in_spec_radiance_hitdist, specSampleCoord, 0);

            // RELAX_PrePass.cs.hlsl:352-353 -- stochastic min-hitT update
            // Reference uses Rng::Hash::GetFloat() < sampleWeight * NoV.
            // Photonics: use a deterministic approximation (sampleWeight * NoV > 0.5).
            // This is a minor deviation; the reference uses per-thread PRNG here.
            if (sampleWeight * NoV > 0.5)
                minHitT = min(minHitT, (sampleSpec.a == 0.0) ? NRD_INF : sampleSpec.a);

            sampleWeight *= mix(specMinHitDistWeight, 1.0,
                nrd_compute_exponential_weight(sampleSpec.a, hitDistWeightParams.x, hitDistWeightParams.y));
            sampleWeight *= nrd_gaussian_weight(offset.z);

            // RELAX_PrePass.cs.hlsl:359-362 -- proximity weight
            // Decreasing weight for close-contact reflections (should not be pre-blurred)
            float d = length(sampleWorldPos - centerWorldPos);
            float h = sampleSpec.a;
            float t = h / max(specularIllumination.a + d, 1e-6);
            float roughnessStep = clamp((centerRoughness - 0.5) / 0.5, 0.0, 1.0); // Math::LinearStep(0.5,1.0)
            sampleWeight *= mix(clamp(t, 0.0, 1.0), 1.0, roughnessStep);

            weightSum += sampleWeight;
            specularIllumination.rgb += sampleSpec.rgb * sampleWeight;
        }

        specularIllumination.rgb /= weightSum;
        // RELAX_PrePass.cs.hlsl:375: specularIllumination.a = minHitT == NRD_INF ? 0.0 : minHitT
        specularIllumination.a = (minHitT >= NRD_INF * 0.5) ? 0.0 : minHitT;
    }

    // RELAX_PrePass.cs.hlsl:213,381 -- clamp to FP16 max before output
    nrd_diff_prepass_out = clamp(diffuseIllumination, vec4(0.0), vec4(NRD_FP16_MAX));
    nrd_spec_prepass_out = clamp(specularIllumination, vec4(0.0), vec4(NRD_FP16_MAX));
}
