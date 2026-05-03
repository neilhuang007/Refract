#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_SORT_COMMON_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_SORT_COMMON_GLSL

// Slot indices into the per-partition global counters buffer. The reproject
// pass bumps DATA_COUNT as it appends contributors; the offsets pass bumps
// PREFIX_SUM while building cell offsets; the sorting pass reads DATA_COUNT
// to bound iteration. Keep these values locked to the reference buffer layout.
#ifndef PH_LIGHTTREE_TEMPORAL_SCATTER_COUNTER_CONSTANTS_DECLARED
#define PH_LIGHTTREE_TEMPORAL_SCATTER_COUNTER_CONSTANTS_DECLARED
const uint LT_TEMPORAL_SCATTER_COUNTER_INDEX_DATA_COUNT = 0u;
const uint LT_TEMPORAL_SCATTER_COUNTER_INDEX_PREFIX_SUM = 1u;
#endif

// Number of slots per partition in global counters. Must equal the number of
// LT_TEMPORAL_SCATTER_COUNTER_INDEX_* constants above; it is the stride the
// multi-partition indexer multiplies by.
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
