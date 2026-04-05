#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 filtered_position_frag_out;
layout(location = 1) out vec4 filtered_normal_frag_out;
layout(location = 2) out vec4 filtered_radiance_frag_out;
layout(location = 3) out vec4 filtered_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/restir_gi_bridge.glsl"

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
    filteredStore = gi_make_reservoir_store(reservoir);

    filtered_position_frag_out = filteredStore.positionData;
    filtered_normal_frag_out = filteredStore.normalData;
    filtered_radiance_frag_out = filteredStore.radianceData;
    filtered_meta_frag_out = filteredStore.metaData;
}
