#ifndef PHOTONICS_RESTIR_DI_MULTI_TEMPORAL_RECORDS_GLSL
#define PHOTONICS_RESTIR_DI_MULTI_TEMPORAL_RECORDS_GLSL

#include "/photonics/lighttree/restir_di_temporal_buffer_bridge.glsl"

// Shared SSBO routing for the reference MultiReprojectTemporalSamples and
// MultiSortReprojectedReservoirs stages. Each partition owns a full
// viewWidth * viewHeight cell range:
//   globalCounters[partition][0] = appended contributor count
//   globalCounters[partition][1] = prefix-sum cursor
//   ph_multi_temporal_cell_data[cell].x = per-cell count
//   ph_multi_temporal_cell_data[cell].y = per-cell sorted offset

bool lt_multi_temporal_pixel_in_view(ivec2 pixel)
{
    return all(greaterThanEqual(pixel, ivec2(0)))
        && all(lessThan(pixel, ivec2(int(viewWidth), int(viewHeight))));
}

uint lt_multi_temporal_cell_index_from_pixel(ivec2 pixel)
{
    uint width = uint(max(int(viewWidth), 1));
    uint height = uint(max(int(viewHeight), 1));
    uint x = uint(clamp(pixel.x, 0, int(width) - 1));
    uint y = uint(clamp(pixel.y, 0, int(height) - 1));
    return y * width + x;
}

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_REPROJECT_STAGE)
void lt_multi_temporal_scatter_append_contributor(
    uint partitionIndex,
    ivec2 targetPixel,
    ivec2 sourceReservoirPos)
{
    if (!lt_multi_temporal_pixel_in_view(targetPixel)) {
        return;
    }

    uint cellLinearIndex = lt_multi_temporal_cell_index_from_pixel(targetPixel);
    uint appendIndex = lt_multi_reproject_temporal_samples_global_counter_atomic_add(
        partitionIndex,
        LT_MULTI_TEMPORAL_COUNTER_INDEX_DATA_COUNT,
        1u
    );
    uint localCellIndex = lt_multi_reproject_temporal_samples_cell_counter_atomic_add(
        partitionIndex,
        cellLinearIndex,
        1u
    );
    lt_multi_reproject_temporal_samples_store_reservoir_index(
        partitionIndex,
        appendIndex,
        uvec2(cellLinearIndex, localCellIndex)
    );
    lt_multi_reproject_temporal_samples_store_scattered_reservoir(
        partitionIndex,
        appendIndex,
        uvec2(sourceReservoirPos)
    );
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_STAGE)
void MultiSortReprojectedReservoirs_computeCellOffsets(ivec2 pixel)
{
    if (!lt_multi_temporal_pixel_in_view(pixel)) {
        return;
    }

    uint cellIndex = lt_multi_temporal_cell_index_from_pixel(pixel);
    for (uint partitionIndex = 0u; partitionIndex < lt_multi_temporal_partition_count(); ++partitionIndex) {
        uint cellCounter = lt_multi_reproject_temporal_samples_cell_counter_value(partitionIndex, cellIndex);
        uint offset = lt_multi_reproject_temporal_samples_global_counter_atomic_add(
            partitionIndex,
            LT_MULTI_TEMPORAL_COUNTER_INDEX_PREFIX_SUM,
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
        uint partitionLocalCount = lt_multi_reproject_temporal_samples_global_counter_value(
            partitionIndex,
            LT_MULTI_TEMPORAL_COUNTER_INDEX_DATA_COUNT
        );
        if (scatterIndex >= partitionLocalCount) {
            continue;
        }

        uvec2 reservoirIndex = lt_multi_reproject_temporal_samples_load_reservoir_index(
            partitionIndex,
            scatterIndex
        );
        uint cellLinearIndex = reservoirIndex.x;
        uint localCellIndex = reservoirIndex.y;
        uint sortedIndex = lt_multi_scatter_temporal_resampling_cell_offset_value(
            partitionIndex,
            cellLinearIndex
        ) + localCellIndex;
        lt_multi_scatter_temporal_resampling_store_sorted_reservoir(
            partitionIndex,
            sortedIndex,
            lt_multi_reproject_temporal_samples_load_scattered_reservoir(partitionIndex, scatterIndex)
        );
    }
}
#endif

#endif
