#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;
layout(location = 3) out vec4 initial_debug_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"

void storeDIReservoir(RTXDI_DIReservoir reservoir) {
    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(reservoir);
}

const int LT_INITIAL_DEBUG_INVALID_SURFACE = 0;
const int LT_INITIAL_DEBUG_NO_LIGHTS = 1;
const int LT_INITIAL_DEBUG_NO_LOCAL_SAMPLES = 2;
const int LT_INITIAL_DEBUG_INVALID_LIGHT_SELECTION = 3;
const int LT_INITIAL_DEBUG_INVALID_LIGHT_SAMPLE = 4;
const int LT_INITIAL_DEBUG_ZERO_RADIANCE = 5;
const int LT_INITIAL_DEBUG_ZERO_SOURCE_PDF = 6;
const int LT_INITIAL_DEBUG_ZERO_TARGET_PDF = 7;
const int LT_INITIAL_DEBUG_NONFINITE_SOURCE_PDF = 8;
const int LT_INITIAL_DEBUG_NONFINITE_TARGET_PDF = 9;
const int LT_INITIAL_DEBUG_SUCCESS = 10;

struct LtInitialSamplingDebugInfo {
    int reason;
    float positiveCandidateFraction;
    float proposalValid;
    float proposalWeight;
};

bool lt_is_finite_float(float value) {
    return value == value && abs(value) < 3.402823466e+38f;
}

void storeDIReservoir(RTXDI_DIReservoir reservoir, LtInitialSamplingDebugInfo debugInfo) {
    storeDIReservoir(reservoir);
    initial_debug_frag_out = vec4(
        float(debugInfo.reason),
        debugInfo.positiveCandidateFraction,
        debugInfo.proposalValid,
        debugInfo.proposalWeight
    );
}

LtInitialSamplingDebugInfo lt_debug_diagnose_initial_local_samples(
    inout RTXDI_RandomSamplerState rng,
    inout RTXDI_RandomSamplerState coherentRng,
    RAB_Surface surface,
    RTXDI_DIInitialSamplingParameters initialSamplingParams)
{
    LtInitialSamplingDebugInfo debugInfo;
    debugInfo.reason = LT_INITIAL_DEBUG_INVALID_SURFACE;
    debugInfo.positiveCandidateFraction = 0.0f;
    debugInfo.proposalValid = 0.0f;
    debugInfo.proposalWeight = 0.0f;

    if (!RAB_IsSurfaceValid(surface)) {
        return debugInfo;
    }

    RTXDI_LightBufferRegion localLightBufferRegion = RTXDI_GetLocalLightBufferRegion();
    if (localLightBufferRegion.numLights == 0u) {
        debugInfo.reason = LT_INITIAL_DEBUG_NO_LIGHTS;
        return debugInfo;
    }

    if (initialSamplingParams.numLocalLightSamples == 0u) {
        debugInfo.reason = LT_INITIAL_DEBUG_NO_LOCAL_SAMPLES;
        return debugInfo;
    }

    RTXDI_InitialSamplingMisData misData = RTXDI_ComputeInitialSamplingMisData(initialSamplingParams);
    RTXDI_RISBufferSegmentParameters localLightRISBufferSegmentParams = RTXDI_GetLocalLightRISBufferSegmentParameters();
    RTXDI_LocalLightSelectionContext lightSelectionContext = RTXDI_InitializeLocalLightSelectionContext(
        coherentRng,
        int(initialSamplingParams.localLightSamplingMode),
        localLightBufferRegion,
        localLightRISBufferSegmentParams,
        surface
    );

    int positiveCandidateCount = 0;
    bool sawInvalidLightSelection = false;
    bool sawInvalidLightSample = false;
    bool sawZeroRadiance = false;
    bool sawZeroSourcePdf = false;
    bool sawNonFiniteSourcePdf = false;
    bool sawZeroTargetPdf = false;
    bool sawNonFiniteTargetPdf = false;
    RTXDI_DIReservoir debugState = RTXDI_EmptyDIReservoir();

    for (uint i = 0u; i < initialSamplingParams.numLocalLightSamples; i++) {
        uint lightIndex = 0u;
        RAB_LightInfo lightInfo = RAB_EmptyLightInfo();
        float invSourcePdf = 0.0f;

        float rnd = RTXDI_GetNextRandom(rng);
        rnd = (rnd + float(i)) / float(initialSamplingParams.numLocalLightSamples);
        RTXDI_SelectNextLocalLight(lightSelectionContext, rnd, lightInfo, lightIndex, invSourcePdf);
        if (lightInfo.index < 0 || invSourcePdf <= 0.0f) {
            sawInvalidLightSelection = true;
            continue;
        }

        vec2 uv = RTXDI_RandomlySelectLocalLightUV(rng);
        RAB_LightSample candidateSample = RAB_SamplePolymorphicLight(lightInfo, surface, uv);
        if (candidateSample.index < 0 || candidateSample.solidAnglePdf <= 0.0f) {
            sawInvalidLightSample = true;
            continue;
        }

        float radianceLuma = ph_luminance(max(candidateSample.color, vec3(0.0f)));
        if (radianceLuma <= 1e-6f) {
            sawZeroRadiance = true;
            continue;
        }

        float blendedSourcePdf = RTXDI_LightBrdfMisWeight(
            surface,
            candidateSample,
            1.0f / invSourcePdf,
            misData.localLightMisWeight,
            misData.brdfMisWeight,
            initialSamplingParams.brdfCutoff
        );
        if (!lt_is_finite_float(blendedSourcePdf)) {
            sawNonFiniteSourcePdf = true;
        } else if (blendedSourcePdf <= 0.0f) {
            sawZeroSourcePdf = true;
        }

        // float targetPdf = RAB_GetLightSampleTargetPdfForSurface(candidateSample, surface);
        float targetPdf = lt_debug_resolve_target_pdf(RAB_GetLightSampleTargetPdfForSurface(candidateSample, surface));
        if (!lt_is_finite_float(targetPdf)) {
            sawNonFiniteTargetPdf = true;
        } else if (targetPdf <= 0.0f) {
            sawZeroTargetPdf = true;
        }

        float invBlendedSourcePdf = 1.0f / blendedSourcePdf;
        float risWeight = targetPdf * invBlendedSourcePdf;
        float risRnd = RTXDI_GetNextRandom(rng);
        if (lt_is_finite_float(blendedSourcePdf) && blendedSourcePdf > 0.0f
            && lt_is_finite_float(targetPdf) && targetPdf > 0.0f
            && lt_is_finite_float(risWeight) && risWeight > 0.0f) {
            positiveCandidateCount++;
        } else {
            continue;
        }
        RTXDI_StreamSample(debugState, int(lightIndex), uv, risRnd, targetPdf, invBlendedSourcePdf);
    }

    RTXDI_FinalizeResampling(debugState, 1.0f, float(misData.numMisSamples));
    debugState.M = 1.0f;
    debugInfo.positiveCandidateFraction = float(positiveCandidateCount) / float(max(int(initialSamplingParams.numLocalLightSamples), 1));
    if (RTXDI_IsValidDIReservoir(debugState)) {
        debugInfo.reason = LT_INITIAL_DEBUG_SUCCESS;
    } else if (sawNonFiniteTargetPdf) {
        debugInfo.reason = LT_INITIAL_DEBUG_NONFINITE_TARGET_PDF;
    } else if (sawNonFiniteSourcePdf) {
        debugInfo.reason = LT_INITIAL_DEBUG_NONFINITE_SOURCE_PDF;
    } else if (sawZeroTargetPdf) {
        debugInfo.reason = LT_INITIAL_DEBUG_ZERO_TARGET_PDF;
    } else if (sawZeroSourcePdf) {
        debugInfo.reason = LT_INITIAL_DEBUG_ZERO_SOURCE_PDF;
    } else if (sawZeroRadiance) {
        debugInfo.reason = LT_INITIAL_DEBUG_ZERO_RADIANCE;
    } else if (sawInvalidLightSample) {
        debugInfo.reason = LT_INITIAL_DEBUG_INVALID_LIGHT_SAMPLE;
    } else if (sawInvalidLightSelection) {
        debugInfo.reason = LT_INITIAL_DEBUG_INVALID_LIGHT_SELECTION;
    }

    return debugInfo;
}

void main() {
    ivec2 GlobalIndex = lt_current_reservoir_pos();
    if (!lt_is_active_reservoir_lane(GlobalIndex)) {
        storeDIReservoir(RTXDI_EmptyDIReservoir(), LtInitialSamplingDebugInfo(LT_INITIAL_DEBUG_INVALID_SURFACE, 0.0f, 0.0f, 0.0f));
        return;
    }

    const RTXDI_RuntimeParameters params = lt_build_runtime_parameters();
    ivec2 pixelPosition = RTXDI_ReservoirPosToPixelPos(GlobalIndex, int(params.activeCheckerboardField));
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        storeDIReservoir(RTXDI_EmptyDIReservoir(), LtInitialSamplingDebugInfo(LT_INITIAL_DEBUG_INVALID_SURFACE, 0.0f, 0.0f, 0.0f));
        return;
    }

    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(uvec2(pixelPosition), params.frameIndex, RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED);
    RTXDI_RandomSamplerState tileRng = RTXDI_InitRandomSampler(uvec2(pixelPosition / RTXDI_TILE_SIZE_IN_PIXELS), params.frameIndex, RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED);

    const RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    RAB_Surface surface = RAB_GetGBufferSurface(pixelPosition, false);
    RTXDI_RandomSamplerState debugRng = rng;
    RTXDI_RandomSamplerState debugTileRng = tileRng;
    LtInitialSamplingDebugInfo debugInfo = lt_debug_diagnose_initial_local_samples(
        debugRng,
        debugTileRng,
        surface,
        restirDI.initialSamplingParams
    );
    RAB_LightSample lightSample = RAB_EmptyLightSample();
    RTXDI_DIReservoir reservoir = RTXDI_SampleLightsForSurface(
        rng,
        tileRng,
        surface,
        restirDI.initialSamplingParams,
        lightSample
    );

    debugInfo.proposalValid = RTXDI_IsValidDIReservoir(reservoir) ? 1.0f : 0.0f;
    debugInfo.proposalWeight = max(reservoir.weightSum, 0.0f);

    storeDIReservoir(reservoir, debugInfo);
}
