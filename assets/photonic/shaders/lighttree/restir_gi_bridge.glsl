#ifndef PHOTONICS_RESTIR_GI_BRIDGE_GLSL
#define PHOTONICS_RESTIR_GI_BRIDGE_GLSL

#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_gi_initial_sampling_impl.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

#ifndef PH_LIGHTTREE_GI_INITIAL_SAMPLES
#define PH_LIGHTTREE_GI_INITIAL_SAMPLES PH_LIGHTTREE_INITIAL_SAMPLES
#endif

const float lt_indirect_max_history = 8.0f;
const float lt_gi_pi = 3.14159265359f;
const float lt_gi_max_brdf_value = 1e4f;
const float lt_gi_mis_roughness = 0.3f;
const float lt_gi_normal_threshold = 0.6f;

float lt_gi_spatial_reuse_radius() {
    return 32.0f;
}

vec4 lt_build_handheld_stage() {
    vec4 handheldLighting = vec4(0.0f);
    if (any(notEqual(handheld_color, vec3(0.0f)))) {
        vec4 handDirection = direction_transformation_matrix_in * vec4(left_handed ? 1.0f : -1.0f, -1.0f, 0.0f, 1.0f);
        handDirection.w = 1.0f / handDirection.w;
        handDirection.xyz *= handDirection.w;

        ray.origin = handDirection.xyz + rt_camera_position;
        vec3 toLight = rt_pos - ray.origin;
        ray.direction = normalize(toLight);
        trace_ray(ray, true);

        float distanceSquared = dot(toLight, toLight);
        float brightness = 2.1f / dot(vec2(1.0f, distanceSquared), vec2(0.9f, 0.1f));
        brightness = max(brightness, 0.02f);

        float handToBaseDistance = distance(ray.origin, rt_pos);
        float handToResultDistance = distance(ray.origin, ray.result_position);
        brightness *= clamp(30.0f * (handToResultDistance - handToBaseDistance + 0.05f), 0.0f, 1.0f);
        brightness *= dot(normal, -ray.direction);
        brightness *= 0.4f;

        vec3 handheldTint = vec3(1.0f);
        if (!ray.result_hit || floor(rt_pos) != floor(ray.result_position)) {
            handheldTint = vec3(0.0f);
        } else {
            handheldTint = result_tint_color;
        }

        handheldLighting.xyz = brightness * handheld_color * handheldTint;
    }
    return vec4(handheldLighting.rgb, 1.0f);
}

struct RTXDI_GISample {
    vec3 position;
    vec3 normal;
    vec3 radiance;
};

struct SplitBrdf {
    float demodulatedDiffuse;
    vec3 specular;
};

SplitBrdf gi_empty_split_brdf() {
    return SplitBrdf(0.0f, vec3(0.0f));
}

struct RTXDI_GIReservoir {
    RTXDI_GISample selected;
    float weight_sum;
    float samples;
    float age;
    uint miscData;
};

RTXDI_GISample gi_null_sample() {
    return RTXDI_GISample(vec3(0.0f), vec3(0.0f), vec3(0.0f));
}

RTXDI_GIReservoir RTXDI_EmptyGIReservoir() {
    return RTXDI_GIReservoir(gi_null_sample(), 0.0f, 0.0f, 0.0f, 0u);
}

const uint gi_misc_flag_skylight = 1u << 16u;

bool gi_reservoir_is_skylight(RTXDI_GIReservoir reservoir) {
    return (reservoir.miscData & gi_misc_flag_skylight) != 0u;
}

void gi_mark_reservoir_skylight(inout RTXDI_GIReservoir reservoir) {
    reservoir.miscData |= gi_misc_flag_skylight;
}

bool gi_sample_is_skylight(RTXDI_GIReservoir reservoir, RAB_Surface surface) {
    return gi_reservoir_is_skylight(reservoir)
        || distance(reservoir.selected.position, surface.worldPos) > 32768.0f;
}

bool gi_is_skylight_sample_position(vec3 samplePosition, vec3 worldPosition) {
    return distance(samplePosition, worldPosition) > 32768.0f;
}

float gi_skylight_distance() {
    return 65536.0f;
}

bool gi_sample_is_valid(RTXDI_GISample giSample) {
    return ph_luminance(max(giSample.radiance, vec3(0.0f))) > 1e-6f;
}

bool RTXDI_IsValidGIReservoir(RTXDI_GIReservoir reservoir) {
    return reservoir.samples > 0.0f
        && reservoir.weight_sum > 0.0f
        && gi_sample_is_valid(reservoir.selected);
}

vec3 gi_surface_albedo(RAB_Surface surface) {
    return clamp(surface.material.diffuseAlbedo, vec3(0.0f), vec3(1.0f));
}

float gi_surface_roughness(RAB_Surface surface) {
    return clamp(surface.material.roughness, 0.03f, 1.0f);
}

float gi_surface_metalness(RAB_Surface surface) {
    vec3 diffuseAlbedo = gi_surface_albedo(surface);
    vec3 denominator = max(diffuseAlbedo - vec3(0.04f), vec3(1e-4f));
    vec3 metallic = clamp((surface.material.specularF0 - vec3(0.04f)) / denominator, vec3(0.0f), vec3(1.0f));
    return clamp(ph_luminance(metallic), 0.0f, 1.0f);
}

vec3 gi_surface_f0(RAB_Surface surface) {
    return clamp(surface.material.specularF0, vec3(0.0f), vec3(1.0f));
}

vec3 gi_fresnel_schlick(float cosTheta, vec3 f0) {
    return f0 + (vec3(1.0f) - f0) * pow(1.0f - clamp(cosTheta, 0.0f, 1.0f), 5.0f);
}

float gi_surface_diffuse_probability(RAB_Surface surface) {
    return clamp(surface.diffuseProbability, 0.0f, 1.0f);
}

float gi_distribution_ggx(float nDotH, float roughness) {
    float clampedRoughness = max(roughness, 0.03f);
    float a = clampedRoughness * clampedRoughness;  // alpha = roughness^2
    float a2 = a * a;                                // alpha^2 = roughness?
    float denom = nDotH * nDotH * (a2 - 1.0f) + 1.0f;
    return a2 / max(lt_gi_pi * denom * denom, 1e-6f);
}

float gi_geometry_schlick_ggx(float nDotX, float roughness) {
    float a = max(roughness, 0.03f) * max(roughness, 0.03f);  // alpha = roughness^2, clamped
    float k = a * 0.5f;                                        // k = alpha/2 (analytic Smith-GGX)
    return nDotX / max(nDotX * (1.0f - k) + k, 1e-6f);
}

float gi_geometry_smith(float nDotV, float nDotL, float roughness) {
    return gi_geometry_schlick_ggx(nDotV, roughness) * gi_geometry_schlick_ggx(nDotL, roughness);
}

float gi_specular_pdf(vec3 shadingNormal, vec3 viewDir, vec3 lightDir, float roughness) {
    vec3 halfVector = normalize(viewDir + lightDir);
    float nDotH = max(dot(shadingNormal, halfVector), 0.0f);
    float vDotH = max(dot(viewDir, halfVector), 0.0f);
    if (nDotH <= 0.0f || vDotH <= 0.0f) {
        return 0.0f;
    }

    return gi_distribution_ggx(nDotH, roughness) * nDotH / max(4.0f * vDotH, 1e-6f);
}

SplitBrdf EvaluateBrdf(RAB_Surface surface, vec3 samplePosition, float roughnessValue) {
    SplitBrdf brdf = SplitBrdf(0.0f, vec3(0.0f));

    vec3 toSample = samplePosition - lt_surface_rt_pos(surface);
    float distanceSq = dot(toSample, toSample);
    if (distanceSq == 0.0f) {
        return brdf;
    }

    vec3 lightDir = toSample * inversesqrt(distanceSq);

    // RTXDI: geometric normal hemisphere test (RAB_Surface.hlsli:230)
    if (dot(surface.geoNormal, lightDir) <= 0.0f) {
        return brdf;
    }

    vec3 normalValue = surface.normal;
    vec3 viewDir = surface.viewDir;
    float nDotL = max(dot(normalValue, lightDir), 0.0f);
    if (nDotL <= 0.0f) {
        return brdf;
    }
    float nDotV = max(dot(normalValue, viewDir), 1e-5f);

    vec3 halfVector = normalize(viewDir + lightDir);
    float nDotH = max(dot(normalValue, halfVector), 0.0f);
    float vDotH = max(dot(viewDir, halfVector), 0.0f);
    vec3 fresnel = gi_fresnel_schlick(vDotH, gi_surface_f0(surface));
    float distribution = gi_distribution_ggx(nDotH, roughnessValue);
    float geometry = gi_geometry_smith(nDotV, nDotL, roughnessValue);

    brdf.demodulatedDiffuse = nDotL / lt_gi_pi;
    // RTXDI: zero specular for delta surfaces (roughness < kMinRoughness = 0.03)
    if (roughnessValue < 0.03f) {
        brdf.specular = vec3(0.0f);
    } else {
        brdf.specular = distribution * geometry * fresnel / max(4.0f * nDotV, 1e-4f);
    }
    return brdf;
}

float gi_brdf_sample_pdf(RAB_Surface surface, vec3 sampleDir) {
    float nDotL = max(dot(surface.normal, sampleDir), 0.0f);
    if (nDotL <= 0.0f) {
        return 0.0f;
    }

    float diffuseProbability = gi_surface_diffuse_probability(surface);
    float diffusePdf = nDotL / lt_gi_pi;
    float specularPdf = gi_specular_pdf(
        surface.normal,
        surface.viewDir,
        sampleDir,
        gi_surface_roughness(surface)
    );
    return mix(specularPdf, diffusePdf, diffuseProbability);
}

vec3 gi_evaluate_reflected_integrand(RAB_Surface surface, RTXDI_GISample giSample) {
    SplitBrdf brdf = EvaluateBrdf(surface, giSample.position, gi_surface_roughness(surface));
    return giSample.radiance * (brdf.demodulatedDiffuse * gi_surface_albedo(surface) + brdf.specular);
}

vec3 RAB_GetReflectedBrdfRadiance(RAB_Surface surface, RTXDI_GISample giSample) {
    return max(giSample.radiance, vec3(0.0f));
}

vec3 gi_clamp_secondary_radiance(vec3 radiance) {
    radiance = max(radiance, vec3(0.0f));
    float indirectLuminance = ph_luminance(radiance);
    if (indirectLuminance > 10.0f) {
        radiance *= 10.0f / indirectLuminance;
    }
    return radiance;
}

bool gi_project_secondary_surface(RAB_Surface secondarySurface, out ivec2 secondaryPixelPosition, out float secondaryViewDepth) {
    secondaryPixelPosition = ivec2(0);
    secondaryViewDepth = 0.0f;

    vec4 secondaryClipPosition = modelview_projection * vec4(secondarySurface.worldPos, 1.0f);
    if (!ph_is_valid_clip_projection(secondaryClipPosition)) {
        return false;
    }

    secondaryClipPosition.xyz /= secondaryClipPosition.w;
    if (!all(lessThan(abs(secondaryClipPosition.xy), vec2(1.0f))) || secondaryClipPosition.w <= 0.0f) {
        return false;
    }

    secondaryPixelPosition = ivec2((secondaryClipPosition.xy * 0.5f + 0.5f) * vec2(viewWidth, viewHeight));
    secondaryViewDepth = secondaryClipPosition.w;
    return lt_is_viewport_uv_in_bounds(secondaryPixelPosition);
}

bool RAB_ValidateGISampleWithJacobian(inout float jacobian) {
    if (jacobian > 10.0f || jacobian < (1.0f / 10.0f)) {
        return false;
    }

    jacobian = clamp(jacobian, 1.0f / 3.0f, 3.0f);
    return true;
}

float RTXDI_GICalculateJacobian(RAB_Surface currentSurface, RAB_Surface sourceSurface, RTXDI_GISample giSample) {
    if (gi_is_skylight_sample_position(giSample.position, currentSurface.worldPos)
        || gi_is_skylight_sample_position(giSample.position, sourceSurface.worldPos)) {
        return 1.0f;
    }

    vec3 vecNew = lt_surface_rt_pos(currentSurface) - giSample.position;
    vec3 vecOriginal = lt_surface_rt_pos(sourceSurface) - giSample.position;

    float newDistanceSq = dot(vecNew, vecNew);
    float originalDistanceSq = dot(vecOriginal, vecOriginal);

    float newCosine = clamp(dot(giSample.normal, vecNew * inversesqrt(max(newDistanceSq, 1e-30f))), 0.0f, 1.0f);
    float originalCosine = clamp(dot(giSample.normal, vecOriginal * inversesqrt(max(originalDistanceSq, 1e-30f))), 0.0f, 1.0f);

    float jacobian = (newCosine * originalDistanceSq) / (originalCosine * newDistanceSq);

    if (isinf(jacobian) || isnan(jacobian)) {
        jacobian = 0.0f;
    }

    return RAB_ValidateGISampleWithJacobian(jacobian) ? jacobian : 0.0f;
}

float RAB_GetGISampleTargetPdfForSurface(RAB_Surface surface, RTXDI_GISample giSample) {
    return ph_luminance(RAB_GetReflectedBrdfRadiance(surface, giSample));
}

RTXDI_GIReservoir RTXDI_MakeGIReservoir(RTXDI_GISample giSample, float samplePdf) {
    RTXDI_GIReservoir reservoir;
    reservoir.selected = giSample;
    reservoir.weight_sum = samplePdf > 0.0f ? 1.0f / samplePdf : 0.0f;
    reservoir.samples = 1.0f;
    reservoir.age = 0.0f;
    reservoir.miscData = 0u;
    return reservoir;
}

bool RTXDI_CombineGIReservoirs(inout RTXDI_GIReservoir reservoir, RTXDI_GIReservoir newReservoir, float randomValue, float targetPdf) {
    float risWeight = targetPdf * newReservoir.weight_sum * newReservoir.samples;

    reservoir.samples += newReservoir.samples;
    reservoir.weight_sum += risWeight;

    bool selectSample = (randomValue * reservoir.weight_sum <= risWeight);
    if (selectSample) {
        reservoir.selected = newReservoir.selected;
        reservoir.age = newReservoir.age;
        reservoir.miscData = newReservoir.miscData;
    }

    return selectSample;
}

void RTXDI_FinalizeGIResampling(inout RTXDI_GIReservoir reservoir, float normalizationNumerator, float normalizationDenominator) {
    reservoir.weight_sum = (normalizationDenominator == 0.0f) ? 0.0f : (reservoir.weight_sum * normalizationNumerator) / normalizationDenominator;
}

struct RTXDI_PackedGIReservoir {
    vec3 position;
    uint packedNormal;
    uint packedMiscDataAgeM;
    float weight;
    uint packedRadiance;
    uint unused;
};

uint gi_pack_snorm_2x16(vec2 value) {
    return packSnorm2x16(value);
}

vec2 gi_unpack_snorm_2x16(uint packedValue) {
    return unpackSnorm2x16(packedValue);
}

vec2 gi_normalized_vector_to_octahedral_mapping(vec3 normalValue) {
    vec3 normalizedNormal = normalize(normalValue + vec3(1e-8f));
    vec2 projected = normalizedNormal.xy / (abs(normalizedNormal.x) + abs(normalizedNormal.y) + abs(normalizedNormal.z));
    if (normalizedNormal.z < 0.0f) {
        projected = vec2(
            (1.0f - abs(projected.y)) * (projected.x >= 0.0f ? 1.0f : -1.0f),
            (1.0f - abs(projected.x)) * (projected.y >= 0.0f ? 1.0f : -1.0f)
        );
    }
    return projected;
}

vec3 gi_octahedral_mapping_to_normalized_vector(vec2 packedNormal) {
    vec3 normalValue = vec3(packedNormal.xy, 1.0f - abs(packedNormal.x) - abs(packedNormal.y));
    if (normalValue.z < 0.0f) {
        normalValue.xy = vec2(
            (1.0f - abs(normalValue.y)) * (normalValue.x >= 0.0f ? 1.0f : -1.0f),
            (1.0f - abs(normalValue.x)) * (normalValue.y >= 0.0f ? 1.0f : -1.0f)
        );
    }
    return normalize(normalValue);
}

uint gi_encode_normal(vec3 normalValue) {
    return gi_pack_snorm_2x16(gi_normalized_vector_to_octahedral_mapping(normalValue));
}

vec3 gi_decode_normal(uint packedNormal) {
    return gi_octahedral_mapping_to_normalized_vector(gi_unpack_snorm_2x16(packedNormal));
}

uint gi_encode_radiance(vec3 radiance) {
    vec3 XYZ = max(radiance, vec3(0.0f)) * mat3(
        0.4123907992659595, 0.3575843393838780, 0.1804807884018343,
        0.2126390058715104, 0.7151686787677559, 0.0721923153607337,
        0.0193308187155918, 0.1191947797946259, 0.9505321522496608
    );

    float logY = 409.6f * (log2(XYZ.y) + 20.0f);
    uint Le = uint(clamp(logY, 0.0f, 16383.0f));
    if (Le == 0u) {
        return 0u;
    }

    float invDenom = 1.0f / (-2.0f * XYZ.x + 12.0f * XYZ.y + 3.0f * (XYZ.x + XYZ.y + XYZ.z));
    vec2 uv = vec2(4.0f, 9.0f) * XYZ.xy * invDenom;
    uvec2 uve = uvec2(clamp(820.0f * uv, vec2(0.0f), vec2(511.0f)));

    return (Le << 18u) | (uve.x << 9u) | uve.y;
}

vec3 gi_decode_radiance(uint packedColor) {
    uint Le = packedColor >> 18u;
    if (Le == 0u) {
        return vec3(0.0f);
    }

    float logY = (float(Le) + 0.5f) / 409.6f - 20.0f;
    float Y = pow(2.0f, logY);

    uvec2 uve = uvec2(packedColor >> 9u, packedColor) & 0x1ffu;
    vec2 uv = (vec2(uve) + 0.5f) / 820.0f;

    float invDenom = 1.0f / (6.0f * uv.x - 16.0f * uv.y + 12.0f);
    vec2 xy = vec2(9.0f, 4.0f) * uv * invDenom;

    float s = Y / xy.y;
    vec3 XYZ = vec3(s * xy.x, Y, s * (1.0f - xy.x - xy.y));
    mat3 xyzToRgb = mat3(
        3.240969941904522, -1.537383177570094, -0.4986107602930032,
        -0.9692436362808803, 1.875967501507721, 0.04155505740717569,
        0.05563007969699373, -0.2039769588889765, 1.056971514242878
    );
    return max(XYZ * xyzToRgb, vec3(0.0f));
}

const uint gi_packed_reservoir_m_shift = 0u;
const uint gi_packed_reservoir_max_m = 0xffu;
const uint gi_packed_reservoir_age_shift = 8u;
const uint gi_packed_reservoir_max_age = 0xffu;
const uint gi_packed_reservoir_misc_data_mask = 0xffff0000u;

RTXDI_PackedGIReservoir gi_pack_reservoir(RTXDI_GIReservoir reservoir, uint miscData) {
    RTXDI_PackedGIReservoir packedReservoir;
    packedReservoir.position = reservoir.selected.position;
    packedReservoir.packedNormal = gi_encode_normal(reservoir.selected.normal);
    packedReservoir.packedMiscDataAgeM = ((miscData & gi_packed_reservoir_misc_data_mask)
        | (min(uint(max(reservoir.age, 0.0f)), gi_packed_reservoir_max_age) << gi_packed_reservoir_age_shift)
        | (min(uint(max(reservoir.samples, 0.0f)), gi_packed_reservoir_max_m) << gi_packed_reservoir_m_shift));
    packedReservoir.weight = reservoir.weight_sum;
    packedReservoir.packedRadiance = gi_encode_radiance(reservoir.selected.radiance);
    packedReservoir.unused = 0u;
    return packedReservoir;
}

RTXDI_GIReservoir gi_unpack_reservoir(RTXDI_PackedGIReservoir packedData) {
    RTXDI_GIReservoir reservoir = RTXDI_EmptyGIReservoir();
    reservoir.selected.position = packedData.position;
    reservoir.selected.normal = gi_decode_normal(packedData.packedNormal);
    reservoir.selected.radiance = gi_decode_radiance(packedData.packedRadiance);
    reservoir.weight_sum = packedData.weight;
    reservoir.samples = float((packedData.packedMiscDataAgeM >> gi_packed_reservoir_m_shift) & gi_packed_reservoir_max_m);
    reservoir.age = float((packedData.packedMiscDataAgeM >> gi_packed_reservoir_age_shift) & gi_packed_reservoir_max_age);
    reservoir.miscData = packedData.packedMiscDataAgeM & gi_packed_reservoir_misc_data_mask;
    return reservoir;
}

struct RTXDI_GIReservoirStore {
    vec4 positionData;
    vec4 normalData;
    vec4 radianceData;
    vec4 metaData;
};

RTXDI_GIReservoirStore gi_make_invalid_reservoir_store() {
    RTXDI_GIReservoirStore store;
    store.positionData = vec4(0.0f);
    store.normalData = vec4(0.0f);
    store.radianceData = vec4(0.0f);
    store.metaData = vec4(0.0f);
    return store;
}

RTXDI_GIReservoirStore gi_make_reservoir_store(RTXDI_GIReservoir reservoir) {
    RTXDI_PackedGIReservoir packedReservoir = gi_pack_reservoir(reservoir, reservoir.miscData);
    RTXDI_GIReservoirStore store;
    store.positionData = vec4(packedReservoir.position, uintBitsToFloat(packedReservoir.packedNormal));
    store.normalData = vec4(
        uintBitsToFloat(packedReservoir.packedMiscDataAgeM),
        packedReservoir.weight,
        uintBitsToFloat(packedReservoir.packedRadiance),
        uintBitsToFloat(packedReservoir.unused)
    );
    store.radianceData = vec4(0.0f);
    store.metaData = vec4(0.0f);
    return store;
}

RTXDI_GIReservoirStore gi_make_initial_reservoir_store(RTXDI_GIReservoir reservoir) {
    // The reference InitialCandidates pass writes reservoir state only -- no side-channel radiance payload.
    // Final-MIS consumers must reconstruct initial radiance from the selected sample, not from a dedicated texture.
    return gi_make_reservoir_store(reservoir);
}

RTXDI_GIReservoirStore gi_make_reservoir_store_from_index(int bufferIndex, ivec2 uv) {
    return gi_make_reservoir_store(RTXDI_LoadGIReservoir(bufferIndex, uv));
}

void gi_store_invalid(out vec4 positionData, out vec4 normalData, out vec4 radianceData, out vec4 metaData) { // photonics-specific texture helper
    RTXDI_GIReservoirStore store = gi_make_invalid_reservoir_store();
    positionData = store.positionData;
    normalData = store.normalData;
    radianceData = store.radianceData;
    metaData = store.metaData;
}

void RTXDI_StoreGIReservoir(RTXDI_GIReservoir reservoir, out vec4 positionData, out vec4 normalData, out vec4 radianceData, out vec4 metaData) {
    RTXDI_GIReservoirStore store = gi_make_reservoir_store(reservoir);
    positionData = store.positionData;
    normalData = store.normalData;
    radianceData = store.radianceData;
    metaData = store.metaData;
}

uniform float ph_restir_indirect_boiling_filter_strength;
uniform float ph_restir_gi_use_boiling_filter;
uniform float ph_restir_gi_temporal_splatting_active;
uniform float ph_restir_gi_initial_sample_count;
uniform float ph_restir_gi_temporal_max_splats;
uniform float ph_restir_gi_spatial_sample_count;
uniform float ph_restir_gi_spatial_bias_mode;

const int gi_buffer_index_initial = 0;
const int gi_buffer_index_spatial = 1;

const int gi_bias_correction_mode_off = 0;
const int gi_bias_correction_mode_basic = 1;
const int gi_bias_correction_mode_ray_traced = 3;
const int gi_default_bias_correction_mode = gi_bias_correction_mode_off;
const float gi_default_spatial_depth_threshold = 0.1f;
const float gi_default_spatial_normal_threshold = 0.6f;
const float gi_default_spatial_sampling_radius = 32.0f;
const float gi_default_boiling_filter_strength = 0.0f;

int gi_runtime_bias_correction_mode(float configuredMode) {
    if (configuredMode < -0.5f) {
        return gi_bias_correction_mode_off;
    }
    if (configuredMode < 0.5f) {
        return gi_default_bias_correction_mode;
    }

    int resolvedMode = int(round(configuredMode));
    if (resolvedMode == gi_bias_correction_mode_basic || resolvedMode == gi_bias_correction_mode_ray_traced) {
        return resolvedMode;
    }
    return gi_default_bias_correction_mode;
}


int gi_runtime_spatial_sample_count() {
    return clamp(int(round(ph_restir_gi_spatial_sample_count)), 0, 8);
}

int gi_runtime_initial_sample_count() {
    return clamp(int(round(ph_restir_gi_initial_sample_count)), 1, 8);
}

int gi_runtime_temporal_max_splats() {
    return clamp(int(round(ph_restir_gi_temporal_max_splats)), 1, 32);
}

float gi_runtime_spatial_radius() {
    return ph_restir_spatial_radius > 0.0f ? ph_restir_spatial_radius : gi_default_spatial_sampling_radius;
}

float gi_runtime_spatial_depth_threshold() {
    return ph_restir_spatial_depth_threshold > 0.0f ? ph_restir_spatial_depth_threshold : gi_default_spatial_depth_threshold;
}

float gi_runtime_spatial_normal_threshold() {
    return ph_restir_spatial_normal_threshold > 0.0f ? ph_restir_spatial_normal_threshold : gi_default_spatial_normal_threshold;
}

float gi_runtime_boiling_filter_strength() {
    return ph_restir_indirect_boiling_filter_strength > 0.0f ? ph_restir_indirect_boiling_filter_strength : gi_default_boiling_filter_strength;
}


RTXDI_GIReservoir RTXDI_LoadGIReservoir(int bufferIndex, ivec2 uv) {
    if (bufferIndex == gi_buffer_index_initial) {
        return gi_unpack_reservoir(RTXDI_PackedGIReservoir(
            texelFetch(radiosity_indirect_initial_position, uv, 0).xyz,
            floatBitsToUint(texelFetch(radiosity_indirect_initial_position, uv, 0).w),
            floatBitsToUint(texelFetch(radiosity_indirect_initial_normal, uv, 0).x),
            texelFetch(radiosity_indirect_initial_normal, uv, 0).y,
            floatBitsToUint(texelFetch(radiosity_indirect_initial_normal, uv, 0).z),
            floatBitsToUint(texelFetch(radiosity_indirect_initial_normal, uv, 0).w)
        ));
    }
    return gi_unpack_reservoir(RTXDI_PackedGIReservoir(
        texelFetch(radiosity_indirect_reservoir_position, uv, 0).xyz,
        floatBitsToUint(texelFetch(radiosity_indirect_reservoir_position, uv, 0).w),
        floatBitsToUint(texelFetch(radiosity_indirect_reservoir_normal, uv, 0).x),
        texelFetch(radiosity_indirect_reservoir_normal, uv, 0).y,
        floatBitsToUint(texelFetch(radiosity_indirect_reservoir_normal, uv, 0).z),
        floatBitsToUint(texelFetch(radiosity_indirect_reservoir_normal, uv, 0).w)
    ));
}

RTXDI_GIReservoir RTXDI_LoadGIReservoir(int bufferIndex, ivec2 reservoirPos, int activeCheckerboardField) {
    return RTXDI_LoadGIReservoir(bufferIndex, reservoirPos);
}

RTXDI_GIReservoir RTXDI_LoadPreviousGIReservoir(ivec2 uv) {
    return gi_unpack_reservoir(RTXDI_PackedGIReservoir(
        texelFetch(prev_radiosity_indirect_reservoir_position, uv, 0).xyz,
        floatBitsToUint(texelFetch(prev_radiosity_indirect_reservoir_position, uv, 0).w),
        floatBitsToUint(texelFetch(prev_radiosity_indirect_reservoir_normal, uv, 0).x),
        texelFetch(prev_radiosity_indirect_reservoir_normal, uv, 0).y,
        floatBitsToUint(texelFetch(prev_radiosity_indirect_reservoir_normal, uv, 0).z),
        floatBitsToUint(texelFetch(prev_radiosity_indirect_reservoir_normal, uv, 0).w)
    ));
}

RTXDI_GIReservoir RTXDI_LoadPreviousGIReservoir(ivec2 reservoirPos, int activeCheckerboardField) {
    return RTXDI_LoadPreviousGIReservoir(reservoirPos);
}

RTXDI_GIReservoir RTXDI_LoadInitialGIReservoir(ivec2 uv) {
    // Parity with reference: the initial stage's selected sample (position/normal/radiance) and M come directly
    // from the reservoir it wrote. No secondary radiance texture is consulted.
    return RTXDI_LoadGIReservoir(gi_buffer_index_initial, uv);
}

RTXDI_GIReservoir RTXDI_LoadCanonicalGIReservoir(ivec2 uv, int activeCheckerboardField) {
    if (ph_restir_gi_use_boiling_filter >= 0.5f) {
        return RTXDI_LoadGIReservoir(gi_buffer_index_spatial, uv, activeCheckerboardField);
    }
    return RTXDI_LoadInitialGIReservoir(uv);
}

RTXDI_GIReservoir RTXDI_LoadCurrentFrameGIReservoir(ivec2 uv, int activeCheckerboardField) {
    if (ph_restir_gi_temporal_splatting_active >= 0.5f || ph_restir_gi_use_boiling_filter >= 0.5f) {
        return RTXDI_LoadGIReservoir(gi_buffer_index_spatial, uv, activeCheckerboardField);
    }
    return RTXDI_LoadInitialGIReservoir(uv);
}

bool RAB_GetConservativeVisibility(RAB_Surface surface, vec3 samplePosition) {
    vec3 rayOrigin;
    vec3 rayDirection;
    float traceMinDistance;
    float traceMaxDistance;
    if (!lt_setup_visibility_ray(surface, samplePosition, 0.001f, rayOrigin, rayDirection, traceMinDistance, traceMaxDistance)) {
        return false;
    }

    ray.origin = rayOrigin;
    ray.direction = rayDirection;
    ray_target = ivec3(-9999);
    ray_ignore_block_id = -1;
    ray_min_trace_distance = traceMinDistance;
    ray_max_trace_distance = traceMaxDistance;
    trace_ray(ray, true);
    ray_target = ivec3(-9999);
    ray_ignore_block_id = -1;
    ray_min_trace_distance = 0.0f;
    ray_max_trace_distance = -1.0f;
    return lt_visibility_trace_is_unoccluded();
}

bool gi_shade_secondary_surface(
    RAB_Surface currentSurface,
    RAB_Surface secondarySurface,
    inout RTXDI_RandomSamplerState rng,
    inout vec3 shadedRadiance
) {
    ivec2 secondaryPixelPosition = ivec2(0);
    float secondaryViewDepth = 0.0f;
    if (gi_project_secondary_surface(secondarySurface, secondaryPixelPosition, secondaryViewDepth)) {
        RAB_Surface visibleSecondarySurface = lt_load_surface(secondaryPixelPosition);
        if (lt_surface_matches(secondarySurface, visibleSecondarySurface, 0.1f, gi_runtime_spatial_normal_threshold())
            && lt_materials_similar(secondarySurface, visibleSecondarySurface)) {
            vec4 directDiffuseData = texelFetch(stage_radiosity_direct, secondaryPixelPosition, 0);
            vec4 directSpecularData = texelFetch(stage_radiosity_direct_specular, secondaryPixelPosition, 0);
            vec3 directDiffuse = nrd_safe_remodulate(
                nrd_unpack_direct_signal(directDiffuseData).radiance,
                max(secondarySurface.material.diffuseAlbedo, vec3(NRD_MATERIAL_FACTOR_MIN_SCALE))
            );
            vec3 directSpecular = nrd_safe_remodulate(
                nrd_unpack_direct_signal(directSpecularData).radiance,
                nrd_compute_specular_demodulation(secondarySurface.material.diffuseAlbedo, gi_surface_metalness(secondarySurface))
            );
            shadedRadiance += max(directDiffuse + directSpecular, vec3(0.0f));
        }
    }

    shadedRadiance = gi_clamp_secondary_radiance(shadedRadiance);
    return ph_luminance(shadedRadiance) > 1e-6f;
}

// -----------------------------------------------------------------------------
// Initial-candidate generation -- reference parity layer
//
// Reference: InitialCandidates.cs.slang
//   tracePath -> addCandidateReservoir with MIS weight 1/SamplesPerPixel
//   Handles primary miss by emitting a primary-miss candidate reservoir.
//
// Photonics GI parity port:
//   gi_generate_primary_miss_candidate(...) synthesizes the primary-miss
//     candidate used when the primary surface is invalid (parity with
//     PathTracer::handlePrimaryMiss in the reference).
//   gi_trace_initial_candidate(...) is a single candidate trace returning a
//     GI-reservoir-shaped record plus its source pdf.
//   gi_add_initial_candidate(...) merges one candidate into the running
//     initial reservoir with MIS weight 1/SamplesPerPixel, mirroring
//     PathReservoir::add in the reference.
//
// Note: the candidate is communicated by flat out-parameters instead of a
// struct containing RTXDI_GISample, because Iris's GLSL transformer parser
// refuses structs whose fields are other user-defined struct types in this
// translation unit.
// -----------------------------------------------------------------------------

// valid/isSkylight are packed into a single uint: bit 0 = valid, bit 1 = skylight.
const uint GI_CANDIDATE_FLAG_VALID     = 0x1u;
const uint GI_CANDIDATE_FLAG_SKYLIGHT  = 0x2u;

void gi_generate_primary_miss_candidate(
    ivec2 pixelPosition,
    vec3 cameraWorldPos,
    vec3 primaryRayDir,
    out RTXDI_GISample outSample,
    out float outSourcePdf,
    out uint outFlags
) {
    outSample = gi_null_sample();
    outSourcePdf = 0.0f;
    outFlags = 0u;

    vec3 skyRadiance = max(get_sky_color(pixelPosition, cameraWorldPos, primaryRayDir), vec3(0.0f));
    if (ph_luminance(skyRadiance) <= 1e-6f) {
        skyRadiance = max(indirect_light_color, vec3(0.0f));
    }
    skyRadiance = gi_clamp_secondary_radiance(skyRadiance);
    if (ph_luminance(skyRadiance) <= 1e-6f) {
        return;
    }

    outSample.position = cameraWorldPos + primaryRayDir * gi_skylight_distance();
    outSample.normal = -primaryRayDir;
    outSample.radiance = skyRadiance;
    // A primary-miss sample has unit pdf in the camera ray hemisphere for the purpose of
    // matching the reference sampling weight; the reservoir absorbs the per-candidate
    // MIS weight 1/SamplesPerPixel in gi_add_initial_candidate.
    outSourcePdf = 1.0f;
    outFlags = GI_CANDIDATE_FLAG_VALID | GI_CANDIDATE_FLAG_SKYLIGHT;
}

void gi_trace_initial_candidate(
    RAB_Surface currentSurface,
    inout RTXDI_RandomSamplerState rng,
    ivec2 pixelPosition,
    out RTXDI_GISample outSample,
    out float outSourcePdf,
    out uint outFlags
) {
    outSample = gi_null_sample();
    outSourcePdf = 0.0f;
    outFlags = 0u;

    vec3 sampleDir = vec3(0.0f);
    if (!RAB_SurfaceImportanceSampleBrdf(currentSurface, rng, sampleDir)) {
        return;
    }

    float samplePdf = RAB_SurfaceEvaluateBrdfPdf(currentSurface, sampleDir);
    if (samplePdf <= 0.0f) {
        return;
    }

    const float brdfRayMinT = 0.001f;
    lightEmittance = vec3(0.0f);
    breakOnEmpty = true;
    ray.origin = lt_surface_rt_pos(currentSurface) + sampleDir * brdfRayMinT;
    ray.direction = sampleDir;
    trace_ray(ray, true);
    breakOnEmpty = false;

    vec3 secondaryThroughput = clamp(result_tint_color, vec3(0.0f), vec3(1.0f));
    bool hitSceneSurface = ray.result_hit && !ray_iteration_bound_reached;

    if (!hitSceneSurface) {
        vec3 skyRadiance = max(get_sky_color(pixelPosition, currentSurface.worldPos, sampleDir), vec3(0.0f));
        if (ph_luminance(skyRadiance) <= 1e-6f) {
            skyRadiance = max(indirect_light_color, vec3(0.0f));
        }
        skyRadiance *= secondaryThroughput;
        skyRadiance = gi_clamp_secondary_radiance(skyRadiance);
        if (ph_luminance(skyRadiance) <= 1e-6f) {
            return;
        }

        RTXDI_GISample incidentSample = RTXDI_GISample(
            currentSurface.worldPos + sampleDir * gi_skylight_distance(),
            -sampleDir,
            skyRadiance
        );
        vec3 reflectedIntegrand = gi_evaluate_reflected_integrand(currentSurface, incidentSample);
        if (ph_luminance(reflectedIntegrand) <= 1e-6f) {
            return;
        }

        outSample.position = incidentSample.position;
        outSample.normal = incidentSample.normal;
        outSample.radiance = reflectedIntegrand;
        outSourcePdf = samplePdf;
        outFlags = GI_CANDIDATE_FLAG_VALID | GI_CANDIDATE_FLAG_SKYLIGHT;
        return;
    }

    vec3 secondaryPos = ray.result_position;
    vec3 secondaryNormal = normalize(ray.result_normal);
    vec3 secondaryAlbedo = max(ray.result_color, vec3(0.0f));
    vec3 emissionRadiance = max(dot(lightEmittance, lightEmittance) > 0.0f ? lightEmittance : vec3(0.0f), vec3(0.0f));
    vec3 secondaryRadiance = emissionRadiance;
    RAB_Material secondaryMaterial = RAB_Material(
        clamp(secondaryAlbedo, vec3(0.0f), vec3(1.0f)),
        vec3(0.0f),
        1.0f,
        max(emissionRadiance, vec3(0.0f))
    );
    RAB_Surface secondarySurface = lt_make_surface(
        secondaryPos + world_offset,
        secondaryNormal,
        secondaryNormal,
        secondaryAlbedo,
        secondaryMaterial,
        currentSurface.worldPos,
        ph_linear_view_depth(modelview_projection, secondaryPos + world_offset)
    );

    if (!gi_shade_secondary_surface(currentSurface, secondarySurface, rng, secondaryRadiance)) {
        return;
    }

    RTXDI_GISample incidentSample = RTXDI_GISample(
        secondarySurface.worldPos,
        secondarySurface.normal,
        secondaryRadiance * secondaryThroughput
    );
    vec3 reflectedIntegrand = gi_evaluate_reflected_integrand(currentSurface, incidentSample);
    if (ph_luminance(reflectedIntegrand) <= 1e-6f) {
        return;
    }

    outSample.position = incidentSample.position;
    outSample.normal = incidentSample.normal;
    outSample.radiance = reflectedIntegrand;
    outSourcePdf = samplePdf;
    outFlags = GI_CANDIDATE_FLAG_VALID; // not skylight
}

// Reference parity: InitialCandidates::addCandidateReservoir
// Accumulates one IID candidate into the running initial reservoir with m_i = 1/SamplesPerPixel.
void gi_add_initial_candidate(
    inout RTXDI_GIReservoir reservoir,
    RTXDI_GISample candidateSample,
    float sourcePdf,
    uint flags,
    inout RTXDI_RandomSamplerState rng,
    int samplesPerPixel
) {
    if ((flags & GI_CANDIDATE_FLAG_VALID) == 0u || sourcePdf <= 0.0f) {
        reservoir.samples += 1.0f;
        return;
    }

    float candidateTargetPdf = ph_luminance(max(candidateSample.radiance, vec3(0.0f)));
    if (candidateTargetPdf <= 0.0f) {
        reservoir.samples += 1.0f;
        return;
    }

    float candidateWeight = candidateTargetPdf / sourcePdf;
    float misWeight = 1.0f / float(max(samplesPerPixel, 1));
    float risWeight = misWeight * candidateWeight;

    reservoir.samples += 1.0f;
    reservoir.weight_sum += risWeight;

    bool selectSample = (RTXDI_GetNextRandom(rng) * reservoir.weight_sum <= risWeight);
    if (selectSample) {
        reservoir.selected = candidateSample;
        reservoir.age = 0.0f;
        reservoir.miscData = ((flags & GI_CANDIDATE_FLAG_SKYLIGHT) != 0u) ? gi_misc_flag_skylight : 0u;
    }
}

void gi_finalize_initial_reservoir(inout RTXDI_GIReservoir reservoir) {
    float selectedTargetPdf = ph_luminance(max(reservoir.selected.radiance, vec3(0.0f)));
    if (reservoir.weight_sum <= 0.0f || selectedTargetPdf <= 0.0f) {
        reservoir = RTXDI_EmptyGIReservoir();
        return;
    }

    reservoir.weight_sum /= selectedTargetPdf;
    reservoir.samples = 1.0f;
}

RTXDI_GIReservoirStore gi_build_initial_reservoir_store(RAB_Surface currentSurface) {
    int samplesPerPixel = gi_runtime_initial_sample_count();

    ivec2 pixelPosition = lt_current_pixel_pos();
    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(
        uvec2(pixelPosition),
        uint(frameCounter),
        RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED
    );

    RTXDI_GIReservoir reservoir = RTXDI_EmptyGIReservoir();
    for (int i = 0; i < samplesPerPixel; i++) {
        RTXDI_GISample candidateSample;
        float candidateSourcePdf;
        uint candidateFlags;
        gi_trace_initial_candidate(currentSurface, rng, pixelPosition, candidateSample, candidateSourcePdf, candidateFlags);
        gi_add_initial_candidate(reservoir, candidateSample, candidateSourcePdf, candidateFlags, rng, samplesPerPixel);
    }

    gi_finalize_initial_reservoir(reservoir);
    return gi_make_initial_reservoir_store(reservoir);
}

// Reference parity: emits a primary-miss initial reservoir when the primary surface is invalid.
// Matches PathTracer::handlePrimaryMiss + InitialCandidates::addCandidateReservoir in the reference.
RTXDI_GIReservoirStore gi_build_primary_miss_initial_reservoir_store(vec3 cameraWorldPos, vec3 primaryRayDir) {
    int samplesPerPixel = gi_runtime_initial_sample_count();
    ivec2 pixelPosition = lt_current_pixel_pos();
    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(
        uvec2(pixelPosition),
        uint(frameCounter),
        RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED
    );

    RTXDI_GIReservoir reservoir = RTXDI_EmptyGIReservoir();
    for (int i = 0; i < samplesPerPixel; i++) {
        RTXDI_GISample candidateSample;
        float candidateSourcePdf;
        uint candidateFlags;
        gi_generate_primary_miss_candidate(pixelPosition, cameraWorldPos, primaryRayDir, candidateSample, candidateSourcePdf, candidateFlags);
        gi_add_initial_candidate(reservoir, candidateSample, candidateSourcePdf, candidateFlags, rng, samplesPerPixel);
    }

    gi_finalize_initial_reservoir(reservoir);
    return gi_make_initial_reservoir_store(reservoir);
}

bool gi_stream_contributor(
    inout RTXDI_GIReservoir mergedReservoir,
    RTXDI_GIReservoir candidateReservoir,
    RAB_Surface currentSurface,
    RAB_Surface sourceSurface,
    int contributorIndex,
    inout int selectedContributorIndex
) {
    if (!RTXDI_IsValidGIReservoir(candidateReservoir)) {
        return false;
    }

    float jacobian = RTXDI_GICalculateJacobian(currentSurface, sourceSurface, candidateReservoir.selected);
    if (jacobian <= 0.0f) {
        return false;
    }

    float targetPdfCurrent = RAB_GetGISampleTargetPdfForSurface(currentSurface, candidateReservoir.selected);
    if (targetPdfCurrent <= 0.0f) {
        return false;
    }

    bool selected = RTXDI_CombineGIReservoirs(
        mergedReservoir,
        candidateReservoir,
        rand_next_float(),
        targetPdfCurrent * jacobian
    );
    if (selected) {
        selectedContributorIndex = contributorIndex;
    }
    return true;
}

void gi_shade_reservoir(RAB_Surface currentSurface, RTXDI_GIReservoir reservoir, RTXDI_GIReservoir initialReservoir, out vec3 outDiffuse, out vec3 outSpecular) {
    outDiffuse = vec3(0.0f);
    outSpecular = vec3(0.0f);

    if (!RTXDI_IsValidGIReservoir(reservoir)) {
        return;
    }

    outDiffuse = max(reservoir.selected.radiance * reservoir.weight_sum, vec3(0.0f));
}

#endif
