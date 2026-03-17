#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 nrd_anti_firefly_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D nrd_anti_firefly_input;

void main() {
    vec4 center = texelFetch(nrd_anti_firefly_input, tex_coord, 0);
    float centerLuma = nrd_luminance(center.rgb);

    float maxLuma = -1.0;
    float minLuma = 1000000.0;
    vec3 maxColor = center.rgb;
    vec3 minColor = center.rgb;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) {
                continue;
            }

            ivec2 sampleCoord = tex_coord + ivec2(dx, dy);
            vec3 sampleColor = texelFetch(nrd_anti_firefly_input, sampleCoord, 0).rgb;
            float sampleLuma = nrd_luminance(sampleColor);

            if (sampleLuma > maxLuma) {
                maxLuma = sampleLuma;
                maxColor = sampleColor;
            }

            if (sampleLuma < minLuma) {
                minLuma = sampleLuma;
                minColor = sampleColor;
            }
        }
    }

    // Luminance-preserving clamping: scale the center color to match the
    // clamped luminance instead of replacing with a neighbor's color (which
    // would corrupt the hue/chroma from stochastic light tree sampling).
    vec3 result = center.rgb;
    float clampedLuma = clamp(centerLuma, minLuma, maxLuma);
    if (centerLuma > 1e-6) {
        result = center.rgb * (clampedLuma / centerLuma);
    } else if (centerLuma < minLuma) {
        result = minColor;
    }

    nrd_anti_firefly_out = vec4(max(result, vec3(0.0)), center.a);
}
