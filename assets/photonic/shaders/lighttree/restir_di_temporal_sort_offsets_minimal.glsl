#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_SORT_OFFSETS_MINIMAL_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_SORT_OFFSETS_MINIMAL_GLSL

const uint LT_TEMPORAL_SCATTER_COUNTER_INDEX_DATA_COUNT = 0u;
const uint LT_TEMPORAL_SCATTER_COUNTER_INDEX_PREFIX_SUM = 1u;

uniform int ph_restir_active_checkerboard_field;

bool lt_is_viewport_uv_in_bounds(ivec2 uv) {
    return all(greaterThanEqual(uv, ivec2(0))) && all(lessThan(uv, ivec2(int(viewWidth), int(viewHeight))));
}

ivec2 lt_temporal_sort_pixel_to_reservoir_pos(ivec2 pixelPosition)
{
    return ph_restir_active_checkerboard_field == 0
        ? pixelPosition
        : ivec2(pixelPosition.x >> 1, pixelPosition.y);
}

ivec2 lt_temporal_sort_reservoir_to_pixel_pos(ivec2 reservoirIndex)
{
    if (ph_restir_active_checkerboard_field == 0) {
        return reservoirIndex;
    }

    ivec2 pixelPosition = ivec2(reservoirIndex.x << 1, reservoirIndex.y);
    pixelPosition.x += ((pixelPosition.y + ph_restir_active_checkerboard_field) & 1);
    return pixelPosition;
}

uint lt_temporal_sort_reservoir_width()
{
    return uint(max(int(ceil(viewWidth * ((ph_restir_active_checkerboard_field == 0) ? 1.0f : 0.5f))), 1));
}

bool lt_temporal_sort_pixel_owns_cell(ivec2 pixelPosition)
{
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        return false;
    }
    if (ph_restir_active_checkerboard_field == 0) {
        return true;
    }

    return all(equal(
        lt_temporal_sort_reservoir_to_pixel_pos(lt_temporal_sort_pixel_to_reservoir_pos(pixelPosition)),
        pixelPosition
    ));
}

uint lt_temporal_sort_cell_index_from_pixel(ivec2 pixelPosition)
{
    ivec2 reservoirPos = lt_temporal_sort_pixel_to_reservoir_pos(pixelPosition);
    uint reservoirWidth = lt_temporal_sort_reservoir_width();
    uint reservoirHeight = uint(max(int(viewHeight), 1));
    return uint(clamp(reservoirPos.y, 0, int(reservoirHeight) - 1)) * reservoirWidth
        + uint(clamp(reservoirPos.x, 0, int(reservoirWidth) - 1));
}

layout(std430) restrict buffer ph_reproject_temporal_samples_global_counters {
    uint ph_reproject_temporal_samples_global_counters_data[];
};

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE)
layout(std430) restrict buffer ph_reproject_temporal_samples_cell_counters {
    uint ph_reproject_temporal_samples_cell_counters_data[];
};
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING)
layout(std430) restrict buffer ph_reproject_temporal_samples_reservoir_indices {
    uvec2 ph_reproject_temporal_samples_reservoir_indices_data[];
};

layout(std430) restrict buffer ph_reproject_temporal_samples_scattered_reservoirs {
    uvec2 ph_reproject_temporal_samples_scattered_reservoirs_data[];
};
#endif

layout(std430) restrict buffer ph_scatter_temporal_resampling_cell_offsets {
    uint ph_scatter_temporal_resampling_cell_offsets_data[];
};

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING)
layout(std430) restrict buffer ph_scatter_temporal_resampling_sorted_reservoirs {
    uvec2 ph_scatter_temporal_resampling_sorted_reservoirs_data[];
};
#endif

uint lt_reproject_temporal_samples_global_counter_value(uint counterIndex)
{
    return ph_reproject_temporal_samples_global_counters_data[counterIndex];
}

uint lt_reproject_temporal_samples_global_counter_atomic_add(uint counterIndex, uint value)
{
    return atomicAdd(ph_reproject_temporal_samples_global_counters_data[counterIndex], value);
}

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE)
uint lt_reproject_temporal_samples_cell_counter_value(uint cellIndex)
{
    return ph_reproject_temporal_samples_cell_counters_data[cellIndex];
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING)
uvec2 lt_reproject_temporal_samples_load_reservoir_index(uint contributorIndex)
{
    return ph_reproject_temporal_samples_reservoir_indices_data[contributorIndex];
}

uvec2 lt_reproject_temporal_samples_load_scattered_reservoir(uint contributorIndex)
{
    return ph_reproject_temporal_samples_scattered_reservoirs_data[contributorIndex];
}
#endif

uint lt_scatter_temporal_resampling_cell_offset_value(uint cellIndex)
{
    return ph_scatter_temporal_resampling_cell_offsets_data[cellIndex];
}

void lt_scatter_temporal_resampling_store_cell_offset(uint cellIndex, uint value)
{
    ph_scatter_temporal_resampling_cell_offsets_data[cellIndex] = value;
}

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING)
void lt_scatter_temporal_resampling_store_sorted_reservoir(uint contributorIndex, uvec2 sortedReservoir)
{
    ph_scatter_temporal_resampling_sorted_reservoirs_data[contributorIndex] = sortedReservoir;
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE)
void SortReprojectedReservoirs_computeCellOffsets(ivec2 pixel)
{
    if (!lt_temporal_sort_pixel_owns_cell(pixel)) {
        return;
    }

    uint cellIndex = lt_temporal_sort_cell_index_from_pixel(pixel);
    uint cellCounter = lt_reproject_temporal_samples_cell_counter_value(cellIndex);
    uint offset = lt_reproject_temporal_samples_global_counter_atomic_add(
        LT_TEMPORAL_SCATTER_COUNTER_INDEX_PREFIX_SUM,
        cellCounter
    );
    lt_scatter_temporal_resampling_store_cell_offset(cellIndex, offset);
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING)
void SortReprojectedReservoirs_sortCellData(uint scatterIndex)
{
    if (scatterIndex >= lt_reproject_temporal_samples_global_counter_value(LT_TEMPORAL_SCATTER_COUNTER_INDEX_DATA_COUNT)) {
        return;
    }

    uvec2 reservoirIndex = lt_reproject_temporal_samples_load_reservoir_index(scatterIndex);
    uint targetCell = reservoirIndex.x;
    uint localCellIndex = reservoirIndex.y;
    uint sortedIndex = lt_scatter_temporal_resampling_cell_offset_value(targetCell) + localCellIndex;
    lt_scatter_temporal_resampling_store_sorted_reservoir(
        sortedIndex,
        lt_reproject_temporal_samples_load_scattered_reservoir(scatterIndex)
    );
}
#endif

#endif
