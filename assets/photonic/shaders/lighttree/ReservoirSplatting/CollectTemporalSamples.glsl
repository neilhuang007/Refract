#ifndef PHOTONICS_RESERVOIR_SPLATTING_COLLECT_TEMPORAL_SAMPLES_GLSL
#define PHOTONICS_RESERVOIR_SPLATTING_COLLECT_TEMPORAL_SAMPLES_GLSL

#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"
#include "/photonics/lighttree/restir_di_spatial_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_shared.glsl"
#include "/photonics/lighttree/restir_di_temporal_shift_mapping.glsl"
#include "/photonics/lighttree/restir_di_scatter_impl.glsl"

float CollectTemporalSamples_bilinear_weight(vec2 fractionalCoord, int x, int y)
{
    return mix(float(1 - x), float(x), fractionalCoord.x)
        * mix(float(1 - y), float(y), fractionalCoord.y);
}

float CollectTemporalSamples_confidence_weight(float confidence)
{
    return lt_restir_temporal_use_confidence_weights() ? confidence : 1.0f;
}

float CollectTemporalSamples_reservoir_confidence(RTXDI_DIReservoir reservoir)
{
    return PathReservoir_getConfidence(reservoir);
}

ShiftedPathData CollectTemporalSamples_make_no_shift_path(
    ivec2 neighborPixel,
    RTXDI_DIReservoir neighborReservoir,
    ReconnectionData neighborReconnectionData)
{
    ShiftedPathData shiftedPath = lt_temporal_empty_shifted_path();
    shiftedPath.primaryHit = neighborReconnectionData.firstHit;
    shiftedPath.fractionalPixel = vec2(neighborPixel)
        + PathReservoir_getSubPixel(neighborReservoir, neighborPixel);
    shiftedPath.lensSample = neighborReconnectionData.lensSample;
    shiftedPath.firstRayDir = -neighborReconnectionData.firstWi;
    shiftedPath.subPixelJacobian = neighborReconnectionData.subPixelJacobian;
    shiftedPath.lensVertexJacobian = neighborReconnectionData.lensVertexJacobian;
    shiftedPath.secondaryPathJacobian = neighborReconnectionData.secondaryPathJacobian;
    shiftedPath.radiance = PathReservoir_getIntegrand(neighborReservoir);
    return shiftedPath;
}

ReconnectionData CollectTemporalSamples_update_reconnection(
    ReconnectionData sourceReconnectionData,
    ShiftedPathData shiftedPath,
    vec2 relativeSubPixel)
{
    ReconnectionData updatedReconnectionData =
        ReconnectionData_update(sourceReconnectionData, shiftedPath);
    updatedReconnectionData.subPixel = relativeSubPixel;
    updatedReconnectionData.lensSample = shiftedPath.lensSample;
    updatedReconnectionData.subPixelJacobian = shiftedPath.subPixelJacobian;
    updatedReconnectionData.lensVertexJacobian = shiftedPath.lensVertexJacobian;
    updatedReconnectionData.secondaryPathJacobian = shiftedPath.secondaryPathJacobian;
    return updatedReconnectionData;
}

void CollectTemporalSamples_storeResult(
    ivec2 currPixel,
    vec2 floatingCoord,
    RTXDI_DIReservoir reservoir,
    ReconnectionData reconnectionData)
{
    GatherData_storeFloatingCoords(currPixel, floatingCoord);

    float reconnectionTransportAux0;
    float reconnectionTransportAux1;
    scatter_pack_reconnection_fields(
        reconnectionData,
        reconnectionTransportAux0,
        reconnectionTransportAux1,
        intermediate_reconnection0_frag_out,
        intermediate_reconnection1_frag_out,
        intermediate_reconnection2_frag_out,
        intermediate_reconnection3_frag_out,
        intermediate_reconnection4_frag_out
    );

    intermediate_reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    intermediate_reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    intermediate_reservoir_meta_frag_out = PathReservoir_packMeta(reservoir);
}

void CollectTemporalSamples_store_empty_result()
{
    intermediate_reservoir_frag_out = rtxdi_pack_reservoir(RTXDI_EmptyDIReservoir());
    intermediate_reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(RTXDI_EmptyDIReservoir());
    intermediate_reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(RTXDI_EmptyDIReservoir());
    intermediate_reconnection0_frag_out = vec4(0.0f);
    intermediate_reconnection1_frag_out = vec4(0.0f);
    intermediate_reconnection2_frag_out = vec4(0.0f);
    intermediate_reconnection3_frag_out = vec4(0.0f);
    intermediate_reconnection4_frag_out = vec4(0.0f);
}

void CollectTemporalSamples_execute(ivec2 currPixel)
{
    if (texelFetch(radiosity_position, currPixel, 0).w == BACKGROUND_DEPTH)
    {
        GatherData_storeFloatingCoords(currPixel, vec2(-1.0f));
        CollectTemporalSamples_store_empty_result();
        return;
    }

    vec2 motionVector = GatherData_getMotionVector(currPixel);
    motionVector = (length(motionVector) < 1e-6f) ? vec2(0.0f) : motionVector;
    vec2 prevPixel = vec2(currPixel) + motionVector * vec2(viewWidth, viewHeight);

    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    ReconnectionData dstReconnectionData = ReconnectionData_init();
    vec2 dstFloatingCoord = vec2(-1.0f);
    float dstConfidence = 0.0f;

    if (any(lessThan(prevPixel, vec2(0.0f)))
        || any(greaterThanEqual(prevPixel, vec2(viewWidth, viewHeight))))
    {
        GatherData_storeFloatingCoords(currPixel, dstFloatingCoord);
        CollectTemporalSamples_store_empty_result();
        return;
    }

    RTXDI_RandomSamplerState rng = lt_init_random_sampler(uvec2(currPixel), uint(frameCounter), 2u);

    ivec2 prevPixelTopLeft = ivec2(floor(prevPixel));
    vec2 fractionalCoord = clamp(prevPixel - vec2(prevPixelTopLeft), vec2(0.0f), vec2(1.0f));
    int gatherOption = GatherData_getGatherOption();

    switch (gatherOption)
    {
    case 0:
    {
        dstFloatingCoord = prevPixel;

        float totalConfidence = 0.0f;
        for (int x = 0; x < 2; ++x)
        {
            for (int y = 0; y < 2; ++y)
            {
                ivec2 offset = ivec2(x, y);
                ivec2 neighborPixel = prevPixelTopLeft + offset;
                if (!lt_is_viewport_uv_in_bounds(neighborPixel))
                {
                    continue;
                }

                RTXDI_DIReservoir neighborReservoir = RTXDI_LoadPreviousDIReservoir(
                    lt_build_restir_di_parameters().reservoirBufferParams,
                    uvec2(neighborPixel)
                );
                vec2 relativeSubPixel = vec2(offset)
                    + PathReservoir_getSubPixel(neighborReservoir, neighborPixel)
                    - fractionalCoord;

                float bilinearWeight = CollectTemporalSamples_bilinear_weight(fractionalCoord, x, y);
                float neighborReservoirConfidence =
                    CollectTemporalSamples_reservoir_confidence(neighborReservoir);
                totalConfidence += bilinearWeight
                    * CollectTemporalSamples_confidence_weight(neighborReservoirConfidence);

                if (any(lessThan(relativeSubPixel, vec2(0.0f)))
                    || any(greaterThanEqual(relativeSubPixel, vec2(1.0f))))
                {
                    continue;
                }

                vec3 integrand = PathReservoir_getIntegrand(neighborReservoir);
                RTXDI_DIReservoir shiftedReservoir = neighborReservoir;
                PathReservoir_setSubPixel(shiftedReservoir, currPixel, relativeSubPixel);
                bool selected = lt_scatter_add_sample_from_reservoir(
                    dstReservoir,
                    dstConfidence,
                    1.0f,
                    integrand,
                    1.0f,
                    lt_scatter_compute_ucw(neighborReservoir, integrand),
                    neighborReservoirConfidence,
                    shiftedReservoir,
                    rng
                );
                if (selected)
                {
                    dstReconnectionData = RestirDI_loadPreviousFrameReconnection(neighborPixel);
                }
            }
        }

        PathReservoir_setConfidence(dstReservoir, totalConfidence);
        break;
    }
    case 1:
    {
        ivec2 roundedPrevPixel = ivec2(round(prevPixel));
        dstFloatingCoord = vec2(roundedPrevPixel);

        if (!lt_is_viewport_uv_in_bounds(roundedPrevPixel))
        {
            break;
        }

        dstReservoir = RTXDI_LoadPreviousDIReservoir(
            lt_build_restir_di_parameters().reservoirBufferParams,
            uvec2(roundedPrevPixel)
        );
        dstReconnectionData = RestirDI_loadPreviousFrameReconnection(roundedPrevPixel);
        break;
    }
    default:
    {
        dstFloatingCoord = prevPixel;
        bool lowMotionHistory = length(motionVector * vec2(viewWidth, viewHeight)) < 0.35f;

        float totalConfidence = 0.0f;
        for (int x = 0; x < 2; ++x)
        {
            for (int y = 0; y < 2; ++y)
            {
                ivec2 offset = ivec2(x, y);
                ivec2 neighborPixel = prevPixelTopLeft + offset;
                if (!lt_is_viewport_uv_in_bounds(neighborPixel))
                {
                    continue;
                }

                RTXDI_DIReservoir neighborReservoir = RTXDI_LoadPreviousDIReservoir(
                    lt_build_restir_di_parameters().reservoirBufferParams,
                    uvec2(neighborPixel)
                );
                ReconnectionData neighborReconnectionData =
                    RestirDI_loadPreviousFrameReconnection(neighborPixel);
                vec2 relativeSubPixel = vec2(offset)
                    + PathReservoir_getSubPixel(neighborReservoir, neighborPixel)
                    - fractionalCoord;
                float bilinearWeight = CollectTemporalSamples_bilinear_weight(fractionalCoord, x, y);
                float neighborReservoirConfidence =
                    CollectTemporalSamples_reservoir_confidence(neighborReservoir);
                totalConfidence += bilinearWeight
                    * CollectTemporalSamples_confidence_weight(neighborReservoirConfidence);
                bool stableMinecraftNeighbor = lowMotionHistory
                    && RTXDI_IsValidDIReservoir(neighborReservoir)
                    && neighborReservoirConfidence >= (PATH_RESERVOIR_CONFIDENCE_CAP * 0.5f);

                ivec2 requiredOffset = ivec2(0);
                if (relativeSubPixel.x < 0.0f) requiredOffset.x += 1;
                if (relativeSubPixel.x >= 1.0f) requiredOffset.x -= 1;
                if (relativeSubPixel.y < 0.0f) requiredOffset.y += 1;
                if (relativeSubPixel.y >= 1.0f) requiredOffset.y -= 1;
                relativeSubPixel += vec2(requiredOffset);

                requiredOffset += ivec2(1);
                int offsetIndex = requiredOffset.x + 3 * requiredOffset.y;
                bool noShiftNeeded = (offsetIndex == 4);
                offsetIndex = (offsetIndex > 4) ? (offsetIndex - 1) : offsetIndex;

                ShiftedPathData shiftedPath = noShiftNeeded
                    ? CollectTemporalSamples_make_no_shift_path(
                        neighborPixel,
                        neighborReservoir,
                        neighborReconnectionData
                    )
                    : lt_temporal_load_shifted_path(neighborPixel, offsetIndex);
                float shiftedJacobian = noShiftNeeded
                    ? 1.0f
                    : (shiftedPath.secondaryPathJacobian
                        / neighborReconnectionData.secondaryPathJacobian);

                vec3 integrand = PathReservoir_getIntegrand(neighborReservoir);
                float pHatSource = lt_scatter_radiance_phat(integrand);
                float sourceWeight = bilinearWeight
                    * pHatSource
                    * CollectTemporalSamples_confidence_weight(neighborReservoirConfidence);
                float totalPHat = sourceWeight;

                if (!stableMinecraftNeighbor)
                {
                    for (int tempX = 0; tempX < 2; ++tempX)
                    {
                        for (int tempY = 0; tempY < 2; ++tempY)
                        {
                            ivec2 tempOffset = ivec2(tempX, tempY);
                            ivec2 tempOffsetPixel = prevPixelTopLeft + tempOffset;
                            if (!lt_is_viewport_uv_in_bounds(tempOffsetPixel))
                            {
                                continue;
                            }

                            ivec2 diff = tempOffset - offset;
                            if (all(equal(diff, ivec2(0))))
                            {
                                continue;
                            }

                            float tempBilinearWeight =
                                CollectTemporalSamples_bilinear_weight(fractionalCoord, tempX, tempY);
                            ivec2 temp = diff + ivec2(1);
                            int tempIndex = temp.x + 3 * temp.y;
                            tempIndex = (tempIndex > 4) ? (tempIndex - 1) : tempIndex;

                            ShiftedPathData tempPath =
                                lt_temporal_load_shifted_path(neighborPixel, tempIndex);
                            float tempPHat = lt_scatter_radiance_phat(tempPath.radiance);
                            float tempJacobian = tempPath.secondaryPathJacobian
                                / neighborReconnectionData.secondaryPathJacobian;
                            float tempConfidence = CollectTemporalSamples_reservoir_confidence(
                                RTXDI_LoadPreviousDIReservoir(
                                    lt_build_restir_di_parameters().reservoirBufferParams,
                                    uvec2(tempOffsetPixel)
                                )
                            );

                            totalPHat += tempBilinearWeight
                                * tempPHat
                                * tempJacobian
                                * CollectTemporalSamples_confidence_weight(tempConfidence);
                        }
                    }
                }

                float misWeight = (totalPHat > 0.0f) ? (sourceWeight / totalPHat) : 0.0f;
                RTXDI_DIReservoir shiftedReservoir = neighborReservoir;
                PathReservoir_setSubPixel(shiftedReservoir, currPixel, relativeSubPixel);

                bool selected = lt_scatter_add_sample_from_reservoir(
                    dstReservoir,
                    dstConfidence,
                    misWeight,
                    shiftedPath.radiance,
                    shiftedJacobian,
                    lt_scatter_compute_ucw(neighborReservoir, integrand),
                    neighborReservoirConfidence,
                    shiftedReservoir,
                    rng
                );
                if (selected)
                {
                    dstReconnectionData = CollectTemporalSamples_update_reconnection(
                        neighborReconnectionData,
                        shiftedPath,
                        relativeSubPixel
                    );
                }
            }
        }

        PathReservoir_setConfidence(dstReservoir, totalConfidence);
        break;
    }
    }

    if (isnan(PathReservoir_getTotalWeight(dstReservoir)))
    {
        PathReservoir_setIntegrand(dstReservoir, vec3(0.0f));
        PathReservoir_setTotalWeight(dstReservoir, 0.0f);
        dstReconnectionData.subPixelJacobian = 1.0f;
        dstReconnectionData.lensVertexJacobian = 1.0f;
        dstReconnectionData.secondaryPathJacobian = 1.0f;
        dstReconnectionData.pathLength = 0u;
    }

    CollectTemporalSamples_storeResult(
        currPixel,
        dstFloatingCoord,
        dstReservoir,
        dstReconnectionData
    );
}

#endif
