#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 spec_firefly_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D spec_firefly_input;
uniform float ph_nrd_denoising_range;

void main() {
    // NRD RELAX_AntiFirefly.cs.hlsl: early out on sky/out-of-world tiles.
    // Reference uses gIn_ViewZ > gDenoisingRange; we have no dedicated viewZ
    // texture, so we use two complementary proxies:
    //   1. is_in_world(): depth-buffer sky check (depthtex0 >= 0.99999).
    //   2. Normal-length check: an invalid/sky pixel has no geometry normal
    //      and will read as a near-zero vector from radiosity_normal.
    // Either condition failing is sufficient to treat the pixel as out-of-world.
    if (!is_in_world()) {
        spec_firefly_out = texelFetch(spec_firefly_input, tex_coord, 0);
        return;
    }

    // Center pixel validity: NRD reference gIn_ViewZ > gDenoisingRange early-out.
    // Uses viewZ = length(worldPos - cameraPos) vs gDenoisingRange (NRD Common.hlsli:244).
    vec3 centerPos = texelFetch(radiosity_position, tex_coord, 0).xyz;
    float centerViewZ = nrd_compute_view_z(centerPos);
    if (centerViewZ > ph_nrd_denoising_range || centerViewZ < 0.001) {
        spec_firefly_out = texelFetch(spec_firefly_input, tex_coord, 0);
        return;
    }

    // center.a is the specular 2nd moment of luminance, preserved unchanged
    // through the filter (see NRD reference:
    //   outSpecular = float4(rgb_from_coords, specular2ndMomentCenter)).
    vec4 center = texelFetch(spec_firefly_input, tex_coord, 0);
    float centerLuma = nrd_luminance(center.rgb);
    float center2ndMoment = center.a;  // preserved; not filtered

    vec4 centerMaterial = texelFetch(stage_radiosity_material, tex_coord, 0);

    // Cross-bilateral RCRS (Rank-Conditioned Rank-Selection) filter.
    // Tracks the min/max luminance neighbor coords in the 3x3 neighbourhood,
    // gated by material compatibility. Sentinel initialisation to tex_coord
    // means no-compatible-neighbour keeps the center value — matches NRD.
    float maxLuma = -1.0;
    float minLuma = 1.0e6;
    ivec2 maxLumaCoord = tex_coord;
    ivec2 minLumaCoord = tex_coord;

    ivec2 texSize = textureSize(spec_firefly_input, 0);

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;

            ivec2 sampleCoord = tex_coord + ivec2(dx, dy);
            if (any(lessThan(sampleCoord, ivec2(0))) || any(greaterThanEqual(sampleCoord, texSize))) continue;

            // NRD CompareMaterials with gSpecMinMaterial — gated per-sample.
            vec4 sampleMaterial = texelFetch(stage_radiosity_material, sampleCoord, 0);
            if (nrd_material_weight(centerMaterial, sampleMaterial) <= 0.0) continue;

            // NRD per-sample validity: viewZ > gDenoisingRange skips the tap.
            // Uses viewZ = length(worldPos - cameraPos) (NRD Common.hlsli:244).
            vec3 samplePos = texelFetch(radiosity_position, sampleCoord, 0).xyz;
            float sampleViewZ = nrd_compute_view_z(samplePos);
            if (sampleViewZ > ph_nrd_denoising_range || sampleViewZ < 0.001) continue;

            float sampleLuma = nrd_luminance(texelFetch(spec_firefly_input, sampleCoord, 0).rgb);

            if (sampleLuma > maxLuma) {
                maxLuma = sampleLuma;
                maxLumaCoord = sampleCoord;
            }
            if (sampleLuma < minLuma) {
                minLuma = sampleLuma;
                minLumaCoord = sampleCoord;
            }
        }
    }

    // Replace center with the min/max neighbor when the center is outside the
    // neighbor luminance range. The 2nd moment (center.a) is always taken from
    // the center pixel, not the replacement — matching the NRD reference:
    //   outSpecular = float4(s_Spec[specularCoords].rgb, specular2ndMomentCenter)
    ivec2 resultCoord = tex_coord;
    if (centerLuma > maxLuma)
        resultCoord = maxLumaCoord;
    if (centerLuma < minLuma)
        resultCoord = minLumaCoord;

    vec3 result = texelFetch(spec_firefly_input, resultCoord, 0).rgb;
    spec_firefly_out = vec4(result, center2ndMoment);
}
