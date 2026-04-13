#ifndef PHOTONICS_RESTIR_DI_SPATIAL_IMPL_GLSL
#define PHOTONICS_RESTIR_DI_SPATIAL_IMPL_GLSL

RTXDI_DIReservoir RTXDI_DISpatialResampling(
    uvec2 pixelPosition,
    RAB_Surface centerSurface,
    RTXDI_DIReservoir centerSample,
    inout RTXDI_RandomSamplerState rng,
    RTXDI_RuntimeParameters params,
    RTXDI_ReservoirBufferParameters reservoirParams,
    uint sourceBufferIndex,
    RTXDI_DISpatialResamplingParameters sparams,
    inout RAB_LightSample selectedLightSample)
{
    if (sparams.biasCorrectionMode == uint(RTXDI_BIAS_CORRECTION_PAIRWISE))
    {
        return RTXDI_DISpatialResamplingWithPairwiseMIS(pixelPosition, centerSurface,
            centerSample, rng, params, reservoirParams, sourceBufferIndex, sparams, selectedLightSample);
    }

    RTXDI_DIReservoir state = RTXDI_EmptyDIReservoir();
    int selected = -1;
    RAB_LightInfo selectedLight = RAB_EmptyLightInfo();

    if (RTXDI_IsValidDIReservoir(centerSample))
    {
        selectedLight = RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(centerSample), false);
    }

    RTXDI_CombineDIReservoirs(state, centerSample, 0.5f, centerSample.targetPdf);

    uint startIdx = uint(lt_next_random(rng) * float(params.neighborOffsetMask));

    uint numSpatialSamples = sparams.numSamples;
    if (centerSample.M < float(sparams.targetHistoryLength))
        numSpatialSamples = max(sparams.numDisocclusionBoostSamples, numSpatialSamples);

    numSpatialSamples = min(numSpatialSamples, 32u);

    uint cachedResult = 0u;

    for (uint i = 0u; i < numSpatialSamples; ++i)
    {
        uint sampleIdx = (startIdx + i) & params.neighborOffsetMask;
        ivec2 spatialOffset = ivec2(lt_load_neighbor_offset(int(sampleIdx)) * sparams.samplingRadius);
        ivec2 idx = ivec2(pixelPosition) + spatialOffset;

        idx = RAB_ClampSamplePositionIntoView(idx, false);

        RTXDI_ActivateCheckerboardPixel(idx, false, int(params.activeCheckerboardField));

        RAB_Surface neighborSurface = RAB_GetGBufferSurface(idx, false);

        if (!RAB_IsSurfaceValid(neighborSurface))
            continue;

        if (!RTXDI_IsValidNeighbor(RAB_GetSurfaceNormal(centerSurface), RAB_GetSurfaceNormal(neighborSurface),
            RAB_GetSurfaceLinearDepth(centerSurface), RAB_GetSurfaceLinearDepth(neighborSurface),
            sparams.normalThreshold, sparams.depthThreshold))
            continue;

        if (sparams.enableMaterialSimilarityTest != 0u && !RAB_AreMaterialsSimilar(RAB_GetMaterial(centerSurface), RAB_GetMaterial(neighborSurface)))
            continue;

        uvec2 neighborReservoirPos = uvec2(RTXDI_PixelPosToReservoirPos(idx, int(params.activeCheckerboardField)));

        RTXDI_DIReservoir neighborSample = RTXDI_LoadDIReservoir(reservoirParams,
            neighborReservoirPos, sourceBufferIndex);
        neighborSample.spatialDistance += spatialOffset;

        cachedResult |= (1u << i);

        RAB_LightInfo candidateLight = RAB_EmptyLightInfo();

        float neighborWeight = 0.0f;
        RAB_LightSample candidateLightSample = RAB_EmptyLightSample();
        if (RTXDI_IsValidDIReservoir(neighborSample))
        {
            if (sparams.discountNaiveSamples != 0u && neighborSample.M <= 2.0f)
                continue;

            candidateLight = RAB_LoadLightInfo(RTXDI_GetDIReservoirLightIndex(neighborSample), false);

            candidateLightSample = RAB_SamplePolymorphicLight(
                candidateLight, centerSurface, RTXDI_GetDIReservoirSampleUV(neighborSample));

            neighborWeight = RAB_GetLightSampleTargetPdfForSurface(candidateLightSample, centerSurface);
        }

        if (RTXDI_CombineDIReservoirs(state, neighborSample, lt_next_random(rng), neighborWeight))
        {
            selected = int(i);
            selectedLight = candidateLight;
            selectedLightSample = candidateLightSample;
        }
    }

    if (RTXDI_IsValidDIReservoir(state))
    {
        if (sparams.biasCorrectionMode >= uint(RTXDI_BIAS_CORRECTION_BASIC))
        {
            float pi = state.targetPdf;
            float piSum = state.targetPdf * centerSample.M;

            for (uint i = 0u; i < numSpatialSamples; ++i)
            {
                if ((cachedResult & (1u << i)) == 0u)
                    continue;

                uint sampleIdx = (startIdx + i) & params.neighborOffsetMask;
                ivec2 idx = ivec2(pixelPosition) + ivec2(lt_load_neighbor_offset(int(sampleIdx)) * sparams.samplingRadius);

                idx = RAB_ClampSamplePositionIntoView(idx, false);

                RTXDI_ActivateCheckerboardPixel(idx, false, int(params.activeCheckerboardField));

                RAB_Surface neighborSurface = RAB_GetGBufferSurface(idx, false);

                const RAB_LightSample selectedSampleAtNeighbor = RAB_SamplePolymorphicLight(
                    selectedLight, neighborSurface, RTXDI_GetDIReservoirSampleUV(state));

                float ps = RAB_GetLightSampleTargetPdfForSurface(selectedSampleAtNeighbor, neighborSurface);

                if (sparams.biasCorrectionMode == uint(RTXDI_BIAS_CORRECTION_RAY_TRACED) && ps > 0.0f)
                {
                    if (!RAB_GetConservativeVisibility(neighborSurface, selectedSampleAtNeighbor))
                    {
                        ps = 0.0f;
                    }
                }

                uvec2 neighborReservoirPos = uvec2(RTXDI_PixelPosToReservoirPos(idx, int(params.activeCheckerboardField)));

                RTXDI_DIReservoir neighborSample = RTXDI_LoadDIReservoir(reservoirParams,
                    neighborReservoirPos, sourceBufferIndex);

                pi = (selected == int(i)) ? ps : pi;
                piSum += ps * neighborSample.M;
            }

            RTXDI_FinalizeResampling(state, pi, piSum);
        }
        else
        {
            RTXDI_FinalizeResampling(state, 1.0f, state.M);
        }
    }

    return state;
}

#endif
