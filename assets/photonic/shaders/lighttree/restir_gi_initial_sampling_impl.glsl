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
// ``ReconnectionData`` and the underlying storage layout is
// defined as ``ReconnectionData`` in reuse_bridge.glsl. Those aliases
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
// Local-light selection context sentinel for unsupported Photonics modes.
const uint LT_PROPOSAL_FAMILY_INVALID = 0xFFFFFFFFu;
const int REGIR_LOCAL_LIGHT_FALLBACK_MODE_UNIFORM = 0;
const int REGIR_LOCAL_LIGHT_FALLBACK_MODE_POWER_RIS = 1;

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

    candidateReservoir.M += 1.0f;
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

bool CandidateReservoir_addReservoir(
    inout RTXDI_DIReservoir candidateReservoir,
    float random,
    RTXDI_DIReservoir otherReservoir)
{
    float sampleWeight = CandidateReservoir_getTotalWeight(otherReservoir);
    sampleWeight = (isnan(sampleWeight) || isinf(sampleWeight) || sampleWeight < 0.0f) ? 0.0f : sampleWeight;
    candidateReservoir.M += max(otherReservoir.M, 0.0f);
    CandidateReservoir_setTotalWeight(
        candidateReservoir,
        CandidateReservoir_getTotalWeight(candidateReservoir) + sampleWeight
    );

    bool selected = (sampleWeight > 0.0f)
        && (random * CandidateReservoir_getTotalWeight(candidateReservoir) < sampleWeight);
    if (selected) {
        candidateReservoir.lightData = otherReservoir.lightData;
        candidateReservoir.uvData = otherReservoir.uvData;
        candidateReservoir.targetPdf = otherReservoir.targetPdf;
        candidateReservoir.packedVisibility = otherReservoir.packedVisibility;
        candidateReservoir.age = otherReservoir.age;
        candidateReservoir.spatialDistance = otherReservoir.spatialDistance;
        candidateReservoir.canonicalWeight = otherReservoir.canonicalWeight;
        candidateReservoir.transportAux0 = otherReservoir.transportAux0;
        candidateReservoir.transportAux1 = otherReservoir.transportAux1;
        candidateReservoir.pixelSampleUV = otherReservoir.pixelSampleUV;
        candidateReservoir.lensSampleUV = otherReservoir.lensSampleUV;
        candidateReservoir.pathSample = otherReservoir.pathSample;
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
    float candidateTotalWeight =
        CandidateReservoir_getTotalWeight(candidateReservoir) * candidateReservoir.targetPdf;
    float weight = sampleMIS * candidateTotalWeight;
    pathReservoir.M += max(candidateReservoir.M, 0.0f);
    PathReservoir_setTotalWeight(pathReservoir, PathReservoir_getTotalWeight(pathReservoir) + weight);
    float accumulatedConfidence = PathReservoir_getConfidence(pathReservoir) + 1.0f;

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
    PathReservoir_setConfidence(pathReservoir, accumulatedConfidence);
    return selected;
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

    float tileRnd = RTXDI_GetNextRandom(coherentRng);
    uint tileIndex = uint(tileRnd * float(params.tileCount));
    risTileInfo.risTileOffset = tileIndex * params.tileSize + params.bufferOffset;
    return risTileInfo;
}

RTXDI_RISTileInfo RTXDI_SelectLocalLightReGIRRISTile(int cellIndex)
{
    RTXDI_RISTileInfo tileInfo;
    tileInfo.risTileOffset = uint(cellIndex) * uint(ph_regir_lights_per_cell) + uint(ph_regir_ris_buffer_offset);
    tileInfo.risTileSize = uint(ph_regir_lights_per_cell);
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
    vec3 rand = vec3(RTXDI_GetNextRandom(rng), RTXDI_GetNextRandom(rng), RTXDI_GetNextRandom(rng));
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
    inout RTXDI_RandomSamplerState regirLookupRng,
    RTXDI_LightBufferRegion localLightBufferRegion,
    RTXDI_RISBufferSegmentParameters localLightRISBufferSegmentParams,
    RAB_Surface surface)
{
    int cellIndex = -1;
    // RTXDI_CalculateReGIRCellIndex: jitter the surface world position with the
    // lookup RNG, then map that jittered world position to a ReGIR cell.
    if (regir_resolve_cell(surface.worldPos, RAB_GetSurfaceNormal(surface), regirLookupRng, cellIndex) && cellIndex >= 0) {
        RTXDI_LocalLightSelectionContext ctx = RTXDI_InitializeLocalLightSelectionContextRIS(
            RTXDI_SelectLocalLightReGIRRISTile(cellIndex));
        ctx.proposalFamily = LT_PROPOSAL_FAMILY_REGIR_RIS;
        ctx.lightBufferRegion = localLightBufferRegion;
        return ctx;
    }

    if (ph_regir_local_light_sampling_fallback_mode == REGIR_LOCAL_LIGHT_FALLBACK_MODE_POWER_RIS)
    {
        RTXDI_LocalLightSelectionContext ctx = RTXDI_InitializeLocalLightSelectionContextRIS(
            coherentRng,
            localLightRISBufferSegmentParams);
        ctx.proposalFamily = LT_PROPOSAL_FAMILY_POWER_RIS;
        return ctx;
    }

    return RTXDI_InitializeLocalLightSelectionContextUniform(localLightBufferRegion);
}

RTXDI_LocalLightSelectionContext RTXDI_InitializeLocalLightSelectionContextFallback(
    inout RTXDI_RandomSamplerState coherentRng,
    RTXDI_LightBufferRegion localLightBufferRegion,
    RTXDI_RISBufferSegmentParameters localLightRISBufferSegmentParams)
{
    RTXDI_LocalLightSelectionContext ctx = RTXDI_InitializeLocalLightSelectionContextRIS(coherentRng, localLightRISBufferSegmentParams);
    ctx.proposalFamily = LT_PROPOSAL_FAMILY_POWER_RIS;
    return ctx;
}

RTXDI_LocalLightSelectionContext RTXDI_InitializeLocalLightSelectionContext(
    inout RTXDI_RandomSamplerState coherentRng,
    inout RTXDI_RandomSamplerState regirLookupRng,
    int localLightSamplingMode,
    RTXDI_LightBufferRegion localLightBufferRegion,
    RTXDI_RISBufferSegmentParameters localLightRISBufferSegmentParams,
    RAB_Surface surface)
{
    if (localLightSamplingMode == RTXDI_LOCAL_LIGHT_SAMPLING_REGIR_RIS)
    {
        return RTXDI_InitializeLocalLightSelectionContextReGIRRIS(
            coherentRng,
            regirLookupRng,
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

    if (localLightSamplingMode == RTXDI_LOCAL_LIGHT_SAMPLING_FAST_RANDOM)
    {
        RTXDI_LocalLightSelectionContext ctx =
            RTXDI_InitializeLocalLightSelectionContextUniform(localLightBufferRegion);
        ctx.proposalFamily = LT_PROPOSAL_FAMILY_FAST_RANDOM;
        return ctx;
    }

    if (localLightSamplingMode == RTXDI_LOCAL_LIGHT_SAMPLING_UNIFORM)
    {
        return RTXDI_InitializeLocalLightSelectionContextUniform(localLightBufferRegion);
    }

    return lt_make_invalid_local_light_selection_context();
}

RTXDI_LocalLightSelectionContext RTXDI_InitializeLocalLightSelectionContext(
    inout RTXDI_RandomSamplerState coherentRng,
    int localLightSamplingMode,
    RTXDI_LightBufferRegion localLightBufferRegion,
    RTXDI_RISBufferSegmentParameters localLightRISBufferSegmentParams,
    RAB_Surface surface)
{
    RTXDI_RandomSamplerState regirLookupRng = coherentRng;
    return RTXDI_InitializeLocalLightSelectionContext(
        coherentRng,
        regirLookupRng,
        localLightSamplingMode,
        localLightBufferRegion,
        localLightRISBufferSegmentParams,
        surface);
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

    if (tileData.y == 0u
        || lightIndex >= uint(ph_light_count)
        || !(invSourcePdf > 0.0f)
        || isinf(invSourcePdf)
        || isnan(invSourcePdf))
    {
        lightIndex = 0u;
        invSourcePdf = 0.0f;
        return;
    }

    lightInfo = ((tileData.x & RTXDI_LIGHT_COMPACT_BIT) != 0u)
        ? RAB_LoadCompactLightInfo(risBufferPtr, int(lightIndex))
        : RAB_LoadLightInfo(int(lightIndex), false);
}

void RTXDI_RandomlySelectLocalLightFromRISTile(
    float rnd,
    const RTXDI_RISTileInfo risTileInfo,
    out RAB_LightInfo lightInfo,
    out uint lightIndex,
    out float invSourcePdf)
{
    lightInfo = RAB_EmptyLightInfo();
    lightIndex = 0u;
    invSourcePdf = 0.0f;

    if (risTileInfo.risTileSize == 0u) {
        return;
    }

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
    uv.x = RTXDI_GetNextRandom(rng);
    uv.y = RTXDI_GetNextRandom(rng);
    return uv;
}

RTXDI_DIReservoir InitialCandidates_SampleLocalLightsAtTime(
    inout RTXDI_RandomSamplerState rng,
    inout RTXDI_RandomSamplerState coherentRng,
    inout RTXDI_RandomSamplerState regirLookupRng,
    RAB_Surface surface,
    RTXDI_DIInitialSamplingParameters initialSamplingParams,
    float pathTime,
    out RAB_LightSample o_selectedSample,
    out vec3 o_selectedIrradiance,
    out vec3 o_selectedEarlyThroughput)
{
    o_selectedSample = RAB_EmptyLightSample();
    o_selectedIrradiance = vec3(0.0f);
    o_selectedEarlyThroughput = vec3(0.0f);

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
    bool fastRandomMode = (localLightSamplingMode == RTXDI_LOCAL_LIGHT_SAMPLING_FAST_RANDOM);
    RTXDI_LocalLightSelectionContext lightSelectionContext = RTXDI_InitializeLocalLightSelectionContext(
        coherentRng,
        regirLookupRng,
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

        float rnd = RTXDI_GetNextRandom(rng);
        rnd = (rnd + float(i)) / float(initialSamplingParams.numLocalLightSamples);

        RTXDI_SelectNextLocalLight(lightSelectionContext, rnd, lightInfo, lightIndex, invSourcePdf);
        if (invSourcePdf <= 0.0f || lightIndex >= uint(ph_light_count))
        {
            continue;
        }

        // Minecraft block emitters are bridged as analytic point lights, so
        // local-light UVs do not affect the sampled position.
        vec2 uv = vec2(0.0f);
        vec3 sampledPosition = lightInfo.position;
        vec3 incidentRadiance;
        vec3 earlyThroughput;
        vec3 unshadowedIntegrand;
        RAB_LightSample candidateSample;
        if (fastRandomMode)
        {
            candidateSample = light_sample_new_at_position_fast_random(
                lightInfo,
                sampledPosition,
                surface,
                incidentRadiance,
                unshadowedIntegrand
            );
            earlyThroughput = vec3(1.0f);
        }
        else
        {
            candidateSample = light_sample_new_at_position_with_radiometry(
                lightInfo,
                sampledPosition,
                surface,
                incidentRadiance,
                earlyThroughput,
                unshadowedIntegrand
            );
        }
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

        vec3 sampleIrradiance = max(incidentRadiance, vec3(0.0f));
        vec3 sampleIntegrand = max(unshadowedIntegrand, vec3(0.0f));

        float risRnd = RTXDI_GetNextRandom(rng);

        // Reference parity (PathTracer.slang:208): each candidate draws its own
        // subpixel and lens sample from the path RNG so the selected reservoir
        // carries the exact domain coordinate of the winning candidate, without
        // a pixel-center fallback.
        vec2 candidatePixelSample = lt_area_random_pixel_sample(rng, lt_fragment_pixel_pos());
        vec2 candidateLensSample = lt_area_sample_lens_sample(rng);
        uint candidatePathSample = lt_make_path_sample_with_time(2u, lightSelectionContext.proposalFamily, pathTime);

        bool selected = CandidateReservoir_addVertex(
            state,
            risRnd,
            int(lightIndex),
            uv,
            1.0f / blendedSourcePdf,
            sampleIntegrand,
            vec3(1.0f),
            candidatePixelSample,
            candidateLensSample,
            candidatePathSample);
        if (selected)
        {
            o_selectedSample = candidateSample;
            o_selectedIrradiance = sampleIrradiance;
            o_selectedEarlyThroughput = earlyThroughput;
        }
    }

    RTXDI_FinalizeResampling(state, 1.0f, float(misData.numMisSamples));
    state.M = 1.0f;
    return state;
}

RTXDI_DIReservoir InitialCandidates_SampleLocalLights(
    inout RTXDI_RandomSamplerState rng,
    inout RTXDI_RandomSamplerState coherentRng,
    RAB_Surface surface,
    RTXDI_DIInitialSamplingParameters initialSamplingParams,
    out RAB_LightSample o_selectedSample,
    out vec3 o_selectedIrradiance,
    out vec3 o_selectedEarlyThroughput)
{
    RTXDI_RandomSamplerState regirLookupRng = coherentRng;
    return InitialCandidates_SampleLocalLightsAtTime(
        rng,
        coherentRng,
        regirLookupRng,
        surface,
        initialSamplingParams,
        0.0f,
        o_selectedSample,
        o_selectedIrradiance,
        o_selectedEarlyThroughput
    );
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

RTXDI_DIReservoir InitialCandidates_SampleBrdf(
    inout RTXDI_RandomSamplerState rng,
    RAB_Surface surface,
    int numSamples,
    RTXDI_InitialSamplingMisData misData,
    float brdfCutoff,
    float pathTime,
    out RAB_LightSample o_selectedSample,
    out vec3 o_selectedIrradiance,
    out vec3 o_selectedEarlyThroughput)
{
    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    o_selectedSample = lt_null_sample();
    o_selectedIrradiance = vec3(0.0f);
    o_selectedEarlyThroughput = vec3(0.0f);
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
        vec3 incidentRadiance;
        vec3 earlyThroughput;
        vec3 sampleIntegrand;
        RAB_LightSample brdfSample = light_sample_new_at_position_with_radiometry(
            hitLight,
            sampledPosition,
            surface,
            incidentRadiance,
            earlyThroughput,
            sampleIntegrand
        );
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
        uint candidatePathSample = lt_make_path_sample_with_time(1u, LT_PROPOSAL_FAMILY_BRDF, pathTime);

        bool selected = CandidateReservoir_addVertex(
            state,
            RTXDI_GetNextRandom(rng),
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
            o_selectedIrradiance = max(incidentRadiance, vec3(0.0f));
            o_selectedEarlyThroughput = earlyThroughput;
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
    vec3 localIrradiance;
    vec3 localEarlyThroughput;
    RTXDI_DIReservoir localReservoir = InitialCandidates_SampleLocalLights(
        rng,
        coherentRng,
        surface,
        initialSamplingParams,
        localSample,
        localIrradiance,
        localEarlyThroughput
    );

    RAB_LightSample infiniteSample = lt_null_sample();
    RTXDI_DIReservoir infiniteReservoir = RTXDI_SampleInfiniteLights(surface, int(initialSamplingParams.numInfiniteLightSamples));

    RAB_LightSample environmentSample = lt_null_sample();
    RTXDI_DIReservoir environmentReservoir = RTXDI_SampleEnvironmentMap(surface, int(initialSamplingParams.numEnvironmentSamples));

    RAB_LightSample brdfSample = lt_null_sample();
    vec3 brdfIrradiance;
    vec3 brdfEarlyThroughput;
    RTXDI_DIReservoir brdfReservoir = InitialCandidates_SampleBrdf(
        rng,
        surface,
        int(initialSamplingParams.numBrdfSamples),
        misData,
        initialSamplingParams.brdfCutoff,
        0.0f,
        brdfSample,
        brdfIrradiance,
        brdfEarlyThroughput);

    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    bool selectLocal = RTXDI_CombineDIReservoirs(state, localReservoir, 0.5f, localReservoir.targetPdf);
    bool selectInfinite = RTXDI_CombineDIReservoirs(state, infiniteReservoir, RTXDI_GetNextRandom(rng), infiniteReservoir.targetPdf);
    bool selectEnvironment = RTXDI_CombineDIReservoirs(state, environmentReservoir, RTXDI_GetNextRandom(rng), environmentReservoir.targetPdf);
    bool selectBrdf = RTXDI_CombineDIReservoirs(state, brdfReservoir, RTXDI_GetNextRandom(rng), brdfReservoir.targetPdf);

    RTXDI_FinalizeResampling(state, 1.0f, 1.0f);
    state.M = 1.0f;

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

    if (initialSamplingParams.enableInitialVisibility != 0u
        && RTXDI_IsValidDIReservoir(state)
        && o_lightSample.index >= 0)
    {
        // RTXDI final-visibility contract: capture RGB transmittance so colored-glass
        // tinting reaches ResolveReSTIR. Pass a copy because the trace rewrites the
        // sample's dir/color/weight.
        RAB_LightSample lightSampleCopy = o_lightSample;
        vec3 transmittance = lt_trace_final_visibility_transmittance(lightSampleCopy, surface, 0.001f);
        if (ph_luminance(transmittance) <= 0.0f)
        {
            RTXDI_StoreVisibilityInDIReservoir(state, vec3(0.0f), true);
            state.weightSum = 0.0f;
        }
        else
        {
            float previousPHat = state.targetPdf;
            vec3 selectedIntegrand = PathReservoir_getIntegrand(state) * transmittance;
            float selectedPHat = ph_luminance(max(selectedIntegrand, vec3(0.0f)));
            if (previousPHat > 0.0f) {
                state.weightSum *= selectedPHat / previousPHat;
            } else {
                state.weightSum = 0.0f;
            }
            PathReservoir_setIntegrand(state, selectedIntegrand);
            state.targetPdf = selectedPHat;
            RTXDI_StoreVisibilityInDIReservoir(state, transmittance, true);
        }
    }

    return state;
}

RTXDI_DIReservoir InitialCandidates_SampleLightsForSurface(
    inout RTXDI_RandomSamplerState rng,
    inout RTXDI_RandomSamplerState coherentRng,
    inout RTXDI_RandomSamplerState regirLookupRng,
    RAB_Surface surface,
    RTXDI_DIInitialSamplingParameters initialSamplingParams,
    float pathTime,
    out RAB_LightSample o_lightSample,
    out vec3 o_selectedIrradiance,
    out vec3 o_selectedEarlyThroughput)
{
    if (!RAB_IsSurfaceValid(surface))
    {
        o_lightSample = RAB_EmptyLightSample();
        o_selectedIrradiance = vec3(0.0f);
        o_selectedEarlyThroughput = vec3(0.0f);
        return RTXDI_EmptyDIReservoir();
    }

    RAB_LightSample localSample = lt_null_sample();
    vec3 localIrradiance;
    vec3 localEarlyThroughput;
    RTXDI_DIReservoir localReservoir = InitialCandidates_SampleLocalLightsAtTime(
        rng,
        coherentRng,
        regirLookupRng,
        surface,
        initialSamplingParams,
        pathTime,
        localSample,
        localIrradiance,
        localEarlyThroughput
    );

    RTXDI_DIReservoir selectedReservoir = RTXDI_EmptyDIReservoir();
    bool selectLocal = RTXDI_CombineDIReservoirs(selectedReservoir, localReservoir, 0.5f, localReservoir.targetPdf);

    RAB_LightSample infiniteSample = lt_null_sample();
    bool selectInfinite = false;
    if (initialSamplingParams.numInfiniteLightSamples > 0u)
    {
        RTXDI_DIReservoir infiniteReservoir = RTXDI_SampleInfiniteLights(
            surface,
            int(initialSamplingParams.numInfiniteLightSamples)
        );
        selectInfinite = RTXDI_CombineDIReservoirs(selectedReservoir, infiniteReservoir, RTXDI_GetNextRandom(rng), infiniteReservoir.targetPdf);
    }

    RAB_LightSample environmentSample = lt_null_sample();
    bool selectEnvironment = false;
    if (initialSamplingParams.numEnvironmentSamples > 0u)
    {
        RTXDI_DIReservoir environmentReservoir = RTXDI_SampleEnvironmentMap(
            surface,
            int(initialSamplingParams.numEnvironmentSamples)
        );
        selectEnvironment = RTXDI_CombineDIReservoirs(selectedReservoir, environmentReservoir, RTXDI_GetNextRandom(rng), environmentReservoir.targetPdf);
    }

    RAB_LightSample brdfSample = lt_null_sample();
    vec3 brdfIrradiance = vec3(0.0f);
    vec3 brdfEarlyThroughput = vec3(0.0f);
    bool selectBrdf = false;
    if (initialSamplingParams.numBrdfSamples > 0u)
    {
        RTXDI_InitialSamplingMisData misData = RTXDI_ComputeInitialSamplingMisData(initialSamplingParams);
        RTXDI_DIReservoir brdfReservoir = InitialCandidates_SampleBrdf(
            rng,
            surface,
            int(initialSamplingParams.numBrdfSamples),
            misData,
            initialSamplingParams.brdfCutoff,
            pathTime,
            brdfSample,
            brdfIrradiance,
            brdfEarlyThroughput
        );
        selectBrdf = RTXDI_CombineDIReservoirs(selectedReservoir, brdfReservoir, RTXDI_GetNextRandom(rng), brdfReservoir.targetPdf);
    }

    RTXDI_FinalizeResampling(selectedReservoir, 1.0f, 1.0f);
    selectedReservoir.M = 1.0f;

    o_lightSample = RAB_EmptyLightSample();
    o_selectedIrradiance = vec3(0.0f);
    o_selectedEarlyThroughput = vec3(0.0f);
    if (selectLocal)
    {
        o_lightSample = localSample;
        o_selectedIrradiance = localIrradiance;
        o_selectedEarlyThroughput = localEarlyThroughput;
    }
    if (selectInfinite)
    {
        o_lightSample = infiniteSample;
    }
    if (selectEnvironment)
    {
        o_lightSample = environmentSample;
    }
    if (selectBrdf)
    {
        o_lightSample = brdfSample;
        o_selectedIrradiance = brdfIrradiance;
        o_selectedEarlyThroughput = brdfEarlyThroughput;
    }

    return selectedReservoir;
}

#endif
