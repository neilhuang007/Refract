#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_SORT_OFFSETS_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_SORT_OFFSETS_GLSL

#include "/photonics/lighttree/restir_di_temporal_sort_common.glsl"

// These SSBO names are matched by the renderer's Stage 3 temporal scatter
// bindings. Keep both the block names and `data` arrays stable.

layout(std430) restrict buffer ph_reproject_temporal_samples_global_counters {
    uint ph_reproject_temporal_samples_global_counters_data[];
};

layout(std430) restrict buffer ph_scatter_temporal_resampling_cell_offsets {
    uint ph_scatter_temporal_resampling_cell_offsets_data[];
};

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE)
layout(std430) restrict buffer ph_reproject_temporal_samples_cell_counters {
    uint ph_reproject_temporal_samples_cell_counters_data[];
};

// Called by the Stage 3 temporal binning offsets pass.
void SortReprojectedReservoirs_computeCellOffsets(ivec2 pixel)
{
    if (!lt_temporal_sort_pixel_owns_cell(pixel)) {
        return;
    }
    uint cellIndex = lt_temporal_sort_cell_index_from_pixel(pixel);
    uint cellCounter = ph_reproject_temporal_samples_cell_counters_data[cellIndex];
    uint offset = atomicAdd(
        ph_reproject_temporal_samples_global_counters_data[LT_TEMPORAL_SCATTER_COUNTER_INDEX_PREFIX_SUM],
        cellCounter
    );
    ph_scatter_temporal_resampling_cell_offsets_data[cellIndex] = offset;
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING)
layout(std430) restrict buffer ph_reproject_temporal_samples_reservoir_indices {
    uvec2 ph_reproject_temporal_samples_reservoir_indices_data[];
};

layout(std430) restrict buffer ph_reproject_temporal_samples_scattered_reservoirs {
    uvec2 ph_reproject_temporal_samples_scattered_reservoirs_data[];
};

layout(std430) restrict buffer ph_scatter_temporal_resampling_sorted_reservoirs {
    uvec2 ph_scatter_temporal_resampling_sorted_reservoirs_data[];
};

// Called by the Stage 3 temporal binning pass.
void SortReprojectedReservoirs_sortCellData(uint scatterIndex)
{
    if (scatterIndex >= ph_reproject_temporal_samples_global_counters_data[LT_TEMPORAL_SCATTER_COUNTER_INDEX_DATA_COUNT]) {
        return;
    }
    uvec2 reservoirIndex = ph_reproject_temporal_samples_reservoir_indices_data[scatterIndex];
    uint cellLinearIndex = reservoirIndex.x;
    uint localCellIndex = reservoirIndex.y;
    uint sortedIndex = ph_scatter_temporal_resampling_cell_offsets_data[cellLinearIndex] + localCellIndex;
    ph_scatter_temporal_resampling_sorted_reservoirs_data[sortedIndex] =
        ph_reproject_temporal_samples_scattered_reservoirs_data[scatterIndex];
}
#endif

#endif
