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

ShiftedPathData CollectTemporalSamples_make_no_shift_path(
    ivec2 neighborPixel,
    RTXDI_DIReservoir neighborReservoir,
    ReservoirSplattingReconnectionData neighborReconnectionData)
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

ReservoirSplattingReconnectionData CollectTemporalSamples_update_reconnection(
    ReservoirSplattingReconnectionData sourceReconnectionData,
    ShiftedPathData shiftedPath,
    vec2 relativeSubPixel)
{
    ReservoirSplattingReconnectionData updatedReconnectionData =
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
    ReservoirSplattingReconnectionData reconnectionData)
{
    lt_store_floating_coords(currPixel, floatingCoord);

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
    lt_store_floating_coords(currPixel, vec2(-1.0f));
    vec2 prevPixel = lt_temporal_previous_pixel_center(currPixel) - vec2(0.5f);
    if (any(lessThan(prevPixel, vec2(0.0f))))
    {
        CollectTemporalSamples_store_empty_result();
        return;
    }
    if (any(greaterThanEqual(prevPixel, vec2(viewWidth, viewHeight))))
    {
        CollectTemporalSamples_store_empty_result();
        return;
    }

    RTXDI_RandomSamplerState rng = lt_init_random_sampler(uvec2(currPixel), uint(frameCounter), 2u);
    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    ReservoirSplattingReconnectionData dstReconnectionData = ReservoirSplattingReconnectionData_init();
    float dstConfidence = 0.0f;

    ivec2 prevPixelTopLeft = ivec2(floor(prevPixel));
    vec2 fractionalCoord = clamp(prevPixel - vec2(prevPixelTopLeft), vec2(0.0f), vec2(1.0f));
    int gatherMode = lt_restir_temporal_gather_mode();

    if (gatherMode == 0)
    {
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

                float bilinearWeight = CollectTemporalSamples_bilinear_weight(fractionalCoord, x, y);
                RTXDI_DIReservoir neighborReservoir = RTXDI_LoadPreviousDIReservoir(
                    lt_build_restir_di_parameters().reservoirBufferParams,
                    uvec2(neighborPixel)
                );
                ReservoirSplattingReconnectionData neighborReconnectionData =
                    RestirDI_loadPreviousFrameReconnection(neighborPixel);
                float neighborConfidence = lt_scatter_reservoir_confidence(
                    neighborReservoir,
                    neighborReconnectionData
                );
                totalConfidence += bilinearWeight
                    * CollectTemporalSamples_confidence_weight(neighborConfidence);

                vec3 sourceIntegrand = PathReservoir_getIntegrand(neighborReservoir);
                vec2 relativeSubPixel = vec2(offset)
                    + PathReservoir_getSubPixel(neighborReservoir, neighborPixel)
                    - fractionalCoord;
                if (
                    !RTXDI_IsValidDIReservoir(neighborReservoir)
                    || ph_luminance(sourceIntegrand) <= 0.0f
                    || any(lessThan(relativeSubPixel, vec2(0.0f)))
                    || any(greaterThanEqual(relativeSubPixel, vec2(1.0f)))
                )
                {
                    continue;
                }

                RTXDI_DIReservoir shiftedReservoir = neighborReservoir;
                PathReservoir_setSubPixel(shiftedReservoir, currPixel, relativeSubPixel);
                bool selected = lt_scatter_add_sample_from_reservoir(
                    dstReservoir,
                    dstConfidence,
                    1.0f,
                    sourceIntegrand,
                    1.0f,
                    lt_scatter_compute_ucw(neighborReservoir, sourceIntegrand),
                    CollectTemporalSamples_confidence_weight(neighborConfidence),
                    shiftedReservoir,
                    rng
                );
                if (selected)
                {
                    dstReconnectionData = neighborReconnectionData;
                }
            }
        }

        PathReservoir_setConfidence(dstReservoir, totalConfidence);
        CollectTemporalSamples_storeResult(currPixel, prevPixel, dstReservoir, dstReconnectionData);
        return;
    }

    if (gatherMode == 1)
    {
        ivec2 roundedPrevPixel = ivec2(round(prevPixel));
        if (!lt_is_viewport_uv_in_bounds(roundedPrevPixel))
        {
            CollectTemporalSamples_storeResult(currPixel, vec2(roundedPrevPixel), dstReservoir, dstReconnectionData);
            return;
        }

        dstReservoir = RTXDI_LoadPreviousDIReservoir(
            lt_build_restir_di_parameters().reservoirBufferParams,
            uvec2(roundedPrevPixel)
        );
        dstReconnectionData = RestirDI_loadPreviousFrameReconnection(roundedPrevPixel);
        CollectTemporalSamples_storeResult(currPixel, vec2(roundedPrevPixel), dstReservoir, dstReconnectionData);
        return;
    }

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

            float bilinearWeight = CollectTemporalSamples_bilinear_weight(fractionalCoord, x, y);
            RTXDI_DIReservoir neighborReservoir = RTXDI_LoadPreviousDIReservoir(
                lt_build_restir_di_parameters().reservoirBufferParams,
                uvec2(neighborPixel)
            );
            ReservoirSplattingReconnectionData neighborReconnectionData =
                RestirDI_loadPreviousFrameReconnection(neighborPixel);
                float neighborConfidence = lt_scatter_reservoir_confidence(
                    neighborReservoir,
                    neighborReconnectionData
                );
                totalConfidence += bilinearWeight
                    * CollectTemporalSamples_confidence_weight(neighborConfidence);

            vec3 sourceIntegrand = PathReservoir_getIntegrand(neighborReservoir);
            if (!RTXDI_IsValidDIReservoir(neighborReservoir))
            {
                continue;
            }
            if (ph_luminance(sourceIntegrand) <= 0.0f)
            {
                continue;
            }

            vec2 relativeSubPixel = vec2(offset)
                + PathReservoir_getSubPixel(neighborReservoir, neighborPixel)
                - fractionalCoord;

            ivec2 requiredOffset = ivec2(0);
            if (relativeSubPixel.x < 0.0f)
            {
                requiredOffset.x += 1;
            }
            if (relativeSubPixel.x >= 1.0f)
            {
                requiredOffset.x -= 1;
            }
            if (relativeSubPixel.y < 0.0f)
            {
                requiredOffset.y += 1;
            }
            if (relativeSubPixel.y >= 1.0f)
            {
                requiredOffset.y -= 1;
            }
            relativeSubPixel += vec2(requiredOffset);

            ivec2 packedOffset = requiredOffset + ivec2(1);
            int packedOffsetIndex = packedOffset.x + 3 * packedOffset.y;
            bool noShiftNeeded = (packedOffsetIndex == 4);
            if (packedOffsetIndex > 4)
            {
                packedOffsetIndex -= 1;
            }

            ShiftedPathData shiftedPath = lt_temporal_empty_shifted_path();
            float shiftedJacobian = 1.0f;
            if (noShiftNeeded)
            {
                shiftedPath = CollectTemporalSamples_make_no_shift_path(
                    neighborPixel,
                    neighborReservoir,
                    neighborReconnectionData
                );
            }
            else
            {
                shiftedPath = lt_temporal_load_shifted_path(neighborPixel, packedOffsetIndex);
                shiftedJacobian = shiftedPath.secondaryPathJacobian
                    / neighborReconnectionData.secondaryPathJacobian;
            }

            float sourceWeight = bilinearWeight
                * lt_scatter_radiance_phat(sourceIntegrand)
                * CollectTemporalSamples_confidence_weight(neighborConfidence);
            float totalPHat = sourceWeight;

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

                    float tempBilinearWeight = CollectTemporalSamples_bilinear_weight(
                        fractionalCoord,
                        tempX,
                        tempY
                    );
                    ivec2 tempPackedOffset = diff + ivec2(1);
                    int tempPackedIndex = tempPackedOffset.x + 3 * tempPackedOffset.y;
                    if (tempPackedIndex > 4)
                    {
                        tempPackedIndex -= 1;
                    }

                    ShiftedPathData tempShiftedPath =
                        lt_temporal_load_shifted_path(neighborPixel, tempPackedIndex);
                    float tempPHat = lt_scatter_radiance_phat(tempShiftedPath.radiance);
                    float tempJacobian = tempShiftedPath.secondaryPathJacobian
                        / neighborReconnectionData.secondaryPathJacobian;
                    float tempConfidence = lt_scatter_reservoir_confidence(
                        RTXDI_LoadPreviousDIReservoir(
                            lt_build_restir_di_parameters().reservoirBufferParams,
                            uvec2(tempOffsetPixel)
                        ),
                        RestirDI_loadPreviousFrameReconnection(tempOffsetPixel)
                    );
                    totalPHat += tempBilinearWeight
                        * tempPHat
                        * tempJacobian
                        * CollectTemporalSamples_confidence_weight(tempConfidence);
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
                lt_scatter_compute_ucw(neighborReservoir, sourceIntegrand),
                CollectTemporalSamples_confidence_weight(neighborConfidence),
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

    if (isnan(PathReservoir_getTotalWeight(dstReservoir)))
    {
        PathReservoir_setIntegrand(dstReservoir, vec3(0.0f));
        PathReservoir_setTotalWeight(dstReservoir, 0.0f);
        dstReconnectionData.subPixelJacobian = 1.0f;
        dstReconnectionData.lensVertexJacobian = 1.0f;
        dstReconnectionData.secondaryPathJacobian = 1.0f;
        dstReconnectionData.pathLength = 0u;
    }

    PathReservoir_setConfidence(dstReservoir, totalConfidence);
    CollectTemporalSamples_storeResult(
        currPixel,
        prevPixel,
        dstReservoir,
        dstReconnectionData
    );
}

#endif
