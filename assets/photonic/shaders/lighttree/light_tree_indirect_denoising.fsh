#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 indirect_denoised_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

const float phi_luminance = 4.0;
const float phi_normal = 128.0;
const float phi_position = 1.0;
const int step_size = 2;

float denoiser_luminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
    if (!is_in_world()) {
        indirect_denoised_out = vec4(0.0);
        return;
    }

    vec4 centerData = texelFetch(radiosity_indirect, tex_coord, 0);
    if (ph_debug_disable_denoiser > 0.5) {
        indirect_denoised_out = centerData;
        return;
    }
    vec3 centerColor = centerData.rgb;
    float centerHistory = centerData.a;

    if (centerHistory <= 0.0) {
        indirect_denoised_out = vec4(0.0);
        return;
    }

    vec3 centerPosition = texelFetch(radiosity_position, tex_coord, 0).xyz;
    vec3 centerGeometryNormal = texelFetch(radiosity_normal, tex_coord, 0).xyz;
    vec3 centerMappedNormal = nrd_select_surface_normal(
        centerGeometryNormal,
        texelFetch(radiosity_mapped_normal, tex_coord, 0).xyz
    );
    float centerLuma = denoiser_luminance(centerColor);

    vec4 varianceData = texelFetch(radiosity_indirect_variance, tex_coord, 0);
    float variance = max(varianceData.z, 1e-6);
    float confidence = varianceData.w;
    float filterStrength = mix(1.0, 0.1, confidence);

    float sumWeight = 1.0;
    vec3 sumColor = centerColor;

    ivec2 textureSizeValue = textureSize(radiosity_indirect, 0);

    for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
            if (dx == 0 && dy == 0) {
                continue;
            }

            ivec2 sampleCoord = tex_coord + ivec2(dx, dy) * step_size;
            if (any(lessThan(sampleCoord, ivec2(0))) || any(greaterThanEqual(sampleCoord, textureSizeValue))) {
                continue;
            }

            vec4 sampleData = texelFetch(radiosity_indirect, sampleCoord, 0);
            if (sampleData.a <= 0.0) {
                continue;
            }

            vec3 samplePosition = texelFetch(radiosity_position, sampleCoord, 0).xyz;
            vec3 sampleMappedNormal = nrd_select_surface_normal(
                texelFetch(radiosity_normal, sampleCoord, 0).xyz,
                texelFetch(radiosity_mapped_normal, sampleCoord, 0).xyz
            );
            float normalDot = max(dot(centerMappedNormal, sampleMappedNormal), 0.0);
            float normalWeight = pow(normalDot, phi_normal);
            if (normalWeight < 0.01) {
                continue;
            }

            float planeDistance = abs(dot(samplePosition - centerPosition, centerGeometryNormal));
            float positionWeight = exp(-planeDistance / max(phi_position, 1e-4));
            float sampleLuma = denoiser_luminance(sampleData.rgb);
            float lumaDiff = abs(centerLuma - sampleLuma);
            float lumaWeight = exp(-lumaDiff / max(phi_luminance * sqrt(variance), 1e-4));
            float kernelDistance = length(vec2(dx, dy));
            float kernelWeight = exp(-kernelDistance * 0.5);
            float weight = normalWeight * positionWeight * lumaWeight * kernelWeight * filterStrength;
            if (weight < 1e-4) {
                continue;
            }

            sumColor += sampleData.rgb * weight;
            sumWeight += weight;
        }
    }

    vec3 denoisedRadiance = sumColor / sumWeight;
    vec3 centerAlbedo = clamp(texelFetch(radiosity_albedo, tex_coord, 0).rgb, vec3(0.04), vec3(1.0));
    indirect_denoised_out = vec4(nrd_safe_remodulate(denoisedRadiance, nrd_compute_diffuse_demodulation(centerAlbedo)), centerHistory);
}
