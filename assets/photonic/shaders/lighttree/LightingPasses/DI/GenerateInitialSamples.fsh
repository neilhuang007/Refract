#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;
layout(location = 3) out vec4 initial_debug_frag_out;

#include "/photonics/common/header.glsl"
 #include "/photonics/lighttree/restir_di_bridge.glsl"

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
    ivec2 pixelPosition,
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

    RTXDI_RandomSamplerState previewRng = rng;
    RTXDI_RandomSamplerState previewCoherentRng = coherentRng;
    RAB_LightSample selectedSample = RAB_EmptyLightSample();
    RTXDI_DIReservoir previewReservoir = RTXDI_SampleLightsForSurface(
        previewRng,
        previewCoherentRng,
        surface,
        initialSamplingParams,
        selectedSample
    );

    debugInfo.proposalValid = RTXDI_IsValidDIReservoir(previewReservoir) ? 1.0f : 0.0f;
    debugInfo.proposalWeight = previewReservoir.weightSum;

    if (RTXDI_IsValidDIReservoir(previewReservoir)) {
        debugInfo.reason = LT_INITIAL_DEBUG_SUCCESS;
        debugInfo.positiveCandidateFraction = 1.0f;
        return debugInfo;
    }

    if (selectedSample.index < 0) {
        debugInfo.reason = LT_INITIAL_DEBUG_INVALID_LIGHT_SAMPLE;
        return debugInfo;
    }

    float radianceLuma = ph_luminance(max(selectedSample.color, vec3(0.0f)));
    if (radianceLuma <= 0.0f) {
        debugInfo.reason = LT_INITIAL_DEBUG_ZERO_RADIANCE;
        return debugInfo;
    }

    float targetPdf = lt_surface_target_pdf(surface, selectedSample);
    if (!lt_is_finite_float(targetPdf)) {
        debugInfo.reason = LT_INITIAL_DEBUG_NONFINITE_TARGET_PDF;
        return debugInfo;
    }
    if (targetPdf <= 0.0f) {
        debugInfo.reason = LT_INITIAL_DEBUG_ZERO_TARGET_PDF;
        return debugInfo;
    }

    debugInfo.reason = LT_INITIAL_DEBUG_ZERO_SOURCE_PDF;
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
        pixelPosition,
        restirDI.initialSamplingParams
    );
    RTXDI_DIReservoir reservoir = RTXDI_EmptyDIReservoir();

    if (RAB_IsSurfaceValid(surface)) {
        RAB_LightSample selectedLightSample = RAB_EmptyLightSample();
        reservoir = RTXDI_SampleLightsForSurface(
            rng,
            tileRng,
            surface,
            restirDI.initialSamplingParams,
            selectedLightSample
        );
        reservoir.spatialDistance = ivec2(0);
    }

    debugInfo.proposalValid = RTXDI_IsValidDIReservoir(reservoir) ? 1.0f : 0.0f;
    debugInfo.proposalWeight = reservoir.weightSum;

    storeDIReservoir(reservoir, debugInfo);
}
