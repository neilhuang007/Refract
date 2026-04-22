#ifndef PH_LIGHTTREE_REUSE_INCLUDE
#define PH_LIGHTTREE_REUSE_INCLUDE

#include "/photonics/lighttree/restir_di_temporal_buffer_bridge.glsl"

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)
#define PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY
#endif

void lt_SortReprojectedReservoirs_compute_cell_offsets(ivec2 pixel);
void lt_SortReprojectedReservoirs_sort_cell_data(uint scatterIndex);
void lt_MultiSortReprojectedReservoirs_compute_cell_offsets(ivec2 pixel);
void lt_MultiSortReprojectedReservoirs_sort_cell_data(uint scatterIndex);

#ifndef PH_LIGHTTREE_INITIAL_SAMPLE_COUNT_HELPERS
#define PH_LIGHTTREE_INITIAL_SAMPLE_COUNT_HELPERS
int lt_resolve_initial_num_environment_samples();
int lt_resolve_initial_num_brdf_samples();
#endif

#include "/photonics/lighttree/nrd_material_id.glsl"

#ifndef PH_LIGHTTREE_INITIAL_SAMPLES
#define PH_LIGHTTREE_INITIAL_SAMPLES 1
#endif

// RTXDI initial-sampling MIS data: needed by the ReSTIR_DI initial-candidate
// stage regardless of whether the scatter buffers are wired in, so it lives at
// top level instead of inside the SCATTER_BUFFERS gate further below.
#ifndef PH_LIGHTTREE_INITIAL_SAMPLING_MIS_DATA_DECLARED
#define PH_LIGHTTREE_INITIAL_SAMPLING_MIS_DATA_DECLARED
struct RTXDI_InitialSamplingMisData {
    int numMisSamples;              // total candidates across all techniques
    float localLightMisWeight;      // fraction of candidates from local-light sampling
    float environmentMapMisWeight;  // fraction of candidates from environment sampling
    float brdfMisWeight;            // fraction of candidates from BRDF sampling
};
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

// RTXDI: RTXDI_RIS_BUFFER -- declared in light_tree.glsl (included above).
// Unified buffer containing presample tiles and ReGIR output.
// Used as outside-grid fallback in RTXDI_SampleLocalLights, matching RTXDI InitialSampling.hlsli

uniform int  ph_ris_tile_size;            // RTXDI: risBufferSegmentParams.tileSize
uniform int  ph_ris_tile_count;           // RTXDI: risBufferSegmentParams.tileCount
uniform int  ph_ris_tile_buffer_offset;   // RTXDI: risBufferSegmentParams.bufferOffset (typically 0)

// Reverse light mapping: current-frame index -> previous-frame index.
// Inverse of ph_light_list_mapping (previous->current). Built in LightRegistry.java.
// Returns -1 when no previous-frame equivalent exists for the current-frame light.
layout(std430) restrict readonly buffer ph_light_reverse_mapping_buf {
    int ph_light_reverse_mapping[];
};

// Previous-frame light data -- double-buffered copy of ph_light_list from the prior frame.
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

// Initial sampling parameters -- matches RTXDI_DIInitialSamplingParameters (ReSTIRDIParameters.h lines 69-85).
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

// Local light sampling mode -- matches RTXDI_DIInitialSamplingParameters::localLightSamplingMode
// (ReSTIRDI_LocalLightSamplingMode enum in RtxdiParameters.h lines 44-48):
//   -1.0 -> SDK default (Uniform, mode 0)
//    0.0 (unbound) -> SDK default (Uniform, mode 0)
//    0 = ReSTIRDI_LocalLightSamplingMode_UNIFORM   -- equal probability from light buffer
//    1 = ReSTIRDI_LocalLightSamplingMode_POWER_RIS -- power-CDF importance sampling (stratified)
//    2 = ReSTIRDI_LocalLightSamplingMode_REGIR_RIS -- ReGIR cell-based RIS (with Power_RIS fallback)
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

// RTXDI neighbor offset buffer -- 8192 entries generated by FillNeighborOffsetBuffer (RtxdiUtils.cpp).
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

// RTXDI: RAB_EmptySurface() -- returns a zeroed surface with a well-defined up-normal.
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

#include "/photonics/lighttree/restir_di_reconnection_surface.glsl"

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

uint lt_path_sample_proposal_family(uint pathSample);

#include "/photonics/lighttree/restir_di_reconnection_packing.glsl"

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_GATHER_STAGE) || defined(PH_LIGHTTREE_ENABLE_ROBUST_REUSE_STAGE)
struct LtTemporalGatherShiftedPathData {
    vec3 radiance;
    float secondaryPathJacobian;
    float lensVertexJacobian;
    float valid;
};

LtTemporalGatherShiftedPathData LtTemporalGatherShiftedPathData_init()
{
    LtTemporalGatherShiftedPathData shiftedPathData;
    shiftedPathData.radiance = vec3(0.0f);
    shiftedPathData.secondaryPathJacobian = 1.0f;
    shiftedPathData.lensVertexJacobian = 1.0f;
    shiftedPathData.valid = 0.0f;
    return shiftedPathData;
}

LtTemporalGatherShiftedPathData scatter_load_gather_shifted_path_data(ivec2 uv, int offsetIndex)
{
    vec4 shiftedPathData0;
    vec4 shiftedPathData1;
    switch (offsetIndex)
    {
        case 0:
            shiftedPathData0 = texelFetch(temporal_gather_shifted_path_data0, uv, 0);
            shiftedPathData1 = texelFetch(temporal_gather_shifted_path_data1, uv, 0);
            break;
        case 1:
            shiftedPathData0 = texelFetch(temporal_gather_shifted_path_data2, uv, 0);
            shiftedPathData1 = texelFetch(temporal_gather_shifted_path_data3, uv, 0);
            break;
        case 2:
            shiftedPathData0 = texelFetch(temporal_gather_shifted_path_data4, uv, 0);
            shiftedPathData1 = texelFetch(temporal_gather_shifted_path_data5, uv, 0);
            break;
        case 3:
            shiftedPathData0 = texelFetch(temporal_gather_shifted_path_data6, uv, 0);
            shiftedPathData1 = texelFetch(temporal_gather_shifted_path_data7, uv, 0);
            break;
        case 4:
            shiftedPathData0 = texelFetch(temporal_gather_shifted_path_data8, uv, 0);
            shiftedPathData1 = texelFetch(temporal_gather_shifted_path_data9, uv, 0);
            break;
        case 5:
            shiftedPathData0 = texelFetch(temporal_gather_shifted_path_data10, uv, 0);
            shiftedPathData1 = texelFetch(temporal_gather_shifted_path_data11, uv, 0);
            break;
        case 6:
            shiftedPathData0 = texelFetch(temporal_gather_shifted_path_data12, uv, 0);
            shiftedPathData1 = texelFetch(temporal_gather_shifted_path_data13, uv, 0);
            break;
        case 7:
            shiftedPathData0 = texelFetch(temporal_gather_shifted_path_data14, uv, 0);
            shiftedPathData1 = texelFetch(temporal_gather_shifted_path_data15, uv, 0);
            break;
        default:
            return LtTemporalGatherShiftedPathData_init();
    }

    LtTemporalGatherShiftedPathData shiftedPathData = LtTemporalGatherShiftedPathData_init();
    shiftedPathData.radiance = shiftedPathData0.xyz;
    shiftedPathData.secondaryPathJacobian = max(shiftedPathData0.w, 1e-10f);
    shiftedPathData.lensVertexJacobian = max(shiftedPathData1.x, 1e-10f);
    shiftedPathData.valid = shiftedPathData1.y;
    return shiftedPathData;
}

void scatter_store_gather_shifted_path_data(
    LtTemporalGatherShiftedPathData shiftedPathData,
    out vec4 shiftedPathData0,
    out vec4 shiftedPathData1)
{
    shiftedPathData0 = vec4(max(shiftedPathData.radiance, vec3(0.0f)), max(shiftedPathData.secondaryPathJacobian, 1e-10f));
    shiftedPathData1 = vec4(max(shiftedPathData.lensVertexJacobian, 1e-10f), shiftedPathData.valid, 0.0f, 0.0f);
}
#endif

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
    float a = clampedRoughness * clampedRoughness;  // alpha = roughness^2
    float a2 = a * a;                                // alpha^2 = roughness?
    float denom = nDotH * nDotH * (a2 - 1.0f) + 1.0f;
    return a2 / max(lt_pi * denom * denom, 1e-6f);
}

float lt_geometry_schlick_ggx(float nDotX, float roughness) {
    float a = max(roughness, lt_min_roughness) * max(roughness, lt_min_roughness);  // alpha = roughness^2, clamped
    float k = a * 0.5f;                                        // k = alpha/2 (analytic Smith-GGX)
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

#include "/photonics/lighttree/restir_di_reservoir_core.glsl"
#include "/photonics/lighttree/restir_di_reservoir_domain.glsl"

void rtxdi_unpack_reservoir_at_surface(inout RTXDI_DIReservoir reservoir, vec4 color, vec4 sampleData, vec4 meta, RAB_Surface surface, bool remap);
vec3 rtxdi_unpack_visibility(uint packedVisibility);
uint rtxdi_pack_visibility(vec3 visibility);

#include "/photonics/lighttree/restir_di_parameters.glsl"
#include "/photonics/lighttree/restir_rab_surface_light.glsl"
#include "/photonics/lighttree/restir_di_reconnection_build.glsl"

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
        // Scatter temporal resampling output -- same packed format, different texture.
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
    // Unconditional -- no visibility guard. Always track accumulated spatial distance.
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

// Scalar visibility test -- true when at least one channel exceeds 0 via luminance.
// Uses per-channel luminance-weighted sum matching RTXDI's packedVisibility bit test.
bool rtxdi_is_visible(RTXDI_DIReservoir reservoir) {
    return ph_luminance(rtxdi_get_visibility(reservoir)) > 0.0f;
}

// Primary -- matches RTXDI_StoreVisibilityInDIReservoir (RTXDI_DIReservoir.hlsli).
// discardIfInvisible: when true and visibility is fully zero, kill the reservoir light data
// (equivalent to RTXDI discarding an occluded sample). M and targetPdf are always preserved.
void RTXDI_StoreVisibilityInDIReservoir(inout RTXDI_DIReservoir reservoir, vec3 visibility, bool discardIfInvisible) {
    reservoir.packedVisibility = rtxdi_pack_visibility(visibility);
    reservoir.spatialDistance = ivec2(0);
    reservoir.age = 0u;
    if (discardIfInvisible && visibility.x == 0.0f && visibility.y == 0.0f && visibility.z == 0.0f) {
        // RTXDI RTXDI_DIReservoir.hlsli lines 93-96: only clears lightData and weightSum.
        // sampleUv (uvData) is intentionally NOT cleared -- RTXDI leaves it intact.
        // M and targetPdf are also preserved for correct downstream resampling.
        reservoir.lightData = 0u;
        reservoir.weightSum = 0.0f;
    }
}

// Backward-compat alias -- preserves original bool-based call sites.
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

void RTXDI_BoostVisibilityAge(inout RTXDI_DIReservoir reservoir)
{
    reservoir.age += 1u;
}

void RTXDI_OffsetVisibilityReuse(inout RTXDI_DIReservoir reservoir, ivec2 offset)
{
    reservoir.spatialDistance += offset;
}

void rtxdi_inherit_visibility(
    inout RTXDI_DIReservoir reservoir,
    RTXDI_DIReservoir sourceReservoir,
    ivec2 currentUv,
    ivec2 sourceUv,
    bool temporalReuse
) {
    rtxdi_copy_visibility(reservoir, sourceReservoir);
    RTXDI_BoostVisibilityAge(reservoir);
    if (temporalReuse) {
        reservoir.spatialDistance = ivec2(0);
    } else {
        reservoir.spatialDistance = sourceReservoir.spatialDistance;
        RTXDI_OffsetVisibilityReuse(reservoir, sourceUv - currentUv);
    }
}

// Primary -- matches RTXDI_StreamSample signature (RTXDI_DIReservoir.hlsli).
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

// Primary -- matches RTXDI_InternalSimpleResample exactly (RTXDI_DIReservoir.hlsli lines 192-225).
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
// Uses reservoir.targetPdf as the denominator base -- call this for temporal/bias-correction paths.
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

#include "/photonics/lighttree/restir_di_reservoir_packing.glsl"

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
// splat helpers, and ``lt_materials_similar``/``IsComplexSurface`` -- all of
// which are consumed by non-scatter passes (GenerateInitialSamples,
// SpatialResampling, GatherTemporalResampling, Shade*). The guard has been
// removed; the narrower ``#if`` blocks below still protect the scatter-SSBO
// touching code (append/sort/resolve cells) so non-scatter passes compile
// cleanly while the splatting pipeline keeps its storage buffers.
// Tracks per-technique sample counts and their MIS weights for blended source PDF computation.
// The canonical declaration lives near the top of this file so every include
// surface sees one shared struct definition.

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

// Backward-compat overload -- passes localLightMisWeight=1.0 (no MIS blending).
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
//   -1.0 or 0.0 (unbound) -> SDK default = Uniform (mode 0)
//   0 = Uniform:   lt_pick_uniform_light for all samples
//   1 = Power_RIS: stratified RIS tile sampling for all samples
//   2 = ReGIR_RIS: regir_pick_light inside grid cell, Power_RIS (RIS tile) fallback outside
//
// Split RNG streams -- matches RTXDI InitialSampling.hlsli:
//   rng         (per-pixel random)   -- drives per-sample light selection and UV draws.
//   coherentRng (spatially coherent) -- drives ReGIR cell jitter and RIS tile selection.
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

#include "/photonics/lighttree/restir_di_local_light_selection.glsl"

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


