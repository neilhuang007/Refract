#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_BUFFER_BRIDGE_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_BUFFER_BRIDGE_GLSL

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_REPROJECT_STAGE) || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE) || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_STAGE) || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_BACKUP_STAGE)
#define PH_LIGHTTREE_ENABLE_CURRENT_TEMPORAL_COUNTER_BUFFERS 1
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_REPROJECT_STAGE) || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE)
#define PH_LIGHTTREE_ENABLE_CURRENT_TEMPORAL_CONTRIBUTOR_BUFFERS 1
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE) || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_STAGE) || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_BACKUP_STAGE)
#define PH_LIGHTTREE_ENABLE_CURRENT_TEMPORAL_SORT_BUFFERS 1
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_REPROJECT_STAGE) || defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_STAGE) || defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SCATTER_STAGE)
#define PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_COUNTER_BUFFERS 1
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_REPROJECT_STAGE) || defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_STAGE)
#define PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_CONTRIBUTOR_BUFFERS 1
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_STAGE) || defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SCATTER_STAGE)
#define PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_BUFFERS 1
#endif

#ifndef PH_LIGHTTREE_FLOATING_COORDS_BUFFER_DECLARED
#define PH_LIGHTTREE_FLOATING_COORDS_BUFFER_DECLARED
layout(std430) restrict buffer floatingCoords {
    vec2 floatingCoordsData[];
};

int lt_restir_temporal_gather_mode();

struct GatherData
{
    int gatherOption;
};

uint lt_floating_coords_pixel_index(ivec2 pixel)
{
    return uint(pixel.y * viewWidth + pixel.x);
}

void lt_store_floating_coords(ivec2 pixel, vec2 floatingCoord)
{
    floatingCoordsData[lt_floating_coords_pixel_index(pixel)] = floatingCoord;
}

vec2 lt_load_floating_coords(ivec2 pixel)
{
    return floatingCoordsData[lt_floating_coords_pixel_index(pixel)];
}

int GatherData_getGatherOption()
{
    return lt_restir_temporal_gather_mode();
}

vec2 GatherData_getMotionVectors(ivec2 pixel)
{
    return texelFetch(radiosity_motion, pixel, 0).xy;
}

vec2 GatherData_getMotionVector(ivec2 pixel)
{
    vec4 motionSample = texelFetch(radiosity_motion, pixel, 0);
    if (motionSample.w <= 0.0f)
    {
        return vec2(0.0f);
    }

    vec2 motionVector = motionSample.xy;
    if (length(motionVector) < 1e-06f)
    {
        return vec2(0.0f);
    }

    return motionVector / vec2(max(viewWidth, 1.0f), max(viewHeight, 1.0f));
}

vec2 GatherData_getFloatingCoords(ivec2 pixel)
{
    return lt_load_floating_coords(pixel);
}

void GatherData_storeFloatingCoords(ivec2 pixel, vec2 floatingCoord)
{
    lt_store_floating_coords(pixel, floatingCoord);
}

struct GatherHelper
{
    ivec2 pixel;
    vec2 prevPixel;
};

GatherHelper GatherHelper_init(ivec2 pixel, ivec2 frameDim)
{
    GatherHelper gatherHelper;
    gatherHelper.pixel = pixel;
    gatherHelper.prevPixel = vec2(pixel) + GatherData_getMotionVector(pixel) * vec2(frameDim);
    return gatherHelper;
}

GatherHelper GatherHelper_init(ivec2 pixel)
{
    return GatherHelper_init(pixel, ivec2(viewWidth, viewHeight));
}

vec2 GatherHelper_getFloatingCoords(GatherHelper gatherHelper)
{
    return GatherData_getFloatingCoords(gatherHelper.pixel);
}
#endif

#if (defined(PH_LIGHTTREE_ENABLE_TEMPORAL_COLLECT_STAGE) || defined(PH_LIGHTTREE_ENABLE_ROBUST_REUSE_STAGE)) && !defined(PH_LIGHTTREE_TEMPORAL_GATHER_SHIFTED_PATH_BUFFER_DECLARED)
#define PH_LIGHTTREE_TEMPORAL_GATHER_SHIFTED_PATH_BUFFER_DECLARED
// RobustReuseOptimization writes exactly 8 shifted paths per previous-frame
// reservoir, ordered by the 3x3 neighborhood without the center sample.
struct ShiftedPathStorageRecord {
    vec4 primaryHitData;
    vec4 primaryHitFaceFractionalPixelLensX;
    vec4 lensYFirstRayDir;
    vec4 jacobianData;
    vec4 radianceData;
};

layout(std430) restrict buffer shiftedPaths {
    ShiftedPathStorageRecord shiftedPathRecords[];
};

const uint LT_TEMPORAL_GATHER_SHIFT_COUNT = 8u;

uint lt_temporal_gather_shifted_path_pixel_index(ivec2 pixel)
{
    return uint(pixel.y * viewWidth + pixel.x);
}

uint lt_temporal_gather_shifted_path_record_index(ivec2 pixel, int offsetIndex)
{
    return lt_temporal_gather_shifted_path_pixel_index(pixel) * LT_TEMPORAL_GATHER_SHIFT_COUNT + uint(offsetIndex);
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_CURRENT_TEMPORAL_COUNTER_BUFFERS) || defined(PH_LIGHTTREE_ENABLE_CURRENT_TEMPORAL_CONTRIBUTOR_BUFFERS) || defined(PH_LIGHTTREE_ENABLE_CURRENT_TEMPORAL_SORT_BUFFERS) || defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_COUNTER_BUFFERS) || defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_CONTRIBUTOR_BUFFERS) || defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_BUFFERS) || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE)
float lt_ScatterTemporalResampling_load_previous_reservoir_confidence(
    ivec2 neighborPixel)
{
    return ScatterTemporalResampling_load_previous_reservoir_confidence(neighborPixel);
}

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)
void lt_temporal_scatter_append_contributor(ivec2 targetPixel, ivec2 sourceReservoirPos, float supportWeight);
void lt_multi_temporal_scatter_append_contributor(uint partitionIndex, ivec2 targetPixel, ivec2 sourceReservoirPos);
#endif

const uint LT_TEMPORAL_SCATTER_COUNTER_INDEX_DATA_COUNT = 0u;
const uint LT_TEMPORAL_SCATTER_COUNTER_INDEX_PREFIX_SUM = 1u;

#if defined(PH_LIGHTTREE_ENABLE_CURRENT_TEMPORAL_COUNTER_BUFFERS)
layout(std430) restrict buffer ph_reproject_temporal_samples_global_counters {
    uint ph_reproject_temporal_samples_global_counters_data[];
};

layout(std430) restrict buffer ph_reproject_temporal_samples_cell_counters {
    uint ph_reproject_temporal_samples_cell_counters_data[];
};
#endif

#if defined(PH_LIGHTTREE_ENABLE_CURRENT_TEMPORAL_CONTRIBUTOR_BUFFERS)
layout(std430) restrict buffer ph_reproject_temporal_samples_reservoir_indices {
    uvec2 ph_reproject_temporal_samples_reservoir_indices_data[];
};

layout(std430) restrict buffer ph_reproject_temporal_samples_scattered_reservoirs {
    uvec2 ph_reproject_temporal_samples_scattered_reservoirs_data[];
};
#endif

#if defined(PH_LIGHTTREE_ENABLE_CURRENT_TEMPORAL_SORT_BUFFERS)
layout(std430) restrict buffer ph_scatter_temporal_resampling_cell_offsets {
    uint ph_scatter_temporal_resampling_cell_offsets_data[];
};

layout(std430) restrict buffer ph_scatter_temporal_resampling_sorted_reservoirs {
    uvec2 ph_scatter_temporal_resampling_sorted_reservoirs_data[];
};
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_COUNTER_BUFFERS) || defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_CONTRIBUTOR_BUFFERS) || defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_BUFFERS)
uniform int ph_reservoir_splatting_time_partition_count;

const uint LT_MULTI_TEMPORAL_COUNTER_INDEX_DATA_COUNT = 0u;
const uint LT_MULTI_TEMPORAL_COUNTER_INDEX_PREFIX_SUM = 1u;

layout(std430) restrict buffer ph_multi_reproject_temporal_samples_global_counters {
    uint ph_multi_reproject_temporal_samples_global_counters_data[];
};

layout(std430) restrict buffer ph_multi_reproject_temporal_samples_cell_counters {
    uint ph_multi_reproject_temporal_samples_cell_counters_data[];
};
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_CONTRIBUTOR_BUFFERS)
layout(std430) restrict buffer ph_multi_reproject_temporal_samples_reservoir_indices {
    uvec2 ph_multi_reproject_temporal_samples_reservoir_indices_data[];
};

layout(std430) restrict buffer ph_multi_reproject_temporal_samples_scattered_reservoirs {
    uvec2 ph_multi_reproject_temporal_samples_scattered_reservoirs_data[];
};
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_BUFFERS)
layout(std430) restrict buffer ph_multi_scatter_temporal_resampling_cell_offsets {
    uint ph_multi_scatter_temporal_resampling_cell_offsets_data[];
};

layout(std430) restrict buffer ph_multi_scatter_temporal_resampling_sorted_reservoirs {
    uvec2 ph_multi_scatter_temporal_resampling_sorted_reservoirs_data[];
};
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_COUNTER_BUFFERS) || defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_CONTRIBUTOR_BUFFERS) || defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_BUFFERS)
uint lt_multi_temporal_partition_count()
{
    return uint(max(ph_reservoir_splatting_time_partition_count, 1));
}

uint lt_multi_temporal_partition_cell_capacity()
{
    uint reservoirWidth = uint(max(int(ceil(viewWidth * ((ph_restir_active_checkerboard_field == 0) ? 1.0f : 0.5f))), 1));
    uint reservoirHeight = uint(max(int(viewHeight), 1));
    return reservoirWidth * reservoirHeight;
}

uint lt_multi_temporal_partition_contributor_capacity()
{
    return lt_multi_temporal_partition_cell_capacity();
}

uint lt_multi_temporal_partition_linear_index(uint partitionIndex, uint cellIndex)
{
    return partitionIndex * lt_multi_temporal_partition_cell_capacity() + cellIndex;
}

uint lt_multi_temporal_scatter_counter_index(uint partitionIndex, uint counterIndex)
{
    return partitionIndex * 2u + counterIndex;
}

uint lt_temporal_partitioned_cell_index(uint partitionIndex, uint cellIndex)
{
    return lt_multi_temporal_partition_linear_index(partitionIndex, cellIndex);
}

uint lt_temporal_partitioned_contributor_index(uint partitionIndex, uint contributorIndex)
{
    return partitionIndex * lt_multi_temporal_partition_contributor_capacity() + contributorIndex;
}

uint lt_temporal_partitioned_counter_index(uint partitionIndex, uint counterIndex)
{
    return lt_multi_temporal_scatter_counter_index(partitionIndex, counterIndex);
}

float lt_multi_temporal_partition_duration()
{
    return ph_reservoir_splatting_shutter_speed / float(lt_multi_temporal_partition_count());
}

float lt_multi_temporal_partition_fraction(float time)
{
    return time / ph_reservoir_splatting_shutter_speed;
}

float lt_multi_temporal_partition_time(float fractionalTime, uint partitionIndex)
{
    return (fractionalTime + float(partitionIndex)) * lt_multi_temporal_partition_duration();
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_CURRENT_TEMPORAL_COUNTER_BUFFERS)
uint lt_reproject_temporal_samples_global_counter_value(uint counterIndex)
{
    return ph_reproject_temporal_samples_global_counters_data[counterIndex];
}

uint lt_reproject_temporal_samples_global_counter_atomic_add(uint counterIndex, uint value)
{
    return atomicAdd(ph_reproject_temporal_samples_global_counters_data[counterIndex], value);
}

uint lt_reproject_temporal_samples_cell_counter_value(uint cellIndex)
{
    return ph_reproject_temporal_samples_cell_counters_data[cellIndex];
}

uint lt_reproject_temporal_samples_cell_counter_atomic_add(uint cellIndex, uint value)
{
    return atomicAdd(ph_reproject_temporal_samples_cell_counters_data[cellIndex], value);
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_CURRENT_TEMPORAL_CONTRIBUTOR_BUFFERS)
void lt_reproject_temporal_samples_store_reservoir_index(uint contributorIndex, uvec2 reservoirIndex)
{
    ph_reproject_temporal_samples_reservoir_indices_data[contributorIndex] = reservoirIndex;
}

uvec2 lt_reproject_temporal_samples_load_reservoir_index(uint contributorIndex)
{
    return ph_reproject_temporal_samples_reservoir_indices_data[contributorIndex];
}

void lt_reproject_temporal_samples_store_scattered_reservoir(uint contributorIndex, uvec2 scatteredReservoir)
{
    ph_reproject_temporal_samples_scattered_reservoirs_data[contributorIndex] = scatteredReservoir;
}

uvec2 lt_reproject_temporal_samples_load_scattered_reservoir(uint contributorIndex)
{
    return ph_reproject_temporal_samples_scattered_reservoirs_data[contributorIndex];
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_CURRENT_TEMPORAL_SORT_BUFFERS)
uint lt_scatter_temporal_resampling_cell_offset_value(uint cellIndex)
{
    return ph_scatter_temporal_resampling_cell_offsets_data[cellIndex];
}

void lt_scatter_temporal_resampling_store_cell_offset(uint cellIndex, uint value)
{
    ph_scatter_temporal_resampling_cell_offsets_data[cellIndex] = value;
}

void lt_scatter_temporal_resampling_store_sorted_reservoir(uint contributorIndex, uvec2 sortedReservoir)
{
    ph_scatter_temporal_resampling_sorted_reservoirs_data[contributorIndex] = sortedReservoir;
}

uvec2 lt_scatter_temporal_resampling_load_sorted_reservoir(uint contributorIndex)
{
    return ph_scatter_temporal_resampling_sorted_reservoirs_data[contributorIndex];
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_COUNTER_BUFFERS)
uint lt_multi_reproject_temporal_samples_global_counter_value(uint partitionIndex, uint counterIndex)
{
    return ph_multi_reproject_temporal_samples_global_counters_data[
        lt_temporal_partitioned_counter_index(partitionIndex, counterIndex)
    ];
}

uint lt_multi_reproject_temporal_samples_global_counter_atomic_add(uint partitionIndex, uint counterIndex, uint value)
{
    return atomicAdd(
        ph_multi_reproject_temporal_samples_global_counters_data[
            lt_temporal_partitioned_counter_index(partitionIndex, counterIndex)
        ],
        value
    );
}

uint lt_multi_reproject_temporal_samples_cell_counter_value(uint partitionIndex, uint cellIndex)
{
    return ph_multi_reproject_temporal_samples_cell_counters_data[
        lt_temporal_partitioned_cell_index(partitionIndex, cellIndex)
    ];
}

uint lt_multi_reproject_temporal_samples_cell_counter_atomic_add(uint partitionIndex, uint cellIndex, uint value)
{
    return atomicAdd(
        ph_multi_reproject_temporal_samples_cell_counters_data[
            lt_temporal_partitioned_cell_index(partitionIndex, cellIndex)
        ],
        value
    );
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_CONTRIBUTOR_BUFFERS)
void lt_multi_reproject_temporal_samples_store_reservoir_index(uint partitionIndex, uint contributorIndex, uvec2 reservoirIndex)
{
    ph_multi_reproject_temporal_samples_reservoir_indices_data[
        lt_temporal_partitioned_contributor_index(partitionIndex, contributorIndex)
    ] = reservoirIndex;
}

uvec2 lt_multi_reproject_temporal_samples_load_reservoir_index(uint partitionIndex, uint contributorIndex)
{
    return ph_multi_reproject_temporal_samples_reservoir_indices_data[
        lt_temporal_partitioned_contributor_index(partitionIndex, contributorIndex)
    ];
}

void lt_multi_reproject_temporal_samples_store_scattered_reservoir(uint partitionIndex, uint contributorIndex, uvec2 scatteredReservoir)
{
    ph_multi_reproject_temporal_samples_scattered_reservoirs_data[
        lt_temporal_partitioned_contributor_index(partitionIndex, contributorIndex)
    ] = scatteredReservoir;
}

uvec2 lt_multi_reproject_temporal_samples_load_scattered_reservoir(uint partitionIndex, uint contributorIndex)
{
    return ph_multi_reproject_temporal_samples_scattered_reservoirs_data[
        lt_temporal_partitioned_contributor_index(partitionIndex, contributorIndex)
    ];
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_BUFFERS)
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

void lt_multi_scatter_temporal_resampling_store_sorted_reservoir(uint partitionIndex, uint contributorIndex, uvec2 sortedReservoir)
{
    ph_multi_scatter_temporal_resampling_sorted_reservoirs_data[
        lt_temporal_partitioned_contributor_index(partitionIndex, contributorIndex)
    ] = sortedReservoir;
}

uvec2 lt_multi_scatter_temporal_resampling_load_sorted_reservoir(uint partitionIndex, uint contributorIndex)
{
    return ph_multi_scatter_temporal_resampling_sorted_reservoirs_data[
        lt_temporal_partitioned_contributor_index(partitionIndex, contributorIndex)
    ];
}
#endif

#endif

#undef PH_LIGHTTREE_ENABLE_CURRENT_TEMPORAL_COUNTER_BUFFERS
#undef PH_LIGHTTREE_ENABLE_CURRENT_TEMPORAL_CONTRIBUTOR_BUFFERS
#undef PH_LIGHTTREE_ENABLE_CURRENT_TEMPORAL_SORT_BUFFERS
#undef PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_COUNTER_BUFFERS
#undef PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_CONTRIBUTOR_BUFFERS
#undef PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_BUFFERS

#endif
