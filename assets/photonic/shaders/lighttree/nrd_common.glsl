#ifndef PHOTONICS_NRD_COMMON_GLSL
#define PHOTONICS_NRD_COMMON_GLSL

#include "/photonics/lighttree/nrd_material_id.glsl"

#ifndef PH_RESTIR_CHECKERBOARD_DECLARED
#define PH_RESTIR_CHECKERBOARD_DECLARED
uniform int ph_restir_active_checkerboard_field;
#endif

const float PH_NRD_HISTORY_SCALE = 255.0;
const vec3 PH_NRD_LUMA_COEFF = vec3(0.2126, 0.7152, 0.0722);
const float NRD_FP16_MAX = 65504.0;

bool nrd_is_active_checkerboard_pixel(ivec2 pixelPosition, bool previousFrame, int activeCheckerboardField) {
    if (activeCheckerboardField == 0) {
        return true;
    }
    return ((pixelPosition.x + pixelPosition.y + int(previousFrame)) & 1) == (activeCheckerboardField & 1);
}

void nrd_activate_checkerboard_pixel(inout ivec2 pixelPos, bool previousFrame, int activeCheckerboardField) {
    if (nrd_is_active_checkerboard_pixel(pixelPos, previousFrame, activeCheckerboardField)) {
        return;
    }

    if (previousFrame) {
        pixelPos.x += activeCheckerboardField * 2 - 3;
    } else {
        pixelPos.x += ((pixelPos.y & 1) != 0) ? 1 : -1;
    }
}

ivec2 nrd_get_checkerboard_owner_pixel(ivec2 pixelPosition, bool previousFrame, int activeCheckerboardField, ivec2 textureSizePx) {
    ivec2 ownerPixel = pixelPosition;
    nrd_activate_checkerboard_pixel(ownerPixel, previousFrame, activeCheckerboardField);
    return clamp(ownerPixel, ivec2(0), textureSizePx - ivec2(1));
}

ivec2 nrd_get_current_checkerboard_owner_pixel(ivec2 pixelPosition, ivec2 textureSizePx) {
    return nrd_get_checkerboard_owner_pixel(pixelPosition, false, ph_restir_active_checkerboard_field, textureSizePx);
}

ivec2 nrd_get_previous_checkerboard_owner_pixel(ivec2 pixelPosition, ivec2 textureSizePx) {
    return nrd_get_checkerboard_owner_pixel(pixelPosition, true, ph_restir_active_checkerboard_field, textureSizePx);
}

vec4 nrd_reconstruct_checkerboard_signal(sampler2D signalTex, ivec2 coord, sampler2D positionTex, sampler2D normalTex) {
    ivec2 texSize = textureSize(signalTex, 0);
    ivec2 sampleCoord = nrd_get_current_checkerboard_owner_pixel(coord, texSize);
    return texelFetch(signalTex, sampleCoord, 0);
}

float nrd_luminance(vec3 value) {
    return dot(value, PH_NRD_LUMA_COEFF);
}

// NRD Common.hlsli:244 UnpackViewZ — compute linear view-space depth from world position
float nrd_compute_view_z(vec3 worldPos) {
    return length(worldPos - world_camera_position);
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

// NRD Common.hlsli:499 GetRoughnessWeightParams
const float NRD_ROUGHNESS_SENSITIVITY = 0.01;

vec2 nrd_roughness_weight_params(float roughness, float fraction) {
    float a = 1.0 / mix(NRD_ROUGHNESS_SENSITIVITY, 1.0, clamp(roughness * fraction, 0.0, 1.0));
    float b = roughness * a;
    return vec2(a, -b);
}

// NRD RELAX_Common.hlsli:122 GetNormalWeightParams_ATrous
// Returns vec2(angle, f) for specular normal weight with roughness-aware cone
vec2 nrd_spec_normal_weight_params_atrous(
    float roughness, float numFramesInHistory, float specReprojConfidence,
    float normalEdgeStoppingRelaxation, float lobeAngleFraction, float lobeAngleSlack
) {
    float relaxation = clamp(numFramesInHistory / 5.0, 0.0, 1.0);
    relaxation *= mix(1.0, specReprojConfidence, normalEdgeStoppingRelaxation);
    float f = 0.9 + 0.1 * relaxation;
    float angle = atan(nrd_spec_lobe_tan_half_angle(roughness, lobeAngleFraction));
    angle *= 10.0 - 9.0 * relaxation;
    angle += lobeAngleSlack;
    const float HALF_PI = 1.5707963;
    angle = min(HALF_PI, angle);
    return vec2(angle, f);
}

// NRD RELAX_Common.hlsli:143 GetSpecularNormalWeight_ATrous
// Uses min of normal dot and view dot for specular lobe awareness
float nrd_spec_normal_weight_atrous_full(vec2 params0, vec3 n0, vec3 n, vec3 v0, vec3 v) {
    float cosaN = dot(n0, n);
    float cosaV = dot(v0, v);
    float cosa = min(cosaN, cosaV);
    float a = acos(clamp(cosa, -1.0, 1.0));
    a = smoothstep(0.0, params0.x, a);
    return clamp(1.0 - a * params0.y, 0.0, 1.0);
}

// NRD Common.hlsli:289 IsInScreenNearest
float nrd_is_in_screen_nearest(vec2 uv) {
    return (all(greaterThan(uv, vec2(0.0))) && all(lessThan(uv, vec2(1.0)))) ? 1.0 : 0.0;
}

// NRD Common.hlsli:302 IsInScreenBilinear — per-tap screen validity for 2x2 footprint
// Returns vec4(tap00, tap10, tap01, tap11) validity
vec4 nrd_is_in_screen_bilinear(vec2 footprintOrigin, vec2 rectSize) {
    vec4 p = vec4(footprintOrigin, footprintOrigin + vec2(1.0));
    vec4 r = vec4(greaterThanEqual(p, vec4(0.0)));
    r *= vec4(lessThan(p, rectSize.xyxy));
    return vec4(r.x * r.y, r.z * r.y, r.x * r.w, r.z * r.w);
}

// NRD RELAX_Common.hlsli:29 BilinearWithCustomWeightsImmediateFloat
float nrd_bilinear_custom_float(float s00, float s10, float s01, float s11, vec4 weights) {
    float result = s00 * weights.x + s10 * weights.y + s01 * weights.z + s11 * weights.w;
    float sumWeights = dot(weights, vec4(1.0));
    return sumWeights < 0.0001 ? 0.0 : result / sumWeights;
}

// NRD RELAX_Common.hlsli:42 BilinearWithCustomWeightsImmediateFloat4
vec4 nrd_bilinear_custom_vec4(vec4 s00, vec4 s10, vec4 s01, vec4 s11, vec4 weights) {
    vec4 result = s00 * weights.x + s10 * weights.y + s01 * weights.z + s11 * weights.w;
    float sumWeights = dot(weights, vec4(1.0));
    return sumWeights < 0.0001 ? vec4(0.0) : result / sumWeights;
}

// NRD Common.hlsli:30 isReprojectionTapValid — world-space plane distance check
float nrd_is_reprojection_tap_valid(vec3 currentWorldPos, vec3 previousWorldPos, vec3 currentNormal, float disocclusionThreshold) {
    float maxPlaneDistance = abs(dot(currentWorldPos - previousWorldPos, currentNormal));
    return maxPlaneDistance > disocclusionThreshold ? 0.0 : 1.0;
}

// NRD Common.hlsli:23 ApplyThinLensEquation — virtual position depth correction for curved specular
float nrd_apply_thin_lens_equation(float O, float curvature) {
    return O / (2.0 * curvature * O + 1.0);
}

// NRD Common.hlsli:507 GetRelaxedRoughnessWeightParams
vec2 nrd_relaxed_roughness_weight_params(float m, float fraction) {
    float a = 1.0 / mix(NRD_ROUGHNESS_SENSITIVITY, 1.0, mix(m * m, m, clamp(fraction, 0.0, 1.0)));
    float b = m * a;
    return vec2(a, -b);
}

// NRD: GetSpecMagicCurve — roughness-dependent interpolation factor
float nrd_spec_magic_curve(float roughness) {
    return 1.0 - exp(-200.0 * roughness * roughness);
}

// NRD: GetModifiedRoughnessFromNormalVariance
float nrd_modified_roughness_from_normal_variance(float roughness, vec3 avgNormal) {
    float avgNormalLen = length(avgNormal);
    float normalVariance = clamp(1.0 - avgNormalLen, 0.0, 1.0);
    return clamp(roughness + normalVariance * 0.25, 0.0, 1.0);
}

// NRD: GetXvirtual — compute virtual world position for specular reprojection
// Uses thin-lens equation with curvature to find virtual reflection point
vec3 nrd_get_xvirtual(float hitDist, float curvature, vec3 X, vec3 Xprev, vec3 N, vec3 V, float roughness) {
    float NoV = abs(dot(N, V));
    // Dominant direction factor (GGX lobe dominant direction)
    float dominantFactor = mix(1.0, NoV, clamp(roughness, 0.0, 1.0));
    vec3 Xvirtual = X - V * nrd_apply_thin_lens_equation(hitDist * dominantFactor, curvature);
    return Xvirtual;
}

// NRD: GetSpecularDominantFactor — how much virtual motion matters based on roughness
float nrd_specular_dominant_factor(vec3 N, vec3 V, float roughness) {
    float NoV = abs(dot(N, V));
    float dominantFactor = (1.0 - roughness * roughness) / (1.0 + roughness);
    return clamp(dominantFactor, 0.0, 1.0);
}

// NRD Common.hlsli:554 GetEncodingAwareNormalWeight — for VMB normal validation
float nrd_encoding_aware_normal_weight(vec3 Ncurr, vec3 Nprev, float maxAngle, float curvatureAngle, float thresholdAngle) {
    float cosa = dot(Ncurr, Nprev);
    float angle = acos(clamp(cosa, -1.0, 1.0));
    float w = smoothstep(1.0, 0.0, (angle - curvatureAngle - thresholdAngle) / max(maxAngle, 1e-6));
    return clamp(w, 0.0, 1.0);
}

// NRD: Schlick Fresnel Pow5 approximation
float nrd_pow5(float x) {
    float x2 = x * x;
    return x2 * x2 * x;
}

const float RELAX_NORMAL_ULP = 1.5 / 255.0;
const float NRD_EPS = 1e-6;
const float NRD_INF = 1e30;
const float RELAX_MAX_ACCUM_FRAME_NUM = 255.0;

// Area-ReSTIR / PathTracer reference writes materialID = 0.f in NRD-facing guide buffers.
const float NRD_DEFAULT_MIN_MATERIAL = 0.0;

// NRD Common.hlsli:238-242 CompareMaterials reference:
//   #if NRD_NORMAL_ENCODING == R10G10B10A2_UNORM:
//     CompareMaterials(m0, m, minm) = (max(m0, minm) == max(m, minm))
//   #else:
//     CompareMaterials(m0, m, minm) = true
//
// Material ID is packed into the .w channel of the material texture.
// nrd_decode_material_id() recovers the raw ID from the encoded value.
// When either pixel decodes to NRD_MATERIAL_ID_DISABLED (0.0), the
// comparison is always treated as passing (returns 1.0), matching the
// NRD behaviour for pipelines that do not supply material IDs.
float nrd_material_weight_with_min(vec4 centerMaterial, vec4 sampleMaterial, float minMaterial) {
    float centerID = nrd_decode_material_id(centerMaterial.w);
    float sampleID = nrd_decode_material_id(sampleMaterial.w);

    // If either side has material IDs disabled, always pass (matches NRD default).
    if (centerID == NRD_MATERIAL_ID_DISABLED || sampleID == NRD_MATERIAL_ID_DISABLED) return 1.0;

    // NRD CompareMaterials: max(m0, minm) == max(m, minm)
    // This groups all IDs below minMaterial into a single bucket.
    return (max(centerID, minMaterial) == max(sampleID, minMaterial)) ? 1.0 : 0.0;
}

// Convenience overload using the NRD default minimum material threshold.
// Material IDs are derived from specular properties (emissive=2, smooth metal=1, dielectric=3).
float nrd_material_weight(vec4 centerMaterial, vec4 sampleMaterial) {
    return nrd_material_weight_with_min(centerMaterial, sampleMaterial, NRD_DEFAULT_MIN_MATERIAL);
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
    return clamp(historyLength / max(maxHistoryLength, 1.0), 0.0, 1.0);
}

float nrd_gradient_to_confidence(vec3 previousRadiance, vec3 currentRadiance, float historyLength, float maxHistoryLength) {
    float prevLuma = nrd_luminance(max(previousRadiance, vec3(0.0)));
    float currLuma = nrd_luminance(max(currentRadiance, vec3(0.0)));
    float maxLuma = max(prevLuma, currLuma);
    float gradient = (maxLuma > 1e-6) ? abs(prevLuma - currLuma) / maxLuma : 0.0;
    float historyFactor = clamp(historyLength / max(maxHistoryLength, 1.0), 0.0, 1.0);
    return clamp(1.0 - gradient * (1.0 - historyFactor), 0.0, 1.0);
}

float nrd_hit_distance_confidence(float hitDistance, float viewDistance) {
    float ratio = hitDistance / max(viewDistance, 1e-3);
    return clamp(1.0 - ratio * 0.5, 0.1, 1.0);
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
