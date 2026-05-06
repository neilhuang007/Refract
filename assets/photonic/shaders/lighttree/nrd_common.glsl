#ifndef PHOTONICS_NRD_COMMON_GLSL
#define PHOTONICS_NRD_COMMON_GLSL

#include "/photonics/lighttree/nrd_material_id.glsl"

// ---------------------------------------------------------------------------
// Uniforms declared by the NRD pipeline -- registered by LightTreeRenderer.
// Shader agents declare these here so all NRD shaders share the definitions.
// ---------------------------------------------------------------------------
uniform float ph_nrd_denoising_range;           // gDenoisingRange
uniform float ph_nrd_depth_threshold;           // gDepthThreshold
uniform float ph_nrd_disocclusion_threshold;    // gDisocclusionThreshold
uniform float ph_nrd_disocclusion_threshold_alt;// gDisocclusionThresholdAlternate
uniform float ph_nrd_max_accumulated_frame_num; // gDiffMaxAccumulatedFrameNum
uniform float ph_nrd_max_fast_accumulated_frame_num; // gDiffMaxFastAccumulatedFrameNum
uniform float ph_nrd_phi_luminance_diff;        // gDiffPhiLuminance  (default 1.0)
uniform float ph_nrd_phi_luminance_spec;        // gSpecPhiLuminance  (default 1.5)
uniform float ph_nrd_lobe_angle_fraction;       // gLobeAngleFraction (default 0.5)
uniform float ph_nrd_roughness_fraction;        // gRoughnessFraction (default 0.15)
uniform float ph_nrd_spec_lobe_angle_slack;     // gSpecLobeAngleSlack (default 0.0)
uniform float ph_nrd_history_fix_frame_num;     // gHistoryFixFrameNum (default 3)
uniform float ph_nrd_history_fix_base_stride;   // gHistoryFixBasePixelStride (default 14)
uniform float ph_nrd_history_fix_normal_power;  // gHistoryFixEdgeStoppingNormalPower (default 8)
uniform float ph_nrd_anti_firefly;              // 1.0 enabled, 0.0 skip
uniform float ph_nrd_hitdist_reconstruction;    // 0.0 disabled, 1.0 = 3x3, 2.0 = 5x5
uniform float ph_nrd_history_clamping_color_box_sigma_scale; // gFastHistoryClampingSigmaScale (default 2.0)
uniform float ph_nrd_history_acceleration_amount;   // gHistoryAccelerationAmount (default 0.3)
uniform float ph_nrd_history_reset_temporal_sigma_scale; // gHistoryResetTemporalSigmaScale (default 0.5)
uniform float ph_nrd_history_reset_spatial_sigma_scale;  // gHistoryResetSpatialSigmaScale (default 4.5)
uniform float ph_nrd_history_reset_amount;      // gHistoryResetAmount (default 0.5)
uniform float ph_nrd_diff_prepass_blur_radius;  // gDiffuseBlurRadius (default 30)
uniform float ph_nrd_spec_prepass_blur_radius;  // gSpecularBlurRadius (default 50)
uniform float ph_nrd_reset_history;             // gResetHistory (1.0 = reset all history this frame)
uniform float ph_nrd_roughness_edge_stopping_relaxation; // gRoughnessEdgeStoppingRelaxation (default 0.3)
uniform float ph_nrd_debug_bypass_temporal_accumulation; // 1.0 bypass temporal accumulation, 0.0 run normally

const float PH_NRD_HISTORY_SCALE = 255.0;
const vec3 PH_NRD_LUMA_COEFF = vec3(0.2126, 0.7152, 0.0722);
const float NRD_FP16_MAX = 65504.0;
const float NRD_EPS = 1e-6;
const float NRD_DIRECT_FIREFLY_LUMA = 16.0;

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

vec3 nrd_clamp_direct_firefly(vec3 radiance) {
    radiance = max(radiance, vec3(0.0));
    float luma = nrd_luminance(radiance);
    if (luma > NRD_DIRECT_FIREFLY_LUMA) {
        radiance *= NRD_DIRECT_FIREFLY_LUMA / max(luma, NRD_EPS);
    }
    return radiance;
}

// NRD Common.hlsli:244 UnpackViewZ -- compute linear view-space depth from world position
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

// NRD.hlsli STL::Color::YCoCgToLinear -- clamps to >= 0 to match NRD inverse
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

// NRD _NRD_SafeNormalize: rsqrt(lenSq + 1e-9) -- additive epsilon, not max
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

// NRD: historyLength / 255.0 -- no saturate, purely linear
float nrd_encoded_history(float historyLength) {
    return historyLength / PH_NRD_HISTORY_SCALE;
}

// NRD: 255.0 * historyTex -- no extra clamp
float nrd_decoded_history(vec4 encodedHistory) {
    return encodedHistory.r * PH_NRD_HISTORY_SCALE;
}

// NRD RELAX_Common.hlsli:105 GetPlaneDistanceWeight_Atrous -- binary A-trous variant
// threshold is pre-scaled by caller using viewZ
float nrd_plane_distance_weight(vec3 centerPos, vec3 centerNormal, vec3 samplePos, float threshold) {
    float planeDistance = abs(dot(samplePos - centerPos, centerNormal));
    return planeDistance < threshold ? 1.0 : 0.0;
}

// NRD RELAX_Common.hlsli:98 GetPlaneDistanceWeight -- normalized form for temporal/history passes
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

// RELAX_HistoryFix.cs.hlsl:92 MirrorUv -- folds OOB taps back into [0,1] instead of
// wasting them on clamped border pixels. Equivalent to a periodic mirror at 0 and 1.
vec2 nrd_mirror_uv(vec2 uv) {
    return 1.0 - abs(1.0 - fract(uv * 0.5) * 2.0);
}

// NRD Common.hlsli:289 IsInScreenNearest
float nrd_is_in_screen_nearest(vec2 uv) {
    return (all(greaterThan(uv, vec2(0.0))) && all(lessThan(uv, vec2(1.0)))) ? 1.0 : 0.0;
}

// NRD Common.hlsli:302 IsInScreenBilinear -- per-tap screen validity for 2x2 footprint
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

// NRD Common.hlsli:30 isReprojectionTapValid -- world-space plane distance check
float nrd_is_reprojection_tap_valid(vec3 currentWorldPos, vec3 previousWorldPos, vec3 currentNormal, float disocclusionThreshold) {
    float maxPlaneDistance = abs(dot(currentWorldPos - previousWorldPos, currentNormal));
    return maxPlaneDistance > disocclusionThreshold ? 0.0 : 1.0;
}

// NRD Common.hlsli:23 ApplyThinLensEquation -- virtual position depth correction for curved specular
float nrd_apply_thin_lens_equation(float O, float curvature) {
    return O / (2.0 * curvature * O + 1.0);
}

// NRD Common.hlsli:507 GetRelaxedRoughnessWeightParams
vec2 nrd_relaxed_roughness_weight_params(float m, float fraction) {
    float a = 1.0 / mix(NRD_ROUGHNESS_SENSITIVITY, 1.0, mix(m * m, m, clamp(fraction, 0.0, 1.0)));
    float b = m * a;
    return vec2(a, -b);
}

// NRD: GetSpecMagicCurve -- roughness-dependent interpolation factor
float nrd_spec_magic_curve(float roughness) {
    return 1.0 - exp(-200.0 * roughness * roughness);
}

// NRD: GetModifiedRoughnessFromNormalVariance
float nrd_modified_roughness_from_normal_variance(float roughness, vec3 avgNormal) {
    float avgNormalLen = length(avgNormal);
    float normalVariance = clamp(1.0 - avgNormalLen, 0.0, 1.0);
    return clamp(roughness + normalVariance * 0.25, 0.0, 1.0);
}

// NRD.hlsli:426 _NRD_GetSpecularDominantFactor
float nrd_specular_dominant_factor(vec3 N, vec3 V, float roughness) {
    float NoV = clamp(abs(dot(N, V)), 0.0, 1.0);
    roughness = clamp(roughness, 0.0, 1.0);
    float a = 0.298475 * log(max(39.4115 - 39.0029 * roughness, 1e-6));
    float dominantFactor = pow(clamp(1.0 - NoV, 0.0, 1.0), 10.8649) * (1.0 - a) + a;
    return clamp(dominantFactor, 0.0, 1.0);
}

// NRD.hlsli:434 _NRD_GetSpecularDominantDirection
vec3 nrd_specular_dominant_direction(vec3 N, vec3 V, float roughness) {
    vec3 R = reflect(-V, N);
    float dominantFactor = nrd_specular_dominant_factor(N, V, roughness);
    return nrd_safe_normal(mix(N, R, dominantFactor));
}

// NRD Common.hlsli:401 GetXvirtual.
// This preserves the important stabilizer from the reference: when the thin-lens
// virtual point is close to the surface, anchor it to the surface-motion position
// from the previous frame instead of inventing independent specular motion.
vec3 nrd_get_xvirtual(float hitDist, float curvature, vec3 X, vec3 Xprev, vec3 N, vec3 V, float roughness) {
    hitDist = max(hitDist, 0.0);

    float dominantFactor = nrd_specular_dominant_factor(N, V, roughness);
    vec3 D = nrd_safe_normal(mix(N, reflect(-V, N), dominantFactor));
    float objectDepth = -max(abs(dot(D, N)) * hitDist, NRD_EPS);
    float mag = 1.0 / (2.0 * curvature * objectDepth - 1.0);

    // Reference uses camera-relative |X| here. Our positions are absolute world
    // space, so subtract the current camera position before applying the silhouette
    // magnification reduction.
    float NoV = clamp(abs(dot(N, V)), 0.0, 1.0);
    float silhouetteReduction = length(X - world_camera_position);
    silhouetteReduction *= clamp(1.0 - NoV, 0.0, 1.0);
    silhouetteReduction *= max(curvature, 0.0);
    mag *= 1.0 / (1.0 + silhouetteReduction);

    float imageDistance = abs(mag) * hitDist;
    float virtualDistance = dominantFactor * imageDistance;
    float closenessToSurface = clamp(virtualDistance / (hitDist + NRD_EPS), 0.0, 1.0);
    vec3 anchor = mix(Xprev, X, closenessToSurface);

    return anchor + V * virtualDistance * sign(mag);
}

// NRD Common.hlsli:554 GetEncodingAwareNormalWeight -- for VMB normal validation
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
const float NRD_INF = 1e30;
const float RELAX_MAX_ACCUM_FRAME_NUM = 255.0;

// NRD Common.hlsli:87 NRD_MAX_ALLOWED_VIRTUAL_MOTION_ACCELERATION
const float NRD_MAX_ALLOWED_VIRTUAL_MOTION_ACCELERATION = 5.0;
// NRD Common.hlsli:86 NRD_CURVATURE_HIGH_PARALLAX_DISOCCLUSION_THRESHOLD (normalized %)
const float NRD_CURVATURE_HIGH_PARALLAX_DISOCCLUSION_THRESHOLD = 0.04;
// NRD RELAX TemporalAccumulation: variance boost when 2nd moment is 0 and confidence is low
const float NRD_SPEC_VARIANCE_BOOST = 1.0;

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

// NRD.hlsli:516 _NRD_EnvironmentTerm_Rtg -- Ray Tracing Gems Chapter 32 Eq 4
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

// NRD.hlsli:733 NRD_MaterialFactors -- view-dependent demodulation/remodulation
// NRD.hlsli:101,105 -- NRD_MATERIAL_FACTOR_MIN_SCALE = 0.02, NRD_ROUGHNESS_FACTOR_MIN_SCALE = 0.1
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

// NRD RELAX unpack is passthrough -- no clamping
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

// ---------------------------------------------------------------------------
// Helpers added for the four new NRD passes (ClassifyTiles, HitDistReconstruction,
// PrePass, Copy). Reference: Common.hlsli and RELAX_Common.hlsli.
// ---------------------------------------------------------------------------

// Common.hlsli:548 GetGaussianWeight -- exp(-0.66 * r^2), r normalised to 1
// RELAX_PrePass.cs.hlsl: used with offset.z (precomputed length in Poisson table)
float nrd_gaussian_weight(float r) {
    return exp(-0.66 * r * r);
}

// Common.hlsli:489-497 GetHitDistanceWeightParams
// Returns vec2(a, b) such that ComputeExponentialWeight(hitDist, a, b) is the weight.
// nonLinearAccumSpeed = 1.0/9.0 in PrePass (reference line 140,291).
vec2 nrd_hit_distance_weight_params(float hitDist, float nonLinearAccumSpeed) {
    float a = 1.0 / nonLinearAccumSpeed;
    float b = hitDist * a;
    return vec2(a, -b);
}

// Common.hlsli:531-532 ComputeExponentialWeight (NRD_EXP_WEIGHT_DEFAULT_SCALE = 3.0)
// ExpApprox(-3 * |x*px + py|) = 1 / ((x*px+py)^2 - (x*px+py) + 1)
// Used wherever the reference calls ComputeExponentialWeight / ComputeWeight.
float nrd_exp_approx(float x) {
    // Common.hlsli:526: rcp((x)*(x) - (x) + 1.0)
    return 1.0 / (x * x - x + 1.0);
}

float nrd_compute_exponential_weight(float x, float px, float py) {
    // NRD_EXP_WEIGHT_DEFAULT_SCALE = 3.0 (Common.hlsli:84)
    return nrd_exp_approx(-3.0 * abs(x * px + py));
}

// Common.hlsli:164-165 GetBilateralWeight: Math::LinearStep(0.03, 0.0, |z-zc|/max(z,zc))
// Used in HitDistReconstruction for cross-bilateral viewZ weight.
float nrd_bilateral_weight(float z, float zc) {
    float relDiff = abs(z - zc) / max(max(z, zc), 1e-6);
    // LinearStep(edge0, edge1, x) = saturate((x-edge0)/(edge1-edge0))
    // LinearStep(0.03, 0.0, relDiff) = saturate(relDiff / 0.03 * (-1) + 1) = 1 - relDiff/0.03 clamped
    return clamp(1.0 - relDiff / 0.03, 0.0, 1.0);
}

// Common.hlsli:508-517 GetRelaxedRoughnessWeightParams
// Used in HitDistReconstruction for specular roughness gate.
vec2 nrd_get_relaxed_roughness_weight_params(float m) {
    // m = roughness*roughness (already squared)
    float a = 1.0 / mix(NRD_ROUGHNESS_SENSITIVITY, 1.0, mix(m * m, m, clamp(1.0, 0.0, 1.0)));
    float b = m * a;
    return vec2(a, -b);
}

// Poisson-8 kernel from Poisson.hlsli -- used by PrePass (g_Poisson8).
// .xy = disc offset, .z = precomputed length.
const vec3 nrd_poisson8[8] = vec3[8](
    vec3(-0.4706069, -0.4427112, 0.6461146),
    vec3(-0.9057375,  0.3003471, 0.9542373),
    vec3(-0.3487388,  0.4037880, 0.5335386),
    vec3( 0.1023042,  0.6439373, 0.6520134),
    vec3( 0.5699277,  0.3513750, 0.6695386),
    vec3( 0.2939128, -0.1131226, 0.3149309),
    vec3( 0.7836658, -0.4208784, 0.8895339),
    vec3( 0.1564120, -0.8198990, 0.8346850)
);

// Rotate a 2D offset using a vec4 rotator (cos, sin, -sin, cos packed as .xyzw).
// Reference: Geometry::RotateVector from ml.hlsli.
vec2 nrd_rotate_vector(vec4 rotator, vec2 v) {
    return vec2(dot(v, rotator.xy), dot(v, rotator.zw));
}

// Build a simple frame-index-based rotator (NRD_FRAME mode = 1 in reference).
// Reference: Common.hlsli:267 GetBlurKernelRotation with mode=NRD_FRAME.
// gRotatorPre is a constant from NRD settings; we approximate with frameCounter.
vec4 nrd_get_kernel_rotation(int frameIndex) {
    // Reference stores a base rotator in gRotatorPre; here we build from a fixed
    // golden-angle sequence per frame for the fragment-shader variant.
    // The actual rotation angle comes from the frame index only (NRD_FRAME mode).
    // golden angle ~= 2.39996 radians
    float angle = float(frameIndex) * 2.39996;
    float s = sin(angle);
    float c = cos(angle);
    return vec4(c, s, -s, c);
}

// Reconstruct world-space position from pixel UV and viewZ.
// Photonics uses actual world-space positions from the G-buffer; this helper
// is a fallback reconstruction from clip-space for sampled taps where we only
// have the viewZ from textures (not the world position texture).
// Reference: Common.hlsli:66-80 GetCurrentWorldPosFromClipSpaceXY.
// In Photonics the view basis vectors are not directly available as uniforms;
// we use the G-buffer position texture for the center and reconstruct offset
// taps via a simple proportional extrapolation using (uv - centerUv) scaled
// by viewZ (perspective).  This matches the reference for the perspective case.
vec3 nrd_world_pos_from_uv(vec2 uv, float viewZ, vec3 centerWorldPos, float centerViewZ) {
    // Simple perspective reconstruction: dx/dy in view space proportional to uv delta.
    // Avoids needing frustum forward/right/up vectors as uniforms.
    // This is an approximation; the reference uses frustum vectors.
    vec2 uvDelta = uv - vec2(tex_coord) / vec2(viewWidth, viewHeight);
    // The screen-space tangent of half FOV ~ centerWorldPos / centerViewZ (camera-relative).
    vec3 camRelCenter = centerWorldPos - world_camera_position;
    vec3 approxPos = world_camera_position + camRelCenter * (viewZ / max(centerViewZ, 1e-3));
    approxPos += vec3(uvDelta * viewZ * 2.0, 0.0); // crude lateral correction
    return approxPos;
}

// Accurate version: reconstruct world pos from pixel integer coord and viewZ using
// the position stored in the G-buffer for the center, scaling laterally.
// For the PrePass spatial loop this gives good-enough plane-distance checks.
// Reference (exact): uses frustum vectors; Photonics stores world pos in G-buffer.
vec3 nrd_world_pos_from_texel(ivec2 coord, sampler2D positionTex) {
    return texelFetch(positionTex, coord, 0).xyz;
}

#endif
