#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 reservoir_sample_frag_out;
layout(location = 2) out vec4 reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"

float lt_di_boiling_filter_weight(RTXDI_DIReservoir reservoir) {
    return max(reservoir.weightSum, 0.0f);
}

bool lt_di_should_reject_boiling_reservoir(ivec2 pixelPosition, ivec2 reservoirPos, int activeCheckerboardField, RTXDI_DIReservoir reservoir) {
    float reservoirWeight = lt_di_boiling_filter_weight(reservoir);
    if (!(reservoirWeight > 0.0f)) {
        return false;
    }

    float nonzeroWeightSum = 0.0f;
    float nonzeroCount = 0.0f;

    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            ivec2 neighborPixel = pixelPosition + ivec2(dx, dy);
            if (!lt_is_viewport_uv_in_bounds(neighborPixel)) {
                continue;
            }

            RTXDI_ActivateCheckerboardPixel(neighborPixel, false, activeCheckerboardField);
            if (!lt_is_viewport_uv_in_bounds(neighborPixel)) {
                continue;
            }

            ivec2 neighborReservoirPos = RTXDI_PixelPosToReservoirPos(neighborPixel, activeCheckerboardField);
            if (neighborReservoirPos == reservoirPos) {
                continue;
            }

            RTXDI_DIReservoir neighborReservoir = RTXDI_LoadDIReservoir(
                lt_build_reservoir_buffer_parameters(),
                uvec2(neighborReservoirPos),
                lt_build_di_buffer_indices().temporalResamplingOutputBufferIndex
            );
            float neighborWeight = lt_di_boiling_filter_weight(neighborReservoir);
            if (neighborWeight > 0.0f) {
                nonzeroWeightSum += neighborWeight;
                nonzeroCount += 1.0f;
            }
        }
    }

    float averageNonzeroWeight = (nonzeroCount > 0.0f) ? (nonzeroWeightSum / nonzeroCount) : 0.0f;
    float filterStrength = clamp(lt_build_di_boiling_filter_parameters().boilingFilterStrength, 1e-6f, 1.0f);
    float boilingFilterMultiplier = 10.0f / filterStrength - 9.0f;
    return averageNonzeroWeight > 0.0f && reservoirWeight > averageNonzeroWeight * boilingFilterMultiplier;
}

void storeDIReservoir(RTXDI_DIReservoir reservoir) {
    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(reservoir);
}

void main() {
    ivec2 GlobalIndex = lt_current_reservoir_pos();
    if (!lt_is_active_reservoir_lane(GlobalIndex)) {
        storeDIReservoir(RTXDI_EmptyDIReservoir());
        return;
    }

    const RTXDI_RuntimeParameters params = lt_build_runtime_parameters();
    ivec2 pixelPosition = RTXDI_ReservoirPosToPixelPos(GlobalIndex, int(params.activeCheckerboardField));
    if (!lt_is_viewport_uv_in_bounds(pixelPosition)) {
        storeDIReservoir(RTXDI_EmptyDIReservoir());
        return;
    }

    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(
        uvec2(pixelPosition),
        params.frameIndex,
        RTXDI_DI_TEMPORAL_RESAMPLING_RANDOM_SEED
    );

    const RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    RAB_Surface surface = RAB_GetGBufferSurface(pixelPosition, false);
    RTXDI_DIReservoir temporalResult = RTXDI_EmptyDIReservoir();
    ivec2 temporalSamplePixelPos = ivec2(-1, -1);

    bool usePermutationSampling = false;
    if (restirDI.temporalResamplingParams.enablePermutationSampling != 0u)
    {
        usePermutationSampling = !IsComplexSurface(pixelPosition, surface);
    }

    if (RAB_IsSurfaceValid(surface))
    {
        RTXDI_DIReservoir curSample = RTXDI_LoadDIReservoir(
            restirDI.reservoirBufferParams,
            uvec2(GlobalIndex),
            restirDI.bufferIndices.initialSamplingOutputBufferIndex
        );

        vec4 motionData = texelFetch(radiosity_motion, pixelPosition, 0);
        vec3 motionVector = motionData.xyz;
        if (motionData.w > 0.5f)
        {
            // ph_compute_temporal_motion stores previousPixel - currentPixelCenter.
            // RTXDI DI temporal resampling expects previousPixel - pixelPosition.
            motionVector.xy += vec2(0.5f);
        }

        uint sourceBufferIndex = restirDI.bufferIndices.temporalResamplingInputBufferIndex;

        RTXDI_DITemporalResamplingParameters tParams = restirDI.temporalResamplingParams;
        tParams.enablePermutationSampling = usePermutationSampling ? 1u : 0u;

        RAB_LightSample selectedLightSample = RAB_EmptyLightSample();

        temporalResult = RTXDI_DITemporalResampling(
            uvec2(pixelPosition), surface, curSample,
            rng, params, restirDI.reservoirBufferParams,
            motionVector, sourceBufferIndex, tParams,
            temporalSamplePixelPos, selectedLightSample);

        if (restirDI.boilingFilterParams.enableBoilingFilter != 0u
            && RTXDI_IsValidDIReservoir(temporalResult)
            && lt_di_should_reject_boiling_reservoir(pixelPosition, GlobalIndex, int(params.activeCheckerboardField), temporalResult)) {
            temporalResult = RTXDI_EmptyDIReservoir();
        }
    }

    storeDIReservoir(temporalResult);
}
