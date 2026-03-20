#ifndef PHOTONICS_NRD_COMMON_GLSL
#define PHOTONICS_NRD_COMMON_GLSL

#include "/photonics/lighttree/nrd_material_id.glsl"

const float PH_NRD_HISTORY_SCALE = 255.0;
const vec3 PH_NRD_LUMA_COEFF = vec3(0.2126, 0.7152, 0.0722);
const float NRD_FP16_MAX = 65504.0;
const float PH_NRD_CONFIDENCE_DISABLED = 0.0;

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

// NRD _NRD_SafeNormalize: rsqrt(lenSq + 1e-9) — additive epsilon, not max
vec3 nrd_safe_normal(vec3 normalValue) {
    float lenSq = dot(normalValue, normalValue);
    return normalValue * inversesqrt(lenSq + 1e-9);
}

vec3 nrd_select_surface_normal(vec3 geometryNormal, vec3 mappedNormal) {
    vec3 safeGeometryNormal = nrd_safe_normal(geometryNormal);
    float mappedLenSq = dot(mappedNormal, mappedNormal);
    if (mappedLenSq <= 1e-6) {
        return safeGeometryNormal;
    }
    return mappedNormal * inversesqrt(mappedLenSq);
}

// NRD: historyLength / 255.0 — no saturate, purely linear
float nrd_encoded_history(float historyLength) {
    return historyLength / PH_NRD_HISTORY_SCALE;
}

// NRD: 255.0 * historyTex — no extra clamp
float nrd_decoded_history(vec4 encodedHistory) {
    return encodedHistory.r * PH_NRD_HISTORY_SCALE;
}

// NRD RELAX_Common.hlsli:105 GetPlaneDistanceWeight_Atrous — binary A-trous variant
// threshold is pre-scaled by caller using viewZ
float nrd_plane_distance_weight(vec3 centerPos, vec3 centerNormal, vec3 samplePos, float threshold) {
    float planeDistance = abs(dot(samplePos - centerPos, centerNormal));
    return planeDistance < threshold ? 1.0 : 0.0;
}

// NRD RELAX_Common.hlsli:98 GetPlaneDistanceWeight — normalized form for temporal/history passes
// Uses abs(dot(dp, n)) / centerViewZ <= threshold
float nrd_plane_distance_weight_normalized(vec3 centerPos, vec3 centerNormal, vec3 samplePos, float centerViewZ, float threshold) {
    float planeDistance = abs(dot(samplePos - centerPos, centerNormal));
    return (planeDistance / max(centerViewZ, 1e-3)) < threshold ? 1.0 : 0.0;
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

// Area-ReSTIR / PathTracer reference writes materialID = 0.f in NRD-facing guide buffers.
const float NRD_DEFAULT_MIN_MATERIAL = 0.0;

float nrd_material_weight_with_min(vec4 currentMaterial, vec4 previousMaterial, float minMaterial) {
    return 1.0;
}

float nrd_material_weight(vec4 currentMaterial, vec4 previousMaterial) {
    return 1.0;
}

float nrd_luminance_weight(float centerLuma, float sampleLuma, float sigma) {
    float lumaSigma = max(sigma, 1e-4);
    float lumaDiff = abs(centerLuma - sampleLuma) / lumaSigma;
    return exp(-min(lumaDiff, 10.0));
}

float nrd_compute_variance(float secondMoment, float mean) {
    return max(secondMoment - mean * mean, 0.0);
}

// NRD.hlsli:516 _NRD_EnvironmentTerm_Rtg — Ray Tracing Gems Chapter 32 Eq 4
// GGX VNDF + Schlick approximation for environment BRDF integral
vec3 nrd_environment_term_rtg(vec3 Rf0, float NoV, float roughness) {
    float m = clamp(roughness * roughness, 0.0, 1.0);

    vec4 X = vec4(1.0, NoV, NoV * NoV, NoV * NoV * NoV);
    vec4 Y = vec4(1.0, m, m * m, m * m * m);

    // M1 (2x2), M2 (3x3) for bias
    float bias = (0.99044 * X.x + -1.28514 * X.y) * Y.x + (1.29678 * X.x + -0.755907 * X.y) * Y.y;
    float biasDenom = (1.0 * X.x + 2.92338 * X.y + 59.4188 * X.w) * Y.x
                    + (20.3225 * X.x + -27.0302 * X.y + 222.592 * X.w) * Y.y
                    + (121.563 * X.x + 626.13 * X.y + 316.627 * X.w) * Y.z;
    bias /= max(biasDenom, 1e-6); // NRD_EPS = 1e-6

    // M3 (2x2), M4 (3x3) for scale
    float scale = (0.0365463 * X.x + 3.32707 * X.y) * Y.x + (9.0632 * X.x + -9.04756 * X.y) * Y.y;
    float scaleDenom = (1.0 * X.x + 3.59685 * X.z + -1.36772 * X.w) * Y.x
                     + (9.04401 * X.x + -16.3174 * X.z + 9.22949 * X.w) * Y.y
                     + (5.56589 * X.x + 19.7886 * X.z + -20.2123 * X.w) * Y.z;
    scale /= max(scaleDenom, 1e-6); // NRD_EPS = 1e-6

    return clamp(Rf0 * scale + bias, vec3(0.0), vec3(1.0));
}

// NRD.hlsli:733 NRD_MaterialFactors — view-dependent demodulation/remodulation
// NRD.hlsli:101,105 — NRD_MATERIAL_FACTOR_MIN_SCALE = 0.02, NRD_ROUGHNESS_FACTOR_MIN_SCALE = 0.1
const float NRD_MATERIAL_FACTOR_MIN_SCALE = 0.02;
const float NRD_ROUGHNESS_FACTOR_MIN_SCALE = 0.1;

void nrd_material_factors(vec3 N, vec3 V, vec3 albedo, vec3 Rf0, float roughness, out vec3 diffFactor, out vec3 specFactor) {
    float NoV = abs(dot(N, V));
    vec3 Fenv = nrd_environment_term_rtg(Rf0, NoV, roughness);

    diffFactor = (vec3(1.0) - Fenv) * albedo;
    diffFactor = mix(vec3(NRD_MATERIAL_FACTOR_MIN_SCALE), vec3(1.0), diffFactor);

    specFactor = Fenv;
    specFactor *= mix(vec3(NRD_ROUGHNESS_FACTOR_MIN_SCALE), vec3(1.0), roughness);
    specFactor = mix(vec3(NRD_MATERIAL_FACTOR_MIN_SCALE), vec3(1.0), specFactor);
}

// Convenience wrappers for diffuse-only and specular-only demodulation
vec3 nrd_compute_diffuse_demodulation(vec3 albedoColor) {
    // Simplified fallback when N/V not available (e.g., GI accumulation)
    return max(albedoColor, vec3(NRD_MATERIAL_FACTOR_MIN_SCALE));
}

vec3 nrd_compute_specular_demodulation(vec3 albedoColor, float metallic) {
    // Simplified fallback when N/V not available
    return max(mix(vec3(0.04), albedoColor, clamp(metallic, 0.0, 1.0)), vec3(NRD_MATERIAL_FACTOR_MIN_SCALE));
}

vec3 nrd_safe_demodulate(vec3 irradiance, vec3 factor) {
    return irradiance / max(factor, vec3(1e-3));
}

vec3 nrd_safe_remodulate(vec3 radiance, vec3 factor) {
    return radiance * max(factor, vec3(1e-3));
}

float nrd_confidence_from_history(float historyLength, float maxHistoryLength) {
    return PH_NRD_CONFIDENCE_DISABLED;
}

float nrd_gradient_to_confidence(vec3 previousRadiance, vec3 currentRadiance, float historyLength, float maxHistoryLength) {
    return PH_NRD_CONFIDENCE_DISABLED;
}

float nrd_hit_distance_confidence(float hitDistance, float viewDistance) {
    return PH_NRD_CONFIDENCE_DISABLED;
}

struct NrdDirectSignal {
    vec3 radiance;
    float hitDistance;
};

struct NrdDirectHistorySample {
    vec3 radiance;
    float secondMoment;
};


// NRD.hlsli RELAX_FrontEnd_PackRadianceAndHitDist: check invalid FIRST, then clamp to FP16 range
vec4 nrd_pack_direct_signal(vec3 radiance, float hitDistance) {
    // NRD order: zero invalid values first, then clamp to [0, FP16_MAX]
    radiance = mix(radiance, vec3(0.0), vec3(any(isnan(radiance)) || any(isinf(radiance)) ? 1.0 : 0.0));
    radiance = clamp(radiance, vec3(0.0), vec3(NRD_FP16_MAX));
    hitDistance = isnan(hitDistance) || isinf(hitDistance) ? 0.0 : hitDistance;
    hitDistance = clamp(hitDistance, 0.0, NRD_FP16_MAX);
    return vec4(radiance, hitDistance);
}

// NRD RELAX unpack is passthrough — no clamping
NrdDirectSignal nrd_unpack_direct_signal(vec4 encodedSignal) {
    return NrdDirectSignal(encodedSignal.rgb, encodedSignal.a);
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
