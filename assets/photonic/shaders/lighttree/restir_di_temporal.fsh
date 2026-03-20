#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"

uniform float ph_debug_disable_temporal_reset;

// Runtime bias correction mode — matches RTXDI TemporalResampling.hlsli lines 173-212.
// Corresponds to RTXDI_DITemporalResamplingParameters::biasCorrectionMode (ReSTIRDIParameters.h line 96).
//   0 (OFF)        — 1/M normalization; no bias correction (RTXDI_BIAS_CORRECTION_OFF).
//   1 (BASIC)      — Recompute targetPdf at temporal surface; no visibility ray (RTXDI_BIAS_CORRECTION_BASIC).
//   2 (PAIRWISE)   — Pairwise MIS normalization (assuming every sample visible) (RTXDI_BIAS_CORRECTION_PAIRWISE).
//   3 (RAY_TRACED) — Same as BASIC but adds a shadow ray toward the temporal surface sample (RTXDI_BIAS_CORRECTION_RAY_TRACED).
// SDK default (ReSTIRDI.cpp line 57): BASIC (1). Use -1.0 as sentinel to explicitly request OFF.
// When unbound (0.0) falls back to SDK default BASIC.
uniform float ph_restir_temporal_bias_mode;

// RTXDI_PackedDIReservoir_MaxM = 0x3fff = 16383 (Reservoir.hlsli)
const float RTXDI_PackedDIReservoir_MaxM = 16383.0;
const int RTXDI_BIAS_CORRECTION_OFF = 0;
const int RTXDI_BIAS_CORRECTION_BASIC = 1;
const int RTXDI_BIAS_CORRECTION_PAIRWISE = 2;
const int RTXDI_BIAS_CORRECTION_RAY_TRACED = 3;

// Runtime uniforms for temporal parameters — wired from LightTreeRenderer.
// When unbound (0.0) each falls back to the RTXDI SDK default documented below.
uniform float ph_restir_temporal_permutation_sampling;   // SDK default: 1 (enabled) (ReSTIRDI.cpp line 61)
uniform float ph_restir_temporal_visibility_shortcut;    // SDK default: 0 (disabled) (ReSTIRDI.cpp line 60)
uniform int   ph_restir_temporal_uniform_random;         // SDK: uniformRandomNumber (per-frame Jenkins hash), provided by Iris as int and cast back to uint

// ENGINE-SPECIFIC EXTENSION (Fix #11): light_reload temporal reset guard.
// Not present in the RTXDI SDK. This engine-specific flag is set by LightRegistry when
// the light list changes substantially (e.g., chunk load/unload invalidates indices).
// When true, temporal history is discarded so stale reservoir light references cannot
// corrupt current-frame output. This is a sound extension: the SDK would require equivalent
// bookkeeping through its RAB_TranslateLightIndex returning -1 for all lights on a full reload.

bool RTXDI_LoadCurrentProposal(DirectSurface currentSurface, ivec2 reservoirPos, out Reservoir reservoir) {
    reservoir = RTXDI_EmptyDIReservoir();
    rtxdi_unpack_reservoir_at_surface(
        reservoir,
        texelFetch(radiosity_proposal_reservoirs, reservoirPos, 0),
        texelFetch(radiosity_proposal_reservoir_samples, reservoirPos, 0),
        texelFetch(radiosity_proposal_reservoir_meta, reservoirPos, 0),
        currentSurface,
        false
    );
    // RTXDI does not validate the proposal here — CombineDIReservoirs handles invalid samples gracefully.
    return true;
}

void RTXDI_StoreEmptyOutputs() {
    Reservoir emptyReservoir = RTXDI_EmptyDIReservoir();
    reservoir_frag_out = rtxdi_pack_reservoir(emptyReservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(emptyReservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(emptyReservoir);
}

void main() {
    ivec2 reservoirPos = lt_current_reservoir_pos();
    if (!lt_is_active_reservoir_lane(reservoirPos)) {
        RTXDI_StoreEmptyOutputs();
        return;
    }

    if (!is_in_world()) {
        RTXDI_StoreEmptyOutputs();
        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);
    rt_pos = world_pos - world_offset;
    bad_angle = is_bad_angle(world_pos, block_normal);

    DirectSurface currentSurface = lt_current_surface();
    ivec2 pixelPosition = lt_current_pixel_pos();
    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(uvec2(pixelPosition), uint(frameCounter), RTXDI_DI_TEMPORAL_RESAMPLING_RANDOM_SEED);

    // Step 1: Load curSample from proposal buffer
    // Don't abort on empty curSample — RTXDI proceeds unconditionally (TemporalResampling.hlsli
    // line 54: CombineDIReservoirs is always called). When curSample is empty (targetPdf=0,
    // weightSum=0, M=0) the combine is a no-op, and temporal history can still populate state.
    Reservoir curSample = RTXDI_EmptyDIReservoir();
    RTXDI_LoadCurrentProposal(currentSurface, reservoirPos, curSample);

    // RTXDI line 42: historyLimit = min(MaxM, uint(tparams.maxHistoryLength * curSample.M))
    // ph_restir_temporal_max_history is the runtime uniform matching tparams.maxHistoryLength.
    // SDK default (ReSTIRDI.cpp line 56): maxHistoryLength = 20.
    // Sentinel: -1.0 → SDK default (20), 0.0 (unbound) → SDK default (20), > 0 → explicit value.
    float resolvedMaxHistory = (ph_restir_temporal_max_history > 0.0)
        ? ph_restir_temporal_max_history
        : 20.0;
    // floor() matches RTXDI's uint() cast which truncates (not rounds) the product.
    float historyLimit = min(RTXDI_PackedDIReservoir_MaxM, floor(resolvedMaxHistory * curSample.M));

    // Step 2: Track selectedLightPrevID (RTXDI lines 44-49)
    // RTXDI: RAB_TranslateLightIndex(curSample.lightIndex, true) = current→previous.
    // ph_light_reverse_mapping provides the exact reverse: currentIndex → previousIndex.
    int selectedLightPrevID = -1;
    if (RTXDI_IsValidDIReservoir(curSample)) {
        int currentIdx = RTXDI_GetDIReservoirLightIndex(curSample);
        if (currentIdx >= 0 && currentIdx < ph_light_count) {
            selectedLightPrevID = ph_light_reverse_mapping[currentIdx];
        }
    }

    // Step 3: Initialize state (RTXDI lines 53-54)
    Reservoir state = RTXDI_EmptyDIReservoir();
    RTXDI_CombineDIReservoirs(state, curSample, 0.5, curSample.targetPdf);

    bool selectedPreviousSample = false;
    float previousM = 0.0;
    DirectSurface temporalSurface = lt_empty_surface();

    // RTXDI: temporal resampling always executes — no engine-specific history gate.
    // When the light list changes, RAB_TranslateLightIndex returns -1 for invalid lights,
    // which kills stale reservoirs through the standard remap path (lines 216-234).
    {
        // Step 4: Backproject using per-pixel motion vectors (RTXDI lines 57-67).
        vec3 motion = texelFetch(radiosity_motion, pixelPosition, 0).xyz;

        // RTXDI lines 59-62: sub-pixel jitter when permutation sampling is disabled.
        // SDK default (ReSTIRDI.cpp line 61): enablePermutationSampling = true.
        // Sentinel pattern (SDK-default-true): unbound (0.0) or -1.0 → true (SDK default).
        // Explicit false: pass -2.0 (< -1.5) to force disabled.
        bool enablePermutationSampling = (ph_restir_temporal_permutation_sampling < -1.5) ? false : true;
        if (!enablePermutationSampling) {
            motion.xy += vec2(RTXDI_GetNextRandom(rng), RTXDI_GetNextRandom(rng)) - 0.5;
        }

        // RTXDI line 64-65: float2 reprojectedSamplePosition = float2(pixelPosition) + motion.xy;
        vec2 reprojectedSamplePosition = vec2(pixelPosition) + motion.xy;
        ivec2 prevPos = ivec2(round(reprojectedSamplePosition));

        // RTXDI line 67: expectedPrevLinearDepth = currentLinearDepth + motion.z
        float currentLinearDepth = length(currentSurface.worldPos - world_camera_position);
        float expectedPrevLinearDepth = currentLinearDepth + motion.z;

        // SDK defaults (ReSTIRDI.cpp lines 59-60): depthThreshold=0.1, normalThreshold=0.5.
        // Sentinel: 0.0 (unbound) → SDK default; -1.0 → SDK default (explicit); > 0 → explicit value.
        float temporalDepthThreshold = (ph_restir_temporal_depth_threshold > 0.0)
            ? ph_restir_temporal_depth_threshold
            : 0.1;
        float temporalNormalThreshold = (ph_restir_temporal_normal_threshold > 0.0)
            ? ph_restir_temporal_normal_threshold
            : 0.5;

        DirectSurface temporalSurfaceCandidate;
        bool foundNeighbor = false;
        ivec2 spatialOffset = ivec2(0, 0);

        // Step 5: 9-tap search (RTXDI lines 75-109)
        // RTXDI TemporalResampling.hlsli line 71: radius = (activeCheckerboardField == 0) ? 4 : 8
        // This is a fixed SDK constant — not a runtime parameter. When checkerboard is off
        // (field == 0, the Minecraft/Photonics default) the radius is 4. When checkerboard
        // is active the radius doubles to 8 to cover both checkerboard fields.
        float searchRadius = (int(ph_restir_active_checkerboard_field) == 0) ? 4.0 : 8.0;
        for (int i = 0; i < 9; i++) {
            ivec2 offset = ivec2(0, 0);
            if (i > 0) {
                // RTXDI lines 80-81: random offsets
                offset.x = int((RTXDI_GetNextRandom(rng) - 0.5) * searchRadius);
                offset.y = int((RTXDI_GetNextRandom(rng) - 0.5) * searchRadius);
            }

            ivec2 idx = prevPos + offset;

            // RTXDI lines 85-88: apply permutation sampling on first candidate (i == 0).
            // RTXDI_ApplyPermutationSampling (ReservoirAddressing.hlsli lines 50-59):
            //   int2 offset = int2(uniformRandomNumber & 3, (uniformRandomNumber >> 2) & 3);
            //   prevPixelPos += offset;
            //   prevPixelPos.x ^= 3; prevPixelPos.y ^= 3;
            //   prevPixelPos -= offset;
            if (enablePermutationSampling && i == 0) {
                // Use the Java-provided per-frame Jenkins hash directly.
                uint uniformRandom = uint(ph_restir_temporal_uniform_random);
                ivec2 permOffset = ivec2(
                    int(uniformRandom & 3u),
                    int((uniformRandom >> 2u) & 3u)
                );
                idx += permOffset;
                idx.x ^= 3;
                idx.y ^= 3;
                idx -= permOffset;
            }

            // RTXDI line 90: RTXDI_ActivateCheckerboardPixel — no-op when field == 0 (Minecraft default).
            RTXDI_ActivateCheckerboardPixel(idx, true, int(ph_restir_active_checkerboard_field));

            // Platform safety: texelFetch with out-of-bounds UV is undefined in GLSL.
            // RTXDI does not need this check because buffer loads handle OOB internally.
            if (!lt_is_viewport_uv_in_bounds(idx)) {
                continue;
            }

            // RTXDI line 93: load previous surface
            temporalSurfaceCandidate = lt_load_previous_surface(idx);

            // RTXDI line 94: RAB_IsSurfaceValid — skip sky/empty pixels (zero normals)
            if (!lt_is_valid_surface(temporalSurfaceCandidate)) {
                continue;
            }

            // RTXDI lines 98-101: neighbor validation
            if (!RTXDI_IsValidTemporalNeighbor(
                currentSurface,
                temporalSurfaceCandidate,
                expectedPrevLinearDepth,
                temporalNormalThreshold,
                temporalDepthThreshold
            )) {
                continue;
            }

            spatialOffset = idx - prevPos;
            prevPos = idx;
            temporalSurface = temporalSurfaceCandidate;
            foundNeighbor = true;
            break;
        }

        // Step 6: Load and combine previous sample (RTXDI lines 114-171)
        if (foundNeighbor) {
            // RTXDI lines 118-120: convert prevPos through RTXDI_PixelPosToReservoirPos
            // and load from sourceBufferIndex. Our "sourceBufferIndex" is always the
            // previous frame's reservoir textures (prev_radiosity_*).
            ivec2 prevReservoirPos = RTXDI_PixelPosToReservoirPos(prevPos, int(ph_restir_active_checkerboard_field));
            Reservoir prevSample = RTXDI_EmptyDIReservoir();
            rtxdi_unpack_reservoir_at_surface(
                prevSample,
                texelFetch(prev_radiosity_reservoirs, prevReservoirPos, 0),
                texelFetch(prev_radiosity_reservoir_samples, prevReservoirPos, 0),
                texelFetch(prev_radiosity_reservoir_meta, prevReservoirPos, 0),
                temporalSurface,
                false  // remap handled manually below to track originalPrevLightID
            );

            // RTXDI line 121: Cap M to historyLimit
            prevSample.M = min(prevSample.M, historyLimit);

            // RTXDI lines 122-123: unconditional spatialDistance and age update
            prevSample.spatialDistance += vec2(spatialOffset);
            prevSample.age += 1.0;

            // RTXDI line 125: save original light ID before remap
            int originalPrevLightID = RTXDI_GetDIReservoirLightIndex(prevSample);

            // RTXDI lines 128-148: light index remapping.
            // RTXDI: mappedLightID = RAB_TranslateLightIndex(prevLightIndex, false)
            // The mapping SSBO is sized to maxLights; previous-frame indices can exceed
            // ph_light_count (current count) but still be valid in the mapping buffer.
            if (RTXDI_IsValidDIReservoir(prevSample)) {
                int previousFrameLightIndex = RTXDI_GetDIReservoirLightIndex(prevSample);
                int mappedLightID = -1;
                if (previousFrameLightIndex >= 0 && previousFrameLightIndex < ph_lights_array_mapping.length()) {
                    mappedLightID = ph_lights_array_mapping[previousFrameLightIndex];
                }

                // RTXDI line 137: if (mappedLightID < 0) — only kill on negative (light disappeared).
                // RTXDI does NOT check against current light count; a valid remap result is trusted.
                if (mappedLightID < 0) {
                    // RTXDI lines 140-141: kill the reservoir
                    prevSample.weightSum = 0.0;
                    prevSample.lightData = 0u;
                    // RTXDI: only clears weightSum and lightData. sampleUv (uvData) is left as-is.
                } else {
                    // RTXDI lines 145-146: only update the light ID.
                    // RTXDI does NOT update sampleUv on a successful remap — the stored sample point
                    // is immutable (it was importance-sampled on the original light surface).
                    prevSample.lightData = rtxdi_make_light_data(mappedLightID);
                    // sampleUv stays unchanged — it is the immutable stored sample point.
                }
            }

            // RTXDI line 150
            previousM = prevSample.M;

            // RTXDI lines 152-162: evaluate weightAtCurrent (guarded by RTXDI_IsValidDIReservoir)
            float weightAtCurrent = 0.0;
            if (RTXDI_IsValidDIReservoir(prevSample)) {
                // RTXDI: RAB_SamplePolymorphicLight with stored UV.
                // Photonics: stored world position (point lights, no UV parameterization).
                weightAtCurrent = rtxdi_target_pdf_at_surface(prevSample, currentSurface);
            }

            // RTXDI line 164: combine
            bool sampleSelected = RTXDI_CombineDIReservoirs(
                state, prevSample, RTXDI_GetNextRandom(rng), weightAtCurrent);

            // RTXDI lines 165-170
            if (sampleSelected) {
                selectedPreviousSample = true;
                selectedLightPrevID = originalPrevLightID;
            }
        }
    }

    // Step 7: Bias correction (RTXDI TemporalResampling.hlsli lines 173-212).
    // SDK default (ReSTIRDI.cpp line 57): BASIC (1).
    // When ph_restir_temporal_bias_mode is 0.0 (unbound) fall back to SDK default BASIC.
    // Use -1.0 as sentinel to explicitly select OFF (1/M normalization).
    int biasCorrectionMode;
    if (ph_restir_temporal_bias_mode < -0.5) {
        // Sentinel -1.0: explicit OFF
        biasCorrectionMode = RTXDI_BIAS_CORRECTION_OFF;
    } else if (ph_restir_temporal_bias_mode < 0.5) {
        // Unbound (0.0): SDK default BASIC
        biasCorrectionMode = RTXDI_BIAS_CORRECTION_BASIC;
    } else {
        biasCorrectionMode = int(round(ph_restir_temporal_bias_mode));
    }

    if (biasCorrectionMode >= RTXDI_BIAS_CORRECTION_BASIC) {
        // RTXDI lines 177-178
        float pi = state.targetPdf;
        float piSum = state.targetPdf * curSample.M;

        // RTXDI line 180
        if (RTXDI_IsValidDIReservoir(state) && selectedLightPrevID >= 0 && previousM > 0.0) {
            float temporalP = 0.0;

            // RTXDI lines 184-190: RAB_LoadLightInfo(selectedLightPrevID, true).
            // Reconstruct the selected previous-frame sample from stored reservoir replay data,
            // keeping the original previous-frame light ID and immutable stored UV semantics.
            Reservoir selectedPrevReplay = state;
            selectedPrevReplay.lightData = rtxdi_make_light_data(selectedLightPrevID);
            LightSample prevLightSample = light_sample_decode_previous(
                selectedPrevReplay,
                temporalSurface
            );
            temporalP = max(lt_surface_target_pdf(temporalSurface, prevLightSample), 0.0);

            // RTXDI lines 192-199: RAY_TRACED mode — RAB_GetTemporalConservativeVisibility.
            // Fix #6: trace the SAME sample that computed temporalP — built from prevLight
            // (previous-frame buffer, selectedLightPrevID) at temporalSurface.
            // RTXDI TemporalResampling.hlsli constructs selectedSampleAtTemporal from
            // selectedLightPrev (not the remapped current-frame light) before tracing.
            // Using load_light(state.lightIndex) would give the current-frame light which
            // may differ in position from the previous-frame light used for temporalP.
            // ph_restir_temporal_visibility_shortcut: SDK default false (ReSTIRDI.cpp line 60).
            // Sentinel: -1.0 → SDK default (false), 0.0 → false, >= 0.5 → true.
            bool enableVisibilityShortcut = (ph_restir_temporal_visibility_shortcut < -0.5)
                ? false
                : (ph_restir_temporal_visibility_shortcut >= 0.5);
            if (biasCorrectionMode == RTXDI_BIAS_CORRECTION_RAY_TRACED
                    && temporalP > 0.0
                    && (!selectedPreviousSample || !enableVisibilityShortcut)) {
                // Reuse prevLightSample already built above — same light/position/surface as temporalP.
                // This matches RTXDI selectedSampleAtTemporal in TemporalResampling.hlsli lines 184-199.
                LightSample visSample = prevLightSample;
                if (visSample.index >= 0) {
                    float hitDist = light_sample_trace_hit_surface(visSample, false, temporalSurface);
                    if (hitDist <= 0.0f) {
                        temporalP = 0.0;
                    }
                } else {
                    temporalP = 0.0;
                }
            }

            // RTXDI line 202
            pi = selectedPreviousSample ? temporalP : pi;
            // RTXDI line 203
            piSum += temporalP * previousM;
        }

        // RTXDI line 206
        RTXDI_FinalizeResampling(state, pi, piSum);
    } else {
        // RTXDI line 211: OFF mode — 1/M normalization (simple, biased).
        // Selected when biasCorrectionMode == RTXDI_BIAS_CORRECTION_OFF (0).
        RTXDI_FinalizeResampling(state, 1.0, state.M);
    }

    // Output
    reservoir_frag_out = rtxdi_pack_reservoir(state);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(state);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(state);
}
