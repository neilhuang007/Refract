#ifndef PHOTONICS_RESTIR_GI_BRIDGE_GLSL
#define PHOTONICS_RESTIR_GI_BRIDGE_GLSL

#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/nrd_common.glsl"

const float lt_indirect_max_history = 8.0f;
const float lt_indirect_max_age = 30.0f;
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

struct RTXDI_GIReservoir {
    RTXDI_GISample selected;
    float weight_sum;
    float samples;
    float age;
};

RTXDI_GISample gi_null_sample() {
    return RTXDI_GISample(vec3(0.0f), vec3(0.0f), vec3(0.0f));
}

RTXDI_GIReservoir RTXDI_EmptyGIReservoir() {
    return RTXDI_GIReservoir(gi_null_sample(), 0.0f, 0.0f, 0.0f);
}

bool gi_sample_is_valid(RTXDI_GISample giSample) {
    return true; // RTXDI has no sample-level validity; validity is reservoir.M != 0
}

bool RTXDI_IsValidGIReservoir(RTXDI_GIReservoir reservoir) {
    return reservoir.samples > 0.0f; // RTXDI: M != 0
}

vec3 gi_surface_albedo(DirectSurface surface) {
    return clamp(surface.albedo, vec3(0.04f), vec3(1.0f));
}

float gi_surface_roughness(DirectSurface surface) {
    return clamp(surface.material.x, 0.03f, 1.0f);
}

float gi_surface_metalness(DirectSurface surface) {
    return clamp(surface.material.y, 0.0f, 1.0f);
}

vec3 gi_surface_f0(DirectSurface surface) {
    return mix(vec3(0.04f), gi_surface_albedo(surface), gi_surface_metalness(surface));
}

vec3 gi_fresnel_schlick(float cosTheta, vec3 f0) {
    return f0 + (vec3(1.0f) - f0) * pow(1.0f - clamp(cosTheta, 0.0f, 1.0f), 5.0f);
}

float gi_surface_diffuse_probability(DirectSurface surface) {
    vec3 viewDir = normalize(rt_camera_position - surface.rtPos);
    float viewCosTheta = max(dot(viewDir, surface.shadingNormal), 0.0f);
    float diffuseWeight = ph_luminance(gi_surface_albedo(surface));
    float specularWeight = ph_luminance(gi_fresnel_schlick(viewCosTheta, gi_surface_f0(surface)));
    float weightSum = diffuseWeight + specularWeight;
    return weightSum < 1e-7f ? 1.0f : clamp(diffuseWeight / weightSum, 0.0f, 1.0f);
}

float gi_distribution_ggx(float nDotH, float roughness) {
    float clampedRoughness = max(roughness, 0.03f);
    float a = clampedRoughness * clampedRoughness;  // α = roughness²
    float a2 = a * a;                                // α² = roughness⁴
    float denom = nDotH * nDotH * (a2 - 1.0f) + 1.0f;
    return a2 / max(lt_gi_pi * denom * denom, 1e-6f);
}

float gi_geometry_schlick_ggx(float nDotX, float roughness) {
    float a = max(roughness, 0.03f) * max(roughness, 0.03f);  // α = roughness², clamped
    float k = a * 0.5f;                                        // k = α/2 (analytic Smith-GGX)
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

SplitBrdf EvaluateBrdf(DirectSurface surface, vec3 samplePosition, float roughnessValue) {
    SplitBrdf brdf = SplitBrdf(0.0f, vec3(0.0f));

    vec3 toSample = samplePosition - surface.rtPos;
    float distanceSq = dot(toSample, toSample);
    if (distanceSq <= 1e-6f) {
        return brdf;
    }

    vec3 lightDir = toSample * inversesqrt(distanceSq);
    vec3 normalValue = surface.shadingNormal;
    vec3 viewDir = normalize(rt_camera_position - surface.rtPos);
    float nDotL = max(dot(normalValue, lightDir), 0.0f);
    float nDotV = max(dot(normalValue, viewDir), 0.0f);
    if (nDotL <= 0.0f || nDotV <= 0.0f) {
        return brdf;
    }

    vec3 halfVector = normalize(viewDir + lightDir);
    float nDotH = max(dot(normalValue, halfVector), 0.0f);
    float vDotH = max(dot(viewDir, halfVector), 0.0f);
    vec3 fresnel = gi_fresnel_schlick(vDotH, gi_surface_f0(surface));
    float distribution = gi_distribution_ggx(nDotH, roughnessValue);
    float geometry = gi_geometry_smith(nDotV, nDotL, roughnessValue);

    brdf.demodulatedDiffuse = nDotL / lt_gi_pi;
    brdf.specular = distribution * geometry * fresnel / max(4.0f * nDotV, 1e-4f);
    return brdf;
}

float gi_brdf_sample_pdf(DirectSurface surface, vec3 sampleDir) {
    float nDotL = max(dot(surface.shadingNormal, sampleDir), 0.0f);
    if (nDotL <= 0.0f) {
        return 0.0f;
    }

    float diffuseProbability = gi_surface_diffuse_probability(surface);
    float diffusePdf = nDotL / lt_gi_pi;
    float specularPdf = gi_specular_pdf(
        surface.shadingNormal,
        normalize(rt_camera_position - surface.rtPos),
        sampleDir,
        gi_surface_roughness(surface)
    );
    return mix(specularPdf, diffusePdf, diffuseProbability);
}

vec3 RAB_GetReflectedBrdfRadiance(DirectSurface surface, RTXDI_GISample giSample) {
    SplitBrdf brdf = EvaluateBrdf(surface, giSample.position, gi_surface_roughness(surface));
    return giSample.radiance * (brdf.demodulatedDiffuse * gi_surface_albedo(surface) + brdf.specular);
}

float GetMISWeight(SplitBrdf roughBrdf, SplitBrdf trueBrdf, vec3 diffuseAlbedo) {
    vec3 combinedRoughBrdf = roughBrdf.demodulatedDiffuse * diffuseAlbedo + roughBrdf.specular;
    vec3 combinedTrueBrdf = trueBrdf.demodulatedDiffuse * diffuseAlbedo + trueBrdf.specular;

    combinedRoughBrdf = clamp(combinedRoughBrdf, vec3(1e-4f), vec3(lt_gi_max_brdf_value));
    combinedTrueBrdf = clamp(combinedTrueBrdf, vec3(0.0f), vec3(lt_gi_max_brdf_value));

    float initialWeight = clamp(
        ph_luminance(combinedTrueBrdf) / max(ph_luminance(combinedTrueBrdf + combinedRoughBrdf), 1e-6f),
        0.0f,
        1.0f
    );
    return initialWeight * initialWeight * initialWeight;
}

DirectSurface gi_load_stage_surface(ivec2 uv) {
    return lt_make_surface(
        texelFetch(stage_radiosity_position, uv, 0).xyz,
        texelFetch(stage_radiosity_normal, uv, 0).xyz,
        texelFetch(stage_radiosity_mapped_normal, uv, 0).xyz,
        texelFetch(stage_radiosity_albedo, uv, 0).rgb,
        texelFetch(stage_radiosity_material, uv, 0)
    );
}

bool gi_try_resolve_stage_surface(DirectSurface secondarySurface, out ivec2 stageUv, out DirectSurface stageSurface) {
    stageUv = ivec2(0);
    stageSurface = secondarySurface;

    vec2 projectedUv = ph_reprojectf(
        modelview_projection,
        secondarySurface.worldPos + secondarySurface.geometryNormal * 0.01f,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    );
    if (!lt_is_viewport_uv_in_bounds(projectedUv)) {
        return false;
    }

    stageUv = ivec2(round(projectedUv));
    stageSurface = gi_load_stage_surface(stageUv);
    return lt_surface_matches(secondarySurface, stageSurface, lt_depth_threshold, lt_surface_normal_threshold);
}

vec3 gi_secondary_view_dir(DirectSurface primarySurface, DirectSurface secondarySurface) {
    vec3 viewDir = primarySurface.rtPos - secondarySurface.rtPos;
    float viewLengthSq = dot(viewDir, viewDir);
    if (viewLengthSq <= 1e-6f) {
        return rt_camera_position - secondarySurface.rtPos;
    }
    return viewDir * inversesqrt(viewLengthSq);
}

bool gi_load_stage_direct_reservoir(ivec2 stageUv, DirectSurface stageSurface, out Reservoir stageReservoir) {
    stageReservoir = rtxdi_empty_reservoir();
    if (!lt_is_viewport_uv_in_bounds(stageUv)) {
        return false;
    }

    rtxdi_unpack_reservoir_at_surface(
        stageReservoir,
        texelFetch(radiosity_reservoirs, stageUv, 0),
        texelFetch(radiosity_reservoir_samples, stageUv, 0),
        texelFetch(radiosity_reservoir_meta, stageUv, 0),
        stageSurface,
        false
    );
    return rtxdi_is_valid_reservoir(stageReservoir)
        && !isnan(stageReservoir.weightSum)
        && !isnan(stageReservoir.targetPdf);
}

vec3 gi_stage_secondary_radiance(DirectSurface primarySurface, ivec2 stageUv, DirectSurface stageSurface) {
    vec3 directRadiance = vec3(0.0f);
    Reservoir stageReservoir = rtxdi_empty_reservoir();
    if (gi_load_stage_direct_reservoir(stageUv, stageSurface, stageReservoir)) {
        bool visible = true;
        LightSample stageLightSample = light_sample_new_at_position(
            load_light(stageReservoir.lightIndex), stageReservoir.storedPosition, stageSurface);
        if (rtxdi_has_reusable_visibility(stageReservoir)) {
            visible = rtxdi_is_visible(stageReservoir);
        } else {
#ifdef PH_LIGHTTREE_SOFT_SHADOWS
            light_sample_trace_hit_surface(stageLightSample, true, stageSurface);
#else
            light_sample_trace_hit_surface(stageLightSample, false, stageSurface);
#endif
            visible = ph_luminance(stageLightSample.color) > 1e-6f;
        }

        if (visible) {
            directRadiance = lt_shade_surface_light_sample_with_view(
                stageSurface,
                stageLightSample,
                gi_secondary_view_dir(primarySurface, stageSurface)
            ) * stageReservoir.weightSum;
        }
    } else {
        directRadiance = nrd_unpack_direct_signal(texelFetch(stage_radiosity_direct, stageUv, 0)).radiance;
    }

    vec3 stageHandheld = texelFetch(stage_radiosity_handheld, stageUv, 0).rgb;
    return ph_clamp_indirect_radiance(max(directRadiance + stageHandheld, vec3(0.0f)));
}

bool RAB_ValidateGISampleWithJacobian(inout float jacobian) {
    if (jacobian > 10.0f || jacobian < (1.0f / 10.0f)) {
        return false;
    }

    jacobian = clamp(jacobian, 1.0f / 3.0f, 3.0f);
    return true;
}

float RTXDI_GICalculateJacobian(DirectSurface currentSurface, DirectSurface sourceSurface, RTXDI_GISample giSample) {
    vec3 vecNew = currentSurface.rtPos - giSample.position;
    vec3 vecOriginal = sourceSurface.rtPos - giSample.position;

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

float RAB_GetGISampleTargetPdfForSurface(DirectSurface surface, RTXDI_GISample giSample) {
    return ph_luminance(RAB_GetReflectedBrdfRadiance(surface, giSample));
}

RTXDI_GIReservoir RTXDI_MakeGIReservoir(RTXDI_GISample giSample, float samplePdf) {
    RTXDI_GIReservoir reservoir;
    reservoir.selected = giSample;
    reservoir.weight_sum = samplePdf > 0.0f ? 1.0f / samplePdf : 0.0f;
    reservoir.samples = 1.0f;
    reservoir.age = 0.0f;
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
    }

    return selectSample;
}

void RTXDI_FinalizeGIResampling(inout RTXDI_GIReservoir reservoir, float normalizationNumerator, float normalizationDenominator) {
    reservoir.weight_sum = (normalizationDenominator == 0.0f) ? 0.0f : (reservoir.weight_sum * normalizationNumerator) / normalizationDenominator;
}

void gi_store_invalid(out vec4 positionData, out vec4 normalData, out vec4 radianceData, out vec4 metaData) { // photonics-specific texture helper
    positionData = vec4(0.0f);
    normalData = vec4(0.0f);
    radianceData = vec4(0.0f);
    metaData = vec4(0.0f);
}

void RTXDI_StoreGIReservoir(RTXDI_GIReservoir reservoir, out vec4 positionData, out vec4 normalData, out vec4 radianceData, out vec4 metaData) {
    positionData = vec4(reservoir.selected.position, min(reservoir.samples, 255.0f));
    normalData = vec4(reservoir.selected.normal, min(reservoir.age, 255.0f));
    radianceData = vec4(reservoir.selected.radiance, reservoir.weight_sum);
    metaData = vec4(0.0f);
}

RTXDI_GIReservoir RTXDI_LoadGIReservoir(
    sampler2D positionTexture,
    sampler2D normalTexture,
    sampler2D radianceTexture,
    sampler2D metaTexture,
    ivec2 uv
) {
    RTXDI_GIReservoir reservoir;
    vec4 positionData = texelFetch(positionTexture, uv, 0);
    vec4 normalData = texelFetch(normalTexture, uv, 0);
    vec4 radianceData = texelFetch(radianceTexture, uv, 0);

    reservoir.selected.position = positionData.xyz;
    reservoir.selected.normal = normalData.xyz;
    reservoir.selected.radiance = radianceData.xyz;
    reservoir.weight_sum = radianceData.w;
    reservoir.samples = positionData.w;
    reservoir.age = normalData.w;
    return reservoir;
}

RTXDI_GIReservoir RTXDI_LoadInitialGIReservoir(ivec2 uv) {
    return RTXDI_LoadGIReservoir(
        radiosity_indirect_initial_position,
        radiosity_indirect_initial_normal,
        radiosity_indirect_initial_radiance,
        radiosity_indirect_initial_meta,
        uv
    );
}

bool GetFinalVisibility(DirectSurface surface, RTXDI_GISample giSample) {
    vec3 toSample = giSample.position - surface.rtPos;
    float distance = length(toSample);
    if (distance <= 1e-5f) {
        return false;
    }

    ray.origin = lt_surface_ray_origin(surface.rtPos, surface.geometryNormal);
    ray.direction = toSample / distance;
    ray_target = ivec3(giSample.position);
    trace_ray(ray, true);
    return ray.result_hit && floor(giSample.position) == floor(ray.result_position);
}

bool gi_sample_requires_final_visibility(DirectSurface surface, RTXDI_GISample giSample) {
    return true;
}

bool gi_build_initial_sample(DirectSurface currentSurface, out RTXDI_GISample giSample, out float samplePdf) {
    giSample = gi_null_sample();
    samplePdf = 0.0f;

    vec3 viewDir = normalize(rt_camera_position - currentSurface.rtPos);

    lightEmittance = vec3(0.0f);
    breakOnEmpty = true;
    ray.origin = currentSurface.rtPos + 0.1f * currentSurface.geometryNormal;
    ray.direction = ph_sample_brdf_direction(
        currentSurface.shadingNormal,
        viewDir,
        gi_surface_albedo(currentSurface),
        gi_surface_roughness(currentSurface),
        gi_surface_metalness(currentSurface),
        tex_coord,
        frameCounter
    );
    trace_ray(ray, true);
    breakOnEmpty = false;

    samplePdf = gi_brdf_sample_pdf(currentSurface, ray.direction);
    if (samplePdf <= 0.0f) {
        return false;
    }

    if (!ray.result_hit && !ray_iteration_bound_reached) {
        giSample.position = currentSurface.rtPos + ray.direction * 256.0f;
        giSample.normal = -ray.direction;
        giSample.radiance = ph_clamp_indirect_radiance(indirect_light_color);
        return gi_sample_is_valid(giSample);
    }

    if (dot(lightEmittance, lightEmittance) > 0.0f) {
        giSample.position = ray.result_position;
        giSample.normal = normalize(ray.result_normal);
        giSample.radiance = ph_clamp_indirect_radiance(lightEmittance);
        return gi_sample_is_valid(giSample);
    }

    vec3 secondaryPos = ray.result_position;
    vec3 secondaryNormal = normalize(ray.result_normal);
    vec3 secondaryAlbedo = max(ray.result_color, vec3(0.0f));
    DirectSurface secondarySurface = lt_make_surface(
        secondaryPos + world_offset,
        secondaryNormal,
        secondaryNormal,
        secondaryAlbedo,
        vec4(1.0f, 0.0f, 0.0f, 0.0f)
    );

    ivec2 secondaryStageUv = ivec2(0);
    DirectSurface secondaryStageSurface = secondarySurface;
    if (gi_try_resolve_stage_surface(secondarySurface, secondaryStageUv, secondaryStageSurface)) {
        vec3 stageRadiance = gi_stage_secondary_radiance(currentSurface, secondaryStageUv, secondaryStageSurface);
        if (ph_luminance(stageRadiance) > 1e-6f) {
            giSample.position = secondaryStageSurface.rtPos;
            giSample.normal = normalize(secondaryStageSurface.shadingNormal);
            giSample.radiance = stageRadiance;
            return gi_sample_is_valid(giSample);
        }
    }

    Reservoir secondaryLightReservoir = rtxdi_empty_reservoir();
    rtxdi_sample_local_lights(secondaryLightReservoir, secondarySurface);
    if (!rtxdi_is_valid_reservoir(secondaryLightReservoir)) {
        return false;
    }

    LightSample secondaryLightSample = light_sample_new_at_position(
        load_light(secondaryLightReservoir.lightIndex), secondaryLightReservoir.storedPosition, secondarySurface);
#ifdef PH_LIGHTTREE_SOFT_SHADOWS
    light_sample_trace_hit_surface(secondaryLightSample, true, secondarySurface);
#else
    light_sample_trace_hit_surface(secondaryLightSample, false, secondarySurface);
#endif

    if (ph_luminance(secondaryLightSample.color) <= 1e-6f) {
        return false;
    }

    vec3 secondaryViewDir = gi_secondary_view_dir(currentSurface, secondarySurface);
    giSample.position = secondaryPos;
    giSample.normal = secondaryNormal;
    giSample.radiance = ph_clamp_indirect_radiance(
        lt_shade_surface_light_sample_with_view(
            secondarySurface,
            secondaryLightSample,
            secondaryViewDir
        ) * secondaryLightReservoir.weightSum
    );
    return gi_sample_is_valid(giSample);
}

RTXDI_GIReservoir gi_build_initial_reservoir(DirectSurface currentSurface) {
    RTXDI_GISample giSample = gi_null_sample();
    float samplePdf = 0.0f;
    if (!gi_build_initial_sample(currentSurface, giSample, samplePdf)) {
        return RTXDI_EmptyGIReservoir();
    }

    return RTXDI_MakeGIReservoir(giSample, samplePdf);
}

bool gi_stream_contributor(
    inout RTXDI_GIReservoir mergedReservoir,
    RTXDI_GIReservoir candidateReservoir,
    DirectSurface currentSurface,
    DirectSurface sourceSurface,
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

    candidateReservoir.weight_sum *= jacobian;
    bool selected = RTXDI_CombineGIReservoirs(
        mergedReservoir,
        candidateReservoir,
        rand_next_float(),
        targetPdfCurrent
    );
    if (selected) {
        selectedContributorIndex = contributorIndex;
    }
    return true;
}

void gi_shade_reservoir(DirectSurface currentSurface, RTXDI_GIReservoir reservoir, RTXDI_GIReservoir initialReservoir, out vec3 outDiffuse, out vec3 outSpecular) {
    outDiffuse = vec3(0.0f);
    outSpecular = vec3(0.0f);

    if (!RTXDI_IsValidGIReservoir(reservoir)) {
        return;
    }

    vec3 finalRadiance = reservoir.selected.radiance * reservoir.weight_sum;
    if (gi_sample_requires_final_visibility(currentSurface, reservoir.selected)
        && !GetFinalVisibility(currentSurface, reservoir.selected))
    {
        finalRadiance = vec3(0.0f);
    }

    SplitBrdf finalBrdf = EvaluateBrdf(currentSurface, reservoir.selected.position, gi_surface_roughness(currentSurface));

    if (RTXDI_IsValidGIReservoir(initialReservoir)) {
        vec3 initialRadiance = initialReservoir.selected.radiance * initialReservoir.weight_sum;
        SplitBrdf initialBrdf = EvaluateBrdf(currentSurface, initialReservoir.selected.position, gi_surface_roughness(currentSurface));
        float roughnessForMis = max(gi_surface_roughness(currentSurface), lt_gi_mis_roughness);
        SplitBrdf roughFinalBrdf = EvaluateBrdf(currentSurface, reservoir.selected.position, roughnessForMis);
        SplitBrdf roughInitialBrdf = EvaluateBrdf(currentSurface, initialReservoir.selected.position, roughnessForMis);
        float finalWeight = 1.0f - GetMISWeight(roughFinalBrdf, finalBrdf, gi_surface_albedo(currentSurface));
        float initialWeight = GetMISWeight(roughInitialBrdf, initialBrdf, gi_surface_albedo(currentSurface));

        outDiffuse = finalBrdf.demodulatedDiffuse * finalRadiance * finalWeight
                   + initialBrdf.demodulatedDiffuse * initialRadiance * initialWeight;
        outSpecular = finalBrdf.specular * finalRadiance * finalWeight
                    + initialBrdf.specular * initialRadiance * initialWeight;
    } else {
        outDiffuse = finalBrdf.demodulatedDiffuse * finalRadiance;
        outSpecular = finalBrdf.specular * finalRadiance;
    }

    // Demodulate specular by specularF0 (matching RTXDI FinalShading.hlsl:124)
    vec3 specF0 = gi_surface_f0(currentSurface);
    outSpecular = outSpecular / max(specF0, vec3(1e-4f));
}

#endif
