#ifndef PHOTONICS_GI_TEMPORAL_SPLATTING_GLSL
#define PHOTONICS_GI_TEMPORAL_SPLATTING_GLSL

const uint GI_TEMPORAL_COUNTER_DATA_COUNT = 0u;
const uint GI_TEMPORAL_COUNTER_PREFIX_SUM = 1u;

#if defined(PH_GI_TEMPORAL_GLOBAL_COUNTER_BUFFER)
layout(std430) restrict buffer ph_reproject_temporal_samples_global_counters {
    uint ph_reproject_temporal_samples_global_counters_data[];
};
#endif

#if defined(PH_GI_TEMPORAL_CELL_COUNTER_BUFFER)
layout(std430) restrict buffer ph_reproject_temporal_samples_cell_counters {
    uint ph_reproject_temporal_samples_cell_counters_data[];
};
#endif

#if defined(PH_GI_TEMPORAL_RECORD_BUFFER)
layout(std430) restrict buffer ph_gi_reproject_temporal_samples_records {
    uvec4 ph_gi_reproject_temporal_samples_records_data[];
};
#endif

#if defined(PH_GI_TEMPORAL_SORT_BUFFERS)
layout(std430) restrict buffer ph_scatter_temporal_resampling_cell_offsets {
    uint ph_scatter_temporal_resampling_cell_offsets_data[];
};

layout(std430) restrict buffer ph_scatter_temporal_resampling_sorted_reservoirs {
    uvec2 ph_scatter_temporal_resampling_sorted_reservoirs_data[];
};
#endif

uint gi_temporal_splat_width()
{
    return uint(max(int(viewWidth), 1));
}

uint gi_temporal_splat_height()
{
    return uint(max(int(viewHeight), 1));
}

uint gi_temporal_splat_capacity()
{
    return gi_temporal_splat_width() * gi_temporal_splat_height();
}

bool gi_temporal_splat_in_bounds(ivec2 pixel)
{
    return all(greaterThanEqual(pixel, ivec2(0)))
        && all(lessThan(pixel, ivec2(int(gi_temporal_splat_width()), int(gi_temporal_splat_height()))));
}

uint gi_temporal_splat_linear_index(ivec2 pixel)
{
    ivec2 clampedPixel = clamp(
        pixel,
        ivec2(0),
        ivec2(int(gi_temporal_splat_width()) - 1, int(gi_temporal_splat_height()) - 1)
    );
    return uint(clampedPixel.y) * gi_temporal_splat_width() + uint(clampedPixel.x);
}

#if defined(PH_GI_TEMPORAL_CELL_COUNTER_BUFFER)
uint gi_temporal_splat_cell_counter_value(uint cellIndex)
{
    return ph_reproject_temporal_samples_cell_counters_data[cellIndex];
}
#endif

#if defined(PH_GI_TEMPORAL_SORT_BUFFERS)
uint gi_temporal_splat_cell_offset_value(uint cellIndex)
{
    return ph_scatter_temporal_resampling_cell_offsets_data[cellIndex];
}

uvec2 gi_temporal_splat_load_sorted_source(uint sortedIndex)
{
    return ph_scatter_temporal_resampling_sorted_reservoirs_data[sortedIndex];
}
#endif

#if defined(PH_GI_TEMPORAL_GLOBAL_COUNTER_BUFFER) && defined(PH_GI_TEMPORAL_CELL_COUNTER_BUFFER) && defined(PH_GI_TEMPORAL_RECORD_BUFFER)
void gi_temporal_splat_append_source(ivec2 sourcePixel, ivec2 targetReservoirPos)
{
    if (!gi_temporal_splat_in_bounds(sourcePixel) || !gi_temporal_splat_in_bounds(targetReservoirPos)) {
        return;
    }

    uint contributorIndex = atomicAdd(
        ph_reproject_temporal_samples_global_counters_data[GI_TEMPORAL_COUNTER_DATA_COUNT],
        1u
    );
    if (contributorIndex >= gi_temporal_splat_capacity()) {
        return;
    }

    uint targetCellIndex = gi_temporal_splat_linear_index(targetReservoirPos);
    uint localCellIndex = atomicAdd(ph_reproject_temporal_samples_cell_counters_data[targetCellIndex], 1u);
    ph_gi_reproject_temporal_samples_records_data[contributorIndex] = uvec4(
        targetCellIndex,
        localCellIndex,
        uint(sourcePixel.x),
        uint(sourcePixel.y)
    );
}
#endif

#if defined(PH_GI_TEMPORAL_GLOBAL_COUNTER_BUFFER) && defined(PH_GI_TEMPORAL_CELL_COUNTER_BUFFER) && defined(PH_GI_TEMPORAL_SORT_BUFFERS)
void gi_temporal_splat_compute_cell_offset(ivec2 pixel)
{
    if (!gi_temporal_splat_in_bounds(pixel)) {
        return;
    }

    uint cellIndex = gi_temporal_splat_linear_index(pixel);
    uint cellCounter = ph_reproject_temporal_samples_cell_counters_data[cellIndex];
    uint offset = atomicAdd(
        ph_reproject_temporal_samples_global_counters_data[GI_TEMPORAL_COUNTER_PREFIX_SUM],
        cellCounter
    );
    ph_scatter_temporal_resampling_cell_offsets_data[cellIndex] = offset;
}
#endif

#if defined(PH_GI_TEMPORAL_GLOBAL_COUNTER_BUFFER) && defined(PH_GI_TEMPORAL_RECORD_BUFFER) && defined(PH_GI_TEMPORAL_SORT_BUFFERS)
void gi_temporal_splat_sort_record(uint scatterIndex)
{
    if (scatterIndex >= ph_reproject_temporal_samples_global_counters_data[GI_TEMPORAL_COUNTER_DATA_COUNT]) {
        return;
    }

    uvec4 record = ph_gi_reproject_temporal_samples_records_data[scatterIndex];
    uint sortedIndex = ph_scatter_temporal_resampling_cell_offsets_data[record.x] + record.y;
    ph_scatter_temporal_resampling_sorted_reservoirs_data[sortedIndex] = record.zw;
}
#endif

#endif
