#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 direct_firefly_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D direct_firefly_input;

void main() {
    vec4 center = texelFetch(direct_firefly_input, tex_coord, 0);
    float centerLuma = nrd_luminance(center.rgb);

    float maxLuma = centerLuma;
    float minLuma = centerLuma;
    vec3 minColor = center.rgb;

    ivec2 texSize = textureSize(direct_firefly_input, 0);

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) {
                continue;
            }

            ivec2 sampleCoord = clamp(tex_coord + ivec2(dx, dy), ivec2(0), texSize - 1);
            vec3 sampleColor = texelFetch(direct_firefly_input, sampleCoord, 0).rgb;
            float sampleLuma = nrd_luminance(sampleColor);
            maxLuma = max(maxLuma, sampleLuma);
            if (sampleLuma < minLuma) {
                minLuma = sampleLuma;
                minColor = sampleColor;
            }
        }
    }

    vec3 result = center.rgb;
    float clampedLuma = clamp(centerLuma, minLuma, maxLuma);
    if (centerLuma > 1e-6) {
        result = center.rgb * (clampedLuma / centerLuma);
    } else if (centerLuma < minLuma) {
        result = minColor;
    }

    direct_firefly_out = vec4(max(result, vec3(0.0)), center.a);
}
