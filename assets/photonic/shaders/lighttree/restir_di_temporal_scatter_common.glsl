#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_SCATTER_COMMON_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_SCATTER_COMMON_GLSL

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS) || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE)

void lt_temporal_scatter_emit_empty_stage_output(out RTXDI_DIReservoir reservoir)
{
    reservoir = RTXDI_EmptyDIReservoir();
}

RTXDI_DIReservoir lt_area_temporal_spatial_passthrough(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng)
{
    return currentReservoir;
}

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_REPROJECT_STAGE)
void lt_temporal_scatter_append_contributor(ivec2 targetPixel, ivec2 sourceReservoirPos, float supportWeight)
{
    if (!lt_is_viewport_uv_in_bounds(targetPixel)) {
        return;
    }

    uint cellLinearIndex = lt_temporal_scatter_cell_index_from_pixel(targetPixel);
    uint appendIndex     = lt_reproject_temporal_samples_global_counter_atomic_add(LT_TEMPORAL_SCATTER_COUNTER_INDEX_DATA_COUNT, 1u);
    uint localCellIndex  = lt_reproject_temporal_samples_cell_counter_atomic_add(cellLinearIndex, 1u);
    lt_reproject_temporal_samples_store_reservoir_index(appendIndex, uvec2(cellLinearIndex, localCellIndex));
    lt_reproject_temporal_samples_store_scattered_reservoir(appendIndex, uvec2(sourceReservoirPos));
}

#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE)
void SortReprojectedReservoirs_computeCellOffsets(ivec2 pixel)
{
    if (!lt_temporal_scatter_pixel_owns_cell(pixel)) {
        return;
    }

    uint cellIndex = lt_temporal_scatter_cell_index_from_pixel(pixel);
    uint cellCounter = lt_reproject_temporal_samples_cell_counter_value(cellIndex);
    uint offset = lt_reproject_temporal_samples_global_counter_atomic_add(LT_TEMPORAL_SCATTER_COUNTER_INDEX_PREFIX_SUM, cellCounter);
    lt_scatter_temporal_resampling_store_cell_offset(cellIndex, offset);
}

void SortReprojectedReservoirs_sortCellData(uint scatterIndex)
{
    if (scatterIndex >= lt_reproject_temporal_samples_global_counter_value(LT_TEMPORAL_SCATTER_COUNTER_INDEX_DATA_COUNT)) {
        return;
    }

    uvec2 reservoirIndex = lt_reproject_temporal_samples_load_reservoir_index(scatterIndex);
    uint targetCell      = reservoirIndex.x;
    uint localCellIndex  = reservoirIndex.y;
    uint sortedIndex     = lt_scatter_temporal_resampling_cell_offset_value(targetCell) + localCellIndex;
    lt_scatter_temporal_resampling_store_sorted_reservoir(sortedIndex, lt_reproject_temporal_samples_load_scattered_reservoir(scatterIndex));
}

#endif

#endif

#endif
