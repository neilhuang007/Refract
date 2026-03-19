#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 spec_firefly_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D spec_firefly_input;

void main() {
    vec4 center = texelFetch(spec_firefly_input, tex_coord, 0);

    // NRD RELAX: skip anti-firefly for pixels beyond denoising range (viewZ > gDenoisingRange).
    // Approximate with normal validity.
    vec3 centerNorm = texelFetch(radiosity_normal, tex_coord, 0).xyz;
    if (dot(centerNorm, centerNorm) < 0.01) {
        spec_firefly_out = center;
        return;
    }

    float centerLuma = nrd_luminance(center.rgb);

    vec4 centerMaterial = texelFetch(stage_radiosity_material, tex_coord, 0);

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
            vec4 sampleMaterial = texelFetch(stage_radiosity_material, sampleCoord, 0);
            if (nrd_material_weight(centerMaterial, sampleMaterial) <= 0.0) continue;
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

    // Replace center with min or max neighbor if it's outside the neighbor range.
    ivec2 resultCoord = tex_coord;
    if (centerLuma > maxLuma)
        resultCoord = maxLumaCoord;
    if (centerLuma < minLuma)
        resultCoord = minLumaCoord;

    vec3 result = texelFetch(spec_firefly_input, resultCoord, 0).rgb;
    spec_firefly_out = vec4(result, center.a);
}
