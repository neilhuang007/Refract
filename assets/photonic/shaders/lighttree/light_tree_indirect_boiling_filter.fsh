#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 filtered_position_frag_out;
layout(location = 1) out vec4 filtered_normal_frag_out;
layout(location = 2) out vec4 filtered_radiance_frag_out;
layout(location = 3) out vec4 filtered_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/restir_gi_bridge.glsl"

float gi_boiling_filter_weight(RTXDI_GIReservoir reservoir) {
    return ph_luminance(max(reservoir.selected.radiance, vec3(0.0f))) * max(reservoir.weight_sum, 0.0f);
}

void main() {
    RTXDI_GIReservoirStore filteredStore = gi_make_invalid_reservoir_store();
    int activeCheckerboardField = int(ph_restir_active_checkerboard_field);
    ivec2 reservoirPos = lt_current_reservoir_pos();
    if (!lt_is_active_reservoir_lane(reservoirPos)) {
        filtered_position_frag_out = filteredStore.positionData;
        filtered_normal_frag_out = filteredStore.normalData;
        filtered_radiance_frag_out = filteredStore.radianceData;
        filtered_meta_frag_out = filteredStore.metaData;
        return;
    }

    ivec2 pixelPosition = RTXDI_ReservoirPosToPixelPos(reservoirPos, activeCheckerboardField);
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        filtered_position_frag_out = filteredStore.positionData;
        filtered_normal_frag_out = filteredStore.normalData;
        filtered_radiance_frag_out = filteredStore.radianceData;
        filtered_meta_frag_out = filteredStore.metaData;
        return;
    }

    RTXDI_GIReservoir reservoir = RTXDI_LoadGIReservoir(gi_buffer_index_temporal, reservoirPos, activeCheckerboardField);
    if (RTXDI_IsValidGIReservoir(reservoir)) {
        float nonzeroWeightSum = 0.0f;
        float nonzeroCount = 0.0f;

        for (int dy = -1; dy <= 1; ++dy) {
            for (int dx = -1; dx <= 1; ++dx) {
                ivec2 neighborPixel = pixelPosition + ivec2(dx, dy);
                if (!lt_is_viewport_uv_in_bounds(neighborPixel)) {
                    continue;
                }

                RTXDI_ActivateCheckerboardPixel(neighborPixel, false, activeCheckerboardField);
                if (!lt_is_viewport_uv_in_bounds(neighborPixel)) {
                    continue;
                }

                ivec2 neighborReservoirPos = RTXDI_PixelPosToReservoirPos(neighborPixel, activeCheckerboardField);
                RTXDI_GIReservoir neighborReservoir = RTXDI_LoadGIReservoir(gi_buffer_index_temporal, neighborReservoirPos, activeCheckerboardField);
                float neighborWeight = gi_boiling_filter_weight(neighborReservoir);
                if (neighborWeight > 0.0f) {
                    nonzeroWeightSum += neighborWeight;
                    nonzeroCount += 1.0f;
                }
            }
        }

        float averageNonzeroWeight = nonzeroCount > 0.0f ? (nonzeroWeightSum / nonzeroCount) : 0.0f;
        if (gi_reservoir_is_skylight(reservoir)) {
            averageNonzeroWeight *= 2.0f;
        }
        float filterStrength = clamp(gi_runtime_boiling_filter_strength(), 1e-6f, 1.0f);
        float boilingFilterMultiplier = 10.0f / filterStrength - 9.0f;
        float reservoirWeight = gi_boiling_filter_weight(reservoir);
        if (averageNonzeroWeight > 0.0f && reservoirWeight > averageNonzeroWeight * boilingFilterMultiplier) {
            reservoir = RTXDI_EmptyGIReservoir();
        }
    }

    filteredStore = gi_make_reservoir_store(reservoir);

    filtered_position_frag_out = filteredStore.positionData;
    filtered_normal_frag_out = filteredStore.normalData;
    filtered_radiance_frag_out = filteredStore.radianceData;
    filtered_meta_frag_out = filteredStore.metaData;
}
