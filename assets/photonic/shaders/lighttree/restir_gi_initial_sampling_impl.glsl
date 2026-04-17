#ifndef PHOTONICS_RESTIR_GI_INITIAL_SAMPLING_IMPL_GLSL
#define PHOTONICS_RESTIR_GI_INITIAL_SAMPLING_IMPL_GLSL

// GI-facing implementation surface for the shared initial-sampling helper chain.
// This keeps the indirect pipeline independent from late implementation regions in
// reuse_bridge.glsl while preserving a single implementation owner for these symbols.

// RTXDI: RTXDI_ComputeInitialSamplingMisData (InitialSampling.hlsli:41-54)
// RTXDI does NOT guard numMisSamples against zero here — the early-exit in RTXDI_SampleLocalLights
// ensures numMisSamples > 0 before this is used in division.
// numMisSamples includes local + environment + BRDF sample counts (InitialSampling.hlsli line 45).
// Environment samples are included even when the environment stub returns M=0 so MIS weights
// remain consistent with the SDK reference.
RTXDI_InitialSamplingMisData RTXDI_ComputeInitialSamplingMisData(RTXDI_DIInitialSamplingParameters initialSamplingParams)
{
    RTXDI_InitialSamplingMisData result;
    result.numMisSamples = int(initialSamplingParams.numLocalLightSamples + initialSamplingParams.numEnvironmentSamples + initialSamplingParams.numBrdfSamples);
    result.localLightMisWeight = float(initialSamplingParams.numLocalLightSamples) / float(result.numMisSamples);
    result.environmentMapMisWeight = float(initialSamplingParams.numEnvironmentSamples) / float(result.numMisSamples);
    result.brdfMisWeight = float(initialSamplingParams.numBrdfSamples) / float(result.numMisSamples);
    return result;
}

// RTXDI: RTXDI_BrdfMaxDistanceFromPdf (InitialSampling.hlsli:57-61)
// Heuristic max ray length from BRDF PDF, controlling the MIS cutoff region.
// brdfCutoff == 0 disables shortening (returns +infinity sentinel).
float RTXDI_BrdfMaxDistanceFromPdf(float brdfCutoff, float pdf)
{
    const float kRayTMax = 3.402823466e+38;
    return brdfCutoff > 0.0 ? sqrt((1.0 / brdfCutoff - 1.0) * pdf) : kRayTMax;
}

// GGX VNDF PDF for a sampled light direction L given view direction V.
// Matches the sampling distribution of ph_sample_ggx_vndf (ph_core.glsl).
// Derivation: pdf_H = D(H) * G1(V) * dot(V,H) / max(dot(V,N), eps)
//             pdf_L = pdf_H / (4 * dot(V,H)) = D(H) * G1(V) / (4 * max(dot(V,N), eps))
float lt_evaluate_ggx_vndf_pdf(RAB_Surface surface, vec3 lightDir, vec3 viewDir)
{
    vec3 N = surface.normal;
    float nDotL = dot(N, lightDir);
    float nDotV = dot(N, viewDir);
    if (nDotL <= 0.0 || nDotV <= 0.0)
    {
        return 0.0;
    }

    vec3 H = normalize(viewDir + lightDir);
    float nDotH = max(dot(N, H), 0.0);

    float roughness = clamp(surface.material.roughness, lt_min_roughness, 1.0);
    float D = lt_distribution_ggx(nDotH, roughness);

    float a = max(roughness * roughness, 0.02);
    float k = a * 0.5;
    float G1 = nDotV / max(nDotV * (1.0 - k) + k, 1e-6);

    return D * G1 / max(4.0 * nDotV, 1e-6);
}

vec3 lt_sample_cosine_hemisphere_rtxdi(vec3 normal, vec2 rnd)
{
    float phi = rnd.x * (2.0f * lt_pi);
    float r = sqrt(rnd.y);
    float x = r * cos(phi);
    float y = r * sin(phi);
    float z = sqrt(max(0.0f, 1.0f - rnd.y));

    vec3 tangent = ph_build_tangent(normal);
    vec3 bitangent = cross(normal, tangent);
    return normalize(tangent * x + bitangent * y + normal * z);
}

vec3 lt_sample_ggx_vndf_rtxdi(vec3 viewDir, vec3 normal, float roughness, vec2 rnd)
{
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

bool RAB_SurfaceImportanceSampleBrdf(RAB_Surface surface, inout RTXDI_RandomSamplerState rng, out vec3 dir)
{
    vec3 rand = vec3(lt_next_random(rng), lt_next_random(rng), lt_next_random(rng));
    float diffuseProbability = lt_surface_diffuse_probability(surface);
    if (rand.x < diffuseProbability)
    {
        dir = lt_sample_cosine_hemisphere_rtxdi(surface.normal, rand.yz);
    }
    else
    {
        dir = lt_sample_ggx_vndf_rtxdi(
            normalize(surface.viewDir),
            surface.normal,
            max(surface.material.roughness, lt_min_roughness),
            rand.yz
        );
    }

    return dot(surface.normal, dir) > 0.0f;
}

float RAB_SurfaceEvaluateBrdfPdf(RAB_Surface surface, vec3 lightDir)
{
    float nDotL = max(dot(surface.normal, lightDir), 0.0);
    if (nDotL <= 0.0)
    {
        return 0.0;
    }

    vec3 viewDir = normalize(surface.viewDir);
    float pdfCosine = nDotL / lt_pi;
    float pdfGgx = lt_evaluate_ggx_vndf_pdf(surface, lightDir, viewDir);
    float diffuseProbability = lt_surface_diffuse_probability_with_view(surface, viewDir);
    return mix(pdfGgx, pdfCosine, diffuseProbability);
}

RTXDI_LocalLightSelectionContext RTXDI_InitializeLocalLightSelectionContextReGIRRIS(
    inout RTXDI_RandomSamplerState coherentRng,
    RTXDI_LightBufferRegion localLightBufferRegion,
    RTXDI_RISBufferSegmentParameters localLightRISBufferSegmentParams,
    RAB_Surface surface)
{
    // Old hard partitioning kept for reference:
    // int cellIndex = -1;
    // if (regir_resolve_cell(surface.worldPos, coherentRng, cellIndex) && cellIndex >= 0)
    // {
    //     RTXDI_LocalLightSelectionContext ctx = RTXDI_InitializeLocalLightSelectionContextRIS(
    //         RTXDI_SelectLocalLightReGIRRISTile(cellIndex));
    //     ctx.proposalFamily = LT_PROPOSAL_FAMILY_REGIR_RIS;
    //     return ctx;
    // }

    int cellIndex = -1;
    bool useReGIR = regir_resolve_cell(surface.worldPos, coherentRng, cellIndex) && cellIndex >= 0;
    bool hasFallbackRIS = localLightRISBufferSegmentParams.tileCount > 0u && localLightRISBufferSegmentParams.tileSize > 0u;

    if (useReGIR) {
        RTXDI_LocalLightSelectionContext ctx = RTXDI_InitializeLocalLightSelectionContextRIS(
            RTXDI_SelectLocalLightReGIRRISTile(cellIndex));
        ctx.proposalFamily = LT_PROPOSAL_FAMILY_REGIR_RIS;
        return ctx;
    }

    if (hasFallbackRIS)
    {
        RTXDI_LocalLightSelectionContext ctx = RTXDI_InitializeLocalLightSelectionContextRIS(coherentRng, localLightRISBufferSegmentParams);
        ctx.proposalFamily = LT_PROPOSAL_FAMILY_REGIR_FALLBACK;
        return ctx;
    }

    return RTXDI_InitializeLocalLightSelectionContextUniform(localLightBufferRegion);
}

RTXDI_LocalLightSelectionContext RTXDI_InitializeLocalLightSelectionContextFallback(
    inout RTXDI_RandomSamplerState coherentRng,
    RTXDI_LightBufferRegion localLightBufferRegion,
    RTXDI_RISBufferSegmentParameters localLightRISBufferSegmentParams)
{
    if (localLightRISBufferSegmentParams.tileCount > 0u && localLightRISBufferSegmentParams.tileSize > 0u)
    {
        RTXDI_LocalLightSelectionContext ctx = RTXDI_InitializeLocalLightSelectionContextRIS(coherentRng, localLightRISBufferSegmentParams);
        ctx.proposalFamily = LT_PROPOSAL_FAMILY_REGIR_FALLBACK;
        return ctx;
    }

    RTXDI_LocalLightSelectionContext ctx = RTXDI_InitializeLocalLightSelectionContextUniform(localLightBufferRegion);
    ctx.proposalFamily = LT_PROPOSAL_FAMILY_UNIFORM;
    return ctx;
}

RTXDI_LocalLightSelectionContext RTXDI_InitializeLocalLightSelectionContext(
    inout RTXDI_RandomSamplerState coherentRng,
    int localLightSamplingMode,
    RTXDI_LightBufferRegion localLightBufferRegion,
    RTXDI_RISBufferSegmentParameters localLightRISBufferSegmentParams,
    RAB_Surface surface)
{
    if (localLightSamplingMode == RTXDI_LOCAL_LIGHT_SAMPLING_REGIR_RIS)
    {
        return RTXDI_InitializeLocalLightSelectionContextReGIRRIS(
            coherentRng,
            localLightBufferRegion,
            localLightRISBufferSegmentParams,
            surface);
    }

    if (localLightSamplingMode == RTXDI_LOCAL_LIGHT_SAMPLING_POWER_RIS)
    {
        if (localLightRISBufferSegmentParams.tileCount > 0u && localLightRISBufferSegmentParams.tileSize > 0u)
        {
            return RTXDI_InitializeLocalLightSelectionContextRIS(coherentRng, localLightRISBufferSegmentParams);
        }
        RTXDI_LocalLightSelectionContext ctx = RTXDI_InitializeLocalLightSelectionContextUniform(localLightBufferRegion);
        ctx.proposalFamily = LT_PROPOSAL_FAMILY_UNIFORM;
        return ctx;
    }

    RTXDI_LocalLightSelectionContext ctx = RTXDI_InitializeLocalLightSelectionContextUniform(localLightBufferRegion);
    ctx.proposalFamily = LT_PROPOSAL_FAMILY_UNIFORM;
    return ctx;
}

void RTXDI_UnpackLocalLightFromRISLightData(
    uvec2 tileData,
    uint risBufferPtr,
    out RAB_LightInfo lightInfo,
    out uint lightIndex,
    out float invSourcePdf)
{
    lightInfo = RAB_EmptyLightInfo();
    lightIndex = tileData.x & RTXDI_LIGHT_INDEX_MASK;
    invSourcePdf = uintBitsToFloat(tileData.y);

    bool invalidEntry = (tileData.x == 0u && tileData.y == 0u) || invSourcePdf <= 0.0f;
    if (invalidEntry)
    {
        lightIndex = 0u;
        invSourcePdf = 0.0f;
        return;
    }

    if ((tileData.x & RTXDI_LIGHT_COMPACT_BIT) != 0u)
    {
        lightInfo = RAB_LoadCompactLightInfo(risBufferPtr, int(lightIndex));
    }
    else
    {
        lightInfo = RAB_LoadLightInfo(int(lightIndex), false);
    }
}

void RTXDI_RandomlySelectLocalLightFromRISTile(
    float rnd,
    const RTXDI_RISTileInfo risTileInfo,
    out RAB_LightInfo lightInfo,
    out uint lightIndex,
    out float invSourcePdf)
{
    uvec2 risTileData;
    uint risBufferPtr;
    RTXDI_RandomlySelectLightDataFromRISTile(rnd, risTileInfo, risTileData, risBufferPtr);
    RTXDI_UnpackLocalLightFromRISLightData(risTileData, risBufferPtr, lightInfo, lightIndex, invSourcePdf);
}

void RTXDI_SelectNextLocalLight(
    RTXDI_LocalLightSelectionContext ctx,
    float rnd,
    out RAB_LightInfo lightInfo,
    out uint lightIndex,
    out float invSourcePdf)
{
    if (ctx.mode == RTXDI_LocalLightContextSamplingMode_RIS)
    {
        RTXDI_RandomlySelectLocalLightFromRISTile(rnd, ctx.risTileInfo, lightInfo, lightIndex, invSourcePdf);
        return;
    }

    RTXDI_RandomlySelectLightUniformly(rnd, ctx.lightBufferRegion, lightInfo, lightIndex, invSourcePdf);
}

vec2 RTXDI_RandomlySelectLocalLightUV(inout RTXDI_RandomSamplerState rng)
{
    vec2 uv;
    uv.x = lt_next_random(rng);
    uv.y = lt_next_random(rng);
    return uv;
}

RTXDI_DIReservoir RTXDI_SampleLocalLights(
    inout RTXDI_RandomSamplerState rng,
    inout RTXDI_RandomSamplerState coherentRng,
    RAB_Surface surface,
    RTXDI_DIInitialSamplingParameters initialSamplingParams,
    out RAB_LightSample o_selectedSample)
{
    o_selectedSample = RAB_EmptyLightSample();

    RTXDI_LightBufferRegion localLightBufferRegion = RTXDI_GetLocalLightBufferRegion();
    if (localLightBufferRegion.numLights == 0u)
    {
        return RTXDI_EmptyDIReservoir();
    }

    if (initialSamplingParams.numLocalLightSamples == 0u)
    {
        return RTXDI_EmptyDIReservoir();
    }

    RTXDI_InitialSamplingMisData misData = RTXDI_ComputeInitialSamplingMisData(initialSamplingParams);
    RTXDI_RISBufferSegmentParameters localLightRISBufferSegmentParams = RTXDI_GetLocalLightRISBufferSegmentParameters();
    int localLightSamplingMode = int(initialSamplingParams.localLightSamplingMode);
    RTXDI_LocalLightSelectionContext lightSelectionContext = RTXDI_InitializeLocalLightSelectionContext(
        coherentRng,
        localLightSamplingMode,
        localLightBufferRegion,
        localLightRISBufferSegmentParams,
        surface);

    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();

    for (uint i = 0u; i < initialSamplingParams.numLocalLightSamples; i++)
    {
        uint lightIndex = 0u;
        RAB_LightInfo lightInfo = RAB_EmptyLightInfo();
        float invSourcePdf = 0.0f;

        float rnd = lt_next_random(rng);
        rnd = (rnd + float(i)) / float(initialSamplingParams.numLocalLightSamples);

        RTXDI_SelectNextLocalLight(lightSelectionContext, rnd, lightInfo, lightIndex, invSourcePdf);
        if (lightInfo.index < 0 || invSourcePdf <= 0.0f)
        {
            continue;
        }

        vec2 uv = RTXDI_RandomlySelectLocalLightUV(rng);
        RAB_LightSample candidateSample = RAB_SamplePolymorphicLight(lightInfo, surface, uv);
        float blendedSourcePdf = RTXDI_LightBrdfMisWeight(
            surface,
            candidateSample,
            1.0f / invSourcePdf,
            misData.localLightMisWeight,
            misData.brdfMisWeight,
            initialSamplingParams.brdfCutoff);
        float targetPdf = RAB_GetLightSampleTargetPdfForSurface(candidateSample, surface);
        float risRnd = lt_next_random(rng);

        if (blendedSourcePdf == 0.0f)
        {
            continue;
        }

        bool selected = RTXDI_StreamSample(state, int(lightIndex), uv, risRnd, targetPdf, 1.0f / blendedSourcePdf);
        if (selected)
        {
            state.transportAux0 = 1.0f / blendedSourcePdf;
            state.pathSample = lt_make_path_sample(2u, lightSelectionContext.proposalFamily);
            o_selectedSample = candidateSample;
        }
    }

    RTXDI_FinalizeResampling(state, 1.0f, float(misData.numMisSamples));
    state.M = 1.0f;
    if (RTXDI_IsValidDIReservoir(state)) {
        state.pathSample = lt_make_path_sample(2u, lightSelectionContext.proposalFamily);
    }
    lt_area_finalize_candidate(state, lt_fragment_pixel_pos(), state.pathSample);
    return state;
}

RTXDI_DIReservoir RTXDI_SampleInfiniteLights(RAB_Surface surface, int numSamples)
{
    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    return state;
}

RTXDI_DIReservoir RTXDI_SampleEnvironmentMap(RAB_Surface surface, int numSamples)
{
    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    return state;
}

RTXDI_DIReservoir RTXDI_SampleBrdf(inout RTXDI_RandomSamplerState rng, RAB_Surface surface, int numSamples, RTXDI_InitialSamplingMisData misData, float brdfCutoff, out RAB_LightSample o_selectedSample)
{
    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    o_selectedSample = lt_null_sample();
    if (numSamples <= 0 || ph_light_count <= 0 || !lt_bridge_supports_brdf_local_light_replay())
    {
        return state;
    }

    vec3 viewDir = normalize(surface.viewDir);
    const float brdfRayMinT = 0.001f;
    vec3 rayOrigin = lt_surface_ray_origin(lt_surface_rt_pos(surface), surface.geoNormal);

    for (int i = 0; i < numSamples; i++)
    {
        vec3 sampleDir = vec3(0.0f);
        if (!RAB_SurfaceImportanceSampleBrdf(surface, rng, sampleDir))
        {
            continue;
        }

        float brdfPdf = RAB_SurfaceEvaluateBrdfPdf(surface, sampleDir);
        if (brdfPdf <= 0.0)
        {
            continue;
        }

        float maxDistance = RTXDI_BrdfMaxDistanceFromPdf(brdfCutoff, brdfPdf);

        lightEmittance = vec3(0.0f);
        breakOnEmpty = true;
        ray.origin = rayOrigin + sampleDir * brdfRayMinT;
        ray.direction = sampleDir;
        trace_ray(ray, true);
        breakOnEmpty = false;

        if (!ray.result_hit || ph_luminance(lightEmittance) <= 1e-6f)
        {
            continue;
        }

        float hitDistance = length(ray.result_position - rayOrigin);
        if (hitDistance > maxDistance)
        {
            continue;
        }

        int lightIndex = -1;
        float bestDistSq = 3.402823466e+38f;
        ivec3 hitCell = ivec3(floor(ray.result_position));
        for (int j = 0; j < ph_light_count; j++)
        {
            Light candidate = load_light(j);
            if (any(notEqual(ivec3(floor(candidate.position)), hitCell)))
            {
                continue;
            }

            if (candidate.blockId >= 0 && result_block_id >= 0 && candidate.blockId != result_block_id)
            {
                continue;
            }

            vec3 delta = candidate.position - ray.result_position;
            float distSq = dot(delta, delta);
            if (distSq < bestDistSq)
            {
                bestDistSq = distSq;
                lightIndex = j;
            }
        }

        if (lightIndex < 0)
        {
            continue;
        }

        Light hitLight = load_light(lightIndex);
        vec3 sampledPosition = hitLight.position;
        vec2 sampleUv = vec2(0.0f);
        RAB_LightSample brdfSample = light_sample_new_at_position(hitLight, sampledPosition, surface);
        float targetPdf = brdfSample.weight;
        if (targetPdf <= 0.0)
        {
            continue;
        }

        float lightSelectionPdf;
        float totalCdfWeight = ph_global_light_cdf_data[ph_light_count - 1];
        if (totalCdfWeight > 1e-6)
        {
            float prevCdf = lightIndex > 0 ? ph_global_light_cdf_data[lightIndex - 1] : 0.0;
            float lightWeight = ph_global_light_cdf_data[lightIndex] - prevCdf;
            lightSelectionPdf = lightWeight / totalCdfWeight;
        }
        else
        {
            lightSelectionPdf = 1.0 / float(max(ph_light_count, 1));
        }

        if (lightSelectionPdf <= 0.0)
        {
            continue;
        }

        float blendedSourcePdf = RTXDI_LightBrdfMisWeight(
            surface,
            brdfSample,
            lightSelectionPdf,
            misData.localLightMisWeight,
            misData.brdfMisWeight,
            brdfCutoff
        );

        if (blendedSourcePdf <= 0.0)
        {
            continue;
        }

        bool selected = RTXDI_StreamSample(state, brdfSample.index, sampleUv, lt_next_random(rng), targetPdf, 1.0f / blendedSourcePdf);
        if (selected)
        {
            state.transportAux0 = 1.0f / blendedSourcePdf;
            state.pathSample = lt_make_path_sample(1u, LT_PROPOSAL_FAMILY_BRDF);
            o_selectedSample = brdfSample;
        }
    }

    RTXDI_FinalizeResampling(state, 1.0, float(misData.numMisSamples));
    state.M = 1.0;
    if (RTXDI_IsValidDIReservoir(state)) {
        state.pathSample = lt_make_path_sample(1u, LT_PROPOSAL_FAMILY_BRDF);
    }
    lt_area_finalize_candidate(state, lt_fragment_pixel_pos(), state.pathSample);
    return state;
}

RTXDI_DIReservoir RTXDI_SampleLightsForSurface(
    inout RTXDI_RandomSamplerState rng,
    inout RTXDI_RandomSamplerState coherentRng,
    RAB_Surface surface,
    RTXDI_DIInitialSamplingParameters initialSamplingParams,
    out RAB_LightSample o_lightSample)
{
    if (!RAB_IsSurfaceValid(surface))
    {
        o_lightSample = RAB_EmptyLightSample();
        return RTXDI_EmptyDIReservoir();
    }

    RTXDI_InitialSamplingMisData misData = RTXDI_ComputeInitialSamplingMisData(initialSamplingParams);

    RAB_LightSample localSample = lt_null_sample();
    RTXDI_DIReservoir localReservoir = RTXDI_SampleLocalLights(rng, coherentRng, surface, initialSamplingParams, localSample);

    RAB_LightSample infiniteSample = lt_null_sample();
    RTXDI_DIReservoir infiniteReservoir = RTXDI_SampleInfiniteLights(surface, int(initialSamplingParams.numInfiniteLightSamples));

    RAB_LightSample environmentSample = lt_null_sample();
    RTXDI_DIReservoir environmentReservoir = RTXDI_SampleEnvironmentMap(surface, int(initialSamplingParams.numEnvironmentSamples));

    RAB_LightSample brdfSample = lt_null_sample();
    RTXDI_DIReservoir brdfReservoir = RTXDI_SampleBrdf(
        rng,
        surface,
        int(initialSamplingParams.numBrdfSamples),
        misData,
        initialSamplingParams.brdfCutoff,
        brdfSample);

    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    RTXDI_CombineDIReservoirs(state, localReservoir, 0.5, localReservoir.targetPdf);
    bool selectInfinite = RTXDI_CombineDIReservoirs(state, infiniteReservoir, lt_next_random(rng), infiniteReservoir.targetPdf);
    bool selectEnvironment = RTXDI_CombineDIReservoirs(state, environmentReservoir, lt_next_random(rng), environmentReservoir.targetPdf);
    bool selectBrdf = RTXDI_CombineDIReservoirs(state, brdfReservoir, lt_next_random(rng), brdfReservoir.targetPdf);

    RTXDI_FinalizeResampling(state, 1.0, 1.0);
    state.M = 1.0;
    if (RTXDI_IsValidDIReservoir(state)) {
        uint selectedProposalFamily = LT_PROPOSAL_FAMILY_UNKNOWN;
        if (selectBrdf) {
            selectedProposalFamily = LT_PROPOSAL_FAMILY_BRDF;
        } else {
            selectedProposalFamily = (state.pathSample >> LT_PATH_SAMPLE_PROPOSAL_SHIFT) & LT_PATH_SAMPLE_PROPOSAL_MASK;
        }
        state.pathSample = lt_make_path_sample(selectBrdf ? 1u : 2u, selectedProposalFamily);
    }
    lt_area_finalize_candidate(state, lt_fragment_pixel_pos(), state.pathSample);

    o_lightSample = localSample;
    if (selectBrdf)
    {
        o_lightSample = brdfSample;
    }
    else if (selectEnvironment)
    {
        o_lightSample = environmentSample;
    }
    else if (selectInfinite)
    {
        o_lightSample = infiniteSample;
    }

    if (initialSamplingParams.enableInitialVisibility != 0u && RTXDI_IsValidDIReservoir(state) && o_lightSample.index >= 0)
    {
        if (!RAB_GetConservativeVisibility(surface, o_lightSample))
        {
            RTXDI_StoreVisibilityInDIReservoir(state, vec3(0.0f), true);
        }
    }

    return state;
}

#endif
