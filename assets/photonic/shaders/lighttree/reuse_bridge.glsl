#ifndef PH_LIGHTTREE_REUSE_INCLUDE
#define PH_LIGHTTREE_REUSE_INCLUDE

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)
layout(std430) restrict buffer ph_temporal_scatter_global_counters {
    uint ph_temporal_scatter_global_counters_data[];
};

layout(std430) restrict buffer ph_temporal_scatter_cell_counters {
    uint ph_temporal_scatter_cell_counters_data[];
};

#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY)
layout(std430) restrict buffer ph_temporal_scatter_reservoir_indices {
    uvec2 ph_temporal_scatter_reservoir_indices_data[];
};

layout(std430) restrict buffer ph_temporal_scatter_scattered_reservoirs {
    uvec2 ph_temporal_scatter_scattered_reservoirs_data[];
};

layout(std430) restrict buffer ph_temporal_scatter_scattered_weights {
    uint ph_temporal_scatter_scattered_weights_data[];
};
#endif

#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY) || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING) || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY)
layout(std430) restrict buffer ph_temporal_scatter_cell_offsets {
    uint ph_temporal_scatter_cell_offsets_data[];
};

layout(std430) restrict buffer ph_temporal_scatter_sorted_reservoirs {
    uvec2 ph_temporal_scatter_sorted_reservoirs_data[];
};

layout(std430) restrict buffer ph_temporal_scatter_sorted_weights {
    uint ph_temporal_scatter_sorted_weights_data[];
};
#endif
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
// Stores per-pixel primary-hit / shift state needed for reservoir splatting.
// This sidecar complements the DI reservoir with transport metadata that the
// reservoir itself does not own, while avoiding duplication of fields already
// persisted in the reservoir (selected light identity, sampled-light UV,
// pixel/lens-domain UVs, target PDF, etc.).
struct ScatterReconnectionData {
    vec3  worldPos;                  // Primary hit world-space position (first hit)
    float confidence;               // Reservoir confidence / history proxy

    float viewDepth;                // Linear view depth of first hit
    uint  faceId;                   // Dominant signed face identifier for stable block matching
    uint  flags;                    // Light / event classification flags
    uint  pathLength;               // Current path length (DI = 1)
    uint  firstBsdfComponentType;   // First BSDF event classification
    uint  secondBsdfComponentType;  // Second BSDF / light-side event classification
    uint  proposalFamily;           // Proposal-family provenance for temporal replay

    vec2  subPixel;                 // Fractional sub-pixel location for scatter support tests
    vec2  lensSample;               // Lens-domain sample carried with the selected path
    float lightPdf;                 // Proposal/source PDF associated with the selected sample
    float time;                     // Frame-local temporal coordinate for transport replay
    float subPixelJacobian;         // Camera-vertex / sub-pixel Jacobian for splatting MIS
    float secondaryPathJacobian;    // Secondary-path Jacobian for the current light transport
    vec3  firstWi;                  // Incoming direction at the first hit (toward camera)
    vec3  secondPos;                // Light-side/secondary transport endpoint for reconnection
    vec3  irradiance;               // Incident radiance context at the selected first hit
    vec3  earlyThroughput;          // Prefix throughput before final radiance accumulation
};

ScatterReconnectionData scatter_empty_reconnection() {
    ScatterReconnectionData d;
    d.worldPos = vec3(0.0f);
    d.confidence = 0.0f;
    d.viewDepth = 0.0f;
    d.faceId = 0u;
    d.flags = 0u;
    d.pathLength = 0u;
    d.firstBsdfComponentType = 0u;
    d.secondBsdfComponentType = 0u;
    d.proposalFamily = 0u;
    d.subPixel = vec2(0.5f);
    d.lensSample = vec2(0.5f);
    d.lightPdf = 0.0f;
    d.time = 0.0f;
    d.subPixelJacobian = 1.0f;
    d.secondaryPathJacobian = 1.0f;
    d.firstWi = vec3(0.0f, 0.0f, 1.0f);
    d.secondPos = vec3(0.0f);
    d.irradiance = vec3(0.0f);
    d.earlyThroughput = vec3(0.0f);
    return d;
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
const float SCATTER_RECONNECTION_CONFIDENCE_MAX = 20.0f;
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
    return clamp(confidence, 0.0f, SCATTER_RECONNECTION_CONFIDENCE_MAX);
}

float scatter_encode_reconnection_face(uint faceId) {
    return float(faceId & SCATTER_RECONNECTION_FACE_MASK);
}

uint scatter_decode_reconnection_face(float encodedFace) {
    return uint(clamp(round(encodedFace), 0.0f, float(SCATTER_RECONNECTION_FACE_MASK)));
}

uint scatter_pack_reconnection_meta(ScatterReconnectionData d) {
    return ((d.faceId & SCATTER_RECONNECTION_FACE_MASK) << SCATTER_RECONNECTION_FACE_SHIFT)
        | ((d.flags & SCATTER_RECONNECTION_FLAGS_MASK) << SCATTER_RECONNECTION_FLAGS_SHIFT)
        | ((d.pathLength & SCATTER_RECONNECTION_PATH_LENGTH_MASK) << SCATTER_RECONNECTION_PATH_LENGTH_SHIFT)
        | ((d.firstBsdfComponentType & SCATTER_RECONNECTION_FIRST_BSDF_MASK) << SCATTER_RECONNECTION_FIRST_BSDF_SHIFT)
        | ((d.secondBsdfComponentType & SCATTER_RECONNECTION_SECOND_BSDF_MASK) << SCATTER_RECONNECTION_SECOND_BSDF_SHIFT);
}

void scatter_unpack_reconnection_meta(uint packedMeta, inout ScatterReconnectionData d) {
    d.faceId = (packedMeta >> SCATTER_RECONNECTION_FACE_SHIFT) & SCATTER_RECONNECTION_FACE_MASK;
    d.flags = (packedMeta >> SCATTER_RECONNECTION_FLAGS_SHIFT) & SCATTER_RECONNECTION_FLAGS_MASK;
    d.pathLength = (packedMeta >> SCATTER_RECONNECTION_PATH_LENGTH_SHIFT) & SCATTER_RECONNECTION_PATH_LENGTH_MASK;
    d.firstBsdfComponentType = (packedMeta >> SCATTER_RECONNECTION_FIRST_BSDF_SHIFT) & SCATTER_RECONNECTION_FIRST_BSDF_MASK;
    d.secondBsdfComponentType = (packedMeta >> SCATTER_RECONNECTION_SECOND_BSDF_SHIFT) & SCATTER_RECONNECTION_SECOND_BSDF_MASK;
}

// Pack the temporal-history reconnection data into the sidecar plus
// widened reservoir meta channels. The float outputs remain finite.
void scatter_pack_reconnection(
    ScatterReconnectionData d,
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

    out0 = vec4(d.worldPos, d.viewDepth);
    out1 = vec4(
        scatter_pack_half2(vec2(
            scatter_clamp_reconnection_confidence(d.confidence),
            0.0f
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
ScatterReconnectionData scatter_unpack_reconnection(vec4 data0, vec4 data1, vec4 sampleData, float transportAux0, float transportAux1) {
    ScatterReconnectionData d;
    d.worldPos = data0.xyz;
    d.viewDepth = data0.w;
    vec2 packedConfidenceUnused = scatter_unpack_half2(data1.x);
    d.confidence = scatter_clamp_reconnection_confidence(packedConfidenceUnused.x);
    d.lightPdf = scatter_unpack_reconnection_proposal_pdf(transportAux0);
    scatter_unpack_reconnection_meta(floatBitsToUint(data1.y), d);
    d.subPixel = clamp(scatter_unpack_half2(data1.z), vec2(0.0f), vec2(1.0f));
    d.lensSample = clamp(rtxdi_unpack_sample_uv(floatBitsToUint(sampleData.z)), vec2(0.0f), vec2(1.0f));
    d.proposalFamily = lt_path_sample_proposal_family(floatBitsToUint(sampleData.w));
    vec2 packedTimeIrradiance = scatter_unpack_half2(transportAux1);
    d.time = clamp(packedTimeIrradiance.x, 0.0f, 1.0f);
    vec2 packedJacobians = scatter_unpack_half2(data1.w);
    d.subPixelJacobian = max(packedJacobians.x, 1e-10f);
    d.secondaryPathJacobian = max(packedJacobians.y, 1e-10f);
    d.firstWi = normalize(world_camera_position - d.worldPos);
    d.secondPos = d.worldPos;
    d.irradiance = vec3(max(packedTimeIrradiance.y, 0.0f));
    d.earlyThroughput = vec3(1.0f);
    return d;
}

// Load reconnection data from previous-frame textures.
ScatterReconnectionData scatter_load_prev_reconnection(ivec2 uv) {
    vec4 prevReservoirMeta = texelFetch(prev_radiosity_reservoir_meta, uv, 0);
    return scatter_unpack_reconnection(
        texelFetch(prev_scatter_reconnection0, uv, 0),
        texelFetch(prev_scatter_reconnection1, uv, 0),
        texelFetch(prev_radiosity_reservoir_samples, uv, 0),
        prevReservoirMeta.y,
        prevReservoirMeta.z
    );
}

bool scatter_reconnection_matches_surface(ScatterReconnectionData reconnection, ivec2 pixelPosition, RAB_Surface currentSurface) {
    vec4 currentIdentity = scatter_load_surface_identity(pixelPosition, false);
    uint currentFaceId = uint(round(currentIdentity.w));
    uint reconnectionSurfaceHash = scatter_compute_surface_hash(reconnection.worldPos);
    uint currentSurfaceHash = scatter_compute_surface_hash(currentSurface.worldPos);
    return reconnectionSurfaceHash == currentSurfaceHash
        && reconnection.faceId == currentFaceId
        && distance(fract(reconnection.worldPos), currentIdentity.xyz) <= (2.0f / 256.0f)
        && abs(reconnection.viewDepth - currentSurface.viewDepth) <= max(1e-3f, 0.02f * max(reconnection.viewDepth, currentSurface.viewDepth));
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
    ScatterReconnectionData reconnection,
    RAB_Surface fallbackSurface,
    vec3 fallbackCameraPos,
    vec3 fallbackCameraForward)
{
    bool hasStoredJacobian = reconnection.viewDepth > 0.0f
        && any(greaterThan(abs(reconnection.worldPos), vec3(0.0f)))
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

float scatter_resolve_stored_secondary_jacobian(ScatterReconnectionData reconnection) {
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

float lt_scatter_compute_history_confidence(ivec2 pixelPosition, RAB_Surface currentSurface, RTXDI_DIReservoir reservoir) {
    float currentConfidence = lt_area_confidence_from_samples(reservoir.M);
    if (!RAB_IsSurfaceValid(currentSurface)) {
        return currentConfidence;
    }

    vec2 motionVector = texelFetch(radiosity_motion, pixelPosition, 0).xy;
    vec2 backprojF = vec2(pixelPosition) - motionVector * vec2(viewWidth, viewHeight);
    ivec2 basePixel = ivec2(floor(backprojF));
    vec2 fracOffset = backprojF - vec2(basePixel);

    float bilinearConfidence = 0.0f;
    float totalWeight = 0.0f;
    for (int dy = 0; dy <= 1; ++dy) {
        for (int dx = 0; dx <= 1; ++dx) {
            ivec2 samplePixel = basePixel + ivec2(dx, dy);
            if (!lt_is_viewport_uv_in_bounds(samplePixel)) {
                continue;
            }

            ScatterReconnectionData neighborReconn = scatter_load_prev_reconnection(samplePixel);
            float weight = lt_scatter_bilinear_weight(fracOffset, dx, dy);
            if (weight <= 0.0f) {
                continue;
            }

            if (!scatter_reconnection_matches_surface(neighborReconn, pixelPosition, currentSurface)) {
                continue;
            }

            bilinearConfidence += weight * neighborReconn.confidence;
            totalWeight += weight;
        }
    }

    float prevConfidence = (totalWeight > 0.0f) ? (bilinearConfidence / totalWeight) : 0.0f;
    return min(max(currentConfidence, prevConfidence + 1.0f), 20.0f);
}

bool lt_area_is_temporal_neighbor_valid(RAB_Surface currentSurface, RAB_Surface prevSurface) {
    if (!RAB_IsSurfaceValid(currentSurface) || !RAB_IsSurfaceValid(prevSurface)) {
        return false;
    }

    if (!RTXDI_IsValidNeighbor(
        RAB_GetSurfaceNormal(currentSurface), RAB_GetSurfaceNormal(prevSurface),
        RAB_GetSurfaceLinearDepth(currentSurface), RAB_GetSurfaceLinearDepth(prevSurface),
        ph_restir_normal_threshold, ph_restir_depth_threshold)) {
        return false;
    }

    vec3 worldDelta = currentSurface.worldPos - prevSurface.worldPos;
    float worldDistanceSq = dot(worldDelta, worldDelta);
    float depthScale = max(max(abs(currentSurface.viewDepth), abs(prevSurface.viewDepth)), 1.0f);
    float worldThreshold = max(1e-4f, 0.02f * depthScale);
    if (worldDistanceSq > worldThreshold * worldThreshold) {
        return false;
    }

    float planeDistance = abs(dot(normalize(currentSurface.geoNormal), worldDelta));
    if (planeDistance > max(1e-4f, 0.01f * depthScale)) {
        return false;
    }

    return true;
}

ivec2 lt_area_reproject_pixel(ivec2 pixelPosition) {
    vec2 motion = texelFetch(radiosity_motion, pixelPosition, 0).xy;
    ivec2 prevPixel = ivec2(floor(vec2(pixelPosition) - motion * vec2(viewWidth, viewHeight)));
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
const uint RTXDI_DI_BUFFER_INDEX_TEMPORAL_REPROJECTION_OUTPUT = 2u;
const uint RTXDI_DI_BUFFER_INDEX_TEMPORAL_BINNING_OUTPUT = 3u;
const uint RTXDI_DI_BUFFER_INDEX_SPATIAL_RESAMPLING_OUTPUT = 4u;
const uint RTXDI_DI_BUFFER_INDEX_SHADING_INPUT = 5u;

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
ScatterReconnectionData scatter_build_reconnection(
    RAB_Surface surface,
    RTXDI_DIReservoir reservoir,
    RAB_LightSample lightSample,
    ivec2 pixelPosition,
    float confidence,
    float subPixelJacobian
) {
    ScatterReconnectionData d;
    vec4 identityData = scatter_load_surface_identity(pixelPosition, false);
    vec3 irradiance = scatter_resolve_irradiance(surface, lightSample);
    vec3 earlyThroughput = scatter_resolve_early_throughput(surface, lightSample);
    vec3 secondPos = (lightSample.index >= 0) ? lightSample.position : surface.worldPos;
    d.worldPos = surface.worldPos;
    d.confidence = confidence;
    d.viewDepth = surface.viewDepth;
    d.faceId = uint(round(identityData.w));
    d.flags = scatter_resolve_reconnection_flags(lightSample);
    d.pathLength = (lightSample.index >= 0) ? 2u : 1u;
    d.firstBsdfComponentType = scatter_resolve_first_bsdf_component_type(surface);
    d.secondBsdfComponentType = scatter_resolve_second_bsdf_component_type(lightSample);
    d.subPixel = scatter_resolve_reservoir_subpixel(reservoir, pixelPosition);
    d.lensSample = lt_area_has_valid_domain(reservoir)
        ? clamp(reservoir.lensSampleUV, vec2(0.0f), vec2(1.0f))
        : lt_area_default_lens_sample();
    d.lightPdf = scatter_resolve_light_pdf(reservoir, lightSample);
    d.time = fract(float(max(ph_restir_frame_index, 0)) * 0.61803398875f);
    d.subPixelJacobian = max(subPixelJacobian, 1e-10f);
    d.firstWi = normalize(world_camera_position - surface.worldPos);
    d.secondPos = secondPos;
    d.irradiance = irradiance;
    d.earlyThroughput = earlyThroughput;
    d.secondaryPathJacobian = scatter_resolve_secondary_path_jacobian(
        surface,
        lightSample,
        secondPos,
        earlyThroughput,
        irradiance
    );
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
    else if (reservoirArrayIndex == RTXDI_DI_BUFFER_INDEX_TEMPORAL_REPROJECTION_OUTPUT)
    {
        rtxdi_unpack_reservoir_at_surface(
            reservoir,
            texelFetch(temporal_reprojection_data, reservoirPositionInt, 0),
            texelFetch(temporal_reprojection_sample, reservoirPositionInt, 0),
            texelFetch(temporal_reprojection_meta, reservoirPositionInt, 0),
            RAB_EmptySurface(),
            false
        );
    }
    else if (reservoirArrayIndex == RTXDI_DI_BUFFER_INDEX_TEMPORAL_BINNING_OUTPUT)
    {
        rtxdi_unpack_reservoir_at_surface(
            reservoir,
            texelFetch(temporal_binning_data, reservoirPositionInt, 0),
            texelFetch(temporal_binning_sample, reservoirPositionInt, 0),
            texelFetch(temporal_binning_meta, reservoirPositionInt, 0),
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

// Forward function declarations for Area-ReSTIR core functions used by temporal/spatial resampling.
void area_resample_reservoir_pairwise_mis(
    inout RTXDI_DIReservoir state,
    RTXDI_DIReservoir canonicalReservoir,
    RAB_Surface canonicalSurface,
    ivec2 canonicalPixel,
    RTXDI_DIReservoir candidateReservoir,
    RAB_Surface candidateSurface,
    ivec2 candidatePixel,
    bool useMFactor,
    float confidenceWeightSum,
    float candidateBilinearWeight,
    bool isTemporalReusing,
    uint shiftMappingMode,
    inout RTXDI_RandomSamplerState rng);

bool area_streaming_resample_finalize_mis(
    inout RTXDI_DIReservoir state,
    RTXDI_DIReservoir canonicalReservoir,
    float canonicalTargetPdf,
    inout RTXDI_RandomSamplerState rng);

RTXDI_DIReservoir lt_area_spatial_resampling(
    ivec2 pixelPosition,
    RAB_Surface centerSurface,
    RTXDI_DIReservoir centerSample,
    inout RTXDI_RandomSamplerState rng);

// Forward declarations for pairwise MIS weight functions (defined later, needed by splat_resample_temporal_pairwise_mis)
float area_pairwise_mis_non_defensive_non_canonical(
    float cSum, float c0, float pi, float c1, float pc, float out_J);
float area_pairwise_mis_non_defensive_canonical(
    float cSum, float c0, float pi, float c1, float pc, float out_J);
float area_pairwise_mis_defensive_non_canonical(
    float cSum, float c0, float pi, float c1, float pc, float out_J);
float area_pairwise_mis_defensive_canonical(
    float cSum, float c0, float pi, float c1, float pc, float out_J);

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)
RTXDI_DIReservoir lt_area_temporal_reprojection_stage(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng);

RTXDI_DIReservoir lt_area_temporal_binning_stage(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng);

RTXDI_DIReservoir lt_area_temporal_scatter_stage(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng,
    out ScatterReconnectionData reconnection);
#else
RTXDI_DIReservoir lt_area_temporal_reprojection_stage(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng)
{
    return currentReservoir;
}

RTXDI_DIReservoir lt_area_temporal_binning_stage(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng)
{
    return currentReservoir;
}

RTXDI_DIReservoir lt_area_temporal_scatter_stage(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng,
    out ScatterReconnectionData reconnection)
{
    reconnection = scatter_empty_reconnection();
    return currentReservoir;
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)
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

#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY)
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
    uint localCellIndex = atomicAdd(ph_temporal_scatter_cell_counters_data[cellLinearIndex], 1u);
    uint appendIndex = atomicAdd(ph_temporal_scatter_global_counters_data[0], 1u);
    ph_temporal_scatter_reservoir_indices_data[appendIndex] = uvec2(cellLinearIndex, localCellIndex);
    ph_temporal_scatter_scattered_reservoirs_data[appendIndex] = uvec2(sourceReservoirPos);
    ph_temporal_scatter_scattered_weights_data[appendIndex] = floatBitsToUint(supportWeight);
}

void lt_temporal_scatter_append_bilinear_contributors(vec2 projectedPixelF, ivec2 sourceReservoirPos)
{
    ivec2 basePixel = ivec2(floor(projectedPixelF));
    vec2 frac = projectedPixelF - vec2(basePixel);

    for (int dy = 0; dy <= 1; ++dy) {
        for (int dx = 0; dx <= 1; ++dx) {
            ivec2 targetPixel = basePixel + ivec2(dx, dy);
            if (!lt_is_viewport_uv_in_bounds(targetPixel)) {
                continue;
            }

            float weight = lt_scatter_bilinear_weight(frac, dx, dy);
            if (weight <= 1e-5f) {
                continue;
            }

            lt_temporal_scatter_append_contributor(targetPixel, sourceReservoirPos, weight);
        }
    }
}
#endif

#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
void lt_temporal_scatter_build_offsets() {
    if (ph_temporal_scatter_global_counters_data[1] != 0u) {
        return;
    }

    ivec2 size = ivec2(max(int(ceil(viewWidth * ((ph_restir_active_checkerboard_field == 0) ? 1.0f : 0.5f))), 1), max(int(viewHeight), 1));
    uint runningOffset = 0u;
    for (int y = 0; y < size.y; ++y) {
        for (int x = 0; x < size.x; ++x) {
            uint linearIndex = uint(y * size.x + x);
            ph_temporal_scatter_cell_offsets_data[linearIndex] = runningOffset;
            runningOffset += ph_temporal_scatter_cell_counters_data[linearIndex];
        }
    }
    memoryBarrierBuffer();
    ph_temporal_scatter_global_counters_data[1] = runningOffset;
}
#endif

#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
void lt_temporal_scatter_sort_contributors()
{
    uint scatterCount = ph_temporal_scatter_global_counters_data[0];
    for (uint scatterIndex = 0u; scatterIndex < scatterCount; ++scatterIndex) {
        uvec2 reservoirIndex = ph_temporal_scatter_reservoir_indices_data[scatterIndex];
        uint targetCell = reservoirIndex.x;
        uint localCellIndex = reservoirIndex.y;
        uint sortedIndex = ph_temporal_scatter_cell_offsets_data[targetCell] + localCellIndex;
        ph_temporal_scatter_sorted_reservoirs_data[sortedIndex] = ph_temporal_scatter_scattered_reservoirs_data[scatterIndex];
        ph_temporal_scatter_sorted_weights_data[sortedIndex] = ph_temporal_scatter_scattered_weights_data[scatterIndex];
    }
    memoryBarrierBuffer();
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
    float storedProposalPdf = max(reconnection.lightPdf, 0.0f);
    if (storedProposalPdf > 0.0f) {
        return storedProposalPdf;
    }

    // Old fallback kept for reference:
    // float fallbackProposalPdf = (reservoir.transportAux0 > 0.0f) ? (1.0f / reservoir.transportAux0) : 0.0f;
    float fallbackProposalPdf = max(reservoir.transportAux0, 0.0f);
    return fallbackProposalPdf;
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
    vec3 prevCameraForward,
    float sourcePHatPrev)
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

            if (!scatter_reconnection_matches_surface(sourceReconnection, neighborPixel, neighborSurface)
                || !lt_area_is_temporal_neighbor_valid(neighborSurface, sourcePrevSurface)) {
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

            denominator += bilinearWeight * sourcePrevReservoir.M * sourceProposalWeight * sourcePHatPrev * invSupportJ;
        }
    }

    return denominator;
#endif
}

RTXDI_DIReservoir lt_area_temporal_reprojection_stage(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng)
{
    if (ph_scatter_temporal_enabled <= 0.5f || ph_debug_enable_direct_temporal_reuse < 0.5f) {
        return RTXDI_EmptyDIReservoir();
    }

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
    if (!RAB_IsSurfaceValid(currentSurface)) {
        return RTXDI_EmptyDIReservoir();
    }

    RTXDI_RuntimeParameters params = lt_build_runtime_parameters();
    ivec2 reservoirPos = RTXDI_PixelPosToReservoirPos(pixelPosition, int(params.activeCheckerboardField));
    if (!lt_is_active_reservoir_lane(reservoirPos)) {
        return RTXDI_EmptyDIReservoir();
    }

    ScatterReconnectionData prevReconnection = scatter_load_prev_reconnection(pixelPosition);
    vec2 projectedPixelF = scatter_forward_project_to_current_frame(prevReconnection.worldPos);
    if (projectedPixelF.x < 0.0f || projectedPixelF.y < 0.0f) {
        return RTXDI_EmptyDIReservoir();
    }

    RAB_Surface prevSurface = lt_load_previous_surface(pixelPosition);
    if (!lt_area_is_temporal_neighbor_valid(currentSurface, prevSurface)) {
        return RTXDI_EmptyDIReservoir();
    }

    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(reservoirPos)
    );
    if (!RTXDI_IsValidDIReservoir(prevReservoir)) {
        return RTXDI_EmptyDIReservoir();
    }

    ivec2 basePixel = ivec2(floor(projectedPixelF));
    vec2 frac = projectedPixelF - vec2(basePixel);
    bool hasValidDestination = false;
    for (int dy = 0; dy <= 1 && !hasValidDestination; ++dy) {
        for (int dx = 0; dx <= 1; ++dx) {
            ivec2 targetPixel = basePixel + ivec2(dx, dy);
            if (!lt_is_viewport_uv_in_bounds(targetPixel)) {
                continue;
            }

            float bilinearWeight = lt_scatter_bilinear_weight(frac, dx, dy);
            if (bilinearWeight <= 1e-5f) {
                continue;
            }

            RAB_Surface targetSurface = RAB_GetGBufferSurface(targetPixel, false);
            if (!RAB_IsSurfaceValid(targetSurface)) {
                continue;
            }

            if (scatter_reconnection_matches_surface(prevReconnection, targetPixel, targetSurface)
                && lt_area_is_temporal_neighbor_valid(targetSurface, prevSurface)) {
                hasValidDestination = true;
                break;
            }
        }
    }

    if (!hasValidDestination) {
        return RTXDI_EmptyDIReservoir();
    }

    lt_temporal_scatter_append_bilinear_contributors(projectedPixelF, reservoirPos);
    return prevReservoir;
#else
    return currentReservoir;
#endif
}

#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY)
RTXDI_DIReservoir lt_area_temporal_binning_stage(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng)
{
    if (ph_scatter_temporal_enabled <= 0.5f) {
        return RTXDI_EmptyDIReservoir();
    }

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
    return RTXDI_EmptyDIReservoir();
#else
    if (lt_temporal_scatter_linear_index(lt_current_reservoir_pos()) != 0u) {
        return RTXDI_EmptyDIReservoir();
    }

    lt_temporal_scatter_build_offsets();
#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY)
    lt_temporal_scatter_sort_contributors();
#endif
    return RTXDI_EmptyDIReservoir();
#endif
}
#else
RTXDI_DIReservoir lt_area_temporal_binning_stage(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng)
{
    return RTXDI_EmptyDIReservoir();
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
RTXDI_DIReservoir lt_area_temporal_scatter_stage(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng,
    out ScatterReconnectionData reconnection)
{
    reconnection = scatter_empty_reconnection();
    return RTXDI_EmptyDIReservoir();
}
#else
RTXDI_DIReservoir lt_area_temporal_scatter_stage(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng,
    out ScatterReconnectionData reconnection)
{
    float maxHistoryLength = (ph_area_restir_max_history_length > 0.0f)
        ? ph_area_restir_max_history_length : 20.0f;

    reconnection = scatter_empty_reconnection();
    if (!RAB_IsSurfaceValid(currentSurface) || ph_scatter_temporal_enabled <= 0.5f || ph_debug_enable_direct_temporal_reuse < 0.5f) {
        return RTXDI_EmptyDIReservoir();
    }

    RTXDI_RuntimeParameters params = lt_build_runtime_parameters();
    ivec2 reservoirPos = lt_current_reservoir_pos();
    int previousCheckerboardField = lt_previous_checkerboard_field(int(params.activeCheckerboardField));
    uint cellLinearIndex = lt_temporal_scatter_linear_index(reservoirPos);
    uint contributorCount = ph_temporal_scatter_cell_counters_data[cellLinearIndex];
    uint contributorOffset = ph_temporal_scatter_cell_offsets_data[cellLinearIndex];

    RTXDI_DIReservoir canonicalReservoir = currentReservoir;
    lt_area_finalize_candidate(canonicalReservoir, pixelPosition, canonicalReservoir.pathSample);

    vec3 currCameraPos = world_camera_position;
    vec3 currCameraForward = normalize(mat3(gbufferModelView) * vec3(0.0f, 0.0f, -1.0f));
    vec3 prevCameraPos = previous_world_camera_position;
    vec3 prevCameraForward = normalize(mat3(gbufferPreviousModelView) * vec3(0.0f, 0.0f, -1.0f));
    float jSubPixelCurrent = scatter_compute_subpixel_jacobian(
        currentSurface.worldPos, currentSurface.geoNormal, currCameraPos, currCameraForward);

    RTXDI_DIReservoir result = canonicalReservoir;
    ScatterReconnectionData selectedPrevReconnection = scatter_empty_reconnection();
    ScatterReconnectionData canonicalReconnection = scatter_build_reconnection(
        currentSurface,
        canonicalReservoir,
        lt_decode_reservoir_sample_for_frame(canonicalReservoir, currentSurface, false, false),
        pixelPosition,
        scatter_clamp_reconnection_confidence(lt_scatter_compute_history_confidence(pixelPosition, currentSurface, canonicalReservoir)),
        jSubPixelCurrent
    );
    bool selectedFromPrev = false;

    struct TemporalScatterCandidate {
        RTXDI_DIReservoir reservoir;
        RAB_Surface prevSurface;
        ScatterReconnectionData reconnection;
        ivec2 prevPixel;
        float pHatPrev;
        float splatJacobian;
        float contributionWeight;
        float selectionScore;
        bool valid;
    };

    TemporalScatterCandidate backupCandidates[4];
    int backupCandidateCount = 0;

    vec2 motionVector = texelFetch(radiosity_motion, pixelPosition, 0).xy;
    vec2 backprojectedPixelF = vec2(pixelPosition) - motionVector * vec2(viewWidth, viewHeight);
    ivec2 backprojectedBasePixel = ivec2(floor(backprojectedPixelF));
    vec2 backprojectedFrac = fract(backprojectedPixelF);
    for (int dy = 0; dy <= 1; ++dy) {
        for (int dx = 0; dx <= 1; ++dx) {
            ivec2 backprojectedPixel = backprojectedBasePixel + ivec2(dx, dy);
            if (!lt_is_viewport_uv_in_bounds(backprojectedPixel)) {
                continue;
            }
            RTXDI_ActivateCheckerboardPixel(backprojectedPixel, true, previousCheckerboardField);
            if (!lt_is_viewport_uv_in_bounds(backprojectedPixel)) {
                continue;
            }

            float bilinearWeight = lt_scatter_bilinear_weight(backprojectedFrac, dx, dy);
            if (bilinearWeight <= 1e-5f) {
                continue;
            }

            RAB_Surface prevSurface = lt_load_previous_surface(backprojectedPixel);
            if (!RAB_IsSurfaceValid(prevSurface) || !lt_area_is_temporal_neighbor_valid(currentSurface, prevSurface)) {
                continue;
            }

            ivec2 backupReservoirPos = RTXDI_PixelPosToReservoirPos(backprojectedPixel, previousCheckerboardField);
            RTXDI_DIReservoir backupReservoir = RTXDI_LoadPreviousDIReservoir(
                lt_build_restir_di_parameters().reservoirBufferParams, uvec2(backupReservoirPos));
            if (!RTXDI_IsValidDIReservoir(backupReservoir)) {
                continue;
            }

            float pHatPrev = backupReservoir.targetPdf;
            RTXDI_DIReservoir temporalBackup = backupReservoir;
            if (!lt_area_try_shift_temporal_domain(temporalBackup, backprojectedPixel, pixelPosition, backprojectedPixelF)) {
                continue;
            }
            temporalBackup.age = min(backupReservoir.age + 1u, RTXDI_PackedDIReservoir_MaxAge);
            temporalBackup.M = min(temporalBackup.M, max(canonicalReservoir.M, 1.0f) * maxHistoryLength);
            temporalBackup.spatialDistance = pixelPosition - backprojectedPixel;

            if (pHatPrev <= 0.0f) {
                continue;
            }

            ScatterReconnectionData backupReconnection = scatter_load_prev_reconnection(backprojectedPixel);
            float jPrev = scatter_resolve_stored_subpixel_jacobian(
                backupReconnection,
                prevSurface,
                prevCameraPos,
                prevCameraForward
            );
            float splatJ = scatter_compute_scatter_jacobian(
                jPrev,
                jSubPixelCurrent,
                scatter_resolve_stored_secondary_jacobian(backupReconnection),
                1.0f
            );
            TemporalScatterCandidate candidate;
            candidate.reservoir = temporalBackup;
            candidate.prevSurface = prevSurface;
            candidate.reconnection = backupReconnection;
            candidate.prevPixel = backprojectedPixel;
            candidate.pHatPrev = pHatPrev;
            candidate.splatJacobian = splatJ;
            candidate.contributionWeight = bilinearWeight * lt_temporal_proposal_match_weight(canonicalReconnection, backupReconnection);
            candidate.selectionScore = candidate.contributionWeight
                * lt_temporal_candidate_confidence_weight(temporalBackup, backupReconnection, 1.0f)
                * max(pHatPrev, 1e-5f);
            candidate.valid = true;
            backupCandidates[backupCandidateCount++] = candidate;
        }
    }

    float canonicalConfidenceWeight = max(canonicalReservoir.M, 1.0f);
    float totalGatheredPreviousConfidenceWeight = 0.0f;
    for (int backupIdx = 0; backupIdx < backupCandidateCount; ++backupIdx) {
        TemporalScatterCandidate backupCandidate = backupCandidates[backupIdx];
        totalGatheredPreviousConfidenceWeight += lt_temporal_candidate_confidence_weight(
            backupCandidate.reservoir,
            backupCandidate.reconnection,
            backupCandidate.contributionWeight
        );
    }

    float gatheredPreviousConfidenceWeight = 0.0f;

    bool allowScatterContributorMerge = true;
    float scatterConfidenceWeightSum = 0.0f;
    if (allowScatterContributorMerge) {
        for (uint contributorIdx = 0u; contributorIdx < contributorCount; ++contributorIdx) {
            float contributorSupportWeight = uintBitsToFloat(ph_temporal_scatter_sorted_weights_data[contributorOffset + contributorIdx]);
            if (contributorSupportWeight <= 0.0f) {
                continue;
            }

            ivec2 sourceReservoirPos = ivec2(ph_temporal_scatter_sorted_reservoirs_data[contributorOffset + contributorIdx]);
            ivec2 sourcePixel = RTXDI_ReservoirPosToPixelPos(sourceReservoirPos, previousCheckerboardField);
            RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
                lt_build_restir_di_parameters().reservoirBufferParams,
                uvec2(sourceReservoirPos)
            );
            if (!RTXDI_IsValidDIReservoir(prevReservoir)) {
                continue;
            }

            ScatterReconnectionData sourceReconnection = scatter_load_prev_reconnection(sourcePixel);
            scatterConfidenceWeightSum += lt_temporal_candidate_confidence_weight(
                prevReservoir,
                sourceReconnection,
                contributorSupportWeight * lt_temporal_proposal_match_weight(canonicalReconnection, sourceReconnection)
            );
        }
    }

    float scatterConfidenceCap = max(canonicalConfidenceWeight * 0.25f, 1.0f);
    float recoveryScatterConfidenceWeight = allowScatterContributorMerge
        ? min(scatterConfidenceWeightSum, scatterConfidenceCap)
        : 0.0f;
    float sharedScatterStabilizationWeight = 0.0f;
    float confidenceWeightSum = canonicalConfidenceWeight
        + totalGatheredPreviousConfidenceWeight
        + sharedScatterStabilizationWeight;

    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    float prevWeightSum = 0.0f;

    uint temporalShiftMappingMode = (ph_area_restir_temporal_shift_mode <= 0.0f)
        ? AREA_RESTIR_SHIFT_MODE_ONLY_RECONNECTION
        : uint(clamp(ph_area_restir_temporal_shift_mode, 0.0f, 2.0f));

    for (int backupIdx = 0; backupIdx < backupCandidateCount; ++backupIdx) {
        TemporalScatterCandidate backupCandidate = backupCandidates[backupIdx];
        RTXDI_DIReservoir weightedBackup = backupCandidate.reservoir;
        gatheredPreviousConfidenceWeight += lt_temporal_candidate_confidence_weight(
            weightedBackup,
            backupCandidate.reconnection,
            backupCandidate.contributionWeight
        );
        prevWeightSum = state.weightSum;
        area_resample_reservoir_pairwise_mis(
            state,
            canonicalReservoir,
            currentSurface,
            pixelPosition,
            weightedBackup,
            backupCandidate.prevSurface,
            backupCandidate.prevPixel,
            false,
            confidenceWeightSum,
            backupCandidate.contributionWeight,
            true,
            temporalShiftMappingMode,
            rng
        );

        if (state.weightSum != prevWeightSum && state.lightData == weightedBackup.lightData) {
            selectedPrevReconnection = backupCandidate.reconnection;
            selectedFromPrev = true;
        }
    }

    state.canonicalWeight = (backupCandidateCount == 0) ? 1.0f : state.canonicalWeight;
    confidenceWeightSum = canonicalConfidenceWeight + recoveryScatterConfidenceWeight;

    for (uint contributorIdx = 0u; allowScatterContributorMerge && gatheredPreviousConfidenceWeight <= 0.0f && contributorIdx < contributorCount; ++contributorIdx) {
        ivec2 sourceReservoirPos = ivec2(ph_temporal_scatter_sorted_reservoirs_data[contributorOffset + contributorIdx]);
        float contributorSupportWeight = uintBitsToFloat(ph_temporal_scatter_sorted_weights_data[contributorOffset + contributorIdx]);
        if (contributorSupportWeight <= 0.0f) continue;
        ivec2 sourcePixel = RTXDI_ReservoirPosToPixelPos(sourceReservoirPos, previousCheckerboardField);
        RAB_Surface prevSurface = lt_load_previous_surface(sourcePixel);
        if (!lt_area_is_temporal_neighbor_valid(currentSurface, prevSurface)) continue;

        RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
            lt_build_restir_di_parameters().reservoirBufferParams,
            uvec2(sourceReservoirPos)
        );
        if (!RTXDI_IsValidDIReservoir(prevReservoir)) continue;

        ScatterReconnectionData contributorReconnection = scatter_load_prev_reconnection(sourcePixel);
        float pHatPrev = prevReservoir.targetPdf;
        vec2 contributorProjectedPixelF = scatter_forward_project_to_current_frame(contributorReconnection.worldPos);
        float contributorProposalMatch = lt_temporal_proposal_match_weight(canonicalReconnection, contributorReconnection);
        float contributorNormalization = lt_temporal_scatter_support_denominator(
            ivec2(floor(contributorProjectedPixelF)),
            fract(contributorProjectedPixelF),
            contributorReconnection,
            prevSurface,
            prevReservoir,
            prevCameraPos,
            prevCameraForward,
            pHatPrev);
        if (contributorNormalization <= 0.0f) continue;

        float scatterNormalizationScale = (scatterConfidenceWeightSum > 0.0f)
            ? min(1.0f, scatterConfidenceCap / scatterConfidenceWeightSum)
            : 0.0f;
        contributorNormalization *= scatterNormalizationScale;
        if (contributorNormalization <= 0.0f) continue;

        RTXDI_DIReservoir shiftedReservoir = lt_translate_reservoir_between_frames(prevReservoir, true, false);
        if (!RTXDI_IsValidDIReservoir(shiftedReservoir)) continue;

        shiftedReservoir.age = min(prevReservoir.age + 1u, RTXDI_PackedDIReservoir_MaxAge);
        shiftedReservoir.M = min(shiftedReservoir.M, max(canonicalReservoir.M, 1.0f) * maxHistoryLength);
        shiftedReservoir.spatialDistance = pixelPosition - sourcePixel;

        lt_area_finalize_candidate(shiftedReservoir, pixelPosition, shiftedReservoir.pathSample);
        RAB_LightSample splatLight = lt_decode_reservoir_sample_for_frame(
            shiftedReservoir, currentSurface, false, false);
        shiftedReservoir.targetPdf = lt_surface_target_pdf(currentSurface, splatLight);

        float jSubPixelPrev = scatter_resolve_stored_subpixel_jacobian(
            contributorReconnection,
            prevSurface,
            prevCameraPos,
            prevCameraForward
        );
        float splatJacobian = scatter_compute_scatter_jacobian(
            jSubPixelPrev,
            jSubPixelCurrent,
            scatter_resolve_stored_secondary_jacobian(contributorReconnection),
            1.0f
        );

        prevWeightSum = state.weightSum;
        splat_resample_temporal_pairwise_mis(
            state,
            canonicalReservoir,
            currentSurface,
            pixelPosition,
            shiftedReservoir,
            prevSurface,
            sourcePixel,
            pHatPrev,
            confidenceWeightSum,
            contributorNormalization * contributorSupportWeight * contributorProposalMatch,
            splatJacobian,
            contributorSupportWeight * contributorProposalMatch,
            rng
        );

        if (state.weightSum != prevWeightSum && state.lightData == shiftedReservoir.lightData) {
            selectedPrevReconnection = contributorReconnection;
            selectedFromPrev = true;
        }
    }

    if (backupCandidateCount > 0 && state.weightSum <= 0.0f) {
        state = canonicalReservoir;
        selectedPrevReconnection = scatter_empty_reconnection();
        selectedFromPrev = false;
    }

    area_streaming_resample_finalize_mis(
        state, canonicalReservoir, canonicalReservoir.targetPdf, rng);

    state.weightSum = (state.targetPdf > 0.0f)
        ? (state.weightSum / state.targetPdf) : 0.0f;

    lt_area_finalize_candidate(state, pixelPosition, state.pathSample);
    if (RTXDI_IsValidDIReservoir(state)) {
        result = state;
    }

    float propagatedConfidence = lt_scatter_compute_history_confidence(pixelPosition, currentSurface, result);
    RAB_LightSample resultLight = lt_decode_reservoir_sample_for_frame(
        result,
        currentSurface,
        false,
        false
    );
    reconnection = scatter_build_reconnection(
        currentSurface,
        result,
        resultLight,
        pixelPosition,
        scatter_clamp_reconnection_confidence(propagatedConfidence),
        jSubPixelCurrent
    );

    if (selectedFromPrev && scatter_reconnection_matches_surface(selectedPrevReconnection, pixelPosition, currentSurface)) {
        reconnection.confidence = scatter_clamp_reconnection_confidence(propagatedConfidence);
    }

    return result;
}
#endif
#endif // PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS (opened at line 3222)

// Legacy fused temporal resampling path removed.
// The active implementation is the explicit reprojection -> binning -> scatter stage chain.
#include "/photonics/lighttree/restir_di_temporal.glsl"

//  Area-ReSTIR Core: Shift Mappings, Jacobians, and Pairwise MIS
//  Adapted from NVIDIA Area-ReSTIR (Resampling.slang, Params.slang)
//  for our GLSL 430 / Minecraft ray tracing context.
// ============================================================================

// --- Shift mapping enums (Params.slang) ---
// NOTE: AREA_RESTIR_SHIFT_* constants are defined earlier (before lt_area_temporal_resampling)
// to satisfy GLSL's declaration-before-use requirement.

const float AREA_RESTIR_FLOAT_EPSILON = 0.0001f;

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
bool RAB_AreMaterialsSimilar(uint materialA, uint materialB)
{
    return materialA == materialB;
}
#endif
// --- JacobianEvalData struct (PixelAreaSampleData.slang) ---
// Stores per-pixel shift evaluation data for Jacobian computation.
struct AreaJacobianEvalData {
    float lensToPixelDist;    // d0: distance from lens sample to pixel sample position on focal plane
    float pixelToRcHitDist;   // d1: distance from pixel sample position to reconnection hit
    vec3  rayDir;             // omega_0: primary ray direction
    vec2  lensUV;             // lens sample UV
};

AreaJacobianEvalData area_jacobian_eval_data_empty() {
    AreaJacobianEvalData d;
    d.lensToPixelDist = 0.0f;
    d.pixelToRcHitDist = 0.0f;
    d.rayDir = vec3(0.0f, 0.0f, -1.0f);
    d.lensUV = vec2(0.0f);
    return d;
}

// --- Pairwise MIS weight functions (Resampling.slang lines 192-219) ---
// All four variants: defensive/non-defensive x canonical/non-canonical.
// out_J = |inverse(T_i'(y))| -> Jacobian from target to source domain.

// Non-defensive, non-canonical: MIS weight for the neighbor sample
float area_pairwise_mis_non_defensive_non_canonical(
    float cSum, float c0, float pi, float c1, float pc, float out_J)
{
    float pHatFrom_i = pi * out_J;
    return (pc == 0.0f) ? 0.0f : c0 * pHatFrom_i / ((cSum - c1) * pHatFrom_i + c1 * pc);
}

// Non-defensive, canonical: MIS weight contribution for the canonical sample
float area_pairwise_mis_non_defensive_canonical(
    float cSum, float c0, float pi, float c1, float pc, float out_J)
{
    float pHatFrom_i = pi * out_J;
    float w = c1 * pc;
    return (pc == 0.0f) ? 0.0f : (c0 / (cSum - c1)) * w / ((cSum - c1) * pHatFrom_i + w);
}

// Defensive, non-canonical: MIS weight for the neighbor sample (defensive variant)
float area_pairwise_mis_defensive_non_canonical(
    float cSum, float c0, float pi, float c1, float pc, float out_J)
{
    float pHatFrom_i = pi * out_J;
    float w = (cSum - c1) * pHatFrom_i;
    return (pc == 0.0f) ? 0.0f : (c0 / cSum) * w / (w + c1 * pc);
}

// Defensive, canonical: MIS weight contribution for the canonical sample (defensive variant)
float area_pairwise_mis_defensive_canonical(
    float cSum, float c0, float pi, float c1, float pc, float out_J)
{
    float pHatFrom_i = pi * out_J;
    float w = c1 * pc;
    return (pc == 0.0f) ? 0.0f : (c0 / cSum) * w / ((cSum - c1) * pHatFrom_i + w);
}

// --- Jacobian evaluation for reconnection (Resampling.slang lines 326-340) ---
// Computes the Jacobian determinant |T'(x)| from source to target domain
// for the primary-hit reconnection shift mapping.
//
// Parameters follow the reference naming:
//   d0, d1       = lens-to-pixel and pixel-to-reconnection-hit distances (base path)
//   dir          = primary ray direction (base)
//   n0, n1       = camera (focal plane) normal and reconnection-hit normal (base)
//   d0_shifted, d1_shifted, dir_shifted, n0_shifted, n1_shifted = same for shifted path
float area_eval_jacobian_for_reconnection(
    float d0, float d1, vec3 dir, vec3 n0, vec3 n1,
    float d0_shifted, float d1_shifted, vec3 dir_shifted, vec3 n0_shifted, vec3 n1_shifted)
{
    // partial1 = (d0'^2 * dot(dir', n1')) / (dot(dir', n0') * d1'^2)
    float det_partial1_denom = dot(dir_shifted, n0_shifted) * d1_shifted * d1_shifted;
    float det_partial1 = (det_partial1_denom == 0.0f)
        ? 0.0f
        : (d0_shifted * d0_shifted * dot(dir_shifted, n1_shifted)) / det_partial1_denom;

    // partial2 = (d1^2 * dot(dir, n0)) / (dot(dir, n1) * d0^2)
    float det_partial2_denom = dot(dir, n1) * d0 * d0;
    float det_partial2 = (det_partial2_denom == 0.0f)
        ? 0.0f
        : (d1 * d1 * dot(dir, n0)) / det_partial2_denom;

    return det_partial1 * det_partial2;
}

// Overload using AreaJacobianEvalData structs
float area_eval_jacobian_for_reconnection(
    AreaJacobianEvalData baseData, vec3 baseCameraNormalW, vec3 baseRcNormalW,
    AreaJacobianEvalData shiftedData, vec3 shiftedCameraNormalW, vec3 shiftedRcNormalW)
{
    return area_eval_jacobian_for_reconnection(
        baseData.lensToPixelDist, baseData.pixelToRcHitDist, baseData.rayDir,
        baseCameraNormalW, baseRcNormalW,
        shiftedData.lensToPixelDist, shiftedData.pixelToRcHitDist, shiftedData.rayDir,
        shiftedCameraNormalW, shiftedRcNormalW
    );
}

// --- Ray-plane intersection in world space (Resampling.slang line 343-347) ---
vec3 area_ray_plane_intersection(vec3 rayOrigin, vec3 rayDir, vec3 planeOrigin, vec3 planeNormal) {
    float denom = dot(rayDir, planeNormal);
    float t = abs(dot(rayOrigin - planeOrigin, planeNormal) / (abs(denom) > 1e-12f ? denom : 1e-12f));
    return rayOrigin + t * rayDir;
}

// --- Circle of Confusion computation (Resampling.slang lines 349-367) ---
// In our Minecraft context with a pinhole camera (apertureRadius=0), CoC is always 0.
// We provide this function for future DoF support and for the MIS confidence weight scaling.
float area_compute_circle_of_confusion(vec3 primaryHitPosW) {
    // For pinhole camera, CoC = 0 always. If DoF is ever added, compute here.
    // The reference formula: dFocal = dLens * |z - focalDist| / |z|, then scale to screen pixels.
    return 0.0f;
}

// --- Confidence weight scaling for two-shift MIS (Resampling.slang lines 573-617) ---
// When using MIS mode (both random replay + reconnection), this scales the confidence
// weight of each shift based on circle of confusion. For pinhole camera, returns 0.5.
float area_compute_confidence_weight_for_two_shifts(vec3 primaryHitPosW) {
    // With pinhole camera (CoC=0), both shifts get equal weight.
    // If DoF is added, use the fitted functions from the reference.
    float coc = area_compute_circle_of_confusion(primaryHitPosW);
    if (coc <= 2.0f) return 0.5f;

    // Fitted function from reference (scalingFunctionIndex=0):
    // coefficients = (8.96701974, -8.27136859, 0.15271796)
    float result = 8.96701974f / (coc - (-8.27136859f)) + 0.15271796f;
    return clamp(result, 0.2f, 1.0f);
}

// --- Compute JacobianEvalData at the base (origin) path ---
// (Resampling.slang lines 369-397)
// For our pinhole camera: apertureRadius=0, so lens sample position = camera position,
// and d0 (lensToPixelDist) is the distance from camera to the focal plane sample point.
AreaJacobianEvalData area_compute_jacobian_eval_data_at_base(
    RTXDI_DIReservoir reservoir,
    RAB_Surface rcSurface,
    vec3 cameraPosW,
    ivec2 originPixel)
{
    AreaJacobianEvalData jEvalData = area_jacobian_eval_data_empty();

    if (!RAB_IsSurfaceValid(rcSurface)) return jEvalData;

    vec3 rcHitPosW = rcSurface.worldPos;

    // For pinhole camera: lens sample position = camera position (apertureRadius = 0)
    vec3 lensSamplePosW = cameraPosW;

    // Pixel sample position on the focal plane in world space.
    // In our engine, the pixel on the focal plane is effectively the surface hit itself
    // for the purpose of the Jacobian computation. However, to match the reference's
    // geometry exactly, we compute the "virtual focal plane point" by unprojecting the pixel.
    //
    // For pinhole camera, the pixel sample world pos lies along the camera-to-hit ray
    // at distance 1 from the camera (the near plane acts as focal plane).
    // We use the view direction derived from the pixel position.
    vec2 pixelSampleUV = lt_area_has_valid_domain(reservoir)
        ? reservoir.pixelSampleUV
        : lt_area_default_pixel_sample(originPixel);

    // Compute the ray direction from camera through the pixel
    // viewDir stored in surface points toward camera, so negate it
    vec3 rayDir = -rcSurface.viewDir;

    // For pinhole camera:
    //   d0 (lensToPixelDist) = distance from camera to the "focal plane" point.
    //   Since we have no real focal plane, use 1.0 as a normalized distance
    //   (the Jacobian ratio cancels this out between base and shifted paths).
    //   d1 (pixelToRcHitDist) = distance from camera to hit minus d0
    //
    // Actually, for the Jacobian to be correct, d0 and d1 must relate to actual geometry.
    // For pinhole: lens=camera, focal plane = near plane.
    // d0 = distance(camera, focalPlanePoint), d1 = distance(focalPlanePoint, rcHit)
    // But with pinhole, the "focal plane point" coincides with the ray origin in a sense.
    // The key insight: for pinhole camera, d0 -> 0, and the Jacobian simplifies.
    //
    // Following the reference more carefully: with apertureRadius=0,
    // lensSamplePosW = cameraPosW, and pixelSamplePosW is computed from NDC.
    // So d0 = distance(camera, pixelOnFocalPlane) and d1 = distance(pixelOnFocalPlane, rcHit).
    //
    // In Minecraft with no DoF, we set focal distance = 1.0 (normalized).
    // The pixel sample world position is at cameraPosW + rayDir * focalDist.
    float focalDist = 1.0f; // Pinhole approximation: unit focal distance
    vec3 pixelSamplePosW = cameraPosW + rayDir * focalDist;

    float lensToPixelDist = length(pixelSamplePosW - lensSamplePosW); // d0
    float pixelToRcHitDist = length(rcHitPosW - pixelSamplePosW);    // d1

    jEvalData.lensToPixelDist = lensToPixelDist;
    jEvalData.pixelToRcHitDist = pixelToRcHitDist;
    jEvalData.rayDir = rayDir;
    jEvalData.lensUV = lt_area_has_valid_domain(reservoir) ? reservoir.lensSampleUV : lt_area_default_lens_sample();

    return jEvalData;
}

// --- Random Replay Shift (Resampling.slang lines 311-323) ---
// Retraces the primary ray at the shifted pixel with the same sub-pixel/lens UV.
// In our Minecraft context: re-read the G-buffer at the shifted pixel position
// and evaluate the target function there.
//
// Parameters:
//   reservoir:    the candidate reservoir being shifted
//   baseSurface:  surface at the base (origin) pixel
//   shiftedPixel: pixel position in the shifted (target) domain
//   isShiftedToPrevFrame: whether the shifted domain is the previous frame
//   pHatFromShiftedDomain [out]: target PDF evaluated at the shifted surface
//   jacobian [out]: Jacobian of the shift (always 1.0 for random replay)
//   shiftedLensSampleUV [out]: lens UV at shifted path (same as reservoir's)
//   shiftedSurface [out]: the G-buffer surface at the shifted pixel
void area_eval_phat_and_jacobian_random_replay(
    RTXDI_DIReservoir reservoir,
    RAB_Surface baseSurface,
    ivec2 shiftedPixel,
    bool isShiftedToPrevFrame,
    inout RTXDI_RandomSamplerState rng,
    out float pHatFromShiftedDomain,
    out float jacobian,
    out vec2 shiftedPixelSampleUV,
    out vec2 shiftedLensSampleUV,
    out RAB_Surface shiftedSurface)
{
    // Re-read G-buffer at the shifted pixel (this is our "retrace primary ray")
    shiftedSurface = RAB_GetGBufferSurface(shiftedPixel, isShiftedToPrevFrame);

    // Decode the reservoir's light sample at the shifted surface
    RAB_LightSample shiftedLightSample = lt_decode_reservoir_sample_for_frame(
        reservoir,
        shiftedSurface,
        !isShiftedToPrevFrame,  // reservoir is from the opposite frame
        isShiftedToPrevFrame
    );

    // Evaluate target PDF at the shifted surface
    pHatFromShiftedDomain = lt_surface_target_pdf(shiftedSurface, shiftedLightSample);

    // Random replay Jacobian is always 1.0
    jacobian = 1.0f;

    shiftedPixelSampleUV = lt_area_has_valid_domain(reservoir)
        ? lt_area_clamp_pixel_sample_uv(reservoir.pixelSampleUV)
        : lt_area_default_pixel_sample(shiftedPixel);

    // Lens UV is unchanged
    shiftedLensSampleUV = lt_area_has_valid_domain(reservoir)
        ? reservoir.lensSampleUV
        : lt_area_default_lens_sample();

    // If base surface validity doesn't match shifted surface validity, zero out
    if (RAB_IsSurfaceValid(baseSurface) != RAB_IsSurfaceValid(shiftedSurface)) {
        pHatFromShiftedDomain = 0.0f;
    }
}

// --- Reconnection Shift (Resampling.slang lines 400-509) ---
// Keeps the same primary hit position, computes a new viewing ray from the
// shifted pixel/lens to the same hit, finds the implied lens position via
// ray-plane intersection, and computes the Jacobian.
//
// In our Minecraft pinhole camera context:
//   - The shifted camera position IS the camera position for that frame
//   - apertureRadius = 0, so lens = camera position
//   - The "reconnection" is simply: same hit point, different viewing direction
//   - Jacobian accounts for the geometric factor change
void area_eval_phat_and_jacobian_reconnection(
    RTXDI_DIReservoir reservoir,
    RAB_Surface rcSurface,        // surface at the reconnection hit (base path's primary hit)
    vec3 originCameraPosW,        // camera position for the origin path
    ivec2 originPixel,            // origin pixel position
    vec3 shiftedCameraPosW,       // camera position for the shifted path
    ivec2 shiftedPixel,           // shifted pixel position
    bool isShiftedToPrevFrame,
    inout RTXDI_RandomSamplerState rng,
    out float pHatFromShiftedDomain,
    out float jacobian,
    out vec2 shiftedPixelSampleUV,
    out vec2 shiftedLensSampleUV,
    out RAB_Surface shiftedSurface,
    out AreaJacobianEvalData jEvalDataShifted)
{
    // Default output values
    pHatFromShiftedDomain = 0.0f;
    jacobian = 1.0f;
    shiftedPixelSampleUV = lt_area_default_pixel_sample(shiftedPixel);
    shiftedLensSampleUV = vec2(0.0f);
    shiftedSurface = rcSurface;  // Default to the base surface
    jEvalDataShifted = area_jacobian_eval_data_empty();

    // Reconnection cannot reuse invalid (background) surfaces
    if (!RAB_IsSurfaceValid(rcSurface)) {
        return;
    }

    // Compute Jacobian eval data at the base (origin) path
    AreaJacobianEvalData jEvalDataBase = area_compute_jacobian_eval_data_at_base(
        reservoir, rcSurface, originCameraPosW, originPixel);

    // Reconnection hit position (same for both paths — that's the whole point)
    vec3 rcHitPosW = rcSurface.worldPos;

    // --- Compute shifted path geometry ---
    // For pinhole camera: shifted lens sample position = shifted camera position
    vec3 shiftedLensSamplePosW = shiftedCameraPosW;

    // Shifted pixel sample on focal plane (analogous to base path computation)
    // Compute the shifted ray direction from the shifted camera through the shifted pixel
    // to the reconnection hit
    vec3 shiftedRayDir = normalize(rcHitPosW - shiftedCameraPosW);

    // For pinhole camera: the "pixel sample world position" is at camera + rayDir * focalDist
    float focalDist = 1.0f;
    vec3 shiftedPixelSamplePosW = shiftedCameraPosW + shiftedRayDir * focalDist;

    // Distances for Jacobian
    float shiftedLensToPixelDist = length(shiftedPixelSamplePosW - shiftedLensSamplePosW); // d0'
    float shiftedPixelToRcHitDist = length(rcHitPosW - shiftedPixelSamplePosW);            // d1'

    // Camera forward (focal plane normal). The Jacobian formula's n0 parameter is the
    // focal plane normal — the camera's forward direction — NOT the per-pixel ray direction.
    // In the reference (ShiftMapping.slang), this is normalize(cameraData.cameraW), which is
    // the same vector for all pixels. Using per-pixel ray directions was incorrect and caused
    // systematic MIS weight bias at screen edges.
    //
    // For our engine, camera forward in world space is -Z transformed by the model-view matrix.
    // The origin camera uses the current model-view; for temporal reuse the shifted camera
    // uses the previous model-view. For spatial reuse (same frame), both use current.
    bool baseIsPrevFrame = !isShiftedToPrevFrame;
    vec3 originCameraForward = baseIsPrevFrame
        ? normalize(mat3(gbufferPreviousModelView) * vec3(0.0f, 0.0f, -1.0f))
        : normalize(mat3(gbufferModelView) * vec3(0.0f, 0.0f, -1.0f));
    vec3 shiftedCameraForward = isShiftedToPrevFrame
        ? normalize(mat3(gbufferPreviousModelView) * vec3(0.0f, 0.0f, -1.0f))
        : normalize(mat3(gbufferModelView) * vec3(0.0f, 0.0f, -1.0f));

    // Reconnection-hit normal
    vec3 rcNormalW = rcSurface.geoNormal;

    // Compute Jacobian from base to shifted path
    jEvalDataShifted.lensToPixelDist = shiftedLensToPixelDist;
    jEvalDataShifted.pixelToRcHitDist = shiftedPixelToRcHitDist;
    jEvalDataShifted.rayDir = shiftedRayDir;
    jEvalDataShifted.lensUV = vec2(0.5f); // pinhole: lens center

    jacobian = area_eval_jacobian_for_reconnection(
        jEvalDataBase.lensToPixelDist, jEvalDataBase.pixelToRcHitDist, jEvalDataBase.rayDir,
        originCameraForward, rcNormalW,
        shiftedLensToPixelDist, shiftedPixelToRcHitDist, shiftedRayDir,
        shiftedCameraForward, rcNormalW  // Same hit normal for both (reconnection keeps hit)
    );

    // Handle degenerate cases
    if (abs(jacobian) < 1e-8f || isinf(jacobian) || isnan(jacobian)) {
        jacobian = 0.0f;
        pHatFromShiftedDomain = 0.0f;
        return;
    }
    jacobian = abs(jacobian);

    // Handle special case: same pixel and pinhole camera (no shift needed)
    if (all(equal(originPixel, shiftedPixel)) && all(lessThan(abs(originCameraPosW - shiftedCameraPosW), vec3(AREA_RESTIR_FLOAT_EPSILON)))) {
        pHatFromShiftedDomain = reservoir.targetPdf;
        jacobian = 1.0f;
        return;
    }

    // Build the shifted surface: same hit point, but with the new viewing direction
    // For the reconnection shift, we view the same surface from a different angle.
    // Create a modified surface with the shifted view direction.
    shiftedSurface = rcSurface;
    shiftedSurface.viewDir = normalize(shiftedCameraPosW - rcHitPosW);
    shiftedSurface.viewDepth = length(rcHitPosW - shiftedCameraPosW);

    // Evaluate target PDF at the shifted surface with the new viewing direction
    RAB_LightSample shiftedLightSample = lt_decode_reservoir_sample_for_frame(
        reservoir,
        shiftedSurface,
        !isShiftedToPrevFrame,
        isShiftedToPrevFrame
    );

    // Use the view-dependent target PDF to account for the changed viewing angle
    pHatFromShiftedDomain = lt_surface_target_pdf_with_view(
        shiftedSurface, shiftedLightSample, shiftedCameraPosW);

    // Check BRDF validity: if the shifted viewing angle makes the BRDF degenerate, reject
    if (dot(shiftedSurface.viewDir, shiftedSurface.geoNormal) < AREA_RESTIR_FLOAT_EPSILON) {
        pHatFromShiftedDomain = 0.0f;
    }

    shiftedPixelSampleUV = lt_area_default_pixel_sample(shiftedPixel);
    shiftedLensSampleUV = vec2(0.5f); // Pinhole camera: lens center
}

// --- findShiftMapping (Resampling.slang lines 512-529) ---
// Selects which shift mapping to use based on the mode and pass index.
uint area_find_shift_mapping(uint shiftMappingMode, vec3 basePrimaryHitPosW, uint passIdx) {
    if (shiftMappingMode == AREA_RESTIR_SHIFT_MODE_ONLY_RANDOM_REPLAY) {
        return AREA_RESTIR_SHIFT_RANDOM_REPLAY;
    } else if (shiftMappingMode == AREA_RESTIR_SHIFT_MODE_ONLY_RECONNECTION) {
        return AREA_RESTIR_SHIFT_RECONNECTION;
    } else if (shiftMappingMode == AREA_RESTIR_SHIFT_MODE_MIS) {
        return (passIdx == 0u) ? AREA_RESTIR_SHIFT_RANDOM_REPLAY : AREA_RESTIR_SHIFT_RECONNECTION;
    }
    return 0xFFFFFFFFu; // Invalid
}

// --- Shift dispatcher (Resampling.slang lines 531-547) ---
// Dispatches to random replay or reconnection shift based on selectedShiftMapping.
void area_eval_phat_and_jacobian(
    uint selectedShiftMapping,
    RTXDI_DIReservoir reservoir,
    RAB_Surface baseSurface,
    vec3 baseCameraPosW,
    ivec2 basePixel,
    vec3 shiftedCameraPosW,
    ivec2 shiftedPixel,
    bool isShiftedToPrevFrame,
    inout RTXDI_RandomSamplerState rng,
    out float pHatFromShiftedDomain,
    out float jacobian,
    out vec2 shiftedPixelSampleUV,
    out vec2 shiftedLensSampleUV,
    out RAB_Surface shiftedSurface)
{
    // Default outputs
    pHatFromShiftedDomain = 0.0f;
    jacobian = 1.0f;
    shiftedPixelSampleUV = lt_area_default_pixel_sample(shiftedPixel);
    shiftedLensSampleUV = vec2(0.0f);
    shiftedSurface = baseSurface;

    if (selectedShiftMapping == AREA_RESTIR_SHIFT_RANDOM_REPLAY) {
        area_eval_phat_and_jacobian_random_replay(
            reservoir, baseSurface, shiftedPixel, isShiftedToPrevFrame, rng,
            pHatFromShiftedDomain, jacobian, shiftedPixelSampleUV, shiftedLensSampleUV, shiftedSurface);
    } else if (selectedShiftMapping == AREA_RESTIR_SHIFT_RECONNECTION) {
        AreaJacobianEvalData dummyData;
        area_eval_phat_and_jacobian_reconnection(
            reservoir, baseSurface,
            baseCameraPosW, basePixel,
            shiftedCameraPosW, shiftedPixel,
            isShiftedToPrevFrame, rng,
            pHatFromShiftedDomain, jacobian, shiftedPixelSampleUV, shiftedLensSampleUV,
            shiftedSurface, dummyData);
    }
}

// --- Full pairwise MIS resampling with shift mappings (Resampling.slang lines 620-700) ---
// This performs one step of pairwise MIS resampling between a canonical reservoir
// and a candidate reservoir, using the selected shift mapping to evaluate target PDFs
// and Jacobians in the canonical domain.
void area_resample_reservoir_pairwise_mis(
    inout RTXDI_DIReservoir state,
    RTXDI_DIReservoir canonicalReservoir,
    RAB_Surface canonicalSurface,
    ivec2 canonicalPixel,
    RTXDI_DIReservoir candidateReservoir,
    RAB_Surface candidateSurface,
    ivec2 candidatePixel,
    bool useMFactor,
    float confidenceWeightSum,
    float candidateBilinearWeight,
    bool isTemporalReusing,
    uint shiftMappingMode,
    inout RTXDI_RandomSamplerState rng)
{
    float pHatCanonical = canonicalReservoir.targetPdf;
    float pHatCandidate = candidateReservoir.targetPdf;

    vec3 currCameraPos = world_camera_position;
    vec3 candidateCameraPos = isTemporalReusing ? previous_world_camera_position : currCameraPos;

    float confidenceWeightScaler = 1.0f;
    uint numPasses = 1u;
    if (shiftMappingMode == AREA_RESTIR_SHIFT_MODE_MIS) {
        numPasses = 2u;
        confidenceWeightScaler = area_compute_confidence_weight_for_two_shifts(candidateSurface.worldPos);
    }

    for (uint pass = 0u; pass < numPasses; ++pass) {
        float passConfScaler = (pass == 0u) ? confidenceWeightScaler : (1.0f - confidenceWeightScaler);
        if (passConfScaler == 0.0f) {
            continue;
        }

        float pHatFromCanonicalForCandidate = 0.0f;
        float inJacobianForCandidate = 1.0f;
        vec2 shiftedCandidatePixelSampleUV = lt_area_default_pixel_sample(canonicalPixel);
        vec2 shiftedCandidateLensSampleUV = vec2(0.0f);
        RAB_Surface shiftedCandidateSurface = RAB_EmptySurface();

        uint selectedShiftMapping = area_find_shift_mapping(
            shiftMappingMode,
            candidateSurface.worldPos,
            pass
        );

        area_eval_phat_and_jacobian(
            selectedShiftMapping,
            candidateReservoir,
            candidateSurface,
            candidateCameraPos,
            candidatePixel,
            currCameraPos,
            canonicalPixel,
            false,
            rng,
            pHatFromCanonicalForCandidate,
            inJacobianForCandidate,
            shiftedCandidatePixelSampleUV,
            shiftedCandidateLensSampleUV,
            shiftedCandidateSurface
        );

        float pHatFromCandidateForCanonical = 0.0f;
        float outJacobianForCanonical = 1.0f;
        vec2 dummyPixelSampleUV = lt_area_default_pixel_sample(candidatePixel);
        vec2 dummyLensSampleUV = vec2(0.0f);
        RAB_Surface dummySurface = RAB_EmptySurface();

        selectedShiftMapping = area_find_shift_mapping(
            shiftMappingMode,
            canonicalSurface.worldPos,
            pass
        );

        area_eval_phat_and_jacobian(
            selectedShiftMapping,
            canonicalReservoir,
            canonicalSurface,
            currCameraPos,
            canonicalPixel,
            candidateCameraPos,
            candidatePixel,
            isTemporalReusing,
            rng,
            pHatFromCandidateForCanonical,
            outJacobianForCanonical,
            dummyPixelSampleUV,
            dummyLensSampleUV,
            dummySurface
        );

        float confidenceWeightFromCandidate = passConfScaler * candidateReservoir.M * candidateBilinearWeight;
        float invInJacobian = (inJacobianForCandidate > 1e-8f) ? (1.0f / inJacobianForCandidate) : 0.0f;

        float m0NonDefensive = area_pairwise_mis_non_defensive_non_canonical(
            confidenceWeightSum,
            confidenceWeightFromCandidate,
            pHatCandidate,
            canonicalReservoir.M,
            pHatFromCanonicalForCandidate,
            invInJacobian
        );
        float m0Defensive = area_pairwise_mis_defensive_non_canonical(
            confidenceWeightSum,
            confidenceWeightFromCandidate,
            pHatCandidate,
            canonicalReservoir.M,
            pHatFromCanonicalForCandidate,
            invInJacobian
        );
        float m1NonDefensive = area_pairwise_mis_non_defensive_canonical(
            confidenceWeightSum,
            confidenceWeightFromCandidate,
            pHatFromCandidateForCanonical,
            canonicalReservoir.M,
            pHatCanonical,
            outJacobianForCanonical
        );
        float m1Defensive = area_pairwise_mis_defensive_canonical(
            confidenceWeightSum,
            confidenceWeightFromCandidate,
            pHatFromCandidateForCanonical,
            canonicalReservoir.M,
            pHatCanonical,
            outJacobianForCanonical
        );

        float m0 = isTemporalReusing ? m0NonDefensive : m0Defensive;
        float m1 = isTemporalReusing ? m1NonDefensive : m1Defensive;
        float sampleWeight = m0 * pHatFromCanonicalForCandidate * candidateReservoir.weightSum * inJacobianForCandidate;

        float mScaler = min(
            rtxdi_m_factor(pHatCandidate, pHatFromCanonicalForCandidate),
            rtxdi_m_factor(pHatFromCandidateForCanonical, pHatCanonical)
        );

        state.M += confidenceWeightFromCandidate * (useMFactor ? mScaler : 1.0f);
        state.weightSum += sampleWeight;
        state.canonicalWeight += m1;

        bool selectSample = false;
        if (candidateBilinearWeight > 0.0f && sampleWeight > 0.0f && state.weightSum > 0.0f) {
            selectSample = lt_next_random(rng) * state.weightSum < sampleWeight;
        }

        if (selectSample) {
            vec2 shiftedPixelSampleUV = shiftedCandidatePixelSampleUV;
            state.targetPdf = pHatFromCanonicalForCandidate;
            state.lightData = candidateReservoir.lightData;
            state.uvData = candidateReservoir.uvData;
            state.pixelSampleUV = shiftedPixelSampleUV;
            state.pathSample = candidateReservoir.pathSample;
            state.lensSampleUV = shiftedCandidateLensSampleUV;
            // Clearing visibility completely kept for reference:
            // state.packedVisibility = 0u;
            // Restored reuse keeps convergence while earlier proposal/boundary fixes reduce flicker.
            state.packedVisibility = candidateReservoir.packedVisibility;
            state.age = candidateReservoir.age;
            state.spatialDistance = candidateReservoir.spatialDistance;
        }
    }
}

// --- Streaming resample finalize MIS (Resampling.slang lines 703-721) ---

bool area_streaming_resample_finalize_mis(
    inout RTXDI_DIReservoir state,
    RTXDI_DIReservoir canonicalReservoir,
    float canonicalTargetPdf,
    inout RTXDI_RandomSamplerState rng)
{
    float sampleWeight = state.canonicalWeight * canonicalTargetPdf * canonicalReservoir.weightSum;

    state.M += canonicalReservoir.M;
    state.weightSum += sampleWeight;

    bool selectSample = false;
    if (sampleWeight > 0.0f && state.weightSum > 0.0f) {
        selectSample = lt_next_random(rng) * state.weightSum < sampleWeight;
    }
    if (selectSample) {
        state.targetPdf = canonicalTargetPdf;
        state.lightData = canonicalReservoir.lightData;
        state.uvData = canonicalReservoir.uvData;
        state.pixelSampleUV = canonicalReservoir.pixelSampleUV;
        state.lensSampleUV = canonicalReservoir.lensSampleUV;
        state.pathSample = canonicalReservoir.pathSample;
        state.packedVisibility = canonicalReservoir.packedVisibility;
        state.age = canonicalReservoir.age;
        state.spatialDistance = canonicalReservoir.spatialDistance;
    }

    return selectSample;
}

// ============================================================================
//  End of Area-ReSTIR Core Functions
// ============================================================================

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

RTXDI_DIReservoir rtxdi_stream_local_light(
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

#endif
