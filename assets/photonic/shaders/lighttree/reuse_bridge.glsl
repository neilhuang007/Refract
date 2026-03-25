#ifndef PH_LIGHTTREE_REUSE_INCLUDE
#define PH_LIGHTTREE_REUSE_INCLUDE

#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/nrd_material_id.glsl"

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

// Load a light from the previous-frame buffer.
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

    vec4 positionFull    = ph_lights_array_previous[base + 0];
    vec4 colorFull       = ph_lights_array_previous[base + 1];
    vec4 attenuationFull = ph_lights_array_previous[base + 2];
    vec4 orientationFull = ph_lights_array_previous[base + 3];

    return Light(
        index,
        floatBitsToInt(positionFull.w),
        positionFull.xyz - world_offset,
        colorFull.xyz,
        colorFull.w,
        attenuationFull.xy,
        attenuationFull.z,
        attenuationFull.w,
        normalize(orientationFull.xyz + vec3(1e-6f)),
        orientationFull.w
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
uniform float ph_restir_temporal_max_history;      // RTXDI: maxHistoryLength (default 20)
uniform float ph_restir_temporal_depth_threshold;  // RTXDI: temporal depthThreshold (default 0.1)
uniform float ph_restir_temporal_normal_threshold; // RTXDI: temporal normalThreshold (default 0.5)
uniform float ph_restir_spatial_sample_count;      // RTXDI: numSamples (default 1)
uniform float ph_restir_spatial_radius;            // RTXDI: samplingRadius (default 32.0)
// RTXDI: params.activeCheckerboardField (0 = off, 1/2 = alternating fields).
// SDK default (ReSTIRDI.cpp UpdateCheckerboardField): 0 (off) for CheckerboardMode::Off.
// Shared across temporal and spatial passes — declared here so reuse_resolve.fsh can read it.
#ifndef PH_RESTIR_CHECKERBOARD_DECLARED
#define PH_RESTIR_CHECKERBOARD_DECLARED
uniform int ph_restir_active_checkerboard_field;
#endif
uniform float ph_restir_spatial_depth_threshold;   // RTXDI: spatial depthThreshold (default 0.1)
uniform float ph_restir_spatial_normal_threshold;  // RTXDI: spatial normalThreshold (default 0.5)

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

// Local light sampling mode — matches RTXDI_DIInitialSamplingParameters::localLightSamplingMode
// (ReSTIRDI_LocalLightSamplingMode enum in RtxdiParameters.h lines 44-48):
//   -1.0 → SDK default (Uniform, mode 0)
//    0.0 (unbound) → SDK default (Uniform, mode 0)
//    0 = ReSTIRDI_LocalLightSamplingMode_UNIFORM   — equal probability from light buffer
//    1 = ReSTIRDI_LocalLightSamplingMode_POWER_RIS — power-CDF importance sampling (stratified)
//    2 = ReSTIRDI_LocalLightSamplingMode_REGIR_RIS — ReGIR cell-based RIS (with Power_RIS fallback)
// SDK default (ReSTIRDI.cpp line 45): Uniform (0).
uniform float ph_restir_local_light_sampling_mode;

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

ivec2 lt_random_temporal_resampling_offset(float radius) {
    return ivec2(
        int((rand_next_float() - 0.5f) * float(radius)),
        int((rand_next_float() - 0.5f) * float(radius))
    );
}

// RTXDI TemporalResampling.hlsli:
//   0 4 3
//   6 x 7
//   2 5 1
ivec2 lt_calculate_temporal_resampling_offset(int sampleIdx, int radius) {
    sampleIdx &= 7;

    int mask2 = (sampleIdx >> 1) & 0x01;
    int mask4 = 1 - ((sampleIdx >> 2) & 0x01);
    int tmp0 = -1 + 2 * (sampleIdx & 0x01);
    int tmp1 = 1 - 2 * mask2;
    int tmp2 = mask4 | mask2;
    int tmp3 = mask4 | (1 - mask2);

    return ivec2(tmp0, tmp0 * tmp1) * ivec2(tmp2, tmp3) * radius;
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

vec3 lt_resolve_reuse_normal(vec3 geometryNormal, vec3 mappedNormal) {
    float mappedLengthSq = dot(mappedNormal, mappedNormal);
    if (mappedLengthSq > 1e-6f) {
        return normalize(mappedNormal);
    }

    float geometryLengthSq = dot(geometryNormal, geometryNormal);
    if (geometryLengthSq > 1e-6f) {
        return normalize(geometryNormal);
    }

    return vec3(0.0f, 1.0f, 0.0f);
}

struct DirectSurface {
    vec3 worldPos;
    vec3 rtPos;
    vec3 geometryNormal;
    vec3 shadingNormal;
    vec3 albedo;
    vec4 material;
};

DirectSurface lt_load_surface(ivec2 uv);

vec4 lt_extract_material_at_uv(vec2 uv) {
    vec4 spec = texture(specular, uv);
    float smoothness = clamp(spec.r, 0.0f, 1.0f);
    float roughness = clamp(1.0f - smoothness, 0.0f, 1.0f);
    float metallic = clamp(spec.g, 0.0f, 1.0f);
    float emission = clamp(spec.a, 0.0f, 1.0f);
    return vec4(roughness, metallic, emission, nrd_encode_material_id(nrd_derive_material_id(spec)));
}

DirectSurface lt_make_surface(vec3 worldPosValue, vec3 geometryNormalValue, vec3 shadingNormalValue, vec3 albedoValue, vec4 materialValue) {
    return DirectSurface(
        worldPosValue,
        worldPosValue - world_offset,
        lt_resolve_reuse_normal(geometryNormalValue, geometryNormalValue),
        lt_resolve_reuse_normal(geometryNormalValue, shadingNormalValue),
        clamp(albedoValue, vec3(0.0f), vec3(1.0f)),
        materialValue
    );
}

DirectSurface lt_make_surface(vec3 worldPosValue, vec3 geometryNormalValue, vec3 shadingNormalValue, vec4 materialValue) {
    return lt_make_surface(worldPosValue, geometryNormalValue, shadingNormalValue, vec3(1.0f), materialValue);
}

DirectSurface lt_make_surface(vec3 worldPosValue, vec3 geometryNormalValue, vec3 shadingNormalValue) {
    return lt_make_surface(worldPosValue, geometryNormalValue, shadingNormalValue, vec3(1.0f), vec4(0.0f));
}

// RTXDI: RAB_EmptySurface() — returns a zeroed surface with a well-defined up-normal.
// Used to initialize temporalSurface before a valid temporal neighbor is found,
// matching RTXDI TemporalResampling.hlsli line 69: RAB_Surface temporalSurface = RAB_EmptySurface();
DirectSurface lt_empty_surface() {
    return DirectSurface(vec3(0.0), vec3(0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0), vec4(0.0));
}

DirectSurface lt_current_surface() {
    return lt_make_surface(
        world_pos,
        block_normal,
        normal,
        clamp(albedo, vec3(0.04f), vec3(1.0f)),
        lt_extract_material_at_uv((vec2(tex_coord) + vec2(0.5f)) / vec2(viewWidth, viewHeight))
    );
}

DirectSurface lt_load_surface(ivec2 uv) {
    return lt_make_surface(
        texelFetch(radiosity_position, uv, 0).xyz,
        texelFetch(radiosity_normal, uv, 0).xyz,
        texelFetch(radiosity_mapped_normal, uv, 0).xyz,
        clamp(texelFetch(radiosity_albedo, uv, 0).rgb, vec3(0.04f), vec3(1.0f)),
        lt_extract_material_at_uv((vec2(uv) + vec2(0.5)) / vec2(viewWidth, viewHeight))
    );
}

DirectSurface lt_load_previous_surface(ivec2 uv) {
    return lt_make_surface(
        texelFetch(prev_radiosity_position, uv, 0).xyz,
        texelFetch(prev_radiosity_normal, uv, 0).xyz,
        texelFetch(prev_radiosity_mapped_normal, uv, 0).xyz,
        clamp(texelFetch(prev_radiosity_albedo, uv, 0).rgb, vec3(0.04f), vec3(1.0f)),
        texelFetch(prev_radiosity_material, uv, 0)
    );
}

float rtxdi_surface_linear_depth(DirectSurface surface, vec3 cameraPosition) {
    // RTXDI's bridge allows any consistent linear-depth metric. This path stores world positions,
    // so distance to the relevant camera is the stable depth metric used for neighbor validation.
    return length(surface.worldPos - cameraPosition);
}

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

bool lt_surface_matches(DirectSurface currentSurface, DirectSurface sourceSurface, float planeThreshold, float normalThreshold) {
    float currentDepth = rtxdi_surface_linear_depth(currentSurface, world_camera_position);
    float sourceDepth = rtxdi_surface_linear_depth(sourceSurface, world_camera_position);
    return rtxdi_is_valid_neighbor(
        currentSurface.shadingNormal,
        sourceSurface.shadingNormal,
        currentDepth,
        sourceDepth,
        normalThreshold,
        planeThreshold
    );
}

bool lt_surface_matches_temporal(DirectSurface currentSurface, DirectSurface previousSurface, float planeThreshold, float normalThreshold) {
    float expectedPreviousDepth = rtxdi_surface_linear_depth(currentSurface, previous_world_camera_position);
    float previousDepth = rtxdi_surface_linear_depth(previousSurface, previous_world_camera_position);
    return rtxdi_is_valid_neighbor(
        currentSurface.shadingNormal,
        previousSurface.shadingNormal,
        expectedPreviousDepth,
        previousDepth,
        normalThreshold,
        planeThreshold
    );
}

// RTXDI-style temporal neighbor validation with explicitly-provided expected depth.
// Matches RTXDI_IsValidNeighbor called in DITemporalResampling with expectedPrevLinearDepth.
bool RTXDI_IsValidTemporalNeighbor(
    DirectSurface currentSurface,
    DirectSurface candidateSurface,
    float expectedPrevLinearDepth,
    float normalThreshold,
    float depthThreshold
) {
    float candidateDepth = rtxdi_surface_linear_depth(candidateSurface, previous_world_camera_position);
    return rtxdi_is_valid_neighbor(
        currentSurface.shadingNormal,
        candidateSurface.shadingNormal,
        expectedPrevLinearDepth,
        candidateDepth,
        normalThreshold,
        depthThreshold
    );
}

vec3 lt_surface_ray_origin(vec3 samplePos, vec3 geometryNormal) {
    return samplePos + geometryNormal * 0.001f;
}

struct LightSample {
    int index;
    vec3 position;
    vec3 sample_pos;
    vec3 color;
    vec3 dir;
    float solidAnglePdf;
    float weight;
};

LightSample lt_null_sample() {
    return LightSample(-1, vec3(0.0f), vec3(0.0f), vec3(0.0f), vec3(0.0f), 0.0f, 0.0f);
}

const float lt_pi = 3.14159265359f;
const float lt_min_roughness = 0.03f;

struct LightBrdf {
    float demodulatedDiffuse;
    vec3 specular;
};

vec3 lt_surface_f0(DirectSurface surface) {
    float metallic = clamp(surface.material.y, 0.0f, 1.0f);
    return mix(vec3(0.04f), clamp(surface.albedo, vec3(0.0f), vec3(1.0f)), metallic);
}

vec3 lt_fresnel_schlick(float cosTheta, vec3 f0);

float lt_surface_diffuse_probability_with_view(DirectSurface surface, vec3 viewDir) {
    float viewLengthSq = dot(viewDir, viewDir);
    if (viewLengthSq <= 1e-6f) {
        return 1.0f;
    }

    vec3 V = viewDir * inversesqrt(viewLengthSq);
    float diffuseWeight = ph_luminance(clamp(surface.albedo, vec3(0.0f), vec3(1.0f)));
    float specularWeight = ph_luminance(
        lt_fresnel_schlick(
            clamp(dot(V, surface.shadingNormal), 0.0f, 1.0f),
            lt_surface_f0(surface)
        )
    );
    float sumWeights = diffuseWeight + specularWeight;
    return sumWeights < 1e-7f ? 1.0f : diffuseWeight / sumWeights;
}

float lt_surface_diffuse_probability(DirectSurface surface) {
    return lt_surface_diffuse_probability_with_view(surface, rt_camera_position - surface.rtPos);
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

LightBrdf lt_evaluate_surface_brdf_with_view(DirectSurface surface, vec3 lightDir, vec3 viewDir) {
    LightBrdf brdf = LightBrdf(0.0f, vec3(0.0f));

    float lightLengthSq = dot(lightDir, lightDir);
    if (lightLengthSq <= 1e-6f) {
        return brdf;
    }
    lightDir *= inversesqrt(lightLengthSq);

    float nDotL = max(dot(surface.shadingNormal, lightDir), 0.0f);
    if (nDotL <= 0.0f) {
        return brdf;
    }
    float viewLengthSq = dot(viewDir, viewDir);
    if (viewLengthSq <= 1e-6f) {
        return brdf;
    }
    viewDir *= inversesqrt(viewLengthSq);

    brdf.demodulatedDiffuse = nDotL / lt_pi;

    float nDotV = max(dot(surface.shadingNormal, viewDir), 0.0f);
    float roughness = clamp(surface.material.x, 0.0f, 1.0f);
    if (roughness >= lt_min_roughness && nDotV > 0.0f) {
        vec3 halfVector = normalize(viewDir + lightDir);
        float nDotH = max(dot(surface.shadingNormal, halfVector), 0.0f);
        float vDotH = max(dot(viewDir, halfVector), 0.0f);
        vec3 fresnel = lt_fresnel_schlick(vDotH, lt_surface_f0(surface));
        float distribution = lt_distribution_ggx(nDotH, roughness);
        float geometry = lt_geometry_smith(nDotV, nDotL, roughness);
        brdf.specular = distribution * geometry * fresnel / max(4.0f * nDotV, 1e-4f);
    }

    return brdf;
}

LightBrdf lt_evaluate_surface_brdf(DirectSurface surface, vec3 lightDir) {
    return lt_evaluate_surface_brdf_with_view(surface, lightDir, rt_camera_position - surface.rtPos);
}

vec3 lt_light_sample_radiance(Light light, vec3 toLight) {
    float lightDistanceSq = dot(toLight, toLight);
    if (lightDistanceSq <= 1e-6f) {
        return vec3(0.0f);
    }

    vec3 lightDir = toLight * inversesqrt(lightDistanceSq);
    vec3 resultColor = light.color * light.intensity / dot(vec2(1.0f, lightDistanceSq * light.falloff), light.attenuation);

    if (light.orientationSpread < lt_pi) {
        float axisAngle = acos(clamp(dot(light.emissionAxis, -lightDir), -1.0f, 1.0f));
        resultColor *= max(cos(max(axisAngle - light.orientationSpread, 0.0f)), 0.0f);
    }

    return resultColor;
}

vec3 lt_light_sample_incident_radiance(DirectSurface surface, LightSample smple) {
    if (smple.index < 0 || ph_luminance(smple.color) <= 1e-6f) {
        return vec3(0.0f);
    }

    return smple.color;
}

float lt_light_sample_solid_angle_pdf(DirectSurface surface, vec3 lightPosition) {
    // RTXDI reference point lights are analytic and report solidAnglePdf = 1.
    // The Minecraft local-light bridge follows that exact point-light contract.
    return 1.0f;
}

vec3 lt_surface_reflected_radiance_with_view(DirectSurface surface, LightSample smple, vec3 viewDir) {
    vec3 incidentRadiance = lt_light_sample_incident_radiance(surface, smple);
    if (ph_luminance(incidentRadiance) <= 1e-6f) {
        return vec3(0.0f);
    }

    LightBrdf brdf = lt_evaluate_surface_brdf_with_view(surface, smple.dir, viewDir);
    return incidentRadiance * (brdf.demodulatedDiffuse * surface.albedo + brdf.specular);
}

vec3 lt_surface_reflected_radiance(DirectSurface surface, LightSample smple) {
    return lt_surface_reflected_radiance_with_view(surface, smple, rt_camera_position - surface.rtPos);
}

float lt_surface_target_pdf(DirectSurface surface, LightSample smple) {
    if (smple.index < 0 || smple.solidAnglePdf <= 0.0f) {
        return 0.0f;
    }

    return ph_luminance(max(lt_surface_reflected_radiance(surface, smple), vec3(0.0f))) / smple.solidAnglePdf;
}

float lt_surface_target_pdf_with_view(DirectSurface surface, LightSample smple, vec3 viewPos) {
    if (smple.index < 0 || smple.solidAnglePdf <= 0.0f) {
        return 0.0f;
    }

    vec3 incidentRadiance = lt_light_sample_incident_radiance(surface, smple);
    if (ph_luminance(incidentRadiance) <= 1e-6f) {
        return 0.0f;
    }

    LightBrdf brdf = lt_evaluate_surface_brdf_with_view(surface, smple.dir, viewPos - surface.rtPos);
    return ph_luminance(max(incidentRadiance * (brdf.demodulatedDiffuse * surface.albedo + brdf.specular), vec3(0.0f))) / smple.solidAnglePdf;
}

vec3 lt_shade_surface_light_sample(DirectSurface surface, LightSample smple) {
    return max(lt_surface_reflected_radiance(surface, smple), vec3(0.0f));
}

vec3 lt_shade_surface_light_sample_with_view(DirectSurface surface, LightSample smple, vec3 viewDir) {
    return max(lt_surface_reflected_radiance_with_view(surface, smple, viewDir), vec3(0.0f));
}

struct LtSplitRadiance {
    vec3 diffuse;       // Demodulated diffuse (albedo divided out)
    vec3 specular;      // Demodulated specular (F0 divided out)
};

// NRD-compatible split shading: returns diffuse-demodulated radiance and raw split specular radiance.
LtSplitRadiance lt_shade_surface_split(DirectSurface surface, LightSample smple) {
    LtSplitRadiance result = LtSplitRadiance(vec3(0.0f), vec3(0.0f));

    vec3 incidentRadiance = lt_light_sample_incident_radiance(surface, smple);
    if (ph_luminance(incidentRadiance) <= 1e-6f) {
        return result;
    }

    vec3 viewDir = rt_camera_position - surface.rtPos;
    LightBrdf brdf = lt_evaluate_surface_brdf_with_view(surface, smple.dir, viewDir);

    result.diffuse = max(incidentRadiance * brdf.demodulatedDiffuse, vec3(0.0f));
    result.specular = max(incidentRadiance * brdf.specular, vec3(0.0f));

    return result;
}

void light_sample_compute_weight(inout LightSample smple, DirectSurface surface) {
    smple.weight = lt_surface_target_pdf(surface, smple);
}

LightSample light_sample_new_at_position(Light light, vec3 lightPosition, DirectSurface surface) {
    vec3 origin = lt_surface_ray_origin(surface.rtPos, surface.geometryNormal);
    vec3 toLight = lightPosition - surface.rtPos;
    float lightDistanceSq = dot(toLight, toLight);
    if (lightDistanceSq <= 1e-6f) {
        return lt_null_sample();
    }

    LightSample result = LightSample(
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

LightSample light_sample_new_at(Light light, DirectSurface surface) {
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
    return lt_sample_light_position_from_uv(light, vec2(rand_next_float(), rand_next_float()), shadowRayOrigin);
}

float lt_light_sample_source_pdf() {
    return 1.0f;
}

bool rtxdi_is_analytic_light_sample(LightSample lightSample) {
    // All bridged Minecraft local lights map to RTXDI analytic point lights.
    return lightSample.index >= 0;
}

LightSample light_sample_random_at(Light light, DirectSurface surface) {
    vec3 origin = lt_surface_ray_origin(surface.rtPos, surface.geometryNormal);
    vec2 sampleUv = vec2(rand_next_float(), rand_next_float());
    vec3 selectedPosition = lt_sample_light_position_from_uv(light, sampleUv, origin);
    return light_sample_new_at_position(light, selectedPosition, surface);
}

LightSample light_sample_new_at(Light light, vec3 sample_pos, vec3 geometryNormal, vec3 shadingNormal) {
    DirectSurface surface = lt_make_surface(sample_pos + world_offset, geometryNormal, shadingNormal);
    return light_sample_new_at(light, surface);
}

LightSample light_sample_new(Light light, vec3 sample_pos) {
    return light_sample_new_at(light, sample_pos, block_normal, normal);
}

float light_sample_target_pdf_at(int lightIndex, vec3 sample_pos, vec3 geometryNormal, vec3 shadingNormal) {
    if (lightIndex < 0 || lightIndex >= ph_light_count) {
        return 0.0f;
    }

    LightSample smple = light_sample_new_at(load_light(lightIndex), sample_pos, geometryNormal, shadingNormal);
    return smple.weight;
}

float light_sample_target_pdf_at_surface(int lightIndex, DirectSurface surface) {
    if (lightIndex < 0 || lightIndex >= ph_light_count) {
        return 0.0f;
    }

    LightSample smple = light_sample_new_at(load_light(lightIndex), surface);
    return smple.weight;
}

float light_sample_target_pdf_at_surface(int lightIndex, vec3 lightWorldPosition, DirectSurface surface) {
    if (lightIndex < 0 || lightIndex >= ph_light_count) {
        return 0.0f;
    }

    LightSample smple = light_sample_new_at_position(load_light(lightIndex), lightWorldPosition - world_offset, surface);
    return smple.weight;
}

float light_sample_target_pdf_at_surface_with_view(int lightIndex, DirectSurface surface, vec3 viewPos) {
    if (lightIndex < 0 || lightIndex >= ph_light_count) {
        return 0.0f;
    }

    LightSample smple = light_sample_new_at(load_light(lightIndex), surface);
    return lt_surface_target_pdf_with_view(surface, smple, viewPos);
}

bool lt_ray_reached_target_cell(vec3 targetPosition) {
    ivec3 targetCell = ivec3(floor(targetPosition));
    ivec3 hitCell = ivec3(floor(ray.result_position));
    return ray.result_hit && all(equal(hitCell, targetCell));
}

// Mirrors RTXDI's setupVisibilityRay helper:
//   L        = samplePosition - surface.worldPos
//   TMin     = offset
//   TMax     = max(offset, length(L) - offset * 2)
//   Direction= normalize(L)
//   Origin   = surface.worldPos
// Our voxel tracer has no explicit TMin/TMax. For voxel cells, the closest equivalent to
// RTXDI's "skip hits very close to the shading surface" semantics is a geometric-normal
// origin bias, which moves the ray out of the source voxel without sliding it laterally
// through the surface at grazing angles. Once the origin is biased, the direction must be
// recomputed from that biased origin; otherwise the ray drifts off the intended target cell
// on grazing terrain samples and over-rejects conservative visibility.
bool lt_setup_visibility_ray(
    DirectSurface surface,
    vec3 targetPosition,
    float offset,
    out vec3 rayOrigin,
    out vec3 rayDirection,
    out float traceDistance
) {
    vec3 unbiasedToTarget = targetPosition - surface.rtPos;
    float lightDistance = length(unbiasedToTarget);
    if (lightDistance <= 1e-5f) {
        rayOrigin = surface.rtPos;
        rayDirection = vec3(0.0f);
        traceDistance = 0.0f;
        return false;
    }

    rayOrigin = surface.rtPos + surface.geometryNormal * offset;
    vec3 biasedToTarget = targetPosition - rayOrigin;
    float biasedDistance = length(biasedToTarget);
    if (biasedDistance <= 1e-5f) {
        rayDirection = vec3(0.0f);
        traceDistance = 0.0f;
        return false;
    }

    rayDirection = biasedToTarget / biasedDistance;
    traceDistance = max(offset, lightDistance - offset * 2.0f);
    return traceDistance > 0.0f;
}

// Match RTXDI's final-visibility contract: the expensive visibility query returns an RGB
// throughput term, not just a binary hit/miss. Our voxel tracer accumulates that through
// transparent voxels in result_tint_color.
vec3 lt_trace_visibility_transmittance() {
    return clamp(result_tint_color, vec3(0.0f), vec3(1.0f));
}

// Mirrors RTXDI's GetConservativeVisibility / RAB_GetConservativeVisibility path:
// trace a cheap visibility ray, treat translucent surfaces conservatively as visible,
// and return a boolean visible/invisible result for resampling.
bool lt_trace_conservative_visibility(inout LightSample smple, DirectSurface surface) {
    if (smple.index < 0) {
        return false;
    }

    vec3 targetPosition = smple.position;
    vec3 rayOrigin;
    vec3 rayDirection;
    float traceDistance;
    if (!lt_setup_visibility_ray(surface, targetPosition, 0.001f, rayOrigin, rayDirection, traceDistance)) {
        return false;
    }

    smple.sample_pos = rayOrigin;
    smple.position = targetPosition;
    ray.origin = smple.sample_pos;
    ray.direction = rayDirection;
    ray_target = ivec3(floor(smple.position));
    trace_ray(ray, true);
    return lt_ray_reached_target_cell(smple.position);
}

// Mirrors RTXDI's GetFinalVisibility path:
// trace the expensive final-visibility ray with a 0.01 offset and return RGB throughput.
vec3 lt_trace_final_visibility_with_offset(
    inout LightSample smple,
    DirectSurface surface,
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
    float traceDistance;
    if (!lt_setup_visibility_ray(surface, targetPosition, rayOffset, rayOrigin, rayDirection, traceDistance)) {
        smple = lt_null_sample();
        return vec3(0.0f);
    }

    smple.sample_pos = rayOrigin;
    smple.position = targetPosition;

    ray.origin = smple.sample_pos;
    ray.direction = rayDirection;
    ray_target = ivec3(floor(smple.position));
    trace_ray(ray, true);

    if (!lt_ray_reached_target_cell(smple.position)) {
        smple.color = vec3(0.0f);
        return vec3(0.0f);
    }

    vec3 surfaceToLight = targetPosition - surface.rtPos;
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

float light_sample_trace_hit_surface_with_offset(inout LightSample smple, bool jitter, DirectSurface surface, float rayOffset) {
    float hitDistance = 0.0f;
    lt_trace_final_visibility_with_offset(smple, surface, rayOffset, hitDistance);
    return hitDistance;
}

float light_sample_trace_hit_surface(inout LightSample smple, bool jitter, DirectSurface surface) {
    return lt_trace_conservative_visibility(smple, surface) ? 1.0f : 0.0f;
}

float light_sample_trace_hit_at(inout LightSample smple, bool jitter, vec3 geometryNormal, vec3 shadingNormal) {
    return light_sample_trace_hit_surface(
        smple,
        jitter,
        lt_make_surface(smple.sample_pos + world_offset, geometryNormal, shadingNormal)
    );
}

float light_sample_trace_hit(inout LightSample smple, bool jitter) {
    return light_sample_trace_hit_at(smple, jitter, block_normal, normal);
}

float light_sample_encode(LightSample smple) {
    return float(smple.index);
}

struct Reservoir {
    uint lightData;
    uint uvData;
    bool hasCompactLightData;
    uint compactLightBufferPtr;

    float weightSum;
    float targetPdf;
    float M;

    vec3 visibility;

    float age;
    vec2 spatialDistance;

    float canonicalWeight;
};

const uint RTXDI_PackedDIReservoir_VisibilityMask = 0x3ffffu;
const uint RTXDI_PackedDIReservoir_VisibilityChannelMax = 0x3fu;
const uint RTXDI_PackedDIReservoir_VisibilityChannelShift = 6u;
const uint RTXDI_PackedDIReservoir_MShift = 18u;
const uint RTXDI_PackedDIReservoir_MaxMUint = 0x3fffu;
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

int rtxdi_get_light_index(Reservoir reservoir) {
    return rtxdi_decode_light_index(reservoir.lightData);
}

void rtxdi_set_light_index(inout Reservoir reservoir, int lightIndex) {
    reservoir.lightData = rtxdi_make_light_data(lightIndex);
}

vec2 rtxdi_get_sample_uv(Reservoir reservoir) {
    return rtxdi_unpack_sample_uv(reservoir.uvData);
}

void rtxdi_set_sample_uv(inout Reservoir reservoir, vec2 sampleUv) {
    reservoir.uvData = rtxdi_pack_sample_uv(sampleUv);
}

Light lt_decode_reservoir_light(Reservoir reservoir, bool remap) {
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

    if (reservoir.hasCompactLightData) {
        return load_compact_light(reservoir.compactLightBufferPtr, index);
    }

    if (index < 0 || index >= ph_light_count) {
        return lt_invalid_light();
    }

    return load_light(index);
}

Light lt_decode_previous_reservoir_light(Reservoir reservoir) {
    int lightIndex = rtxdi_get_light_index(reservoir);
    if (lightIndex < 0) {
        return lt_invalid_light();
    }

    return load_previous_light(lightIndex);
}

LightSample light_sample_decode(Reservoir reservoir, DirectSurface surface, bool remap) {
    Light light = lt_decode_reservoir_light(reservoir, remap);
    if (light.index < 0) {
        return lt_null_sample();
    }

    vec3 lightPosition = lt_sample_light_position_from_uv(light, rtxdi_get_sample_uv(reservoir), lt_surface_ray_origin(surface.rtPos, surface.geometryNormal));
    return light_sample_new_at_position(light, lightPosition, surface);
}

LightSample light_sample_decode_previous(Reservoir reservoir, DirectSurface surface) {
    Light light = lt_decode_previous_reservoir_light(reservoir);
    if (light.index < 0) {
        return lt_null_sample();
    }

    vec3 lightPosition = lt_sample_light_position_from_uv(light, rtxdi_get_sample_uv(reservoir), lt_surface_ray_origin(surface.rtPos, surface.geometryNormal));
    return light_sample_new_at_position(light, lightPosition, surface);
}

LightSample light_sample_decode_at(float value, vec2 sampleUv, DirectSurface surface, bool remap) {
    Reservoir replayReservoir;
    replayReservoir.lightData = 0u;
    replayReservoir.uvData = 0u;
    replayReservoir.hasCompactLightData = false;
    replayReservoir.compactLightBufferPtr = 0u;
    replayReservoir.weightSum = 0.0;
    replayReservoir.targetPdf = 0.0;
    replayReservoir.M = 0.0;
    replayReservoir.visibility = vec3(0.0);
    replayReservoir.age = 0.0;
    replayReservoir.spatialDistance = vec2(0.0);
    replayReservoir.canonicalWeight = 0.0;
    rtxdi_set_light_index(replayReservoir, int(round(value)));
    rtxdi_set_sample_uv(replayReservoir, sampleUv);
    return light_sample_decode(replayReservoir, surface, remap);
}

LightSample light_sample_decode_at(float value, DirectSurface surface, bool remap) {
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

// Primary — matches RTXDI naming (Reservoir.hlsli: RTXDI_EmptyDIReservoir)
Reservoir RTXDI_EmptyDIReservoir() {
    Reservoir r;
    r.lightData = 0u;
    r.uvData = 0u;
    r.hasCompactLightData = false;
    r.compactLightBufferPtr = 0u;
    r.weightSum = 0.0;
    r.targetPdf = 0.0;
    r.M = 0.0;
    r.visibility = vec3(0.0);
    r.age = 0.0;
    r.spatialDistance = vec2(0.0);
    r.canonicalWeight = 0.0;
    return r;
}
// Backward-compat alias
Reservoir rtxdi_empty_reservoir() { return RTXDI_EmptyDIReservoir(); }

// Primary — matches RTXDI semantics: only checks light index validity (Reservoir.hlsli: lightData != 0)
bool RTXDI_IsValidDIReservoir(Reservoir reservoir) {
    return reservoir.lightData != 0u;
}

// Stricter photonics validity check — also requires M > 0 and weightSum > 0.
// Kept separate from RTXDI_IsValidDIReservoir for callers that need it.
bool rtxdi_is_valid_reservoir(Reservoir reservoir) {
    return reservoir.lightData != 0u && reservoir.M > 0.0f && reservoir.weightSum > 0.0f;
}

// Accessor wrappers — naming parity with RTXDI's Reservoir.hlsli accessor functions.
int RTXDI_GetDIReservoirLightIndex(Reservoir reservoir) {
    return rtxdi_get_light_index(reservoir);
}

vec2 RTXDI_GetDIReservoirSampleUV(Reservoir reservoir) {
    return rtxdi_get_sample_uv(reservoir);
}

float RTXDI_GetDIReservoirInvPdf(Reservoir reservoir) {
    return reservoir.weightSum;
}

// A surface is valid if it has a non-zero-length normal (sky/empty pixels have zero normals).
// Matches RAB_IsSurfaceValid semantics from RTXDI (TemporalResampling.hlsli line 94).
bool lt_is_valid_surface(DirectSurface surface) {
    return dot(surface.geometryNormal, surface.geometryNormal) > 1e-6;
}

void rtxdi_reset_visibility(inout Reservoir reservoir) {
    reservoir.visibility = vec3(0.0f);
    reservoir.age = 0.0f;
    reservoir.spatialDistance = vec2(0.0f);
}

void rtxdi_prepare_spatial_reuse(inout Reservoir reservoir, ivec2 spatialOffset) {
    // RTXDI SpatialResampling.hlsli line 87: neighborSample.spatialDistance += spatialOffset;
    // Unconditional — no visibility guard. Always track accumulated spatial distance.
    reservoir.spatialDistance += vec2(spatialOffset);
}

void rtxdi_prepare_temporal_reuse(inout Reservoir reservoir, ivec2 spatialOffset) {
    // RTXDI: unconditional update — no visibility guard, no age cap here
    reservoir.spatialDistance += vec2(spatialOffset);
    reservoir.age += 1.0f;
}

bool rtxdi_has_reusable_visibility(Reservoir reservoir) {
    // When uniforms are unbound (0.0), fall back to SDK defaults:
    //   finalVisibilityMaxAge      = 4   (ReSTIRDI.cpp line 114)
    //   finalVisibilityMaxDistance = 16  (ReSTIRDI.cpp line 115)
    float maxAge      = (ph_restir_visibility_max_age      > 0.0f) ? ph_restir_visibility_max_age      : lt_visibility_reuse_max_age;
    float maxDistance = (ph_restir_visibility_max_distance > 0.0f) ? ph_restir_visibility_max_distance : lt_visibility_reuse_max_distance;
    return reservoir.age > 0.0f
        && reservoir.age <= maxAge
        && length(reservoir.spatialDistance) < maxDistance;
}

// Returns the stored RGB visibility exactly as packed in the reservoir.
vec3 rtxdi_get_visibility(Reservoir reservoir) {
    return clamp(reservoir.visibility, vec3(0.0f), vec3(1.0f));
}

// Scalar visibility test — true when at least one channel exceeds 0 via luminance.
// Uses per-channel luminance-weighted sum matching RTXDI's packedVisibility bit test.
bool rtxdi_is_visible(Reservoir reservoir) {
    return ph_luminance(rtxdi_get_visibility(reservoir)) > 0.0f;
}

// Primary — matches RTXDI_StoreVisibilityInDIReservoir (Reservoir.hlsli).
// discardIfInvisible: when true and visibility is fully zero, kill the reservoir light data
// (equivalent to RTXDI discarding an occluded sample). M and targetPdf are always preserved.
void RTXDI_StoreVisibilityInDIReservoir(inout Reservoir reservoir, vec3 visibility, bool discardIfInvisible) {
    reservoir.visibility = visibility;
    reservoir.spatialDistance = vec2(0.0f);
    reservoir.age = 0.0f;
    if (discardIfInvisible && visibility.x == 0.0f && visibility.y == 0.0f && visibility.z == 0.0f) {
        // RTXDI Reservoir.hlsli lines 93-96: only clears lightData and weightSum.
        // sampleUv (uvData) is intentionally NOT cleared — RTXDI leaves it intact.
        // M and targetPdf are also preserved for correct downstream resampling.
        reservoir.lightData = 0u;
        reservoir.weightSum = 0.0f;
    }
}

// Backward-compat alias — preserves original bool-based call sites.
void rtxdi_store_visibility(inout Reservoir reservoir, bool visible) {
    RTXDI_StoreVisibilityInDIReservoir(reservoir, visible ? vec3(1.0f) : vec3(0.0f), true);
}

void rtxdi_copy_visibility(inout Reservoir reservoir, Reservoir sourceReservoir) {
    reservoir.visibility = sourceReservoir.visibility;
    reservoir.age = sourceReservoir.age;
    reservoir.spatialDistance = sourceReservoir.spatialDistance;
}

void rtxdi_inherit_visibility(
    inout Reservoir reservoir,
    Reservoir sourceReservoir,
    ivec2 currentUv,
    ivec2 sourceUv,
    bool temporalReuse
) {
    reservoir.visibility = sourceReservoir.visibility;
    reservoir.age = sourceReservoir.age;
    reservoir.spatialDistance = sourceReservoir.spatialDistance;

    reservoir.age = sourceReservoir.age + 1.0f;
    if (temporalReuse) {
        reservoir.spatialDistance = vec2(0.0f);
    } else {
        reservoir.spatialDistance = sourceReservoir.spatialDistance + vec2(sourceUv - currentUv);
    }
}

// Primary — matches RTXDI_StreamSample signature (Reservoir.hlsli).
// Takes explicit lightIndex, position (RT-space), random value, targetPdf, and invSourcePdf.
// Always increments M; does NOT reset visibility (caller manages visibility lifecycle).
bool RTXDI_StreamSample(inout Reservoir reservoir, int lightIndex, vec2 sampleUv, float random, float targetPdf, float invSourcePdf) {
    float risWeight = targetPdf * invSourcePdf;
    reservoir.M += 1.0f;
    reservoir.weightSum += risWeight;
    bool selectSample = (random * reservoir.weightSum < risWeight);
    if (selectSample) {
        rtxdi_set_light_index(reservoir, lightIndex);
        rtxdi_set_sample_uv(reservoir, sampleUv);
        reservoir.hasCompactLightData = false;
        reservoir.compactLightBufferPtr = 0u;
        reservoir.targetPdf = targetPdf;
    }
    return selectSample;
}

// Backward-compat alias — preserves original LightSample-based call sites.
bool rtxdi_stream_sample(inout Reservoir reservoir, LightSample smple, float weight, float samples) {
    reservoir.M += max(samples, 0.0f);

    if (smple.index < 0 || weight <= 0.0f || samples <= 0.0f) {
        return false;
    }

    reservoir.weightSum += weight;
    if (rand_next_float() * reservoir.weightSum < weight) {
        rtxdi_set_light_index(reservoir, smple.index);
        reservoir.targetPdf = smple.weight;
        rtxdi_set_sample_uv(reservoir, lt_encode_light_sample_uv(load_light(smple.index), smple.position));
        return true;
    }

    return false;
}

float rtxdi_target_pdf_at_surface(Reservoir reservoir, DirectSurface surface) {
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        return 0.0f;
    }

    LightSample smple = light_sample_decode(reservoir, surface, false);
    return lt_surface_target_pdf(surface, smple);
}

float rtxdi_target_pdf_at_surface_with_view(Reservoir reservoir, DirectSurface surface, vec3 viewPos) {
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        return 0.0f;
    }

    LightSample smple = light_sample_decode(reservoir, surface, false);
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

// Primary — matches RTXDI_InternalSimpleResample exactly (Reservoir.hlsli lines 192-225).
// No early-return guards: risWeight=0 cases fall through naturally (M still accumulates).
bool RTXDI_InternalSimpleResample(
    inout Reservoir reservoir,
    Reservoir candidateReservoir,
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
        reservoir.hasCompactLightData = candidateReservoir.hasCompactLightData;
        reservoir.compactLightBufferPtr = candidateReservoir.compactLightBufferPtr;
        reservoir.targetPdf = targetPdf;
        reservoir.visibility = candidateReservoir.visibility;
        reservoir.age = candidateReservoir.age;
        reservoir.spatialDistance = candidateReservoir.spatialDistance;
    }
    return selectSample;
}

// Matches RTXDI_CombineDIReservoirs (Reservoir.hlsli lines 230-244).
// Wraps RTXDI_InternalSimpleResample with canonical CombineDIReservoirs normalization.
bool RTXDI_CombineDIReservoirs(
    inout Reservoir reservoir,
    Reservoir newReservoir,
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
    inout Reservoir reservoir,
    Reservoir candidateReservoir,
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
        reservoir.hasCompactLightData = candidateReservoir.hasCompactLightData;
        reservoir.compactLightBufferPtr = candidateReservoir.compactLightBufferPtr;
        reservoir.targetPdf = targetPdf;
        reservoir.visibility = candidateReservoir.visibility;
        reservoir.age = candidateReservoir.age;
        reservoir.spatialDistance = candidateReservoir.spatialDistance;
    }

    return selectSample;
}

// Primary — matches RTXDI_StreamNeighborWithPairwiseMIS exactly (PairwiseStreaming.hlsli lines 35-72).
// Takes explicit random value (RTXDI passes RTXDI_GetNextRandom(rng) at the call site).
// Uses RTXDI_InternalSimpleResample (unguarded) matching the reference exactly.
bool RTXDI_StreamNeighborWithPairwiseMIS(
    inout Reservoir reservoir,
    float random,
    Reservoir neighborSample,
    DirectSurface neighborSurface,
    Reservoir centerSample,
    DirectSurface centerSurface,
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
    return RTXDI_InternalSimpleResample(
        reservoir,
        neighborSample,
        random,
        neighborWeightAtCanonical,
        neighborSample.weightSum * neighborMisWeight,
        effectiveM
    );
}

// Backward-compat alias — generates its own random, delegates to RTXDI_StreamNeighborWithPairwiseMIS.
// Old call sites that do not pass an explicit random continue to work unchanged.
bool rtxdi_stream_neighbor_with_pairwise_mis(
    inout Reservoir reservoir,
    Reservoir neighborReservoir,
    DirectSurface neighborSurface,
    Reservoir canonicalReservoir,
    DirectSurface canonicalSurface,
    float neighborsInStream
) {
    return RTXDI_StreamNeighborWithPairwiseMIS(
        reservoir,
        rand_next_float(),
        neighborReservoir,
        neighborSurface,
        canonicalReservoir,
        canonicalSurface,
        neighborsInStream
    );
}

// Primary — matches RTXDI_StreamCanonicalWithPairwiseStep exactly (PairwiseStreaming.hlsli lines 77-86).
// Takes explicit random and centerSurface (centerSurface unused in body but present for signature parity).
// Uses RTXDI_InternalSimpleResample (unguarded) matching the reference exactly.
bool RTXDI_StreamCanonicalWithPairwiseStep(
    inout Reservoir reservoir,
    float random,
    Reservoir centerSample,
    DirectSurface centerSurface
) {
    return RTXDI_InternalSimpleResample(
        reservoir,
        centerSample,
        random,
        centerSample.targetPdf,
        centerSample.weightSum * reservoir.canonicalWeight,
        centerSample.M
    );
}

// Backward-compat alias — generates its own random, delegates to RTXDI_StreamCanonicalWithPairwiseStep.
bool rtxdi_stream_canonical_with_pairwise_step(
    inout Reservoir reservoir,
    Reservoir canonicalReservoir
) {
    // centerSurface is unused in the body; pass empty surface for signature parity.
    return RTXDI_StreamCanonicalWithPairwiseStep(
        reservoir,
        rand_next_float(),
        canonicalReservoir,
        lt_empty_surface()
    );
}

// 3-parameter version matching RTXDI_FinalizeResampling exactly (Reservoir.hlsli).
// Uses reservoir.targetPdf as the denominator base — call this for temporal/bias-correction paths.
void RTXDI_FinalizeResampling(inout Reservoir reservoir, float normalizationNumerator, float normalizationDenominator) {
    float denominator = reservoir.targetPdf * normalizationDenominator;
    reservoir.weightSum = (denominator == 0.0f) ? 0.0f : (reservoir.weightSum * normalizationNumerator) / denominator;
}

// 4-parameter extended version kept for callers that supply an explicit selectedTargetPdf
// (e.g. reuse_resolve.fsh pairwise-MIS path).
// Matches RTXDI_FinalizeResampling exactly: the only guard is denominator == 0.0.
// No extra NaN/Inf clamps or targetPdf clamping — those diverge from RTXDI reference behavior.
void rtxdi_finalize_resampling_ex(inout Reservoir reservoir, float normalizationNumerator, float normalizationDenominator, float selectedTargetPdf) {
    float denominator = selectedTargetPdf * normalizationDenominator;
    reservoir.weightSum = (denominator == 0.0f) ? 0.0f : (reservoir.weightSum * normalizationNumerator) / denominator;
    reservoir.targetPdf = selectedTargetPdf;
}

// Backward-compatible alias so existing callers of rtxdi_finalize_resampling(..., selectedTargetPdf)
// continue to compile without modification.
void rtxdi_finalize_resampling(inout Reservoir reservoir, float normalizationNumerator, float normalizationDenominator, float selectedTargetPdf) {
    rtxdi_finalize_resampling_ex(reservoir, normalizationNumerator, normalizationDenominator, selectedTargetPdf);
}

void rtxdi_finalize_initial(inout Reservoir reservoir) {
    // Legacy helper used by old call sites; RTXDI_SampleLocalLights uses RTXDI_FinalizeResampling
    // with misData.numMisSamples (local + environment + BRDF) directly. Keep this for compat.
    rtxdi_finalize_resampling(reservoir, 1.0, float(max(PH_LIGHTTREE_INITIAL_SAMPLES, 1)), reservoir.targetPdf);
}

float light_sample_encode_index(int lightIndex) {
    return uintBitsToFloat(rtxdi_make_light_data(lightIndex));
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

vec4 rtxdi_pack_reservoir(Reservoir reservoir) {
    uint packedVisibility = rtxdi_pack_visibility(reservoir.visibility);
    uint packedM = min(uint(reservoir.M), RTXDI_PackedDIReservoir_MaxMUint);
    return vec4(
        uintBitsToFloat(reservoir.lightData),
        reservoir.weightSum,
        reservoir.targetPdf,
        uintBitsToFloat(packedVisibility | (packedM << RTXDI_PackedDIReservoir_MShift))
    );
}

vec4 rtxdi_pack_reservoir_sample(Reservoir reservoir) {
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        return vec4(0.0f);
    }

    return vec4(uintBitsToFloat(reservoir.uvData), 0.0f, 0.0f, 0.0f);
}

const int RTXDI_PackedDIReservoir_DistanceChannelBits = 8;
const int RTXDI_PackedDIReservoir_DistanceXShift = 0;
const int RTXDI_PackedDIReservoir_DistanceYShift = 8;
const int RTXDI_PackedDIReservoir_AgeShift = 16;
const uint RTXDI_PackedDIReservoir_MaxAge = 0xffu;
const uint RTXDI_PackedDIReservoir_DistanceMask = (1u << RTXDI_PackedDIReservoir_DistanceChannelBits) - 1u;
const int RTXDI_PackedDIReservoir_MaxDistance = int((1u << (RTXDI_PackedDIReservoir_DistanceChannelBits - 1)) - 1u);

uint rtxdi_pack_age_distance(float age, vec2 sd) {
    ivec2 clampedSpatialDistance = clamp(
        ivec2(sd),
        ivec2(-RTXDI_PackedDIReservoir_MaxDistance),
        ivec2(RTXDI_PackedDIReservoir_MaxDistance)
    );
    uint clampedAge = uint(clamp(int(age), 0, int(RTXDI_PackedDIReservoir_MaxAge)));

    return ((uint(clampedSpatialDistance.x) & RTXDI_PackedDIReservoir_DistanceMask) << RTXDI_PackedDIReservoir_DistanceXShift)
        | ((uint(clampedSpatialDistance.y) & RTXDI_PackedDIReservoir_DistanceMask) << RTXDI_PackedDIReservoir_DistanceYShift)
        | (clampedAge << RTXDI_PackedDIReservoir_AgeShift);
}

void rtxdi_unpack_age_distance(uint packedValue, out float age, out vec2 sd) {
    int sxShift = 32 - RTXDI_PackedDIReservoir_DistanceXShift - RTXDI_PackedDIReservoir_DistanceChannelBits;
    int syShift = 32 - RTXDI_PackedDIReservoir_DistanceYShift - RTXDI_PackedDIReservoir_DistanceChannelBits;
    int signExtendShift = 32 - RTXDI_PackedDIReservoir_DistanceChannelBits;
    int isx = int(packedValue << sxShift) >> signExtendShift;
    int isy = int(packedValue << syShift) >> signExtendShift;
    age = float((packedValue >> RTXDI_PackedDIReservoir_AgeShift) & RTXDI_PackedDIReservoir_MaxAge);
    sd = vec2(float(isx), float(isy));
}

vec4 rtxdi_pack_reservoir_meta(Reservoir reservoir) {
    return vec4(0.0f, 0.0f, 0.0f, uintBitsToFloat(rtxdi_pack_age_distance(reservoir.age, reservoir.spatialDistance)));
}

void rtxdi_unpack_reservoir_at_surface(inout Reservoir reservoir, vec4 color, vec4 sampleData, vec4 meta, DirectSurface surface, bool remap) {
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
    reservoir.hasCompactLightData = false;
    reservoir.compactLightBufferPtr = 0u;
    reservoir.weightSum = color.y;
    reservoir.targetPdf = color.z;
    uint packedVisibilityAndM = floatBitsToUint(color.w);
    reservoir.M = float((packedVisibilityAndM >> RTXDI_PackedDIReservoir_MShift) & RTXDI_PackedDIReservoir_MaxMUint);

    // Unpack age+spatialDistance from meta.w, matching RTXDI distanceAge packing.
    // packedVisibility lives in color.w with M, matching RTXDI_PackedDIReservoir::mVisibility.
    uint packedDistanceAge = floatBitsToUint(meta.w);
    reservoir.visibility = rtxdi_unpack_visibility(packedVisibilityAndM & RTXDI_PackedDIReservoir_VisibilityMask);
    rtxdi_unpack_age_distance(packedDistanceAge, reservoir.age, reservoir.spatialDistance);
    reservoir.canonicalWeight = 0.0f;

    // RTXDI_UnpackDIReservoir sanitization (ReservoirStorage.hlsli lines 88-91):
    //   if (isinf(res.weightSum) || isnan(res.weightSum)) { res = RTXDI_EmptyDIReservoir(); }
    // RTXDI only checks weightSum, not targetPdf. Match exactly.
    if (isinf(reservoir.weightSum) || isnan(reservoir.weightSum)) {
        reservoir = RTXDI_EmptyDIReservoir();
    }
}

void rtxdi_unpack_reservoir_at_surface(inout Reservoir reservoir, vec4 color, vec4 meta, DirectSurface surface, bool remap) {
    rtxdi_unpack_reservoir_at_surface(reservoir, color, vec4(0.0f), meta, surface, remap);
}

void rtxdi_unpack_reservoir_at_surface(inout Reservoir reservoir, vec4 color, DirectSurface surface, bool remap) {
    rtxdi_unpack_reservoir_at_surface(reservoir, color, vec4(0.0f), vec4(-1.0f, 0.0f, 0.0f, 0.0f), surface, remap);
}

void rtxdi_unpack_reservoir(inout Reservoir reservoir, vec4 color, vec4 meta, vec3 sample_pos, bool remap) {
    DirectSurface surface = DirectSurface(
        sample_pos + world_offset,
        sample_pos,
        block_normal,
        normal,
        clamp(albedo, vec3(0.0f), vec3(1.0f)),
        lt_extract_material_at_uv((vec2(tex_coord) + vec2(0.5f)) / vec2(viewWidth, viewHeight))
    );
    rtxdi_unpack_reservoir_at_surface(reservoir, color, meta, surface, remap);
}

void rtxdi_unpack_reservoir(inout Reservoir reservoir, vec4 color, vec3 sample_pos, bool remap) {
    rtxdi_unpack_reservoir(reservoir, color, vec4(-1.0f, 0.0f, 0.0f, 0.0f), sample_pos, remap);
}

// RTXDI: RTXDI_InitialSamplingMisData (InitialSampling.hlsli:33-39)
// Tracks per-technique sample counts and their MIS weights for blended source PDF computation.
// Defined here so RTXDI_LightBrdfMisWeight and rtxdi_stream_local_light can reference it.
struct RTXDI_InitialSamplingMisData {
    int numMisSamples;              // total candidates across all techniques
    float localLightMisWeight;      // fraction of candidates from local-light sampling
    float environmentMapMisWeight;  // fraction of candidates from environment sampling
    float brdfMisWeight;            // fraction of candidates from BRDF sampling
};

// RTXDI: RTXDI_ComputeInitialSamplingMisData (InitialSampling.hlsli:41-54)
// RTXDI does NOT guard numMisSamples against zero here — the early-exit in RTXDI_SampleLocalLights
// ensures numMisSamples > 0 before this is used in division.
// numMisSamples includes local + environment + BRDF sample counts (InitialSampling.hlsli line 45).
// Environment samples are included even when the environment stub returns M=0 so MIS weights
// remain consistent with the SDK reference.
RTXDI_InitialSamplingMisData RTXDI_ComputeInitialSamplingMisData(int numLocalLightSamples, int numEnvironmentSamples, int numBrdfSamples) {
    RTXDI_InitialSamplingMisData result;
    result.numMisSamples = numLocalLightSamples + numEnvironmentSamples + numBrdfSamples;
    result.localLightMisWeight = float(numLocalLightSamples) / float(result.numMisSamples);
    result.environmentMapMisWeight = float(numEnvironmentSamples) / float(result.numMisSamples);
    result.brdfMisWeight = float(numBrdfSamples) / float(result.numMisSamples);
    return result;
}

// Backward-compat overload — passes numEnvironmentSamples=0 for existing two-arg call sites.
RTXDI_InitialSamplingMisData RTXDI_ComputeInitialSamplingMisData(int numLocalLightSamples, int numBrdfSamples) {
    return RTXDI_ComputeInitialSamplingMisData(numLocalLightSamples, 0, numBrdfSamples);
}

// RTXDI: RTXDI_BrdfMaxDistanceFromPdf (InitialSampling.hlsli:57-61)
// Heuristic max ray length from BRDF PDF, controlling the MIS cutoff region.
// brdfCutoff == 0 disables shortening (returns +infinity sentinel).
float rtxdi_brdf_max_distance_from_pdf(float brdfCutoff, float pdf) {
    const float kRayTMax = 3.402823466e+38;
    return brdfCutoff > 0.0 ? sqrt((1.0 / brdfCutoff - 1.0) * pdf) : kRayTMax;
}

// GGX VNDF PDF for a sampled light direction L given view direction V.
// Matches the sampling distribution of ph_sample_ggx_vndf (ph_core.glsl).
// Derivation: pdf_H = D(H) * G1(V) * dot(V,H) / max(dot(V,N), eps)
//             pdf_L = pdf_H / (4 * dot(V,H)) = D(H) * G1(V) / (4 * max(dot(V,N), eps))
float lt_evaluate_ggx_vndf_pdf(DirectSurface surface, vec3 lightDir, vec3 viewDir) {
    vec3 N = surface.shadingNormal;
    float nDotL = dot(N, lightDir);
    float nDotV = dot(N, viewDir);
    if (nDotL <= 0.0 || nDotV <= 0.0) {
        return 0.0;
    }

    vec3 H = normalize(viewDir + lightDir);
    float nDotH = max(dot(N, H), 0.0);

    float roughness = clamp(surface.material.x, lt_min_roughness, 1.0);
    float D = lt_distribution_ggx(nDotH, roughness);

    // G1(V) -- Smith-GGX masking, matching lt_geometry_schlick_ggx
    float a = max(roughness * roughness, 0.02);
    float k = a * 0.5;
    float G1 = nDotV / max(nDotV * (1.0 - k) + k, 1e-6);

    // VNDF PDF wrt solid angle: D * G1 / (4 * nDotV)
    return D * G1 / max(4.0 * nDotV, 1e-6);
}

vec3 lt_sample_cosine_hemisphere_rtxdi(vec3 normal, vec2 rnd) {
    float phi = rnd.x * (2.0f * lt_pi);
    float r = sqrt(rnd.y);
    float x = r * cos(phi);
    float y = r * sin(phi);
    float z = sqrt(max(0.0f, 1.0f - rnd.y));

    vec3 tangent = ph_build_tangent(normal);
    vec3 bitangent = cross(normal, tangent);
    return normalize(tangent * x + bitangent * y + normal * z);
}

vec3 lt_sample_ggx_vndf_rtxdi(vec3 viewDir, vec3 normal, float roughness, vec2 rnd) {
    float a = max(roughness * roughness, 0.02f);

    vec3 tangent = ph_build_tangent(normal);
    vec3 bitangent = cross(normal, tangent);
    mat3 basis = mat3(tangent, bitangent, normal);

    vec3 Ve = transpose(basis) * normalize(viewDir);
    vec3 Vh = normalize(vec3(a * Ve.x, a * Ve.y, max(Ve.z, 1e-4f)));

    float lensq = Vh.x * Vh.x + Vh.y * Vh.y;
    vec3 T1 = lensq > 1e-7f ? vec3(-Vh.y, Vh.x, 0.0f) * inversesqrt(lensq) : vec3(1.0f, 0.0f, 0.0f);
    vec3 T2 = cross(Vh, T1);

    float r = sqrt(rnd.x);
    float phi = 2.0f * lt_pi * rnd.y;
    float t1 = r * cos(phi);
    float t2 = r * sin(phi);
    float s = 0.5f * (1.0f + Vh.z);
    t2 = mix(sqrt(max(0.0f, 1.0f - t1 * t1)), t2, s);

    vec3 Nh = t1 * T1 + t2 * T2 + sqrt(max(0.0f, 1.0f - t1 * t1 - t2 * t2)) * Vh;
    vec3 Ne = normalize(vec3(a * Nh.x, a * Nh.y, max(0.0f, Nh.z)));
    vec3 H = normalize(basis * Ne);
    return normalize(reflect(-viewDir, H));
}

bool rtxdi_surface_importance_sample_brdf(DirectSurface surface, inout RTXDI_RandomSamplerState rng, out vec3 dir) {
    vec3 rand = vec3(RTXDI_GetNextRandom(rng), RTXDI_GetNextRandom(rng), RTXDI_GetNextRandom(rng));
    float diffuseProbability = lt_surface_diffuse_probability(surface);
    if (rand.x < diffuseProbability) {
        dir = lt_sample_cosine_hemisphere_rtxdi(surface.shadingNormal, rand.yz);
    } else {
        dir = lt_sample_ggx_vndf_rtxdi(
            normalize(rt_camera_position - surface.rtPos),
            surface.shadingNormal,
            max(surface.material.x, lt_min_roughness),
            rand.yz
        );
    }

    return dot(surface.shadingNormal, dir) > 0.0f;
}

// RTXDI: RAB_SurfaceEvaluateBrdfPdf -- evaluates the PDF of the diffuse/specular
// mixture used by RAB_SurfaceImportanceSampleBrdf.
float rtxdi_surface_evaluate_brdf_pdf(DirectSurface surface, vec3 lightDir) {
    float nDotL = max(dot(surface.shadingNormal, lightDir), 0.0);
    if (nDotL <= 0.0) {
        return 0.0;
    }

    vec3 viewDir = normalize(rt_camera_position - surface.rtPos);
    float pdfCosine = nDotL / lt_pi;
    float pdfGgx = lt_evaluate_ggx_vndf_pdf(surface, lightDir, viewDir);
    float diffuseProbability = lt_surface_diffuse_probability_with_view(surface, viewDir);
    return mix(pdfGgx, pdfCosine, diffuseProbability);
}

// RTXDI: RTXDI_LightBrdfMisWeight (InitialSampling.hlsli:66-96)
// Computes the blended source PDF that mixes the light-selection PDF with the BRDF PDF
// using a balance-heuristic MIS weight.
float RTXDI_LightBrdfMisWeight(
    DirectSurface surface,
    LightSample lightSample,
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
    float brdfPdf = rtxdi_surface_evaluate_brdf_pdf(surface, lightSample.dir);
    float maxDistance = rtxdi_brdf_max_distance_from_pdf(brdfCutoff, brdfPdf);
    float lightDistance = length(lightSample.position - surface.rtPos);
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
    inout Reservoir reservoir,
    DirectSurface surface,
    Light light,
    float sourcePdf,
    RTXDI_InitialSamplingMisData misData,
    float brdfCutoff
) {
    if (light.index < 0 || light.index >= ph_light_count || sourcePdf <= 0.0) {
        return;
    }

    vec2 sampleUv = vec2(rand_next_float(), rand_next_float());
    vec3 sampledPosition = lt_sample_light_position_from_uv(light, sampleUv, lt_surface_ray_origin(surface.rtPos, surface.geometryNormal));
    LightSample smple = light_sample_new_at_position(light, sampledPosition, surface);

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
    bool selected = RTXDI_StreamSample(reservoir, smple.index, sampleUv, rand_next_float(), smple.weight, invSourcePdf);
    if (selected) {
        reservoir.hasCompactLightData = false;
        reservoir.compactLightBufferPtr = 0u;
    }
}

void rtxdi_stream_local_light(inout Reservoir reservoir, DirectSurface surface, int lightIndex, float sourcePdf, RTXDI_InitialSamplingMisData misData, float brdfCutoff) {
    if (lightIndex < 0 || lightIndex >= ph_light_count || sourcePdf <= 0.0) {
        return;
    }
    rtxdi_stream_local_light(reservoir, surface, load_light(lightIndex), sourcePdf, misData, brdfCutoff);
}

void rtxdi_stream_local_light(inout Reservoir reservoir, DirectSurface surface, int lightIndex, float sourcePdf, float localLightMisWeight) {
    RTXDI_InitialSamplingMisData misData;
    misData.numMisSamples = 1;
    misData.localLightMisWeight = localLightMisWeight;
    misData.environmentMapMisWeight = 0.0;
    misData.brdfMisWeight = 0.0;
    rtxdi_stream_local_light(reservoir, surface, lightIndex, sourcePdf, misData, 0.0);
}

// Backward-compat overload — passes localLightMisWeight=1.0 (no MIS blending).
void rtxdi_stream_local_light(inout Reservoir reservoir, DirectSurface surface, int lightIndex, float sourcePdf) {
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

// Sampling mode constants -- matches RTXDI's ReSTIRDI_LocalLightSamplingMode enum (RtxdiParameters.h lines 44-48).
const int RTXDI_LOCAL_LIGHT_SAMPLING_UNIFORM   = 0;  // Uniform random selection over all lights
const int RTXDI_LOCAL_LIGHT_SAMPLING_POWER_RIS = 1;  // Power-CDF importance sampling (stratified RIS tile)
const int RTXDI_LOCAL_LIGHT_SAMPLING_REGIR_RIS = 2;  // ReGIR cell-based RIS (with Power_RIS fallback outside grid)

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
    inout Reservoir reservoir,
    DirectSurface surface,
    Light light,
    float sourcePdf,
    RTXDI_InitialSamplingMisData misData,
    float brdfCutoff,
    out LightSample o_selectedSample
) {
    o_selectedSample = lt_null_sample();

    if (light.index < 0 || light.index >= ph_light_count || sourcePdf <= 0.0) {
        return false;
    }

    vec2 sampleUv = vec2(RTXDI_GetNextRandom(rng), RTXDI_GetNextRandom(rng));
    vec3 sampledPosition = lt_sample_light_position_from_uv(light, sampleUv, lt_surface_ray_origin(surface.rtPos, surface.geometryNormal));
    LightSample smple = light_sample_new_at_position(light, sampledPosition, surface);

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
    bool selected = RTXDI_StreamSample(reservoir, smple.index, sampleUv, RTXDI_GetNextRandom(rng), smple.weight, invSourcePdf);
    if (selected) {
        reservoir.hasCompactLightData = false;
        reservoir.compactLightBufferPtr = 0u;
        o_selectedSample = smple;
    }
    return selected;
}

bool rtxdi_stream_local_light_rng(
    inout RTXDI_RandomSamplerState rng,
    inout Reservoir reservoir,
    DirectSurface surface,
    int lightIndex,
    float sourcePdf,
    RTXDI_InitialSamplingMisData misData,
    float brdfCutoff,
    out LightSample o_selectedSample
) {
    if (lightIndex < 0 || lightIndex >= ph_light_count || sourcePdf <= 0.0) {
        o_selectedSample = lt_null_sample();
        return false;
    }

    return rtxdi_stream_local_light_rng(rng, reservoir, surface, load_light(lightIndex), sourcePdf, misData, brdfCutoff, o_selectedSample);
}

void rtxdi_stream_local_light_rng(
    inout RTXDI_RandomSamplerState rng,
    inout Reservoir reservoir,
    DirectSurface surface,
    Light light,
    float sourcePdf,
    RTXDI_InitialSamplingMisData misData,
    float brdfCutoff
) {
    LightSample ignoredSelectedSample;
    rtxdi_stream_local_light_rng(rng, reservoir, surface, light, sourcePdf, misData, brdfCutoff, ignoredSelectedSample);
}

void rtxdi_stream_local_light_rng(
    inout RTXDI_RandomSamplerState rng,
    inout Reservoir reservoir,
    DirectSurface surface,
    int lightIndex,
    float sourcePdf,
    RTXDI_InitialSamplingMisData misData,
    float brdfCutoff
) {
    LightSample ignoredSelectedSample;
    rtxdi_stream_local_light_rng(rng, reservoir, surface, lightIndex, sourcePdf, misData, brdfCutoff, ignoredSelectedSample);
}

Reservoir RTXDI_SampleLocalLights(inout RTXDI_RandomSamplerState rng, inout RTXDI_RandomSamplerState coherentRng, DirectSurface surface, out LightSample o_selectedSample) {
    o_selectedSample = lt_null_sample();

    // RTXDI: early-out when no lights (InitialSampling.hlsli:319)
    if (ph_light_count <= 0) {
        return RTXDI_EmptyDIReservoir();
    }

    Reservoir state = RTXDI_EmptyDIReservoir();

    // Resolve local light sampling mode from runtime uniform.
    // SDK default (ReSTIRDI.cpp line 45): Uniform (0).
    // Sentinel: -1.0 or 0.0 (unbound) → SDK default (Uniform); round positive values to mode int.
    int localLightSamplingMode;
    if (ph_restir_local_light_sampling_mode <= 0.0) {
        localLightSamplingMode = RTXDI_LOCAL_LIGHT_SAMPLING_UNIFORM;
    } else {
        localLightSamplingMode = int(round(ph_restir_local_light_sampling_mode));
    }

    // RTXDI: RTXDI_InitializeLocalLightSelectionContext for ReGIR_RIS mode only.
    // Reference: InitialSampling.hlsli:262, LocalLightSelection.hlsli:46-62
    // coherent_rng_state matches RTXDI_CalculateReGIRCellIndex(coherentRng, ...).
    int regirFlatCellIndex = -1;
    bool useRegir = false;
    if (localLightSamplingMode == RTXDI_LOCAL_LIGHT_SAMPLING_REGIR_RIS) {
        useRegir = regir_resolve_cell(surface.worldPos, coherentRng, regirFlatCellIndex);
    }

    // Runtime-overridable sample count. ph_restir_initial_num_local_samples == 0.0 means unbound:
    // fall back to the compile-time PH_LIGHTTREE_INITIAL_SAMPLES constant (RTXDI default = 8).
    int numLocalSamples = (ph_restir_initial_num_local_samples > 0.0)
        ? max(int(ph_restir_initial_num_local_samples), 1)
        : max(PH_LIGHTTREE_INITIAL_SAMPLES, 1);

    if (ph_light_count <= 0) {
        return RTXDI_EmptyDIReservoir();
    }

    // RTXDI: early exit when numLocalLightSamples == 0 (InitialSampling.hlsli lines 322-323).
    if (numLocalSamples == 0) {
        return RTXDI_EmptyDIReservoir();
    }

    // RTXDI: RTXDI_ComputeInitialSamplingMisData (InitialSampling.hlsli:41-54)
    // Fix 1: numBrdfSamples now defaults to 1 (SDK default), matching RTXDI behavior.
    //   - ph_restir_initial_num_brdf_samples > 0.0 → use runtime value
    //   - ph_restir_initial_num_brdf_samples == -1.0 → explicitly disable (0)
    //   - ph_restir_initial_num_brdf_samples == 0.0 (unbound) → SDK default = 1
    // numEnvironmentSamples: SDK default 1 (ReSTIRDI.cpp line 41).
    // 0.0 (unbound) falls back to 1; negative values explicitly disable the technique
    // when the environment-light path is absent in this bridge.
    int numEnvironmentSamples = (ph_restir_initial_num_environment_samples > 0.0)
        ? int(ph_restir_initial_num_environment_samples)
        : (ph_restir_initial_num_environment_samples < -0.5 ? 0 : 1);
    int numBrdfSamples = (ph_restir_initial_num_brdf_samples > 0.0)
        ? int(ph_restir_initial_num_brdf_samples)
        : (ph_restir_initial_num_brdf_samples < -0.5 ? 0 : 1);
    RTXDI_InitialSamplingMisData misData = RTXDI_ComputeInitialSamplingMisData(numLocalSamples, numEnvironmentSamples, numBrdfSamples);

    float brdfCutoff = (ph_restir_initial_brdf_cutoff > 0.0) ? ph_restir_initial_brdf_cutoff : 0.0001f;

    // For Power_RIS and ReGIR_RIS (outside grid) modes: select ONE RIS tile using coherentRng before the loop.
    // Matches RTXDI RTXDI_InitializeLocalLightSelectionContextRIS / RTXDI_RandomlySelectRISTile:
    //   tileIndex = uint(coherentRnd * tileCount);  risTileOffset = tileIndex * tileSize;
    // Tile is selected once so all iterations in a pixel draw from the same tile,
    // giving the same spatial coherence the ReGIR cell provides for inside-grid pixels.
    bool usePowerRisTiles = (localLightSamplingMode == RTXDI_LOCAL_LIGHT_SAMPLING_POWER_RIS)
        || (localLightSamplingMode == RTXDI_LOCAL_LIGHT_SAMPLING_REGIR_RIS && !useRegir);
    bool hasFallbackTiles = usePowerRisTiles && ph_ris_tile_count > 0 && ph_ris_tile_size > 0;
    uint fallbackTileOffset = 0u;
    if (hasFallbackTiles) {
        float coherentRnd = RTXDI_GetNextRandom(coherentRng);
        uint fallbackTileIndex = min(uint(coherentRnd * float(ph_ris_tile_count)), uint(ph_ris_tile_count) - 1u);
        fallbackTileOffset = fallbackTileIndex * uint(ph_ris_tile_size);
    }

    for (int i = 0; i < numLocalSamples; i++) {
        int lightIndex = -1;
        float sourcePdf = 0.0;

        if (localLightSamplingMode == RTXDI_LOCAL_LIGHT_SAMPLING_REGIR_RIS && useRegir) {
            // ReGIR_RIS, inside grid: draw from the ReGIR cell's RIS slots.
            // RTXDI: RTXDI_SelectNextLocalLight with ReGIR RIS context.
            // Draws from [0, lightsPerCell) -- invalid entries (invSourcePdf=0)
            // produce zero RIS weight via rtxdi_stream_local_light and don't contribute.
            // RTXDI_STRATIFY_LOCAL_SAMPLING (InitialSampling.hlsli:280): stratify the
            // per-iteration draw so samples are spread evenly across the cell's slots.
            float regirRnd = (RTXDI_GetNextRandom(rng) + float(i)) / float(numLocalSamples);
            bool regirHasCompact = false;
            uint regirRisBufferPtr = 0u;
            regir_pick_light(regirFlatCellIndex, regirRnd, lightIndex, sourcePdf, regirHasCompact, regirRisBufferPtr);
            if (regirHasCompact && lightIndex >= 0 && sourcePdf > 0.0f) {
                Light compactLight = load_compact_light(regirRisBufferPtr, lightIndex);
                LightSample selectedSample;
                bool selected = rtxdi_stream_local_light_rng(rng, state, surface, compactLight, sourcePdf, misData, brdfCutoff, selectedSample);
                if (selected) {
                    state.hasCompactLightData = true;
                    state.compactLightBufferPtr = regirRisBufferPtr;
                    o_selectedSample = selectedSample;
                }
                continue;
            }
        } else if (hasFallbackTiles) {
            // Power_RIS or ReGIR_RIS (outside grid): draw from the pre-selected RIS tile.
            // Stratified draw spreads iterations across the tile (RTXDI_STRATIFY_LOCAL_SAMPLING).
            // Matches RTXDI_RandomlySelectLightDataFromRISTile in InitialSampling.hlsli.
            float tileRnd = (RTXDI_GetNextRandom(rng) + float(i)) / float(numLocalSamples);
            uint risSample = min(uint(floor(tileRnd * float(ph_ris_tile_size))), uint(ph_ris_tile_size) - 1u);
            uint risBufferPtr = uint(ph_ris_tile_buffer_offset) + fallbackTileOffset + risSample;
            uvec2 tileData = ph_ris_data[risBufferPtr];
            bool hasCompactData = (tileData.x & RTXDI_LIGHT_COMPACT_BIT) != 0u;
            lightIndex = int(tileData.x & RTXDI_LIGHT_INDEX_MASK);
            float invSourcePdf = uintBitsToFloat(tileData.y);
            if (invSourcePdf <= 0.0 || lightIndex < 0 || lightIndex >= ph_light_count) {
                lightIndex = -1;
                sourcePdf = 0.0;
            } else {
                sourcePdf = 1.0 / invSourcePdf;
                if (hasCompactData) {
                    Light compactLight = load_compact_light(risBufferPtr, lightIndex);
                    LightSample selectedSample;
                    bool selected = rtxdi_stream_local_light_rng(rng, state, surface, compactLight, sourcePdf, misData, brdfCutoff, selectedSample);
                    if (selected) {
                        state.hasCompactLightData = true;
                        state.compactLightBufferPtr = risBufferPtr;
                        o_selectedSample = selectedSample;
                    }
                    continue;
                }
            }
        } else {
            // Uniform with stratification (RTXDI_STRATIFY_LOCAL_SAMPLING)
            float uniformRnd = (RTXDI_GetNextRandom(rng) + float(i)) / float(numLocalSamples);
            lightIndex = clamp(int(uniformRnd * float(ph_light_count)), 0, ph_light_count - 1);
            sourcePdf = 1.0 / float(max(ph_light_count, 1));
        }

        // Fix 1: RTXDI_StreamLocalLightAtUVIntoReservoir — pass full misData + brdfCutoff
        // so that RTXDI_LightBrdfMisWeight blends the BRDF PDF into the source PDF.
        // Invalid entries (lightIndex<0, sourcePdf=0) get zero risWeight -> no contribution.
        LightSample selectedSample;
        if (rtxdi_stream_local_light_rng(rng, state, surface, lightIndex, sourcePdf, misData, brdfCutoff, selectedSample)) {
            o_selectedSample = selectedSample;
        }
    }

    // RTXDI: RTXDI_FinalizeResampling(state, 1.0, misData.numMisSamples) (InitialSampling.hlsli:291).
    // 3-parameter form — no max() guard; zero case is handled by the early exit above.
    RTXDI_FinalizeResampling(state, 1.0, float(misData.numMisSamples));
    // RTXDI sets M=1 after initial RIS (InitialSampling.hlsli:292).
    state.M = 1.0;
    return state;
}

Reservoir RTXDI_SampleLocalLights(inout RTXDI_RandomSamplerState rng, inout RTXDI_RandomSamplerState coherentRng, DirectSurface surface) {
    LightSample ignoredSelectedSample;
    return RTXDI_SampleLocalLights(rng, coherentRng, surface, ignoredSelectedSample);
}

// Backward-compat: original in-place API delegating to RTXDI_SampleLocalLights.
void rtxdi_sample_local_lights(inout Reservoir reservoir, DirectSurface surface) {
    uvec2 pixelPosition = uvec2(lt_current_pixel_pos());
    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(pixelPosition, uint(frameCounter), RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED);
    RTXDI_RandomSamplerState coherentRng = RTXDI_InitRandomSampler(pixelPosition / RTXDI_TILE_SIZE_IN_PIXELS, uint(frameCounter), RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED);
    reservoir = RTXDI_SampleLocalLights(rng, coherentRng, surface);
}

// RTXDI_SampleInfiniteLights (InitialSampling.hlsli lines 368-400)
// Stub: Minecraft sun/moon handled by base shader pack.
// Returns empty reservoir with M=0 so it contributes nothing to the merger.
Reservoir RTXDI_SampleInfiniteLights(DirectSurface surface, int numSamples) {
    Reservoir state = RTXDI_EmptyDIReservoir();
    // TODO: When integrating sun/moon into ReSTIR pipeline:
    // - Sample directional light with random UV on virtual disk
    // - Evaluate target PDF at surface
    // - Stream into reservoir
    // For now, no infinite lights in the ReSTIR pipeline.
    // state.M is 0, so RTXDI_CombineDIReservoirs will skip this.
    return state;
}

// RTXDI_SampleEnvironmentMap (InitialSampling.hlsli lines 458-493)
// Stub: Environment map sampling not yet integrated.
// Returns empty reservoir with M=0.
Reservoir RTXDI_SampleEnvironmentMap(DirectSurface surface, int numSamples) {
    Reservoir state = RTXDI_EmptyDIReservoir();
    // TODO: When integrating sky radiance:
    // - Sample environment cubemap with importance-presampled UV
    // - Evaluate target PDF at surface
    // - Apply MIS weighting against BRDF samples
    return state;
}

// RTXDI_SampleBrdf (InitialSampling.hlsli lines 501-589)
// BRDF importance sampling: traces a ray in a BRDF-sampled direction and streams any
// emissive block hit into the reservoir.  Matching the reference structure:
//   for each sample:
//     1. Importance-sample a BRDF direction (cosine-weighted + GGX via ph_sample_brdf_direction).
//     2. Evaluate the BRDF PDF for that direction.
//     3. Trace a ray; check lightEmittance to detect emissive-block hits.
//     4. If an emissive block was hit, locate the nearest light in the array.
//     5. Evaluate targetPdf and MIS-blended source PDF, then stream into reservoir.
//   FinalizeResampling with misData.numMisSamples matching the reference.
//
// numSamples: number of BRDF candidates to generate (matches RTXDI numBrdfSamples).
// misData:    MIS weight data shared with RTXDI_SampleLocalLights (same frame draw).
// brdfCutoff: RTXDI brdfCutoff — disables BRDF blend when 0.
Reservoir RTXDI_SampleBrdf(inout RTXDI_RandomSamplerState rng, DirectSurface surface, int numSamples, RTXDI_InitialSamplingMisData misData, float brdfCutoff, out LightSample o_selectedSample) {
    Reservoir state = RTXDI_EmptyDIReservoir();
    o_selectedSample = lt_null_sample();
    if (numSamples <= 0 || ph_light_count <= 0) {
        return state;
    }

    vec3 viewDir = normalize(rt_camera_position - surface.rtPos);

    // Match RTXDI DI initial sampling default (ReSTIRDI.cpp line 42).
    const float brdfRayMinT = 0.001f;

    vec3 rayOrigin = lt_surface_ray_origin(surface.rtPos, surface.geometryNormal);

    for (int i = 0; i < numSamples; i++) {
        // Step 1: importance-sample a BRDF direction using RTXDI's random-sampler-driven
        // diffuse/specular mixture (RAB_SurfaceImportanceSampleBrdf).
        vec3 sampleDir = vec3(0.0f);
        if (!rtxdi_surface_importance_sample_brdf(surface, rng, sampleDir)) {
            continue;
        }

        // Step 2: evaluate BRDF PDF for the sampled direction.
        // Fix 1: rtxdi_surface_evaluate_brdf_pdf now evaluates the Fresnel-weighted GGX+cosine
        // mixture PDF, matching the sampling distribution of ph_sample_brdf_direction exactly.
        float brdfPdf = rtxdi_surface_evaluate_brdf_pdf(surface, sampleDir);
        if (brdfPdf <= 0.0) {
            continue;
        }

        // Fix 2: RTXDI_BrdfMaxDistanceFromPdf (InitialSampling.hlsli line 525).
        // Limits trace distance based on PDF to control MIS cutoff region.
        // High PDF (specular peak) -> large maxDistance; low PDF (diffuse tail) -> shorter.
        float maxDistance = rtxdi_brdf_max_distance_from_pdf(brdfCutoff, brdfPdf);

        // Step 3: trace ray in sampled direction with brdfRayMinT and maxDistance limits.
        // breakOnEmpty stops traversal at the first empty block (sky), matching
        // the early-exit semantics of RAB_TraceRayForLocalLight.
        lightEmittance = vec3(0.0f);
        breakOnEmpty = true;
        ray.origin = rayOrigin + sampleDir * brdfRayMinT;
        ray.direction = sampleDir;
        trace_ray(ray, true);
        breakOnEmpty = false;

        // lightEmittance is set by trace_ray when the terminating block is emissive.
        // A zero lightEmittance means either air/opaque non-emitter or sky miss.
        if (!ray.result_hit || ph_luminance(lightEmittance) <= 1e-6f) {
            continue;
        }

        // Fix 2: discard hits beyond maxDistance (reference lines 535-546).
        float hitDistance = length(ray.result_position - rayOrigin);
        if (hitDistance > maxDistance) {
            continue;
        }

        // Step 4: identify the exact emitter cell that was hit.
        // RTXDI's bridge receives the exact hit light from RAB_TraceRayForLocalLight.
        // For Minecraft block lights, the bridge equivalent is: require the traced hit
        // cell to match the candidate light's block cell exactly. Do not fall back to a
        // nearest-light heuristic across neighboring cells.
        int lightIndex = -1;
        float bestDistSq = 3.402823466e+38f;
        ivec3 hitCell = ivec3(floor(ray.result_position));
        for (int j = 0; j < ph_light_count; j++) {
            Light candidate = load_light(j);
            if (any(notEqual(ivec3(floor(candidate.position)), hitCell))) {
                continue;
            }

            vec3 delta = candidate.position - ray.result_position;
            float distSq = dot(delta, delta);
            if (distSq < bestDistSq) {
                bestDistSq = distSq;
                lightIndex = j;
            }
        }

        if (lightIndex < 0) {
            continue;
        }

        // Step 5: evaluate target PDF and blended source PDF, then stream.
        // Preserve the hit-derived sample point when reconstructing the candidate so the
        // reservoir UV and the sampled emitter point stay aligned, matching RTXDI's use of
        // the hit-derived randXY in RAB_SamplePolymorphicLight.
        Light hitLight = load_light(lightIndex);
        vec3 sampledPosition = hitLight.position;
        vec2 sampleUv = vec2(0.0f);
        LightSample brdfSample = light_sample_new_at_position(hitLight, sampledPosition, surface);
        float targetPdf = brdfSample.weight;
        if (targetPdf <= 0.0) {
            continue;
        }

        // Fix 3: use power-CDF probability for lightSelectionPdf (RAB_EvaluateLocalLightSourcePdf).
        // This is the probability of picking the specific light via the global importance CDF,
        // matching RTXDI's RAB_EvaluateLocalLightSourcePdf which uses the actual source distribution.
        float lightSelectionPdf;
        float totalCdfWeight = ph_global_light_cdf_data[ph_light_count - 1];
        if (totalCdfWeight > 1e-6) {
            float prevCdf = lightIndex > 0 ? ph_global_light_cdf_data[lightIndex - 1] : 0.0;
            float lightWeight = ph_global_light_cdf_data[lightIndex] - prevCdf;
            lightSelectionPdf = lightWeight / totalCdfWeight;
        } else {
            lightSelectionPdf = 1.0 / float(max(ph_light_count, 1));
        }

        if (lightSelectionPdf <= 0.0) {
            continue;
        }

        // RTXDI_LightBrdfMisWeight blends lightSelectionPdf (converted to solid-angle domain)
        // with brdfPdf using balance-heuristic MIS, matching reference lines 573-576.
        float blendedSourcePdf = RTXDI_LightBrdfMisWeight(
            surface,
            brdfSample,
            lightSelectionPdf,
            misData.localLightMisWeight,
            misData.brdfMisWeight,
            brdfCutoff
        );

        if (blendedSourcePdf <= 0.0) {
            continue;
        }

        // Stream into reservoir -- reference line 579.
        bool selected = RTXDI_StreamSample(state, brdfSample.index, sampleUv, RTXDI_GetNextRandom(rng), targetPdf, 1.0f / blendedSourcePdf);
        if (selected) {
            o_selectedSample = brdfSample;
        }
    }

    // Reference line 585: FinalizeResampling(state, 1.0, misData.numMisSamples).
    RTXDI_FinalizeResampling(state, 1.0, float(misData.numMisSamples));
    // Reference line 586: state.M = 1.
    state.M = 1.0;
    return state;
}

Reservoir RTXDI_SampleBrdf(inout RTXDI_RandomSamplerState rng, DirectSurface surface, int numSamples, RTXDI_InitialSamplingMisData misData, float brdfCutoff) {
    LightSample ignoredSelectedSample;
    return RTXDI_SampleBrdf(rng, surface, numSamples, misData, brdfCutoff, ignoredSelectedSample);
}
// Backward-compat overload — stub signature kept so existing zero-sample call sites compile.
// numSamples == 0 returns an empty reservoir (M=0) with no side-effects.
Reservoir RTXDI_SampleBrdf(DirectSurface surface, int numSamples) {
    RTXDI_InitialSamplingMisData fallbackMis;
    fallbackMis.numMisSamples = 1;
    fallbackMis.localLightMisWeight = 1.0;
    fallbackMis.environmentMapMisWeight = 0.0;
    fallbackMis.brdfMisWeight = 0.0;
    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(uvec2(lt_current_pixel_pos()), uint(frameCounter), RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED);
    LightSample ignoredSelectedSample;
    return RTXDI_SampleBrdf(rng, surface, numSamples, fallbackMis, 0.0001f, ignoredSelectedSample);
}

// RTXDI_SampleLightsForSurface (InitialSampling.hlsli lines 592-671)
// Combines local, infinite, environment, and BRDF sub-reservoirs into one.
// Stubs for infinite/environment return M=0 reservoirs, which are no-ops
// in RTXDI_CombineDIReservoirs (weightSum contribution is 0*M=0).
Reservoir RTXDI_SampleLightsForSurface(DirectSurface surface) {
    uvec2 pixelPosition = uvec2(lt_current_pixel_pos());
    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(pixelPosition, uint(frameCounter), RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED);
    RTXDI_RandomSamplerState coherentRng = RTXDI_InitRandomSampler(pixelPosition / RTXDI_TILE_SIZE_IN_PIXELS, uint(frameCounter), RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED);

    // Compute numBrdfSamples and misData using the same uniform-reading logic as
    // RTXDI_SampleLocalLights, so both functions share a consistent MIS denominator.
    // Mirrors RTXDI_ComputeInitialSamplingMisData (InitialSampling.hlsli:41-54).
    int numLocalSamples = (ph_restir_initial_num_local_samples > 0.0)
        ? max(int(ph_restir_initial_num_local_samples), 1)
        : max(PH_LIGHTTREE_INITIAL_SAMPLES, 1);
    int numEnvironmentSamples = (ph_restir_initial_num_environment_samples > 0.0)
        ? int(ph_restir_initial_num_environment_samples)
        : (ph_restir_initial_num_environment_samples < -0.5 ? 0 : 1);
    int numBrdfSamples = (ph_restir_initial_num_brdf_samples > 0.0)
        ? int(ph_restir_initial_num_brdf_samples)
        : (ph_restir_initial_num_brdf_samples < -0.5 ? 0 : 1);
    RTXDI_InitialSamplingMisData misData = RTXDI_ComputeInitialSamplingMisData(numLocalSamples, numEnvironmentSamples, numBrdfSamples);
    float brdfCutoff = (ph_restir_initial_brdf_cutoff > 0.0) ? ph_restir_initial_brdf_cutoff : 0.0001f;

    // 1. Local lights
    LightSample localSample = lt_null_sample();
    Reservoir localReservoir = RTXDI_SampleLocalLights(rng, coherentRng, surface, localSample);

    // 2. Infinite lights (sun/moon) -- stub for now
    LightSample infiniteSample = lt_null_sample();
    Reservoir infiniteReservoir = RTXDI_SampleInfiniteLights(surface, 0);

    // 3. Environment map -- stub for now
    LightSample environmentSample = lt_null_sample();
    Reservoir environmentReservoir = RTXDI_SampleEnvironmentMap(surface, 0);

    // 4. BRDF importance sampling — passes misData and brdfCutoff so MIS weights
    // are consistent with the local-light pass (reference lines 573-576).
    LightSample brdfSample = lt_null_sample();
    Reservoir brdfReservoir = RTXDI_SampleBrdf(rng, surface, numBrdfSamples, misData, brdfCutoff, brdfSample);

    // Combine all four using RTXDI_CombineDIReservoirs (Algorithm 4, ReSTIR paper)
    Reservoir state = RTXDI_EmptyDIReservoir();
    RTXDI_CombineDIReservoirs(state, localReservoir, 0.5, localReservoir.targetPdf);
    bool selectInfinite = RTXDI_CombineDIReservoirs(state, infiniteReservoir, RTXDI_GetNextRandom(rng), infiniteReservoir.targetPdf);
    bool selectEnvironment = RTXDI_CombineDIReservoirs(state, environmentReservoir, RTXDI_GetNextRandom(rng), environmentReservoir.targetPdf);
    bool selectBrdf = RTXDI_CombineDIReservoirs(state, brdfReservoir, RTXDI_GetNextRandom(rng), brdfReservoir.targetPdf);

    // RTXDI: FinalizeResampling(state, 1.0, 1.0); state.M = 1;
    RTXDI_FinalizeResampling(state, 1.0, 1.0);
    state.M = 1.0;

    LightSample selectedLight = localSample;
    if (selectBrdf) {
        selectedLight = brdfSample;
    } else if (selectEnvironment) {
        selectedLight = environmentSample;
    } else if (selectInfinite) {
        selectedLight = infiniteSample;
    }

    // RTXDI: enableInitialVisibility (InitialSampling.hlsli:661-668)
    // Applied here on the COMBINED reservoir (local + infinite + env + BRDF), matching RTXDI.
    if (ph_restir_initial_enable_visibility > -0.5 && RTXDI_IsValidDIReservoir(state) && selectedLight.index >= 0) {
        float hitDist = light_sample_trace_hit_surface(selectedLight, false, surface);
        bool isVisible = hitDist > 0.0 && selectedLight.index >= 0;
        if (!isVisible) {
            RTXDI_StoreVisibilityInDIReservoir(state, vec3(0.0), true);
        }
    }

    return state;
}

// Traces an initial visibility ray for the selected sample and discards occluded samples.
// Controlled by ph_restir_initial_enable_visibility (RTXDI: enableInitialVisibility).
// SDK default (ReSTIRDI.cpp line 43): enabled = true.
// Sentinel pattern: < -0.5 → explicitly disabled, 0.0 (unbound) → SDK default enabled, >= 0.5 → enabled.
// Matches RTXDI InitialSampling.hlsli lines 661-668:
//   if (enableInitialVisibility && RTXDI_IsValidDIReservoir(state)) {
//     if (!RAB_GetConservativeVisibility(surface, selectedSample))
//       RTXDI_StoreVisibilityInDIReservoir(state, 0, true)  // discard invisible
//     // visible: do NOT store — leave visibility/age at the default zero state
//   }
void rtxdi_sample_local_lights_with_visibility(inout Reservoir reservoir, DirectSurface surface) {
    rtxdi_sample_local_lights(reservoir, surface);

    // SDK default: enabled. Explicitly disabled only with sentinel < -0.5.
    bool enableInitialVisibility = ph_restir_initial_enable_visibility > -0.5;
    if (!enableInitialVisibility) {
        return;
    }

    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        return;
    }

    // Reconstruct a LightSample from the reservoir's stored replay state for tracing.
    LightSample selectedLight = light_sample_decode(reservoir, surface, false);
    float hitDistance = light_sample_trace_hit_surface(selectedLight, false, surface);
    bool isVisible = hitDistance > 0.0f && selectedLight.index >= 0;

    if (isVisible) {
        // RTXDI InitialSampling.hlsli lines 661-668: on SUCCESS, do NOT call StoreVisibility.
        // The reservoir keeps its default packedVisibility=0, age=0 state.
    } else {
        // RTXDI: on FAILURE (occluded), discard the reservoir sample.
        // RTXDI_StoreVisibilityInDIReservoir(state, 0, true) — discardIfInvisible=true clears lightData+weightSum.
        RTXDI_StoreVisibilityInDIReservoir(reservoir, vec3(0.0f), true);
    }
}

void rtxdi_sample_lights(inout Reservoir reservoir) {
    rtxdi_sample_local_lights(reservoir, lt_current_surface());
}

bool rtxdi_load_spatial_with_surface(inout Reservoir reservoir, ivec2 uv, out DirectSurface sourceSurface) {
    sourceSurface = lt_current_surface();
    if (!lt_is_viewport_uv_in_bounds(uv)) {
        return false;
    }

    sourceSurface = lt_load_surface(uv);
    if (!lt_surface_matches(lt_current_surface(), sourceSurface, ph_restir_depth_threshold, ph_restir_normal_threshold)) {
        return false;
    }

    rtxdi_unpack_reservoir_at_surface(
        reservoir,
        texelFetch(radiosity_reservoirs, uv, 0),
        texelFetch(radiosity_reservoir_samples, uv, 0),
        texelFetch(radiosity_reservoir_meta, uv, 0),
        sourceSurface,
        false
    );
    return rtxdi_is_valid_reservoir(reservoir) && !isnan(reservoir.weightSum) && !isnan(reservoir.targetPdf);
}

bool rtxdi_load_spatial(inout Reservoir reservoir, ivec2 uv) {
    DirectSurface sourceSurface = lt_current_surface();
    return rtxdi_load_spatial_with_surface(reservoir, uv, sourceSurface);
}

bool rtxdi_load_previous_with_surface(
    inout Reservoir reservoir,
    DirectSurface currentSurface,
    ivec2 uv,
    out DirectSurface previousSurface
) {
    previousSurface = currentSurface;
    if (!lt_is_viewport_uv_in_bounds(uv)) {
        return false;
    }

    previousSurface = lt_load_previous_surface(uv);
    if (!lt_surface_matches_temporal(currentSurface, previousSurface, ph_restir_temporal_depth_threshold, ph_restir_temporal_normal_threshold)) {
        return false;
    }

    rtxdi_unpack_reservoir_at_surface(
        reservoir,
        texelFetch(prev_radiosity_reservoirs, uv, 0),
        texelFetch(prev_radiosity_reservoir_samples, uv, 0),
        texelFetch(prev_radiosity_reservoir_meta, uv, 0),
        previousSurface,
        true
    );
    // RTXDI: when light remap fails the mapped ID becomes invalid;
    // kill the weightSum so the reservoir cannot contribute (matching RTXDI prevSample.weightSum = 0).
    if (!RTXDI_IsValidDIReservoir(reservoir)) {
        reservoir.weightSum = 0.0f;
    }
    return rtxdi_is_valid_reservoir(reservoir) && !isnan(reservoir.weightSum) && !isnan(reservoir.targetPdf);
}

bool rtxdi_reproject_with_surface(inout Reservoir reservoir, out DirectSurface previousSurface, out ivec2 previousUv) {
    vec2 uv = ph_reprojectf(
        previous_modelview_projection,
        world_pos + block_normal * 0.01f,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    );
    previousUv = ivec2(uv);
    previousSurface = lt_current_surface();

    if (!lt_is_viewport_uv_in_bounds(uv)) {
        return false;
    }

    previousSurface = lt_load_previous_surface(previousUv);
    if (!lt_surface_matches_temporal(lt_current_surface(), previousSurface, ph_restir_temporal_depth_threshold, ph_restir_temporal_normal_threshold)) {
        return false;
    }

    rtxdi_unpack_reservoir_at_surface(
        reservoir,
        texelFetch(prev_radiosity_reservoirs, previousUv, 0),
        texelFetch(prev_radiosity_reservoir_samples, previousUv, 0),
        texelFetch(prev_radiosity_reservoir_meta, previousUv, 0),
        previousSurface,
        true
    );
    return rtxdi_is_valid_reservoir(reservoir);
}

bool rtxdi_reproject(inout Reservoir reservoir) {
    DirectSurface previousSurface = lt_current_surface();
    ivec2 previousUv = ivec2(0);
    return rtxdi_reproject_with_surface(reservoir, previousSurface, previousUv);
}

bool lt_is_complex_surface(DirectSurface surface) {
    float roughness = clamp(surface.material.x, 0.0f, 1.0f);
    float metallic = clamp(surface.material.y, 0.0f, 1.0f);
    float emission = clamp(surface.material.z, 0.0f, 1.0f);
    return roughness < 0.35f || metallic > 0.1f || emission > 0.0f;
}

bool lt_materials_similar(DirectSurface a, DirectSurface b) {
    float roughnessA = clamp(a.material.x, 0.0f, 1.0f);
    float roughnessB = clamp(b.material.x, 0.0f, 1.0f);
    if (!rtxdi_compare_relative_difference(roughnessA, roughnessB, 0.5f)) {
        return false;
    }

    vec3 specF0_A = mix(vec3(0.04f), clamp(a.albedo, vec3(0.0f), vec3(1.0f)), clamp(a.material.y, 0.0f, 1.0f));
    vec3 specF0_B = mix(vec3(0.04f), clamp(b.albedo, vec3(0.0f), vec3(1.0f)), clamp(b.material.y, 0.0f, 1.0f));
    if (abs(ph_luminance(specF0_A) - ph_luminance(specF0_B)) > 0.25f) {
        return false;
    }

    if (abs(ph_luminance(a.albedo) - ph_luminance(b.albedo)) > 0.25f) {
        return false;
    }

    return true;
}

#endif
