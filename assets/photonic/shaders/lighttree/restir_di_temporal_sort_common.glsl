#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_SORT_COMMON_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_SORT_COMMON_GLSL

// SLOT INDICES INTO THE PER-PARTITION GLOBAL_COUNTERS BUFFER. THE REPROJECT
// PASS BUMPS DATA_COUNT AS IT APPENDS CONTRIBUTORS; THE OFFSETS PASS BUMPS
// PREFIX_SUM WHILE BUILDING CELL OFFSETS; THE SORTING PASS READS DATA_COUNT
// TO BOUND ITERATION. KEEP THESE VALUES LOCKED TO THE REFERENCE BUFFER LAYOUT.
const uint LT_TEMPORAL_SCATTER_COUNTER_INDEX_DATA_COUNT = 0u;
const uint LT_TEMPORAL_SCATTER_COUNTER_INDEX_PREFIX_SUM = 1u;

// NUMBER OF SLOTS PER PARTITION IN GLOBAL_COUNTERS. MUST EQUAL THE NUMBER OF
// LT_TEMPORAL_SCATTER_COUNTER_INDEX_* CONSTANTS ABOVE -- IT IS THE STRIDE THE
// MULTI-PARTITION INDEXER MULTIPLIES BY.
const uint LT_TEMPORAL_SCATTER_COUNTER_COUNT = 2u;

bool lt_is_viewport_uv_in_bounds(ivec2 uv)
{
    return all(greaterThanEqual(uv, ivec2(0)))
        && all(lessThan(uv, ivec2(int(viewWidth), int(viewHeight))));
}

ivec2 lt_temporal_sort_pixel_to_reservoir_pos(ivec2 pixelPosition)
{
    return pixelPosition;
}

ivec2 lt_temporal_sort_reservoir_to_pixel_pos(ivec2 reservoirIndex)
{
    return reservoirIndex;
}

ivec2 lt_temporal_sort_reservoir_size()
{
    return ivec2(
        max(int(viewWidth), 1),
        max(int(viewHeight), 1)
    );
}

bool lt_temporal_sort_pixel_owns_cell(ivec2 pixelPosition)
{
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        return false;
    }
    return true;
}

uint lt_temporal_sort_cell_index_from_pixel(ivec2 pixelPosition)
{
    ivec2 reservoirPos = lt_temporal_sort_pixel_to_reservoir_pos(pixelPosition);
    ivec2 reservoirSize = lt_temporal_sort_reservoir_size();
    return uint(clamp(reservoirPos.y, 0, reservoirSize.y - 1)) * uint(reservoirSize.x)
        + uint(clamp(reservoirPos.x, 0, reservoirSize.x - 1));
}

#endif
