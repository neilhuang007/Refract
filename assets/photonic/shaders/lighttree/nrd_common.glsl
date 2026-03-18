#ifndef PHOTONICS_NRD_COMMON_GLSL
#define PHOTONICS_NRD_COMMON_GLSL

const float PH_NRD_HISTORY_SCALE = 63.0;
const vec3 PH_NRD_LUMA_COEFF = vec3(0.2126, 0.7152, 0.0722);

float nrd_luminance(vec3 value) {
    return dot(value, PH_NRD_LUMA_COEFF);
}

vec3 nrd_rgb_to_ycocg(vec3 value) {
    float co = value.r - value.b;
    float t = value.b + co * 0.5;
    float cg = value.g - t;
    float y = t + cg * 0.5;
    return vec3(y, co, cg);
}

vec3 nrd_ycocg_to_rgb(vec3 value) {
    float t = value.x - value.z * 0.5;
    float g = value.z + t;
    float b = t - value.y * 0.5;
    float r = value.y + b;
    return vec3(r, g, b);
}

float nrd_saturate(float value) {
    return clamp(value, 0.0, 1.0);
}

vec3 nrd_saturate(vec3 value) {
    return clamp(value, vec3(0.0), vec3(1.0));
}

vec3 nrd_safe_normal(vec3 normalValue) {
    float lenSq = dot(normalValue, normalValue);
    if (lenSq <= 1e-6) {
        return vec3(0.0, 1.0, 0.0);
    }
    return normalValue * inversesqrt(lenSq);
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

float nrd_plane_distance_weight(vec3 centerPos, vec3 centerNormal, vec3 samplePos, float depthThreshold) {
    float centerDistance = max(length(centerPos - world_camera_position), 1e-3);
    float planeDistance = abs(dot(samplePos - centerPos, centerNormal));
    float threshold = depthThreshold * centerDistance;
    return planeDistance < threshold ? 1.0 : 0.0;
}

float nrd_normal_weight(vec3 centerNormal, vec3 sampleNormal, float powerValue) {
    float normalDot = max(dot(centerNormal, sampleNormal), 0.0);
    return pow(max(normalDot, 1e-4), powerValue);
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

float nrd_material_weight(vec4 currentMaterial, vec4 previousMaterial) {
    float roughnessDelta = abs(currentMaterial.x - previousMaterial.x);
    float metallicDelta = abs(currentMaterial.y - previousMaterial.y);
    float emissionDelta = abs(currentMaterial.z - previousMaterial.z);
    float smoothnessDelta = abs(currentMaterial.w - previousMaterial.w);
    float delta = roughnessDelta + 0.5 * metallicDelta + 0.25 * emissionDelta + 0.125 * smoothnessDelta;
    return 1.0 - nrd_saturate(delta / 0.35);
}

float nrd_luminance_weight(float centerLuma, float sampleLuma, float sigma) {
    float lumaSigma = max(sigma, 1e-4);
    float lumaDiff = abs(centerLuma - sampleLuma) / lumaSigma;
    return exp(-min(lumaDiff, 10.0));
}

float nrd_compute_variance(float secondMoment, float mean) {
    return max(secondMoment - mean * mean, 1e-6);
}

vec3 nrd_compute_diffuse_demodulation(vec3 albedoColor) {
    return max(albedoColor, vec3(0.04));
}

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

struct NrdDirectFeatures {
    float hitDistance;
    float hitDistanceWeight;
    float temporalStability;
    float accumulationSpeed;
};

vec4 nrd_pack_direct_signal(vec3 radiance, float hitDistance) {
    return vec4(max(radiance, vec3(0.0)), max(hitDistance, 0.0));
}

NrdDirectSignal nrd_unpack_direct_signal(vec4 encodedSignal) {
    return NrdDirectSignal(max(encodedSignal.rgb, vec3(0.0)), max(encodedSignal.a, 0.0));
}

float nrd_direct_second_moment(vec3 radiance) {
    float luma = nrd_luminance(max(radiance, vec3(0.0)));
    return luma * luma;
}

vec4 nrd_pack_direct_history(vec3 radiance, float secondMoment) {
    float clampedSecondMoment = max(secondMoment, nrd_direct_second_moment(radiance));
    return vec4(max(radiance, vec3(0.0)), clampedSecondMoment);
}

NrdDirectHistorySample nrd_unpack_direct_history(vec4 encodedHistory) {
    vec3 radiance = max(encodedHistory.rgb, vec3(0.0));
    float secondMoment = max(encodedHistory.a, nrd_direct_second_moment(radiance));
    return NrdDirectHistorySample(radiance, secondMoment);
}

NrdDirectHistorySample nrd_direct_history_from_radiance(vec3 radiance) {
    return NrdDirectHistorySample(max(radiance, vec3(0.0)), nrd_direct_second_moment(radiance));
}

vec4 nrd_pack_direct_features(float hitDistance, float hitDistanceWeight, float temporalStability, float accumulationSpeed) {
    return vec4(
        max(hitDistance, 0.0),
        nrd_saturate(hitDistanceWeight),
        nrd_saturate(temporalStability),
        nrd_saturate(accumulationSpeed)
    );
}

NrdDirectFeatures nrd_unpack_direct_features(vec4 encodedFeatures) {
    return NrdDirectFeatures(
        max(encodedFeatures.x, 0.0),
        nrd_saturate(encodedFeatures.y),
        nrd_saturate(encodedFeatures.z),
        nrd_saturate(encodedFeatures.w)
    );
}

vec4 nrd_mix_direct_history(vec4 previousHistory, NrdDirectHistorySample currentHistory, float blendAlpha) {
    NrdDirectHistorySample previous = nrd_unpack_direct_history(previousHistory);
    float alpha = nrd_saturate(blendAlpha);
    vec3 radiance = mix(previous.radiance, currentHistory.radiance, alpha);
    float secondMoment = mix(previous.secondMoment, currentHistory.secondMoment, alpha);
    return nrd_pack_direct_history(radiance, secondMoment);
}

