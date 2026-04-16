#ifndef PHOTONICS_RESTIR_DI_BRIDGE_GLSL
#define PHOTONICS_RESTIR_DI_BRIDGE_GLSL

#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_gi_initial_sampling_impl.glsl"
#include "/photonics/lighttree/restir_di_temporal.glsl"
#include "/photonics/lighttree/restir_di_spatial.glsl"
#include "/photonics/lighttree/restir_di_spatial_impl.glsl"

float lt_area_spatial_domain_compatibility(
    RTXDI_DIReservoir canonicalReservoir,
    RTXDI_DIReservoir neighborReservoir)
{
    // Fully disabled compatibility kept for reference:
    // return 1.0f;

    // Original heuristic kept for reference:
    // if (!lt_area_has_valid_domain(canonicalReservoir) || !lt_area_has_valid_domain(neighborReservoir)) {
    //     return 1.0f;
    // }
    // vec2 pixelDelta = (canonicalReservoir.pixelSampleUV - neighborReservoir.pixelSampleUV) * vec2(viewWidth, viewHeight);
    // float pixelCompatibility = max(0.0f, 1.0f - length(pixelDelta) / 2.5f);
    // float lensCompatibility = max(0.0f, 1.0f - length(canonicalReservoir.lensSampleUV - neighborReservoir.lensSampleUV) / 0.5f);
    // return max(pixelCompatibility * lensCompatibility, 0.0f);

    if (!lt_area_has_valid_domain(canonicalReservoir) || !lt_area_has_valid_domain(neighborReservoir)) {
        return 1.0f;
    }

    vec2 pixelDelta = (canonicalReservoir.pixelSampleUV - neighborReservoir.pixelSampleUV) * vec2(viewWidth, viewHeight);
    float pixelCompatibility = max(0.0f, 1.0f - length(pixelDelta) / 3.5f);
    float lensCompatibility = max(0.0f, 1.0f - length(canonicalReservoir.lensSampleUV - neighborReservoir.lensSampleUV) / 0.75f);
    return clamp(max(pixelCompatibility * lensCompatibility, 0.0f), 0.35f, 1.0f);
}

RTXDI_DIReservoir lt_area_spatial_resampling(
    ivec2 pixelPosition,
    RAB_Surface centerSurface,
    RTXDI_DIReservoir centerSample,
    inout RTXDI_RandomSamplerState rng)
{
    if (!RAB_IsSurfaceValid(centerSurface) || !RTXDI_IsValidDIReservoir(centerSample)) {
        return RTXDI_EmptyDIReservoir();
    }

    RTXDI_Parameters restirDI = lt_build_restir_di_parameters();
    RTXDI_RuntimeParameters params = lt_build_runtime_parameters();
    RTXDI_DISpatialResamplingParameters sparams = restirDI.spatialResamplingParams;
    bool useMFactor = (sparams.discountNaiveSamples == 0u);
    uint shiftMappingMode = (ph_area_restir_spatial_shift_mode <= 0.0f)
        ? AREA_RESTIR_SHIFT_MODE_ONLY_RECONNECTION
        : uint(clamp(ph_area_restir_spatial_shift_mode, 0.0f, 2.0f));

    RTXDI_DIReservoir canonicalReservoir = centerSample;
    lt_area_finalize_candidate(canonicalReservoir, pixelPosition, canonicalReservoir.pathSample);

    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    state.canonicalWeight = 0.0f;

    uint numSpatialSamples = (canonicalReservoir.M < float(sparams.targetHistoryLength))
        ? max(sparams.numDisocclusionBoostSamples, sparams.numSamples)
        : sparams.numSamples;

    uint startIdx = uint(lt_next_random(rng) * float(params.neighborOffsetMask));
    uint validSpatialSamples = 0u;
    float confidenceWeightSum = canonicalReservoir.M;

    for (uint i = 0u; i < numSpatialSamples; ++i) {
        uint sampleIdx = (startIdx + i) & params.neighborOffsetMask;
        ivec2 spatialOffset = ivec2(lt_load_neighbor_offset(int(sampleIdx)) * sparams.samplingRadius);
        ivec2 idx = pixelPosition + spatialOffset;
        idx = RAB_ClampSamplePositionIntoView(idx, false);

        RTXDI_ActivateCheckerboardPixel(idx, false, int(params.activeCheckerboardField));

        RAB_Surface neighborSurface = RAB_GetGBufferSurface(idx, false);
        if (!RAB_IsSurfaceValid(neighborSurface)) {
            continue;
        }

        if (!RTXDI_IsValidNeighbor(
            RAB_GetSurfaceNormal(centerSurface), RAB_GetSurfaceNormal(neighborSurface),
            RAB_GetSurfaceLinearDepth(centerSurface), RAB_GetSurfaceLinearDepth(neighborSurface),
            sparams.normalThreshold, sparams.depthThreshold)) {
            continue;
        }

        if (sparams.enableMaterialSimilarityTest != 0u
            && !RAB_AreMaterialsSimilar(RAB_GetMaterial(centerSurface), RAB_GetMaterial(neighborSurface))) {
            continue;
        }

        RTXDI_DIReservoir neighborSample = RTXDI_LoadDIReservoir(
            restirDI.reservoirBufferParams,
            uvec2(RTXDI_PixelPosToReservoirPos(idx, int(params.activeCheckerboardField))),
            restirDI.bufferIndices.spatialResamplingInputBufferIndex
        );
        neighborSample.spatialDistance += spatialOffset;

        if (RTXDI_IsValidDIReservoir(neighborSample)) {
            if (sparams.discountNaiveSamples != 0u && neighborSample.M <= 2.0f) {
                continue;
            }
            neighborSample.M = lt_spatial_neighbor_history_cap(
                canonicalReservoir,
                neighborSample,
                float(sparams.targetHistoryLength)
            );
        }

        validSpatialSamples++;

        if (neighborSample.M <= 0.0f) {
            continue;
        }

        lt_area_finalize_candidate(neighborSample, idx, neighborSample.pathSample);
        float domainCompatibility = lt_area_spatial_domain_compatibility(canonicalReservoir, neighborSample);
        if (domainCompatibility <= 0.0f) {
            continue;
        }

        confidenceWeightSum += neighborSample.M * domainCompatibility;
        area_resample_reservoir_pairwise_mis(
            state,
            canonicalReservoir,
            centerSurface,
            pixelPosition,
            neighborSample,
            neighborSurface,
            idx,
            useMFactor,
            confidenceWeightSum,
            domainCompatibility,
            false,
            shiftMappingMode,
            rng
        );
    }

    state.canonicalWeight = (validSpatialSamples == 0u) ? 1.0f : state.canonicalWeight;
    area_streaming_resample_finalize_mis(
        state,
        canonicalReservoir,
        canonicalReservoir.targetPdf,
        rng
    );

    state.weightSum = (state.targetPdf > 0.0f)
        ? (state.weightSum / state.targetPdf)
        : 0.0f;
    lt_area_finalize_candidate(state, pixelPosition, state.pathSample);

    if (!RTXDI_IsValidDIReservoir(state)) {
        return centerSample;
    }

    return state;
}

#endif

