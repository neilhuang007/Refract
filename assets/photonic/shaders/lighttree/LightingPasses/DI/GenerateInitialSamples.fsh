#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;
layout(location = 3) out vec4 initial_debug_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/light_tree.glsl"
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

    uint localLightCount = uint(max(ph_light_count, 0));
    if (localLightCount == 0u) {
        debugInfo.reason = LT_INITIAL_DEBUG_NO_LIGHTS;
        return debugInfo;
    }

    uint sampleCount = initialSamplingParams.numLocalLightSamples;
    if (sampleCount == 0u) {
        sampleCount = 4u;
    }
    if (sampleCount == 0u) {
        debugInfo.reason = LT_INITIAL_DEBUG_NO_LOCAL_SAMPLES;
        return debugInfo;
    }

    int positiveCandidateCount = 0;
    bool sawInvalidLightSelection = false;
    bool sawInvalidLightSample = false;
    bool sawZeroRadiance = false;
    bool sawZeroSourcePdf = false;
    bool sawNonFiniteSourcePdf = false;
    bool sawZeroTargetPdf = false;
    bool sawNonFiniteTargetPdf = false;
    RTXDI_DIReservoir debugState = RTXDI_EmptyDIReservoir();

    for (uint i = 0u; i < sampleCount; i++) {
        uint lightIndex = min(uint(floor(lt_next_random(coherentRng) * float(localLightCount))), localLightCount - 1u);
        RAB_LightInfo lightInfo = RAB_LoadLightInfo(int(lightIndex), false);
        if (lightInfo.index < 0) {
            sawInvalidLightSelection = true;
            continue;
        }

        vec2 uv = vec2(lt_next_random(rng), lt_next_random(rng));
        RAB_LightSample candidateSample = RAB_SamplePolymorphicLight(lightInfo, surface, uv);
        if (candidateSample.index < 0 || candidateSample.solidAnglePdf <= 0.0f) {
            sawInvalidLightSample = true;
            continue;
        }

        float radianceLuma = ph_luminance(max(candidateSample.color, vec3(0.0f)));
        if (radianceLuma <= 0.0f) {
            sawZeroRadiance = true;
            continue;
        }

        float sourcePdf = 1.0f / float(localLightCount);
        if (sourcePdf <= 0.0f) {
            sawZeroSourcePdf = true;
            continue;
        }
        if (!lt_is_finite_float(sourcePdf)) {
            sawNonFiniteSourcePdf = true;
            continue;
        }

        float targetPdf = lt_surface_target_pdf(surface, candidateSample);
        if (targetPdf <= 0.0f) {
            sawZeroTargetPdf = true;
            continue;
        }
        if (!lt_is_finite_float(targetPdf)) {
            sawNonFiniteTargetPdf = true;
            continue;
        }

        positiveCandidateCount++;
        debugState.M += 1.0f;
        debugState.weightSum += targetPdf / sourcePdf;
    }

    debugInfo.positiveCandidateFraction = float(positiveCandidateCount) / float(sampleCount);
    debugInfo.proposalValid = RTXDI_IsValidDIReservoir(debugState) ? 1.0f : 0.0f;
    debugInfo.proposalWeight = debugState.weightSum;

    if (positiveCandidateCount > 0) {
        debugInfo.reason = LT_INITIAL_DEBUG_SUCCESS;
    } else if (sawInvalidLightSelection) {
        debugInfo.reason = LT_INITIAL_DEBUG_INVALID_LIGHT_SELECTION;
    } else if (sawInvalidLightSample) {
        debugInfo.reason = LT_INITIAL_DEBUG_INVALID_LIGHT_SAMPLE;
    } else if (sawZeroRadiance) {
        debugInfo.reason = LT_INITIAL_DEBUG_ZERO_RADIANCE;
    } else if (sawZeroSourcePdf) {
        debugInfo.reason = LT_INITIAL_DEBUG_ZERO_SOURCE_PDF;
    } else if (sawNonFiniteSourcePdf) {
        debugInfo.reason = LT_INITIAL_DEBUG_NONFINITE_SOURCE_PDF;
    } else if (sawZeroTargetPdf) {
        debugInfo.reason = LT_INITIAL_DEBUG_ZERO_TARGET_PDF;
    } else if (sawNonFiniteTargetPdf) {
        debugInfo.reason = LT_INITIAL_DEBUG_NONFINITE_TARGET_PDF;
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
    RTXDI_DIReservoir reservoir = RTXDI_EmptyDIReservoir();

    if (RAB_IsSurfaceValid(surface)) {
        reservoir = RTXDI_EmptyDIReservoir();

        uint localLightCount = uint(max(ph_light_count, 0));
        RAB_LightSample selectedLightSample = RAB_EmptyLightSample();

        if (localLightCount > 0u) {
            uint sampleCount = restirDI.initialSamplingParams.numLocalLightSamples;
            if (sampleCount == 0u) {
                sampleCount = 4u;
            }

            for (uint i = 0u; i < sampleCount; ++i) {
                uint lightIndex = min(uint(floor(lt_next_random(tileRng) * float(localLightCount))), localLightCount - 1u);
                RAB_LightInfo lightInfo = RAB_LoadLightInfo(int(lightIndex), false);
                if (lightInfo.index < 0) {
                    continue;
                }

                vec2 uv = vec2(lt_next_random(rng), lt_next_random(rng));
                RAB_LightSample candidateSample = RAB_SamplePolymorphicLight(lightInfo, surface, uv);
                if (candidateSample.index < 0 || candidateSample.solidAnglePdf <= 0.0f) {
                    continue;
                }

                float targetPdf = lt_surface_target_pdf(surface, candidateSample);
                float sourcePdf = 1.0f / float(localLightCount);
                if (targetPdf <= 0.0f || sourcePdf <= 0.0f) {
                    continue;
                }

                bool selected = RTXDI_StreamSample(
                    reservoir,
                    candidateSample.index,
                    uv,
                    lt_next_random(rng),
                    targetPdf,
                    1.0f / sourcePdf
                );
                if (selected) {
                    selectedLightSample = candidateSample;
                }
            }

            RTXDI_FinalizeResampling(reservoir, 1.0f, max(reservoir.M, 1.0f));
            reservoir.M = 1.0f;
            lt_area_finalize_candidate(reservoir, lt_fragment_pixel_pos(), 2u);

            if (restirDI.initialSamplingParams.enableInitialVisibility != 0u
                && RTXDI_IsValidDIReservoir(reservoir)
                && selectedLightSample.index >= 0)
            {
                if (!RAB_GetConservativeVisibility(surface, selectedLightSample)) {
                    RTXDI_StoreVisibilityInDIReservoir(reservoir, vec3(0.0f), true);
                }
            }
        }
        reservoir.spatialDistance = ivec2(0);
    }

    debugInfo.proposalValid = RTXDI_IsValidDIReservoir(reservoir) ? 1.0f : 0.0f;
    debugInfo.proposalWeight = reservoir.weightSum;

    storeDIReservoir(reservoir, debugInfo);
}
