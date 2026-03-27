#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"

// Spatial bias correction mode — matches RTXDI_DISpatialResamplingParameters::biasCorrectionMode.
// Corresponds to ReSTIRDI_SpatialBiasCorrectionMode and RTXDI_BIAS_CORRECTION_* defines
// (RtxdiParameters.h lines 35-41):
//   0 (OFF)        — 1/M normalization after combining (RTXDI_BIAS_CORRECTION_OFF)
//   1 (BASIC)      — Two-pass MIS normalization without visibility rays (RTXDI_BIAS_CORRECTION_BASIC)
//   2 (PAIRWISE)   — Pairwise MIS normalization assuming every sample visible (RTXDI_BIAS_CORRECTION_PAIRWISE)
//   3 (RAY_TRACED) — Two-pass MIS with visibility ray per neighbor, unbiased (RTXDI_BIAS_CORRECTION_RAY_TRACED)
// SDK default (ReSTIRDI.cpp line 79): BASIC (1). When unbound (0.0), use BASIC.
// Use sentinel: -1.0 to explicitly request OFF; 0.0 (unbound) falls back to SDK default BASIC.
uniform float ph_restir_spatial_bias_mode;

// SDK defaults from GetDefaultReSTIRDISpatialResamplingParams() (ReSTIRDI.cpp lines 74-87):
//   discountNaiveSamples        = true   (SDK default; prevents over-weighting fresh samples)
//   enableMaterialSimilarityTest = true  (SDK default; prevents cross-material light bleeding)
//   numDisocclusionBoostSamples  = 8     (SDK default; boosted sample count on disocclusion)
//   targetHistoryLength          = 0     (SDK default; 0 means: condition M < 0 never fires, NO boost)
const float rtxdi_naive_sampling_m_threshold = 2.0f;

// Runtime uniforms wired to RTXDI_DISpatialResamplingParameters fields.
// When unbound (0.0) each falls back to the SDK default documented above.
// Use -1.0 as a sentinel to explicitly disable features whose SDK default is enabled.
uniform float ph_restir_spatial_discount_naive;    // SDK default: true  (1.0); unbound 0.0 → SDK default true
uniform float ph_restir_spatial_material_test;     // SDK default: true  (1.0); unbound 0.0 → SDK default true
uniform float ph_restir_spatial_boost_samples;     // SDK default: 8
uniform float ph_restir_spatial_target_history;    // SDK default: 0 (always boost)

// RTXDI bias correction constants — matches RtxdiParameters.h lines 35-41 exactly.
const int RTXDI_BIAS_CORRECTION_OFF = 0;
const int RTXDI_BIAS_CORRECTION_BASIC = 1;
const int RTXDI_BIAS_CORRECTION_PAIRWISE = 2;
const int RTXDI_BIAS_CORRECTION_RAY_TRACED = 3;

// Fix #9: rtxdi_unpack_reservoir_at_surface resets to empty on invalid weightSum (fix #2 in reuse_bridge.glsl).
// When the reservoir has corrupt weightSum the unpack returns RTXDI_EmptyDIReservoir(),
// causing this function to return false and the reservoir to remain at its empty initial state.
bool lt_load_direct_temporal_reservoir(ivec2 reservoirPos, DirectSurface surface, out Reservoir reservoir) {
    reservoir = rtxdi_empty_reservoir();
    if (!lt_is_active_reservoir_lane(reservoirPos)) {
        return false;
    }

    if (!lt_is_viewport_uv_in_bounds(reservoirPos)) {
        return false;
    }

    rtxdi_unpack_reservoir_at_surface(
        reservoir,
        texelFetch(radiosity_temporal_reservoirs, reservoirPos, 0),
        texelFetch(radiosity_temporal_reservoir_samples, reservoirPos, 0),
        texelFetch(radiosity_temporal_reservoir_meta, reservoirPos, 0),
        surface,
        false
    );
    // RTXDI_UnpackDIReservoir (ReservoirStorage.hlsli lines 88-91) only sanitizes weightSum, not targetPdf.
    // Match RTXDI exactly: do NOT check targetPdf for NaN here.

    // RTXDI contract: RAB_LoadLightInfo reads from a fully-populated GPU buffer where every stored
    // index is guaranteed to address valid light data. In photonics the buffer holds exactly
    // ph_light_count entries per frame; a packed index >= ph_light_count is a stale reference
    // from a previous frame (e.g., a block was broken and the light list shrank). Invalidate such
    // reservoirs so they cannot (a) cause out-of-range reads in load_light() and (b) inflate M
    // with zero-weight contributions during spatial reuse, which darkens the result for several
    // frames after a block break.
    if (RTXDI_IsValidDIReservoir(reservoir)) {
        int lightIndex = RTXDI_GetDIReservoirLightIndex(reservoir);
        if (lightIndex >= ph_light_count) {
            reservoir = rtxdi_empty_reservoir();
            return false;
        }
    }

    return RTXDI_IsValidDIReservoir(reservoir) && !isnan(reservoir.weightSum);
}

void main() {
    ivec2 reservoirPos = lt_current_reservoir_pos();
    if (!lt_is_active_reservoir_lane(reservoirPos)) {
        Reservoir emptyReservoir = rtxdi_empty_reservoir();
        reservoir_frag_out = rtxdi_pack_reservoir(emptyReservoir);
        reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(emptyReservoir);
        reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(emptyReservoir);
        return;
    }

    ivec2 centerPixelPos = lt_current_pixel_pos();
    if (!lt_is_viewport_uv_in_bounds(centerPixelPos)) {
        Reservoir emptyReservoir = rtxdi_empty_reservoir();
        reservoir_frag_out = rtxdi_pack_reservoir(emptyReservoir);
        reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(emptyReservoir);
        reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(emptyReservoir);
        return;
    }

    int activeCheckerboardField = int(ph_restir_active_checkerboard_field);
    ivec2 centerReservoirPos = reservoirPos;
    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(uvec2(centerPixelPos), uint(frameCounter), RTXDI_DI_SPATIAL_RESAMPLING_RANDOM_SEED);

    // Variable names match RTXDI_DISpatialResamplingWithPairwiseMIS (SpatialResampling.hlsli line 36).
    DirectSurface centerSurface = lt_load_surface(centerPixelPos);
    if (!lt_is_valid_surface(centerSurface)) {
        Reservoir emptyReservoir = rtxdi_empty_reservoir();
        reservoir_frag_out = rtxdi_pack_reservoir(emptyReservoir);
        reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(emptyReservoir);
        reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(emptyReservoir);
        return;
    }
    // Don't abort on empty center sample — RTXDI proceeds unconditionally
    // (SpatialResampling.hlsli line 52: centerSample.M is read without any prior
    // validity guard). When centerSample is empty, neighbors via pairwise MIS
    // or the non-pairwise path can still produce a valid merged result.
    Reservoir centerSample = rtxdi_empty_reservoir();
    lt_load_direct_temporal_reservoir(centerReservoirPos, centerSurface, centerSample);

    // Spatial bias correction mode from runtime uniform.
    // SDK default (ReSTIRDI.cpp line 79): BASIC (1).
    // When unbound (0.0) fall back to SDK default BASIC.
    // Explicit mode values (RtxdiParameters.h lines 35-41):
    //   0 = OFF        — 1/M normalization
    //   1 = BASIC      — Two-pass non-pairwise MIS (SpatialResampling.hlsli lines 132-306)
    //   2 = PAIRWISE   — Pairwise MIS
    //   3 = RAY_TRACED — Two-pass with visibility ray per neighbor, unbiased
    // Use -1.0 as a sentinel to explicitly request OFF (since 0 collides with unbound detection).
    int biasCorrectionMode;
    if (ph_restir_spatial_bias_mode < -0.5) {
        // Sentinel -1.0: explicit OFF
        biasCorrectionMode = RTXDI_BIAS_CORRECTION_OFF;
    } else if (ph_restir_spatial_bias_mode < 0.5) {
        // Unbound (0.0) or very small: use SDK default BASIC
        biasCorrectionMode = RTXDI_BIAS_CORRECTION_BASIC;
    } else {
        biasCorrectionMode = int(round(ph_restir_spatial_bias_mode));
    }

    // Runtime-controllable spatial parameters wired from ph_restir_spatial_* uniforms.
    // SDK defaults (ReSTIRDI.cpp lines 83-84): discountNaiveSamples=true, enableMaterialSimilarityTest=true.
    // Sentinel pattern for SDK-default-true booleans:
    //   -1.0 → SDK default (true), 0.0 (unbound) → SDK default (true), >= 0.5 → true.
    //   Explicit disable: pass -2.0 (< -1.5) to force false.
    bool lt_discount_naive_samples = (ph_restir_spatial_discount_naive < -1.5) ? false : true;
    bool lt_enable_material_similarity_test = (ph_restir_spatial_material_test < -1.5) ? false : true;

    // Use ph_restir_spatial_sample_count runtime uniform; fall back to compile-time macro when unbound (0).
    int lt_spatial_sample_count = max(PH_LIGHTTREE_SPATIAL_REUSE_SAMPLES, 1);
    if (ph_restir_spatial_sample_count > 0.0) {
        lt_spatial_sample_count = max(int(floor(ph_restir_spatial_sample_count)), 1);
    }

    // numDisocclusionBoostSamples: SDK default exactly 8 (ReSTIRDI.cpp line 85).
    // When unbound (0.0): use exactly 8 (not max with sampleCount — SDK default is 8 unconditionally).
    // When explicitly set: use the provided value, clamped to at least the normal sample count.
    int lt_disocclusion_boost_samples = 8;
    if (ph_restir_spatial_boost_samples > 0.0) {
        lt_disocclusion_boost_samples = max(int(floor(ph_restir_spatial_boost_samples)), lt_spatial_sample_count);
    }

    // targetHistoryLength: SDK default 0 (ReSTIRDI.cpp line 85).
    // Semantics from SpatialResampling.hlsli: boost fires when M < targetHistoryLength.
    // When targetHistoryLength == 0: M < 0 is never true, so NO boost by default.
    // Boost only activates when targetHistoryLength > 0 and M < targetHistoryLength.
    float lt_target_history_length = (ph_restir_spatial_target_history > 0.0)
        ? ph_restir_spatial_target_history
        : 0.0f;

    // RTXDI SpatialResampling.hlsli lines 52-54: numSpatialSamples based on centerSample.M.
    int numSpatialSamples = lt_spatial_sample_count;
    if (lt_target_history_length > 0.0 && centerSample.M < lt_target_history_length) {
        numSpatialSamples = max(lt_disocclusion_boost_samples, lt_spatial_sample_count);
    }
    // RTXDI_DISpatialResamplingWithPairwiseMIS does NOT clamp numSpatialSamples.
    // The non-pairwise RTXDI_DISpatialResampling (line 174) clamps to 32, but that is
    // a different function. No cap here to match the pairwise reference exactly.

    // Use ph_restir_spatial_radius runtime uniform; fall back to compile-time macro when unbound (0).
    float spatialRadius = ph_restir_spatial_radius > 0.0
        ? max(ph_restir_spatial_radius, 1.0f)
        : max(PH_LIGHTTREE_SPATIAL_REUSE_RADIUS, 1.0f);

    // Use ph_restir_spatial_depth/normal_threshold runtime uniforms; fall back to constants when unbound (0).
    float spatialDepthThreshold = ph_restir_spatial_depth_threshold > 0.0
        ? ph_restir_spatial_depth_threshold
        : lt_depth_threshold;
    float spatialNormalThreshold = ph_restir_spatial_normal_threshold > 0.0
        ? ph_restir_spatial_normal_threshold
        : lt_surface_normal_threshold;

    // RTXDI line 57: uint startIdx = uint(RTXDI_GetNextRandom(rng) * params.neighborOffsetMask);
    // neighborOffsetMask = lt_neighbor_offset_count - 1 (power-of-2 bitmask).
    uint neighborOffsetMask = uint(lt_neighbor_offset_count - 1);
    uint startIdx = uint(RTXDI_GetNextRandom(rng) * float(neighborOffsetMask));

    // State reservoir — matches RTXDI_DISpatialResamplingWithPairwiseMIS variable name "state".
    Reservoir state = rtxdi_empty_reservoir();

    if (biasCorrectionMode == RTXDI_BIAS_CORRECTION_PAIRWISE) {
        // ============================================================
        // PAIRWISE MIS path — RTXDI_DISpatialResamplingWithPairwiseMIS
        // (SpatialResampling.hlsli lines 36-122)
        // ============================================================
        state.canonicalWeight = 0.0f;
        // RTXDI SpatialResampling.hlsli line 58: uint validSpatialSamples = 0
        int validSpatialSamples = 0;

        for (int i = 0; i < numSpatialSamples; i++) {
            int sampleIdx = int((startIdx + uint(i)) & neighborOffsetMask);
            ivec2 spatialOffset = lt_calculate_spatial_resampling_offset(sampleIdx, spatialRadius);
            // RTXDI SpatialResampling.hlsli line 65: int2 idx = int2(pixelPosition) + spatialOffset
            ivec2 idx = centerPixelPos + spatialOffset;
            // RTXDI SpatialResampling.hlsli line 66: RAB_ClampSamplePositionIntoView
            // Reflects at screen edges (not clamps) — ports RAB_SpatialHelpers.hlsli lines 20-33.
            idx = RAB_ClampSamplePositionIntoView(idx, false);
            // RTXDI SpatialResampling.hlsli line 68: RTXDI_ActivateCheckerboardPixel
            RTXDI_ActivateCheckerboardPixel(idx, false, activeCheckerboardField);

            DirectSurface neighborSurface = lt_load_surface(idx);
            if (!lt_is_valid_surface(neighborSurface)) continue;

            if (!lt_surface_matches(centerSurface, neighborSurface, spatialDepthThreshold, spatialNormalThreshold)) continue;

            if (lt_enable_material_similarity_test && !lt_materials_similar(centerSurface, neighborSurface)) continue;

            // Always load the neighbor sample.
            // RTXDI SpatialResampling.hlsli line 85: RTXDI_DIReservoir neighborSample = RTXDI_LoadDIReservoir(...)
            ivec2 neighborReservoirPos = lt_pass_pixel_to_reservoir_pos(idx);
            Reservoir neighborSample = rtxdi_empty_reservoir();
            lt_load_direct_temporal_reservoir(neighborReservoirPos, neighborSurface, neighborSample);
            rtxdi_prepare_spatial_reuse(neighborSample, spatialOffset);

            // RTXDI SpatialResampling.hlsli lines 89-93: discountNaiveSamples check.
            // Only count this neighbor as valid after it passes the discount check.
            if (RTXDI_IsValidDIReservoir(neighborSample)) {
                if (lt_discount_naive_samples && neighborSample.M <= rtxdi_naive_sampling_m_threshold) continue;
            }

            // RTXDI SpatialResampling.hlsli line 95: validSpatialSamples++
            // Surface-similar neighbors count even if the loaded reservoir is invalid;
            // only discounted naive samples are skipped before the increment.
            validSpatialSamples++;

            // RTXDI SpatialResampling.hlsli line 98: if (neighborSample.M <= 0) continue;
            if (neighborSample.M <= 0.0f) continue;

            // RTXDI SpatialResampling.hlsli lines 101-104: RTXDI_StreamNeighborWithPairwiseMIS
            RTXDI_StreamNeighborWithPairwiseMIS(
                state,
                RTXDI_GetNextRandom(rng),
                neighborSample,
                neighborSurface,
                centerSample,
                centerSurface,
                float(numSpatialSamples)
            );
        }

        // RTXDI SpatialResampling.hlsli line 108: canonicalWeight fallback when no valid neighbors.
        if (validSpatialSamples <= 0) {
            state.canonicalWeight = 1.0f;
        }
        // RTXDI SpatialResampling.hlsli line 111: RTXDI_StreamCanonicalWithPairwiseStep
        RTXDI_StreamCanonicalWithPairwiseStep(state, RTXDI_GetNextRandom(rng), centerSample, centerSurface);
        // RTXDI SpatialResampling.hlsli line 113: RTXDI_FinalizeResampling(state, 1.0, float(max(1, validSpatialSamples)))
        RTXDI_FinalizeResampling(state, 1.0, float(max(1, validSpatialSamples)));

    } else {
        // ============================================================
        // Non-pairwise path — RTXDI_DISpatialResampling
        // (SpatialResampling.hlsli lines 132-306).
        // NOTE: This is a DIFFERENT RTXDI function from RTXDI_DISpatialResamplingWithPairwiseMIS.
        // Supports OFF (1/M), BASIC (two-pass MIS), and RAY_TRACED modes.
        // ============================================================

        // First pass: combine center + neighbors into state (lines 149-237).
        // selected tracks the first-pass neighbor index exactly like RTXDI; the selected sample's
        // replay identity comes from state.lightIndex/sampleUv after combination, not from cached placeholders.
        int selected = -1;
        uint cachedResult = 0u;  // bitmask: bit i set iff neighbor passed the first-loop cache point exactly like RTXDI

        // RTXDI SpatialResampling.hlsli line 169: clamp numSpatialSamples to 32.
        // Required because cachedResult is a single uint (32-bit bitmask) and cannot track
        // more than 32 neighbors. The pairwise path does NOT have this cap.
        numSpatialSamples = min(numSpatialSamples, 32);

        // Seed with center sample (SpatialResampling.hlsli line 164).
        RTXDI_CombineDIReservoirs(state, centerSample, 0.5f, centerSample.targetPdf);

        for (int i = 0; i < numSpatialSamples; i++) {
            int sampleIdx = int((startIdx + uint(i)) & neighborOffsetMask);
            ivec2 spatialOffset = lt_calculate_spatial_resampling_offset(sampleIdx, spatialRadius);
            ivec2 idx = centerPixelPos + spatialOffset;
            // RTXDI SpatialResampling.hlsli line 66: RAB_ClampSamplePositionIntoView
            // Reflects at screen edges (not clamps) — ports RAB_SpatialHelpers.hlsli lines 20-33.
            idx = RAB_ClampSamplePositionIntoView(idx, false);
            // RTXDI SpatialResampling.hlsli line 68: RTXDI_ActivateCheckerboardPixel
            RTXDI_ActivateCheckerboardPixel(idx, false, activeCheckerboardField);

            DirectSurface neighborSurface = lt_load_surface(idx);
            if (!lt_is_valid_surface(neighborSurface)) continue;

            if (!lt_surface_matches(centerSurface, neighborSurface, spatialDepthThreshold, spatialNormalThreshold)) continue;

            if (lt_enable_material_similarity_test && !lt_materials_similar(centerSurface, neighborSurface)) continue;

            ivec2 neighborReservoirPos = lt_pass_pixel_to_reservoir_pos(idx);
            Reservoir neighborSample = rtxdi_empty_reservoir();
            lt_load_direct_temporal_reservoir(neighborReservoirPos, neighborSurface, neighborSample);
            rtxdi_prepare_spatial_reuse(neighborSample, spatialOffset);

            // Cache this neighbor at the same point as RTXDI SpatialResampling.hlsli line 211:
            // after load/prep and before naive-sample discount / weight evaluation.
            cachedResult |= (1u << uint(i));

            float neighborWeight = 0.0f;
            if (RTXDI_IsValidDIReservoir(neighborSample)) {
                if (lt_discount_naive_samples && neighborSample.M <= rtxdi_naive_sampling_m_threshold) {
                    continue;
                }

                // Evaluate neighbor's light at the center surface (SpatialResampling.hlsli lines 223-228).
                LightSample candidateSample = light_sample_decode(
                    neighborSample,
                    centerSurface,
                    false
                );
                neighborWeight = lt_surface_target_pdf(centerSurface, candidateSample);
            }

            bool neighborSelected = RTXDI_CombineDIReservoirs(state, neighborSample, RTXDI_GetNextRandom(rng), neighborWeight);
            if (neighborSelected) {
                selected = i;
            }
        }

        // Second pass and finalization.
        if (RTXDI_IsValidDIReservoir(state)) {
            if (biasCorrectionMode >= RTXDI_BIAS_CORRECTION_BASIC) {
                // Two-pass MIS normalization (SpatialResampling.hlsli lines 241-296).
                float pi = state.targetPdf;
                float piSum = state.targetPdf * centerSample.M;

                for (int i = 0; i < numSpatialSamples; i++) {
                    if ((cachedResult & (1u << uint(i))) == 0u) continue;

                    int sampleIdx = int((startIdx + uint(i)) & neighborOffsetMask);
                    ivec2 spatialOffset = lt_calculate_spatial_resampling_offset(sampleIdx, spatialRadius);
                    ivec2 idx = centerPixelPos + spatialOffset;
                    // RTXDI SpatialResampling.hlsli line 66: RAB_ClampSamplePositionIntoView
                    // Reflects at screen edges (not clamps) — ports RAB_SpatialHelpers.hlsli lines 20-33.
                    idx = RAB_ClampSamplePositionIntoView(idx, false);
                    RTXDI_ActivateCheckerboardPixel(idx, false, activeCheckerboardField);

                    DirectSurface neighborSurface = lt_load_surface(idx);
                    if (!lt_is_valid_surface(neighborSurface)) continue;

                    // Evaluate selected sample at this neighbor's surface (line 267-270).
                    float ps = 0.0f;
                    if (RTXDI_IsValidDIReservoir(state)) {
                        LightSample selectedSampleAtNeighbor = light_sample_decode(
                            state,
                            neighborSurface,
                            false
                        );
                        ps = lt_surface_target_pdf(neighborSurface, selectedSampleAtNeighbor);

                        // RAY_TRACED: conservative visibility check on the neighbor surface
                        // (SpatialResampling.hlsli lines 272-279: RAB_GetConservativeVisibility).
                        if (biasCorrectionMode == RTXDI_BIAS_CORRECTION_RAY_TRACED && ps > 0.0f) {
                            if (selectedSampleAtNeighbor.index >= 0) {
                                float hitDist = light_sample_trace_hit_surface(selectedSampleAtNeighbor, false, neighborSurface);
                                if (hitDist <= 0.0f || selectedSampleAtNeighbor.index < 0) {
                                    ps = 0.0f;
                                }
                            } else {
                                ps = 0.0f;
                            }
                        }
                    }

                    ivec2 neighborReservoirPos = lt_pass_pixel_to_reservoir_pos(idx);
                    Reservoir neighborSample = rtxdi_empty_reservoir();
                    lt_load_direct_temporal_reservoir(neighborReservoirPos, neighborSurface, neighborSample);

                    pi = (selected == i) ? ps : pi;
                    piSum += ps * neighborSample.M;
                }

                RTXDI_FinalizeResampling(state, pi, piSum);
            } else {
                // OFF mode: 1/M normalization (SpatialResampling.hlsli line 301).
                RTXDI_FinalizeResampling(state, 1.0f, state.M);
            }
        }
    }

    reservoir_frag_out = rtxdi_pack_reservoir(state);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(state);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(state);
}
