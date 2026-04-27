#ifndef PHOTONICS_RESTIR_DI_MULTI_TEMPORAL_SORT_OFFSETS_MINIMAL_GLSL
#define PHOTONICS_RESTIR_DI_MULTI_TEMPORAL_SORT_OFFSETS_MINIMAL_GLSL

uniform int ph_reservoir_splatting_time_partition_count;

const uint LT_TEMPORAL_SCATTER_COUNTER_INDEX_DATA_COUNT = 0u;
const uint LT_TEMPORAL_SCATTER_COUNTER_INDEX_PREFIX_SUM = 1u;
const uint LT_MULTI_TEMPORAL_COUNTER_INDEX_DATA_COUNT = 0u;
const uint LT_MULTI_TEMPORAL_COUNTER_INDEX_PREFIX_SUM = 1u;

bool lt_is_viewport_uv_in_bounds(ivec2 uv) {
    return all(greaterThanEqual(uv, ivec2(0))) && all(lessThan(uv, ivec2(int(viewWidth), int(viewHeight))));
}

ivec2 lt_multi_temporal_sort_pixel_to_reservoir_pos(ivec2 pixelPosition)
{
    return ph_restir_active_checkerboard_field == 0
        ? pixelPosition
        : ivec2(pixelPosition.x >> 1, pixelPosition.y);
}

ivec2 lt_multi_temporal_sort_reservoir_to_pixel_pos(ivec2 reservoirIndex)
{
    if (ph_restir_active_checkerboard_field == 0) {
        return reservoirIndex;
    }

    ivec2 pixelPosition = ivec2(reservoirIndex.x << 1, reservoirIndex.y);
    pixelPosition.x += ((pixelPosition.y + ph_restir_active_checkerboard_field) & 1);
    return pixelPosition;
}

uint lt_multi_temporal_sort_reservoir_width()
{
    return uint(max(int(ceil(viewWidth * ((ph_restir_active_checkerboard_field == 0) ? 1.0f : 0.5f))), 1));
}

bool lt_multi_temporal_sort_pixel_owns_cell(ivec2 pixelPosition)
{
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        return false;
    }
    if (ph_restir_active_checkerboard_field == 0) {
        return true;
    }

    return all(equal(
        lt_multi_temporal_sort_reservoir_to_pixel_pos(lt_multi_temporal_sort_pixel_to_reservoir_pos(pixelPosition)),
        pixelPosition
    ));
}

uint lt_multi_temporal_sort_cell_index_from_pixel(ivec2 pixelPosition)
{
    ivec2 reservoirPos = lt_multi_temporal_sort_pixel_to_reservoir_pos(pixelPosition);
    uint reservoirWidth = lt_multi_temporal_sort_reservoir_width();
    uint reservoirHeight = uint(max(int(viewHeight), 1));
    return uint(clamp(reservoirPos.y, 0, int(reservoirHeight) - 1)) * reservoirWidth
        + uint(clamp(reservoirPos.x, 0, int(reservoirWidth) - 1));
}

layout(std430) restrict buffer ph_multi_reproject_temporal_samples_global_counters {
    uint ph_multi_reproject_temporal_samples_global_counters_data[];
};

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE)
layout(std430) restrict buffer ph_multi_reproject_temporal_samples_cell_counters {
    uint ph_multi_reproject_temporal_samples_cell_counters_data[];
};
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING)
layout(std430) restrict buffer ph_multi_reproject_temporal_samples_reservoir_indices {
    uvec2 ph_multi_reproject_temporal_samples_reservoir_indices_data[];
};

layout(std430) restrict buffer ph_multi_reproject_temporal_samples_scattered_reservoirs {
    uvec2 ph_multi_reproject_temporal_samples_scattered_reservoirs_data[];
};
#endif

layout(std430) restrict buffer ph_multi_scatter_temporal_resampling_cell_offsets {
    uint ph_multi_scatter_temporal_resampling_cell_offsets_data[];
};

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING)
layout(std430) restrict buffer ph_multi_scatter_temporal_resampling_sorted_reservoirs {
    uvec2 ph_multi_scatter_temporal_resampling_sorted_reservoirs_data[];
};
#endif

uint lt_multi_temporal_partition_count()
{
    return uint(max(ph_reservoir_splatting_time_partition_count, 1));
}

uint lt_multi_temporal_partition_cell_capacity()
{
    return lt_multi_temporal_sort_reservoir_width() * uint(max(int(viewHeight), 1));
}

uint lt_temporal_partitioned_cell_index(uint partitionIndex, uint cellIndex)
{
    return partitionIndex * lt_multi_temporal_partition_cell_capacity() + cellIndex;
}

uint lt_temporal_partitioned_contributor_index(uint partitionIndex, uint contributorIndex)
{
    return partitionIndex * lt_multi_temporal_partition_cell_capacity() + contributorIndex;
}

uint lt_multi_temporal_scatter_counter_index(uint partitionIndex, uint counterIndex)
{
    return partitionIndex * 2u + counterIndex;
}

uint lt_multi_reproject_temporal_samples_global_counter_value(uint partitionIndex, uint counterIndex)
{
    return ph_multi_reproject_temporal_samples_global_counters_data[
        lt_multi_temporal_scatter_counter_index(partitionIndex, counterIndex)
    ];
}

uint lt_multi_reproject_temporal_samples_global_counter_atomic_add(uint partitionIndex, uint counterIndex, uint value)
{
    return atomicAdd(
        ph_multi_reproject_temporal_samples_global_counters_data[
            lt_multi_temporal_scatter_counter_index(partitionIndex, counterIndex)
        ],
        value
    );
}

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE)
uint lt_multi_reproject_temporal_samples_cell_counter_value(uint partitionIndex, uint cellIndex)
{
    return ph_multi_reproject_temporal_samples_cell_counters_data[
        lt_temporal_partitioned_cell_index(partitionIndex, cellIndex)
    ];
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING)
uvec2 lt_multi_reproject_temporal_samples_load_reservoir_index(uint partitionIndex, uint contributorIndex)
{
    return ph_multi_reproject_temporal_samples_reservoir_indices_data[
        lt_temporal_partitioned_contributor_index(partitionIndex, contributorIndex)
    ];
}

uvec2 lt_multi_reproject_temporal_samples_load_scattered_reservoir(uint partitionIndex, uint contributorIndex)
{
    return ph_multi_reproject_temporal_samples_scattered_reservoirs_data[
        lt_temporal_partitioned_contributor_index(partitionIndex, contributorIndex)
    ];
}
#endif

uint lt_multi_scatter_temporal_resampling_cell_offset_value(uint partitionIndex, uint cellIndex)
{
    return ph_multi_scatter_temporal_resampling_cell_offsets_data[
        lt_temporal_partitioned_cell_index(partitionIndex, cellIndex)
    ];
}

void lt_multi_scatter_temporal_resampling_store_cell_offset(uint partitionIndex, uint cellIndex, uint value)
{
    ph_multi_scatter_temporal_resampling_cell_offsets_data[
        lt_temporal_partitioned_cell_index(partitionIndex, cellIndex)
    ] = value;
}

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING)
void lt_multi_scatter_temporal_resampling_store_sorted_reservoir(uint partitionIndex, uint contributorIndex, uvec2 sortedReservoir)
{
    ph_multi_scatter_temporal_resampling_sorted_reservoirs_data[
        lt_temporal_partitioned_contributor_index(partitionIndex, contributorIndex)
    ] = sortedReservoir;
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE)
void MultiSortReprojectedReservoirs_computeCellOffsets(ivec2 pixel)
{
    if (!lt_multi_temporal_sort_pixel_owns_cell(pixel)) {
        return;
    }

    uint cellIndex = lt_multi_temporal_sort_cell_index_from_pixel(pixel);
    for (uint partitionIndex = 0u; partitionIndex < lt_multi_temporal_partition_count(); ++partitionIndex) {
        uint cellCounter = lt_multi_reproject_temporal_samples_cell_counter_value(partitionIndex, cellIndex);
        uint offset = lt_multi_reproject_temporal_samples_global_counter_atomic_add(
            partitionIndex,
            LT_TEMPORAL_SCATTER_COUNTER_INDEX_PREFIX_SUM,
            cellCounter
        );
        lt_multi_scatter_temporal_resampling_store_cell_offset(partitionIndex, cellIndex, offset);
    }
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING)
void MultiSortReprojectedReservoirs_sortCellData(uint scatterIndex)
{
    for (uint partitionIndex = 0u; partitionIndex < lt_multi_temporal_partition_count(); ++partitionIndex) {
        uint partitionCount = lt_multi_reproject_temporal_samples_global_counter_value(
            partitionIndex,
            LT_TEMPORAL_SCATTER_COUNTER_INDEX_DATA_COUNT
        );
        if (scatterIndex >= partitionCount) {
            continue;
        }

        uvec2 reservoirIndex = lt_multi_reproject_temporal_samples_load_reservoir_index(partitionIndex, scatterIndex);
        uint cellLinearIndex = reservoirIndex.x;
        uint localCellIndex = reservoirIndex.y;
        uint sortedIndex = lt_multi_scatter_temporal_resampling_cell_offset_value(partitionIndex, cellLinearIndex) + localCellIndex;
        lt_multi_scatter_temporal_resampling_store_sorted_reservoir(
            partitionIndex,
            sortedIndex,
            lt_multi_reproject_temporal_samples_load_scattered_reservoir(partitionIndex, scatterIndex)
        );
    }
}
#endif

#endif
