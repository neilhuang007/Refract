#version 430

in vec4 direction_vert_out;

// MRT layout -- contract section 7, AntiFirefly
// Writes back into the permanent diff/spec illum prev buffers (in-place rewrite).
layout(location = 0) out vec4 nrd_diff_illum_prev_firefly_out;
layout(location = 1) out vec4 nrd_spec_illum_prev_firefly_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

// Samplers declared in samplers.glsl (via header.glsl → photonics.glsl → ph_samplers.glsl → samplers.glsl):
//   nrd_out_diff_radiance_hitdist, nrd_out_spec_radiance_hitdist,
//   nrd_in_tiles, radiosity_material, radiosity_position

// RELAX_AntiFirefly.cs.hlsl -- Cross-bilateral RCRS (Rank-Conditioned Rank-Selection) filter.
// Fused diffuse + specular in one pass, matching the reference structure exactly.
// Reference lines 50-170.
void runRCRS(
    ivec2 pixelPos,
    ivec2 texSize,
    vec4 centerMaterial,
    out vec4 outDiffuse,
    out vec4 outSpecular
) {
    // Fetch center data (RELAX_AntiFirefly.cs.hlsl:62-87)
    vec4 diffCenter = texelFetch(nrd_out_diff_radiance_hitdist, pixelPos, 0);
    vec3 diffuseIlluminationCenter = diffCenter.rgb;
    float diffuse2ndMomentCenter = diffCenter.a;  // preserved unchanged per reference line 168
    float diffuseLuminanceCenter = nrd_luminance(diffuseIlluminationCenter);

    vec4 specCenter = texelFetch(nrd_out_spec_radiance_hitdist, pixelPos, 0);
    vec3 specularIlluminationCenter = specCenter.rgb;
    float specular2ndMomentCenter = specCenter.a;  // preserved unchanged per reference line 159
    float specularLuminanceCenter = nrd_luminance(specularIlluminationCenter);

    // RELAX_AntiFirefly.cs.hlsl:82-87 -- init min/max trackers, sentinel at center coords
    float maxDiffuseLuminance = -1.0;
    float minDiffuseLuminance = 1.0e6;
    ivec2 maxDiffuseLuminanceCoords = pixelPos;
    ivec2 minDiffuseLuminanceCoords = pixelPos;

    // RELAX_AntiFirefly.cs.hlsl:72-76 -- spec min/max trackers
    float maxSpecularLuminance = -1.0;
    float minSpecularLuminance = 1.0e6;
    ivec2 maxSpecularLuminanceCoords = pixelPos;
    ivec2 minSpecularLuminanceCoords = pixelPos;

    // RELAX_AntiFirefly.cs.hlsl:89-149 -- 3x3 neighbourhood scan with material gate
    for (int yy = -1; yy <= 1; yy++) {
        for (int xx = -1; xx <= 1; xx++) {
            if (xx == 0 && yy == 0) continue;

            ivec2 sampleCoord = pixelPos + ivec2(xx, yy);

            // RELAX_AntiFirefly.cs.hlsl:101-102 -- bounds check
            if (any(lessThan(sampleCoord, ivec2(0))) || any(greaterThanEqual(sampleCoord, texSize))) continue;

            // RELAX_AntiFirefly.cs.hlsl:115 / 133 -- CompareMaterials per signal
            // Reference has no per-tap viewZ check inside the loop (only center early-out above).
            vec4 sampleMaterial = texelFetch(radiosity_material, sampleCoord, 0);

            // Diffuse: RELAX_AntiFirefly.cs.hlsl:133-147 -- CompareMaterials(sampleMaterialID, centerMaterialID, gDiffMinMaterial)
            if (nrd_material_weight(centerMaterial, sampleMaterial) > 0.0) {
                float diffuseLuminanceSample = nrd_luminance(texelFetch(nrd_out_diff_radiance_hitdist, sampleCoord, 0).rgb);

                // RELAX_AntiFirefly.cs.hlsl:134-138
                if (diffuseLuminanceSample > maxDiffuseLuminance) {
                    maxDiffuseLuminance = diffuseLuminanceSample;
                    maxDiffuseLuminanceCoords = sampleCoord;
                }
                // RELAX_AntiFirefly.cs.hlsl:139-143
                if (diffuseLuminanceSample < minDiffuseLuminance) {
                    minDiffuseLuminance = diffuseLuminanceSample;
                    minDiffuseLuminanceCoords = sampleCoord;
                }
            }

            // Specular: RELAX_AntiFirefly.cs.hlsl:117-131 -- CompareMaterials(sampleMaterialID, centerMaterialID, gSpecMinMaterial)
            if (nrd_material_weight(centerMaterial, sampleMaterial) > 0.0) {
                float specularLuminanceSample = nrd_luminance(texelFetch(nrd_out_spec_radiance_hitdist, sampleCoord, 0).rgb);

                // RELAX_AntiFirefly.cs.hlsl:118-122
                if (specularLuminanceSample > maxSpecularLuminance) {
                    maxSpecularLuminance = specularLuminanceSample;
                    maxSpecularLuminanceCoords = sampleCoord;
                }
                // RELAX_AntiFirefly.cs.hlsl:123-127
                if (specularLuminanceSample < minSpecularLuminance) {
                    minSpecularLuminance = specularLuminanceSample;
                    minSpecularLuminanceCoords = sampleCoord;
                }
            }
        }
    }

    // RELAX_AntiFirefly.cs.hlsl:162-168 -- diffuse RCRS selection
    // Replace center with min/max neighbor if center is outside [min, max] range.
    // Center 2nd moment is always preserved (not taken from replacement neighbor).
    ivec2 diffuseCoords = pixelPos;
    if (diffuseLuminanceCenter > maxDiffuseLuminance)
        diffuseCoords = maxDiffuseLuminanceCoords;
    if (diffuseLuminanceCenter < minDiffuseLuminance)
        diffuseCoords = minDiffuseLuminanceCoords;
    outDiffuse = vec4(texelFetch(nrd_out_diff_radiance_hitdist, diffuseCoords, 0).rgb, diffuse2ndMomentCenter);

    // RELAX_AntiFirefly.cs.hlsl:153-159 -- specular RCRS selection
    ivec2 specularCoords = pixelPos;
    if (specularLuminanceCenter > maxSpecularLuminance)
        specularCoords = maxSpecularLuminanceCoords;
    if (specularLuminanceCenter < minSpecularLuminance)
        specularCoords = minSpecularLuminanceCoords;
    outSpecular = vec4(texelFetch(nrd_out_spec_radiance_hitdist, specularCoords, 0).rgb, specular2ndMomentCenter);
}

void main() {
    // RELAX_AntiFirefly.cs.hlsl:177, 180-182 -- tile early-out
    // Contract section 11.7: if tile flag > 0.5, this pixel is sky; write zero.
    if (texelFetch(nrd_in_tiles, tex_coord >> 4, 0).r > 0.5) {
        nrd_diff_illum_prev_firefly_out = vec4(0.0);
        nrd_spec_illum_prev_firefly_out = vec4(0.0);
        return;
    }

    // RELAX_AntiFirefly.cs.hlsl:184-187 -- viewZ early-out
    // Pixels beyond the denoising range are written back unchanged (not discarded).
    vec3 centerPos = texelFetch(radiosity_position, tex_coord, 0).xyz;
    float centerViewZ = nrd_compute_view_z(centerPos);
    if (centerViewZ > ph_nrd_denoising_range) {
        nrd_diff_illum_prev_firefly_out = texelFetch(nrd_out_diff_radiance_hitdist, tex_coord, 0);
        nrd_spec_illum_prev_firefly_out = texelFetch(nrd_out_spec_radiance_hitdist, tex_coord, 0);
        return;
    }

    // RELAX_AntiFirefly.cs.hlsl:190-207 -- run fused RCRS for diff and spec
    vec4 centerMaterial = texelFetch(radiosity_material, tex_coord, 0);
    ivec2 texSize = textureSize(nrd_out_diff_radiance_hitdist, 0);

    vec4 outDiffuseIlluminationAnd2ndMoment;
    vec4 outSpecularIlluminationAnd2ndMoment;

    runRCRS(
        tex_coord,
        texSize,
        centerMaterial,
        outDiffuseIlluminationAnd2ndMoment,
        outSpecularIlluminationAnd2ndMoment
    );

    // RELAX_AntiFirefly.cs.hlsl:209-215 -- write outputs
    nrd_diff_illum_prev_firefly_out = outDiffuseIlluminationAnd2ndMoment;
    nrd_spec_illum_prev_firefly_out = outSpecularIlluminationAnd2ndMoment;
}
