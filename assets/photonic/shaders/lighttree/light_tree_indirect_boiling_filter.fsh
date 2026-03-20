#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 filtered_position_frag_out;
layout(location = 1) out vec4 filtered_normal_frag_out;
layout(location = 2) out vec4 filtered_radiance_frag_out;
layout(location = 3) out vec4 filtered_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/restir_gi_bridge.glsl"

// RTXDI default: boilingFilterStrength = 0.2
const float gi_boiling_filter_strength = 0.2f;
const int gi_boiling_filter_radius = 4; // half of 8x8 tile

void main() {
    RTXDI_GIReservoir reservoir = RTXDI_LoadGIReservoir(gi_buffer_index_temporal, tex_coord);
    RTXDI_GIReservoirStore filteredStore = gi_make_reservoir_store(reservoir);

    float weight = ph_luminance(reservoir.selected.radiance) * reservoir.weight_sum;
    float weightSum = 0.0f;
    float weightCount = 0.0f;

    for (int dy = -gi_boiling_filter_radius; dy < gi_boiling_filter_radius; dy += 2) {
        for (int dx = -gi_boiling_filter_radius; dx < gi_boiling_filter_radius; dx += 2) {
            ivec2 sampleUv = tex_coord + ivec2(dx, dy);
            if (!lt_is_viewport_uv_in_bounds(sampleUv)) continue;

            RTXDI_GIReservoir sampleReservoir = RTXDI_LoadGIReservoir(gi_buffer_index_temporal, sampleUv);
            float sampleWeight = ph_luminance(sampleReservoir.selected.radiance) * sampleReservoir.weight_sum;
            if (sampleWeight > 0.0f) {
                weightSum += sampleWeight;
                weightCount += 1.0f;
            }
        }
    }

    float averageNonzeroWeight = weightCount > 0.0f ? weightSum / weightCount : 0.0f;
    float boilingFilterStrength = gi_runtime_boiling_filter_strength();
    float boilingFilterMultiplier = 10.0f / clamp(boilingFilterStrength, 1e-6f, 1.0f) - 9.0f;

    if (weight > averageNonzeroWeight * boilingFilterMultiplier) {
        filteredStore = gi_make_invalid_reservoir_store();
    }

    filtered_position_frag_out = filteredStore.positionData;
    filtered_normal_frag_out = filteredStore.normalData;
    filtered_radiance_frag_out = filteredStore.radianceData;
    filtered_meta_frag_out = filteredStore.metaData;
}
