#ifndef PHOTONICS_RESTIR_GI_INITIAL_SAMPLING_IMPL_GLSL
#define PHOTONICS_RESTIR_GI_INITIAL_SAMPLING_IMPL_GLSL

// Forward declarations for the sampling helpers defined below. The
// function prototypes for RTXDI_Sample* / RAB_SurfaceImportanceSampleBrdf
// / RAB_SurfaceEvaluateBrdfPdf / RTXDI_BrdfMaxDistanceFromPdf already live
// in reuse_bridge.glsl (pulled in via the stage header) -- redeclaring
// them here triggers "declaration conflicts with previous declaration"
// under strict drivers, so this block intentionally only holds the
// additional GI-specific prototypes we need before their point of use.

// GI-facing implementation surface for the shared initial-sampling helper chain.
// This keeps the indirect pipeline independent from late implementation regions in
// reuse_bridge.glsl while preserving a single implementation owner for these symbols.

// ---------------------------------------------------------------------------
// Paper-aligned reconnection payload alias.
// The reference implementation (Reservoir-Splatting, ReconnectionData.slang)
// names this struct ``ReconnectionData``. Photonics exposes it under
// ``ReservoirSplattingReconnectionData`` and the underlying storage layout is
// defined as ``ScatterReconnectionData`` in reuse_bridge.glsl. Those aliases
// are declared in reuse_bridge.glsl right after the struct definition so every
// downstream include (this file included) picks them up transparently -- no
// re-declaration is needed or permitted here (GLSL forbids redefining macros
// to the same target without ``#undef``).

// ---------------------------------------------------------------------------
// Reference-aligned local-light selection payloads.
// These declarations are consumed by the initial-candidate stage before the
// late reuse bridge implementation region becomes visible in Iris' dumped
// shader output, so they live with the stage that first requires them.
#ifndef PH_LIGHTTREE_REUSE_INCLUDE
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
const uint RTXDI_LocalLightContextSamplingMode_INVALID = 0xFFFFFFFFu;

struct RTXDI_LocalLightSelectionContext
{
    uint mode;
    uint proposalFamily;
    RTXDI_RISTileInfo risTileInfo;
    RTXDI_LightBufferRegion lightBufferRegion;
};

RTXDI_LightBufferRegion RTXDI_GetLocalLightBufferRegion();
RTXDI_RISBufferSegmentParameters RTXDI_GetLocalLightRISBufferSegmentParameters();
void RTXDI_RandomlySelectLightUniformly(
    float rnd,
    RTXDI_LightBufferRegion region,
    out RAB_LightInfo lightInfo,
    out uint lightIndex,
    out float invSourcePdf);
void RTXDI_RandomlySelectLightDataFromRISTile(
    float rnd,
    RTXDI_RISTileInfo bufferInfo,
    out uvec2 tileData,
    out uint risBufferPtr);
RTXDI_RISTileInfo RTXDI_SelectLocalLightReGIRRISTile(int cellIndex);
RTXDI_LocalLightSelectionContext RTXDI_InitializeLocalLightSelectionContextUniform(RTXDI_LightBufferRegion lightBufferRegion);
RTXDI_LocalLightSelectionContext RTXDI_InitializeLocalLightSelectionContextRIS(RTXDI_RISTileInfo risTileInfo);
RTXDI_LocalLightSelectionContext RTXDI_InitializeLocalLightSelectionContextRIS(
    inout RTXDI_RandomSamplerState coherentRng,
    RTXDI_RISBufferSegmentParameters risBufferSegmentParams);
bool lt_bridge_supports_brdf_local_light_replay();
float RTXDI_BrdfMaxDistanceFromPdf(float brdfCutoff, float pdf);
float RAB_SurfaceEvaluateBrdfPdf(RAB_Surface surface, vec3 lightDir);
float RTXDI_LightBrdfMisWeight(
    RAB_Surface surface,
    RAB_LightSample lightSample,
    float lightSelectionPdf,
    float lightMisWeight,
    float brdfMisWeight,
    float brdfCutoff);
#endif

// ---------------------------------------------------------------------------
// Local-light selection context sentinel (reference parity):
// RTXDI_InitializeLocalLightSelectionContext may fail to produce a usable
// POWER_RIS tile or REGIR_RIS cell. In that case the caller must short-circuit
// RTXDI_SelectNextLocalLight with invSourcePdf=0 rather than silently falling
// back to uniform sampling (which would bias the initial candidate stream).
// These sentinels are consumed by ``lt_make_invalid_local_light_selection_context``
// and the ``ctx.mode == RTXDI_LocalLightContextSamplingMode_INVALID`` branch in
// ``RTXDI_SelectNextLocalLight`` (see reuse_bridge.glsl).
const uint LT_PROPOSAL_FAMILY_INVALID = 0xFFFFFFFFu;

// ---------------------------------------------------------------------------
// RTXDI_StreamSampleWithDomain
//
// Extends ``RTXDI_StreamSample`` with the Area-ReSTIR / reservoir-splatting
// domain coordinates (subpixel, lens, pathSample id) that the reference
// PathTracer records alongside the winning candidate (PathTracer.slang:208,
// Reservoir.slang:CandidateReservoir::addVertex and the reconnection payload
// plumbing in InitialCandidates.cs.slang). When the candidate is selected, the
// reservoir stores the exact domain coordinate of the winning candidate so
// downstream stages (scatter temporal reprojection, MIS weighting, shading)
// can replay the selected path without a pixel-center fallback.
float CandidateReservoir_getTotalWeight(RTXDI_DIReservoir candidateReservoir)
{
    return PathReservoir_getTotalWeight(candidateReservoir);
}

void CandidateReservoir_setTotalWeight(
    inout RTXDI_DIReservoir candidateReservoir,
    float totalWeight)
{
    PathReservoir_setTotalWeight(candidateReservoir, totalWeight);
}

vec3 CandidateReservoir_getIntegrand(RTXDI_DIReservoir candidateReservoir)
{
    return PathReservoir_getIntegrand(candidateReservoir);
}

void CandidateReservoir_setIntegrand(
    inout RTXDI_DIReservoir candidateReservoir,
    vec3 integrand)
{
    PathReservoir_setIntegrand(candidateReservoir, integrand);
}

bool CandidateReservoir_addVertex(
    inout RTXDI_DIReservoir candidateReservoir,
    float random,
    int lightIndex,
    vec2 sampleUv,
    float sampleMIS,
    vec3 sampleIntegrand,
    vec3 sampleVisibility,
    vec2 pixelSampleUV,
    vec2 lensSampleUV,
    uint pathSample)
{
    float samplePHat = ph_luminance(max(sampleIntegrand, vec3(0.0f)));
    float sampleWeight = sampleMIS * samplePHat;
    sampleWeight = isnan(sampleWeight) ? 0.0f : sampleWeight;

    CandidateReservoir_setTotalWeight(
        candidateReservoir,
        CandidateReservoir_getTotalWeight(candidateReservoir) + sampleWeight
    );
    bool selected = (random * CandidateReservoir_getTotalWeight(candidateReservoir) < sampleWeight);
    if (selected) {
        rtxdi_set_light_index(candidateReservoir, lightIndex);
        rtxdi_set_sample_uv(candidateReservoir, sampleUv);
        candidateReservoir.targetPdf = samplePHat;
        CandidateReservoir_setIntegrand(candidateReservoir, sampleIntegrand);
        RTXDI_StoreVisibilityInDIReservoir(candidateReservoir, sampleVisibility, false);
        candidateReservoir.pixelSampleUV = pixelSampleUV;
        candidateReservoir.lensSampleUV  = lensSampleUV;
        candidateReservoir.pathSample    = pathSample;
    }
    return selected;
}

float CandidateReservoir_computeUCW(RTXDI_DIReservoir candidateReservoir)
{
    float pHat = ph_luminance(CandidateReservoir_getIntegrand(candidateReservoir));
    return (pHat <= 0.0f) ? 0.0f : CandidateReservoir_getTotalWeight(candidateReservoir) / pHat;
}

bool PathReservoir_add(
    inout RTXDI_DIReservoir pathReservoir,
    float random,
    float sampleMIS,
    RTXDI_DIReservoir candidateReservoir)
{
    float weight = sampleMIS * CandidateReservoir_getTotalWeight(candidateReservoir);
    PathReservoir_setTotalWeight(pathReservoir, PathReservoir_getTotalWeight(pathReservoir) + weight);
    PathReservoir_setConfidence(pathReservoir, PathReservoir_getConfidence(pathReservoir) + 1.0f);

    bool selected = (random * PathReservoir_getTotalWeight(pathReservoir) < weight);
    if (selected) {
        pathReservoir.lightData = candidateReservoir.lightData;
        pathReservoir.uvData = candidateReservoir.uvData;
        pathReservoir.targetPdf = candidateReservoir.targetPdf;
        pathReservoir.packedVisibility = candidateReservoir.packedVisibility;
        pathReservoir.age = candidateReservoir.age;
        pathReservoir.spatialDistance = candidateReservoir.spatialDistance;
        pathReservoir.canonicalWeight = candidateReservoir.canonicalWeight;
        pathReservoir.transportAux0 = candidateReservoir.transportAux0;
        pathReservoir.transportAux1 = candidateReservoir.transportAux1;
        pathReservoir.pixelSampleUV = candidateReservoir.pixelSampleUV;
        pathReservoir.lensSampleUV = candidateReservoir.lensSampleUV;
        pathReservoir.pathSample = candidateReservoir.pathSample;
    }
    return selected;
}

float PathReservoir_computeUCW(RTXDI_DIReservoir pathReservoir)
{
    return PathReservoir_computeStoredUCW(pathReservoir);
}

// RTXDI: RTXDI_ComputeInitialSamplingMisData (InitialSampling.hlsli:41-54)
// RTXDI does NOT guard numMisSamples against zero here -- the early-exit in RTXDI_SampleLocalLights
// ensures numMisSamples > 0 before this is used in division.
// numMisSamples includes local + environment + BRDF sample counts (InitialSampling.hlsli line 45).
// Environment samples are included even when the environment stub returns M=0 so MIS weights
// remain consistent with the SDK reference.
RTXDI_LocalLightSelectionContext lt_make_invalid_local_light_selection_context()
{
    RTXDI_LocalLightSelectionContext ctx;
    ctx.mode = RTXDI_LocalLightContextSamplingMode_INVALID;
    ctx.proposalFamily = LT_PROPOSAL_FAMILY_INVALID;
    ctx.risTileInfo.risTileOffset = 0u;
    ctx.risTileInfo.risTileSize = 0u;
    ctx.lightBufferRegion.firstLightIndex = 0u;
    ctx.lightBufferRegion.numLights = 0u;
    ctx.lightBufferRegion.pad1 = 0u;
    ctx.lightBufferRegion.pad2 = 0u;
    return ctx;
}

#ifndef PH_LIGHTTREE_REUSE_INCLUDE
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

bool lt_bridge_supports_brdf_local_light_replay() {
    return false;
}

float RTXDI_LightBrdfMisWeight(
    RAB_Surface surface,
    RAB_LightSample lightSample,
    float lightSelectionPdf,
    float lightMisWeight,
    float brdfMisWeight,
    float brdfCutoff
) {
    float lightSolidAnglePdf = lightSample.solidAnglePdf;

    if (brdfMisWeight == 0.0
        || rtxdi_is_analytic_light_sample(lightSample)
        || lightSolidAnglePdf <= 0.0
        || isinf(lightSolidAnglePdf)
        || isnan(lightSolidAnglePdf)) {
        return lightMisWeight * lightSelectionPdf;
    }

    float brdfPdf = RAB_SurfaceEvaluateBrdfPdf(surface, lightSample.dir);
    float maxDistance = RTXDI_BrdfMaxDistanceFromPdf(brdfCutoff, brdfPdf);
    float lightDistance = length(lightSample.position - lt_surface_rt_pos(surface));
    if (lightDistance > maxDistance) {
        brdfPdf = 0.0;
    }

    float sourcePdfWrtSolidAngle = lightSelectionPdf * lightSolidAnglePdf;
    float blendedPdfWrtSolidAngle = lightMisWeight * sourcePdfWrtSolidAngle + brdfMisWeight * brdfPdf;
    return blendedPdfWrtSolidAngle / lightSolidAnglePdf;
}
#endif

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
    int cellIndex = -1;
    bool useReGIR = regir_resolve_cell(surface.worldPos, coherentRng, cellIndex) && cellIndex >= 0;
    if (!useReGIR) {
        return lt_make_invalid_local_light_selection_context();
    }

    RTXDI_LocalLightSelectionContext ctx = RTXDI_InitializeLocalLightSelectionContextRIS(
        RTXDI_SelectLocalLightReGIRRISTile(cellIndex));
    ctx.proposalFamily = LT_PROPOSAL_FAMILY_REGIR_RIS;
    return ctx;
}

RTXDI_LocalLightSelectionContext RTXDI_InitializeLocalLightSelectionContextFallback(
    inout RTXDI_RandomSamplerState coherentRng,
    RTXDI_LightBufferRegion localLightBufferRegion,
    RTXDI_RISBufferSegmentParameters localLightRISBufferSegmentParams)
{
    if (localLightRISBufferSegmentParams.tileCount == 0u || localLightRISBufferSegmentParams.tileSize == 0u)
    {
        return lt_make_invalid_local_light_selection_context();
    }

    RTXDI_LocalLightSelectionContext ctx = RTXDI_InitializeLocalLightSelectionContextRIS(coherentRng, localLightRISBufferSegmentParams);
    ctx.proposalFamily = LT_PROPOSAL_FAMILY_POWER_RIS;
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
        return RTXDI_InitializeLocalLightSelectionContextFallback(
            coherentRng,
            localLightBufferRegion,
            localLightRISBufferSegmentParams);
    }

    // Reference parity: the initial-candidate stage has no uniform-selection
    // fallback. Any non-RIS/non-ReGIR mode is an explicit misconfiguration and
    // results in an INVALID selection context that emits no candidates.
    return lt_make_invalid_local_light_selection_context();
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
    // Reference parity: an INVALID context (ReGIR cell missing or RIS tiles
    // absent) short-circuits with no candidate instead of degrading to uniform.
    if (ctx.mode == RTXDI_LocalLightContextSamplingMode_INVALID)
    {
        lightInfo = RAB_EmptyLightInfo();
        lightIndex = 0u;
        invSourcePdf = 0.0f;
        return;
    }

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

RTXDI_DIReservoir InitialCandidates_SampleLocalLights(
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

        // Reference parity: candidates must be IID (InitialCandidates.cs.slang:59
        // "All samples are IID, so m_i = 1 / M."). No per-iteration stratified
        // remapping of the random draw.
        float rnd = lt_next_random(rng);

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
        if (blendedSourcePdf <= 0.0f)
        {
            continue;
        }

        float visibilityHitDistance = 0.0f;
        vec3 visibility = lt_trace_final_visibility_with_offset(
            candidateSample,
            surface,
            0.0f,
            visibilityHitDistance
        );
        if (candidateSample.index < 0 || ph_luminance(max(visibility, vec3(0.0f))) <= 0.0f)
        {
            continue;
        }

        vec3 sampleIntegrand = max(
            lt_shade_surface_light_sample(surface, candidateSample) * visibility,
            vec3(0.0f)
        );
        if (ph_luminance(sampleIntegrand) <= 0.0f)
        {
            continue;
        }

        float risRnd = lt_next_random(rng);

        // Reference parity (PathTracer.slang:208): each candidate draws its own
        // subpixel and lens sample from the path RNG so the selected reservoir
        // carries the exact domain coordinate of the winning candidate, without
        // a pixel-center fallback.
        vec2 candidatePixelSample = lt_area_random_pixel_sample(rng, lt_fragment_pixel_pos());
        vec2 candidateLensSample = lt_area_sample_lens_sample(rng);
        uint candidatePathSample = lt_make_path_sample(2u, lightSelectionContext.proposalFamily);

        bool selected = CandidateReservoir_addVertex(
            state,
            risRnd,
            int(lightIndex),
            uv,
            1.0f / blendedSourcePdf,
            sampleIntegrand,
            visibility,
            candidatePixelSample,
            candidateLensSample,
            candidatePathSample);
        if (selected)
        {
            o_selectedSample = candidateSample;
        }
    }

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

RTXDI_DIReservoir InitialCandidates_SampleBrdf(inout RTXDI_RandomSamplerState rng, RAB_Surface surface, int numSamples, RTXDI_InitialSamplingMisData misData, float brdfCutoff, out RAB_LightSample o_selectedSample)
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
        vec3 sampleIntegrand = max(lt_shade_surface_light_sample(surface, brdfSample), vec3(0.0f));
        if (ph_luminance(sampleIntegrand) <= 0.0f)
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

        // Reference parity: draw per-candidate subpixel + lens sample and
        // record them alongside the light selection. No pixel-center fallback.
        vec2 candidatePixelSample = lt_area_random_pixel_sample(rng, lt_fragment_pixel_pos());
        vec2 candidateLensSample = lt_area_sample_lens_sample(rng);
        uint candidatePathSample = lt_make_path_sample(1u, LT_PROPOSAL_FAMILY_BRDF);

        bool selected = CandidateReservoir_addVertex(
            state,
            lt_next_random(rng),
            brdfSample.index,
            sampleUv,
            1.0f / blendedSourcePdf,
            sampleIntegrand,
            vec3(1.0f),
            candidatePixelSample,
            candidateLensSample,
            candidatePathSample);
        if (selected)
        {
            o_selectedSample = brdfSample;
        }
    }

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
    bool selectLocal = PathReservoir_add(state, lt_next_random(rng), 1.0f, localReservoir);
    bool selectInfinite = PathReservoir_add(state, lt_next_random(rng), 1.0f, infiniteReservoir);
    bool selectEnvironment = PathReservoir_add(state, lt_next_random(rng), 1.0f, environmentReservoir);
    bool selectBrdf = PathReservoir_add(state, lt_next_random(rng), 1.0f, brdfReservoir);

    RTXDI_FinalizeResampling(state, 1.0, 1.0);
    state.M = 1.0;
    if (RTXDI_IsValidDIReservoir(state)) {
        uint selectedProposalFamily = LT_PROPOSAL_FAMILY_UNKNOWN;
        if (selectBrdf) {
            selectedProposalFamily = LT_PROPOSAL_FAMILY_BRDF;
        } else {
            selectedProposalFamily = (state.pathSample >> LT_PATH_SAMPLE_PROPOSAL_SHIFT) & LT_PATH_SAMPLE_PROPOSAL_MASK;
        }
        // Preserve the pixel/lens domain samples that the sub-reservoir
        // recorded during streaming (RTXDI_InternalSimpleResample copies them
        // on selection); only rewrite the path-sample tag so the proposal
        // family reflects the winning technique.
        uint basePathSample = selectBrdf ? 1u : 2u;
        state.pathSample = lt_make_path_sample(basePathSample, selectedProposalFamily);
    }
    // Reference parity: subpixel + lens domain samples are recorded during
    // streaming, not synthesized post-hoc. Removed lt_area_finalize_candidate.

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
        // Trace the FINAL visibility (RGB transmittance through stained glass,
        // tinted voxels, etc.) once per selected candidate and store it in the
        // reservoir's packedVisibility channel. Bug T1.2 fix: bake V into the
        // RIS arithmetic (targetPdf + weightSum) so the reference invariant
        //     pHat_at_finalize == luminance(integrand)
        // holds once the reconnection's integrand is built with V in
        // `scatter_compute_reconnection_integrand`. Downstream stages then use
        // pure `integrand * UCW` at resolve (ResolveReSTIR.cs.slang:57),
        // eliminating the per-frame visibility re-trace that caused bug T1.1.
        float visibilityHitDistance = 0.0f;
        vec3 visibilityRgb = lt_trace_final_visibility_with_offset(
            o_lightSample, surface, 0.0f, visibilityHitDistance
        );
        float lumV = ph_luminance(max(visibilityRgb, vec3(0.0f)));
        if (!(lumV > 0.0f))
        {
            RTXDI_StoreVisibilityInDIReservoir(state, vec3(0.0f), true);
        }
        else
        {
            RTXDI_StoreVisibilityInDIReservoir(state, visibilityRgb, false);
            // Bug T1.2 fix: bake V into the reservoir's stored pHat so the
            // reference invariant pHat == luminance(integrand_with_V) holds
            // after the reconnection's integrand absorbs V in
            // `scatter_compute_reconnection_integrand`.
            //
            // Port storage convention: after this inner-RIS finalize,
            //   state.weightSum = UCW (post-RTXDI_FinalizeResampling)
            //   state.targetPdf = pHat (without V).
            // The OUTER IID merge in `lt_accumulate_iid_candidate` accumulates
            //   outer.weightSum += mis * candidate.weightSum * candidate.targetPdf
            //                    = mis * UCW * pHat                  (reference totalWeight)
            // and the resolve path recovers ref UCW via
            //   UCW_resolve = outer.weightSum / luminance(integrand_with_V).
            //
            // To bake V into the reference `totalWeight` at the outer level we
            // need exactly ONE factor of luminance(V) in `UCW * pHat`. Scaling
            // BOTH would over-multiply by lumV^2 and amplify per-pixel pHat
            // jitter across frames (catastrophic on shadow edges). Scaling
            // ONLY `targetPdf` yields:
            //   outer.weightSum += mis * UCW * (pHat * lumV) = mis * totalWeight_ref_with_V
            //   UCW_resolve      = (totalWeight * lumV) / (pHat * lumV) = UCW_ref
            //   color            = integrand_with_V * UCW_ref
            // exactly matching ResolveReSTIR.cs.slang:57.
            state.targetPdf *= lumV;
        }
    }

    return state;
}

RTXDI_DIReservoir InitialCandidates_SampleLightsForSurface(
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
    RTXDI_DIReservoir localReservoir = InitialCandidates_SampleLocalLights(
        rng,
        coherentRng,
        surface,
        initialSamplingParams,
        localSample
    );

    RAB_LightSample infiniteSample = lt_null_sample();
    RTXDI_DIReservoir infiniteReservoir = RTXDI_SampleInfiniteLights(
        surface,
        int(initialSamplingParams.numInfiniteLightSamples)
    );

    RAB_LightSample environmentSample = lt_null_sample();
    RTXDI_DIReservoir environmentReservoir = RTXDI_SampleEnvironmentMap(
        surface,
        int(initialSamplingParams.numEnvironmentSamples)
    );

    RAB_LightSample brdfSample = lt_null_sample();
    RTXDI_DIReservoir brdfReservoir = InitialCandidates_SampleBrdf(
        rng,
        surface,
        int(initialSamplingParams.numBrdfSamples),
        misData,
        initialSamplingParams.brdfCutoff,
        brdfSample
    );

    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    o_lightSample = lt_null_sample();

    if (PathReservoir_add(state, lt_next_random(rng), 1.0f, localReservoir))
    {
        o_lightSample = localSample;
    }
    if (PathReservoir_add(state, lt_next_random(rng), 1.0f, infiniteReservoir))
    {
        o_lightSample = infiniteSample;
    }
    if (PathReservoir_add(state, lt_next_random(rng), 1.0f, environmentReservoir))
    {
        o_lightSample = environmentSample;
    }
    if (PathReservoir_add(state, lt_next_random(rng), 1.0f, brdfReservoir))
    {
        o_lightSample = brdfSample;
    }

    return state;
}

#endif
