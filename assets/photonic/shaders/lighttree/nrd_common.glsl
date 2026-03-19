#ifndef PHOTONICS_NRD_COMMON_GLSL
#define PHOTONICS_NRD_COMMON_GLSL

const float PH_NRD_HISTORY_SCALE = 255.0;
const vec3 PH_NRD_LUMA_COEFF = vec3(0.2126, 0.7152, 0.0722);
const float NRD_FP16_MAX = 65504.0;

float nrd_luminance(vec3 value) {
    return dot(value, PH_NRD_LUMA_COEFF);
}

// NRD.hlsli STL::Color::LinearToYCoCg (NRD.hlsli:396-412)
vec3 nrd_rgb_to_ycocg(vec3 value) {
    float y  = dot(value, vec3(0.25, 0.5, 0.25));
    float co = dot(value, vec3(0.5, 0.0, -0.5));
    float cg = dot(value, vec3(-0.25, 0.5, -0.25));
    return vec3(y, co, cg);
}

// NRD.hlsli STL::Color::YCoCgToLinear — clamps to >= 0 to match NRD inverse
vec3 nrd_ycocg_to_rgb(vec3 value) {
    float t = value.x - value.z;
    float g = value.x + value.z;
    float b = t - value.y;
    float r = t + value.y;
    return max(vec3(r, g, b), vec3(0.0));
}

float nrd_saturate(float value) {
    return clamp(value, 0.0, 1.0);
}

vec3 nrd_saturate(vec3 value) {
    return clamp(value, vec3(0.0), vec3(1.0));
}

// NRD epsilon-normalize: no fallback direction, matches NRD's Math::SafeNormalize
vec3 nrd_safe_normal(vec3 normalValue) {
    float lenSq = dot(normalValue, normalValue);
    return normalValue * inversesqrt(max(lenSq, 1e-6));
}

vec3 nrd_select_surface_normal(vec3 geometryNormal, vec3 mappedNormal) {
    vec3 safeGeometryNormal = nrd_safe_normal(geometryNormal);
    float mappedLenSq = dot(mappedNormal, mappedNormal);
    if (mappedLenSq <= 1e-6) {
        return safeGeometryNormal;
    }
    return mappedNormal * inversesqrt(mappedLenSq);
}

float nrd_encoded_history(float historyLength) {
    return nrd_saturate(historyLength / PH_NRD_HISTORY_SCALE);
}

float nrd_decoded_history(vec4 encodedHistory) {
    return clamp(encodedHistory.r * PH_NRD_HISTORY_SCALE, 0.0, PH_NRD_HISTORY_SCALE);
}

// Plane distance uses view-Z semantics; threshold is pre-scaled by caller using viewZ
float nrd_plane_distance_weight(vec3 centerPos, vec3 centerNormal, vec3 samplePos, float threshold) {
    float planeDistance = abs(dot(samplePos - centerPos, centerNormal));
    return planeDistance < threshold ? 1.0 : 0.0;
}

// Normal weight floor matches NRD RELAX_HistoryFix.cs.hlsl:21
float nrd_normal_weight(vec3 centerNormal, vec3 sampleNormal, float powerValue) {
    float normalDot = max(dot(centerNormal, sampleNormal), 0.0);
    return pow(max(normalDot, 0.01), powerValue);
}

// Reference NRD SmoothStep-based weight: Math::SmoothStep(1.0, 0.0, |x * px + py|)
float nrd_compute_weight(float x, float px, float py) {
    float t = clamp(1.0 - abs(x * px + py), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

// Reference: GetSpecLobeTanHalfAngle(roughness, percentOfVolume)
float nrd_spec_lobe_tan_half_angle(float roughness, float percentOfVolume) {
    roughness = clamp(roughness, 0.0, 1.0);
    percentOfVolume = clamp(percentOfVolume, 0.0, 1.0);
    return roughness * roughness * percentOfVolume / (1.0 - percentOfVolume + 1e-6);
}

// Reference: GetNormalWeightParam2(roughness, angleFraction)
// Returns 1.0 / cutoffAngle for use with nrd_compute_weight
float nrd_normal_weight_param(float roughness, float angleFraction) {
    float angle = atan(nrd_spec_lobe_tan_half_angle(roughness, angleFraction));
    return 1.0 / max(angle, 1.5 / 255.0);
}

// Angle-based normal weight matching reference RELAX_Atrous diffuse path:
// ComputeWeight(acos(dot(n0, n1)), normalWeightParam, 0.0)
float nrd_normal_weight_atrous(vec3 centerNormal, vec3 sampleNormal, float normalWeightParam) {
    float cosAngle = clamp(dot(centerNormal, sampleNormal), -1.0, 1.0);
    float angle = acos(cosAngle);
    return nrd_compute_weight(angle, normalWeightParam, 0.0);
}

// NRD Common.hlsli:239 CompareMaterials: binary material ID comparison.
// Roughness channel used as material discriminator (proxy for NRD's materialID from normal/roughness pack).
float nrd_material_weight(vec4 currentMaterial, vec4 previousMaterial) {
    float roughnessDelta = abs(currentMaterial.x - previousMaterial.x);
    return roughnessDelta < 0.02 ? 1.0 : 0.0;
}

float nrd_luminance_weight(float centerLuma, float sampleLuma, float sigma) {
    float lumaSigma = max(sigma, 1e-4);
    float lumaDiff = abs(centerLuma - sampleLuma) / lumaSigma;
    return exp(-min(lumaDiff, 10.0));
}

float nrd_compute_variance(float secondMoment, float mean) {
    return max(secondMoment - mean * mean, 0.0);
}

// TODO: exact NRD demodulation is view-dependent (uses BRDF/FG tables); this is a simplified approximation.
vec3 nrd_compute_diffuse_demodulation(vec3 albedoColor) {
    return max(albedoColor, vec3(0.04));
}

// TODO: exact NRD specular demodulation is view-dependent (uses BRDF/FG tables); this is a simplified approximation.
vec3 nrd_compute_specular_demodulation(vec3 albedoColor, float metallic) {
    return max(mix(vec3(0.04), albedoColor, clamp(metallic, 0.0, 1.0)), vec3(0.04));
}

vec3 nrd_safe_demodulate(vec3 irradiance, vec3 factor) {
    return irradiance / max(factor, vec3(1e-3));
}

vec3 nrd_safe_remodulate(vec3 radiance, vec3 factor) {
    return radiance * max(factor, vec3(1e-3));
}

float nrd_confidence_from_history(float historyLength, float maxHistoryLength) {
    return clamp(historyLength / max(maxHistoryLength, 1.0), 0.0, 1.0);
}

float nrd_gradient_to_confidence(vec3 previousRadiance, vec3 currentRadiance, float historyLength, float maxHistoryLength) {
    float prevLuma = max(nrd_luminance(previousRadiance), 0.02);
    float currLuma = max(nrd_luminance(currentRadiance), 0.02);
    float gradient = abs(currLuma - prevLuma) / max(max(prevLuma, currLuma), 1e-3);
    float gradientConfidence = 1.0 - clamp(gradient * 1.5, 0.0, 1.0);
    float historyConfidence = nrd_confidence_from_history(historyLength, maxHistoryLength);
    return min(historyConfidence, gradientConfidence);
}

// Project-specific: no NRD counterpart. Kept for internal use only.
float nrd_hit_distance_confidence(float hitDistance, float viewDistance) {
    if (hitDistance <= 0.0) {
        return 0.0;
    }
    float normalized = hitDistance / max(viewDistance, 1.0);
    return 1.0 / (1.0 + normalized);
}

struct NrdDirectSignal {
    vec3 radiance;
    float hitDistance;
};

struct NrdDirectHistorySample {
    vec3 radiance;
    float secondMoment;
};


// NRD.hlsli RELAX_FrontEnd_PackRadianceAndHitDist: sanitize NaN/Inf, clamp to FP16 range
vec4 nrd_pack_direct_signal(vec3 radiance, float hitDistance) {
    radiance = clamp(radiance, vec3(0.0), vec3(NRD_FP16_MAX));
    radiance = mix(radiance, vec3(0.0), vec3(any(isnan(radiance)) || any(isinf(radiance)) ? 1.0 : 0.0));
    hitDistance = clamp(hitDistance, 0.0, NRD_FP16_MAX);
    hitDistance = isnan(hitDistance) || isinf(hitDistance) ? 0.0 : hitDistance;
    return vec4(radiance, hitDistance);
}

NrdDirectSignal nrd_unpack_direct_signal(vec4 encodedSignal) {
    return NrdDirectSignal(max(encodedSignal.rgb, vec3(0.0)), max(encodedSignal.a, 0.0));
}

float nrd_direct_second_moment(vec3 radiance) {
    float luma = nrd_luminance(max(radiance, vec3(0.0)));
    return luma * luma;
}

// NRD writes raw float4 values; no clamping applied
vec4 nrd_pack_direct_history(vec3 radiance, float secondMoment) {
    return vec4(radiance, secondMoment);
}

// NRD reads raw float4 values; no clamping applied
NrdDirectHistorySample nrd_unpack_direct_history(vec4 encodedHistory) {
    return NrdDirectHistorySample(encodedHistory.rgb, encodedHistory.a);
}

// NRD: no clamping, raw radiance + luminance^2
NrdDirectHistorySample nrd_direct_history_from_radiance(vec3 radiance) {
    return NrdDirectHistorySample(radiance, nrd_direct_second_moment(radiance));
}


vec4 nrd_mix_direct_history(vec4 previousHistory, NrdDirectHistorySample currentHistory, float blendAlpha) {
    NrdDirectHistorySample previous = nrd_unpack_direct_history(previousHistory);
    float alpha = nrd_saturate(blendAlpha);
    vec3 radiance = mix(previous.radiance, currentHistory.radiance, alpha);
    float secondMoment = mix(previous.secondMoment, currentHistory.secondMoment, alpha);
    return nrd_pack_direct_history(radiance, secondMoment);
}

#endif
