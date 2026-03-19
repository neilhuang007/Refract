#ifndef PH_LIGHTTREE_REUSE_INCLUDE
#define PH_LIGHTTREE_REUSE_INCLUDE

#include "/photonics/lighttree/light_tree.glsl"

layout(std430) restrict readonly buffer ph_global_light_cdf {
    float ph_global_light_cdf_data[];
};

// RTXDI: RTXDI_RIS_BUFFER — presampled power-importance tiles written by regir_presample_tiles.glsl.
// Used as outside-grid fallback in RTXDI_SampleLocalLights, matching RTXDI InitialSampling.hlsli
// POWER_RIS fallback: pick ONE tile via coherentRng, then draw from it each iteration.
layout(std430, binding = 5) restrict readonly buffer ph_ris_tile_buffer {
    uvec2 ph_ris_tile_data[];
};

uniform int ph_ris_tile_size;   // RTXDI: risBufferSegmentParams.tileSize
uniform int ph_ris_tile_count;  // RTXDI: risBufferSegmentParams.tileCount

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

// Load a light from the previous-frame buffer.
// Uses the exact same decoding as load_light() in ph_core.glsl but reads from
// ph_lights_array_previous instead of ph_lights_array.
// RTXDI equivalent: RAB_LoadLightInfo(index, true)
Light load_previous_light(int index) {
    // RTXDI: RAB_LoadLightInfo(selectedLightPrevID, true) loads unconditionally.
    // Validate against the previous-frame buffer capacity (maxLights), NOT ph_light_count.
    if (index < 0 || index * light_size + 3 >= ph_lights_array_previous.length()) {
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
uniform uint ph_restir_active_checkerboard_field;
uniform float ph_restir_spatial_depth_threshold;   // RTXDI: spatial depthThreshold (default 0.1)
uniform float ph_restir_spatial_normal_threshold;  // RTXDI: spatial normalThreshold (default 0.5)

// Initial sampling parameters — matches RTXDI_DIInitialSamplingParameters (ReSTIRDIParameters.h lines 69-85).
// When 0.0 (unbound), fall back to compile-time macro values.
uniform float ph_restir_initial_num_local_samples;       // RTXDI: numLocalLightSamples
uniform float ph_restir_initial_num_environment_samples; // RTXDI: numEnvironmentSamples (SDK default 1, ReSTIRDI.cpp line 41)
uniform float ph_restir_initial_num_brdf_samples;        // RTXDI: numBrdfSamples (stub; BRDF sampling not yet integrated)
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

bool lt_is_viewport_uv_in_bounds(ivec2 uv) {
    return all(greaterThanEqual(uv, ivec2(0))) && all(lessThan(uv, ivec2(viewWidth, viewHeight)));
}

bool lt_is_viewport_uv_in_bounds(vec2 uv) {
    return all(greaterThanEqual(uv, vec2(0.0f))) && all(lessThan(uv, vec2(viewWidth, viewHeight)));
}

const int lt_neighbor_offset_count = 32;
const vec2 lt_neighbor_offsets[lt_neighbor_offset_count] = vec2[](
    vec2(-0.490245f, -0.860319f),
    vec2(0.529266f, -0.580958f),
    vec2(0.039021f, 0.558722f),
    vec2(-0.451223f, -0.301597f),
    vec2(0.568287f, -0.022236f),
    vec2(0.078043f, -0.882555f),
    vec2(-0.412202f, 0.257125f),
    vec2(0.607309f, 0.536486f),
    vec2(0.117064f, -0.323833f),
    vec2(-0.373181f, 0.815848f),
    vec2(-0.863425f, -0.044472f),
    vec2(0.156085f, 0.234889f),
    vec2(-0.334159f, -0.625430f),
    vec2(-0.824404f, 0.514250f),
    vec2(0.685351f, -0.346069f),
    vec2(0.195107f, 0.793612f),
    vec2(-0.295138f, -0.066708f),
    vec2(0.724373f, 0.212653f),
    vec2(0.234128f, -0.647666f),
    vec2(-0.256117f, 0.492015f),
    vec2(-0.746361f, -0.368305f),
    vec2(0.273149f, -0.088944f),
    vec2(-0.217095f, -0.949263f),
    vec2(-0.707340f, 0.190417f),
    vec2(0.312171f, 0.469779f),
    vec2(-0.178074f, -0.390541f),
    vec2(0.841437f, -0.111180f),
    vec2(-0.139053f, 0.168182f),
    vec2(-0.629297f, -0.692138f),
    vec2(0.880458f, 0.447543f),
    vec2(0.390213f, -0.412777f),
    vec2(-0.100031f, 0.726904f)
);

ivec2 lt_random_temporal_resampling_offset(float radius) {
    return ivec2(
        int((rand_next_float() - 0.5f) * radius),
        int((rand_next_float() - 0.5f) * radius)
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
    // Use bitmask wrap to match RTXDI's pattern. lt_neighbor_offset_count must be a power of 2 (32).
    int wrappedIndex = sampleIdx & (lt_neighbor_offset_count - 1);

    return ivec2(lt_neighbor_offsets[wrappedIndex] * radius);
}

// RTXDI: RTXDI_ActivateCheckerboardPixel (TemporalResampling.hlsli line 90, SpatialResampling.hlsli line 68).
// Shifts the pixel position to match a checkerboard sampling pattern when active.
// activeCheckerboardField: 0 = off (Minecraft default), 1/2 = alternating fields.
// When activeCheckerboardField == 0 this is a no-op; the pixel position is unchanged.
// When active: odd-row pixels are shifted by +1 or -1 depending on the field to interleave
// current and previous frame pixels in a checkerboard layout.
void RTXDI_ActivateCheckerboardPixel(inout ivec2 pixelPos, bool previousFrame, int activeCheckerboardField) {
    // Checkerboard rendering not active — no-op when activeCheckerboardField == 0
    if (activeCheckerboardField == 0) return;
    // When active: shift odd-row pixels by 1 to match checkerboard pattern
    if ((pixelPos.y & 1) != 0) {
        pixelPos.x += (activeCheckerboardField == 1) ? 1 : -1;
    }
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

vec4 lt_extract_material_at_uv(vec2 uv) {
    vec4 spec = texture(specular, uv);
    float smoothness = clamp(spec.r, 0.0f, 1.0f);
    float roughness = clamp(1.0f - smoothness, 0.0f, 1.0f);
    float metallic = clamp(spec.g, 0.0f, 1.0f);
    float emission = clamp(spec.a, 0.0f, 1.0f);
    return vec4(roughness, metallic, emission, smoothness);
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
        albedo,
        lt_extract_material_at_uv((vec2(tex_coord) + vec2(0.5f)) / vec2(viewWidth, viewHeight))
    );
}

DirectSurface lt_load_surface(ivec2 uv) {
    return lt_make_surface(
        texelFetch(stage_radiosity_position, uv, 0).xyz,
        texelFetch(stage_radiosity_normal, uv, 0).xyz,
        texelFetch(stage_radiosity_mapped_normal, uv, 0).xyz,
        clamp(texelFetch(stage_radiosity_albedo, uv, 0).rgb, vec3(0.04f), vec3(1.0f)),
        texelFetch(stage_radiosity_material, uv, 0)
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
    return samplePos + geometryNormal * 0.02f;
}

struct LightSample {
    int index;
    vec3 position;
    vec3 sample_pos;
    vec3 color;
    vec3 dir;
    float weight;
};

LightSample lt_null_sample() {
    return LightSample(-1, vec3(0.0f), vec3(0.0f), vec3(0.0f), vec3(0.0f), 0.0f);
}

const float lt_pi = 3.14159265359f;

struct LightBrdf {
    float demodulatedDiffuse;
    vec3 specular;
};

vec3 lt_surface_f0(DirectSurface surface) {
    float metallic = clamp(surface.material.y, 0.0f, 1.0f);
    return mix(vec3(0.04f), clamp(surface.albedo, vec3(0.0f), vec3(1.0f)), metallic);
}

vec3 lt_fresnel_schlick(float cosTheta, vec3 f0) {
    return f0 + (vec3(1.0f) - f0) * pow(1.0f - clamp(cosTheta, 0.0f, 1.0f), 5.0f);
}

float lt_distribution_ggx(float nDotH, float roughness) {
    float clampedRoughness = max(roughness, 0.03f);
    float a = clampedRoughness * clampedRoughness;  // α = roughness²
    float a2 = a * a;                                // α² = roughness⁴
    float denom = nDotH * nDotH * (a2 - 1.0f) + 1.0f;
    return a2 / max(lt_pi * denom * denom, 1e-6f);
}

float lt_geometry_schlick_ggx(float nDotX, float roughness) {
    float a = max(roughness, 0.03f) * max(roughness, 0.03f);  // α = roughness², clamped
    float k = a * 0.5f;                                        // k = α/2 (analytic Smith-GGX)
    return nDotX / max(nDotX * (1.0f - k) + k, 1e-6f);
}

float lt_geometry_smith(float nDotV, float nDotL, float roughness) {
    return lt_geometry_schlick_ggx(nDotV, roughness) * lt_geometry_schlick_ggx(nDotL, roughness);
}

LightBrdf lt_evaluate_surface_brdf_with_view(DirectSurface surface, vec3 lightDir, vec3 viewDir) {
    LightBrdf brdf = LightBrdf(0.0f, vec3(0.0f));

    float nDotL = max(dot(surface.shadingNormal, lightDir), 0.0f);
    if (nDotL <= 0.0f) {
        return brdf;
    }

    float viewLengthSq = dot(viewDir, viewDir);
    if (viewLengthSq <= 1e-6f) {
        return brdf;
    }
    viewDir *= inversesqrt(viewLengthSq);

    float nDotV = max(dot(surface.shadingNormal, viewDir), 0.0f);
    if (nDotV <= 0.0f) {
        return brdf;
    }

    vec3 halfVector = normalize(viewDir + lightDir);
    float nDotH = max(dot(surface.shadingNormal, halfVector), 0.0f);
    float vDotH = max(dot(viewDir, halfVector), 0.0f);
    float roughness = clamp(surface.material.x, 0.03f, 1.0f);
    vec3 fresnel = lt_fresnel_schlick(vDotH, lt_surface_f0(surface));
    float distribution = lt_distribution_ggx(nDotH, roughness);
    float geometry = lt_geometry_smith(nDotV, nDotL, roughness);

    brdf.demodulatedDiffuse = nDotL / lt_pi;
    brdf.specular = distribution * geometry * fresnel / max(4.0f * nDotV, 1e-4f);
    return brdf;
}

LightBrdf lt_evaluate_surface_brdf(DirectSurface surface, vec3 lightDir) {
    return lt_evaluate_surface_brdf_with_view(surface, lightDir, rt_camera_position - surface.rtPos);
}

vec3 lt_light_sample_incident_radiance(DirectSurface surface, LightSample smple) {
    if (smple.index < 0 || ph_luminance(smple.color) <= 1e-6f) {
        return vec3(0.0f);
    }

    float nDotL = max(dot(surface.shadingNormal, smple.dir), 0.0f);
    if (nDotL <= 0.0f) {
        return vec3(0.0f);
    }

    return smple.color / max(nDotL, 1e-4f);
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
    if (smple.index < 0) {
        return 0.0f;
    }

    return ph_luminance(max(lt_surface_reflected_radiance(surface, smple), vec3(0.0f)));
}

float lt_surface_target_pdf_with_view(DirectSurface surface, LightSample smple, vec3 viewPos) {
    if (smple.index < 0) {
        return 0.0f;
    }

    vec3 incidentRadiance = lt_light_sample_incident_radiance(surface, smple);
    if (ph_luminance(incidentRadiance) <= 1e-6f) {
        return 0.0f;
    }

    LightBrdf brdf = lt_evaluate_surface_brdf_with_view(surface, smple.dir, viewPos - surface.rtPos);
    return ph_luminance(max(incidentRadiance * (brdf.demodulatedDiffuse * surface.albedo + brdf.specular), vec3(0.0f)));
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

// NRD-compatible split shading: returns demodulated diffuse and specular separately
LtSplitRadiance lt_shade_surface_split(DirectSurface surface, LightSample smple) {
    LtSplitRadiance result = LtSplitRadiance(vec3(0.0f), vec3(0.0f));

    vec3 incidentRadiance = lt_light_sample_incident_radiance(surface, smple);
    if (ph_luminance(incidentRadiance) <= 1e-6f) {
        return result;
    }

    vec3 viewDir = rt_camera_position - surface.rtPos;
    LightBrdf brdf = lt_evaluate_surface_brdf_with_view(surface, smple.dir, viewDir);

    // Diffuse: demodulatedDiffuse is already albedo-independent (Lambert/PI)
    // NRD expects diffuse demodulated by albedo, so we multiply by incident and leave it demodulated
    result.diffuse = max(incidentRadiance * brdf.demodulatedDiffuse, vec3(0.0f));

    // Specular: brdf.specular already includes Fresnel, GGX distribution, and geometry
    // NRD expects specular demodulated by F0
    vec3 specularF0 = lt_surface_f0(surface);
    vec3 rawSpecular = max(incidentRadiance * brdf.specular, vec3(0.0f));
    result.specular = rawSpecular / max(specularF0, vec3(0.01f));

    return result;
}

void light_sample_compute_weight(inout LightSample smple, DirectSurface surface) {
    smple.weight = lt_surface_target_pdf(surface, smple);
}

LightSample light_sample_new_at_position(Light light, vec3 lightPosition, DirectSurface surface) {
    vec3 origin = lt_surface_ray_origin(surface.rtPos, surface.geometryNormal);
    vec3 toLight = lightPosition - origin;
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
        0.0f
    );

    result.color = ph_compute_attenuation(
        light,
        toLight,
        origin,
        lightPosition,
        surface.geometryNormal,
        surface.shadingNormal
    );

    if (ph_luminance(result.color) <= 1e-6f) {
        return lt_null_sample();
    }

    light_sample_compute_weight(result, surface);
    return result;
}

LightSample light_sample_new_at(Light light, DirectSurface surface) {
    return light_sample_new_at_position(light, light.position, surface);
}

vec3 lt_sample_light_position(Light light, vec3 shadowRayOrigin) {
    vec3 selectedPosition = light.position;
#ifdef PH_LIGHTTREE_SOFT_SHADOWS
    ray.origin = shadowRayOrigin;
    jitter_sample_position(selectedPosition);
#endif
    return selectedPosition;
}

float lt_light_sample_source_pdf() {
#ifdef PH_LIGHTTREE_SOFT_SHADOWS
    return 1.0f / max(lt_pi * ph_light_jitter_radius * ph_light_jitter_radius, 1e-6f);
#else
    return 1.0f;
#endif
}

LightSample light_sample_random_at(Light light, DirectSurface surface) {
    vec3 origin = lt_surface_ray_origin(surface.rtPos, surface.geometryNormal);
    vec3 selectedPosition = lt_sample_light_position(light, origin);
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

float light_sample_trace_hit_surface(inout LightSample smple, bool jitter, DirectSurface surface) {
    if (smple.index < 0) {
        return 0.0f;
    }

    Light light = load_light(smple.index);
    vec3 targetPosition = smple.position;
    if (distance(targetPosition, light.position) <= 1e-5f && jitter) {
        ray.origin = smple.sample_pos;
        jitter_sample_position(targetPosition);
    }

    vec3 toLight = targetPosition - smple.sample_pos;
    float lightDistance = length(toLight);
    if (lightDistance <= 1e-5f) {
        smple = lt_null_sample();
        return 0.0f;
    }

    smple.position = targetPosition;
    smple.dir = toLight / lightDistance;

    ray.origin = smple.sample_pos;
    ray.direction = smple.dir;
    ray_target = ivec3(smple.position);
    trace_ray(ray, true);

    if (!ray.result_hit || floor(smple.position) != floor(ray.result_position)) {
        smple.color = vec3(0.0f);
        return 0.0f;
    }

    smple.color = ph_compute_attenuation(
        light,
        toLight,
        smple.sample_pos,
        smple.position,
        surface.geometryNormal,
        surface.shadingNormal
    );
    light_sample_compute_weight(smple, surface);
    return lightDistance;
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

LightSample light_sample_decode_at(float value, vec3 sampleWorldPosition, DirectSurface surface, bool remap) {
    int index = int(round(value));
    if (index < 0 || index >= ph_light_count) {
        return lt_null_sample();
    }

    if (remap) {
        index = ph_lights_array_mapping[index];
        if (index < 0 || index >= ph_light_count) {
            return lt_null_sample();
        }
    }

    Light light = load_light(index);
    if (dot(sampleWorldPosition, sampleWorldPosition) <= 1e-8f) {
        return light_sample_new_at(light, surface);
    }

    return light_sample_new_at_position(light, sampleWorldPosition - world_offset, surface);
}

LightSample light_sample_decode_at(float value, DirectSurface surface, bool remap) {
    return light_sample_decode_at(value, vec3(0.0f), surface, remap);
}

struct Reservoir {
    // Light reference — matches RTXDI's lightData + uvData concept.
    // For Minecraft point lights, storedPosition is our equivalent of UV
    // (there is no sub-light-surface parameterization for point sources).
    int lightIndex;          // RTXDI: lightData (index + validity bit)
    vec3 storedPosition;     // RTXDI: uvData (stored sample point, RT-space)

    // RIS state
    float weightSum;         // RTXDI: weightSum (RIS weight sum / inverse PDF after finalize)
    float targetPdf;         // RTXDI: targetPdf (target PDF of selected sample)
    float M;                 // RTXDI: M (number of candidates considered)

    // Visibility reuse — RTXDI stores 3-channel packed RGB visibility.
    // We use vec3 to match the per-channel representation.
    vec3 visibility;         // RTXDI: packedVisibility (per-channel, -1 = uninitialized)

    // Tracking
    float age;               // RTXDI: age (frames since visibility was generated)
    vec2 spatialDistance;     // RTXDI: spatialDistance (screen-space offset from visibility origin)

    // Pairwise MIS
    float canonicalWeight;   // RTXDI: canonicalWeight (accumulated during pairwise MIS)
};

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
    r.lightIndex = -1;
    r.storedPosition = vec3(0.0);
    r.weightSum = 0.0;
    r.targetPdf = 0.0;
    r.M = 0.0;
    r.visibility = vec3(-1.0);  // uninitialized marker
    r.age = 0.0;
    r.spatialDistance = vec2(0.0);
    r.canonicalWeight = 0.0;
    return r;
}
// Backward-compat alias
Reservoir rtxdi_empty_reservoir() { return RTXDI_EmptyDIReservoir(); }

// Primary — matches RTXDI semantics: only checks light index validity (Reservoir.hlsli: lightData != 0)
bool RTXDI_IsValidDIReservoir(Reservoir reservoir) {
    return reservoir.lightIndex >= 0;
}

// Stricter photonics validity check — also requires M > 0 and weightSum > 0.
// Kept separate from RTXDI_IsValidDIReservoir for callers that need it.
bool rtxdi_is_valid_reservoir(Reservoir reservoir) {
    return reservoir.lightIndex >= 0 && reservoir.M > 0.0f && reservoir.weightSum > 0.0f;
}

// Accessor wrappers — naming parity with RTXDI's Reservoir.hlsli accessor functions.
int RTXDI_GetDIReservoirLightIndex(Reservoir reservoir) {
    return reservoir.lightIndex;
}

vec3 RTXDI_GetDIReservoirSamplePosition(Reservoir reservoir) {
    return reservoir.storedPosition;
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
    reservoir.visibility = vec3(-1.0f);
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
    return any(greaterThan(reservoir.visibility, vec3(-0.5f)))
        && reservoir.age > 0.0f
        && reservoir.age <= maxAge
        && length(reservoir.spatialDistance) < maxDistance;
}

// Returns the stored RGB visibility. Uninitialized (sentinel -1) is treated as fully visible
// so that reservoirs without a traced visibility ray are not incorrectly discarded.
vec3 rtxdi_get_visibility(Reservoir reservoir) {
    return (reservoir.visibility.x < -0.5f) ? vec3(1.0f) : clamp(reservoir.visibility, vec3(0.0f), vec3(1.0f));
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
        // storedPosition (uvData) is intentionally NOT cleared — RTXDI leaves it intact.
        // M and targetPdf are also preserved for correct downstream resampling.
        reservoir.lightIndex = -1;
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

    if (!any(greaterThan(sourceReservoir.visibility, vec3(-0.5f)))) {
        return;
    }

    reservoir.age = min(sourceReservoir.age + 1.0f, ph_restir_visibility_max_age);
    if (temporalReuse) {
        reservoir.spatialDistance = vec2(0.0f);
    } else {
        reservoir.spatialDistance = sourceReservoir.spatialDistance + vec2(sourceUv - currentUv);
    }
}

// Primary — matches RTXDI_StreamSample signature (Reservoir.hlsli).
// Takes explicit lightIndex, position (RT-space), random value, targetPdf, and invSourcePdf.
// Always increments M; does NOT reset visibility (caller manages visibility lifecycle).
bool RTXDI_StreamSample(inout Reservoir reservoir, int lightIndex, vec3 position, float random, float targetPdf, float invSourcePdf) {
    float risWeight = targetPdf * invSourcePdf;
    reservoir.M += 1.0f;
    reservoir.weightSum += risWeight;
    bool selectSample = (random * reservoir.weightSum < risWeight);
    if (selectSample) {
        reservoir.lightIndex = lightIndex;
        reservoir.storedPosition = position;
        reservoir.targetPdf = targetPdf;
    }
    return selectSample;
}

// Backward-compat alias — preserves original LightSample-based call sites.
bool rtxdi_stream_sample(inout Reservoir reservoir, LightSample smple, float weight, float samples) {
    // Always increment M (matching RTXDI_StreamSample behavior)
    reservoir.M += max(samples, 0.0f);

    if (smple.index < 0 || weight <= 0.0f || samples <= 0.0f) {
        return false;
    }

    reservoir.weightSum += weight;
    if (rand_next_float() * reservoir.weightSum < weight) {
        reservoir.lightIndex = smple.index;
        reservoir.storedPosition = smple.position;
        reservoir.targetPdf = smple.weight;
        rtxdi_reset_visibility(reservoir);
        return true;
    }

    return false;
}

float rtxdi_target_pdf_at_surface(Reservoir reservoir, DirectSurface surface) {
    if (reservoir.lightIndex < 0) {
        return 0.0f;
    }

    return light_sample_target_pdf_at_surface(reservoir.lightIndex, reservoir.storedPosition + world_offset, surface);
}

float rtxdi_target_pdf_at_surface_with_view(Reservoir reservoir, DirectSurface surface, vec3 viewPos) {
    if (reservoir.lightIndex < 0) {
        return 0.0f;
    }

    LightSample smple = light_sample_new_at_position(
        load_light(reservoir.lightIndex),
        reservoir.storedPosition,
        surface
    );
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
        reservoir.lightIndex = candidateReservoir.lightIndex;
        reservoir.storedPosition = candidateReservoir.storedPosition;
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

    if (candidateReservoir.lightIndex < 0 || targetPdf <= 0.0f || sampleNormalization <= 0.0f || sampleM <= 0.0f) {
        return false;
    }

    float risWeight = targetPdf * sampleNormalization;
    reservoir.weightSum += risWeight;

    bool selectSample = randomValue * reservoir.weightSum < risWeight;
    if (selectSample) {
        reservoir.lightIndex = candidateReservoir.lightIndex;
        reservoir.storedPosition = candidateReservoir.storedPosition;
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
    // Denominator is numLocalSamples only because BRDF/environment MIS is not yet integrated.
    // RTXDI uses misData.numMisSamples (local + BRDF + environment total) as the denominator.
    // TODO: change denominator to numMisSamples when BRDF-MIS sampling is added.
    rtxdi_finalize_resampling(reservoir, 1.0f, float(max(PH_LIGHTTREE_INITIAL_SAMPLES, 1)), reservoir.targetPdf);
}

float light_sample_encode_index(int lightIndex) {
    return float(lightIndex);
}

vec4 rtxdi_pack_reservoir(Reservoir reservoir) {
    return vec4(
        light_sample_encode_index(reservoir.lightIndex),
        reservoir.weightSum,
        reservoir.targetPdf,
        min(reservoir.M, 16383.0f)  // RTXDI_PackedDIReservoir_MaxM = 0x3fff
    );
}

vec4 rtxdi_pack_reservoir_sample(Reservoir reservoir) {
    if (reservoir.lightIndex < 0) {
        return vec4(0.0f);
    }

    return vec4(reservoir.storedPosition + world_offset, 1.0f);
}

// Pack age [0, 255] and spatialDistance [[-127, 127], [-127, 127]] into a single float32.
// Matches RTXDI's RTXDI_PackedDIReservoir_MaxAge = 0xff (ReservoirStorage.hlsli line 34).
// Uses 8 bits for age (max 255) and 8 bits each for spatial x/y (offset by +128 to be unsigned).
// Encoding: age * 65536 + (sx+128) * 256 + (sy+128).
// Maximum packed value = 255 * 65536 + 255 * 256 + 255 = 16,777,215 = 2^24 - 1,
// which is exactly within float32's 24-bit integer precision (all integers 0..2^24 are exact).
float rtxdi_pack_age_distance(float age, vec2 sd) {
    int iage = clamp(int(age), 0, 255);  // 8-bit age; RTXDI_PackedDIReservoir_MaxAge = 0xff
    int isx = clamp(int(round(sd.x)), -127, 127) + 128;
    int isy = clamp(int(round(sd.y)), -127, 127) + 128;
    return float(iage * 65536 + isx * 256 + isy);
}

void rtxdi_unpack_age_distance(float packed, out float age, out vec2 sd) {
    int ipacked = int(packed);
    int isy = ipacked & 0xFF;
    int isx = (ipacked >> 8) & 0xFF;
    int iage = (ipacked >> 16) & 0xFF;  // 8-bit age; RTXDI_PackedDIReservoir_MaxAge = 0xff
    age = float(iage);
    sd = vec2(float(isx) - 128.0f, float(isy) - 128.0f);
}

vec4 rtxdi_pack_reservoir_meta(Reservoir reservoir) {
    // RGB visibility stored in xyz; packed age+spatialDistance in w.
    // If visibility is uninitialized (sentinel -1), clamp to 0 — age==0 signals freshness.
    vec3 vis = (reservoir.visibility.x < -0.5f)
        ? vec3(0.0f)
        : clamp(reservoir.visibility, vec3(0.0f), vec3(1.0f));
    return vec4(vis, rtxdi_pack_age_distance(reservoir.age, reservoir.spatialDistance));
}

void rtxdi_unpack_reservoir_at_surface(inout Reservoir reservoir, vec4 color, vec4 sampleData, vec4 meta, DirectSurface surface, bool remap) {
    int index = int(round(color.x));
    vec3 sampleWorldPosition = sampleData.xyz;

    if (remap) {
        // Previous→current frame remap via mapping buffer (sized to maxLights).
        if (index >= 0 && index < ph_lights_array_mapping.length()) {
            index = ph_lights_array_mapping[index];
        }
        // After remap, validate against current light count.
        if (index < 0 || index >= ph_light_count) {
            index = -1;
        }
    }
    // When remap=false, the index is a previous-frame ID and is NOT validated here.
    // RTXDI_LoadDIReservoir does not validate — remapping happens separately at the
    // call site (TemporalResampling.hlsli line 135).

    reservoir.lightIndex = index;
    reservoir.storedPosition = (dot(sampleWorldPosition, sampleWorldPosition) > 1e-8)
        ? sampleWorldPosition - world_offset
        : vec3(0.0f);
    reservoir.weightSum = color.y;
    reservoir.targetPdf = color.z;
    reservoir.M = color.w;

    // Unpack RGB visibility from meta.xyz; unpack age+spatialDistance from meta.w.
    // Always preserve the raw packed visibility — age == 0 means freshly traced this frame,
    // not uninitialized. The uninitialized sentinel (vec3(-1)) is handled by rtxdi_pack_reservoir_meta
    // which stores vec3(0) when visibility was -1 at pack time. Reuse eligibility is gated by
    // rtxdi_has_reusable_visibility (requires age > 0), NOT by zeroing the value here.
    // This matches RTXDI_GetDIReservoirVisibility which returns packed bits unconditionally.
    float unpackedAge;
    vec2 unpackedSd;
    rtxdi_unpack_age_distance(meta.w, unpackedAge, unpackedSd);
    reservoir.visibility = meta.xyz;  // Always preserve raw packed visibility
    reservoir.age = unpackedAge;
    reservoir.spatialDistance = unpackedSd;
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

// RTXDI: RTXDI_LightBrdfMisWeight (InitialSampling.hlsli:66-96)
// localLightMisWeight blends the light-selection PDF with the BRDF PDF.
// When numBrdfSamples=0, localLightMisWeight=1.0 and blendedSourcePdf == sourcePdf,
// so the RIS weight is numerically identical to the pre-MIS formula.
void rtxdi_stream_local_light(inout Reservoir reservoir, DirectSurface surface, int lightIndex, float sourcePdf, float localLightMisWeight) {
    // RTXDI InitialSampling.hlsli:129-133: StreamSample is only called when blendedSourcePdf != 0.
    // If the light is truly invalid (no valid index or zero PDF), skip streaming entirely — M is NOT
    // incremented, matching RTXDI where a zero blendedSourcePdf means the stream call is skipped.
    if (lightIndex < 0 || lightIndex >= ph_light_count || sourcePdf <= 0.0f) {
        return;
    }

    LightSample smple = light_sample_random_at(load_light(lightIndex), surface);
    // blendedSourcePdf = localLightMisWeight * sourcePdf * solidAnglePdf
    // (brdfMisWeight * brdfPdf term is 0 when numBrdfSamples = 0)
    float blendedSourcePdf = localLightMisWeight * sourcePdf * lt_light_sample_source_pdf();
    // RTXDI: only skip on exact zero (InitialSampling.hlsli:129) — no epsilon clamp.
    if (blendedSourcePdf == 0.0) {
        return;
    }
    float invSourcePdf = 1.0 / blendedSourcePdf;
    // RTXDI_StreamSample: increments M, uses risWeight = targetPdf * invSourcePdf.
    RTXDI_StreamSample(reservoir, smple.index, smple.position, rand_next_float(), smple.weight, invSourcePdf);
}

// Backward-compat overload — passes localLightMisWeight=1.0 (no MIS blending).
void rtxdi_stream_local_light(inout Reservoir reservoir, DirectSurface surface, int lightIndex, float sourcePdf) {
    rtxdi_stream_local_light(reservoir, surface, lightIndex, sourcePdf, 1.0f);
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

// RTXDI: RTXDI_InitialSamplingMisData (InitialSampling.hlsli:33-39)
// Tracks per-technique sample counts and their MIS weights for blended source PDF computation.
struct RTXDI_InitialSamplingMisData {
    int numMisSamples;         // total candidates across all techniques
    float localLightMisWeight; // fraction of candidates from local-light sampling
    float brdfMisWeight;       // fraction of candidates from BRDF sampling (0 until BRDF pass is added)
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
    result.brdfMisWeight = float(numBrdfSamples) / float(result.numMisSamples);
    return result;
}

// Backward-compat overload — passes numEnvironmentSamples=0 for existing two-arg call sites.
RTXDI_InitialSamplingMisData RTXDI_ComputeInitialSamplingMisData(int numLocalLightSamples, int numBrdfSamples) {
    return RTXDI_ComputeInitialSamplingMisData(numLocalLightSamples, 0, numBrdfSamples);
}

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
// Here coherent_rng_state is seeded from the block-aligned (8x8) pixel position to give
// spatial coherence while avoiding the per-pixel temporal variation of rng_state.
Reservoir RTXDI_SampleLocalLights(DirectSurface surface) {
    Reservoir state = RTXDI_EmptyDIReservoir();

    // Coherent RNG: seeded from 16x16 block-aligned pixel position + frame counter.
    // Block alignment ensures neighboring pixels in the same block share the ReGIR cell
    // draw, matching RTXDI's coherentRng semantic for RTXDI_CalculateReGIRCellIndex.
    // 16x16 matches RTXDI_TILE_SIZE_IN_PIXELS = 16 (RtxdiParameters.h line 65).
    ivec2 blockCoord = ivec2(tex_coord) / 16;
    uint coherent_rng_state = uint(blockCoord.x * 1664525u + blockCoord.y * 1013904223u)
        ^ uint(frameCounter * 2246822519u);

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
        useRegir = regir_resolve_cell(surface.worldPos, coherent_rng_state, regirFlatCellIndex);
    }

    // Runtime-overridable sample count. ph_restir_initial_num_local_samples == 0.0 means unbound:
    // fall back to the compile-time PH_LIGHTTREE_INITIAL_SAMPLES constant (RTXDI default = 8).
    int numLocalSamples = (ph_restir_initial_num_local_samples > 0.0)
        ? max(int(ph_restir_initial_num_local_samples), 1)
        : max(PH_LIGHTTREE_INITIAL_SAMPLES, 1);

    // RTXDI: early exit when numLocalLightSamples == 0 (InitialSampling.hlsli lines 322-323).
    if (numLocalSamples == 0) {
        return RTXDI_EmptyDIReservoir();
    }

    // RTXDI: RTXDI_ComputeInitialSamplingMisData (InitialSampling.hlsli:41-54)
    // numBrdfSamples=0 for now — will be nonzero when BRDF sampling is added.
    // numEnvironmentSamples: SDK default 1 (ReSTIRDI.cpp line 41). 0.0 (unbound) falls back to 1.
    // Environment stub returns M=0 but the count still appears in the MIS denominator per RTXDI.
    int numEnvironmentSamples = (ph_restir_initial_num_environment_samples > 0.0)
        ? int(ph_restir_initial_num_environment_samples)
        : 1;
    RTXDI_InitialSamplingMisData misData = RTXDI_ComputeInitialSamplingMisData(numLocalSamples, numEnvironmentSamples, 0);

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
        float coherentRnd = ph_RandomFloat01(coherent_rng_state);
        uint fallbackTileIndex = min(uint(coherentRnd * float(ph_ris_tile_count)), uint(ph_ris_tile_count) - 1u);
        fallbackTileOffset = fallbackTileIndex * uint(ph_ris_tile_size);
    }

    for (int i = 0; i < numLocalSamples; i++) {
        int lightIndex = -1;
        float sourcePdf = 0.0f;

        if (localLightSamplingMode == RTXDI_LOCAL_LIGHT_SAMPLING_REGIR_RIS && useRegir) {
            // ReGIR_RIS, inside grid: draw from the ReGIR cell's RIS slots.
            // RTXDI: RTXDI_SelectNextLocalLight with ReGIR RIS context.
            // Draws from [0, lightsPerCell) -- invalid entries (invSourcePdf=0)
            // produce zero RIS weight via rtxdi_stream_local_light and don't contribute.
            // RTXDI_STRATIFY_LOCAL_SAMPLING (InitialSampling.hlsli:280): stratify the
            // per-iteration draw so samples are spread evenly across the cell's slots.
            float regirRnd = (rand_next_float() + float(i)) / float(numLocalSamples);
            regir_pick_light(regirFlatCellIndex, regirRnd, lightIndex, sourcePdf);
        } else if (hasFallbackTiles) {
            // Power_RIS or ReGIR_RIS (outside grid): draw from the pre-selected RIS tile.
            // Stratified draw spreads iterations across the tile (RTXDI_STRATIFY_LOCAL_SAMPLING).
            // Matches RTXDI_RandomlySelectLightDataFromRISTile in InitialSampling.hlsli.
            float tileRnd = (rand_next_float() + float(i)) / float(numLocalSamples);
            uint risSample = min(uint(floor(tileRnd * float(ph_ris_tile_size))), uint(ph_ris_tile_size) - 1u);
            uvec2 tileData = ph_ris_tile_data[fallbackTileOffset + risSample];
            bool hasCompactData = (tileData.x & RTXDI_LIGHT_COMPACT_BIT) != 0u;
            lightIndex = int(tileData.x & RTXDI_LIGHT_INDEX_MASK);
            float invSourcePdf = uintBitsToFloat(tileData.y);
            if (hasCompactData || invSourcePdf <= 0.0f || lightIndex < 0 || lightIndex >= ph_light_count) {
                lightIndex = -1;
                sourcePdf = 0.0f;
            } else {
                sourcePdf = 1.0f / invSourcePdf;
            }
        } else {
            // Uniform (mode 0, SDK default) or tile buffer unavailable: equal probability from light buffer.
            lt_pick_uniform_light(lightIndex, sourcePdf);
        }

        // RTXDI: RTXDI_StreamLocalLightAtUVIntoReservoir -- always called, always increments M.
        // Invalid entries (lightIndex<0, sourcePdf=0) get zero risWeight -> no contribution.
        // Pass MIS weight so blendedSourcePdf = localLightMisWeight * sourcePdf (RTXDI:66-96).
        rtxdi_stream_local_light(state, surface, lightIndex, sourcePdf, misData.localLightMisWeight);
    }

    // RTXDI: RTXDI_FinalizeResampling(state, 1.0, misData.numMisSamples) (InitialSampling.hlsli:291).
    // 3-parameter form — no max() guard; zero case is handled by the early exit above.
    RTXDI_FinalizeResampling(state, 1.0, float(misData.numMisSamples));
    // RTXDI sets M=1 after initial RIS (InitialSampling.hlsli:292).
    state.M = 1.0f;
    return state;
}

// Backward-compat: original in-place API delegating to RTXDI_SampleLocalLights.
void rtxdi_sample_local_lights(inout Reservoir reservoir, DirectSurface surface) {
    reservoir = RTXDI_SampleLocalLights(surface);
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
// Stub: BRDF importance sampling not yet integrated.
// Returns empty reservoir with M=0.
Reservoir RTXDI_SampleBrdf(DirectSurface surface, int numSamples) {
    Reservoir state = RTXDI_EmptyDIReservoir();
    // TODO: When adding BRDF ray tracing:
    // - Importance sample BRDF direction (cosine-weighted + GGX)
    // - Trace ray to find intersecting lights
    // - Evaluate target PDF, apply MIS weighting
    return state;
}

// RTXDI_SampleLightsForSurface (InitialSampling.hlsli lines 592-671)
// Combines local, infinite, environment, and BRDF sub-reservoirs into one.
// Stubs for infinite/environment/BRDF return M=0 reservoirs, which are no-ops
// in RTXDI_CombineDIReservoirs (weightSum contribution is 0*M=0).
Reservoir RTXDI_SampleLightsForSurface(DirectSurface surface) {
    // 1. Local lights
    Reservoir localReservoir = RTXDI_SampleLocalLights(surface);

    // 2. Infinite lights (sun/moon) -- stub for now
    Reservoir infiniteReservoir = RTXDI_SampleInfiniteLights(surface, 0);

    // 3. Environment map -- stub for now
    Reservoir environmentReservoir = RTXDI_SampleEnvironmentMap(surface, 0);

    // 4. BRDF samples -- stub for now
    Reservoir brdfReservoir = RTXDI_SampleBrdf(surface, 0);

    // Combine all four using RTXDI_CombineDIReservoirs (Algorithm 4, ReSTIR paper)
    Reservoir state = RTXDI_EmptyDIReservoir();
    RTXDI_CombineDIReservoirs(state, localReservoir, 0.5, localReservoir.targetPdf);
    RTXDI_CombineDIReservoirs(state, infiniteReservoir, rand_next_float(), infiniteReservoir.targetPdf);
    RTXDI_CombineDIReservoirs(state, environmentReservoir, rand_next_float(), environmentReservoir.targetPdf);
    RTXDI_CombineDIReservoirs(state, brdfReservoir, rand_next_float(), brdfReservoir.targetPdf);

    // RTXDI: FinalizeResampling(state, 1.0, 1.0); state.M = 1;
    RTXDI_FinalizeResampling(state, 1.0, 1.0);
    state.M = 1.0;

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
//     // visible: do NOT store — leave reservoir visibility at its uninitialized sentinel
//   }
void rtxdi_sample_local_lights_with_visibility(inout Reservoir reservoir, DirectSurface surface) {
    rtxdi_sample_local_lights(reservoir, surface);

    // SDK default: enabled. Explicitly disabled only with sentinel < -0.5.
    bool enableInitialVisibility = ph_restir_initial_enable_visibility > -0.5;
    if (!enableInitialVisibility) {
        return;
    }

    if (!rtxdi_is_valid_reservoir(reservoir)) {
        return;
    }

    // Reconstruct a LightSample from the reservoir's stored index/position for tracing.
    LightSample selectedLight = light_sample_new_at_position(
        load_light(reservoir.lightIndex), reservoir.storedPosition, surface);
    float hitDistance = light_sample_trace_hit_surface(selectedLight, false, surface);
    bool isVisible = hitDistance > 0.0f && selectedLight.index >= 0;

    if (isVisible) {
        // RTXDI InitialSampling.hlsli lines 661-668: on SUCCESS, do NOT call StoreVisibility.
        // The reservoir keeps its default uninitialized visibility sentinel (vec3(-1)).
        // Update stored position with the traced hit position for consistency.
        reservoir.storedPosition = selectedLight.position;
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
    if (reservoir.lightIndex < 0) {
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
