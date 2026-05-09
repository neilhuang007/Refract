// Split from light_tree_indirect_accumulation.fsh; GI resampling is duplicated across the two passes due to OpenGL's prohibition on mixed-resolution FBO attachments. Optimization opportunity: unify via a half-res lighting buffer + reconstruction pass.
#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 indirect_reservoir_position_frag_out;
layout(location = 1) out vec4 indirect_reservoir_normal_frag_out;
layout(location = 2) out vec4 indirect_reservoir_radiance_frag_out;
layout(location = 3) out vec4 indirect_reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/restir_gi_bridge.glsl"

const int lt_gi_spatial_sample_count = 2;

void main() {
    RTXDI_GIReservoirStore outputStore = gi_make_invalid_reservoir_store();
    indirect_reservoir_position_frag_out = outputStore.positionData;
    indirect_reservoir_normal_frag_out = outputStore.normalData;
    indirect_reservoir_radiance_frag_out = outputStore.radianceData;
    indirect_reservoir_meta_frag_out = outputStore.metaData;

    ivec2 reservoirPos = ivec2(gl_FragCoord.xy);
    int activeField = int(ph_restir_active_checkerboard_field);
    ivec2 pixelPosition;
    if (activeField == 0) {
        pixelPosition = reservoirPos;
    } else {
        // RTXDI_ReservoirPosToPixelPos: expand half-width reservoir coord to full-res pixel.
        // Reference: RTXDI Libraries/Rtxdi/Include/Rtxdi/Utils/ReservoirAddressing.hlsli
        pixelPosition = ivec2(reservoirPos.x << 1, reservoirPos.y);
        pixelPosition.x += ((pixelPosition.y + activeField) & 1);
    }
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        return;
    }

    int activeCheckerboardField = activeField;
    ivec2 currentReservoirPos = reservoirPos;

    RAB_Surface currentSurface = lt_load_surface(pixelPosition);
    if (!lt_is_valid_surface(currentSurface)) {
        return;
    }

    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(
        uvec2(currentReservoirPos),
        uint(frameCounter),
        RTXDI_GI_SPATIAL_RESAMPLING_RANDOM_SEED
    );
    RTXDI_GIReservoir currentReservoir = RTXDI_LoadCurrentFrameGIReservoir(currentReservoirPos, activeCheckerboardField);
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
    int biasCorrectionMode = gi_runtime_bias_correction_mode(ph_restir_gi_spatial_bias_mode);

    if (RTXDI_IsValidGIReservoir(currentReservoir)) {
        selectedTargetPdf = RAB_GetGISampleTargetPdfForSurface(currentSurface, currentReservoir.selected);
        RTXDI_CombineGIReservoirs(state, currentReservoir, 0.5f, selectedTargetPdf);
        inputM = currentReservoir.samples;
    }

    for (int i = 0; i < activeSpatialSampleCount; i++) {
        ivec2 neighborUv = pixelPosition + lt_calculate_spatial_resampling_offset(
            neighborSampleStartIdx + i,
            spatialReuseRadius
        );
        neighborUv = RAB_ClampSamplePositionIntoView(neighborUv, false);
        RTXDI_ActivateCheckerboardPixel(neighborUv, false, activeCheckerboardField);

        RAB_Surface neighborSurface = lt_load_surface(neighborUv);
        if (!lt_surface_matches(currentSurface, neighborSurface, spatialDepthThreshold, spatialNormalThreshold)) {
            ivec2 neighborReservoirPos = RTXDI_PixelPosToReservoirPos(neighborUv, activeCheckerboardField);
            RTXDI_GIReservoir neighborReservoir = RTXDI_LoadCurrentFrameGIReservoir(neighborReservoirPos, activeCheckerboardField);
            if (!gi_sample_is_skylight(neighborReservoir, currentSurface)) {
                continue;
            }
        }

        if (!lt_materials_similar(currentSurface, neighborSurface)) {
            ivec2 neighborReservoirPos = RTXDI_PixelPosToReservoirPos(neighborUv, activeCheckerboardField);
            RTXDI_GIReservoir neighborReservoir = RTXDI_LoadCurrentFrameGIReservoir(neighborReservoirPos, activeCheckerboardField);
            if (!gi_sample_is_skylight(neighborReservoir, currentSurface)) {
                continue;
            }
        }

        ivec2 neighborReservoirPos = RTXDI_PixelPosToReservoirPos(neighborUv, activeCheckerboardField);
        RTXDI_GIReservoir neighborReservoir = RTXDI_LoadCurrentFrameGIReservoir(neighborReservoirPos, activeCheckerboardField);
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

            ivec2 neighborUv = pixelPosition + lt_calculate_spatial_resampling_offset(
                neighborSampleStartIdx + i,
                spatialReuseRadius
            );
            neighborUv = RAB_ClampSamplePositionIntoView(neighborUv, false);
            RTXDI_ActivateCheckerboardPixel(neighborUv, false, activeCheckerboardField);

            RAB_Surface neighborSurface = lt_load_surface(neighborUv);
            ivec2 neighborReservoirPos = RTXDI_PixelPosToReservoirPos(neighborUv, activeCheckerboardField);
            RTXDI_GIReservoir neighborReservoir = RTXDI_LoadCurrentFrameGIReservoir(neighborReservoirPos, activeCheckerboardField);
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
        return;
    }

    float history = min(state.age + 1.0f, 8.0f);
    state.age = history;

    outputStore = gi_make_reservoir_store(state);
    indirect_reservoir_position_frag_out = outputStore.positionData;
    indirect_reservoir_normal_frag_out = outputStore.normalData;
    indirect_reservoir_radiance_frag_out = outputStore.radianceData;
    indirect_reservoir_meta_frag_out = outputStore.metaData;
}
