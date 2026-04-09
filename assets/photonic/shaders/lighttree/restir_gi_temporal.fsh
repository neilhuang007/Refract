#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 indirect_temporal_position_frag_out;
layout(location = 1) out vec4 indirect_temporal_normal_frag_out;
layout(location = 2) out vec4 indirect_temporal_radiance_frag_out;
layout(location = 3) out vec4 indirect_temporal_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/restir_gi_bridge.glsl"

const int lt_gi_temporal_search_radius = 1;
const int lt_gi_temporal_sample_count = 5;

void main() {
    RTXDI_GIReservoirStore temporalStore = gi_make_invalid_reservoir_store();
    int activeCheckerboardField = int(ph_restir_active_checkerboard_field);
    ivec2 currentReservoirPos = lt_current_reservoir_pos();
    if (!lt_is_active_reservoir_lane(currentReservoirPos)) {
        indirect_temporal_position_frag_out = temporalStore.positionData;
        indirect_temporal_normal_frag_out = temporalStore.normalData;
        indirect_temporal_radiance_frag_out = temporalStore.radianceData;
        indirect_temporal_meta_frag_out = temporalStore.metaData;
        return;
    }

    ivec2 pixelPosition = RTXDI_ReservoirPosToPixelPos(currentReservoirPos, activeCheckerboardField);
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        indirect_temporal_position_frag_out = temporalStore.positionData;
        indirect_temporal_normal_frag_out = temporalStore.normalData;
        indirect_temporal_radiance_frag_out = temporalStore.radianceData;
        indirect_temporal_meta_frag_out = temporalStore.metaData;
        return;
    }

    RAB_Surface currentSurface = lt_load_surface(pixelPosition);
    if (!lt_is_valid_surface(currentSurface)) {
        indirect_temporal_position_frag_out = temporalStore.positionData;
        indirect_temporal_normal_frag_out = temporalStore.normalData;
        indirect_temporal_radiance_frag_out = temporalStore.radianceData;
        indirect_temporal_meta_frag_out = temporalStore.metaData;
        return;
    }
    RTXDI_GIReservoir inputReservoir = RTXDI_LoadGIReservoir(gi_buffer_index_initial, currentReservoirPos, activeCheckerboardField);
    RTXDI_GIReservoir state = RTXDI_EmptyGIReservoir();
    float selectedTargetPdf = 0.0f;
    float temporalMaxHistory = gi_runtime_temporal_max_history();
    float temporalDepthThreshold = gi_runtime_temporal_depth_threshold();
    float temporalNormalThreshold = gi_runtime_temporal_normal_threshold();
    float temporalMaxReservoirAge = gi_runtime_temporal_max_reservoir_age();
    bool enableFallbackSampling = gi_runtime_enable_fallback_sampling();
    bool enablePermutationSampling = gi_runtime_enable_permutation_sampling();
    int biasCorrectionMode = gi_runtime_bias_correction_mode(ph_restir_temporal_bias_mode);

    if (RTXDI_IsValidGIReservoir(inputReservoir)) {
        selectedTargetPdf = RAB_GetGISampleTargetPdfForSurface(currentSurface, inputReservoir.selected);
        RTXDI_CombineGIReservoirs(state, inputReservoir, 0.5f, selectedTargetPdf);
    }

    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(
        uvec2(currentReservoirPos),
        uint(frameCounter),
        RTXDI_GI_TEMPORAL_RESAMPLING_RANDOM_SEED
    );
    temporalMaxReservoirAge *= 0.5f + RTXDI_GetNextRandom(rng) * 0.5f;
    vec4 motionVector = texelFetch(radiosity_motion, pixelPosition, 0);
    if (motionVector.w > 0.5f) {
        motionVector.xy += vec2(0.5f);
    }
    ivec2 prevPos = ivec2(round(vec2(pixelPosition) + motionVector.xy));
    float currentLinearDepth = ph_linear_view_depth(modelview_projection, currentSurface.worldPos);
    float expectedPrevLinearDepth = currentLinearDepth + motionVector.z;
    uint uniformRandomNumber = ph_restir_temporal_uniform_random != 0
        ? uint(ph_restir_temporal_uniform_random)
        : uint(frameCounter);
    int temporalSampleStartIdx = int(RTXDI_GetNextRandom(rng) * 8.0f);
    float temporalSearchRadius = (activeCheckerboardField == 0) ? 1.0f : 2.0f;

    RTXDI_GIReservoir temporalReservoir = RTXDI_EmptyGIReservoir();
    RAB_Surface temporalSurface = lt_empty_surface();
    bool foundTemporalReservoir = false;

    for (int i = 0; i < lt_gi_temporal_sample_count + (enableFallbackSampling ? 1 : 0); i++) {
        bool isFirstSample = (i == 0);
        bool isFallbackSample = (i == lt_gi_temporal_sample_count);
        ivec2 idx = prevPos;

        if (isFallbackSample) {
            idx = pixelPosition;
        } else if (!isFirstSample) {
            idx += lt_calculate_temporal_resampling_offset(temporalSampleStartIdx + i, int(temporalSearchRadius));
        }

        if ((enablePermutationSampling && isFirstSample) || isFallbackSample) {
            RTXDI_ApplyPermutationSampling(idx, uniformRandomNumber);
        }

        RTXDI_ActivateCheckerboardPixel(idx, true, activeCheckerboardField);

        if (!lt_is_viewport_uv_in_bounds(idx)) {
            continue;
        }

        RAB_Surface candidateSurface = lt_load_previous_surface(idx);
        if (!lt_is_valid_surface(candidateSurface)) {
            continue;
        }

        if (!isFallbackSample && !RTXDI_IsValidTemporalNeighbor(
            currentSurface,
            candidateSurface,
            expectedPrevLinearDepth,
            temporalNormalThreshold,
            temporalDepthThreshold
        )) {
            ivec2 prevReservoirPos = RTXDI_PixelPosToReservoirPos(idx, activeCheckerboardField);
            RTXDI_GIReservoir candidateReservoir = RTXDI_LoadPreviousGIReservoir(prevReservoirPos, activeCheckerboardField);
            if (!gi_sample_is_skylight(candidateReservoir, currentSurface)) {
                continue;
            }
        }

        if (!lt_materials_similar(currentSurface, candidateSurface)) {
            ivec2 prevReservoirPos = RTXDI_PixelPosToReservoirPos(idx, activeCheckerboardField);
            RTXDI_GIReservoir candidateReservoir = RTXDI_LoadPreviousGIReservoir(prevReservoirPos, activeCheckerboardField);
            if (!gi_sample_is_skylight(candidateReservoir, currentSurface)) {
                continue;
            }
        }

        ivec2 prevReservoirPos = RTXDI_PixelPosToReservoirPos(idx, activeCheckerboardField);
        RTXDI_GIReservoir candidateReservoir = RTXDI_LoadPreviousGIReservoir(prevReservoirPos, activeCheckerboardField);
        if (!RTXDI_IsValidGIReservoir(candidateReservoir)) {
            continue;
        }

        temporalReservoir = candidateReservoir;
        temporalSurface = candidateSurface;
        foundTemporalReservoir = true;
        break;
    }

    if (foundTemporalReservoir) {
        float jacobian = RTXDI_GICalculateJacobian(currentSurface, temporalSurface, temporalReservoir.selected);
        if (jacobian <= 0.0f) {
            foundTemporalReservoir = false;
        } else {
            temporalReservoir.weight_sum *= jacobian;
            temporalReservoir.samples = min(temporalReservoir.samples, temporalMaxHistory);
            temporalReservoir.age += 1.0f;
            if (temporalReservoir.age > temporalMaxReservoirAge) {
                foundTemporalReservoir = false;
            }
        }
    }

    bool selectedPreviousSample = false;
    if (foundTemporalReservoir) {
        float targetPdf = RAB_GetGISampleTargetPdfForSurface(currentSurface, temporalReservoir.selected);
        selectedPreviousSample = RTXDI_CombineGIReservoirs(state, temporalReservoir, RTXDI_GetNextRandom(rng), targetPdf);
        if (selectedPreviousSample) {
            selectedTargetPdf = targetPdf;
        }
    }

    if (biasCorrectionMode >= gi_bias_correction_mode_basic && foundTemporalReservoir) {
        float pi = selectedTargetPdf;
        float piSum = selectedTargetPdf * inputReservoir.samples;
        float temporalP = RAB_GetGISampleTargetPdfForSurface(temporalSurface, state.selected);
        if (biasCorrectionMode == gi_bias_correction_mode_ray_traced && temporalP > 0.0f && !RAB_GetTemporalConservativeVisibility(currentSurface, temporalSurface, state.selected.position)) {
            temporalP = 0.0f;
        }
        pi = selectedPreviousSample ? temporalP : pi;
        piSum += temporalP * temporalReservoir.samples;
        RTXDI_FinalizeGIResampling(state, pi, piSum * selectedTargetPdf);
    } else {
        RTXDI_FinalizeGIResampling(state, 1.0f, selectedTargetPdf * state.samples);
    }

    temporalStore = gi_make_reservoir_store(state);
    indirect_temporal_position_frag_out = temporalStore.positionData;
    indirect_temporal_normal_frag_out = temporalStore.normalData;
    indirect_temporal_radiance_frag_out = temporalStore.radianceData;
    indirect_temporal_meta_frag_out = temporalStore.metaData;
}
