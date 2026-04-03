#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 indirect_frag_out;
layout(location = 1) out vec4 indirect_variance_frag_out;
layout(location = 2) out vec4 handheld_frag_out;
layout(location = 3) out vec4 indirect_reservoir_position_frag_out;
layout(location = 4) out vec4 indirect_reservoir_normal_frag_out;
layout(location = 5) out vec4 indirect_reservoir_radiance_frag_out;
layout(location = 6) out vec4 indirect_reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/restir_gi_bridge.glsl"

const int lt_gi_spatial_sample_count = 2;

void main() {
    handheld_frag_out = vec4(0.0f);
    RTXDI_GIReservoirStore outputStore = gi_make_invalid_reservoir_store();
    indirect_reservoir_position_frag_out = outputStore.positionData;
    indirect_reservoir_normal_frag_out = outputStore.normalData;
    indirect_reservoir_radiance_frag_out = outputStore.radianceData;
    indirect_reservoir_meta_frag_out = outputStore.metaData;

    handheld_frag_out = lt_build_handheld_stage();

    RAB_Surface currentSurface = lt_load_surface(tex_coord);
    if (!lt_is_valid_surface(currentSurface)) {
        indirect_frag_out = vec4(0.0f);
        indirect_variance_frag_out = vec4(0.0f);
        return;
    }

    RTXDI_GIReservoir initialReservoir = RTXDI_LoadGIReservoir(gi_buffer_index_initial, tex_coord);

    int activeCheckerboardField = ph_restir_active_checkerboard_field;
    ivec2 currentReservoirPos = RTXDI_PixelPosToReservoirPos(tex_coord, activeCheckerboardField);
    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(
        uvec2(currentReservoirPos),
        uint(frameCounter),
        RTXDI_GI_SPATIAL_RESAMPLING_RANDOM_SEED
    );
    RTXDI_GIReservoir currentReservoir = RTXDI_LoadGIReservoir(gi_buffer_index_spatial, currentReservoirPos, activeCheckerboardField);
    RTXDI_GIReservoir state = RTXDI_EmptyGIReservoir();
    float selectedTargetPdf = 0.0f;
    float inputM = 0.0f;
    uint cachedResult = 0u;
    int selectedNeighborIndex = -1;
    int neighborSampleStartIdx = int(RTXDI_GetNextRandom(rng) * float(lt_neighbor_offset_count - 1));
    int activeSpatialSampleCount = gi_runtime_spatial_sample_count();
    float spatialReuseRadius = gi_runtime_spatial_radius();
    float spatialDepthThreshold = gi_runtime_spatial_depth_threshold();
    float spatialNormalThreshold = gi_runtime_spatial_normal_threshold();
    int biasCorrectionMode = gi_runtime_bias_correction_mode(ph_restir_spatial_bias_mode);

    if (RTXDI_IsValidGIReservoir(currentReservoir)) {
        selectedTargetPdf = RAB_GetGISampleTargetPdfForSurface(currentSurface, currentReservoir.selected);
        RTXDI_CombineGIReservoirs(state, currentReservoir, 0.5f, selectedTargetPdf);
        inputM = currentReservoir.samples;
    }

    for (int i = 0; i < activeSpatialSampleCount; i++) {
        ivec2 neighborUv = tex_coord + lt_calculate_spatial_resampling_offset(
            neighborSampleStartIdx + i,
            spatialReuseRadius
        );
        neighborUv = RAB_ClampSamplePositionIntoView(neighborUv, false);
        RTXDI_ActivateCheckerboardPixel(neighborUv, false, activeCheckerboardField);

        RAB_Surface neighborSurface = lt_load_surface(neighborUv);
        if (!lt_surface_matches(currentSurface, neighborSurface, spatialDepthThreshold, spatialNormalThreshold)) {
            continue;
        }

        if (!lt_materials_similar(currentSurface, neighborSurface)) {
            continue;
        }

        ivec2 neighborReservoirPos = RTXDI_PixelPosToReservoirPos(neighborUv, activeCheckerboardField);
        RTXDI_GIReservoir neighborReservoir = RTXDI_LoadGIReservoir(gi_buffer_index_spatial, neighborReservoirPos, activeCheckerboardField);
        if (!RTXDI_IsValidGIReservoir(neighborReservoir)) {
            continue;
        }

        float jacobian = RTXDI_GICalculateJacobian(currentSurface, neighborSurface, neighborReservoir.selected);
        if (jacobian <= 0.0f) {
            continue;
        }

        float targetPdf = RAB_GetGISampleTargetPdfForSurface(currentSurface, neighborReservoir.selected);
        cachedResult |= (1u << uint(i));

        if (RTXDI_CombineGIReservoirs(state, neighborReservoir, RTXDI_GetNextRandom(rng), targetPdf * jacobian)) {
            selectedTargetPdf = targetPdf;
            selectedNeighborIndex = i;
        }
    }

    float normalizationNumerator = 1.0f;
    float normalizationDenominator = state.samples * selectedTargetPdf;
    if (biasCorrectionMode >= gi_bias_correction_mode_basic) {
        float pi = selectedTargetPdf;
        float piSum = selectedTargetPdf * inputM;

        for (int i = 0; i < activeSpatialSampleCount; i++) {
            if ((cachedResult & (1u << uint(i))) == 0u) {
                continue;
            }

            ivec2 neighborUv = tex_coord + lt_calculate_spatial_resampling_offset(
                neighborSampleStartIdx + i,
                spatialReuseRadius
            );
            neighborUv = RAB_ClampSamplePositionIntoView(neighborUv, false);
            RTXDI_ActivateCheckerboardPixel(neighborUv, false, activeCheckerboardField);

            RAB_Surface neighborSurface = lt_load_surface(neighborUv);
            ivec2 neighborReservoirPos = RTXDI_PixelPosToReservoirPos(neighborUv, activeCheckerboardField);
            RTXDI_GIReservoir neighborReservoir = RTXDI_LoadGIReservoir(gi_buffer_index_spatial, neighborReservoirPos, activeCheckerboardField);
            float ps = RAB_GetGISampleTargetPdfForSurface(neighborSurface, state.selected);

            if (biasCorrectionMode == gi_bias_correction_mode_ray_traced && ps > 0.0f && !RAB_GetConservativeVisibility(neighborSurface, state.selected.position)) {
                ps = 0.0f;
            }

            if (selectedNeighborIndex == i) {
                pi = ps;
            }

            piSum += ps * neighborReservoir.samples;
        }

        normalizationNumerator = pi;
        normalizationDenominator = selectedTargetPdf * piSum;
    }

    RTXDI_FinalizeGIResampling(state, normalizationNumerator, normalizationDenominator);

    if (!RTXDI_IsValidGIReservoir(state)) {
        indirect_frag_out = vec4(0.0f);
        indirect_variance_frag_out = vec4(0.0f);
        return;
    }

    vec3 shadedDiffuse = vec3(0.0f);
    vec3 shadedSpecular = vec3(0.0f);
    gi_shade_reservoir(currentSurface, state, initialReservoir, shadedDiffuse, shadedSpecular);

    vec3 demodulatedIndirect = max(shadedDiffuse + shadedSpecular, vec3(0.0f));
    float history = min(state.age + 1.0f, gi_runtime_temporal_max_history());
    float luma = ph_luminance(demodulatedIndirect);
    float secondMoment = luma * luma;
    float variance = max(secondMoment / max(history, 1.0f), 1e-6f);
    float confidence = 0.0f;

    indirect_frag_out = vec4(demodulatedIndirect, history);
    indirect_variance_frag_out = vec4(luma, secondMoment, variance, confidence);
    outputStore = gi_make_reservoir_store(state);
    indirect_reservoir_position_frag_out = outputStore.positionData;
    indirect_reservoir_normal_frag_out = outputStore.normalData;
    indirect_reservoir_radiance_frag_out = outputStore.radianceData;
    indirect_reservoir_meta_frag_out = outputStore.metaData;
}
