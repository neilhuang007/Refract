#ifndef PHOTONICS_RESTIR_DI_MULTI_TEMPORAL_SORT_OFFSETS_GLSL
#define PHOTONICS_RESTIR_DI_MULTI_TEMPORAL_SORT_OFFSETS_GLSL

#include "/photonics/lighttree/restir_di_temporal_sort_common.glsl"

// Bound by name from the renderer. Keep this uniform name stable so the
// multi-partition Stage 3 path sees the configured partition count.
uniform int ph_reservoir_splatting_time_partition_count;

uint lt_multi_temporal_partition_count()
{
    return uint(max(ph_reservoir_splatting_time_partition_count, 1));
}

// Partition stride for every per-partition Stage 3 array. Each partition owns
// `width * height` slots, matching the renderer-side buffer sizing.
uint lt_multi_temporal_partition_cell_capacity()
{
    ivec2 size = lt_temporal_sort_reservoir_size();
    return uint(size.x * size.y);
}

// These SSBO names are matched by the renderer's multi-scatter Stage 3
// bindings. Keep both the block names and `data` arrays stable.

layout(std430) restrict buffer ph_multi_reproject_temporal_samples_global_counters {
    uint ph_multi_reproject_temporal_samples_global_counters_data[];
};

layout(std430) restrict buffer ph_multi_scatter_temporal_resampling_cell_offsets {
    uint ph_multi_scatter_temporal_resampling_cell_offsets_data[];
};

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE)
layout(std430) restrict buffer ph_multi_reproject_temporal_samples_cell_counters {
    uint ph_multi_reproject_temporal_samples_cell_counters_data[];
};

// Called by the Stage 3 multi-temporal binning offsets pass.
void MultiSortReprojectedReservoirs_computeCellOffsets(ivec2 pixel)
{
    if (!lt_temporal_sort_pixel_owns_cell(pixel)) {
        return;
    }
    uint cellIndex = lt_temporal_sort_cell_index_from_pixel(pixel);
    uint partitionCount = lt_multi_temporal_partition_count();
    uint cellCapacity = lt_multi_temporal_partition_cell_capacity();
    for (uint partitionIndex = 0u; partitionIndex < partitionCount; ++partitionIndex) {
        uint partitionedIdx = partitionIndex * cellCapacity + cellIndex;
        uint counterIdx = partitionIndex * LT_TEMPORAL_SCATTER_COUNTER_COUNT + LT_TEMPORAL_SCATTER_COUNTER_INDEX_PREFIX_SUM;
        uint cellCounter = ph_multi_reproject_temporal_samples_cell_counters_data[partitionedIdx];
        uint offset = atomicAdd(
            ph_multi_reproject_temporal_samples_global_counters_data[counterIdx],
            cellCounter
        );
        ph_multi_scatter_temporal_resampling_cell_offsets_data[partitionedIdx] = offset;
    }
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING)
layout(std430) restrict buffer ph_multi_reproject_temporal_samples_reservoir_indices {
    uvec2 ph_multi_reproject_temporal_samples_reservoir_indices_data[];
};

layout(std430) restrict buffer ph_multi_reproject_temporal_samples_scattered_reservoirs {
    uvec2 ph_multi_reproject_temporal_samples_scattered_reservoirs_data[];
};

layout(std430) restrict buffer ph_multi_scatter_temporal_resampling_sorted_reservoirs {
    uvec2 ph_multi_scatter_temporal_resampling_sorted_reservoirs_data[];
};

// Called by the Stage 3 multi-temporal binning pass.
void MultiSortReprojectedReservoirs_sortCellData(uint scatterIndex)
{
    uint partitionCount = lt_multi_temporal_partition_count();
    uint cellCapacity = lt_multi_temporal_partition_cell_capacity();
    for (uint partitionIndex = 0u; partitionIndex < partitionCount; ++partitionIndex) {
        uint counterIdx = partitionIndex * LT_TEMPORAL_SCATTER_COUNTER_COUNT + LT_TEMPORAL_SCATTER_COUNTER_INDEX_DATA_COUNT;
        uint partitionLocalCount = ph_multi_reproject_temporal_samples_global_counters_data[counterIdx];
        if (scatterIndex >= partitionLocalCount) {
            continue;
        }
        uint partitionBase = partitionIndex * cellCapacity;
        uint contributorIdx = partitionBase + scatterIndex;
        uvec2 reservoirIndex = ph_multi_reproject_temporal_samples_reservoir_indices_data[contributorIdx];
        uint cellLinearIndex = reservoirIndex.x;
        uint localCellIndex = reservoirIndex.y;
        uint sortedIndex = ph_multi_scatter_temporal_resampling_cell_offsets_data[partitionBase + cellLinearIndex] + localCellIndex;
        ph_multi_scatter_temporal_resampling_sorted_reservoirs_data[partitionBase + sortedIndex] =
            ph_multi_reproject_temporal_samples_scattered_reservoirs_data[contributorIdx];
    }
}
#endif

#endif
