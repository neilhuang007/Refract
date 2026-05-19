#ifndef PHOTONICS_NRD_PARAMETERS_GLSL
#define PHOTONICS_NRD_PARAMETERS_GLSL

// ---------------------------------------------------------------------------
// NRD tuning constants — centralised here, mirroring the pattern of
// restir_di_parameters.glsl.  All values are identical to their original
// sites; this file only relocates them.
//
// Rules:
//   - No uniforms here (they remain in nrd_common.glsl).
//   - No includes here (leaf file; no guard cycles possible).
//   - Algorithm-shape constants that are not developer-tunable
//     (e.g. NRD_FP16_MAX, NRD_EPS, RELAX_NORMAL_ULP, NRD_INF,
//     RELAX_MAX_ACCUM_FRAME_NUM, PH_NRD_HISTORY_SCALE, PH_NRD_LUMA_COEFF)
//     stay in nrd_common.glsl.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Firefly suppression
// ---------------------------------------------------------------------------

// Maximum luminance allowed for a direct-lighting sample before it is scaled
// back toward the threshold.  Tightened from the NRD reference default of
// ~64-128 to 16 (commit b255214) to catch block-shadow / lamp-off events
// within one frame.
// Reference: nrd_clamp_direct_firefly() in nrd_common.glsl.
#define NRD_DIRECT_FIREFLY_LUMA 16.0

// ---------------------------------------------------------------------------
// Anti-lag (per-pixel history rejection)
// ---------------------------------------------------------------------------

// History is rejected when its luminance exceeds (current * MULT + ADDEND).
// Tightened from the reference 8x/+4 to 4x/+2 to catch lighting-change events
// (typical luma ratios 4-10x) before they decay over RELAX_MAX_ACCUM_FRAME_NUM
// frames.  Pixels whose lighting did not change are unaffected.
// Reference: nrd_ta_history_sample_valid() in nrd_temporal_accumulation.fsh.
#define NRD_ANTI_LAG_MULT   4.0
#define NRD_ANTI_LAG_ADDEND 2.0

// ---------------------------------------------------------------------------
// FP16 view-depth packing
// ---------------------------------------------------------------------------

// Scale applied when packing linear view depth into a FP16 channel.
// 0.125 keeps viewZ up to 524032 in FP16 range (65504 / 0.125).
// Reference: NRD Shared.hlsli FP16_VIEWZ_SCALE; used in nrd_confidence_*.fsh.
#define NRD_FP16_VIEWZ_SCALE 0.125

// ---------------------------------------------------------------------------
// Roughness weight sensitivity
// ---------------------------------------------------------------------------

// Minimum roughness fraction fed into the mix() that shapes the weight slope.
// Lower = sharper roughness edge-stopping; raise to soften specular boundaries.
// Reference: NRD Common.hlsli GetRoughnessWeightParams / GetRelaxedRoughnessWeightParams.
#define NRD_ROUGHNESS_SENSITIVITY 0.01

// ---------------------------------------------------------------------------
// Virtual-motion curvature guard
// ---------------------------------------------------------------------------

// Maximum allowed virtual-to-surface motion ratio before curvature is zeroed.
// Reference: NRD Common.hlsli NRD_MAX_ALLOWED_VIRTUAL_MOTION_ACCELERATION = 5.
#define NRD_MAX_ALLOWED_VIRTUAL_MOTION_ACCELERATION 5.0

// Normalised disocclusion threshold used in the high-parallax curvature path.
// Reference: NRD Common.hlsli NRD_CURVATURE_HIGH_PARALLAX_DISOCCLUSION_THRESHOLD = 0.04.
#define NRD_CURVATURE_HIGH_PARALLAX_DISOCCLUSION_THRESHOLD 0.04

// ---------------------------------------------------------------------------
// Specular variance
// ---------------------------------------------------------------------------

// Variance injected when the specular second moment is zero and history
// confidence is low (prevents divide-by-zero in the A-trous filter).
// Reference: RELAX_TemporalAccumulation.cs.hlsl lines 926-927.
#define NRD_SPEC_VARIANCE_BOOST 1.0

// ---------------------------------------------------------------------------
// Material demodulation floors
// ---------------------------------------------------------------------------

// Clamp floor for the diffuse material factor to prevent division artifacts.
// Reference: NRD.hlsli NRD_MATERIAL_FACTOR_MIN_SCALE = 0.02.
#define NRD_MATERIAL_FACTOR_MIN_SCALE 0.02

// Clamp floor for the roughness-based specular factor.
// Reference: NRD.hlsli NRD_ROUGHNESS_FACTOR_MIN_SCALE = 0.1.
#define NRD_ROUGHNESS_FACTOR_MIN_SCALE 0.1

#endif // PHOTONICS_NRD_PARAMETERS_GLSL
