#ifndef PH_LIGHTTREE_REUSE_INCLUDE
#define PH_LIGHTTREE_REUSE_INCLUDE

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)
// Reference-stage per-partition scatter tables.
// Partition 0 is the single-splat temporal path; partitions [0, kNumTimePartitions)
// are also addressed explicitly by the multi-splat motion-blur stages.
layout(std430) restrict buffer ph_temporal_scatter_global_counters_partition0 {
    uint ph_temporal_scatter_global_counters_partition0_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_global_counters_partition1 {
    uint ph_temporal_scatter_global_counters_partition1_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_global_counters_partition2 {
    uint ph_temporal_scatter_global_counters_partition2_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_global_counters_partition3 {
    uint ph_temporal_scatter_global_counters_partition3_data[];
};

layout(std430) restrict buffer ph_temporal_scatter_cell_counters_partition0 {
    uint ph_temporal_scatter_cell_counters_partition0_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_cell_counters_partition1 {
    uint ph_temporal_scatter_cell_counters_partition1_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_cell_counters_partition2 {
    uint ph_temporal_scatter_cell_counters_partition2_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_cell_counters_partition3 {
    uint ph_temporal_scatter_cell_counters_partition3_data[];
};

#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY)
layout(std430) restrict buffer ph_temporal_scatter_reservoir_indices_partition0 {
    uvec2 ph_temporal_scatter_reservoir_indices_partition0_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_reservoir_indices_partition1 {
    uvec2 ph_temporal_scatter_reservoir_indices_partition1_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_reservoir_indices_partition2 {
    uvec2 ph_temporal_scatter_reservoir_indices_partition2_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_reservoir_indices_partition3 {
    uvec2 ph_temporal_scatter_reservoir_indices_partition3_data[];
};

layout(std430) restrict buffer ph_temporal_scatter_scattered_reservoirs_partition0 {
    uvec2 ph_temporal_scatter_scattered_reservoirs_partition0_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_scattered_reservoirs_partition1 {
    uvec2 ph_temporal_scatter_scattered_reservoirs_partition1_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_scattered_reservoirs_partition2 {
    uvec2 ph_temporal_scatter_scattered_reservoirs_partition2_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_scattered_reservoirs_partition3 {
    uvec2 ph_temporal_scatter_scattered_reservoirs_partition3_data[];
};

layout(std430) restrict buffer ph_temporal_scatter_scattered_weights_partition0 {
    uint ph_temporal_scatter_scattered_weights_partition0_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_scattered_weights_partition1 {
    uint ph_temporal_scatter_scattered_weights_partition1_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_scattered_weights_partition2 {
    uint ph_temporal_scatter_scattered_weights_partition2_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_scattered_weights_partition3 {
    uint ph_temporal_scatter_scattered_weights_partition3_data[];
};
#endif

#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY) || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING) || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY)
layout(std430) restrict buffer ph_temporal_scatter_cell_offsets_partition0 {
    uint ph_temporal_scatter_cell_offsets_partition0_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_cell_offsets_partition1 {
    uint ph_temporal_scatter_cell_offsets_partition1_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_cell_offsets_partition2 {
    uint ph_temporal_scatter_cell_offsets_partition2_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_cell_offsets_partition3 {
    uint ph_temporal_scatter_cell_offsets_partition3_data[];
};

layout(std430) restrict buffer ph_temporal_scatter_sorted_reservoirs_partition0 {
    uvec2 ph_temporal_scatter_sorted_reservoirs_partition0_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_sorted_reservoirs_partition1 {
    uvec2 ph_temporal_scatter_sorted_reservoirs_partition1_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_sorted_reservoirs_partition2 {
    uvec2 ph_temporal_scatter_sorted_reservoirs_partition2_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_sorted_reservoirs_partition3 {
    uvec2 ph_temporal_scatter_sorted_reservoirs_partition3_data[];
};

layout(std430) restrict buffer ph_temporal_scatter_sorted_weights_partition0 {
    uint ph_temporal_scatter_sorted_weights_partition0_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_sorted_weights_partition1 {
    uint ph_temporal_scatter_sorted_weights_partition1_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_sorted_weights_partition2 {
    uint ph_temporal_scatter_sorted_weights_partition2_data[];
};
layout(std430) restrict buffer ph_temporal_scatter_sorted_weights_partition3 {
    uint ph_temporal_scatter_sorted_weights_partition3_data[];
};
#endif
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)
uniform uint ph_reservoir_splatting_time_partition_count;

uint lt_multi_temporal_partition_count()
{
    return max(ph_reservoir_splatting_time_partition_count, 1u);
}

const uint LT_MULTI_TEMPORAL_COUNTER_INDEX_DATA_COUNT = 0u;
const uint LT_MULTI_TEMPORAL_COUNTER_INDEX_PREFIX_SUM = 1u;

uint lt_multi_temporal_partition_linear_index(uint partitionIndex, uint cellIndex)
{
    return cellIndex;
}

uint lt_multi_temporal_scatter_counter_index(uint partitionIndex, uint counterIndex)
{
    return counterIndex;
}

uint lt_temporal_partitioned_cell_index(uint partitionIndex, uint cellIndex)
{
    return lt_multi_temporal_partition_linear_index(partitionIndex, cellIndex);
}

uint lt_temporal_partitioned_contributor_index(uint partitionIndex, uint contributorIndex)
{
    return contributorIndex;
}

uint lt_temporal_partitioned_counter_index(uint partitionIndex, uint counterIndex)
{
    return lt_multi_temporal_scatter_counter_index(partitionIndex, counterIndex);
}

float lt_multi_temporal_partition_duration()
{
    return 1.0f / float(lt_multi_temporal_partition_count());
}

float lt_multi_temporal_partition_fraction(float time)
{
    return clamp(time, 0.0f, 1.0f);
}

float lt_multi_temporal_partition_time(float fractionalTime, uint partitionIndex)
{
    return (fractionalTime + float(partitionIndex)) * lt_multi_temporal_partition_duration();
}

uint lt_temporal_scatter_global_counter_value(uint partitionIndex, uint counterIndex)
{
    if (partitionIndex == 0u) return ph_temporal_scatter_global_counters_partition0_data[counterIndex];
    if (partitionIndex == 1u) return ph_temporal_scatter_global_counters_partition1_data[counterIndex];
    if (partitionIndex == 2u) return ph_temporal_scatter_global_counters_partition2_data[counterIndex];
    return ph_temporal_scatter_global_counters_partition3_data[counterIndex];
}

uint lt_temporal_scatter_global_counter_atomic_add(uint partitionIndex, uint counterIndex, uint value)
{
    if (partitionIndex == 0u) return atomicAdd(ph_temporal_scatter_global_counters_partition0_data[counterIndex], value);
    if (partitionIndex == 1u) return atomicAdd(ph_temporal_scatter_global_counters_partition1_data[counterIndex], value);
    if (partitionIndex == 2u) return atomicAdd(ph_temporal_scatter_global_counters_partition2_data[counterIndex], value);
    return atomicAdd(ph_temporal_scatter_global_counters_partition3_data[counterIndex], value);
}

uint lt_temporal_scatter_cell_counter_value(uint partitionIndex, uint cellIndex)
{
    if (partitionIndex == 0u) return ph_temporal_scatter_cell_counters_partition0_data[cellIndex];
    if (partitionIndex == 1u) return ph_temporal_scatter_cell_counters_partition1_data[cellIndex];
    if (partitionIndex == 2u) return ph_temporal_scatter_cell_counters_partition2_data[cellIndex];
    return ph_temporal_scatter_cell_counters_partition3_data[cellIndex];
}

uint lt_temporal_scatter_cell_counter_atomic_add(uint partitionIndex, uint cellIndex, uint value)
{
    if (partitionIndex == 0u) return atomicAdd(ph_temporal_scatter_cell_counters_partition0_data[cellIndex], value);
    if (partitionIndex == 1u) return atomicAdd(ph_temporal_scatter_cell_counters_partition1_data[cellIndex], value);
    if (partitionIndex == 2u) return atomicAdd(ph_temporal_scatter_cell_counters_partition2_data[cellIndex], value);
    return atomicAdd(ph_temporal_scatter_cell_counters_partition3_data[cellIndex], value);
}

void lt_temporal_scatter_store_reservoir_index(uint partitionIndex, uint contributorIndex, uvec2 reservoirIndex)
{
    if (partitionIndex == 0u) { ph_temporal_scatter_reservoir_indices_partition0_data[contributorIndex] = reservoirIndex; return; }
    if (partitionIndex == 1u) { ph_temporal_scatter_reservoir_indices_partition1_data[contributorIndex] = reservoirIndex; return; }
    if (partitionIndex == 2u) { ph_temporal_scatter_reservoir_indices_partition2_data[contributorIndex] = reservoirIndex; return; }
    ph_temporal_scatter_reservoir_indices_partition3_data[contributorIndex] = reservoirIndex;
}

uvec2 lt_temporal_scatter_load_reservoir_index(uint partitionIndex, uint contributorIndex)
{
    if (partitionIndex == 0u) return ph_temporal_scatter_reservoir_indices_partition0_data[contributorIndex];
    if (partitionIndex == 1u) return ph_temporal_scatter_reservoir_indices_partition1_data[contributorIndex];
    if (partitionIndex == 2u) return ph_temporal_scatter_reservoir_indices_partition2_data[contributorIndex];
    return ph_temporal_scatter_reservoir_indices_partition3_data[contributorIndex];
}

void lt_temporal_scatter_store_scattered_reservoir(uint partitionIndex, uint contributorIndex, uvec2 scatteredReservoir)
{
    if (partitionIndex == 0u) { ph_temporal_scatter_scattered_reservoirs_partition0_data[contributorIndex] = scatteredReservoir; return; }
    if (partitionIndex == 1u) { ph_temporal_scatter_scattered_reservoirs_partition1_data[contributorIndex] = scatteredReservoir; return; }
    if (partitionIndex == 2u) { ph_temporal_scatter_scattered_reservoirs_partition2_data[contributorIndex] = scatteredReservoir; return; }
    ph_temporal_scatter_scattered_reservoirs_partition3_data[contributorIndex] = scatteredReservoir;
}

uvec2 lt_temporal_scatter_load_scattered_reservoir(uint partitionIndex, uint contributorIndex)
{
    if (partitionIndex == 0u) return ph_temporal_scatter_scattered_reservoirs_partition0_data[contributorIndex];
    if (partitionIndex == 1u) return ph_temporal_scatter_scattered_reservoirs_partition1_data[contributorIndex];
    if (partitionIndex == 2u) return ph_temporal_scatter_scattered_reservoirs_partition2_data[contributorIndex];
    return ph_temporal_scatter_scattered_reservoirs_partition3_data[contributorIndex];
}

uint lt_temporal_scatter_cell_offset_value(uint partitionIndex, uint cellIndex)
{
    if (partitionIndex == 0u) return ph_temporal_scatter_cell_offsets_partition0_data[cellIndex];
    if (partitionIndex == 1u) return ph_temporal_scatter_cell_offsets_partition1_data[cellIndex];
    if (partitionIndex == 2u) return ph_temporal_scatter_cell_offsets_partition2_data[cellIndex];
    return ph_temporal_scatter_cell_offsets_partition3_data[cellIndex];
}

void lt_temporal_scatter_store_cell_offset(uint partitionIndex, uint cellIndex, uint value)
{
    if (partitionIndex == 0u) { ph_temporal_scatter_cell_offsets_partition0_data[cellIndex] = value; return; }
    if (partitionIndex == 1u) { ph_temporal_scatter_cell_offsets_partition1_data[cellIndex] = value; return; }
    if (partitionIndex == 2u) { ph_temporal_scatter_cell_offsets_partition2_data[cellIndex] = value; return; }
    ph_temporal_scatter_cell_offsets_partition3_data[cellIndex] = value;
}

void lt_temporal_scatter_store_sorted_reservoir(uint partitionIndex, uint contributorIndex, uvec2 sortedReservoir)
{
    if (partitionIndex == 0u) { ph_temporal_scatter_sorted_reservoirs_partition0_data[contributorIndex] = sortedReservoir; return; }
    if (partitionIndex == 1u) { ph_temporal_scatter_sorted_reservoirs_partition1_data[contributorIndex] = sortedReservoir; return; }
    if (partitionIndex == 2u) { ph_temporal_scatter_sorted_reservoirs_partition2_data[contributorIndex] = sortedReservoir; return; }
    ph_temporal_scatter_sorted_reservoirs_partition3_data[contributorIndex] = sortedReservoir;
}

uvec2 lt_temporal_scatter_load_sorted_reservoir(uint partitionIndex, uint contributorIndex)
{
    if (partitionIndex == 0u) return ph_temporal_scatter_sorted_reservoirs_partition0_data[contributorIndex];
    if (partitionIndex == 1u) return ph_temporal_scatter_sorted_reservoirs_partition1_data[contributorIndex];
    if (partitionIndex == 2u) return ph_temporal_scatter_sorted_reservoirs_partition2_data[contributorIndex];
    return ph_temporal_scatter_sorted_reservoirs_partition3_data[contributorIndex];
}
#endif

#ifndef PH_LIGHTTREE_INITIAL_SAMPLE_COUNT_HELPERS
#define PH_LIGHTTREE_INITIAL_SAMPLE_COUNT_HELPERS
int lt_resolve_initial_num_environment_samples();
int lt_resolve_initial_num_brdf_samples();
#endif

#include "/photonics/lighttree/nrd_material_id.glsl"

#ifndef PH_LIGHTTREE_INITIAL_SAMPLES
#define PH_LIGHTTREE_INITIAL_SAMPLES 1
#endif

uint lt_rng_hash(uint x)
{
    x ^= x >> 16u;
    x *= 0x7feb352du;
    x ^= x >> 15u;
    x *= 0x846ca68bu;
    x ^= x >> 16u;
    return x;
}

RTXDI_RandomSamplerState lt_init_random_sampler(uvec2 pixelPosition, uint frameIndex, uint seed)
{
    RTXDI_RandomSamplerState rng;
    uint mixed = pixelPosition.x * 0x1f123bb5u;
    mixed ^= pixelPosition.y * 0x5f356495u;
    mixed ^= frameIndex * 0x9e3779b9u;
    mixed ^= seed * 0x85ebca6bu;
    rng.seed = lt_rng_hash(mixed | 1u);
    rng.index = 1u;
    return rng;
}

float lt_next_random(inout RTXDI_RandomSamplerState rng)
{
    rng.seed = lt_rng_hash(rng.seed + 0x9e3779b9u);
    return float(rng.seed & 0x00ffffffu) / float(0x01000000u);
}

layout(std430) restrict readonly buffer ph_global_light_cdf {
    float ph_global_light_cdf_data[];
};

// RTXDI: RTXDI_RIS_BUFFER — declared in light_tree.glsl (included above).
// Unified buffer containing presample tiles and ReGIR output.
// Used as outside-grid fallback in RTXDI_SampleLocalLights, matching RTXDI InitialSampling.hlsli

uniform int  ph_ris_tile_size;            // RTXDI: risBufferSegmentParams.tileSize
uniform int  ph_ris_tile_count;           // RTXDI: risBufferSegmentParams.tileCount
uniform int  ph_ris_tile_buffer_offset;   // RTXDI: risBufferSegmentParams.bufferOffset (typically 0)

// Reverse light mapping: current-frame index → previous-frame index.
// Inverse of ph_light_list_mapping (previous→current). Built in LightRegistry.java.
// Returns -1 when no previous-frame equivalent exists for the current-frame light.
layout(std430) restrict readonly buffer ph_light_reverse_mapping_buf {
    int ph_light_reverse_mapping[];
};

// Previous-frame light data — double-buffered copy of ph_light_list from the prior frame.
// Enables RTXDI-style RAB_LoadLightInfo(id, true) semantics for temporal resampling.
// Memory layout is identical to ph_light_list (std140, 4 vec4s per light).
layout(std140) restrict readonly buffer ph_light_list_previous {
    vec4 ph_lights_array_previous[];
};

Light lt_invalid_light() {
    return Light(
        -1,
        0,
        vec3(0.0),
        vec3(0.0),
        0.0,
        vec2(0.0),
        0.0,
        0.0,
        vec3(0.0, 1.0, 0.0),
        0.0
    );
}

// Uses the exact same decoding as load_light() in ph_core.glsl but reads from
// ph_lights_array_previous instead of ph_lights_array.
// RTXDI equivalent: RAB_LoadLightInfo(index, true)
Light load_previous_light(int index) {
    // RTXDI: RAB_LoadLightInfo(selectedLightPrevID, true) loads unconditionally.
    // Validate against the previous-frame buffer capacity (maxLights), NOT ph_light_count.
    if (index < 0 || index * light_size + 3 >= ph_lights_array_previous.length()) {
        return lt_invalid_light();
    }

    int base = index * light_size;

    vec4 position_full    = ph_lights_array_previous[base + 0];
    vec4 color_full       = ph_lights_array_previous[base + 1];
    vec4 attenuation_full = ph_lights_array_previous[base + 2];
    vec4 orientation_full = ph_lights_array_previous[base + 3];

    return Light(
        index,
        floatBitsToInt(position_full.w),
        position_full.xyz - world_offset,
        color_full.xyz,
        color_full.w,
        attenuation_full.xy,
        attenuation_full.z,
        attenuation_full.w,
        normalize(orientation_full.xyz + vec3(1e-6f)),
        orientation_full.w
    );
}

// Default constants -- used as fallback documentation values; runtime values come from uniforms below.
const float lt_depth_threshold = 0.1f;
const float lt_surface_normal_threshold = 0.5f;
const float lt_visibility_reuse_max_age = 4.0f;      // RTXDI default: finalVisibilityMaxAge = 4
const float lt_visibility_reuse_max_distance = 16.0f;  // RTXDI default: finalVisibilityMaxDistance = 16

// ReSTIR DI parameter surface -- matches RTXDI runtime parameter structs.
// Registered by LightTreeRenderer; fall back to 0.0 (unbound) which callers must handle.
uniform float ph_restir_depth_threshold;           // RTXDI: depthThreshold (shared, default 0.1)
uniform float ph_restir_normal_threshold;          // RTXDI: normalThreshold (shared, default 0.5)
uniform float ph_restir_visibility_max_age;        // RTXDI: finalVisibilityMaxAge (default 4)
uniform float ph_restir_visibility_max_distance;   // RTXDI: finalVisibilityMaxDistance (default 16)
uniform float ph_restir_spatial_sample_count;      // RTXDI: numSamples (default 1)
uniform float ph_restir_spatial_radius;            // RTXDI: samplingRadius (default 32.0)
// RTXDI: params.activeCheckerboardField (0 = off, 1/2 = alternating fields).
// SDK default (ReSTIRDI.cpp UpdateCheckerboardField): 0 (off) for CheckerboardMode::Off.
// Shared across spatial/shading passes and NRD helpers.
#ifndef PH_RESTIR_CHECKERBOARD_DECLARED
#define PH_RESTIR_CHECKERBOARD_DECLARED
uniform int ph_restir_active_checkerboard_field;
uniform int ph_restir_frame_index;
#endif
uniform float ph_restir_spatial_depth_threshold;   // RTXDI: spatial depthThreshold (default 0.1)
uniform float ph_restir_spatial_normal_threshold;  // RTXDI: spatial normalThreshold (default 0.5)
#ifndef PH_RESTIR_SPATIAL_PARAMS_DECLARED
#define PH_RESTIR_SPATIAL_PARAMS_DECLARED
uniform float ph_restir_spatial_bias_mode;         // RTXDI: biasCorrectionMode
uniform float ph_restir_spatial_discount_naive;    // RTXDI: discountNaiveSamples
uniform float ph_restir_spatial_material_test;     // RTXDI: enableMaterialSimilarityTest
uniform float ph_restir_spatial_boost_samples;     // RTXDI: numDisocclusionBoostSamples
uniform float ph_restir_spatial_target_history;    // RTXDI: targetHistoryLength
#endif
uniform float ph_restir_enable_final_visibility;   // RTXDI: enableFinalVisibility
uniform float ph_restir_reuse_final_visibility;    // RTXDI: reuseFinalVisibility
uniform float ph_restir_enable_denoiser_packing;   // RTXDI: enableDenoiserInputPacking
uniform float ph_debug_enable_direct_temporal_reuse;
uniform float ph_debug_enable_direct_spatial_reuse;
uniform float ph_debug_enable_direct_final_visibility;
uniform float ph_debug_enable_direct_visibility_transmittance;
uniform float ph_scatter_temporal_enabled;  // 1.0 = scatter temporal resampling active

// Area-ReSTIR shift mapping mode uniforms.
// Values map to AREA_RESTIR_SHIFT_MODE_* enums:
//   0 = OnlyRandomReplay, 1 = OnlyReconnection (default), 2 = MIS (both)
// When unbound (0.0), defaults to OnlyReconnection (1).
uniform float ph_area_restir_temporal_shift_mode;
uniform float ph_area_restir_spatial_shift_mode;
// Area-ReSTIR temporal max history length (caps previous reservoir M).
// When unbound (0.0), defaults to 20.
uniform float ph_area_restir_max_history_length;

const int RTXDI_BIAS_CORRECTION_OFF = 0;
const int RTXDI_BIAS_CORRECTION_BASIC = 1;
const int RTXDI_BIAS_CORRECTION_PAIRWISE = 2;
const int RTXDI_BIAS_CORRECTION_RAY_TRACED = 3;
const int RTXDI_LOCAL_LIGHT_SAMPLING_UNIFORM   = 0;
const int RTXDI_LOCAL_LIGHT_SAMPLING_POWER_RIS = 1;
const int RTXDI_LOCAL_LIGHT_SAMPLING_REGIR_RIS = 2;

// Initial sampling parameters — matches RTXDI_DIInitialSamplingParameters (ReSTIRDIParameters.h lines 69-85).
// When 0.0 (unbound), fall back to compile-time macro values.
uniform float ph_restir_initial_num_local_samples;       // RTXDI: numLocalLightSamples
// RTXDI: numEnvironmentSamples (SDK default 1, ReSTIRDI.cpp line 41).
// This port uses a negative sentinel to explicitly disable the technique when the
// environment-light path is not implemented. 0.0 remains "use SDK default".
uniform float ph_restir_initial_num_environment_samples;
uniform float ph_restir_initial_num_brdf_samples;        // RTXDI: numBrdfSamples; SDK default=1. -1.0=disable, 0.0(unbound)=SDK default(1), >0=explicit count
uniform float ph_restir_initial_enable_visibility;  // RTXDI: enableInitialVisibility; SDK default true. Sentinel: -1.0=disabled, 0.0(unbound)=enabled, 1.0=enabled
uniform float ph_restir_initial_brdf_cutoff;        // RTXDI: brdfCutoff (MIS cutoff for BRDF-length shortening)
uniform float ph_restir_debug_force_target_pdf_one;       // Hidden debug override: force targetPdf = 1 during DI proposal weighting.
uniform float ph_restir_debug_force_shading_inv_pdf_one;  // Hidden debug override: force reservoir invPdf = 1 during shading.
uniform float ph_restir_debug_force_solid_angle_pdf_one;  // Hidden debug override: force light sample solidAnglePdf = 1 during shading.

// Local light sampling mode — matches RTXDI_DIInitialSamplingParameters::localLightSamplingMode
// (ReSTIRDI_LocalLightSamplingMode enum in RtxdiParameters.h lines 44-48):
//   -1.0 → SDK default (Uniform, mode 0)
//    0.0 (unbound) → SDK default (Uniform, mode 0)
//    0 = ReSTIRDI_LocalLightSamplingMode_UNIFORM   — equal probability from light buffer
//    1 = ReSTIRDI_LocalLightSamplingMode_POWER_RIS — power-CDF importance sampling (stratified)
//    2 = ReSTIRDI_LocalLightSamplingMode_REGIR_RIS — ReGIR cell-based RIS (with Power_RIS fallback)
// SDK default (ReSTIRDI.cpp line 45): Uniform (0).
uniform float ph_restir_local_light_sampling_mode;

float lt_debug_resolve_target_pdf(float targetPdf) {
    return (ph_restir_debug_force_target_pdf_one >= 0.5f) ? 1.0f : targetPdf;
}

float lt_debug_resolve_shading_inv_pdf(float invPdf) {
    return (ph_restir_debug_force_shading_inv_pdf_one >= 0.5f) ? 1.0f : invPdf;
}

float lt_debug_resolve_solid_angle_pdf(float solidAnglePdf) {
    return (ph_restir_debug_force_solid_angle_pdf_one >= 0.5f) ? 1.0f : solidAnglePdf;
}

// GLSL requires declarations before first use; these helpers are defined later in the file.
ivec2 RTXDI_PixelPosToReservoirPos(ivec2 pixelPosition, int activeCheckerboardField);
ivec2 RTXDI_ReservoirPosToPixelPos(ivec2 reservoirIndex, int activeCheckerboardField);

bool lt_is_viewport_uv_in_bounds(ivec2 uv) {
    return all(greaterThanEqual(uv, ivec2(0))) && all(lessThan(uv, ivec2(int(viewWidth), int(viewHeight))));
}

bool lt_is_viewport_uv_in_bounds(vec2 uv) {
    return all(greaterThanEqual(uv, vec2(0.0f))) && all(lessThan(uv, vec2(viewWidth, viewHeight)));
}

ivec2 lt_current_reservoir_pos() {
    return ivec2(gl_FragCoord.xy);
}

ivec2 lt_fragment_pixel_pos() {
    return tex_coord;
}

ivec2 lt_current_pixel_pos() {
    return RTXDI_ReservoirPosToPixelPos(lt_current_reservoir_pos(), ph_restir_active_checkerboard_field);
}

ivec2 lt_current_full_res_pixel_pos() {
    return lt_current_pixel_pos();
}

ivec2 lt_current_pass_pixel_pos() {
    return lt_fragment_pixel_pos();
}

ivec2 lt_pass_pixel_to_reservoir_pos(ivec2 pixelPos) {
    return RTXDI_PixelPosToReservoirPos(pixelPos, ph_restir_active_checkerboard_field);
}

bool lt_is_active_reservoir_lane(ivec2 reservoirPos) {
    return ph_restir_active_checkerboard_field == 0
        || lt_is_viewport_uv_in_bounds(RTXDI_ReservoirPosToPixelPos(reservoirPos, ph_restir_active_checkerboard_field));
}

uint lt_temporal_scatter_linear_index(ivec2 reservoirPos) {
    ivec2 size = ivec2(max(int(ceil(viewWidth * ((ph_restir_active_checkerboard_field == 0) ? 1.0f : 0.5f))), 1), max(int(viewHeight), 1));
    return uint(clamp(reservoirPos.y, 0, size.y - 1) * size.x + clamp(reservoirPos.x, 0, size.x - 1));
}

uvec2 lt_temporal_scatter_decode_linear_index(uint linearIndex) {
    ivec2 size = ivec2(max(int(ceil(viewWidth * ((ph_restir_active_checkerboard_field == 0) ? 1.0f : 0.5f))), 1), max(int(viewHeight), 1));
    uint width = uint(size.x);
    return uvec2(linearIndex % width, linearIndex / width);
}

// RTXDI neighbor offset buffer — 8192 entries generated by FillNeighborOffsetBuffer (RtxdiUtils.cpp).
// The SDK stores two signed 8-bit values per neighbor. Mirror that storage exactly here
// and reconstruct signed offsets before multiplying by the sampling radius.
// Populated once at init by LightRegistry.fillNeighborOffsets(); never written per-frame.
// neighborOffsetMask = lt_neighbor_offset_count - 1 = 8191.
// SDK default: NeighborOffsetCount = 8192 (ReSTIRDI.h line 45).
layout(std430) restrict readonly buffer ph_neighbor_offsets {
    uint ph_neighbor_offsets_data[];
};

const int lt_neighbor_offset_count = 8192;

int lt_unpack_neighbor_offset_byte(int byteIndex) {
    uint packedWord = ph_neighbor_offsets_data[byteIndex >> 2];
    uint shift = uint(byteIndex & 3) << 3u;
    int packedByte = int((packedWord >> shift) & 0xffu);
    return (packedByte << 24) >> 24;
}

vec2 lt_load_neighbor_offset(int sampleIdx) {
    int packedIndex = (sampleIdx & (lt_neighbor_offset_count - 1)) * 2;
    vec2 offset = vec2(
        float(lt_unpack_neighbor_offset_byte(packedIndex + 0)),
        float(lt_unpack_neighbor_offset_byte(packedIndex + 1))
    ) / 127.0f;
    return clamp(offset, vec2(-1.0f), vec2(1.0f));
}

ivec2 lt_calculate_spatial_resampling_offset(int sampleIdx, float radius) {
    // RTXDI SpatialResampling.hlsli line 63: (startIdx + i) & params.neighborOffsetMask
    // Bitmask wrap requires lt_neighbor_offset_count to be a power of 2 (8192 = 2^13).
    sampleIdx &= (lt_neighbor_offset_count - 1);
    return ivec2(lt_load_neighbor_offset(sampleIdx) * radius);
}

// RTXDI: RTXDI_IsActiveCheckerboardPixel (Checkerboard.hlsli lines 16-25).
// Returns true when the pixel is an active checkerboard pixel for this frame/field.
bool RTXDI_IsActiveCheckerboardPixel(ivec2 pixelPosition, bool previousFrame, int activeCheckerboardField) {
    if (activeCheckerboardField == 0)
        return true;
    return ((pixelPosition.x + pixelPosition.y + int(previousFrame)) & 1) == (activeCheckerboardField & 1);
}

int lt_previous_checkerboard_field(int activeCheckerboardField) {
    if (activeCheckerboardField == 0) {
        return 0;
    }
    return 3 - activeCheckerboardField;
}

// RTXDI: RTXDI_ActivateCheckerboardPixel (Checkerboard.hlsli lines 27-43).
// Shifts the pixel position to the nearest active checkerboard pixel when not already active.
// Ports the exact SDK logic for both previousFrame and current-frame cases:
//   previousFrame=true:  shift by (activeCheckerboardField * 2 - 3), i.e. -1 for field=1, +1 for field=2.
//   previousFrame=false: shift by +1 or -1 depending on row parity to interleave the checkerboard.
// When activeCheckerboardField == 0 this is a no-op (off).
void RTXDI_ActivateCheckerboardPixel(inout ivec2 pixelPos, bool previousFrame, int activeCheckerboardField) {
    if (RTXDI_IsActiveCheckerboardPixel(pixelPos, previousFrame, activeCheckerboardField))
        return;

    if (previousFrame)
        pixelPos.x += activeCheckerboardField * 2 - 3;
    else
        pixelPos.x += ((pixelPos.y & 1) != 0) ? 1 : -1;
}

// RTXDI: RAB_ClampSamplePositionIntoView (RAB_SpatialHelpers.hlsli lines 20-33).
// Reflects the pixel position across screen edges instead of clamping.
// Compared to simple clamping, this prevents the spread of colorful blobs from screen edges.
// previousFrame parameter is present to match the SDK signature but not used in the reflection
// logic (the reflection is symmetric for both current and previous frames).
ivec2 RAB_ClampSamplePositionIntoView(ivec2 pixelPosition, bool previousFrame) {
    int width = int(viewWidth);
    int height = int(viewHeight);

    if (pixelPosition.x < 0) pixelPosition.x = -pixelPosition.x;
    if (pixelPosition.y < 0) pixelPosition.y = -pixelPosition.y;
    if (pixelPosition.x >= width)  pixelPosition.x = 2 * width  - pixelPosition.x - 1;
    if (pixelPosition.y >= height) pixelPosition.y = 2 * height - pixelPosition.y - 1;

    return pixelPosition;
}

// RTXDI_PixelPosToReservoirPos (ReservoirAddressing.hlsli lines 16-22).
// Identity when checkerboard is off; halves x when active.
ivec2 RTXDI_PixelPosToReservoirPos(ivec2 pixelPosition, int activeCheckerboardField) {
    if (activeCheckerboardField == 0) return pixelPosition;
    return ivec2(pixelPosition.x >> 1, pixelPosition.y);
}

// RTXDI_ReservoirPosToPixelPos (ReservoirAddressing.hlsli lines 24-30).
ivec2 RTXDI_ReservoirPosToPixelPos(ivec2 reservoirIndex, int activeCheckerboardField) {
    if (activeCheckerboardField == 0) return reservoirIndex;
    ivec2 pixelPosition = ivec2(reservoirIndex.x << 1, reservoirIndex.y);
    pixelPosition.x += ((pixelPosition.y + activeCheckerboardField) & 1);
    return pixelPosition;
}

void RTXDI_ApplyPermutationSampling(inout ivec2 prevPixelPos, uint uniformRandomNumber) {
    ivec2 offset = ivec2(uniformRandomNumber & 3u, (uniformRandomNumber >> 2u) & 3u);
    prevPixelPos += offset;

    prevPixelPos.x ^= 3;
    prevPixelPos.y ^= 3;

    prevPixelPos -= offset;
}

vec3 lt_resolve_reuse_normal(vec3 geoNormal, vec3 mappedNormal) {
    float mappedLengthSq = dot(mappedNormal, mappedNormal);
    if (mappedLengthSq > 1e-6f) {
        return normalize(mappedNormal);
    }

    float geometryLengthSq = dot(geoNormal, geoNormal);
    if (geometryLengthSq > 1e-6f) {
        return normalize(geoNormal);
    }

    return vec3(0.0f, 1.0f, 0.0f);
}

const float BACKGROUND_DEPTH = 0.0f;

struct RAB_Material {
    vec3 diffuseAlbedo;
    vec3 specularF0;
    float roughness;
    vec3 emissiveColor;
};

RAB_Material RAB_EmptyMaterial() {
    return RAB_Material(vec3(0.0f), vec3(0.0f), 0.0f, vec3(0.0f));
}

vec3 GetDiffuseAlbedo(RAB_Material material) {
    return material.diffuseAlbedo;
}

vec3 GetSpecularF0(RAB_Material material) {
    return material.specularF0;
}

float GetRoughness(RAB_Material material) {
    return material.roughness;
}

float RAB_GetRoughness(RAB_Material material) {
    return GetRoughness(material);
}

vec3 RAB_GetEmissiveColor(RAB_Material material) {
    return material.emissiveColor;
}

float lt_material_diffuse_probability_with_view(RAB_Material material, vec3 shadingNormal, vec3 viewDir);

struct RAB_Surface {
    vec3 worldPos;
    vec3 viewDir;
    vec3 normal;
    vec3 geoNormal;
    float viewDepth;
    float diffuseProbability;
    RAB_Material material;
};

RAB_Surface lt_load_surface(ivec2 uv);
RAB_Surface lt_load_previous_surface(ivec2 uv);
RAB_Surface RAB_EmptySurface();
bool lt_materials_similar(RAB_Surface a, RAB_Surface b);
bool lt_is_complex_surface(RAB_Surface surface);
int lt_resolve_initial_num_environment_samples();
int lt_resolve_initial_num_brdf_samples();
int RAB_TranslateLightIndex(int lightIndex, bool previousFrame);
bool RAB_AreMaterialsSimilar(RAB_Material a, RAB_Material b);
RAB_Material lt_make_material(vec4 packedMaterial, vec3 diffuseAlbedoValue) {
    vec3 diffuseAlbedo = clamp(diffuseAlbedoValue, vec3(0.0f), vec3(1.0f));
    float roughness = clamp(packedMaterial.x, 0.0f, 1.0f);
    float metallic = clamp(packedMaterial.y, 0.0f, 1.0f);
    float emission = clamp(packedMaterial.z, 0.0f, 1.0f);
    return RAB_Material(
        diffuseAlbedo,
        mix(vec3(0.04f), diffuseAlbedo, metallic),
        roughness,
        diffuseAlbedo * emission
    );
}

RAB_Material lt_extract_material_at_uv(vec2 uv) {
    vec4 spec = texture(specular, uv);
    float smoothness = clamp(spec.r, 0.0f, 1.0f);
    float roughness = clamp(1.0f - smoothness, 0.0f, 1.0f);
    float metallic = clamp(spec.g, 0.0f, 1.0f);
    float emission = clamp(spec.a, 0.0f, 1.0f);
    return lt_make_material(
        vec4(roughness, metallic, emission, 0.0f),
        vec3(1.0f)
    );
}

vec3 lt_surface_rt_pos(RAB_Surface surface) {
    return surface.worldPos - world_offset;
}

RAB_Surface lt_make_surface(vec3 worldPosValue, vec3 geoNormalValue, vec3 shadingNormalValue, vec3 albedoValue, RAB_Material materialValue, vec3 cameraWorldPosition, float linearDepthValue) {
    vec3 resolvedGeoNormal = lt_resolve_reuse_normal(geoNormalValue, geoNormalValue);
    vec3 resolvedShadingNormal = lt_resolve_reuse_normal(geoNormalValue, shadingNormalValue);
    vec3 viewDir = cameraWorldPosition - worldPosValue;
    float viewDirLengthSq = dot(viewDir, viewDir);
    viewDir = (viewDirLengthSq > 1e-6f) ? (viewDir * inversesqrt(viewDirLengthSq)) : vec3(0.0f, 0.0f, 1.0f);
    materialValue.diffuseAlbedo = clamp(albedoValue, vec3(0.0f), vec3(1.0f));
    materialValue.specularF0 = clamp(materialValue.specularF0, vec3(0.0f), vec3(1.0f));

    return RAB_Surface(
        worldPosValue,
        viewDir,
        resolvedShadingNormal,
        resolvedGeoNormal,
        linearDepthValue,
        lt_material_diffuse_probability_with_view(materialValue, resolvedShadingNormal, viewDir),
        materialValue
    );
}

RAB_Surface lt_make_surface(vec3 worldPosValue, vec3 geoNormalValue, vec3 shadingNormalValue, vec3 albedoValue, RAB_Material materialValue, float linearDepthValue) {
    return lt_make_surface(
        worldPosValue,
        geoNormalValue,
        shadingNormalValue,
        albedoValue,
        materialValue,
        world_camera_position,
        linearDepthValue
    );
}

RAB_Surface lt_make_surface(vec3 worldPosValue, vec3 geoNormalValue, vec3 shadingNormalValue, vec3 albedoValue, RAB_Material materialValue) {
    return lt_make_surface(
        worldPosValue,
        geoNormalValue,
        shadingNormalValue,
        albedoValue,
        materialValue,
        ph_linear_view_depth(modelview_projection, worldPosValue)
    );
}

RAB_Surface lt_make_surface(vec3 worldPosValue, vec3 geoNormalValue, vec3 shadingNormalValue, vec4 materialValue) {
    return lt_make_surface(
        worldPosValue,
        geoNormalValue,
        shadingNormalValue,
        vec3(1.0f),
        lt_make_material(materialValue, vec3(1.0f))
    );
}

RAB_Surface lt_make_surface(vec3 worldPosValue, vec3 geoNormalValue, vec3 shadingNormalValue, vec3 albedoValue, vec4 materialValue, vec3 cameraWorldPosition, float linearDepthValue) {
    return lt_make_surface(
        worldPosValue,
        geoNormalValue,
        shadingNormalValue,
        albedoValue,
        lt_make_material(materialValue, albedoValue),
        cameraWorldPosition,
        linearDepthValue
    );
}

RAB_Surface lt_make_surface(vec3 worldPosValue, vec3 geoNormalValue, vec3 shadingNormalValue, vec3 albedoValue, vec4 materialValue, float linearDepthValue) {
    return lt_make_surface(
        worldPosValue,
        geoNormalValue,
        shadingNormalValue,
        albedoValue,
        lt_make_material(materialValue, albedoValue),
        linearDepthValue
    );
}

RAB_Surface lt_make_surface(vec3 worldPosValue, vec3 geoNormalValue, vec3 shadingNormalValue) {
    return lt_make_surface(worldPosValue, geoNormalValue, shadingNormalValue, vec3(1.0f), RAB_EmptyMaterial());
}

// RTXDI: RAB_EmptySurface() — returns a zeroed surface with a well-defined up-normal.
// Used to initialize temporalSurface before a valid temporal neighbor is found,
// matching RTXDI TemporalResampling.hlsli line 69: RAB_Surface temporalSurface = RAB_EmptySurface();
RAB_Surface lt_empty_surface() {
    return RAB_Surface(
        vec3(0.0f),
        vec3(0.0f),
        vec3(0.0f),
        vec3(0.0f),
        BACKGROUND_DEPTH,
        0.0f,
        RAB_EmptyMaterial()
    );
}

RAB_Surface lt_current_surface() {
    return lt_make_surface(
        world_pos,
        block_normal,
        normal,
        clamp(albedo, vec3(0.04f), vec3(1.0f)),
        lt_extract_material_at_uv((vec2(tex_coord) + vec2(0.5f)) / vec2(viewWidth, viewHeight)),
        ph_linear_view_depth(modelview_projection, world_pos)
    );
}

RAB_Surface lt_load_surface(ivec2 uv) {
    vec4 positionData = texelFetch(radiosity_position, uv, 0);
    if (positionData.w == BACKGROUND_DEPTH) {
        return RAB_EmptySurface();
    }
    return lt_make_surface(
        positionData.xyz,
        texelFetch(radiosity_normal, uv, 0).xyz,
        texelFetch(radiosity_mapped_normal, uv, 0).xyz,
        clamp(texelFetch(radiosity_albedo, uv, 0).rgb, vec3(0.04f), vec3(1.0f)),
        texelFetch(radiosity_material, uv, 0),
        positionData.w
    );
}

RAB_Surface lt_load_previous_surface(ivec2 uv) {
    vec4 positionData = texelFetch(prev_radiosity_position, uv, 0);
    if (positionData.w == BACKGROUND_DEPTH) {
        return RAB_EmptySurface();
    }
    return lt_make_surface(
        positionData.xyz,
        texelFetch(prev_radiosity_normal, uv, 0).xyz,
        texelFetch(prev_radiosity_mapped_normal, uv, 0).xyz,
        clamp(texelFetch(prev_radiosity_albedo, uv, 0).rgb, vec3(0.04f), vec3(1.0f)),
        texelFetch(prev_radiosity_material, uv, 0),
        previous_world_camera_position,
        positionData.w
    );
}

float rtxdi_surface_linear_depth(RAB_Surface surface, mat4 modelViewProjection) {
    return surface.viewDepth;
}

bool RAB_IsSurfaceValid(RAB_Surface surface);
vec3 RAB_GetSurfaceNormal(RAB_Surface surface);
float RAB_GetSurfaceLinearDepth(RAB_Surface surface);
RAB_Material RAB_GetMaterial(RAB_Surface surface);

// ============================================================================
// Scatter Temporal Resampling: Reconnection Data
// ============================================================================
// =====================================================================
// Reference-parity ReconnectionData (ReconnectionData.slang:89-166).
//
// Field order, names, types and default values MUST match the Slang
// reference 1:1. The Photonics GLSL port spells the struct
// `ReservoirSplattingReconnectionData` to avoid namespace conflicts with
// the RTXDI sidecar bookkeeping, and `ScatterReconnectionData` is kept as
// a macro alias for legacy call sites. DO NOT add photonics-specific
// fields here -- those belong on the per-pixel reservoir header or the
// surface identity texture, NOT on the reconnection payload.
//
// In Falcor the `HitInfo` struct packs instance+primitive+barycentric;
// on GLSL we substitute two block-coordinate channels (worldPos + faceId)
// because that IS the Minecraft-block addressing scheme the g-buffer
// writes out. These channels collectively play the role of Falcor
// `HitInfo`, so `firstHit.worldPos`, `firstHit.faceId`, and
// `firstHit.viewDepth` together substitute for the reference's
// `ReconnectionData::firstHit`. Same for `secondHit.*`. This matches the
// paper's implementation note that Area ReSTIR reservoir storage is
// extended with "the explicit object-space primary hit".
// =====================================================================
struct ReservoirSplattingHitInfo {
    vec3  worldPos;    // Object/world-space hit position
    float viewDepth;   // Linear view depth (for bilateral tests)
    uint  faceId;      // Dominant signed block face identifier
};

ReservoirSplattingHitInfo ReservoirSplattingHitInfo_empty() {
    ReservoirSplattingHitInfo h;
    h.worldPos = vec3(0.0f);
    h.viewDepth = 0.0f;
    h.faceId = 0u;
    return h;
}

// Reference-parity ``ReconnectionData`` (ReconnectionData.slang:89-166).
struct ReservoirSplattingReconnectionData {
    // Some camera / film parameters used generally.
    vec2  subPixel;                     // ReconnectionData.slang:92
    vec2  lensSample;                   // ReconnectionData.slang:93
    float time;                         // ReconnectionData.slang:94

    // The only vertex that contributes actual emission is the final
    // vertex, i.e. the path length is equivalent to the index of the
    // light vertex.
    uint  pathLength;                   // ReconnectionData.slang:98

    // Information about the first vertex.
    ReservoirSplattingHitInfo firstHit; // ReconnectionData.slang:101 (HitInfo)
    uint  firstBSDFComponentType;       // ReconnectionData.slang:102 (NOTE camelcase)
    vec3  firstWi;                      // ReconnectionData.slang:103 (toward camera)

    // Information about the second vertex.
    ReservoirSplattingHitInfo secondHit; // ReconnectionData.slang:106 (HitInfo)
    uint  secondBSDFComponentType;       // ReconnectionData.slang:107 (NOTE camelcase)
    vec3  secondWo;                      // ReconnectionData.slang:108 (outgoing at x2)

    bool  transmissionEvent;             // ReconnectionData.slang:110

    // Light-side book-keeping for NEE vs BSDF resolution at the shift.
    bool  lightIsNEE;                    // ReconnectionData.slang:113
    bool  lightIsDistant;                // ReconnectionData.slang:114
    float lightPdf;                      // ReconnectionData.slang:115

    // Jacobians carried by every shift map.
    float subPixelJacobian;              // ReconnectionData.slang:119
    float lensVertexJacobian;            // ReconnectionData.slang:120
    float secondaryPathJacobian;         // ReconnectionData.slang:121
    vec3  irradiance;                    // ReconnectionData.slang:122
    vec3  earlyThroughput;               // ReconnectionData.slang:123 (prefix thp)
};

// Back-compat alias macros. The rest of the Photonics shader layer still
// refers to this type as ``ScatterReconnectionData`` through the sidecar
// plumbing; these macros let both spellings resolve to the reference
// struct without any adaptation.
#define ScatterReconnectionData ReservoirSplattingReconnectionData

ReservoirSplattingReconnectionData ReservoirSplattingReconnectionData_init() {
    ReservoirSplattingReconnectionData d;
    // ReconnectionData.slang:127-129 -- camera / film parameters.
    d.subPixel = vec2(0.5f, 0.5f);
    d.lensSample = vec2(0.0f, 0.0f);            // Reference: float2(0, 0) (NOT 0.5).
    d.time = 0.0f;

    // ReconnectionData.slang:131.
    d.pathLength = 0u;

    // ReconnectionData.slang:133-135 -- first vertex.
    d.firstHit = ReservoirSplattingHitInfo_empty();
    d.firstBSDFComponentType = 0u;
    d.firstWi = vec3(0.0f, 0.0f, 0.0f);         // Reference: float3(0, 0, 0).

    // ReconnectionData.slang:137-139 -- second vertex.
    d.secondHit = ReservoirSplattingHitInfo_empty();
    d.secondBSDFComponentType = 0u;
    d.secondWo = vec3(0.0f, 0.0f, 0.0f);

    // ReconnectionData.slang:141 -- transmission flag.
    d.transmissionEvent = false;

    // ReconnectionData.slang:143-145 -- NEE / distant / lightPdf.
    d.lightIsNEE = false;
    d.lightIsDistant = false;
    d.lightPdf = 0.0f;

    // ReconnectionData.slang:147-151 -- Jacobians + radiance carriers.
    d.subPixelJacobian = 1.0f;
    d.lensVertexJacobian = 1.0f;
    d.secondaryPathJacobian = 1.0f;
    d.irradiance = vec3(0.0f, 0.0f, 0.0f);
    d.earlyThroughput = vec3(1.0f, 1.0f, 1.0f); // Reference: float3(1, 1, 1), NOT 0.
    return d;
}

// Legacy spelling alias -- kept because existing callers use either name.
// The `scatter_empty_reconnection` helper pre-dates the reference-aligned
// rename; both resolve to the same constructor body.
ReservoirSplattingReconnectionData scatter_empty_reconnection() {
    return ReservoirSplattingReconnectionData_init();
}

vec4 scatter_load_surface_identity(ivec2 uv, bool previousFrame) {
    return previousFrame
        ? texelFetch(prev_radiosity_identity, uv, 0)
        : texelFetch(radiosity_identity, uv, 0);
}

// Compute a voxel position hash for surface identity matching.
// In Minecraft's block world, floor(worldPos) gives exact block coordinates.
uint scatter_compute_surface_hash(vec3 worldPos) {
    ivec3 blockPos = ivec3(floor(worldPos));
    // Wang hash of packed block coordinates for uniform distribution.
    uint h = uint(blockPos.x) ^ (uint(blockPos.y) * 2654435761u) ^ (uint(blockPos.z) * 2246822519u);
    h = ((h >> 16u) ^ h) * 0x45d9f3bu;
    h = ((h >> 16u) ^ h) * 0x45d9f3bu;
    h = (h >> 16u) ^ h;
    return h;
}

const uint SCATTER_RECONNECTION_FLAG_LIGHT_IS_NEE = 1u << 0u;
const uint SCATTER_RECONNECTION_FLAG_LIGHT_IS_DISTANT = 1u << 1u;
const uint SCATTER_RECONNECTION_EVENT_TRANSMISSION = 1u << 0u;
const uint SCATTER_BSDF_COMPONENT_DIFFUSE = 0u;
const uint SCATTER_BSDF_COMPONENT_SPECULAR = 1u;
// Reference: PathReservoir.confidenceCap (Reservoir.slang:75).
const float PATH_RESERVOIR_CONFIDENCE_CAP = 20.0f;
// Legacy spelling -- kept for old call sites. New code MUST use
// `PATH_RESERVOIR_CONFIDENCE_CAP` so that it matches the reference
// `PathReservoir::confidenceCap` naming convention.
#define SCATTER_RECONNECTION_CONFIDENCE_MAX PATH_RESERVOIR_CONFIDENCE_CAP
const uint SCATTER_RECONNECTION_VIEW_DEPTH_MASK = 0x0000FFFFu;
const uint SCATTER_RECONNECTION_CONFIDENCE_MASK = 0x00000FFFu;
const uint SCATTER_RECONNECTION_CONFIDENCE_SHIFT = 16u;
const uint SCATTER_RECONNECTION_FACE_MASK = 0xFu;
const uint SCATTER_RECONNECTION_FACE_SHIFT = 0u;
const uint SCATTER_RECONNECTION_FLAGS_MASK = 0x3u;
const uint SCATTER_RECONNECTION_FLAGS_SHIFT = 4u;
const uint SCATTER_RECONNECTION_PATH_LENGTH_MASK = 0x3Fu;
const uint SCATTER_RECONNECTION_PATH_LENGTH_SHIFT = 6u;
const uint SCATTER_RECONNECTION_FIRST_BSDF_MASK = 0x3u;
const uint SCATTER_RECONNECTION_FIRST_BSDF_SHIFT = 12u;
const uint SCATTER_RECONNECTION_SECOND_BSDF_MASK = 0x3u;
const uint SCATTER_RECONNECTION_SECOND_BSDF_SHIFT = 14u;

float scatter_pack_half2(vec2 value) {
    return uintBitsToFloat(packHalf2x16(value));
}

vec2 scatter_unpack_half2(float packedValue) {
    return unpackHalf2x16(floatBitsToUint(packedValue));
}

float scatter_pack_reconnection_proposal_pdf(float proposalPdf) {
    return max(proposalPdf, 0.0f);
}

float scatter_unpack_reconnection_proposal_pdf(float packedValue) {
    return max(packedValue, 0.0f);
}

vec2 rtxdi_unpack_sample_uv(uint packedUv);
uint lt_path_sample_proposal_family(uint pathSample);

float scatter_pack_unit_vector(vec3 direction) {
    float directionLengthSq = dot(direction, direction);
    vec3 n = directionLengthSq > 1e-12f
        ? direction * inversesqrt(directionLengthSq)
        : vec3(0.0f, 0.0f, 1.0f);
    vec2 p = n.xy / (abs(n.x) + abs(n.y) + abs(n.z));
    if (n.z < 0.0f) {
        p = (1.0f - abs(p.yx)) * sign(p.xy);
    }
    return scatter_pack_half2(clamp(p, vec2(-1.0f), vec2(1.0f)));
}

vec3 scatter_unpack_unit_vector(float packedValue) {
    vec2 p = scatter_unpack_half2(packedValue);
    vec3 n = vec3(p.x, p.y, 1.0f - abs(p.x) - abs(p.y));
    if (n.z < 0.0f) {
        n.xy = (1.0f - abs(n.yx)) * sign(n.xy);
    }
    return normalize(n);
}

vec3 scatter_pack_relative_second_pos(vec3 worldPos, vec3 secondPos) {
    return secondPos - worldPos;
}

vec3 scatter_unpack_relative_second_pos(vec3 worldPos, vec3 packedSecondPos) {
    return worldPos + packedSecondPos;
}

float scatter_clamp_reconnection_confidence(float confidence) {
    return clamp(confidence, 0.0f, PATH_RESERVOIR_CONFIDENCE_CAP);
}

float scatter_encode_reconnection_face(uint faceId) {
    return float(faceId & SCATTER_RECONNECTION_FACE_MASK);
}

uint scatter_decode_reconnection_face(float encodedFace) {
    return uint(clamp(round(encodedFace), 0.0f, float(SCATTER_RECONNECTION_FACE_MASK)));
}

// Pack light-side flags (`lightIsNEE`, `lightIsDistant`,
// `transmissionEvent`) into a single `uint` flag bag for storage.
uint scatter_pack_reconnection_flags(ReservoirSplattingReconnectionData d) {
    uint flags = 0u;
    if (d.lightIsNEE)        flags |= SCATTER_RECONNECTION_FLAG_LIGHT_IS_NEE;
    if (d.lightIsDistant)    flags |= SCATTER_RECONNECTION_FLAG_LIGHT_IS_DISTANT;
    return flags;
}

void scatter_unpack_reconnection_flags(uint packedFlags, inout ReservoirSplattingReconnectionData d) {
    d.lightIsNEE     = (packedFlags & SCATTER_RECONNECTION_FLAG_LIGHT_IS_NEE)     != 0u;
    d.lightIsDistant = (packedFlags & SCATTER_RECONNECTION_FLAG_LIGHT_IS_DISTANT) != 0u;
}

uint scatter_pack_reconnection_meta(ReservoirSplattingReconnectionData d) {
    uint packedFlags = scatter_pack_reconnection_flags(d);
    return ((d.firstHit.faceId & SCATTER_RECONNECTION_FACE_MASK) << SCATTER_RECONNECTION_FACE_SHIFT)
        | ((packedFlags & SCATTER_RECONNECTION_FLAGS_MASK) << SCATTER_RECONNECTION_FLAGS_SHIFT)
        | ((d.pathLength & SCATTER_RECONNECTION_PATH_LENGTH_MASK) << SCATTER_RECONNECTION_PATH_LENGTH_SHIFT)
        | ((d.firstBSDFComponentType & SCATTER_RECONNECTION_FIRST_BSDF_MASK) << SCATTER_RECONNECTION_FIRST_BSDF_SHIFT)
        | ((d.secondBSDFComponentType & SCATTER_RECONNECTION_SECOND_BSDF_MASK) << SCATTER_RECONNECTION_SECOND_BSDF_SHIFT)
        | ((d.transmissionEvent ? 1u : 0u) << 16u);
}

void scatter_unpack_reconnection_meta(uint packedMeta, inout ReservoirSplattingReconnectionData d) {
    d.firstHit.faceId = (packedMeta >> SCATTER_RECONNECTION_FACE_SHIFT) & SCATTER_RECONNECTION_FACE_MASK;
    uint packedFlags  = (packedMeta >> SCATTER_RECONNECTION_FLAGS_SHIFT) & SCATTER_RECONNECTION_FLAGS_MASK;
    scatter_unpack_reconnection_flags(packedFlags, d);
    d.pathLength              = (packedMeta >> SCATTER_RECONNECTION_PATH_LENGTH_SHIFT) & SCATTER_RECONNECTION_PATH_LENGTH_MASK;
    d.firstBSDFComponentType  = (packedMeta >> SCATTER_RECONNECTION_FIRST_BSDF_SHIFT) & SCATTER_RECONNECTION_FIRST_BSDF_MASK;
    d.secondBSDFComponentType = (packedMeta >> SCATTER_RECONNECTION_SECOND_BSDF_SHIFT) & SCATTER_RECONNECTION_SECOND_BSDF_MASK;
    d.transmissionEvent       = ((packedMeta >> 16u) & 0x1u) != 0u;
    // secondHit.faceId round-trips the same storage as firstHit.faceId -- DI
    // paths only use the primary hit block face for matching, so we reuse the
    // same nybble for both fields.
    d.secondHit.faceId = d.firstHit.faceId;
}

// Reference ReconnectionData.slang:44 -- kIntegrand = irradiance * earlyThroughput.
// The post-reconnection integrand is the product of the light irradiance at the
// reconnection vertex and the subpath throughput leading up to it. This helper
// reconstructs that quantity so scatter/gather stages can compute luminance(pHat).
vec3 scatter_reconnection_integrand(ReservoirSplattingReconnectionData d) {
    return max(d.irradiance * d.earlyThroughput, vec3(0.0f));
}

// Pack the temporal-history reconnection data into the sidecar plus
// widened reservoir meta channels. The float outputs remain finite.
//
// The Photonics storage layout allocates 2 x RGBA32F attachments
// (`reconnection0`, `reconnection1`) + 2 scalar aux channels on the
// reservoir meta texture:
//
//   reconnection0.xyz = firstHit.worldPos
//   reconnection0.w   = firstHit.viewDepth
//   reconnection1.x   = packed(half2: lightPdf / subPixelJacobian for short-round-trip redundancy)
//   reconnection1.y   = asfloat(packedMeta uint: faceId|flags|pathLength|firstBSDF|secondBSDF|transmission)
//   reconnection1.z   = packed(half2: subPixel.xy)
//   reconnection1.w   = packed(half2: subPixelJacobian, secondaryPathJacobian)
//   transportAux0     = lightPdf (unclamped)
//   transportAux1     = packed(half2: time, luminance(irradiance))
//
// The reservoir confidence (c_i in the reference PathReservoir) is NOT stored
// in the reconnection sidecar any more -- it now lives on RTXDI_DIReservoir.M
// which is the Photonics PathReservoir.confidence carrier. Same for
// PathReservoir.integrand and PathReservoir.totalWeight.
void scatter_pack_reconnection(
    ReservoirSplattingReconnectionData d,
    out float transportAux0,
    out float transportAux1,
    out vec4 out0,
    out vec4 out1
) {
    transportAux0 = scatter_pack_reconnection_proposal_pdf(d.lightPdf);
    transportAux1 = scatter_pack_half2(vec2(
        clamp(d.time, 0.0f, 1.0f),
        clamp(ph_luminance(max(d.irradiance, vec3(0.0f))), 0.0f, 65504.0f)
    ));

    out0 = vec4(d.firstHit.worldPos, d.firstHit.viewDepth);
    out1 = vec4(
        scatter_pack_half2(vec2(
            clamp(d.lightPdf, 0.0f, 65504.0f),
            clamp(d.subPixelJacobian, 0.0f, 65504.0f)
        )),
        uintBitsToFloat(scatter_pack_reconnection_meta(d)),
        scatter_pack_half2(clamp(d.subPixel, vec2(0.0f), vec2(1.0f))),
        scatter_pack_half2(vec2(
            clamp(d.subPixelJacobian, 0.0f, 65504.0f),
            clamp(d.secondaryPathJacobian, 0.0f, 65504.0f)
        ))
    );
}

// Unpack reconnection data from two texel fetches plus widened reservoir metadata.
ReservoirSplattingReconnectionData scatter_unpack_reconnection(vec4 data0, vec4 data1, vec4 sampleData, float transportAux0, float transportAux1) {
    ReservoirSplattingReconnectionData d = ReservoirSplattingReconnectionData_init();
    d.firstHit.worldPos  = data0.xyz;
    d.firstHit.viewDepth = data0.w;
    d.lightPdf           = scatter_unpack_reconnection_proposal_pdf(transportAux0);
    scatter_unpack_reconnection_meta(floatBitsToUint(data1.y), d);
    d.subPixel  = clamp(scatter_unpack_half2(data1.z), vec2(0.0f), vec2(1.0f));
    d.lensSample = clamp(rtxdi_unpack_sample_uv(floatBitsToUint(sampleData.z)), vec2(0.0f), vec2(1.0f));
    vec2 packedTimeIrradiance = scatter_unpack_half2(transportAux1);
    d.time = clamp(packedTimeIrradiance.x, 0.0f, 1.0f);
    vec2 packedJacobians = scatter_unpack_half2(data1.w);
    d.subPixelJacobian      = max(packedJacobians.x, 1e-10f);
    d.secondaryPathJacobian = max(packedJacobians.y, 1e-10f);
    d.firstWi = normalize(world_camera_position - d.firstHit.worldPos);
    // secondHit / secondWo are DI-unused -- zero by default. For path lengths
    // >= 3 the scatter stage would need to store the secondary hit; the
    // Photonics DI pipeline never walks past length 2 so this stays zero.
    d.secondHit = ReservoirSplattingHitInfo_empty();
    d.secondWo  = vec3(0.0f);
    d.irradiance = vec3(max(packedTimeIrradiance.y, 0.0f));
    d.earlyThroughput = vec3(1.0f);
    return d;
}

// Load reconnection data from previous-frame textures.
ScatterReconnectionData scatter_load_gather_intermediate_reconnection(ivec2 uv) {
    vec4 intermediateReservoirMeta = texelFetch(temporal_gather_intermediate_reservoir_meta, uv, 0);
    return scatter_unpack_reconnection(
        texelFetch(temporal_gather_intermediate_reconnection0, uv, 0),
        texelFetch(temporal_gather_intermediate_reconnection1, uv, 0),
        texelFetch(temporal_gather_intermediate_reservoir_sample, uv, 0),
        intermediateReservoirMeta.y,
        intermediateReservoirMeta.z
    );
}

vec2 scatter_load_gather_floating_coords(ivec2 uv) {
    return texelFetch(temporal_gather_floating_coords, uv, 0).xy;
}

ScatterReconnectionData scatter_load_prev_reconnection(ivec2 uv) {
    vec4 prevReservoirMeta = texelFetch(prev_radiosity_reservoir_meta, uv, 0);
    return scatter_unpack_reconnection(
        texelFetch(previous_frame_reconnection0, uv, 0),
        texelFetch(previous_frame_reconnection1, uv, 0),
        texelFetch(prev_radiosity_reservoir_samples, uv, 0),
        prevReservoirMeta.y,
        prevReservoirMeta.z
    );
}

bool scatter_reconnection_matches_surface(ReservoirSplattingReconnectionData reconnection, ivec2 pixelPosition, RAB_Surface currentSurface, bool previousFrame) {
    vec4 currentIdentity = scatter_load_surface_identity(pixelPosition, previousFrame);
    uint currentFaceId = uint(round(currentIdentity.w));
    uint reconnectionSurfaceHash = scatter_compute_surface_hash(reconnection.firstHit.worldPos);
    uint currentSurfaceHash = scatter_compute_surface_hash(currentSurface.worldPos);

    float maxDepth = max(reconnection.firstHit.viewDepth, currentSurface.viewDepth);
    float depthTolerance = max(1e-3f, 0.05f * maxDepth);
    float worldTolerance = max(0.05f, 0.03f * maxDepth);
    float fractionalTolerance = 12.0f / 256.0f;

    float fractionalDistance = distance(fract(reconnection.firstHit.worldPos), currentIdentity.xyz);
    float worldDistance = distance(reconnection.firstHit.worldPos, currentSurface.worldPos);
    bool depthCompatible = abs(reconnection.firstHit.viewDepth - currentSurface.viewDepth) <= depthTolerance;
    bool nearSurface = worldDistance <= worldTolerance;
    bool sameHashedBlock = reconnectionSurfaceHash == currentSurfaceHash;
    bool faceCompatible = reconnection.firstHit.faceId == currentFaceId || nearSurface;
    bool positionCompatible = (sameHashedBlock && fractionalDistance <= fractionalTolerance) || nearSurface;

    return depthCompatible && faceCompatible && positionCompatible;
}

// Back-compat 3-arg overload. Same semantics with ``previousFrame = false``
// for call sites that predate the gather-shift previous-frame flag.
bool scatter_reconnection_matches_surface(ReservoirSplattingReconnectionData reconnection, ivec2 pixelPosition, RAB_Surface currentSurface) {
    return scatter_reconnection_matches_surface(reconnection, pixelPosition, currentSurface, false);
}

// Forward-project a world-space position to the current frame's screen pixel.
// Returns the fractional pixel coordinate, or vec2(-1.0) if behind camera / off screen.
// This implements Section 4.1.1 of Liu et al. 2025 (Reservoir Splatting).
vec2 scatter_forward_project_to_current_frame(vec3 worldPos) {
    vec4 clipPos = modelview_projection * vec4(worldPos, 1.0f);
    if (clipPos.w <= 0.0f) return vec2(-1.0f);  // Behind camera
    vec3 ndc = clipPos.xyz / clipPos.w;
    if (any(greaterThan(abs(ndc.xy), vec2(1.0f)))) return vec2(-1.0f);  // Off screen
    // NDC [-1,1] to pixel coordinates [0, resolution)
    return (ndc.xy * 0.5f + 0.5f) * vec2(viewWidth, viewHeight);
}

// Compute the sub-pixel Jacobian at a single camera vertex (Equation 15).
// Reference: PathTracer.slang:821-826, ShiftMapping.slang:141,402
//   J_subpixel = |cos(theta_normal)| / (d^2 * |cos(theta_sensor)|^3)
// where:
//   theta_normal = angle between incoming ray and surface face normal at x1
//   d = distance from camera origin to x1
//   theta_sensor = angle between camera forward direction and ray direction
// For pinhole cameras (no DoF), lensVertexJacobian = 1.
float scatter_compute_subpixel_jacobian(
    vec3 primaryHitPos,
    vec3 primaryHitNormal,
    vec3 cameraPos,
    vec3 cameraForward)
{
    vec3 toHit = primaryHitPos - cameraPos;
    float dist = length(toHit);
    if (dist < 1e-6f) return 1.0f;
    vec3 rayDir = toHit / dist;

    float cosNormal = abs(dot(-rayDir, primaryHitNormal));
    float cosSensor = max(abs(dot(cameraForward, rayDir)), 1e-6f);

    // Equation 15: J_subpixel = |cos_normal| / (dist^2 * |cos_sensor|^3)
    float jacobian = cosNormal / (dist * dist * cosSensor * cosSensor * cosSensor);
    return max(jacobian, 1e-10f);
}

// Compute the full scatter Jacobian as the ratio J_dst / J_src (Equation 16).
// Reference: ScatterTemporalResampling.rt.slang:88,130
//   J_total = (J_subpixel_dst * J_secondary_dst) / (J_subpixel_src * J_secondary_src)
//
// For DI (direct illumination) in Minecraft, the secondary path Jacobian
// accounts for the geometry term change at the light vertex when reconnecting
// from a different surface point. For point lights (no area), J_secondary = 1
// because the light PDF doesn't depend on the reconnection geometry.
// The ratio simplifies to J_subpixel_dst / J_subpixel_src.
//
// The caller provides the pre-computed per-pixel subPixelJacobian values
// from both the source (previous) and destination (current) frames.
float scatter_compute_scatter_jacobian(
    float srcSubPixelJacobian,
    float dstSubPixelJacobian,
    float srcSecondaryPathJacobian,
    float dstSecondaryPathJacobian)
{
    float srcJ = srcSubPixelJacobian * srcSecondaryPathJacobian;
    float dstJ = dstSubPixelJacobian * dstSecondaryPathJacobian;
    if (srcJ < 1e-10f) return 1.0f;
    return clamp(dstJ / srcJ, 1e-4f, 1e4f);
}

float scatter_resolve_stored_subpixel_jacobian(
    ReservoirSplattingReconnectionData reconnection,
    RAB_Surface fallbackSurface,
    vec3 fallbackCameraPos,
    vec3 fallbackCameraForward)
{
    bool hasStoredJacobian = reconnection.firstHit.viewDepth > 0.0f
        && any(greaterThan(abs(reconnection.firstHit.worldPos), vec3(0.0f)))
        && reconnection.subPixelJacobian > 1e-10f;
    if (hasStoredJacobian) {
        return reconnection.subPixelJacobian;
    }

    return scatter_compute_subpixel_jacobian(
        fallbackSurface.worldPos,
        fallbackSurface.geoNormal,
        fallbackCameraPos,
        fallbackCameraForward
    );
}

float scatter_resolve_stored_secondary_jacobian(ReservoirSplattingReconnectionData reconnection) {
    return max(reconnection.secondaryPathJacobian, 1e-10f);
}

// ============================================================================

bool rtxdi_compare_relative_difference(float referenceDepth, float candidateDepth, float threshold) {
    return threshold <= 0.0f
        || abs(referenceDepth - candidateDepth) <= threshold * max(referenceDepth, candidateDepth);
}

bool rtxdi_is_valid_neighbor(
    vec3 referenceNormal,
    vec3 candidateNormal,
    float referenceDepth,
    float candidateDepth,
    float normalThreshold,
    float depthThreshold
) {
    return dot(candidateNormal, referenceNormal) >= normalThreshold
        && rtxdi_compare_relative_difference(referenceDepth, candidateDepth, depthThreshold);
}

bool lt_surface_matches(RAB_Surface currentSurface, RAB_Surface sourceSurface, float planeThreshold, float normalThreshold) {
    float currentDepth = rtxdi_surface_linear_depth(currentSurface, modelview_projection);
    float sourceDepth = rtxdi_surface_linear_depth(sourceSurface, modelview_projection);
    return rtxdi_is_valid_neighbor(
        currentSurface.normal,
        sourceSurface.normal,
        currentDepth,
        sourceDepth,
        normalThreshold,
        planeThreshold
    );
}

bool RTXDI_IsValidNeighbor(
    vec3 referenceNormal,
    vec3 candidateNormal,
    float referenceDepth,
    float candidateDepth,
    float normalThreshold,
    float depthThreshold
) {
    return rtxdi_is_valid_neighbor(
        referenceNormal,
        candidateNormal,
        referenceDepth,
        candidateDepth,
        normalThreshold,
        depthThreshold
    );
}

vec3 lt_surface_ray_origin(vec3 samplePos, vec3 geoNormal) {
    return samplePos + geoNormal * 0.001f;
}

struct RAB_LightSample {
    int index;
    vec3 position;
    vec3 sample_pos;
    vec3 color;
    vec3 dir;
    float solidAnglePdf;
    float weight;
};

// Legacy shader code still uses RAB_LightSample internally; Light already aliases to RAB_LightInfo
// in photonics.glsl, so do not alias RAB_LightInfo back to Light here.

RAB_LightSample lt_null_sample() {
    return RAB_LightSample(-1, vec3(0.0f), vec3(0.0f), vec3(0.0f), vec3(0.0f), 0.0f, 0.0f);
}

vec3 RAB_LightSamplePosition(RAB_LightSample lightSample)
{
    return lightSample.position;
}

bool RAB_IsAnalyticLightSample(RAB_LightSample lightSample)
{
    return lightSample.index >= 0;
}

float RAB_LightSampleSolidAnglePdf(RAB_LightSample lightSample)
{
    return lightSample.solidAnglePdf;
}

vec3 RAB_LightSampleRadiance(RAB_LightSample lightSample)
{
    return lightSample.color;
}

const float lt_pi = 3.14159265359f;
const float lt_min_roughness = 0.03f;

struct LightBrdf {
    float demodulatedDiffuse;
    vec3 specular;
};

vec3 lt_surface_f0(RAB_Surface surface) {
    return clamp(surface.material.specularF0, vec3(0.0f), vec3(1.0f));
}

vec3 lt_fresnel_schlick(float cosTheta, vec3 f0);

float lt_material_diffuse_probability_with_view(RAB_Material material, vec3 shadingNormal, vec3 viewDir) {
    float viewLengthSq = dot(viewDir, viewDir);
    if (viewLengthSq <= 1e-6f) {
        return 1.0f;
    }

    vec3 V = viewDir * inversesqrt(viewLengthSq);
    float diffuseWeight = ph_luminance(clamp(material.diffuseAlbedo, vec3(0.0f), vec3(1.0f)));
    float specularWeight = ph_luminance(
        lt_fresnel_schlick(
            clamp(dot(V, shadingNormal), 0.0f, 1.0f),
            clamp(material.specularF0, vec3(0.0f), vec3(1.0f))
        )
    );
    float sumWeights = diffuseWeight + specularWeight;
    return sumWeights < 1e-7f ? 1.0f : diffuseWeight / sumWeights;
}

float lt_surface_diffuse_probability_with_view(RAB_Surface surface, vec3 viewDir) {
    return lt_material_diffuse_probability_with_view(surface.material, surface.normal, viewDir);
}

float lt_surface_diffuse_probability(RAB_Surface surface) {
    return surface.diffuseProbability;
}

float RAB_GetSurfaceRoughness(RAB_Surface surface) {
    return surface.material.roughness;
}

float getSurfaceDiffuseProbability(RAB_Surface surface) {
    return surface.diffuseProbability;
}

vec3 lt_fresnel_schlick(float cosTheta, vec3 f0) {
    return f0 + (vec3(1.0f) - f0) * pow(1.0f - clamp(cosTheta, 0.0f, 1.0f), 5.0f);
}

float lt_distribution_ggx(float nDotH, float roughness) {
    float clampedRoughness = max(roughness, lt_min_roughness);
    float a = clampedRoughness * clampedRoughness;  // α = roughness²
    float a2 = a * a;                                // α² = roughness⁴
    float denom = nDotH * nDotH * (a2 - 1.0f) + 1.0f;
    return a2 / max(lt_pi * denom * denom, 1e-6f);
}

float lt_geometry_schlick_ggx(float nDotX, float roughness) {
    float a = max(roughness, lt_min_roughness) * max(roughness, lt_min_roughness);  // α = roughness², clamped
    float k = a * 0.5f;                                        // k = α/2 (analytic Smith-GGX)
    return nDotX / max(nDotX * (1.0f - k) + k, 1e-6f);
}

float lt_geometry_smith(float nDotV, float nDotL, float roughness) {
    return lt_geometry_schlick_ggx(nDotV, roughness) * lt_geometry_schlick_ggx(nDotL, roughness);
}

LightBrdf lt_evaluate_surface_brdf_with_view(RAB_Surface surface, vec3 lightDir, vec3 viewDir) {
    LightBrdf brdf = LightBrdf(0.0f, vec3(0.0f));

    float lightLengthSq = dot(lightDir, lightDir);
    if (lightLengthSq <= 1e-6f) {
        return brdf;
    }
    lightDir *= inversesqrt(lightLengthSq);

    float nDotL = max(dot(surface.normal, lightDir), 0.0f);
    if (nDotL <= 0.0f) {
        return brdf;
    }
    float viewLengthSq = dot(viewDir, viewDir);
    if (viewLengthSq <= 1e-6f) {
        return brdf;
    }
    viewDir *= inversesqrt(viewLengthSq);

    brdf.demodulatedDiffuse = nDotL / lt_pi;

    float nDotV = max(dot(surface.normal, viewDir), 0.0f);
    float roughness = clamp(surface.material.roughness, 0.0f, 1.0f);
    if (roughness >= lt_min_roughness && nDotV > 0.0f) {
        vec3 halfVector = normalize(viewDir + lightDir);
        float nDotH = max(dot(surface.normal, halfVector), 0.0f);
        float vDotH = max(dot(viewDir, halfVector), 0.0f);
        vec3 fresnel = lt_fresnel_schlick(vDotH, lt_surface_f0(surface));
        float distribution = lt_distribution_ggx(nDotH, roughness);
        float geometry = lt_geometry_smith(nDotV, nDotL, roughness);
        brdf.specular = distribution * geometry * fresnel / max(4.0f * nDotV, 1e-4f);
    }

    return brdf;
}

LightBrdf lt_evaluate_surface_brdf(RAB_Surface surface, vec3 lightDir) {
    return lt_evaluate_surface_brdf_with_view(surface, lightDir, surface.viewDir);
}

vec3 RAB_SurfaceEvaluateBrdfTimesNoL(RAB_Surface surface, vec3 L)
{
    if (dot(L, surface.geoNormal) <= 0.0f) {
        return vec3(0.0f);
    }

    LightBrdf brdf = lt_evaluate_surface_brdf(surface, L);
    return brdf.demodulatedDiffuse * surface.material.diffuseAlbedo + brdf.specular;
}

vec3 lt_light_sample_radiance(Light light, vec3 toLight) {
    float lightDistanceSq = dot(toLight, toLight);
    if (lightDistanceSq <= 1e-6f) {
        return vec3(0.0f);
    }

    vec3 lightDir = toLight * inversesqrt(lightDistanceSq);
    float safeDistanceSq = max(lightDistanceSq, 0.25f);
    vec3 resultColor = light.color * light.intensity / dot(vec2(1.0f, safeDistanceSq * light.falloff), light.attenuation);

    if (light.orientationSpread < lt_pi) {
        float axisAngle = acos(clamp(dot(light.emissionAxis, -lightDir), -1.0f, 1.0f));
        resultColor *= max(cos(max(axisAngle - light.orientationSpread, 0.0f)), 0.0f);
    }

    return resultColor;
}

vec3 lt_light_sample_incident_radiance(RAB_Surface surface, RAB_LightSample smple) {
    if (smple.index < 0 || ph_luminance(smple.color) <= 1e-6f) {
        return vec3(0.0f);
    }

    return smple.color;
}

float lt_light_sample_solid_angle_pdf(RAB_Surface surface, vec3 lightPosition) {
    // RTXDI reference point lights are analytic and report solidAnglePdf = 1.
    // The Minecraft local-light bridge follows that exact point-light contract.
    return 1.0f;
}

vec3 lt_surface_reflected_radiance_with_view(RAB_Surface surface, RAB_LightSample smple, vec3 viewDir) {
    vec3 incidentRadiance = lt_light_sample_incident_radiance(surface, smple);
    if (ph_luminance(incidentRadiance) <= 1e-6f) {
        return vec3(0.0f);
    }

    LightBrdf brdf = lt_evaluate_surface_brdf_with_view(surface, smple.dir, viewDir);
    return incidentRadiance * (brdf.demodulatedDiffuse * surface.material.diffuseAlbedo + brdf.specular);
}

vec3 lt_surface_reflected_radiance(RAB_Surface surface, RAB_LightSample smple) {
    return lt_surface_reflected_radiance_with_view(surface, smple, surface.viewDir);
}

float lt_surface_target_pdf(RAB_Surface surface, RAB_LightSample smple) {
    if (smple.index < 0 || smple.solidAnglePdf <= 0.0f) {
        return 0.0f;
    }

    return ph_luminance(max(lt_surface_reflected_radiance(surface, smple), vec3(0.0f))) / smple.solidAnglePdf;
}

float lt_surface_target_pdf_with_view(RAB_Surface surface, RAB_LightSample smple, vec3 viewPos) {
    if (smple.index < 0 || smple.solidAnglePdf <= 0.0f) {
        return 0.0f;
    }

    vec3 incidentRadiance = lt_light_sample_incident_radiance(surface, smple);
    if (ph_luminance(incidentRadiance) <= 1e-6f) {
        return 0.0f;
    }

    LightBrdf brdf = lt_evaluate_surface_brdf_with_view(surface, smple.dir, viewPos - lt_surface_rt_pos(surface));
    return ph_luminance(max(incidentRadiance * (brdf.demodulatedDiffuse * surface.material.diffuseAlbedo + brdf.specular), vec3(0.0f))) / smple.solidAnglePdf;
}

vec3 lt_shade_surface_light_sample(RAB_Surface surface, RAB_LightSample smple) {
    return max(lt_surface_reflected_radiance(surface, smple), vec3(0.0f));
}

vec3 lt_shade_surface_light_sample_with_view(RAB_Surface surface, RAB_LightSample smple, vec3 viewDir) {
    return max(lt_surface_reflected_radiance_with_view(surface, smple, viewDir), vec3(0.0f));
}

struct LtSplitRadiance {
    // RTXDI reference (ShadingHelpers.hlsli line 108-109):
    // diffuse  = brdf.demodulatedDiffuse * radiance = Lambert(N,-L) * radiance (NO albedo divided out)
    // specular = brdf.specular           * radiance = GGX*NdotL    * radiance (F0 baked into Fresnel;
    //            F0 demodulation happens in shade_samples.fsh via DemodulateSpecular)
    vec3 diffuse;
    vec3 specular;
};

// NRD-compatible split shading: returns diffuse-demodulated radiance and raw split specular radiance.
LtSplitRadiance lt_shade_surface_split(RAB_Surface surface, RAB_LightSample smple) {
    LtSplitRadiance result = LtSplitRadiance(vec3(0.0f), vec3(0.0f));

    vec3 incidentRadiance = lt_light_sample_incident_radiance(surface, smple);
    if (ph_luminance(incidentRadiance) <= 1e-6f) {
        return result;
    }

    vec3 viewDir = surface.viewDir;
    LightBrdf brdf = lt_evaluate_surface_brdf_with_view(surface, smple.dir, viewDir);

    result.diffuse = max(incidentRadiance * brdf.demodulatedDiffuse, vec3(0.0f));
    result.specular = max(incidentRadiance * brdf.specular, vec3(0.0f));

    return result;
}

void light_sample_compute_weight(inout RAB_LightSample smple, RAB_Surface surface) {
    smple.weight = lt_surface_target_pdf(surface, smple);
}

vec3 lt_sample_light_position_from_uv(Light light, vec2 sampleUv, vec3 shadowRayOrigin);

RAB_LightSample light_sample_new_at_position(Light light, vec3 lightPosition, RAB_Surface surface) {
    vec3 surfaceRtPos = lt_surface_rt_pos(surface);
    vec3 origin = lt_surface_ray_origin(surfaceRtPos, surface.geoNormal);
    vec3 toLight = lightPosition - surfaceRtPos;
    float lightDistanceSq = dot(toLight, toLight);
    if (lightDistanceSq <= 1e-6f) {
        return lt_null_sample();
    }

    RAB_LightSample result = RAB_LightSample(
        light.index,
        lightPosition,
        origin,
        vec3(0.0f),
        toLight * inversesqrt(lightDistanceSq),
        lt_light_sample_solid_angle_pdf(surface, lightPosition),
        0.0f
    );

    result.color = lt_light_sample_radiance(light, toLight);

    if (ph_luminance(result.color) <= 1e-6f) {
        return lt_null_sample();
    }

    light_sample_compute_weight(result, surface);
    return result;
}

RAB_LightSample light_sample_new_at(Light light, RAB_Surface surface) {
    return light_sample_new_at_position(light, light.position, surface);
}

vec3 lt_sample_light_position_from_uv(Light light, vec2 sampleUv, vec3 shadowRayOrigin) {
    // RTXDI point lights ignore UVs during sampling.
    return light.position;
}

vec2 lt_encode_light_sample_uv(Light light, vec3 lightPosition) {
    // RTXDI point lights do not carry a sampled-light UV.
    return vec2(0.0f);
}

vec3 lt_sample_light_position(Light light, vec3 shadowRayOrigin) {
    return light.position;
}

float lt_light_sample_source_pdf() {
    return 1.0f;
}

bool rtxdi_is_analytic_light_sample(RAB_LightSample lightSample) {
    // All bridged Minecraft local lights map to RTXDI analytic point lights.
    return lightSample.index >= 0;
}

RAB_LightSample light_sample_random_at(Light light, RAB_Surface surface) {
    vec3 origin = lt_surface_ray_origin(lt_surface_rt_pos(surface), surface.geoNormal);
    vec2 sampleUv = vec2(rand_next_float(), rand_next_float());
    vec3 selectedPosition = lt_sample_light_position_from_uv(light, sampleUv, origin);
    return light_sample_new_at_position(light, selectedPosition, surface);
}

RAB_LightSample light_sample_new_at(Light light, vec3 sample_pos, vec3 geoNormal, vec3 shadingNormal) {
    RAB_Surface surface = lt_make_surface(sample_pos + world_offset, geoNormal, shadingNormal);
    return light_sample_new_at(light, surface);
}

RAB_LightSample light_sample_new(Light light, vec3 sample_pos) {
    return light_sample_new_at(light, sample_pos, block_normal, normal);
}

float light_sample_target_pdf_at(int lightIndex, vec3 sample_pos, vec3 geoNormal, vec3 shadingNormal) {
    if (lightIndex < 0 || lightIndex >= ph_light_count) {
        return 0.0f;
    }

    RAB_LightSample smple = light_sample_new_at(load_light(lightIndex), sample_pos, geoNormal, shadingNormal);
    return smple.weight;
}

float light_sample_target_pdf_at_surface(int lightIndex, RAB_Surface surface) {
    if (lightIndex < 0 || lightIndex >= ph_light_count) {
        return 0.0f;
    }

    RAB_LightSample smple = light_sample_new_at(load_light(lightIndex), surface);
    return smple.weight;
}

float light_sample_target_pdf_at_surface(int lightIndex, vec3 lightWorldPosition, RAB_Surface surface) {
    if (lightIndex < 0 || lightIndex >= ph_light_count) {
        return 0.0f;
    }

    RAB_LightSample smple = light_sample_new_at_position(load_light(lightIndex), lightWorldPosition - world_offset, surface);
    return smple.weight;
}

float light_sample_target_pdf_at_surface_with_view(int lightIndex, RAB_Surface surface, vec3 viewPos) {
    if (lightIndex < 0 || lightIndex >= ph_light_count) {
        return 0.0f;
    }

    RAB_LightSample smple = light_sample_new_at(load_light(lightIndex), surface);
    return lt_surface_target_pdf_with_view(surface, smple, viewPos);
}

// RTXDI FullSample RAB_VisibilityTest.hlsli keeps the ray origin at the surface point
// and uses TMin/TMax to trim the segment along the light direction. The voxel bridge
// mirrors that contract, but still marks the target emitter cell as a successful
// terminal hit so emissive host blocks don't self-occlude.
bool lt_setup_visibility_ray(
    RAB_Surface surface,
    vec3 targetPosition,
    float offset,
    out vec3 rayOrigin,
    out vec3 rayDirection,
    out float traceMinDistance,
    out float traceMaxDistance
) {
    float rayOffset = max(offset, 0.001f);
    rayOrigin = lt_surface_rt_pos(surface);

    vec3 offsetToTarget = targetPosition - rayOrigin;
    float lightDistance = length(offsetToTarget);
    if (lightDistance <= 1e-5f) {
        rayDirection = vec3(0.0f);
        traceMinDistance = 0.0f;
        traceMaxDistance = 0.0f;
        return false;
    }

    rayDirection = offsetToTarget / lightDistance;
    traceMinDistance = rayOffset;
    traceMaxDistance = max(rayOffset, lightDistance - rayOffset * 2.0f);
    return true;
}

// When the bounded segment does hit before TMax, the hit is only accepted if it lands in
// the sampled emitter cell and matches the selected emitter host block.
bool lt_visibility_trace_hit_matches_light(Light light, vec3 targetPosition) {
    if (!ray.result_hit) {
        return false;
    }

    ivec3 targetCell = ivec3(floor(targetPosition));
    ivec3 hitCell = ivec3(floor(ray.result_position));
    bool hostBlockCompatible = light.blockId < 0 || result_block_id < 0 || light.blockId == result_block_id;

    // Old strict ownership kept for reference:
    // if (any(notEqual(hitCell, targetCell))) {
    //     return false;
    // }
    // return light.blockId < 0 || result_block_id < 0 || light.blockId == result_block_id;

    if (!hostBlockCompatible) {
        return false;
    }

    if (all(equal(hitCell, targetCell))) {
        return true;
    }

    float hitToTargetDistance = length(ray.result_position - targetPosition);
    return hitToTargetDistance <= 0.75f;
}

// RTXDI visibility succeeds when the bounded segment reaches TMax without committing a hit.
// In the voxel tracer that means the distance cap was reached and no blocker was reported.
bool lt_visibility_trace_is_unoccluded() {
    return !ray.result_hit && ray_distance_limit_reached;
}

bool lt_visibility_trace_is_unoccluded(Light light, vec3 targetPosition) {
    return lt_visibility_trace_is_unoccluded() || lt_visibility_trace_hit_matches_light(light, targetPosition);
}

// Match RTXDI's final-visibility contract: the expensive visibility query returns an RGB
// throughput term, not just a binary hit/miss. Our voxel tracer accumulates that through
// transparent voxels in result_tint_color.
vec3 lt_trace_visibility_transmittance() {
    return clamp(result_tint_color, vec3(0.0f), vec3(1.0f));
}

// Match RTXDI's conservative visibility semantics: trace a bounded shadow segment and treat
// any committed hit before TMax as occlusion. Minecraft local lights are bridged as analytic
// point lights at block centers, so the selected light's own host block must be ignored when
// the bounded segment reaches the target cell.
bool lt_trace_conservative_visibility(inout RAB_LightSample smple, RAB_Surface surface) {
    if (smple.index < 0) {
        return false;
    }

    Light light = load_light(smple.index);
    vec3 targetPosition = smple.position;
    vec3 rayOrigin;
    vec3 rayDirection;
    float traceMinDistance;
    float traceMaxDistance;
    if (!lt_setup_visibility_ray(surface, targetPosition, 0.001f, rayOrigin, rayDirection, traceMinDistance, traceMaxDistance)) {
        return false;
    }

    smple.sample_pos = rayOrigin;
    smple.position = targetPosition;
    ray.origin = smple.sample_pos;
    ray.direction = rayDirection;
    ray_target = ivec3(floor(smple.position));
    ray_ignore_block_id = light.blockId;
    ray_stop_on_target = true;
    ray_min_trace_distance = traceMinDistance;
    ray_max_trace_distance = traceMaxDistance;
    trace_ray(ray, true);
    ray_target = ivec3(-9999);
    ray_ignore_block_id = -1;
    ray_stop_on_target = false;
    ray_min_trace_distance = 0.0f;
    ray_max_trace_distance = -1.0f;
    return lt_visibility_trace_is_unoccluded(light, targetPosition);
}

// Match RTXDI's final-visibility contract: trace the bounded segment to the sampled point,
// return zero when anything blocks before TMax, and otherwise preserve RGB transmittance
// accumulated through transparent voxels along the way. For finite block emitters, a hit on
// the sampled emitter cell itself is a successful terminal event, just like in the conservative
// visibility path.
vec3 lt_trace_final_visibility_with_offset(
    inout RAB_LightSample smple,
    RAB_Surface surface,
    float rayOffset,
    out float hitDistance
) {
    hitDistance = 0.0f;
    if (smple.index < 0) {
        return vec3(0.0f);
    }

    Light light = load_light(smple.index);
    vec3 targetPosition = smple.position;
    vec3 rayOrigin;
    vec3 rayDirection;
    float traceMinDistance;
    float traceMaxDistance;
    if (!lt_setup_visibility_ray(surface, targetPosition, rayOffset, rayOrigin, rayDirection, traceMinDistance, traceMaxDistance)) {
        smple = lt_null_sample();
        return vec3(0.0f);
    }

    smple.sample_pos = rayOrigin;
    smple.position = targetPosition;

    ray.origin = smple.sample_pos;
    ray.direction = rayDirection;
    ray_target = ivec3(floor(smple.position));
    ray_ignore_block_id = light.blockId;
    ray_stop_on_target = true;
    ray_min_trace_distance = traceMinDistance;
    ray_max_trace_distance = traceMaxDistance;
    trace_ray(ray, true);
    ray_target = ivec3(-9999);
    ray_ignore_block_id = -1;
    ray_stop_on_target = false;
    ray_min_trace_distance = 0.0f;
    ray_max_trace_distance = -1.0f;

    if (!lt_visibility_trace_is_unoccluded(light, targetPosition)) {
        smple.color = vec3(0.0f);
        return vec3(0.0f);
    }

    vec3 surfaceToLight = targetPosition - lt_surface_rt_pos(surface);
    float lightDistanceSq = dot(surfaceToLight, surfaceToLight);
    if (lightDistanceSq <= 1e-6f) {
        smple = lt_null_sample();
        return vec3(0.0f);
    }

    smple.dir = surfaceToLight * inversesqrt(lightDistanceSq);
    smple.solidAnglePdf = lt_light_sample_solid_angle_pdf(surface, targetPosition);
    smple.color = lt_light_sample_radiance(light, surfaceToLight);
    light_sample_compute_weight(smple, surface);
    hitDistance = sqrt(lightDistanceSq);
    return lt_trace_visibility_transmittance();
}

float light_sample_trace_hit_surface_with_offset(inout RAB_LightSample smple, bool jitter, RAB_Surface surface, float rayOffset) {
    float hitDistance = 0.0f;
    lt_trace_final_visibility_with_offset(smple, surface, rayOffset, hitDistance);
    return hitDistance;
}

float light_sample_trace_hit_surface(inout RAB_LightSample smple, bool jitter, RAB_Surface surface) {
    return lt_trace_conservative_visibility(smple, surface) ? 1.0f : 0.0f;
}

float light_sample_trace_hit_at(inout RAB_LightSample smple, bool jitter, vec3 geoNormal, vec3 shadingNormal) {
    return light_sample_trace_hit_surface(
        smple,
        jitter,
        lt_make_surface(smple.sample_pos + world_offset, geoNormal, shadingNormal)
    );
}

float light_sample_trace_hit(inout RAB_LightSample smple, bool jitter) {
    return light_sample_trace_hit_at(smple, jitter, block_normal, normal);
}

float light_sample_encode(RAB_LightSample smple) {
    return float(smple.index);
}

struct RTXDI_DIReservoir {
    uint lightData;
    uint uvData;
    float weightSum;
    float targetPdf;
    float M;
    uint packedVisibility;
    ivec2 spatialDistance;
    uint age;
    float canonicalWeight;
    float transportAux0;
    float transportAux1;
    vec2 pixelSampleUV;
    vec2 lensSampleUV;
    uint pathSample;
};

RTXDI_DIReservoir RTXDI_EmptyDIReservoir();
bool RTXDI_IsValidDIReservoir(RTXDI_DIReservoir reservoir);

const uint RTXDI_PackedDIReservoir_VisibilityMask = 0x3ffffu;
const uint RTXDI_PackedDIReservoir_VisibilityChannelMax = 0x3fu;
const uint RTXDI_PackedDIReservoir_VisibilityChannelShift = 6u;
const uint RTXDI_PackedDIReservoir_MShift = 18u;
const uint RTXDI_PackedDIReservoir_MaxMUint = 0x3fffu;
const uint RTXDI_PackedDIReservoir_MaxM = RTXDI_PackedDIReservoir_MaxMUint;
const uint RTXDI_DIReservoir_LightValidBit = 0x80000000u;
const uint RTXDI_DIReservoir_LightIndexMask = 0x7fffffffu;

uint rtxdi_make_light_data(int lightIndex) {
    return (lightIndex < 0)
        ? 0u
        : (uint(lightIndex) & RTXDI_DIReservoir_LightIndexMask) | RTXDI_DIReservoir_LightValidBit;
}

int rtxdi_decode_light_index(uint lightData) {
    return ((lightData & RTXDI_DIReservoir_LightValidBit) == 0u)
        ? -1
        : int(lightData & RTXDI_DIReservoir_LightIndexMask);
}

uint rtxdi_pack_sample_uv(vec2 sampleUv) {
    uint packedX = uint(clamp(sampleUv.x, 0.0f, 1.0f) * 65535.0f + 0.5f);
    uint packedY = uint(clamp(sampleUv.y, 0.0f, 1.0f) * 65535.0f + 0.5f);
    return packedX | (packedY << 16u);
}

vec2 rtxdi_unpack_sample_uv(uint packedUv) {
    return vec2(float(packedUv & 0xffffu), float((packedUv >> 16u) & 0xffffu)) / 65535.0f;
}

uint lt_path_sample_proposal_family(uint pathSample);

int rtxdi_get_light_index(RTXDI_DIReservoir reservoir) {
    return rtxdi_decode_light_index(reservoir.lightData);
}

void rtxdi_set_light_index(inout RTXDI_DIReservoir reservoir, int lightIndex) {
    reservoir.lightData = rtxdi_make_light_data(lightIndex);
}

vec2 rtxdi_get_sample_uv(RTXDI_DIReservoir reservoir) {
    return rtxdi_unpack_sample_uv(reservoir.uvData);
}

void rtxdi_set_sample_uv(inout RTXDI_DIReservoir reservoir, vec2 sampleUv) {
    reservoir.uvData = rtxdi_pack_sample_uv(sampleUv);
}

Light lt_decode_reservoir_light(RTXDI_DIReservoir reservoir, bool remap) {
    int index = rtxdi_get_light_index(reservoir);
    if (index < 0) {
        return lt_invalid_light();
    }

    if (remap) {
        if (index < 0 || index >= ph_lights_array_mapping.length()) {
            index = -1;
        } else {
            index = ph_lights_array_mapping[index];
        }
        if (index < 0 || index >= ph_light_count) {
            return lt_invalid_light();
        }
    }

    if (index < 0 || index >= ph_light_count) {
        return lt_invalid_light();
    }

    return load_light(index);
}

RAB_LightInfo lt_decode_previous_reservoir_light(RTXDI_DIReservoir reservoir) {
    int lightIndex = rtxdi_get_light_index(reservoir);
    if (lightIndex < 0) {
        return lt_invalid_light();
    }

    return load_previous_light(lightIndex);
}

RAB_LightSample light_sample_decode(RTXDI_DIReservoir reservoir, RAB_Surface surface, bool remap) {
    Light light = lt_decode_reservoir_light(reservoir, remap);
    if (light.index < 0) {
        return lt_null_sample();
    }

    vec3 lightPosition = lt_sample_light_position_from_uv(light, rtxdi_get_sample_uv(reservoir), lt_surface_ray_origin(lt_surface_rt_pos(surface), surface.geoNormal));
    return light_sample_new_at_position(light, lightPosition, surface);
}

RAB_LightSample light_sample_decode_previous(RTXDI_DIReservoir reservoir, RAB_Surface surface) {
    RAB_LightInfo light = lt_decode_previous_reservoir_light(reservoir);
    if (light.index < 0) {
        return lt_null_sample();
    }

    vec3 lightPosition = lt_sample_light_position_from_uv(light, rtxdi_get_sample_uv(reservoir), lt_surface_ray_origin(lt_surface_rt_pos(surface), surface.geoNormal));
    return light_sample_new_at_position(light, lightPosition, surface);
}

int lt_translate_reservoir_light_index_between_frames(int lightIndex, bool reservoirPreviousFrame, bool targetPreviousFrame) {
    if (lightIndex < 0) {
        return -1;
    }

    if (reservoirPreviousFrame == targetPreviousFrame) {
        return lightIndex;
    }

    return RAB_TranslateLightIndex(lightIndex, !reservoirPreviousFrame);
}

RTXDI_DIReservoir lt_translate_reservoir_between_frames(RTXDI_DIReservoir reservoir, bool reservoirPreviousFrame, bool targetPreviousFrame) {
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        return reservoir;
    }

    int translatedLightIndex = lt_translate_reservoir_light_index_between_frames(
        rtxdi_get_light_index(reservoir),
        reservoirPreviousFrame,
        targetPreviousFrame
    );

    if (translatedLightIndex < 0) {
        return RTXDI_EmptyDIReservoir();
    }

    rtxdi_set_light_index(reservoir, translatedLightIndex);
    return reservoir;
}

RAB_LightSample lt_decode_reservoir_sample_for_frame(
    RTXDI_DIReservoir reservoir,
    RAB_Surface surface,
    bool reservoirPreviousFrame,
    bool targetPreviousFrame)
{
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        return lt_null_sample();
    }

    int translatedLightIndex = lt_translate_reservoir_light_index_between_frames(
        rtxdi_get_light_index(reservoir),
        reservoirPreviousFrame,
        targetPreviousFrame
    );
    if (translatedLightIndex < 0) {
        return lt_null_sample();
    }

    RAB_LightInfo light = targetPreviousFrame
        ? load_previous_light(translatedLightIndex)
        : load_light(translatedLightIndex);
    if (light.index < 0) {
        return lt_null_sample();
    }

    vec3 lightPosition = lt_sample_light_position_from_uv(light, rtxdi_get_sample_uv(reservoir), lt_surface_ray_origin(lt_surface_rt_pos(surface), surface.geoNormal));
    return light_sample_new_at_position(light, lightPosition, surface);
}

RAB_LightSample light_sample_decode_at(float value, vec2 sampleUv, RAB_Surface surface, bool remap) {
    RTXDI_DIReservoir replayReservoir;
    replayReservoir.lightData = 0u;
    replayReservoir.uvData = 0u;
    replayReservoir.weightSum = 0.0;
    replayReservoir.targetPdf = 0.0;
    replayReservoir.M = 0.0;
    replayReservoir.packedVisibility = 0u;
    replayReservoir.age = 0u;
    replayReservoir.spatialDistance = ivec2(0);
    replayReservoir.canonicalWeight = 0.0;
    replayReservoir.transportAux0 = 0.0;
    replayReservoir.transportAux1 = 0.0;
    replayReservoir.pixelSampleUV = vec2(0.5f);
    replayReservoir.lensSampleUV = vec2(0.5f);
    replayReservoir.pathSample = 2u;
    rtxdi_set_light_index(replayReservoir, int(round(value)));
    rtxdi_set_sample_uv(replayReservoir, sampleUv);
    return light_sample_decode(replayReservoir, surface, remap);
}

RAB_LightSample light_sample_decode_at(float value, RAB_Surface surface, bool remap) {
    return light_sample_decode_at(value, vec2(0.0f), surface, remap);
}

bool lt_pick_uniform_light(out int lightIndex, out float lightPdf) {
    lightIndex = -1;
    lightPdf = 0.0f;

    if (ph_light_count <= 0) {
        return false;
    }

    lightIndex = rand_next_int(0, ph_light_count);
    lightPdf = 1.0f / float(max(ph_light_count, 1));
    return lightIndex >= 0 && lightIndex < ph_light_count;
}

bool lt_pick_power_light(out int lightIndex, out float lightPdf) {
    lightIndex = -1;
    lightPdf = 0.0f;

    if (ph_light_count <= 0) {
        return false;
    }

    float totalWeight = ph_global_light_cdf_data[ph_light_count - 1];
    if (totalWeight <= 1e-6f) {
        return lt_pick_uniform_light(lightIndex, lightPdf);
    }

    float draw = rand_next_float() * totalWeight;
    int low = 0;
    int high = ph_light_count - 1;
    while (low < high) {
        int mid = (low + high) >> 1;
        if (ph_global_light_cdf_data[mid] < draw) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }

    float prevCdf = low > 0 ? ph_global_light_cdf_data[low - 1] : 0.0f;
    float weight = ph_global_light_cdf_data[low] - prevCdf;
    if (weight <= 1e-6f) {
        return lt_pick_uniform_light(lightIndex, lightPdf);
    }

    lightIndex = low;
    lightPdf = max(weight / totalWeight, 1e-6f);
    return true;
}

// Primary — matches RTXDI naming (RTXDI_DIReservoir.hlsli: RTXDI_EmptyDIReservoir)
RTXDI_DIReservoir RTXDI_EmptyDIReservoir() {
    RTXDI_DIReservoir r;
    r.lightData = 0u;
    r.uvData = 0u;
    r.weightSum = 0.0;
    r.targetPdf = 0.0;
    r.M = 0.0;
    r.packedVisibility = 0u;
    r.age = 0u;
    r.spatialDistance = ivec2(0);
    r.canonicalWeight = 0.0;
    r.transportAux0 = 0.0;
    r.transportAux1 = 0.0;
    r.pixelSampleUV = vec2(-1.0f);
    r.lensSampleUV = vec2(-1.0f);
    r.pathSample = 2u;
    return r;
}
// Backward-compat alias
RTXDI_DIReservoir rtxdi_empty_reservoir() { return RTXDI_EmptyDIReservoir(); }

// Primary — matches RTXDI semantics: only checks light index validity (RTXDI_DIReservoir.hlsli: lightData != 0)
bool RTXDI_IsValidDIReservoir(RTXDI_DIReservoir reservoir) {
    return reservoir.lightData != 0u;
}

vec2 scatter_resolve_reservoir_subpixel(RTXDI_DIReservoir reservoir, ivec2 pixelPosition);
ivec2 lt_area_pixel_from_sample_uv(vec2 pixelSampleUV);

vec2 lt_area_default_pixel_sample(ivec2 pixelPosition) {
    return (vec2(pixelPosition) + vec2(0.5f)) / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
}

vec2 lt_area_random_pixel_sample(inout RTXDI_RandomSamplerState rng, ivec2 pixelPosition) {
    vec2 jitter = vec2(lt_next_random(rng), lt_next_random(rng));
    return (vec2(pixelPosition) + jitter) / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
}

vec2 lt_area_default_lens_sample() {
    return vec2(0.5f);
}

vec2 lt_area_sample_lens_sample(inout RTXDI_RandomSamplerState rng) {
    return lt_area_default_lens_sample();
}

const uint LT_PATH_SAMPLE_MASK = 0xFFu;
const uint LT_PATH_SAMPLE_PROPOSAL_SHIFT = 8u;
const uint LT_PATH_SAMPLE_PROPOSAL_MASK = 0xFu;
const uint LT_PROPOSAL_FAMILY_UNKNOWN = 0u;
const uint LT_PROPOSAL_FAMILY_UNIFORM = 1u;
const uint LT_PROPOSAL_FAMILY_POWER_RIS = 2u;
const uint LT_PROPOSAL_FAMILY_REGIR_RIS = 3u;
const uint LT_PROPOSAL_FAMILY_REGIR_FALLBACK = 4u;
const uint LT_PROPOSAL_FAMILY_BRDF = 5u;

uint lt_make_path_sample(uint basePathSample, uint proposalFamily) {
    return (basePathSample & LT_PATH_SAMPLE_MASK)
        | ((proposalFamily & LT_PATH_SAMPLE_PROPOSAL_MASK) << LT_PATH_SAMPLE_PROPOSAL_SHIFT);
}

uint lt_path_sample_base(uint pathSample) {
    return pathSample & LT_PATH_SAMPLE_MASK;
}

uint lt_path_sample_proposal_family(uint pathSample) {
    return (pathSample >> LT_PATH_SAMPLE_PROPOSAL_SHIFT) & LT_PATH_SAMPLE_PROPOSAL_MASK;
}

bool lt_area_has_valid_domain(RTXDI_DIReservoir reservoir) {
    return all(greaterThanEqual(reservoir.pixelSampleUV, vec2(0.0f)))
        && all(greaterThanEqual(reservoir.lensSampleUV, vec2(0.0f)));
}

void lt_area_set_domain_samples(inout RTXDI_DIReservoir reservoir, vec2 pixelSampleUV, vec2 lensSampleUV, uint pathSample) {
    reservoir.pixelSampleUV = clamp(pixelSampleUV, vec2(0.0f), vec2(1.0f));
    reservoir.lensSampleUV = clamp(lensSampleUV, vec2(0.0f), vec2(1.0f));
    reservoir.pathSample = pathSample;
}

void lt_area_finalize_candidate(inout RTXDI_DIReservoir reservoir, ivec2 pixelPosition, uint pathSample) {
    if (!lt_area_has_valid_domain(reservoir)) {
        lt_area_set_domain_samples(reservoir, lt_area_default_pixel_sample(pixelPosition), lt_area_default_lens_sample(), pathSample);
    } else {
        reservoir.pathSample = pathSample;
    }
}

float lt_area_effective_target_pdf(
    RTXDI_DIReservoir reservoir,
    RAB_Surface surface,
    ivec2 referencePixelPosition,
    bool reservoirPreviousFrame,
    bool targetPreviousFrame)
{
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        return 0.0f;
    }

    RAB_LightSample smple = lt_decode_reservoir_sample_for_frame(
        reservoir,
        surface,
        reservoirPreviousFrame,
        targetPreviousFrame
    );
    if (smple.index < 0 || smple.solidAnglePdf <= 0.0f) {
        return 0.0f;
    }

    float shiftedTarget = lt_surface_target_pdf(surface, smple);
    vec2 referencePixelSample = lt_area_default_pixel_sample(referencePixelPosition);
    float pixelJacobian = lt_area_has_valid_domain(reservoir)
        ? max(0.25f, 1.0f - length((reservoir.pixelSampleUV - referencePixelSample) * vec2(viewWidth, viewHeight)) / 4.0f)
        : 1.0f;
    float lensJacobian = lt_area_has_valid_domain(reservoir)
        ? max(0.25f, 1.0f - length(reservoir.lensSampleUV - lt_area_default_lens_sample()) * 2.0f)
        : 1.0f;
    return shiftedTarget * pixelJacobian * lensJacobian;
}

float lt_area_effective_target_pdf(
    RTXDI_DIReservoir reservoir,
    RAB_Surface surface)
{
    return lt_area_effective_target_pdf(
        reservoir,
        surface,
        lt_fragment_pixel_pos(),
        false,
        false
    );
}

vec2 lt_area_clamp_pixel_sample_uv(vec2 pixelSampleUV) {
    vec2 pixelSize = vec2(1.0f / max(viewWidth, 1.0), 1.0f / max(viewHeight, 1.0));
    return clamp(pixelSampleUV, pixelSize * 0.5f, vec2(1.0f) - pixelSize * 0.5f);
}

vec2 lt_area_pixel_sample_from_subpixel(ivec2 pixelPosition, vec2 subPixel) {
    return lt_area_clamp_pixel_sample_uv(
        (vec2(pixelPosition) + clamp(subPixel, vec2(0.0f), vec2(1.0f))) / vec2(viewWidth, viewHeight)
    );
}

bool lt_area_try_shift_temporal_domain(
    inout RTXDI_DIReservoir reservoir,
    ivec2 sourcePixel,
    ivec2 targetPixel,
    vec2 previousFloatingPixel)
{
    const float overlapEpsilon = 1e-4f;
    vec2 prevSubPixel = scatter_resolve_reservoir_subpixel(reservoir, sourcePixel);
    vec2 shiftedSubPixel = (vec2(sourcePixel) + prevSubPixel) - previousFloatingPixel;
    if (any(lessThan(shiftedSubPixel, vec2(-overlapEpsilon)))
        || any(greaterThan(shiftedSubPixel, vec2(1.0f + overlapEpsilon))))
    {
        return false;
    }

    shiftedSubPixel = clamp(shiftedSubPixel, vec2(0.0f), vec2(1.0f - 1e-5f));

    vec2 lensSampleUV = lt_area_has_valid_domain(reservoir)
        ? clamp(reservoir.lensSampleUV, vec2(0.0f), vec2(1.0f))
        : lt_area_default_lens_sample();
    lt_area_set_domain_samples(
        reservoir,
        lt_area_pixel_sample_from_subpixel(targetPixel, shiftedSubPixel),
        lensSampleUV,
        reservoir.pathSample
    );
    return lt_area_pixel_from_sample_uv(reservoir.pixelSampleUV) == targetPixel;
}

ivec2 lt_area_pixel_from_sample_uv(vec2 pixelSampleUV) {
    vec2 scaled = lt_area_clamp_pixel_sample_uv(pixelSampleUV) * vec2(viewWidth, viewHeight) - vec2(0.5f);
    return clamp(ivec2(floor(scaled)), ivec2(0), ivec2(int(viewWidth) - 1, int(viewHeight) - 1));
}

vec2 lt_area_jitter_domain_sample(vec2 sampleUv, vec2 jitter, vec2 scale) {
    return clamp(sampleUv + jitter * scale, vec2(0.0f), vec2(1.0f));
}

void lt_area_seed_domain_samples(inout RTXDI_DIReservoir reservoir, ivec2 pixelPosition, uint pathSample) {
    lt_area_set_domain_samples(
        reservoir,
        lt_area_default_pixel_sample(pixelPosition),
        lt_area_default_lens_sample(),
        pathSample
    );
}

void lt_area_seed_domain_samples(
    inout RTXDI_DIReservoir reservoir,
    inout RTXDI_RandomSamplerState rng,
    ivec2 pixelPosition,
    uint pathSample)
{
    lt_area_set_domain_samples(
        reservoir,
        lt_area_random_pixel_sample(rng, pixelPosition),
        lt_area_sample_lens_sample(rng),
        pathSample
    );
}

float lt_area_confidence_from_samples(float sampleCount) {
    // Reference: Reservoir.slang:75 — PathReservoir::confidenceCap = 20
    return clamp(sampleCount, 0.0f, 20.0f);
}

float lt_scatter_bilinear_weight(vec2 fracOffset, int dx, int dy) {
    return ((dx == 0) ? (1.0f - fracOffset.x) : fracOffset.x)
         * ((dy == 0) ? (1.0f - fracOffset.y) : fracOffset.y);
}

vec2 lt_temporal_previous_pixel_center(ivec2 pixelPosition) {
    vec4 motionSample = texelFetch(radiosity_motion, pixelPosition, 0);
    if (motionSample.w <= 0.0f) {
        return vec2(pixelPosition) + vec2(0.5f);
    }

    // ph_compute_temporal_motion() already stores pixel-space motion as:
    //   previousPixel - currentPixelCenter
    // so temporal reuse must add that delta directly instead of scaling by the
    // viewport again or flipping the sign.
    return vec2(pixelPosition) + vec2(0.5f) + motionSample.xy;
}

ivec2 lt_temporal_previous_checkerboard_pixel(ivec2 pixelPosition, int previousCheckerboardField) {
    ivec2 previousPixel = pixelPosition;
    RTXDI_ActivateCheckerboardPixel(previousPixel, true, previousCheckerboardField);
    return previousPixel;
}

float lt_scatter_compute_history_confidence(ivec2 pixelPosition, RAB_Surface currentSurface, RTXDI_DIReservoir reservoir) {
    float currentConfidence = lt_area_confidence_from_samples(reservoir.M);
    if (!RAB_IsSurfaceValid(currentSurface)) {
        return currentConfidence;
    }

    vec2 backprojF = lt_temporal_previous_pixel_center(pixelPosition);
    ivec2 basePixel = ivec2(floor(backprojF));
    vec2 fracOffset = backprojF - vec2(basePixel);
    int previousCheckerboardField = lt_previous_checkerboard_field(int(ph_restir_active_checkerboard_field));

    float bilinearConfidence = 0.0f;
    float totalWeight = 0.0f;
    for (int dy = 0; dy <= 1; ++dy) {
        for (int dx = 0; dx <= 1; ++dx) {
            ivec2 samplePixel = basePixel + ivec2(dx, dy);
            if (!lt_is_viewport_uv_in_bounds(samplePixel)) {
                continue;
            }

            ivec2 previousSamplePixel = lt_temporal_previous_checkerboard_pixel(samplePixel, previousCheckerboardField);
            if (!lt_is_viewport_uv_in_bounds(previousSamplePixel)) {
                continue;
            }

            ScatterReconnectionData neighborReconn = scatter_load_prev_reconnection(previousSamplePixel);
            float weight = lt_scatter_bilinear_weight(fracOffset, dx, dy);
            if (weight <= 0.0f) {
                continue;
            }

            if (!scatter_reconnection_matches_surface(neighborReconn, pixelPosition, currentSurface)) {
                continue;
            }

            bilinearConfidence += weight * RTXDI_LoadPreviousDIReservoir(
                lt_build_restir_di_parameters().reservoirBufferParams,
                uvec2(previousSamplePixel)
            ).M;
            totalWeight += weight;
        }
    }

    float prevConfidence = (totalWeight > 0.0f) ? (bilinearConfidence / totalWeight) : 0.0f;
    return min(max(currentConfidence, prevConfidence + 1.0f), 20.0f);
}

bool lt_area_is_surface_neighbor_valid(RAB_Surface currentSurface, RAB_Surface prevSurface) {
    if (!RAB_IsSurfaceValid(currentSurface) || !RAB_IsSurfaceValid(prevSurface)) {
        return false;
    }

    return RTXDI_IsValidNeighbor(
        RAB_GetSurfaceNormal(currentSurface), RAB_GetSurfaceNormal(prevSurface),
        RAB_GetSurfaceLinearDepth(currentSurface), RAB_GetSurfaceLinearDepth(prevSurface),
        ph_restir_normal_threshold, ph_restir_depth_threshold);
}

bool lt_area_is_temporal_neighbor_valid(
    RAB_Surface currentSurface,
    RAB_Surface prevSurface,
    ScatterReconnectionData prevReconnection,
    ivec2 currentPixel)
{
    return lt_area_is_surface_neighbor_valid(currentSurface, prevSurface);
}

ivec2 lt_area_reproject_pixel(ivec2 pixelPosition) {
    ivec2 prevPixel = ivec2(floor(lt_temporal_previous_pixel_center(pixelPosition)));
    return clamp(prevPixel, ivec2(0), ivec2(int(viewWidth) - 1, int(viewHeight) - 1));
}

// Stricter photonics validity check — also requires M > 0 and weightSum > 0.
// Kept separate from RTXDI_IsValidDIReservoir for callers that need it.
bool rtxdi_is_valid_reservoir(RTXDI_DIReservoir reservoir) {
    return reservoir.lightData != 0u && reservoir.M > 0.0f && reservoir.weightSum > 0.0f;
}

// Accessor wrappers — naming parity with RTXDI's RTXDI_DIReservoir.hlsli accessor functions.
int RTXDI_GetDIReservoirLightIndex(RTXDI_DIReservoir reservoir) {
    return rtxdi_get_light_index(reservoir);
}

vec2 RTXDI_GetDIReservoirSampleUV(RTXDI_DIReservoir reservoir) {
    return rtxdi_get_sample_uv(reservoir);
}

float RTXDI_GetDIReservoirInvPdf(RTXDI_DIReservoir reservoir) {
    return reservoir.weightSum;
}

// A surface is valid if it has a non-zero-length normal (sky/empty pixels have zero normals).
// Matches RAB_IsSurfaceValid semantics from RTXDI (TemporalResampling.hlsli line 94).
bool lt_is_valid_surface(RAB_Surface surface) {
    return surface.viewDepth != BACKGROUND_DEPTH;
}

void rtxdi_unpack_reservoir_at_surface(inout RTXDI_DIReservoir reservoir, vec4 color, vec4 sampleData, vec4 meta, RAB_Surface surface, bool remap);
vec3 rtxdi_unpack_visibility(uint packedVisibility);
uint rtxdi_pack_visibility(vec3 visibility);

struct RTXDI_RuntimeParameters
{
    uint neighborOffsetMask;
    uint activeCheckerboardField;
    uint frameIndex;
    uint pad2;
};

struct RTXDI_ReservoirBufferParameters
{
    uint reservoirBlockRowPitch;
    uint reservoirArrayPitch;
    uint pad1;
    uint pad2;
};

struct RTXDI_BoilingFilterParameters
{
    uint enableBoilingFilter;
    float boilingFilterStrength;
    uint pad1;
    uint pad2;
};

struct RTXDI_DIInitialSamplingParameters
{
    uint numLocalLightSamples;
    uint numInfiniteLightSamples;
    uint numEnvironmentSamples;
    uint numBrdfSamples;
    float brdfCutoff;
    float brdfRayMinT;
    uint localLightSamplingMode;
    uint enableInitialVisibility;
    uint environmentMapImportanceSampling;
    uint pad1;
    uint pad2;
    uint pad3;
};

struct RTXDI_DISpatialResamplingParameters
{
    uint numSamples;
    uint numDisocclusionBoostSamples;
    float samplingRadius;
    uint biasCorrectionMode;
    float depthThreshold;
    float normalThreshold;
    uint targetHistoryLength;
    uint enableMaterialSimilarityTest;
    uint discountNaiveSamples;
    uint pad1;
    uint pad2;
    uint pad3;
};

struct RTXDI_ShadingParameters
{
    uint enableFinalVisibility;
    uint reuseFinalVisibility;
    uint finalVisibilityMaxAge;
    float finalVisibilityMaxDistance;
    uint enableDenoiserInputPacking;
    uint pad1;
    uint pad2;
    uint pad3;
};

struct RTXDI_VisibilityReuseParameters
{
    uint maxAge;
    float maxDistance;
};

struct RTXDI_DIBufferIndices
{
    uint initialSamplingOutputBufferIndex;
    uint spatialResamplingInputBufferIndex;
    uint spatialResamplingOutputBufferIndex;
    uint shadingInputBufferIndex;
    uint pad1;
    uint pad2;
    uint pad3;
    uint pad4;
};

struct RTXDI_Parameters
{
    RTXDI_ReservoirBufferParameters reservoirBufferParams;
    RTXDI_DIBufferIndices bufferIndices;
    RTXDI_DIInitialSamplingParameters initialSamplingParams;
    RTXDI_BoilingFilterParameters boilingFilterParams;
    RTXDI_DISpatialResamplingParameters spatialResamplingParams;
    RTXDI_ShadingParameters shadingParams;
};

const uint RTXDI_DI_BUFFER_INDEX_INITIAL_SAMPLING_OUTPUT = 0u;
const uint RTXDI_DI_BUFFER_INDEX_TEMPORAL_RESAMPLING_OUTPUT = 1u;
const uint RTXDI_DI_BUFFER_INDEX_SPATIAL_RESAMPLING_OUTPUT = 2u;
const uint RTXDI_DI_BUFFER_INDEX_SHADING_INPUT = 3u;

RTXDI_DIBufferIndices lt_build_di_buffer_indices()
{
    RTXDI_DIBufferIndices bufferIndices;
    bufferIndices.initialSamplingOutputBufferIndex = RTXDI_DI_BUFFER_INDEX_INITIAL_SAMPLING_OUTPUT;

    bool enableTemporalReuse = ph_debug_enable_direct_temporal_reuse >= 0.5f;
    uint temporalOutputBufferIndex = enableTemporalReuse
        ? RTXDI_DI_BUFFER_INDEX_TEMPORAL_RESAMPLING_OUTPUT
        : RTXDI_DI_BUFFER_INDEX_INITIAL_SAMPLING_OUTPUT;
    bool enableSpatialReuse = ph_debug_enable_direct_spatial_reuse >= 0.5f;

    bufferIndices.spatialResamplingInputBufferIndex = temporalOutputBufferIndex;
    bufferIndices.spatialResamplingOutputBufferIndex = enableSpatialReuse
        ? RTXDI_DI_BUFFER_INDEX_SPATIAL_RESAMPLING_OUTPUT
        : temporalOutputBufferIndex;
    bufferIndices.shadingInputBufferIndex = bufferIndices.spatialResamplingOutputBufferIndex;
    bufferIndices.pad1 = 0u;
    bufferIndices.pad2 = 0u;
    bufferIndices.pad3 = 0u;
    bufferIndices.pad4 = 0u;
    return bufferIndices;
}

RTXDI_DIBufferIndices RTXDI_GetDIBufferIndices()
{
    return lt_build_di_buffer_indices();
}

uint lt_get_final_shading_input_buffer_index()
{
    return lt_build_di_buffer_indices().shadingInputBufferIndex;
}

RTXDI_RuntimeParameters lt_build_runtime_parameters()
{
    RTXDI_RuntimeParameters params;
    params.neighborOffsetMask = uint(lt_neighbor_offset_count - 1);
    params.activeCheckerboardField = uint(ph_restir_active_checkerboard_field);
    params.frameIndex = uint(max(ph_restir_frame_index, 0));
    params.pad2 = 0u;
    return params;
}

RTXDI_ReservoirBufferParameters lt_build_reservoir_buffer_parameters()
{
    RTXDI_ReservoirBufferParameters reservoirParams;
    reservoirParams.reservoirBlockRowPitch = 0u;
    reservoirParams.reservoirArrayPitch = 0u;
    reservoirParams.pad1 = 0u;
    reservoirParams.pad2 = 0u;
    return reservoirParams;
}

RTXDI_DIInitialSamplingParameters lt_build_di_initial_sampling_parameters()
{
    RTXDI_DIInitialSamplingParameters initialSamplingParams;
    initialSamplingParams.numLocalLightSamples = uint((ph_restir_initial_num_local_samples > 0.0)
        ? max(int(ph_restir_initial_num_local_samples), 1)
        : max(PH_LIGHTTREE_INITIAL_SAMPLES, 1));
    initialSamplingParams.numInfiniteLightSamples = 0u;
    initialSamplingParams.numEnvironmentSamples = 0u;
    initialSamplingParams.numBrdfSamples = 0u;
    initialSamplingParams.brdfCutoff = (ph_restir_initial_brdf_cutoff > 0.0) ? ph_restir_initial_brdf_cutoff : 0.0001f;
    initialSamplingParams.brdfRayMinT = 0.001f;

    int requestedLocalLightSamplingMode = (ph_restir_local_light_sampling_mode <= 0.0)
        ? RTXDI_LOCAL_LIGHT_SAMPLING_UNIFORM
        : int(round(ph_restir_local_light_sampling_mode));

    initialSamplingParams.localLightSamplingMode = uint(requestedLocalLightSamplingMode);
    initialSamplingParams.enableInitialVisibility = (ph_restir_initial_enable_visibility > -0.5f) ? 1u : 0u;
    initialSamplingParams.environmentMapImportanceSampling = 0u;
    initialSamplingParams.pad1 = 0u;
    initialSamplingParams.pad2 = 0u;
    initialSamplingParams.pad3 = 0u;
    return initialSamplingParams;
}

RTXDI_DISpatialResamplingParameters lt_build_di_spatial_resampling_parameters()
{
    RTXDI_DISpatialResamplingParameters spatialResamplingParams;
    spatialResamplingParams.numSamples = uint((ph_restir_spatial_sample_count > 0.0)
        ? max(int(floor(ph_restir_spatial_sample_count)), 1)
        : max(PH_LIGHTTREE_SPATIAL_REUSE_SAMPLES, 1));
    spatialResamplingParams.numDisocclusionBoostSamples = uint((ph_restir_spatial_boost_samples > 0.0)
        ? max(int(floor(ph_restir_spatial_boost_samples)), int(spatialResamplingParams.numSamples))
        : 8);
    spatialResamplingParams.samplingRadius = ph_restir_spatial_radius > 0.0
        ? max(ph_restir_spatial_radius, 1.0f)
        : max(PH_LIGHTTREE_SPATIAL_REUSE_RADIUS, 1.0f);

    // Player/runtime default is pairwise MIS for spatial reuse, matching the RTXDI reference's
    // dedicated spatial resampling path. The explicit override still accepts Off/Basic/Pairwise/Ray-traced.
    if (ph_restir_spatial_bias_mode < -0.5f) {
        spatialResamplingParams.biasCorrectionMode = uint(RTXDI_BIAS_CORRECTION_PAIRWISE);
    } else {
        int resolvedMode = int(round(ph_restir_spatial_bias_mode));
        spatialResamplingParams.biasCorrectionMode = uint(
            (resolvedMode == RTXDI_BIAS_CORRECTION_OFF
                || resolvedMode == RTXDI_BIAS_CORRECTION_BASIC
                || resolvedMode == RTXDI_BIAS_CORRECTION_PAIRWISE
                || resolvedMode == RTXDI_BIAS_CORRECTION_RAY_TRACED)
                ? resolvedMode
                : RTXDI_BIAS_CORRECTION_BASIC
        );
    }

    spatialResamplingParams.depthThreshold = ph_restir_spatial_depth_threshold > 0.0
        ? ph_restir_spatial_depth_threshold
        : lt_depth_threshold;
    spatialResamplingParams.normalThreshold = ph_restir_spatial_normal_threshold > 0.0
        ? ph_restir_spatial_normal_threshold
        : lt_surface_normal_threshold;
    spatialResamplingParams.targetHistoryLength = uint(max(int(floor(ph_restir_spatial_target_history)), 0));
    spatialResamplingParams.enableMaterialSimilarityTest = (ph_restir_spatial_material_test < -1.5) ? 0u : 1u;
    spatialResamplingParams.discountNaiveSamples = (ph_restir_spatial_discount_naive < -1.5) ? 0u : 1u;
    spatialResamplingParams.pad1 = 0u;
    spatialResamplingParams.pad2 = 0u;
    spatialResamplingParams.pad3 = 0u;
    return spatialResamplingParams;
}

RTXDI_BoilingFilterParameters lt_build_di_boiling_filter_parameters()
{
    RTXDI_BoilingFilterParameters boilingFilterParams;
    boilingFilterParams.enableBoilingFilter = 1u;
    boilingFilterParams.boilingFilterStrength = 0.2f;
    boilingFilterParams.pad1 = 0u;
    boilingFilterParams.pad2 = 0u;
    return boilingFilterParams;
}

RTXDI_ShadingParameters lt_build_shading_parameters()
{
    RTXDI_ShadingParameters shadingParams;
    shadingParams.enableFinalVisibility = (ph_restir_enable_final_visibility >= 0.5f) ? 1u : 0u;
    shadingParams.reuseFinalVisibility = (ph_restir_reuse_final_visibility >= 0.5f) ? 1u : 0u;
    shadingParams.finalVisibilityMaxAge = uint((ph_restir_visibility_max_age > 0.0f) ? ph_restir_visibility_max_age : lt_visibility_reuse_max_age);
    shadingParams.finalVisibilityMaxDistance = (ph_restir_visibility_max_distance > 0.0f) ? ph_restir_visibility_max_distance : lt_visibility_reuse_max_distance;
    shadingParams.enableDenoiserInputPacking = (ph_restir_enable_denoiser_packing >= 0.5f) ? 1u : 0u;
    shadingParams.pad1 = 0u;
    shadingParams.pad2 = 0u;
    shadingParams.pad3 = 0u;
    return shadingParams;
}

RTXDI_VisibilityReuseParameters lt_build_visibility_reuse_parameters()
{
    RTXDI_VisibilityReuseParameters visibilityReuseParams;
    visibilityReuseParams.maxAge = uint((ph_restir_visibility_max_age > 0.0f) ? ph_restir_visibility_max_age : lt_visibility_reuse_max_age);
    visibilityReuseParams.maxDistance = (ph_restir_visibility_max_distance > 0.0f) ? ph_restir_visibility_max_distance : lt_visibility_reuse_max_distance;
    return visibilityReuseParams;
}

RTXDI_Parameters lt_build_restir_di_parameters()
{
    RTXDI_Parameters restirDI;
    restirDI.reservoirBufferParams = lt_build_reservoir_buffer_parameters();
    restirDI.bufferIndices = lt_build_di_buffer_indices();
    restirDI.initialSamplingParams = lt_build_di_initial_sampling_parameters();
    restirDI.boilingFilterParams = lt_build_di_boiling_filter_parameters();
    restirDI.spatialResamplingParams = lt_build_di_spatial_resampling_parameters();
    restirDI.shadingParams = lt_build_shading_parameters();
    return restirDI;
}

RAB_Surface RAB_EmptySurface()
{
    return lt_empty_surface();
}

bool RAB_IsSurfaceValid(RAB_Surface surface)
{
    return lt_is_valid_surface(surface);
}

vec3 RAB_GetSurfaceNormal(RAB_Surface surface)
{
    return surface.normal;
}

vec3 RAB_GetSurfaceWorldPos(RAB_Surface surface)
{
    return surface.worldPos;
}

vec3 RAB_GetSurfaceGeoNormal(RAB_Surface surface)
{
    return surface.geoNormal;
}

vec3 RAB_GetSurfaceViewDir(RAB_Surface surface)
{
    return surface.viewDir;
}

float RAB_GetSurfaceLinearDepth(RAB_Surface surface)
{
    return surface.viewDepth;
}

RAB_Material RAB_GetMaterial(RAB_Surface surface)
{
    return surface.material;
}

RAB_Material RAB_GetGBufferMaterial(ivec2 pixelPosition, bool previousFrame)
{
    if (!lt_is_viewport_uv_in_bounds(pixelPosition))
    {
        return RAB_EmptyMaterial();
    }

    if (previousFrame)
    {
        return lt_make_material(
            texelFetch(prev_radiosity_material, pixelPosition, 0),
            clamp(texelFetch(prev_radiosity_albedo, pixelPosition, 0).rgb, vec3(0.04f), vec3(1.0f))
        );
    }

    return lt_make_material(
        texelFetch(radiosity_material, pixelPosition, 0),
        clamp(texelFetch(radiosity_albedo, pixelPosition, 0).rgb, vec3(0.04f), vec3(1.0f))
    );
}

RAB_Surface RAB_GetGBufferSurface(ivec2 pixelPosition, bool previousFrame)
{
    if (!lt_is_viewport_uv_in_bounds(pixelPosition))
    {
        return RAB_EmptySurface();
    }

    return previousFrame
        ? lt_load_previous_surface(pixelPosition)
        : lt_load_surface(pixelPosition);
}

int RAB_TranslateLightIndex(int lightIndex, bool previousFrame)
{
    if (lightIndex < 0)
    {
        return -1;
    }

    if (previousFrame)
    {
        if (lightIndex >= ph_light_reverse_mapping.length())
        {
            return -1;
        }

        return ph_light_reverse_mapping[lightIndex];
    }

    if (lightIndex >= ph_lights_array_mapping.length())
    {
        return -1;
    }

    int mappedLightIndex = ph_lights_array_mapping[lightIndex];
    if (mappedLightIndex < 0 || mappedLightIndex >= ph_light_count)
    {
        return -1;
    }

    return mappedLightIndex;
}

RAB_LightInfo RAB_EmptyLightInfo()
{
    return lt_invalid_light();
}

RAB_LightSample RAB_EmptyLightSample()
{
    return lt_null_sample();
}

RAB_LightInfo RAB_LoadLightInfo(int lightIndex, bool previousFrame)
{
    if (lightIndex < 0)
    {
        return RAB_EmptyLightInfo();
    }

    return previousFrame
        ? load_previous_light(lightIndex)
        : (lightIndex < ph_light_count ? load_light(lightIndex) : RAB_EmptyLightInfo());
}

RAB_LightInfo RAB_LoadCompactLightInfo(uint risBufferPtr, int lightIndex)
{
    if (lightIndex < 0)
    {
        return RAB_EmptyLightInfo();
    }

    return load_compact_light(risBufferPtr, lightIndex);
}

RAB_LightSample RAB_SamplePolymorphicLight(Light light, RAB_Surface surface, vec2 sampleUv)
{
    if (light.index < 0)
    {
        return RAB_EmptyLightSample();
    }

    vec3 lightPosition = lt_sample_light_position_from_uv(
        light,
        sampleUv,
        lt_surface_ray_origin(lt_surface_rt_pos(surface), surface.geoNormal)
    );

    return light_sample_new_at_position(light, lightPosition, surface);
}

float RAB_GetLightSampleTargetPdfForSurface(RAB_LightSample lightSample, RAB_Surface surface)
{
    return lt_surface_target_pdf(surface, lightSample);
}

float scatter_resolve_light_pdf(RTXDI_DIReservoir reservoir, RAB_LightSample lightSample) {
    if (!RTXDI_IsValidDIReservoir(reservoir) || lightSample.index < 0) {
        return 0.0f;
    }

    return max(lightSample.solidAnglePdf, 0.0f);
}

vec3 scatter_resolve_irradiance(RAB_Surface surface, RAB_LightSample lightSample) {
    if (lightSample.index < 0) {
        return vec3(0.0f);
    }

    return lt_light_sample_incident_radiance(surface, lightSample);
}

vec3 scatter_resolve_early_throughput(RAB_Surface surface, RAB_LightSample lightSample) {
    if (lightSample.index < 0) {
        return vec3(0.0f);
    }

    return vec3(1.0f);
}

float scatter_resolve_secondary_path_jacobian(
    RAB_Surface surface,
    RAB_LightSample lightSample,
    vec3 secondPos,
    vec3 earlyThroughput,
    vec3 irradiance)
{
    if (lightSample.index < 0) {
        return 1.0f;
    }

    vec3 surfaceToSecond = secondPos - surface.worldPos;
    float distanceSq = dot(surfaceToSecond, surfaceToSecond);
    if (distanceSq <= 1e-6f) {
        return 1.0f;
    }

    vec3 directionToSecond = surfaceToSecond * inversesqrt(distanceSq);
    float cosSurface = max(abs(dot(surface.geoNormal, directionToSecond)), 1e-4f);
    float throughputScale = max(ph_luminance(max(earlyThroughput, vec3(0.0f))), 1e-4f);
    float irradianceScale = max(ph_luminance(max(irradiance, vec3(0.0f))), 1e-4f);
    return clamp((cosSurface * irradianceScale) / (distanceSq * throughputScale), 1e-4f, 1e4f);
}

// Convenience 2-arg overload: derives ``secondPos``, ``earlyThroughput`` and
// ``irradiance`` from the provided analytic light sample. This matches the
// reference ``pathReconnectionShift`` invocation where the spatial / scatter
// shift has already recomputed the light context at the new primary hit.
float scatter_resolve_secondary_path_jacobian(
    RAB_Surface     surface,
    RAB_LightSample lightSample)
{
    if (lightSample.index < 0) {
        return 1.0f;
    }
    vec3 secondPos       = lightSample.position;
    vec3 earlyThroughput = scatter_resolve_early_throughput(surface, lightSample);
    vec3 irradiance      = scatter_resolve_irradiance(surface, lightSample);
    return scatter_resolve_secondary_path_jacobian(
        surface, lightSample, secondPos, earlyThroughput, irradiance);
}

vec2 scatter_resolve_reservoir_subpixel(RTXDI_DIReservoir reservoir, ivec2 pixelPosition) {
    vec2 pixelSampleUV = lt_area_has_valid_domain(reservoir)
        ? lt_area_clamp_pixel_sample_uv(reservoir.pixelSampleUV)
        : lt_area_default_pixel_sample(pixelPosition);
    vec2 samplePixel = pixelSampleUV * vec2(viewWidth, viewHeight) - vec2(0.5f);
    return fract(samplePixel);
}

uint scatter_resolve_first_bsdf_component_type(RAB_Surface surface) {
    return lt_surface_diffuse_probability(surface) >= 0.5f
        ? SCATTER_BSDF_COMPONENT_DIFFUSE
        : SCATTER_BSDF_COMPONENT_SPECULAR;
}

uint scatter_resolve_second_bsdf_component_type(RAB_LightSample lightSample) {
    return lightSample.index >= 0 ? SCATTER_BSDF_COMPONENT_DIFFUSE : 0u;
}

uint scatter_resolve_reconnection_flags(RAB_LightSample lightSample) {
    uint flags = 0u;
    if (RAB_IsAnalyticLightSample(lightSample)) {
        flags |= SCATTER_RECONNECTION_FLAG_LIGHT_IS_NEE;
    } else if (lightSample.solidAnglePdf > 0.0f
        && ph_luminance(max(lightSample.color, vec3(0.0f))) > 0.0f)
    {
        // Preserve a semantic distinction between analytic/NEE selections and
        // non-analytic distant samples (e.g. future environment-map reuse).
        flags |= SCATTER_RECONNECTION_FLAG_LIGHT_IS_DISTANT;
    }
    return flags;
}

// Build reconnection data from current surface + reservoir state.
// Computes real sub-pixel Jacobian from surface geometry instead of accepting a stub.
// Build reconnection data from current surface + reservoir state.
// Reference parity: ReconnectionData is populated in-line during handleHit
// in the Falcor PathTracer. Photonics rebuilds the same payload from the
// resolved RTXDI_DIReservoir + RAB_LightSample pair.
//
// NOTE: `confidence` no longer lives on the reconnection -- it moved to
// PathReservoir.confidence (carried via RTXDI_DIReservoir.M in Photonics
// storage). The legacy `confidence` parameter is ignored (retained for
// ABI compatibility with older call sites and is removed in a follow-up).
ReservoirSplattingReconnectionData scatter_build_reconnection(
    RAB_Surface surface,
    RTXDI_DIReservoir reservoir,
    RAB_LightSample lightSample,
    ivec2 pixelPosition,
    float confidenceIgnored,
    float subPixelJacobian
) {
    ReservoirSplattingReconnectionData d = ReservoirSplattingReconnectionData_init();
    vec4 identityData    = scatter_load_surface_identity(pixelPosition, false);
    vec3 irradiance      = scatter_resolve_irradiance(surface, lightSample);
    vec3 earlyThroughput = scatter_resolve_early_throughput(surface, lightSample);
    vec3 secondPos       = (lightSample.index >= 0) ? lightSample.position : surface.worldPos;

    // ReconnectionData.slang:101 -- primary hit (Photonics HitInfo substitute).
    d.firstHit.worldPos  = surface.worldPos;
    d.firstHit.viewDepth = surface.viewDepth;
    d.firstHit.faceId    = uint(round(identityData.w));

    // ReconnectionData.slang:92-94 -- camera / film parameters.
    d.subPixel   = scatter_resolve_reservoir_subpixel(reservoir, pixelPosition);
    d.lensSample = lt_area_has_valid_domain(reservoir)
        ? clamp(reservoir.lensSampleUV, vec2(0.0f), vec2(1.0f))
        : lt_area_default_lens_sample();
    d.time = fract(float(max(ph_restir_frame_index, 0)) * 0.61803398875f);

    // ReconnectionData.slang:98 -- path length (DI: 2 for NEE, 1 for direct hit).
    d.pathLength = (lightSample.index >= 0) ? 2u : 1u;

    // ReconnectionData.slang:102-103 -- first vertex BSDF classification.
    d.firstBSDFComponentType = scatter_resolve_first_bsdf_component_type(surface);
    d.firstWi                = normalize(world_camera_position - surface.worldPos);

    // ReconnectionData.slang:106-108 -- second vertex / light vertex metadata.
    d.secondHit.worldPos  = secondPos;
    d.secondHit.viewDepth = surface.viewDepth;
    d.secondHit.faceId    = uint(round(identityData.w));
    d.secondBSDFComponentType = scatter_resolve_second_bsdf_component_type(lightSample);
    d.secondWo = (lightSample.index >= 0 && distance(secondPos, surface.worldPos) > 1e-6f)
        ? normalize(secondPos - surface.worldPos)
        : vec3(0.0f);

    // ReconnectionData.slang:110 -- transmission event (DI never uses BTDF).
    d.transmissionEvent = false;

    // ReconnectionData.slang:113-115 -- light-side book-keeping.
    d.lightIsNEE     = (lightSample.index >= 0) && RAB_IsAnalyticLightSample(lightSample);
    d.lightIsDistant = (lightSample.index >= 0) && !RAB_IsAnalyticLightSample(lightSample);
    d.lightPdf       = scatter_resolve_light_pdf(reservoir, lightSample);

    // ReconnectionData.slang:119-123 -- Jacobians + radiance carriers.
    d.subPixelJacobian      = max(subPixelJacobian, 1e-10f);
    d.lensVertexJacobian    = 1.0f;
    d.secondaryPathJacobian = scatter_resolve_secondary_path_jacobian(
        surface, lightSample, secondPos, earlyThroughput, irradiance);
    d.irradiance      = irradiance;
    d.earlyThroughput = earlyThroughput;
    return d;
}

bool RAB_GetConservativeVisibility(RAB_Surface surface, RAB_LightSample lightSample)
{
    RAB_LightSample lightSampleCopy = lightSample;
    return lt_trace_conservative_visibility(lightSampleCopy, surface);
}

RTXDI_DIReservoir RTXDI_LoadDIReservoir(
    RTXDI_ReservoirBufferParameters reservoirParams,
    uvec2 reservoirPosition,
    uint reservoirArrayIndex)
{
    RTXDI_DIReservoir reservoir = RTXDI_EmptyDIReservoir();
    ivec2 reservoirPositionInt = ivec2(reservoirPosition);

    if (reservoirArrayIndex == RTXDI_DI_BUFFER_INDEX_INITIAL_SAMPLING_OUTPUT)
    {
        rtxdi_unpack_reservoir_at_surface(
            reservoir,
            texelFetch(radiosity_proposal_reservoirs, reservoirPositionInt, 0),
            texelFetch(radiosity_proposal_reservoir_samples, reservoirPositionInt, 0),
            texelFetch(radiosity_proposal_reservoir_meta, reservoirPositionInt, 0),
            RAB_EmptySurface(),
            false
        );
    }
    else if (reservoirArrayIndex == RTXDI_DI_BUFFER_INDEX_TEMPORAL_RESAMPLING_OUTPUT)
    {
        // Scatter temporal resampling output — same packed format, different texture.
        rtxdi_unpack_reservoir_at_surface(
            reservoir,
            texelFetch(temporal_reservoir_data, reservoirPositionInt, 0),
            texelFetch(temporal_reservoir_sample, reservoirPositionInt, 0),
            texelFetch(temporal_reservoir_meta, reservoirPositionInt, 0),
            RAB_EmptySurface(),
            false
        );
    }
    else if (reservoirArrayIndex == RTXDI_DI_BUFFER_INDEX_SPATIAL_RESAMPLING_OUTPUT)
    {
        rtxdi_unpack_reservoir_at_surface(
            reservoir,
            texelFetch(radiosity_spatial_reservoirs, reservoirPositionInt, 0),
            texelFetch(radiosity_spatial_reservoir_samples, reservoirPositionInt, 0),
            texelFetch(radiosity_spatial_reservoir_meta, reservoirPositionInt, 0),
            RAB_EmptySurface(),
            false
        );
    }
    else if (reservoirArrayIndex == RTXDI_DI_BUFFER_INDEX_SHADING_INPUT)
    {
        // Final shading must evaluate the authoritative post-spatial reservoir,
        // while the promotion pass writes the next-frame persistent history.
        rtxdi_unpack_reservoir_at_surface(
            reservoir,
            texelFetch(radiosity_spatial_reservoirs, reservoirPositionInt, 0),
            texelFetch(radiosity_spatial_reservoir_samples, reservoirPositionInt, 0),
            texelFetch(radiosity_spatial_reservoir_meta, reservoirPositionInt, 0),
            RAB_EmptySurface(),
            false
        );
    }
    else
    {
        rtxdi_unpack_reservoir_at_surface(
            reservoir,
            texelFetch(radiosity_reservoirs, reservoirPositionInt, 0),
            texelFetch(radiosity_reservoir_samples, reservoirPositionInt, 0),
            texelFetch(radiosity_reservoir_meta, reservoirPositionInt, 0),
            RAB_EmptySurface(),
            false
        );
    }

    return reservoir;
}

RTXDI_DIReservoir RTXDI_LoadPreviousDIReservoir(
    RTXDI_ReservoirBufferParameters reservoirParams,
    uvec2 reservoirPosition)
{
    RTXDI_DIReservoir reservoir = RTXDI_EmptyDIReservoir();
    ivec2 reservoirPositionInt = ivec2(reservoirPosition);
    rtxdi_unpack_reservoir_at_surface(
        reservoir,
        texelFetch(prev_radiosity_reservoirs, reservoirPositionInt, 0),
        texelFetch(prev_radiosity_reservoir_samples, reservoirPositionInt, 0),
        texelFetch(prev_radiosity_reservoir_meta, reservoirPositionInt, 0),
        RAB_EmptySurface(),
        false
    );
    return reservoir;
}

void rtxdi_reset_visibility(inout RTXDI_DIReservoir reservoir) {
    reservoir.packedVisibility = 0u;
    reservoir.age = 0u;
    reservoir.spatialDistance = ivec2(0);
}

void rtxdi_prepare_spatial_reuse(inout RTXDI_DIReservoir reservoir, ivec2 spatialOffset) {
    // RTXDI SpatialResampling.hlsli line 87: neighborSample.spatialDistance += spatialOffset;
    // Unconditional — no visibility guard. Always track accumulated spatial distance.
    reservoir.spatialDistance += spatialOffset;
}

bool rtxdi_has_reusable_visibility(RTXDI_DIReservoir reservoir) {
    // When uniforms are unbound (0.0), fall back to SDK defaults:
    //   finalVisibilityMaxAge      = 4   (ReSTIRDI.cpp line 114)
    //   finalVisibilityMaxDistance = 16  (ReSTIRDI.cpp line 115)
    float maxAge      = (ph_restir_visibility_max_age      > 0.0f) ? ph_restir_visibility_max_age      : lt_visibility_reuse_max_age;
    float maxDistance = (ph_restir_visibility_max_distance > 0.0f) ? ph_restir_visibility_max_distance : lt_visibility_reuse_max_distance;
    return reservoir.age > 0u
        && float(reservoir.age) <= maxAge
        && length(vec2(reservoir.spatialDistance)) < maxDistance;
}

bool RTXDI_GetDIReservoirVisibility(
    RTXDI_DIReservoir reservoir,
    RTXDI_VisibilityReuseParameters params,
    out vec3 visibility)
{
    if (reservoir.age > 0u
        && reservoir.age <= params.maxAge
        && length(vec2(reservoir.spatialDistance)) < params.maxDistance)
    {
        visibility = rtxdi_unpack_visibility(reservoir.packedVisibility);
        return true;
    }

    visibility = vec3(0.0f);
    return false;
}

// Returns the stored RGB visibility exactly as packed in the reservoir.
vec3 rtxdi_get_visibility(RTXDI_DIReservoir reservoir) {
    return rtxdi_unpack_visibility(reservoir.packedVisibility);
}

// Scalar visibility test — true when at least one channel exceeds 0 via luminance.
// Uses per-channel luminance-weighted sum matching RTXDI's packedVisibility bit test.
bool rtxdi_is_visible(RTXDI_DIReservoir reservoir) {
    return ph_luminance(rtxdi_get_visibility(reservoir)) > 0.0f;
}

// Primary — matches RTXDI_StoreVisibilityInDIReservoir (RTXDI_DIReservoir.hlsli).
// discardIfInvisible: when true and visibility is fully zero, kill the reservoir light data
// (equivalent to RTXDI discarding an occluded sample). M and targetPdf are always preserved.
void RTXDI_StoreVisibilityInDIReservoir(inout RTXDI_DIReservoir reservoir, vec3 visibility, bool discardIfInvisible) {
    reservoir.packedVisibility = rtxdi_pack_visibility(visibility);
    reservoir.spatialDistance = ivec2(0);
    reservoir.age = 0u;
    if (discardIfInvisible && visibility.x == 0.0f && visibility.y == 0.0f && visibility.z == 0.0f) {
        // RTXDI RTXDI_DIReservoir.hlsli lines 93-96: only clears lightData and weightSum.
        // sampleUv (uvData) is intentionally NOT cleared — RTXDI leaves it intact.
        // M and targetPdf are also preserved for correct downstream resampling.
        reservoir.lightData = 0u;
        reservoir.weightSum = 0.0f;
    }
}

// Backward-compat alias — preserves original bool-based call sites.
void rtxdi_store_visibility(inout RTXDI_DIReservoir reservoir, bool visible) {
    RTXDI_StoreVisibilityInDIReservoir(reservoir, visible ? vec3(1.0f) : vec3(0.0f), true);
}

void rtxdi_copy_visibility(inout RTXDI_DIReservoir reservoir, RTXDI_DIReservoir sourceReservoir) {
    reservoir.packedVisibility = sourceReservoir.packedVisibility;
    reservoir.age = sourceReservoir.age;
    reservoir.spatialDistance = sourceReservoir.spatialDistance;
    reservoir.transportAux0 = sourceReservoir.transportAux0;
    reservoir.transportAux1 = sourceReservoir.transportAux1;
    reservoir.pixelSampleUV = sourceReservoir.pixelSampleUV;
    reservoir.lensSampleUV = sourceReservoir.lensSampleUV;
    reservoir.pathSample = sourceReservoir.pathSample;
}

void rtxdi_inherit_visibility(
    inout RTXDI_DIReservoir reservoir,
    RTXDI_DIReservoir sourceReservoir,
    ivec2 currentUv,
    ivec2 sourceUv,
    bool temporalReuse
) {
    reservoir.packedVisibility = sourceReservoir.packedVisibility;
    reservoir.age = sourceReservoir.age;
    reservoir.spatialDistance = sourceReservoir.spatialDistance;
    reservoir.age = sourceReservoir.age + 1u;
    reservoir.transportAux0 = sourceReservoir.transportAux0;
    reservoir.transportAux1 = sourceReservoir.transportAux1;
    reservoir.pixelSampleUV = sourceReservoir.pixelSampleUV;
    reservoir.lensSampleUV = sourceReservoir.lensSampleUV;
    reservoir.pathSample = sourceReservoir.pathSample;
    if (temporalReuse) {
        reservoir.spatialDistance = ivec2(0);
    } else {
        reservoir.spatialDistance = sourceReservoir.spatialDistance + (sourceUv - currentUv);
    }
}

// Primary — matches RTXDI_StreamSample signature (RTXDI_DIReservoir.hlsli).
// Takes explicit lightIndex, position (RT-space), random value, targetPdf, and invSourcePdf.
// Always increments M; does NOT reset visibility (caller manages visibility lifecycle).
bool RTXDI_StreamSample(inout RTXDI_DIReservoir reservoir, int lightIndex, vec2 sampleUv, float random, float targetPdf, float invSourcePdf) {
    float risWeight = targetPdf * invSourcePdf;
    reservoir.M += 1.0f;
    reservoir.weightSum += risWeight;
    bool selectSample = (random * reservoir.weightSum < risWeight);
    if (selectSample) {
        rtxdi_set_light_index(reservoir, lightIndex);
        rtxdi_set_sample_uv(reservoir, sampleUv);
        reservoir.targetPdf = targetPdf;
        reservoir.transportAux0 = 0.0f;
        reservoir.transportAux1 = 0.0f;
        reservoir.pixelSampleUV = vec2(-1.0f);
        reservoir.lensSampleUV = vec2(-1.0f);
        reservoir.pathSample = 2u;
    }
    return selectSample;
}

bool rtxdi_stream_sample(inout RTXDI_DIReservoir reservoir, RAB_LightSample smple, float weight, float samples) {
    reservoir.M += max(samples, 0.0f);

    if (smple.index < 0 || weight <= 0.0f || samples <= 0.0f) {
        return false;
    }

    reservoir.weightSum += weight;
    if (rand_next_float() * reservoir.weightSum < weight) {
        rtxdi_set_light_index(reservoir, smple.index);
        reservoir.targetPdf = smple.weight;
        reservoir.transportAux0 = 0.0f;
        reservoir.transportAux1 = 0.0f;
        rtxdi_set_sample_uv(reservoir, lt_encode_light_sample_uv(load_light(smple.index), smple.position));
        reservoir.pixelSampleUV = vec2(-1.0f);
        reservoir.lensSampleUV = vec2(-1.0f);
        reservoir.pathSample = 2u;
        return true;
    }

    return false;
}

float rtxdi_target_pdf_at_surface(RTXDI_DIReservoir reservoir, RAB_Surface surface) {
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        return 0.0f;
    }

    RAB_LightSample smple = light_sample_decode(reservoir, surface, false);
    return lt_surface_target_pdf(surface, smple);
}

float rtxdi_target_pdf_at_surface_with_view(RTXDI_DIReservoir reservoir, RAB_Surface surface, vec3 viewPos) {
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        return 0.0f;
    }

    RAB_LightSample smple = light_sample_decode(reservoir, surface, false);
    return lt_surface_target_pdf_with_view(surface, smple, viewPos);
}

float rtxdi_m_factor(float q0, float q1) {
    return (q0 <= 0.0f)
        ? 1.0f
        : clamp(pow(min(q1 / q0, 1.0f), 8.0f), 0.0f, 1.0f);
}

float rtxdi_pairwise_mis_weight(float w0, float w1, float M0, float M1) {
    float balanceDenominator = M0 * w0 + M1 * w1;
    return balanceDenominator <= 0.0f ? 0.0f : max(M0 * w0, 0.0f) / balanceDenominator;
}

// Primary — matches RTXDI_InternalSimpleResample exactly (RTXDI_DIReservoir.hlsli lines 192-225).
// No early-return guards: risWeight=0 cases fall through naturally (M still accumulates).
bool RTXDI_InternalSimpleResample(
    inout RTXDI_DIReservoir reservoir,
    RTXDI_DIReservoir candidateReservoir,
    float randomValue,
    float targetPdf,
    float sampleNormalization,
    float sampleM
) {
    float risWeight = targetPdf * sampleNormalization;
    reservoir.M += sampleM;
    reservoir.weightSum += risWeight;
    bool selectSample = (randomValue * reservoir.weightSum < risWeight);
    if (selectSample) {
        reservoir.lightData = candidateReservoir.lightData;
        reservoir.uvData = candidateReservoir.uvData;
        reservoir.targetPdf = targetPdf;
        reservoir.packedVisibility = candidateReservoir.packedVisibility;
        reservoir.age = candidateReservoir.age;
        reservoir.spatialDistance = candidateReservoir.spatialDistance;
        reservoir.transportAux0 = candidateReservoir.transportAux0;
        reservoir.transportAux1 = candidateReservoir.transportAux1;
        reservoir.pixelSampleUV = candidateReservoir.pixelSampleUV;
        reservoir.lensSampleUV = candidateReservoir.lensSampleUV;
        reservoir.pathSample = candidateReservoir.pathSample;
    }
    return selectSample;
}

// Matches RTXDI_CombineDIReservoirs (RTXDI_DIReservoir.hlsli lines 230-244).
// Wraps RTXDI_InternalSimpleResample with canonical CombineDIReservoirs normalization.
bool RTXDI_CombineDIReservoirs(
    inout RTXDI_DIReservoir reservoir,
    RTXDI_DIReservoir newReservoir,
    float random,
    float targetPdf
) {
    return RTXDI_InternalSimpleResample(
        reservoir,
        newReservoir,
        random,
        targetPdf,
        newReservoir.weightSum * newReservoir.M,
        newReservoir.M
    );
}

// Backward-compat alias with photonics-specific guards for existing callers.
// Keeps the original defensive behavior (index check, zero-pdf early return, max(sampleM,0)).
bool rtxdi_internal_simple_resample(
    inout RTXDI_DIReservoir reservoir,
    RTXDI_DIReservoir candidateReservoir,
    float randomValue,
    float targetPdf,
    float sampleNormalization,
    float sampleM
) {
    // Always accumulate M even when targetPdf is zero (matching RTXDI behavior).
    // This ensures M correctly reflects the number of candidates considered,
    // which is critical for downstream pairwise MIS balance heuristic weights.
    reservoir.M += max(sampleM, 0.0f);

    if (candidateReservoir.lightData == 0u || targetPdf <= 0.0f || sampleNormalization <= 0.0f || sampleM <= 0.0f) {
        return false;
    }

    float risWeight = targetPdf * sampleNormalization;
    reservoir.weightSum += risWeight;

    bool selectSample = randomValue * reservoir.weightSum < risWeight;
    if (selectSample) {
        reservoir.lightData = candidateReservoir.lightData;
        reservoir.uvData = candidateReservoir.uvData;
        reservoir.targetPdf = targetPdf;
        reservoir.packedVisibility = candidateReservoir.packedVisibility;
        reservoir.age = candidateReservoir.age;
        reservoir.spatialDistance = candidateReservoir.spatialDistance;
        reservoir.transportAux0 = candidateReservoir.transportAux0;
        reservoir.transportAux1 = candidateReservoir.transportAux1;
        reservoir.pixelSampleUV = candidateReservoir.pixelSampleUV;
        reservoir.lensSampleUV = candidateReservoir.lensSampleUV;
        reservoir.pathSample = candidateReservoir.pathSample;
    }

    return selectSample;
}

// Primary pairwise MIS helpers shared by DI/GI include paths.
// Keep these as the single owned entry points so downstream bridges link against
// one canonical implementation surface without legacy wrapper drift.
bool RTXDI_StreamNeighborWithPairwiseMIS(
    inout RTXDI_DIReservoir reservoir,
    float random,
    RTXDI_DIReservoir neighborSample,
    RAB_Surface neighborSurface,
    RTXDI_DIReservoir centerSample,
    RAB_Surface centerSurface,
    float numSpatialSamples
) {
    float neighborWeightAtCanonical = max(rtxdi_target_pdf_at_surface(neighborSample, centerSurface), 0.0f);
    float canonicalWeightAtNeighbor = max(rtxdi_target_pdf_at_surface(centerSample, neighborSurface), 0.0f);
    float neighborWeightAtNeighbor = max(rtxdi_target_pdf_at_surface(neighborSample, neighborSurface), 0.0f);
    float canonicalWeightAtCanonical = max(rtxdi_target_pdf_at_surface(centerSample, centerSurface), 0.0f);

    float neighborMisWeight = rtxdi_pairwise_mis_weight(
        neighborWeightAtNeighbor,
        neighborWeightAtCanonical,
        neighborSample.M * numSpatialSamples,
        centerSample.M
    );
    float canonicalMisWeight = rtxdi_pairwise_mis_weight(
        canonicalWeightAtNeighbor,
        canonicalWeightAtCanonical,
        neighborSample.M * numSpatialSamples,
        centerSample.M
    );

    float effectiveM = neighborSample.M * min(
        rtxdi_m_factor(neighborWeightAtNeighbor, neighborWeightAtCanonical),
        rtxdi_m_factor(canonicalWeightAtNeighbor, canonicalWeightAtCanonical)
    );

    reservoir.canonicalWeight += 1.0f - canonicalMisWeight;
    return rtxdi_internal_simple_resample(
        reservoir,
        neighborSample,
        random,
        neighborWeightAtCanonical,
        neighborSample.weightSum * neighborMisWeight,
        effectiveM
    );
}

bool RTXDI_StreamCanonicalWithPairwiseStep(
    inout RTXDI_DIReservoir reservoir,
    float random,
    RTXDI_DIReservoir centerSample,
    RAB_Surface centerSurface
) {
    return rtxdi_internal_simple_resample(
        reservoir,
        centerSample,
        random,
        centerSample.targetPdf,
        centerSample.weightSum * reservoir.canonicalWeight,
        centerSample.M
    );
}

// 3-parameter version matching RTXDI_FinalizeResampling exactly (RTXDI_DIReservoir.hlsli).
// Uses reservoir.targetPdf as the denominator base — call this for temporal/bias-correction paths.
void RTXDI_FinalizeResampling(inout RTXDI_DIReservoir reservoir, float normalizationNumerator, float normalizationDenominator) {
    float denominator = reservoir.targetPdf * normalizationDenominator;
    reservoir.weightSum = (denominator == 0.0f) ? 0.0f : (reservoir.weightSum * normalizationNumerator) / denominator;
}

// 4-parameter helper kept for callers that supply an explicit selectedTargetPdf
// (e.g. reuse_resolve.fsh pairwise-MIS path).
// Matches RTXDI_FinalizeResampling exactly: the only guard is denominator == 0.0.
void ph_rtxdi_finalize_resampling_explicit(inout RTXDI_DIReservoir reservoir, float normalizationNumerator, float normalizationDenominator, float selectedTargetPdf) {
    float denominator = selectedTargetPdf * normalizationDenominator;
    reservoir.weightSum = (denominator == 0.0f) ? 0.0f : (reservoir.weightSum * normalizationNumerator) / denominator;
    reservoir.targetPdf = selectedTargetPdf;
}

void ph_rtxdi_finalize_initial(inout RTXDI_DIReservoir reservoir) {
    // Legacy helper used by old call sites; keep the finalize path simple to avoid
    // macro-dependent parse drift in include-expanded shader builds.
    ph_rtxdi_finalize_resampling_explicit(reservoir, 1.0, reservoir.M > 0.0 ? reservoir.M : 1.0, reservoir.targetPdf);
}

// Matches RTXDI_DIReservoir::packedVisibility reuse semantics.
// Visibility bits are preserved independently of age; reuse eligibility is gated by age/distance.
vec3 rtxdi_unpack_visibility(uint packedVisibility) {
    return vec3(
        float(packedVisibility & RTXDI_PackedDIReservoir_VisibilityChannelMax),
        float((packedVisibility >> RTXDI_PackedDIReservoir_VisibilityChannelShift) & RTXDI_PackedDIReservoir_VisibilityChannelMax),
        float((packedVisibility >> (RTXDI_PackedDIReservoir_VisibilityChannelShift * 2u)) & RTXDI_PackedDIReservoir_VisibilityChannelMax)
    ) / float(RTXDI_PackedDIReservoir_VisibilityChannelMax);
}

uint rtxdi_pack_visibility(vec3 visibility) {
    vec3 clampedVisibility = clamp(visibility, vec3(0.0f), vec3(1.0f));
    uvec3 encodedVisibility = uvec3(clampedVisibility * float(RTXDI_PackedDIReservoir_VisibilityChannelMax));
    return encodedVisibility.x
        | (encodedVisibility.y << RTXDI_PackedDIReservoir_VisibilityChannelShift)
        | (encodedVisibility.z << (RTXDI_PackedDIReservoir_VisibilityChannelShift * 2u));
}

vec4 rtxdi_pack_reservoir(RTXDI_DIReservoir reservoir) {
    uint packedM = min(uint(reservoir.M), RTXDI_PackedDIReservoir_MaxMUint);
    return vec4(
        uintBitsToFloat(reservoir.lightData),
        reservoir.weightSum,
        reservoir.targetPdf,
        uintBitsToFloat(reservoir.packedVisibility | (packedM << RTXDI_PackedDIReservoir_MShift))
    );
}

vec4 rtxdi_pack_reservoir_sample(RTXDI_DIReservoir reservoir) {
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        return vec4(0.0f);
    }

    return vec4(
        uintBitsToFloat(reservoir.uvData),
        uintBitsToFloat(rtxdi_pack_sample_uv(reservoir.pixelSampleUV)),
        uintBitsToFloat(rtxdi_pack_sample_uv(reservoir.lensSampleUV)),
        uintBitsToFloat(reservoir.pathSample)
    );
}

const int RTXDI_PackedDIReservoir_DistanceChannelBits = 8;
const int RTXDI_PackedDIReservoir_DistanceXShift = 0;
const int RTXDI_PackedDIReservoir_DistanceYShift = 8;
const int RTXDI_PackedDIReservoir_AgeShift = 16;
const uint RTXDI_PackedDIReservoir_MaxAge = 0xffu;
const uint RTXDI_PackedDIReservoir_DistanceMask = (1u << RTXDI_PackedDIReservoir_DistanceChannelBits) - 1u;
const int RTXDI_PackedDIReservoir_MaxDistance = int((1u << (RTXDI_PackedDIReservoir_DistanceChannelBits - 1)) - 1u);

uint rtxdi_pack_age_distance(uint age, ivec2 sd) {
    ivec2 clampedSpatialDistance = clamp(
        sd,
        ivec2(-RTXDI_PackedDIReservoir_MaxDistance),
        ivec2(RTXDI_PackedDIReservoir_MaxDistance)
    );
    uint clampedAge = min(age, RTXDI_PackedDIReservoir_MaxAge);

    return ((uint(clampedSpatialDistance.x) & RTXDI_PackedDIReservoir_DistanceMask) << RTXDI_PackedDIReservoir_DistanceXShift)
        | ((uint(clampedSpatialDistance.y) & RTXDI_PackedDIReservoir_DistanceMask) << RTXDI_PackedDIReservoir_DistanceYShift)
        | (clampedAge << RTXDI_PackedDIReservoir_AgeShift);
}

void rtxdi_unpack_age_distance(uint packedValue, out uint age, out ivec2 sd) {
    int sxShift = 32 - RTXDI_PackedDIReservoir_DistanceXShift - RTXDI_PackedDIReservoir_DistanceChannelBits;
    int syShift = 32 - RTXDI_PackedDIReservoir_DistanceYShift - RTXDI_PackedDIReservoir_DistanceChannelBits;
    int signExtendShift = 32 - RTXDI_PackedDIReservoir_DistanceChannelBits;
    int isx = int(packedValue << sxShift) >> signExtendShift;
    int isy = int(packedValue << syShift) >> signExtendShift;
    age = (packedValue >> RTXDI_PackedDIReservoir_AgeShift) & RTXDI_PackedDIReservoir_MaxAge;
    sd = ivec2(isx, isy);
}

vec4 rtxdi_pack_reservoir_meta(RTXDI_DIReservoir reservoir) {
    return vec4(
        reservoir.canonicalWeight,
        reservoir.transportAux0,
        reservoir.transportAux1,
        uintBitsToFloat(rtxdi_pack_age_distance(reservoir.age, reservoir.spatialDistance))
    );
}

void rtxdi_unpack_reservoir_at_surface(inout RTXDI_DIReservoir reservoir, vec4 color, vec4 sampleData, vec4 meta, RAB_Surface surface, bool remap) {
    uint lightData = floatBitsToUint(color.x);

    if (remap) {
        int index = rtxdi_decode_light_index(lightData);
        if (index >= 0 && index < ph_lights_array_mapping.length()) {
            index = ph_lights_array_mapping[index];
        }
        if (index < 0 || index >= ph_light_count) {
            lightData = 0u;
        } else {
            lightData = rtxdi_make_light_data(index);
        }
    }
    // When remap=false, lightData preserves the previous-frame packed ID and validity bit.
    // RTXDI_LoadDIReservoir does not validate — remapping happens separately at the call site.

    reservoir.lightData = lightData;
    reservoir.uvData = floatBitsToUint(sampleData.x);
    reservoir.pixelSampleUV = rtxdi_unpack_sample_uv(floatBitsToUint(sampleData.y));
    reservoir.lensSampleUV = rtxdi_unpack_sample_uv(floatBitsToUint(sampleData.z));
    reservoir.pathSample = floatBitsToUint(sampleData.w);
    reservoir.weightSum = color.y;
    reservoir.targetPdf = color.z;
    uint packedVisibilityAndM = floatBitsToUint(color.w);
    reservoir.M = float((packedVisibilityAndM >> RTXDI_PackedDIReservoir_MShift) & RTXDI_PackedDIReservoir_MaxMUint);

    // Unpack age+spatialDistance from meta.w, matching RTXDI distanceAge packing.
    // packedVisibility lives in color.w with M, matching RTXDI_PackedDIReservoir::mVisibility.
    uint packedDistanceAge = floatBitsToUint(meta.w);
    reservoir.packedVisibility = packedVisibilityAndM & RTXDI_PackedDIReservoir_VisibilityMask;
    rtxdi_unpack_age_distance(packedDistanceAge, reservoir.age, reservoir.spatialDistance);
    reservoir.canonicalWeight = meta.x;
    reservoir.transportAux0 = meta.y;
    reservoir.transportAux1 = meta.z;

    if (!lt_area_has_valid_domain(reservoir)) {
        reservoir.pixelSampleUV = vec2(-1.0f);
        reservoir.lensSampleUV = vec2(-1.0f);
    }

    // RTXDI_UnpackDIReservoir sanitization (ReservoirStorage.hlsli lines 88-91):
    //   if (isinf(res.weightSum) || isnan(res.weightSum)) { res = RTXDI_EmptyDIReservoir(); }
    // RTXDI only checks weightSum, not targetPdf. Match exactly.
    if (isinf(reservoir.weightSum) || isnan(reservoir.weightSum)) {
        reservoir = RTXDI_EmptyDIReservoir();
    }
}

RTXDI_DIReservoir RTXDI_DISpatialResamplingWithPairwiseMIS(
    uvec2 pixelPosition,
    RAB_Surface centerSurface,
    RTXDI_DIReservoir centerSample,
    inout RTXDI_RandomSamplerState rng,
    RTXDI_RuntimeParameters params,
    RTXDI_ReservoirBufferParameters reservoirParams,
    uint sourceBufferIndex,
    RTXDI_DISpatialResamplingParameters sparams,
    inout RAB_LightSample selectedLightSample)
{
    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    state.canonicalWeight = 0.0f;

    uint numSpatialSamples = (centerSample.M < float(sparams.targetHistoryLength))
        ? max(sparams.numDisocclusionBoostSamples, sparams.numSamples)
        : sparams.numSamples;

    uint startIdx = uint(lt_next_random(rng) * float(params.neighborOffsetMask));
    uint validSpatialSamples = 0u;

    for (uint i = 0u; i < numSpatialSamples; ++i)
    {
        uint sampleIdx = (startIdx + i) & params.neighborOffsetMask;
        ivec2 spatialOffset = ivec2(lt_load_neighbor_offset(int(sampleIdx)) * sparams.samplingRadius);
        ivec2 idx = ivec2(pixelPosition) + spatialOffset;
        idx = RAB_ClampSamplePositionIntoView(idx, false);

        RTXDI_ActivateCheckerboardPixel(idx, false, int(params.activeCheckerboardField));

        RAB_Surface neighborSurface = RAB_GetGBufferSurface(idx, false);

        if (!RAB_IsSurfaceValid(neighborSurface))
            continue;

        if (!RTXDI_IsValidNeighbor(RAB_GetSurfaceNormal(centerSurface), RAB_GetSurfaceNormal(neighborSurface),
            RAB_GetSurfaceLinearDepth(centerSurface), RAB_GetSurfaceLinearDepth(neighborSurface),
            sparams.normalThreshold, sparams.depthThreshold))
            continue;

        if (sparams.enableMaterialSimilarityTest != 0u && !RAB_AreMaterialsSimilar(RAB_GetMaterial(centerSurface), RAB_GetMaterial(neighborSurface)))
            continue;

        RTXDI_DIReservoir neighborSample = RTXDI_LoadDIReservoir(reservoirParams,
            uvec2(RTXDI_PixelPosToReservoirPos(idx, int(params.activeCheckerboardField))), sourceBufferIndex);
        neighborSample.spatialDistance += spatialOffset;

        if (RTXDI_IsValidDIReservoir(neighborSample))
        {
            if (sparams.discountNaiveSamples != 0u && neighborSample.M <= 2.0f)
                continue;
        }

        validSpatialSamples++;

        if (neighborSample.M <= 0.0f)
            continue;

        RTXDI_StreamNeighborWithPairwiseMIS(state, lt_next_random(rng),
            neighborSample, neighborSurface,
            centerSample, centerSurface,
            float(numSpatialSamples));
    }

    state.canonicalWeight = (validSpatialSamples == 0u) ? 1.0f : state.canonicalWeight;

    RTXDI_StreamCanonicalWithPairwiseStep(state, lt_next_random(rng), centerSample, centerSurface);

    RTXDI_FinalizeResampling(state, 1.0f, float(max(1u, validSpatialSamples)));

    selectedLightSample = RAB_SamplePolymorphicLight(
        RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(state), false),
        centerSurface, RTXDI_GetDIReservoirSampleUV(state));

    return state;
}

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
bool RAB_AreMaterialsSimilar(RAB_Material a, RAB_Material b)
{
    return true;
}
#else
bool RAB_AreMaterialsSimilar(RAB_Material a, RAB_Material b)
{
    float roughnessA = clamp(a.roughness, 0.0f, 1.0f);
    float roughnessB = clamp(b.roughness, 0.0f, 1.0f);
    if (!rtxdi_compare_relative_difference(roughnessA, roughnessB, 0.5f)) {
        return false;
    }

    vec3 specF0_A = clamp(a.specularF0, vec3(0.0f), vec3(1.0f));
    vec3 specF0_B = clamp(b.specularF0, vec3(0.0f), vec3(1.0f));
    if (abs(ph_luminance(specF0_A) - ph_luminance(specF0_B)) > 0.25f) {
        return false;
    }

    vec3 albedoA = clamp(a.diffuseAlbedo, vec3(0.0f), vec3(1.0f));
    vec3 albedoB = clamp(b.diffuseAlbedo, vec3(0.0f), vec3(1.0f));
    if (abs(ph_luminance(albedoA) - ph_luminance(albedoB)) > 0.25f) {
        return false;
    }

    return true;
}
#endif

// Forward declarations for Area-ReSTIR shift mapping constants and core functions.
// These are defined later in the file (Area-ReSTIR Core section) but referenced by
// lt_area_temporal_resampling and lt_area_spatial_resampling which appear first.
const uint AREA_RESTIR_SHIFT_RANDOM_REPLAY     = 0u;  // ShiftMapping::RandomReplay
const uint AREA_RESTIR_SHIFT_RECONNECTION      = 1u;  // ShiftMapping::PrimaryHitReconnection
const uint AREA_RESTIR_SHIFT_MODE_ONLY_RANDOM_REPLAY = 0u;  // ShiftMappingModeInReusing::OnlyRandomReplay
const uint AREA_RESTIR_SHIFT_MODE_ONLY_RECONNECTION  = 1u;  // ShiftMappingModeInReusing::OnlyReconnection
const uint AREA_RESTIR_SHIFT_MODE_MIS                = 2u;  // ShiftMappingModeInReusing::MIS

// Area-ReSTIR shift-mapping constants remain; temporal scatter stage
// implementations are defined later in this file under the concrete stage
// sections so each wrapper sees exactly one implementation.

// NOTE: Previously there was a top-level `#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)`
// wrapping the remainder of this file. That gated core RTXDI helpers such as
// ``RTXDI_SampleLocalLights``, ``RTXDI_LightBrdfMisWeight``, the pairwise MIS
// splat helpers, and ``lt_materials_similar``/``IsComplexSurface`` — all of
// which are consumed by non-scatter passes (GenerateInitialSamples,
// SpatialResampling, GatherTemporalResampling, Shade*). The guard has been
// removed; the narrower ``#if`` blocks below still protect the scatter-SSBO
// touching code (append/sort/resolve cells) so non-scatter passes compile
// cleanly while the splatting pipeline keeps its storage buffers.
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

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY)
// Reference: ReprojectTemporalSamples.rt.slang:167-174.
//   InterlockedAdd(globalCounters[kCounterIndexDataCount], 1, index);
//   InterlockedAdd(cellCounters[linearizedIndex], 1, cellIndex);
//   reservoirIndices[index]    = uint2(linearizedIndex, cellIndex);
//   scatteredReservoirs[index] = pixel;
// ``supportWeight`` is ignored so the scatter/sort tables stay in lockstep with
// the reference (uniform weight 1.0 per splat). It is kept in the signature
// because the Java pipeline still expects the 3-arg call shape.
void lt_temporal_scatter_append_contributor(ivec2 targetPixel, ivec2 sourceReservoirPos, float supportWeight)
{
    if (!lt_is_viewport_uv_in_bounds(targetPixel) || supportWeight <= 0.0f) {
        return;
    }

    ivec2 targetReservoirPos = RTXDI_PixelPosToReservoirPos(targetPixel, ph_restir_active_checkerboard_field);
    if (!lt_is_active_reservoir_lane(targetReservoirPos)) {
        return;
    }

    uint cellLinearIndex = lt_temporal_scatter_linear_index(targetReservoirPos);
    uint localCellIndex  = lt_temporal_scatter_cell_counter_atomic_add(0u, cellLinearIndex, 1u);
    uint appendIndex     = lt_temporal_scatter_global_counter_atomic_add(0u, 0u, 1u);
    lt_temporal_scatter_store_reservoir_index(0u, appendIndex, uvec2(cellLinearIndex, localCellIndex));
    lt_temporal_scatter_store_scattered_reservoir(0u, appendIndex, uvec2(sourceReservoirPos));
}

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)
void lt_multi_temporal_scatter_append_contributor(
    uint partitionIndex,
    ivec2 targetPixel,
    ivec2 sourceReservoirPos)
{
    if (!lt_is_viewport_uv_in_bounds(targetPixel)) {
        return;
    }

    ivec2 targetReservoirPos = RTXDI_PixelPosToReservoirPos(targetPixel, ph_restir_active_checkerboard_field);
    if (!lt_is_active_reservoir_lane(targetReservoirPos)) {
        return;
    }

    uint cellLinearIndex = lt_temporal_scatter_linear_index(targetReservoirPos);
    uint partitionedCellIndex = lt_temporal_partitioned_cell_index(partitionIndex, cellLinearIndex);
    uint counterBaseIndex = lt_temporal_partitioned_counter_index(partitionIndex, LT_MULTI_TEMPORAL_COUNTER_INDEX_DATA_COUNT);
    uint localCellIndex = lt_temporal_scatter_cell_counter_atomic_add(partitionIndex, partitionedCellIndex, 1u);
    uint appendIndex = lt_temporal_scatter_global_counter_atomic_add(partitionIndex, counterBaseIndex, 1u);
    uint scatteredBufferIndex = lt_temporal_partitioned_contributor_index(partitionIndex, appendIndex);
    lt_temporal_scatter_store_reservoir_index(partitionIndex, scatteredBufferIndex, uvec2(cellLinearIndex, localCellIndex));
    lt_temporal_scatter_store_scattered_reservoir(partitionIndex, scatteredBufferIndex, uvec2(sourceReservoirPos));
}
#endif
#endif

#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
// Reference: SortReprojectedReservoirs.cs.slang::computeCellOffsets (lines 56-73).
//   InterlockedAdd(globalCounters[kCounterIndexPrefixSum], cellCounter, offset);
//   cellOffsets[index] = offset;
void lt_SortReprojectedReservoirs_compute_cell_offsets(ivec2 pixel)
{
    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return;
    }

    uint cellIndex = uint(pixel.y * viewWidth + pixel.x);
    uint cellCounter = lt_temporal_scatter_cell_counter_value(0u, cellIndex);
    if (cellCounter == 0u) {
        return;
    }
    uint offset = lt_temporal_scatter_global_counter_atomic_add(0u, 1u, cellCounter);
    lt_temporal_scatter_store_cell_offset(0u, cellIndex, offset);
}

// Reference: SortReprojectedReservoirs.cs.slang::sortCellData (lines 79-95).
//   sortedReservoirs[cellOffsets[linearizedIndex] + cellIndex] = prevPixel;
// Photonics matches: a single indirection writes the source pixel into the
// sorted list at the per-cell offset computed by the prefix-sum pass.
void lt_SortReprojectedReservoirs_sort_cell_data(uint scatterIndex)
{
    if (scatterIndex >= lt_temporal_scatter_global_counter_value(0u, 0u)) {
        return;
    }

    uvec2 reservoirIndex = lt_temporal_scatter_load_reservoir_index(0u, scatterIndex);
    uint targetCell      = reservoirIndex.x;
    uint localCellIndex  = reservoirIndex.y;
    uint sortedIndex     = lt_temporal_scatter_cell_offset_value(0u, targetCell) + localCellIndex;
    lt_temporal_scatter_store_sorted_reservoir(0u, sortedIndex, lt_temporal_scatter_load_scattered_reservoir(0u, scatterIndex));
}

void lt_MultiSortReprojectedReservoirs_compute_cell_offsets(ivec2 pixel)
{
    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return;
    }

    uint cellIndex = uint(pixel.y * viewWidth + pixel.x);
    for (uint partitionIndex = 0u; partitionIndex < lt_multi_temporal_partition_count(); ++partitionIndex) {
        uint partitionedCellIndex = lt_temporal_partitioned_cell_index(partitionIndex, cellIndex);
        uint cellCounter = lt_temporal_scatter_cell_counter_value(partitionIndex, partitionedCellIndex);
        if (cellCounter == 0u) {
            continue;
        }
        uint counterIndex = lt_temporal_partitioned_counter_index(partitionIndex, LT_MULTI_TEMPORAL_COUNTER_INDEX_PREFIX_SUM);
        uint offset = lt_temporal_scatter_global_counter_atomic_add(partitionIndex, counterIndex, cellCounter);
        lt_temporal_scatter_store_cell_offset(partitionIndex, partitionedCellIndex, offset);
    }
}

void lt_MultiSortReprojectedReservoirs_sort_cell_data(uint scatterIndex)
{
    for (uint partitionIndex = 0u; partitionIndex < lt_multi_temporal_partition_count(); ++partitionIndex) {
        uint counterIndex = lt_temporal_partitioned_counter_index(partitionIndex, LT_MULTI_TEMPORAL_COUNTER_INDEX_DATA_COUNT);
        uint partitionCount = ph_temporal_scatter_global_counters_data[counterIndex];
        uint partitionCount = lt_temporal_scatter_global_counter_value(partitionIndex, counterIndex);
        if (scatterIndex >= partitionCount) {
            continue;
        }

        uint scatteredBufferIndex = lt_temporal_partitioned_contributor_index(partitionIndex, scatterIndex);
        uvec2 reservoirIndex = lt_temporal_scatter_load_reservoir_index(partitionIndex, scatteredBufferIndex);
        uint cellLinearIndex = reservoirIndex.x;
        uint localCellIndex = reservoirIndex.y;
        uint partitionedCellIndex = lt_temporal_partitioned_cell_index(partitionIndex, cellLinearIndex);
        uint sortedIndex = lt_temporal_scatter_cell_offset_value(partitionIndex, partitionedCellIndex) + localCellIndex;
        uint sortedBufferIndex = lt_temporal_partitioned_contributor_index(partitionIndex, sortedIndex);
        lt_temporal_scatter_store_sorted_reservoir(partitionIndex, sortedBufferIndex, lt_temporal_scatter_load_scattered_reservoir(partitionIndex, scatteredBufferIndex));
    }
}
#endif

// Legacy fused temporal resampling path removed.
// The active implementation is the explicit reprojection -> binning -> scatter stage chain.

// ============================================================================
// Reservoir Splatting: Temporal Pairwise MIS (Liu et al. 2025, Eq 10-13)
// ============================================================================
// Replaces area_resample_reservoir_pairwise_mis for the temporal scatter path.
// Splatting preserves x1 exactly, so we use the sub-pixel Jacobian (Eq 15-16)
// instead of Area ReSTIR's reconnection/random-replay Jacobian.
//
// Parameters:
//   state:              streaming RIS state being accumulated
//   canonicalReservoir: current-frame initial candidate (the canonical sample Y*)
//   canonicalSurface:   G-buffer surface at the current pixel
//   canonicalPixel:     current pixel position
//   candidateReservoir: splatted previous-frame reservoir (ALREADY translated + finalized)
//   candidateSurface:   G-buffer surface from the previous frame at source pixel
//   candidatePixel:     source pixel position in previous frame
//   pHatPrev:           candidate's target PDF in the PREVIOUS frame (saved before finalization)
//   confidenceWeightSum: sum of all M values (canonical + all valid contributors)
//   splatJacobian:      |dT/dX_i| = J_subpixel_current / J_subpixel_prev (Eq 16)
//   rng:                random state
void splat_resample_temporal_pairwise_mis(
    inout RTXDI_DIReservoir state,
    RTXDI_DIReservoir canonicalReservoir,
    RAB_Surface canonicalSurface,
    ivec2 canonicalPixel,
    RTXDI_DIReservoir candidateReservoir,
    RAB_Surface candidateSurface,
    ivec2 candidatePixel,
    float pHatPrev,
    float confidenceWeightSum,
    float candidateNormalization,
    float splatJacobian,
    float supportWeight,
    inout RTXDI_RandomSamplerState rng)
{
    float pHatCurrent = candidateReservoir.targetPdf;  // p_hat(Y_i) - evaluated at current surface after finalization
    float pHatCanonical = canonicalReservoir.targetPdf; // p_hat(Y*) at current surface
    float c_i = max(candidateReservoir.M, 0.0f);    // confidence of splatted candidate
    float c_star = max(canonicalReservoir.M, 1.0f); // confidence of canonical sample

    if (pHatCurrent <= 0.0f || pHatCanonical <= 0.0f || c_i <= 0.0f || candidateReservoir.weightSum <= 0.0f || supportWeight <= 0.0f) {
        return;
    }

    float weightedCandidateConfidence = c_i * supportWeight;
    float weightedCandidateNormalization = candidateNormalization * pHatPrev;

    // --- Eq 11: Non-canonical MIS weight for the splatted sample ---
    float m0Denominator = c_star * pHatCurrent + weightedCandidateNormalization;
    float m0 = (m0Denominator > 0.0f) ? (weightedCandidateNormalization / m0Denominator) : 0.0f;

    // --- Eq 13: Canonical MIS weight contribution ---
    // For the reverse direction: evaluate canonical sample's light at the previous surface.
    // This is the "reverse splat" of Y* to the candidate's previous-frame domain.
    RAB_LightSample canonicalLightAtPrev = lt_decode_reservoir_sample_for_frame(
        canonicalReservoir, candidateSurface, false, true);
    float pHatCanonicalAtPrev = (RAB_IsSurfaceValid(candidateSurface) && canonicalLightAtPrev.index >= 0)
        ? lt_surface_target_pdf(candidateSurface, canonicalLightAtPrev)
        : 0.0;

    float canonicalReverseContribution = weightedCandidateConfidence * pHatCanonicalAtPrev * splatJacobian;
    float m1Denominator = c_star * pHatCanonical + canonicalReverseContribution;
    float m1 = (m1Denominator > 0.0f) ? ((c_star * pHatCanonical) / m1Denominator) : 0.0f;

    // --- Eq 10: Resampling weight ---
    // w_i = m_i * p_hat(Y_i) * W_{X_i} * |J|
    float sampleWeight = m0 * pHatCurrent * candidateReservoir.weightSum * splatJacobian;

    state.M += weightedCandidateConfidence;
    state.weightSum += sampleWeight;
    state.canonicalWeight += m1;

    bool selectSample = (sampleWeight > 0.0 && state.weightSum > 0.0)
        ? (lt_next_random(rng) * state.weightSum < sampleWeight)
        : false;

    if (selectSample) {
        state.targetPdf = pHatCurrent;
        state.lightData = candidateReservoir.lightData;
        state.uvData = candidateReservoir.uvData;
        state.pixelSampleUV = candidateReservoir.pixelSampleUV;
        state.pathSample = candidateReservoir.pathSample;
        state.lensSampleUV = candidateReservoir.lensSampleUV;
        state.packedVisibility = candidateReservoir.packedVisibility;
        state.age = candidateReservoir.age;
        state.spatialDistance = candidateReservoir.spatialDistance;
    }
}

float lt_temporal_proposal_pdf(RTXDI_DIReservoir reservoir, ScatterReconnectionData reconnection) {
    return max(reconnection.lightPdf, 0.0f);
}

float lt_temporal_proposal_weight(RTXDI_DIReservoir reservoir, ScatterReconnectionData reconnection) {
    float proposalPdf = lt_temporal_proposal_pdf(reservoir, reconnection);
    if (proposalPdf <= 0.0f) {
        return 0.0f;
    }

    return 1.0f / proposalPdf;
}

float lt_temporal_candidate_confidence_weight(
    RTXDI_DIReservoir reservoir,
    ScatterReconnectionData reconnection,
    float supportWeight)
{
    // Old confidence amplification kept for reference:
    // return max(reservoir.M, 0.0f)
    //     * max(supportWeight, 0.0f)
    //     * lt_temporal_proposal_weight(reservoir, reconnection);
    float proposalWeight = lt_temporal_proposal_weight(reservoir, reconnection);
    float clampedProposalWeight = clamp(proposalWeight, 0.25f, 4.0f);
    return max(reservoir.M, 0.0f)
        * max(supportWeight, 0.0f)
        * clampedProposalWeight;
}

float lt_temporal_scatter_debug_stage_marker()
{
    return 0.0f;
}

float lt_temporal_proposal_match_weight(
    ScatterReconnectionData canonicalReconnection,
    ScatterReconnectionData candidateReconnection)
{
    // Old hard mismatch penalties kept for reference:
    // float weight = 1.0f;
    // if (canonicalReconnection.proposalFamily != 0u
    //     && candidateReconnection.proposalFamily != 0u
    //     && canonicalReconnection.proposalFamily != candidateReconnection.proposalFamily)
    // {
    //     weight *= 0.2f;
    // }
    // if (canonicalReconnection.pathLength > 0u
    //     && candidateReconnection.pathLength > 0u
    //     && canonicalReconnection.pathLength != candidateReconnection.pathLength)
    // {
    //     weight *= 0.5f;
    // }
    // if (canonicalReconnection.firstBsdfComponentType > 0u
    //     && candidateReconnection.firstBsdfComponentType > 0u
    //     && canonicalReconnection.firstBsdfComponentType != candidateReconnection.firstBsdfComponentType)
    // {
    //     weight *= 0.5f;
    // }
    // if (canonicalReconnection.secondBsdfComponentType > 0u
    //     && candidateReconnection.secondBsdfComponentType > 0u
    //     && canonicalReconnection.secondBsdfComponentType != candidateReconnection.secondBsdfComponentType)
    // {
    //     weight *= 0.5f;
    // }
    // uint sharedFlags = canonicalReconnection.flags & candidateReconnection.flags;
    // uint combinedFlags = canonicalReconnection.flags | candidateReconnection.flags;
    // if (combinedFlags != 0u && sharedFlags == 0u) {
    //     weight *= 0.35f;
    // }

    float weight = 1.0f;
    float lightPdfA = max(canonicalReconnection.lightPdf, 0.0f);
    float lightPdfB = max(candidateReconnection.lightPdf, 0.0f);
    if (lightPdfA > 0.0f && lightPdfB > 0.0f) {
        float pdfRatio = max(lightPdfA, lightPdfB) / max(min(lightPdfA, lightPdfB), 1e-6f);
        weight *= clamp(1.0f / sqrt(pdfRatio), 0.35f, 1.0f);
    }

    return clamp(weight, 0.0f, 1.0f);
}

float lt_temporal_scatter_support_denominator(
    ivec2 basePixel,
    vec2 frac,
    ScatterReconnectionData sourceReconnection,
    RAB_Surface sourcePrevSurface,
    RTXDI_DIReservoir sourcePrevReservoir,
    vec3 prevCameraPos,
    vec3 prevCameraForward)
{
#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
    return 0.0f;
#else
    float denominator = 0.0f;
    vec3 currCameraForward = normalize(mat3(gbufferModelView) * vec3(0.0f, 0.0f, -1.0f));
    float sourceProposalWeight = lt_temporal_proposal_weight(sourcePrevReservoir, sourceReconnection);

    for (int dy = 0; dy <= 1; ++dy) {
        for (int dx = 0; dx <= 1; ++dx) {
            ivec2 neighborPixel = basePixel + ivec2(dx, dy);
            if (!lt_is_viewport_uv_in_bounds(neighborPixel)) {
                continue;
            }

            float bilinearWeight = lt_scatter_bilinear_weight(frac, dx, dy);
            if (bilinearWeight <= 1e-5f) {
                continue;
            }

            RAB_Surface neighborSurface = RAB_GetGBufferSurface(neighborPixel, false);
            if (!RAB_IsSurfaceValid(neighborSurface)) {
                continue;
            }

            if (!lt_area_is_surface_neighbor_valid(neighborSurface, sourcePrevSurface)) {
                continue;
            }

            RTXDI_DIReservoir shiftedNeighbor = lt_translate_reservoir_between_frames(sourcePrevReservoir, true, false);
            if (!RTXDI_IsValidDIReservoir(shiftedNeighbor)) {
                continue;
            }

            lt_area_finalize_candidate(shiftedNeighbor, neighborPixel, shiftedNeighbor.pathSample);
            RAB_LightSample shiftedLight = lt_decode_reservoir_sample_for_frame(
                shiftedNeighbor, neighborSurface, false, false);
            float pHatNeighbor = lt_surface_target_pdf(neighborSurface, shiftedLight);
            if (pHatNeighbor <= 0.0f) {
                continue;
            }

            float jPrev = scatter_resolve_stored_subpixel_jacobian(
                sourceReconnection, sourcePrevSurface, prevCameraPos, prevCameraForward);
            float jCurr = scatter_compute_subpixel_jacobian(
                neighborSurface.worldPos, neighborSurface.geoNormal, world_camera_position, currCameraForward);
            float supportJacobian = scatter_compute_scatter_jacobian(
                jPrev,
                jCurr,
                scatter_resolve_stored_secondary_jacobian(sourceReconnection),
                1.0f
            );
            float invSupportJ = (supportJacobian > 1e-8f) ? (1.0f / supportJacobian) : 0.0f;

            denominator += bilinearWeight * sourcePrevReservoir.M * sourceProposalWeight * invSupportJ;
        }
    }

    return denominator;
#endif
}


#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)
#include "/photonics/lighttree/restir_di_temporal.glsl"
// Direct port of ``ReprojectTemporalSamples::run`` (lines 60-175 in the reference).
//
//   1. Load previous reservoir at ``pixel`` (pixel-linearized index).
//   2. Bail if the previous reservoir carries zero integrand / is invalid.
//   3. Load previous reconnection sidecar.
//   4. Forward-project the stored ``worldPos`` through the current-frame
//      view-projection. This is the photonics analogue of the reference
//      "rotate the camera to ``prevReconnection.time`` then cast a ray"
//      sequence — we collapse it to a single matrix projection because
//      Minecraft has no sub-frame motion-blur time sample and uses a pinhole
//      camera (no lens aperture). ``scatter_forward_project_to_current_frame``
//      already handles behind-camera rejection and view bounds.
//   5. Validate surface compatibility against the previous reconnection
//      (paper §4.1.2 — target-domain reconnection test).
//   6. Atomically append ``(cellIndex, localCellIndex)`` and the source pixel
//      to the scatter tables, exactly like the reference InterlockedAdd pair.
//
// Per the reference there is exactly one scatter contributor per source
// reservoir (``scatteredReservoirs[index] = pixel``). Earlier drafts of this
// port splatted bilinearly across four neighbours with extra weight buffers;
// that is removed here to match the reference structure.
#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)
float lt_multi_temporal_reproject_partition(
    ScatterReconnectionData prevReconnection,
    uint partitionIndex,
    out vec2 newFractionalPixel,
    out bool hitValid,
    out vec3 rayDirection)
{
    float fractionalTime = lt_multi_temporal_partition_fraction(prevReconnection.time);
    float newTime = lt_multi_temporal_partition_time(fractionalTime, partitionIndex);
    hitValid = prevReconnection.firstHit.viewDepth > 0.0f
        && any(greaterThan(abs(prevReconnection.firstHit.worldPos), vec3(0.0f)));

    if (hitValid) {
        rayDirection = prevReconnection.firstHit.worldPos - world_camera_position;
        newFractionalPixel = scatter_forward_project_to_current_frame(prevReconnection.firstHit.worldPos);
        return newTime;
    }

    if (prevReconnection.lightIsDistant) {
        rayDirection = -prevReconnection.firstWi;
        vec3 farPoint = world_camera_position + rayDirection * 1e5f;
        newFractionalPixel = scatter_forward_project_to_current_frame(farPoint);
        return newTime;
    }

    rayDirection = vec3(0.0f);
    newFractionalPixel = vec2(-1.0f);
    return newTime;
}

void lt_di_multi_reproject_temporal_samples_stage(
    ivec2 pixel)
{
    if (ph_scatter_temporal_enabled <= 0.5f || ph_debug_enable_direct_temporal_reuse < 0.5f) {
        return;
    }

    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return;
    }

    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel)
    );
    if (!RTXDI_IsValidDIReservoir(prevReservoir)) {
        return;
    }

    ScatterReconnectionData prevReconnection = scatter_load_prev_reconnection(pixel);
    RAB_Surface prevSurface = lt_load_previous_surface(pixel);
    for (uint partitionIndex = 0u; partitionIndex < lt_multi_temporal_partition_count(); ++partitionIndex) {
        vec2 newFractionalPixel;
        bool hitValid;
        vec3 rayDirection;
        float newTime = lt_multi_temporal_reproject_partition(
            prevReconnection,
            partitionIndex,
            newFractionalPixel,
            hitValid,
            rayDirection
        );
        if (newFractionalPixel.x < 0.0f || newFractionalPixel.y < 0.0f) {
            continue;
        }

        ivec2 newPixel = ivec2(floor(newFractionalPixel));
        if (!lt_is_viewport_uv_in_bounds(newPixel)) {
            continue;
        }

        vec3 normalizedRayDirection = normalize(rayDirection);
        vec3 cameraForward = normalize(mat3(gbufferModelView) * vec3(0.0f, 0.0f, -1.0f));
        float cameraFacing = dot(normalizedRayDirection, cameraForward);
        if (cameraFacing <= 0.001f) {
            continue;
        }

        RAB_Surface currentSurface = RAB_GetGBufferSurface(newPixel, false);
        if (!RAB_IsSurfaceValid(currentSurface)) {
            continue;
        }

        ScatterReconnectionData partitionedReconnection = prevReconnection;
        partitionedReconnection.time = newTime;
        if (hitValid) {
            if (!lt_area_is_temporal_neighbor_valid(currentSurface, prevSurface, partitionedReconnection, newPixel)) {
                continue;
            }
        } else if (!partitionedReconnection.lightIsDistant) {
            continue;
        }

        lt_multi_temporal_scatter_append_contributor(partitionIndex, newPixel, pixel);
    }
}
#endif

void lt_di_reproject_temporal_samples_stage(
    ivec2 pixel)
{
    if (ph_scatter_temporal_enabled <= 0.5f || ph_debug_enable_direct_temporal_reuse < 0.5f) {
        return;
    }

    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return;
    }

    // ReprojectTemporalSamples.rt.slang:70-76 — load prev reservoir, reject empty.
    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel)
    );
    if (!RTXDI_IsValidDIReservoir(prevReservoir)) {
        return;
    }

    // ReprojectTemporalSamples.rt.slang:78 — prev reconnection sidecar.
    ScatterReconnectionData prevReconnection = scatter_load_prev_reconnection(pixel);

    // ReprojectTemporalSamples.rt.slang:81-152 — determine the fractional pixel
    // the stored primary hit projects to in the current frame.
    vec2 newFractionalPixel = scatter_forward_project_to_current_frame(prevReconnection.firstHit.worldPos);
    if (newFractionalPixel.x < 0.0f || newFractionalPixel.y < 0.0f) {
        return;
    }

    ivec2 newPixel = ivec2(floor(newFractionalPixel));
    if (!lt_is_viewport_uv_in_bounds(newPixel)) {
        return;
    }

    // ReprojectTemporalSamples.rt.slang:139-143 — visibility test.
    vec3 rayOrigin = world_camera_position;
    vec3 rayDirection = normalize(prevReconnection.firstHit.worldPos - rayOrigin);
    float traceDistance = length(prevReconnection.firstHit.worldPos - rayOrigin);
    if (traceDistance <= 1e-5f) {
        return;
    }

    ray.origin = rayOrigin;
    ray.direction = rayDirection;
    ray_target = ivec3(floor(prevReconnection.firstHit.worldPos));
    ray_ignore_block_id = -1;
    ray_stop_on_target = true;
    ray_min_trace_distance = 0.001f * traceDistance;
    ray_max_trace_distance = max(ray_min_trace_distance, 0.999f * traceDistance);
    trace_ray(ray, true);
    ray_target = ivec3(-9999);
    ray_ignore_block_id = -1;
    ray_stop_on_target = false;
    ray_min_trace_distance = 0.0f;
    ray_max_trace_distance = -1.0f;
    if (!lt_visibility_trace_is_unoccluded()) {
        return;
    }

    // ReprojectTemporalSamples.rt.slang:167-174 — atomic append to the scatter
    // tables. Weight stays uniform across scattered samples (the reference
    // does not store per-splat weights), so we call the single-pixel variant.
    lt_temporal_scatter_append_contributor(newPixel, pixel, 1.0f);
}

#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY)
void lt_di_compute_temporal_cell_offsets_stage(
    ivec2 pixel)
{
    if (ph_scatter_temporal_enabled <= 0.5f) {
        return;
    }

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
    return;
#else
    lt_SortReprojectedReservoirs_compute_cell_offsets(pixel);
#endif
}
#else
void lt_di_compute_temporal_cell_offsets_stage(
    ivec2 pixel)
{
}
#endif

#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
void lt_di_sort_temporal_reprojected_reservoirs_stage(
    uint index)
{
    if (ph_scatter_temporal_enabled <= 0.5f) {
        return;
    }

    lt_SortReprojectedReservoirs_sort_cell_data(index);
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
RTXDI_DIReservoir lt_di_scatter_temporal_resampling_stage(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    currReconnectionData = ReservoirSplattingReconnectionData_init();
    return RTXDI_EmptyDIReservoir();
}
#else
// =============================================================================
// Stage 2e — ScatterTemporalResampling (reference ScatterTemporalResampling.rt.slang)
// =============================================================================
// Port of ``ScatterTemporalResampling::run`` (lines 64-174 in the reference).
//
// For each pixel:
//   1. Consider the current-frame canonical sample (loaded from the initial
//      sampling output).
//   2. Shift it forward to the *previous* frame domain, compute pairwise-MIS
//      m_1 (self) and m_2 (prev-frame reservoir at the shifted pixel) and
//      stream it into the destination reservoir.
//   3. Iterate the scattered reservoirs landed in this cell by the Reproject
//      stage (``sortedReservoirs[cellOffsets[idx] + i]``), shift each to the
//      current domain, update their reconnection, and stream them in.
//   4. Recompute ``dstReservoir.confidence`` using a bilinear-weighted
//      history of the previous reservoirs hit by the current motion vector
//      (paper §3.3 Area ReSTIR confidence cap is preserved in the helper).
//   5. Store the resulting reservoir + reconnection as the stage output.
RTXDI_DIReservoir lt_di_scatter_temporal_resampling_stage(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    currReconnectionData = ReservoirSplattingReconnectionData_init();

    if (ph_scatter_temporal_enabled <= 0.5f || ph_debug_enable_direct_temporal_reuse < 0.5f) {
        return RTXDI_EmptyDIReservoir();
    }

    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);
    if (!lt_is_viewport_uv_in_bounds(pixel) || !RAB_IsSurfaceValid(surface)) {
        return RTXDI_EmptyDIReservoir();
    }

    RTXDI_RandomSamplerState sg = lt_init_random_sampler(
        uvec2(pixel),
        uint(frameCounter),
        5u
    );

    // ScatterTemporalResampling.rt.slang:75-79 — load canonical sample.
    uint reservoirIdx = uint(pixel.y * viewWidth + pixel.x);
    RTXDI_DIReservoir currReservoir = lt_current_reservoir_at_pixel(pixel);
    LtScatterCurrentSample currSample = lt_ScatterTemporalResampling_load_current_sample(
        reservoirIdx,
        pixel,
        surface,
        currReservoir
    );

    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    ReservoirSplattingReconnectionData dstReconnectionData = ReservoirSplattingReconnectionData_init();
    ReservoirSplattingReconnectionData currReconnectionDataLocal = currSample.reconnectionData;
    vec3  currIntegrand            = currSample.isValid ? scatter_reconnection_integrand(currReconnectionDataLocal) : vec3(0.0f);
    float currReservoirConfidence  = currSample.confidence;
    float currUCW                  = currSample.isValid ? lt_scatter_compute_ucw(currReservoir, currIntegrand) : 0.0f;

    // ScatterTemporalResampling.rt.slang:81-104 — canonical MIS.
    float currSampleMIS = ScatterTemporalResampling_compute_curr_sample_mis(
        currSample,
        pixel,
        surface
    );
    bool currSelected = lt_scatter_add_sample_from_reservoir(
        dstReservoir,
        dstReservoir.M,
        currSampleMIS,
        currIntegrand,
        1.0f,
        currUCW,
        currReservoirConfidence,
        currReservoir,
        sg
    );
    dstReconnectionData = currSelected ? currReconnectionDataLocal : dstReconnectionData;

    // ScatterTemporalResampling.rt.slang:110 — track confidence AFTER canonical.
    float newConfidence = dstReservoir.M;

    // ScatterTemporalResampling.rt.slang:112-147 — direct cell traversal.
    uint numReservoirs = lt_temporal_scatter_cell_counter_value(0u, reservoirIdx);
    uint cellOffset = lt_temporal_scatter_cell_offset_value(0u, reservoirIdx);
    for (uint i = 0u; i < numReservoirs; ++i) {
        ivec2 scatteredPixel = ivec2(lt_temporal_scatter_load_sorted_reservoir(0u, cellOffset + i));
        ScatterTemporalResampling_process_contributor(
            dstReservoir,
            dstReconnectionData,
            newConfidence,
            scatteredPixel,
            pixel,
            currReservoir,
            currReconnectionDataLocal,
            currReservoirConfidence,
            sg
        );
    }

    dstReservoir.M = ScatterTemporalResampling_motion_vector_confidence(pixel, newConfidence);
    // PathReservoir.confidence in the reference lives on RTXDI_DIReservoir.M
    // in Photonics; no sidecar write is necessary.
    currReconnectionData = dstReconnectionData;
    return dstReservoir;
}

bool lt_multi_scatter_process_contributor(
    inout RTXDI_DIReservoir dstReservoir,
    inout ReservoirSplattingReconnectionData dstReconnectionData,
    ivec2 scatteredPixel,
    ivec2 resolvePixel,
    uint partitionIndex,
    RTXDI_DIReservoir currReservoir,
    ScatterReconnectionData currReconnection,
    float currReservoirConfidence,
    inout RTXDI_RandomSamplerState sg)
{
    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(scatteredPixel)
    );
    if (!RTXDI_IsValidDIReservoir(prevReservoir)) {
        return false;
    }

    ScatterReconnectionData prevReconnection = scatter_load_prev_reconnection(scatteredPixel);
    RAB_Surface targetSurface = RAB_GetGBufferSurface(resolvePixel, false);
    LtScatterShiftedPath shiftedPrev;
    RTXDI_DIReservoir shiftedReservoir;
    ScatterReconnectionData shiftedReconnection;
    float shiftedJacobian;
    if (!lt_scatter_update_shifted_reservoir(
            prevReconnection,
            prevReservoir,
            true,
            false,
            targetSurface,
            resolvePixel,
            shiftedPrev,
            shiftedReservoir,
            shiftedReconnection,
            shiftedJacobian)) {
        return false;
    }

    float prevMIS = 0.0f;
    if (any(prevReservoir.integrand > vec3(0.0f))) {
        float m1 = lt_scatter_radiance_phat(shiftedPrev.radiance)
            * shiftedJacobian
            * currReservoirConfidence;
        float m2 = lt_scatter_radiance_phat(prevReservoir.integrand)
            * lt_scatter_reservoir_confidence(prevReservoir, prevReconnection);
        if ((m1 + m2) > 0.0f) {
            prevMIS = m2 / (m1 + m2);
        }
    }

    bool prevSelected = lt_scatter_add_sample_from_reservoir(
        dstReservoir,
        dstReservoir.M,
        prevMIS,
        shiftedPrev.radiance,
        shiftedJacobian * (1.0f / float(lt_multi_temporal_partition_count())),
        lt_scatter_compute_ucw(shiftedReservoir, shiftedPrev.radiance),
        lt_scatter_reservoir_confidence(prevReservoir, prevReconnection),
        shiftedReservoir,
        sg
    );
    if (prevSelected) {
        float timePartitions = 1.0f / float(lt_multi_temporal_partition_count());
        float fractionalTime = clamp(prevReconnection.time, 0.0f, 1.0f);
        shiftedReconnection.time = (fractionalTime + float(partitionIndex)) * timePartitions;
        shiftedReconnection.subPixel = clamp(shiftedPrev.fractionalPixel - floor(shiftedPrev.fractionalPixel), vec2(0.0f), vec2(1.0f));
        dstReconnectionData = shiftedReconnection;
    }
    return prevSelected;
}

void lt_di_multi_compute_temporal_cell_offsets_stage(
    ivec2 pixel)
{
#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
    if (ph_scatter_temporal_enabled > 0.5f) {
        lt_MultiSortReprojectedReservoirs_compute_cell_offsets(pixel);
    }
#endif
}

void lt_di_multi_sort_temporal_reprojected_reservoirs_stage(
    uint index)
{
#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
    if (ph_scatter_temporal_enabled > 0.5f) {
        lt_MultiSortReprojectedReservoirs_sort_cell_data(index);
    }
#endif
}

RTXDI_DIReservoir lt_di_scatter_backup_temporal_resampling_stage(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    currReconnectionData = ReservoirSplattingReconnectionData_init();

    if (ph_scatter_temporal_enabled <= 0.5f || ph_debug_enable_direct_temporal_reuse < 0.5f) {
        return RTXDI_EmptyDIReservoir();
    }

    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);
    if (!lt_is_viewport_uv_in_bounds(pixel) || !RAB_IsSurfaceValid(surface)) {
        return RTXDI_EmptyDIReservoir();
    }

    RTXDI_RandomSamplerState sg = lt_init_random_sampler(
        uvec2(pixel),
        uint(frameCounter),
        6u
    );

    uint reservoirIdx = uint(pixel.y * viewWidth + pixel.x);
    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    ReservoirSplattingReconnectionData dstReconnectionData = ReservoirSplattingReconnectionData_init();

    RTXDI_DIReservoir currReservoir = lt_current_reservoir_at_pixel(pixel);
    LtScatterCurrentSample currSample = lt_ScatterTemporalResampling_load_current_sample(
        reservoirIdx,
        pixel,
        surface,
        currReservoir
    );

    RTXDI_DIReservoir backupReservoir = RTXDI_LoadDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel),
        lt_build_restir_di_parameters().bufferIndices.temporalResamplingOutputBufferIndex
    );
    ReservoirSplattingReconnectionData backupReconnectionData = scatter_load_gather_intermediate_reconnection(pixel);

    // We first consider the current reservoir (the initial sample).
    {
        float currSampleMIS = 1.0f;
        if (currSample.isValid && currSample.hasPositivePHat) {
            float m1 = lt_scatter_radiance_phat(currSample.reconnectionData.integrand)
                * currSample.confidence;

            float m2 = 0.0f;
            LtScatterShiftedPath scatteredCurr;
            RTXDI_DIReservoir shiftedCurrReservoir;
            ScatterReconnectionData shiftedCurrReconnectionData;
            float scatteredJacobian;
            if (lt_scatter_update_shifted_reservoir(
                    currSample.reconnectionData,
                    currSample.reservoir,
                    false,
                    true,
                    surface,
                    pixel,
                    scatteredCurr,
                    shiftedCurrReservoir,
                    shiftedCurrReconnectionData,
                    scatteredJacobian)) {
                ivec2 scatteredPixel = ivec2(floor(scatteredCurr.fractionalPixel));
                if (lt_is_viewport_uv_in_bounds(scatteredPixel)) {
                    float prevReservoirConfidence = ScatterTemporalResampling_load_previous_reservoir_confidence(scatteredPixel);
                    m2 = lt_scatter_radiance_phat(scatteredCurr.radiance)
                        * scatteredJacobian
                        * 0.5f
                        * prevReservoirConfidence;
                    m2 = (isnan(m2) || isinf(m2)) ? 0.0f : m2;
                }
            }

            float m3 = 0.0f;
            vec2 floatingCoord = scatter_load_gather_floating_coords(pixel);
            if (lt_is_viewport_uv_in_bounds(ivec2(floor(floatingCoord)))
                && all(greaterThanEqual(floatingCoord, vec2(0.0f)))
                && all(lessThan(floatingCoord, vec2(viewWidth, viewHeight)))) {
                ShiftedPathData shiftedCurr = gatherLensVertexCopyShift(
                    sg,
                    currSample.reconnectionData,
                    currSample.reconnectionData.time,
                    floatingCoord + currReservoir.pixelSampleUV,
                    currSample.reconnectionData.lensSample
                );
                float shiftedJacobian = shiftedCurr.secondaryPathJacobian
                    / max(currSample.reconnectionData.secondaryPathJacobian, 1e-10f);
                float backupReservoirConfidence = lt_scatter_reservoir_confidence(backupReservoir, backupReconnectionData);
                m3 = lt_scatter_radiance_phat(shiftedCurr.radiance)
                    * shiftedJacobian
                    * 0.5f
                    * backupReservoirConfidence;
                m3 = (isnan(m3) || isinf(m3)) ? 0.0f : m3;
            }

            float denominator = m1 + m2 + m3;
            currSampleMIS = (denominator > 0.0f) ? (m1 / denominator) : 0.0f;
        }

        bool currSelected = lt_scatter_add_sample_from_reservoir(
            dstReservoir,
            dstReservoir.M,
            currSampleMIS,
            currSample.reconnectionData.integrand,
            1.0f,
            currSample.isValid ? lt_scatter_compute_ucw(currSample.reservoir, currSample.reconnectionData.integrand) : 0.0f,
            currSample.confidence,
            currSample.reservoir,
            sg
        );
        dstReconnectionData = currSelected ? currSample.reconnectionData : dstReconnectionData;
    }

    // Next, consider the backup sample.
    {
        float backupSampleMIS = 0.0f;
        vec3 backupPHat = vec3(0.0f);
        float shiftedJacobian = 1.0f;
        if (RTXDI_IsValidDIReservoir(backupReservoir) && any(greaterThan(backupReservoir.integrand, vec3(0.0f)))) {
            ShiftedPathData shiftedBackup = gatherLensVertexCopyShift(
                sg,
                backupReconnectionData,
                backupReconnectionData.time,
                vec2(pixel) + backupReservoir.pixelSampleUV,
                backupReconnectionData.lensSample
            );
            shiftedJacobian = shiftedBackup.secondaryPathJacobian
                / max(backupReconnectionData.secondaryPathJacobian, 1e-10f);
            float m1 = lt_scatter_radiance_phat(shiftedBackup.radiance)
                * shiftedJacobian
                * currSample.confidence;
            backupPHat = (isnan(m1) || isinf(m1)) ? vec3(0.0f) : max(shiftedBackup.radiance, vec3(0.0f));
            shiftedJacobian = (isnan(m1) || isinf(m1)) ? 1.0f : shiftedJacobian;
            m1 = (isnan(m1) || isinf(m1)) ? 0.0f : m1;

            backupReconnectionData = ReconnectionData_update(backupReconnectionData, shiftedBackup);

            float m2 = 0.0f;
            LtScatterShiftedPath scatteredBackup;
            RTXDI_DIReservoir shiftedBackupReservoir;
            ScatterReconnectionData shiftedBackupReconnectionData;
            float scatteredJacobian;
            if (lt_scatter_update_shifted_reservoir(
                    backupReconnectionData,
                    backupReservoir,
                    false,
                    true,
                    surface,
                    pixel,
                    scatteredBackup,
                    shiftedBackupReservoir,
                    shiftedBackupReconnectionData,
                    scatteredJacobian)) {
                ivec2 scatteredPixel = ivec2(floor(scatteredBackup.fractionalPixel));
                if (lt_is_viewport_uv_in_bounds(scatteredPixel)) {
                    float prevReservoirConfidence = ScatterTemporalResampling_load_previous_reservoir_confidence(scatteredPixel);
                    m2 = lt_scatter_radiance_phat(scatteredBackup.radiance)
                        * scatteredJacobian
                        * shiftedJacobian
                        * 0.5f
                        * prevReservoirConfidence;
                    m2 = (isnan(m2) || isinf(m2)) ? 0.0f : m2;
                }
            }

            float backupReservoirConfidence = lt_scatter_reservoir_confidence(backupReservoir, backupReconnectionData);
            float m3 = lt_scatter_radiance_phat(backupReservoir.integrand)
                * 0.5f
                * backupReservoirConfidence;
            float denominator = m1 + m2 + m3;
            backupSampleMIS = (denominator > 0.0f) ? (m3 / denominator) : 0.0f;
        }

        bool backupSelected = lt_scatter_add_sample_from_reservoir(
            dstReservoir,
            dstReservoir.M,
            backupSampleMIS,
            backupPHat,
            shiftedJacobian,
            lt_scatter_compute_ucw(backupReservoir, backupReservoir.integrand),
            lt_scatter_reservoir_confidence(backupReservoir, backupReconnectionData),
            backupReservoir,
            sg
        );
        dstReconnectionData = backupSelected ? backupReconnectionData : dstReconnectionData;
    }

    float newConfidence = dstReservoir.M;

    // Lastly, consider the scattered reservoirs from the previous frame.
    uint numReservoirs = lt_temporal_scatter_cell_counter_value(0u, reservoirIdx);
    uint cellOffset = lt_temporal_scatter_cell_offset_value(0u, reservoirIdx);
    for (uint i = 0u; i < numReservoirs; ++i) {
        ivec2 scatteredPixel = ivec2(lt_temporal_scatter_load_sorted_reservoir(0u, cellOffset + i));
        ScatterTemporalResampling_process_contributor(
            dstReservoir,
            dstReconnectionData,
            newConfidence,
            scatteredPixel,
            pixel,
            currSample.reservoir,
            currSample.reconnectionData,
            currSample.confidence,
            sg
        );
    }

    dstReservoir.M = ScatterTemporalResampling_motion_vector_confidence(pixel, newConfidence);
    currReconnectionData = dstReconnectionData;
    return dstReservoir;
}

RTXDI_DIReservoir lt_di_multi_scatter_temporal_resampling_stage(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    currReconnectionData = ReservoirSplattingReconnectionData_init();
    if (ph_scatter_temporal_enabled <= 0.5f || ph_debug_enable_direct_temporal_reuse < 0.5f) {
        return RTXDI_EmptyDIReservoir();
    }

    RAB_Surface surface = RAB_GetGBufferSurface(pixel, false);
    if (!lt_is_viewport_uv_in_bounds(pixel) || !RAB_IsSurfaceValid(surface)) {
        return RTXDI_EmptyDIReservoir();
    }

    RTXDI_RandomSamplerState sg = lt_init_random_sampler(uvec2(pixel), uint(frameCounter), 5u);
    uint reservoirIdx = uint(pixel.y * viewWidth + pixel.x);
    RTXDI_DIReservoir currReservoir = lt_current_reservoir_at_pixel(pixel);
    LtScatterCurrentSample currSample = lt_ScatterTemporalResampling_load_current_sample(
        reservoirIdx,
        pixel,
        surface,
        currReservoir
    );

    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    ReservoirSplattingReconnectionData dstReconnectionData = ReservoirSplattingReconnectionData_init();

    // We first consider the current reservoir (the initial sample).
    {
        float currSampleMIS = ScatterTemporalResampling_compute_curr_sample_mis(
            currSample,
            pixel,
            surface
        );
        bool currSelected = lt_scatter_add_sample_from_reservoir(
            dstReservoir,
            dstReservoir.M,
            currSampleMIS,
            currSample.reconnectionData.integrand,
            1.0f,
            currSample.isValid ? lt_scatter_compute_ucw(currSample.reservoir, currSample.reconnectionData.integrand) : 0.0f,
            currSample.confidence,
            currSample.reservoir,
            sg
        );
        dstReconnectionData = currSelected ? currSample.reconnectionData : dstReconnectionData;
    }

    float newConfidence = dstReservoir.M;

    // Next, consider the scattered reservoirs from the previous frame.
    for (uint partitionIndex = 0u; partitionIndex < lt_multi_temporal_partition_count(); ++partitionIndex) {
        uint partitionedCellIndex = lt_temporal_partitioned_cell_index(partitionIndex, reservoirIdx);
        uint numReservoirs = lt_temporal_scatter_cell_counter_value(partitionIndex, partitionedCellIndex);
        uint cellOffset = lt_temporal_scatter_cell_offset_value(partitionIndex, partitionedCellIndex);

        for (uint i = 0u; i < numReservoirs; ++i) {
            uint sortedBufferIndex = lt_temporal_partitioned_contributor_index(partitionIndex, cellOffset + i);
            ivec2 scatteredPixel = ivec2(lt_temporal_scatter_load_sorted_reservoir(partitionIndex, sortedBufferIndex));
            bool prevSelected = lt_multi_scatter_process_contributor(
                dstReservoir,
                dstReconnectionData,
                scatteredPixel,
                pixel,
                partitionIndex,
                currSample.reservoir,
                currSample.reconnectionData,
                currSample.confidence,
                sg
            );
            newConfidence = prevSelected ? dstReservoir.M : newConfidence;
        }
    }

    dstReservoir.M = ScatterTemporalResampling_motion_vector_confidence(pixel, newConfidence);
    currReconnectionData = dstReconnectionData;
    return dstReservoir;
}

struct RTXDI_InitialSamplingMisData {
    int numMisSamples;              // total candidates across all techniques
    float localLightMisWeight;      // fraction of candidates from local-light sampling
    float environmentMapMisWeight;  // fraction of candidates from environment sampling
    float brdfMisWeight;            // fraction of candidates from BRDF sampling
};

RTXDI_DIReservoir RTXDI_SampleLocalLights(
    inout RTXDI_RandomSamplerState rng,
    inout RTXDI_RandomSamplerState coherentRng,
    RAB_Surface surface,
    RTXDI_DIInitialSamplingParameters initialSamplingParams,
    out RAB_LightSample o_selectedSample);

RTXDI_DIReservoir RTXDI_SampleInfiniteLights(RAB_Surface surface, int numSamples);
RTXDI_DIReservoir RTXDI_SampleEnvironmentMap(RAB_Surface surface, int numSamples);
RTXDI_DIReservoir RTXDI_SampleBrdf(inout RTXDI_RandomSamplerState rng, RAB_Surface surface, int numSamples, RTXDI_InitialSamplingMisData misData, float brdfCutoff, out RAB_LightSample o_selectedSample);
RTXDI_DIReservoir RTXDI_SampleLightsForSurface(
    inout RTXDI_RandomSamplerState rng,
    inout RTXDI_RandomSamplerState coherentRng,
    RAB_Surface surface,
    RTXDI_DIInitialSamplingParameters initialSamplingParams,
    out RAB_LightSample o_lightSample);

bool RAB_SurfaceImportanceSampleBrdf(RAB_Surface surface, inout RTXDI_RandomSamplerState rng, out vec3 dir);
float RAB_SurfaceEvaluateBrdfPdf(RAB_Surface surface, vec3 lightDir);
float RTXDI_BrdfMaxDistanceFromPdf(float brdfCutoff, float pdf);

// Tracks per-technique sample counts and their MIS weights for blended source PDF computation.
// Defined here so RTXDI_LightBrdfMisWeight and rtxdi_stream_local_light can reference it.

bool lt_bridge_supports_environment_sampling() {
    return false;
}

int lt_resolve_initial_num_environment_samples() {
    if (!lt_bridge_supports_environment_sampling()) {
        return 0;
    }

    return (ph_restir_initial_num_environment_samples > 0.0)
        ? int(ph_restir_initial_num_environment_samples)
        : (ph_restir_initial_num_environment_samples < -0.5 ? 0 : 1);
}

bool lt_bridge_supports_brdf_local_light_replay() {
    // RTXDI BRDF initial sampling expects the bridge to replay the exact local-light
    // sample hit by RAB_TraceRayForLocalLight through RAB_SamplePolymorphicLight.
    // The current Minecraft bridge still models block emitters as analytic point lights,
    // so traced BRDF hits cannot be replayed faithfully. Keep BRDF initial sampling off
    // until the bridge can provide exact local-light replay semantics.
    return false;
}

int lt_resolve_initial_num_brdf_samples() {
    if (!lt_bridge_supports_brdf_local_light_replay()) {
        return 0;
    }

    return (ph_restir_initial_num_brdf_samples > 0.0)
        ? int(ph_restir_initial_num_brdf_samples)
        : (ph_restir_initial_num_brdf_samples < -0.5 ? 0 : 1);
}

// RTXDI: RTXDI_LightBrdfMisWeight (InitialSampling.hlsli:66-96)
// Computes the blended source PDF that mixes the light-selection PDF with the BRDF PDF
// using a balance-heuristic MIS weight.
float RTXDI_LightBrdfMisWeight(
    RAB_Surface surface,
    RAB_LightSample lightSample,
    float lightSelectionPdf,
    float lightMisWeight,
    float brdfMisWeight,
    float brdfCutoff
) {
    float lightSolidAnglePdf = lightSample.solidAnglePdf;

    // RTXDI InitialSampling.hlsli:71-76: skip BRDF blend when:
    //   - brdfMisWeight == 0 (no BRDF samples counted)
    //   - analytic light sample
    //   - degenerate solid-angle PDF (<= 0, isinf, or nan)
    if (brdfMisWeight == 0.0
        || rtxdi_is_analytic_light_sample(lightSample)
        || lightSolidAnglePdf <= 0.0
        || isinf(lightSolidAnglePdf)
        || isnan(lightSolidAnglePdf)) {
        return lightMisWeight * lightSelectionPdf;
    }

    // RTXDI InitialSampling.hlsli:78-86: evaluate BRDF PDF and apply MIS distance cutoff.
    float brdfPdf = RAB_SurfaceEvaluateBrdfPdf(surface, lightSample.dir);
    float maxDistance = RTXDI_BrdfMaxDistanceFromPdf(brdfCutoff, brdfPdf);
    float lightDistance = length(lightSample.position - lt_surface_rt_pos(surface));
    if (lightDistance > maxDistance) {
        brdfPdf = 0.0;
    }

    // RTXDI InitialSampling.hlsli:88-95: convert selection PDF to solid-angle domain,
    // blend with BRDF PDF, then convert back to selection-PDF domain.
    float sourcePdfWrtSolidAngle = lightSelectionPdf * lightSolidAnglePdf;
    float blendedPdfWrtSolidAngle = lightMisWeight * sourcePdfWrtSolidAngle + brdfMisWeight * brdfPdf;
    return blendedPdfWrtSolidAngle / lightSolidAnglePdf;
}

// RTXDI: RTXDI_StreamLocalLightAtUVIntoReservoir (InitialSampling.hlsli:110-139)
// Streams a single local-light candidate into the reservoir using BRDF-blended MIS source PDF.
// Pass misData to activate BRDF participation (Fix 1); brdfCutoff comes from the uniform.
void rtxdi_stream_local_light(
    inout RTXDI_DIReservoir reservoir,
    RAB_Surface surface,
    Light light,
    float sourcePdf,
    RTXDI_InitialSamplingMisData misData,
    float brdfCutoff
) {
    if (light.index < 0 || light.index >= ph_light_count || sourcePdf <= 0.0) {
        return;
    }

    vec2 sampleUv = vec2(rand_next_float(), rand_next_float());
    vec3 sampledPosition = lt_sample_light_position_from_uv(light, sampleUv, lt_surface_ray_origin(lt_surface_rt_pos(surface), surface.geoNormal));
    RAB_LightSample smple = light_sample_new_at_position(light, sampledPosition, surface);

    float blendedSourcePdf = RTXDI_LightBrdfMisWeight(
        surface, smple, sourcePdf,
        misData.localLightMisWeight,
        misData.brdfMisWeight,
        brdfCutoff
    );

    if (blendedSourcePdf == 0.0) {
        return;
    }

    float invSourcePdf = 1.0 / blendedSourcePdf;
    RTXDI_StreamSample(reservoir, smple.index, sampleUv, rand_next_float(), smple.weight, invSourcePdf);
}

void rtxdi_stream_local_light(inout RTXDI_DIReservoir reservoir, RAB_Surface surface, int lightIndex, float sourcePdf, RTXDI_InitialSamplingMisData misData, float brdfCutoff) {
    if (lightIndex < 0 || lightIndex >= ph_light_count || sourcePdf <= 0.0) {
        return;
    }
    rtxdi_stream_local_light(reservoir, surface, load_light(lightIndex), sourcePdf, misData, brdfCutoff);
}

void rtxdi_stream_local_light(inout RTXDI_DIReservoir reservoir, RAB_Surface surface, int lightIndex, float sourcePdf, float localLightMisWeight) {
    RTXDI_InitialSamplingMisData misData;
    misData.numMisSamples = 1;
    misData.localLightMisWeight = localLightMisWeight;
    misData.environmentMapMisWeight = 0.0;
    misData.brdfMisWeight = 0.0;
    rtxdi_stream_local_light(reservoir, surface, lightIndex, sourcePdf, misData, 0.0);
}

// Backward-compat overload — passes localLightMisWeight=1.0 (no MIS blending).
void rtxdi_stream_local_light(inout RTXDI_DIReservoir reservoir, RAB_Surface surface, int lightIndex, float sourcePdf) {
    rtxdi_stream_local_light(reservoir, surface, lightIndex, sourcePdf, 1.0);
}

bool lt_pick_power_light_stratified(int sampleIndex, int totalSamples, out int lightIndex, out float lightPdf) {
    lightIndex = -1;
    lightPdf = 0.0f;

    if (ph_light_count <= 0) {
        return false;
    }

    float totalWeight = ph_global_light_cdf_data[ph_light_count - 1];
    if (totalWeight <= 1e-6f) {
        return lt_pick_uniform_light(lightIndex, lightPdf);
    }

    // Stratified: divide [0, totalWeight) into totalSamples equal strata and draw
    // uniformly within the stratum for sampleIndex, reducing clustering variance.
    float stratumSize = totalWeight / float(max(totalSamples, 1));
    float draw = (float(sampleIndex) + rand_next_float()) * stratumSize;

    int low = 0;
    int high = ph_light_count - 1;
    while (low < high) {
        int mid = (low + high) >> 1;
        if (ph_global_light_cdf_data[mid] < draw) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }

    float prevCdf = low > 0 ? ph_global_light_cdf_data[low - 1] : 0.0f;
    float weight = ph_global_light_cdf_data[low] - prevCdf;
    if (weight <= 1e-6f) {
        return lt_pick_uniform_light(lightIndex, lightPdf);
    }

    lightIndex = low;
    lightPdf = max(weight / totalWeight, 1e-6f);
    return true;
}

// Exact RTXDI random-sampler helpers come from light_tree.glsl so the fragment ReGIR path,
// temporal/spatial passes, and initial sampling all share the same seed/index logic.

// RTXDI_SampleLocalLights (InitialSampling.hlsli lines 301-333)
// Returns the initial local-light reservoir for the given surface.
// ph_restir_local_light_sampling_mode selects the sampling strategy at runtime:
//   -1.0 or 0.0 (unbound) → SDK default = Uniform (mode 0)
//   0 = Uniform:   lt_pick_uniform_light for all samples
//   1 = Power_RIS: stratified RIS tile sampling for all samples
//   2 = ReGIR_RIS: regir_pick_light inside grid cell, Power_RIS (RIS tile) fallback outside
//
// Split RNG streams — matches RTXDI InitialSampling.hlsli:
//   rng         (per-pixel random)   — drives per-sample light selection and UV draws.
//   coherentRng (spatially coherent) — drives ReGIR cell jitter and RIS tile selection.
// RTXDI uses coherentRng exclusively for RTXDI_CalculateReGIRCellIndex and
// RTXDI_SelectLocalLightReGIRRISTile so neighboring pixels share the same ReGIR cell.
bool rtxdi_stream_local_light_rng(
    inout RTXDI_RandomSamplerState rng,
    inout RTXDI_DIReservoir reservoir,
    RAB_Surface surface,
    Light light,
    float sourcePdf,
    RTXDI_InitialSamplingMisData misData,
    float brdfCutoff,
    out RAB_LightSample o_selectedSample
) {
    o_selectedSample = lt_null_sample();

    if (light.index < 0 || light.index >= ph_light_count || sourcePdf <= 0.0) {
        return false;
    }

    vec2 sampleUv = vec2(lt_next_random(rng), lt_next_random(rng));
    vec3 sampledPosition = lt_sample_light_position_from_uv(light, sampleUv, lt_surface_ray_origin(lt_surface_rt_pos(surface), surface.geoNormal));
    RAB_LightSample smple = light_sample_new_at_position(light, sampledPosition, surface);

    float blendedSourcePdf = RTXDI_LightBrdfMisWeight(
        surface, smple, sourcePdf,
        misData.localLightMisWeight,
        misData.brdfMisWeight,
        brdfCutoff
    );

    if (blendedSourcePdf == 0.0) {
        return false;
    }

    float invSourcePdf = 1.0 / blendedSourcePdf;
    bool selected = RTXDI_StreamSample(reservoir, smple.index, sampleUv, lt_next_random(rng), smple.weight, invSourcePdf);
    if (selected) {
        o_selectedSample = smple;
    }
    return selected;
}

bool rtxdi_stream_local_light_rng(
    inout RTXDI_RandomSamplerState rng,
    inout RTXDI_DIReservoir reservoir,
    RAB_Surface surface,
    int lightIndex,
    float sourcePdf,
    RTXDI_InitialSamplingMisData misData,
    float brdfCutoff,
    out RAB_LightSample o_selectedSample
) {
    if (lightIndex < 0 || lightIndex >= ph_light_count || sourcePdf <= 0.0) {
        o_selectedSample = lt_null_sample();
        return false;
    }

    return rtxdi_stream_local_light_rng(rng, reservoir, surface, load_light(lightIndex), sourcePdf, misData, brdfCutoff, o_selectedSample);
}

void rtxdi_stream_local_light_rng(
    inout RTXDI_RandomSamplerState rng,
    inout RTXDI_DIReservoir reservoir,
    RAB_Surface surface,
    Light light,
    float sourcePdf,
    RTXDI_InitialSamplingMisData misData,
    float brdfCutoff
) {
    RAB_LightSample ignoredSelectedSample;
    rtxdi_stream_local_light_rng(rng, reservoir, surface, light, sourcePdf, misData, brdfCutoff, ignoredSelectedSample);
}

void rtxdi_stream_local_light_rng(
    inout RTXDI_RandomSamplerState rng,
    inout RTXDI_DIReservoir reservoir,
    RAB_Surface surface,
    int lightIndex,
    float sourcePdf,
    RTXDI_InitialSamplingMisData misData,
    float brdfCutoff
) {
    RAB_LightSample ignoredSelectedSample;
    rtxdi_stream_local_light_rng(rng, reservoir, surface, lightIndex, sourcePdf, misData, brdfCutoff, ignoredSelectedSample);
}

struct RTXDI_LightBufferRegion
{
    uint firstLightIndex;
    uint numLights;
    uint pad1;
    uint pad2;
};

struct RTXDI_RISBufferSegmentParameters
{
    uint bufferOffset;
    uint tileSize;
    uint tileCount;
    uint pad1;
};

struct RTXDI_RISTileInfo
{
    uint risTileOffset;
    uint risTileSize;
};

const uint RTXDI_LocalLightContextSamplingMode_UNIFORM = 0u;
const uint RTXDI_LocalLightContextSamplingMode_RIS = 1u;

struct RTXDI_LocalLightSelectionContext
{
    uint mode;
    uint proposalFamily;
    RTXDI_RISTileInfo risTileInfo;
    RTXDI_LightBufferRegion lightBufferRegion;
};

RTXDI_LightBufferRegion RTXDI_GetLocalLightBufferRegion()
{
    RTXDI_LightBufferRegion region;
    region.firstLightIndex = 0u;
    region.numLights = uint(max(ph_light_count, 0));
    region.pad1 = 0u;
    region.pad2 = 0u;
    return region;
}

RTXDI_RISBufferSegmentParameters RTXDI_GetLocalLightRISBufferSegmentParameters()
{
    RTXDI_RISBufferSegmentParameters params;
    params.bufferOffset = uint(max(ph_ris_tile_buffer_offset, 0));
    params.tileSize = uint(max(ph_ris_tile_size, 0));
    params.tileCount = uint(max(ph_ris_tile_count, 0));
    params.pad1 = 0u;
    return params;
}

void RTXDI_RandomlySelectLightUniformly(
    float rnd,
    RTXDI_LightBufferRegion region,
    out RAB_LightInfo lightInfo,
    out uint lightIndex,
    out float invSourcePdf)
{
    lightInfo = RAB_EmptyLightInfo();
    lightIndex = 0u;
    invSourcePdf = 0.0f;

    if (region.numLights == 0u)
    {
        return;
    }

    invSourcePdf = float(region.numLights);
    lightIndex = region.firstLightIndex + min(uint(floor(rnd * float(region.numLights))), region.numLights - 1u);
    lightInfo = RAB_LoadLightInfo(int(lightIndex), false);
}

void RTXDI_RandomlySelectLightDataFromRISTile(
    float rnd,
    RTXDI_RISTileInfo bufferInfo,
    out uvec2 tileData,
    out uint risBufferPtr)
{
    tileData = uvec2(0u);
    risBufferPtr = 0u;

    if (bufferInfo.risTileSize == 0u)
    {
        return;
    }

    uint risSample = min(uint(floor(rnd * float(bufferInfo.risTileSize))), bufferInfo.risTileSize - 1u);
    risBufferPtr = risSample + bufferInfo.risTileOffset;
    tileData = ph_ris_data[risBufferPtr];
}

RTXDI_RISTileInfo RTXDI_RandomlySelectRISTile(
    inout RTXDI_RandomSamplerState coherentRng,
    RTXDI_RISBufferSegmentParameters params)
{
    RTXDI_RISTileInfo risTileInfo;
    risTileInfo.risTileOffset = params.bufferOffset;
    risTileInfo.risTileSize = params.tileSize;

    if (params.tileCount == 0u || params.tileSize == 0u)
    {
        risTileInfo.risTileSize = 0u;
        return risTileInfo;
    }

    float tileRnd = RTXDI_GetNextRandom(coherentRng);
    uint tileIndex = min(uint(tileRnd * float(params.tileCount)), params.tileCount - 1u);
    risTileInfo.risTileOffset = tileIndex * params.tileSize + params.bufferOffset;
    return risTileInfo;
}

RTXDI_RISTileInfo RTXDI_SelectLocalLightReGIRRISTile(int cellIndex)
{
    RTXDI_RISTileInfo tileInfo;
    tileInfo.risTileOffset = uint(cellIndex) * uint(ph_regir_lights_per_cell) + uint(ph_regir_ris_buffer_offset);
    tileInfo.risTileSize = uint(max(ph_regir_lights_per_cell, 0));
    return tileInfo;
}

RTXDI_LocalLightSelectionContext RTXDI_InitializeLocalLightSelectionContextUniform(RTXDI_LightBufferRegion lightBufferRegion)
{
    RTXDI_LocalLightSelectionContext ctx;
    ctx.mode = RTXDI_LocalLightContextSamplingMode_UNIFORM;
    ctx.proposalFamily = LT_PROPOSAL_FAMILY_UNIFORM;
    ctx.lightBufferRegion = lightBufferRegion;
    ctx.risTileInfo.risTileOffset = 0u;
    ctx.risTileInfo.risTileSize = 0u;
    return ctx;
}

RTXDI_LocalLightSelectionContext RTXDI_InitializeLocalLightSelectionContextRIS(RTXDI_RISTileInfo risTileInfo)
{
    RTXDI_LocalLightSelectionContext ctx;
    ctx.mode = RTXDI_LocalLightContextSamplingMode_RIS;
    ctx.proposalFamily = LT_PROPOSAL_FAMILY_POWER_RIS;
    ctx.risTileInfo = risTileInfo;
    ctx.lightBufferRegion.firstLightIndex = 0u;
    ctx.lightBufferRegion.numLights = 0u;
    ctx.lightBufferRegion.pad1 = 0u;
    ctx.lightBufferRegion.pad2 = 0u;
    return ctx;
}

RTXDI_LocalLightSelectionContext RTXDI_InitializeLocalLightSelectionContextRIS(
    inout RTXDI_RandomSamplerState coherentRng,
    RTXDI_RISBufferSegmentParameters risBufferSegmentParams)
{
    return RTXDI_InitializeLocalLightSelectionContextRIS(
        RTXDI_RandomlySelectRISTile(coherentRng, risBufferSegmentParams));
}

bool lt_is_complex_surface(RAB_Surface surface) {
    float roughness = clamp(surface.material.roughness, 0.0f, 1.0f);
    float reflectivity = ph_luminance(clamp(surface.material.specularF0, vec3(0.0f), vec3(1.0f)));
    float emission = ph_luminance(max(surface.material.emissiveColor, vec3(0.0f)));
    return roughness < 0.35f || reflectivity > 0.1f || emission > 0.0f;
}

float lt_spatial_neighbor_history_cap(
    RTXDI_DIReservoir canonicalReservoir,
    RTXDI_DIReservoir neighborReservoir,
    float targetHistoryLength)
{
    float canonicalHistory = max(canonicalReservoir.M, 1.0f);
    float targetHistory = max(targetHistoryLength, canonicalHistory + 1.0f);
    return min(max(neighborReservoir.M, 0.0f), targetHistory);
}

bool lt_materials_similar(RAB_Surface a, RAB_Surface b) {
    return RAB_AreMaterialsSimilar(RAB_GetMaterial(a), RAB_GetMaterial(b));
}

bool IsComplexSurface(ivec2 pixelPosition, RAB_Surface surface) {
    return lt_is_complex_surface(surface);
}

#endif // closes #ifndef PH_LIGHTTREE_REUSE_INCLUDE (opened line 1)


