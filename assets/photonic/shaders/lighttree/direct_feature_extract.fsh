#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 material_frag_out;
layout(location = 1) out vec4 direct_confidence_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

uniform sampler2D prev_direct_noisy_input;
uniform sampler2D prev_direct_confidence_input;

vec4 ph_extract_material(vec2 uv) {
    vec4 spec = texture(specular, uv);
    float smoothness = clamp(spec.r, 0.0, 1.0);
    float roughness = clamp(1.0 - smoothness, 0.0, 1.0);
    float metallic = clamp(spec.g, 0.0, 1.0);
    float emission = clamp(spec.a, 0.0, 1.0);
    return vec4(roughness, metallic, emission, smoothness);
}

ivec2 ph_clamp_previous_uv(vec2 previousPixel, ivec2 textureSizeValue) {
    return clamp(ivec2(previousPixel), ivec2(0), textureSizeValue - 1);
}

// NRD-compatible confidence: scalar [0,1] derived from temporal luminance gradient
// Reference: ConfidencePass.hlsl - confidence = saturate(1.0 - colorGradient / normalGradient)
// We approximate: confidence = 1 - abs(currentLuma - prevLuma) / max(currentLuma, prevLuma, epsilon)
// Then apply sensitivity power and temporal blend.
const float nrd_confidence_sensitivity = 2.0;
const float nrd_confidence_blend_factor = 0.5;
const float nrd_confidence_blend_power = 0.25;

float ph_compute_nrd_confidence(vec3 currentRadiance, vec3 previousRadiance, float previousConfidence, bool hasPrevious) {
    float currentLuma = nrd_luminance(currentRadiance);
    float previousLuma = nrd_luminance(previousRadiance);

    // Gradient-based confidence (approximates NRD's gradient ratio)
    float gradientRatio = abs(currentLuma - previousLuma) / max(max(currentLuma, previousLuma), 0.01);
    float confidence = clamp(1.0 - gradientRatio, 0.0, 1.0);
    confidence = clamp(pow(confidence, nrd_confidence_sensitivity), 0.0, 1.0);

    // Temporal blend in non-linear space (NRD ConfidencePass lines 75-93)
    if (hasPrevious) {
        float currNL = pow(confidence, nrd_confidence_blend_power);
        float prevNL = pow(clamp(previousConfidence, 0.0, 1.0), nrd_confidence_blend_power);
        float blended = mix(prevNL, currNL, nrd_confidence_blend_factor);
        confidence = pow(clamp(blended, 0.0, 1.0), 1.0 / nrd_confidence_blend_power);
    }

    return confidence;
}

void main() {
    if (!is_in_world()) {
        material_frag_out = vec4(0.0);
        direct_confidence_frag_out = vec4(0.0);
        return;
    }

    vec3 stagePosition = texelFetch(stage_radiosity_position, tex_coord, 0).xyz;
    vec3 stageGeometryNormal = texelFetch(stage_radiosity_normal, tex_coord, 0).xyz;
    vec3 stageMappedNormal = texelFetch(stage_radiosity_mapped_normal, tex_coord, 0).xyz;
    vec3 reprojectionNormal = nrd_select_surface_normal(stageGeometryNormal, stageMappedNormal);
    vec2 uv = (vec2(tex_coord) + vec2(0.5)) / vec2(viewWidth, viewHeight);
    vec2 previousPixel = ph_reprojectf(
        previous_modelview_projection,
        stagePosition + normalize(reprojectionNormal) * 0.01,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    );
    ivec2 previousUv = ph_clamp_previous_uv(previousPixel, textureSize(prev_radiosity_direct, 0));
    bool hasPreviousSample = all(greaterThanEqual(previousPixel, vec2(0.0)))
        && all(lessThan(previousPixel, vec2(viewWidth, viewHeight)));

    material_frag_out = ph_extract_material(uv);

    NrdDirectSignal currentDirectSignal = nrd_unpack_direct_signal(texelFetch(stage_radiosity_direct, tex_coord, 0));
    NrdDirectSignal previousDirectSignal = hasPreviousSample
        ? nrd_unpack_direct_signal(texelFetch(prev_direct_noisy_input, previousUv, 0))
        : NrdDirectSignal(vec3(0.0), 0.0);

    // Read previous confidence for temporal blend
    vec4 prevConfidenceVec = hasPreviousSample
        ? texelFetch(prev_direct_confidence_input, previousUv, 0)
        : vec4(0.0);

    float diffuseConfidence = ph_compute_nrd_confidence(
        currentDirectSignal.radiance,
        previousDirectSignal.radiance,
        prevConfidenceVec.r,
        hasPreviousSample
    );

    // For now, specular confidence mirrors diffuse (until specular signal split is fully wired)
    float specularConfidence = diffuseConfidence;

    direct_confidence_frag_out = vec4(diffuseConfidence, specularConfidence, 0.0, 0.0);
}
