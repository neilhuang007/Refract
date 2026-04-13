#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;

uniform float viewWidth;
uniform float viewHeight;
uniform int ph_restir_active_checkerboard_field;

layout(std430) restrict buffer ph_temporal_scatter_global_counters {
    uint ph_temporal_scatter_global_counters_data[];
};

layout(std430) restrict buffer ph_temporal_scatter_cell_counters {
    uint ph_temporal_scatter_cell_counters_data[];
};

layout(std430) restrict buffer ph_temporal_scatter_reservoir_indices {
    uvec2 ph_temporal_scatter_reservoir_indices_data[];
};

layout(std430) restrict buffer ph_temporal_scatter_scattered_reservoirs {
    uvec2 ph_temporal_scatter_scattered_reservoirs_data[];
};

layout(std430) restrict buffer ph_temporal_scatter_scattered_weights {
    uint ph_temporal_scatter_scattered_weights_data[];
};

layout(std430) restrict buffer ph_temporal_scatter_cell_offsets {
    uint ph_temporal_scatter_cell_offsets_data[];
};

layout(std430) restrict buffer ph_temporal_scatter_sorted_reservoirs {
    uvec2 ph_temporal_scatter_sorted_reservoirs_data[];
};

layout(std430) restrict buffer ph_temporal_scatter_sorted_weights {
    uint ph_temporal_scatter_sorted_weights_data[];
};

ivec2 lt_current_reservoir_pos() {
    return ivec2(gl_FragCoord.xy);
}

bool lt_is_viewport_uv_in_bounds(ivec2 uv) {
    return all(greaterThanEqual(uv, ivec2(0)))
        && all(lessThan(uv, ivec2(int(viewWidth), int(viewHeight))));
}

ivec2 lt_reservoir_grid_size() {
    float checkerboardScale = (ph_restir_active_checkerboard_field == 0) ? 1.0f : 0.5f;
    return ivec2(
        max(int(ceil(viewWidth * checkerboardScale)), 1),
        max(int(viewHeight), 1)
    );
}

bool lt_is_active_reservoir_lane(ivec2 reservoirPos) {
    if (ph_restir_active_checkerboard_field == 0) {
        return true;
    }

    ivec2 pixelPosition = ivec2(reservoirPos.x << 1, reservoirPos.y);
    pixelPosition.x += ((pixelPosition.y + ph_restir_active_checkerboard_field) & 1);
    return lt_is_viewport_uv_in_bounds(pixelPosition);
}

uint lt_temporal_scatter_linear_index(ivec2 reservoirPos) {
    ivec2 size = lt_reservoir_grid_size();
    return uint(clamp(reservoirPos.y, 0, size.y - 1) * size.x + clamp(reservoirPos.x, 0, size.x - 1));
}

void lt_temporal_scatter_build_offsets() {
    if (ph_temporal_scatter_global_counters_data[1] != 0u) {
        return;
    }

    ivec2 size = lt_reservoir_grid_size();
    uint runningOffset = 0u;
    for (int y = 0; y < size.y; ++y) {
        for (int x = 0; x < size.x; ++x) {
            uint linearIndex = uint(y * size.x + x);
            ph_temporal_scatter_cell_offsets_data[linearIndex] = runningOffset;
            runningOffset += ph_temporal_scatter_cell_counters_data[linearIndex];
        }
    }
    memoryBarrierBuffer();
    ph_temporal_scatter_global_counters_data[1] = runningOffset;
}

void lt_temporal_scatter_sort_contributors() {
    uint scatterCount = ph_temporal_scatter_global_counters_data[0];
    for (uint scatterIndex = 0u; scatterIndex < scatterCount; ++scatterIndex) {
        uvec2 reservoirIndex = ph_temporal_scatter_reservoir_indices_data[scatterIndex];
        uint targetCell = reservoirIndex.x;
        uint localCellIndex = reservoirIndex.y;
        uint sortedIndex = ph_temporal_scatter_cell_offsets_data[targetCell] + localCellIndex;
        ph_temporal_scatter_sorted_reservoirs_data[sortedIndex] = ph_temporal_scatter_scattered_reservoirs_data[scatterIndex];
        ph_temporal_scatter_sorted_weights_data[sortedIndex] = ph_temporal_scatter_scattered_weights_data[scatterIndex];
    }
    memoryBarrierBuffer();
}

void main() {
    reservoir_frag_out = vec4(0.0);
    reservoir_sample_frag_out = vec4(0.0);
    reservoir_meta_frag_out = vec4(0.0);

    ivec2 reservoirPos = lt_current_reservoir_pos();
    if (!lt_is_active_reservoir_lane(reservoirPos)) {
        return;
    }

    if (lt_temporal_scatter_linear_index(reservoirPos) != 0u) {
        return;
    }

    lt_temporal_scatter_build_offsets();
    lt_temporal_scatter_sort_contributors();
}
