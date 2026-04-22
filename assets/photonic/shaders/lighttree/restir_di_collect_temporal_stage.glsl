#ifndef PHOTONICS_RESTIR_DI_COLLECT_TEMPORAL_STAGE_GLSL
#define PHOTONICS_RESTIR_DI_COLLECT_TEMPORAL_STAGE_GLSL

#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"
#include "/photonics/lighttree/restir_di_reconnection_surface.glsl"
#include "/photonics/lighttree/restir_di_reconnection_packing.glsl"
#include "/photonics/lighttree/restir_di_spatial_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_shared.glsl"
#include "/photonics/lighttree/restir_di_temporal_shift_mapping.glsl"
#include "/photonics/lighttree/restir_di_scatter_impl.glsl"

float CollectTemporalSamples_bilinear_weight(vec2 fractionalCoord, int x, int y)
{
    return mix(float(1 - x), float(x), fractionalCoord.x)
        * mix(float(1 - y), float(y), fractionalCoord.y);
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
    shiftedPath.subPixelJacobian = max(neighborReconnectionData.subPixelJacobian, 1e-10f);
    shiftedPath.lensVertexJacobian = max(neighborReconnectionData.lensVertexJacobian, 1e-10f);
    shiftedPath.secondaryPathJacobian = max(neighborReconnectionData.secondaryPathJacobian, 1e-10f);
    shiftedPath.radiance = PathReservoir_getIntegrand(neighborReservoir);
    return shiftedPath;
}

ShiftedPathData CollectTemporalSamples_restore_shifted_path(
    ivec2 targetPixel,
    vec2 relativeSubPixel,
    ReservoirSplattingReconnectionData sourceReconnectionData,
    LtTemporalGatherShiftedPathData packedShiftedPath)
{
    ShiftedPathData shiftedPath = lt_temporal_empty_shifted_path();
    shiftedPath.fractionalPixel = vec2(targetPixel) + relativeSubPixel;
    shiftedPath.lensSample = sourceReconnectionData.lensSample;
    shiftedPath.firstRayDir = -sourceReconnectionData.firstWi;
    shiftedPath.subPixelJacobian = max(sourceReconnectionData.subPixelJacobian, 1e-10f);
    shiftedPath.lensVertexJacobian = max(packedShiftedPath.lensVertexJacobian, 1e-10f);
    shiftedPath.secondaryPathJacobian = max(packedShiftedPath.secondaryPathJacobian, 1e-10f);
    shiftedPath.radiance = packedShiftedPath.radiance;

    if (packedShiftedPath.valid <= 0.0f)
    {
        return shiftedPath;
    }

    RAB_Surface targetSurface = RAB_GetGBufferSurface(targetPixel, false);
    if (!RAB_IsSurfaceValid(targetSurface))
    {
        return shiftedPath;
    }

    vec3 firstRayDir = normalize(targetSurface.worldPos - world_camera_position);
    shiftedPath.primaryHit.worldPos = targetSurface.worldPos;
    shiftedPath.primaryHit.viewDepth = targetSurface.viewDepth;
    shiftedPath.primaryHit.faceId = uint(round(scatter_load_surface_identity(targetPixel, false).w));
    shiftedPath.firstRayDir = firstRayDir;
    shiftedPath.subPixelJacobian = scatter_compute_subpixel_jacobian(
        targetSurface.worldPos,
        targetSurface.geoNormal,
        world_camera_position,
        lt_current_camera_forward()
    );

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
    updatedReconnectionData.subPixelJacobian = max(shiftedPath.subPixelJacobian, 1e-10f);
    updatedReconnectionData.lensVertexJacobian = max(shiftedPath.lensVertexJacobian, 1e-10f);
    updatedReconnectionData.secondaryPathJacobian = max(shiftedPath.secondaryPathJacobian, 1e-10f);
    return updatedReconnectionData;
}

void lt_di_store_collect_temporal_sample_result(
    vec2 floatingCoord,
    RTXDI_DIReservoir reservoir,
    ReservoirSplattingReconnectionData reconnectionData)
{
    floating_coords_frag_out = floatingCoord;

    float transportAux0;
    float transportAux1;
    scatter_pack_reconnection_fields(
        reconnectionData.firstHit.worldPos,
        reconnectionData.firstHit.viewDepth,
        reconnectionData.lightPdf,
        reconnectionData.time,
        reconnectionData.irradiance,
        reconnectionData.subPixel,
        reconnectionData.subPixelJacobian,
        reconnectionData.lensVertexJacobian,
        reconnectionData.secondaryPathJacobian,
        reconnectionData.firstHit.faceId,
        reconnectionData.pathLength,
        reconnectionData.firstBSDFComponentType,
        reconnectionData.secondBSDFComponentType,
        reconnectionData.transmissionEvent,
        reconnectionData.lightIsNEE,
        reconnectionData.lightIsDistant,
        transportAux0,
        transportAux1,
        intermediate_reconnection0_frag_out,
        intermediate_reconnection1_frag_out
    );

    intermediate_reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    intermediate_reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    intermediate_reservoir_meta_frag_out = PathReservoir_packMeta(reservoir);
}

void lt_di_collect_temporal_samples_stage(
    ivec2 currPixel)
{
    vec2 prevPixel = lt_temporal_previous_pixel_center(currPixel) - vec2(0.5f);
    if (any(lessThan(prevPixel, vec2(0.0f))))
    {
        return;
    }
    if (any(greaterThanEqual(prevPixel, vec2(viewWidth, viewHeight))))
    {
        return;
    }

    RTXDI_RandomSamplerState sg = lt_init_random_sampler(uvec2(currPixel), uint(frameCounter), 2u);
    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    ReservoirSplattingReconnectionData dstReconnectionData = ReservoirSplattingReconnectionData_init();
    float dstConfidence = 0.0f;

    ivec2 prevPixelTopLeft = ivec2(floor(prevPixel));
    vec2 fractionalCoord = clamp(prevPixel - vec2(prevPixelTopLeft), vec2(0.0f), vec2(1.0f));
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
            totalConfidence += bilinearWeight * neighborConfidence;

            vec3 sourceIntegrand = PathReservoir_getIntegrand(neighborReservoir);
            if (!RTXDI_IsValidDIReservoir(neighborReservoir)
                || ph_luminance(sourceIntegrand) <= 0.0f)
            {
                continue;
            }

            vec2 relativeSubPixel = vec2(offset)
                + PathReservoir_getSubPixel(neighborReservoir, neighborPixel)
                - fractionalCoord;

            ivec2 requiredOffset = ivec2(0);
            if (relativeSubPixel.x < 0.0f) requiredOffset.x += 1;
            if (relativeSubPixel.x >= 1.0f) requiredOffset.x -= 1;
            if (relativeSubPixel.y < 0.0f) requiredOffset.y += 1;
            if (relativeSubPixel.y >= 1.0f) requiredOffset.y -= 1;
            relativeSubPixel += vec2(requiredOffset);

            ivec2 packedOffset = requiredOffset + ivec2(1);
            int packedOffsetIndex = packedOffset.x + 3 * packedOffset.y;
            bool noShiftNeeded = (packedOffsetIndex == 4);
            if (packedOffsetIndex > 4)
            {
                packedOffsetIndex -= 1;
            }

            ivec2 targetPixel = neighborPixel + requiredOffset;
            ShiftedPathData shiftedPath;
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
                shiftedPath = CollectTemporalSamples_restore_shifted_path(
                    targetPixel,
                    relativeSubPixel,
                    neighborReconnectionData,
                    scatter_load_gather_shifted_path_data(neighborPixel, packedOffsetIndex)
                );
            }

            float shiftedJacobian = noShiftNeeded
                ? 1.0f
                : shiftedPath.secondaryPathJacobian
                    / max(neighborReconnectionData.secondaryPathJacobian, 1e-10f);

            float sourceWeight = bilinearWeight
                * lt_scatter_radiance_phat(sourceIntegrand)
                * neighborConfidence;
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

                    LtTemporalGatherShiftedPathData tempShiftedPath =
                        scatter_load_gather_shifted_path_data(neighborPixel, tempPackedIndex);
                    float tempPHat = lt_scatter_radiance_phat(tempShiftedPath.radiance);
                    float tempJacobian = tempShiftedPath.secondaryPathJacobian
                        / max(neighborReconnectionData.secondaryPathJacobian, 1e-10f);
                    float tempConfidence = lt_scatter_reservoir_confidence(
                        RTXDI_LoadPreviousDIReservoir(
                            lt_build_restir_di_parameters().reservoirBufferParams,
                            uvec2(tempOffsetPixel)
                        ),
                        RestirDI_loadPreviousFrameReconnection(tempOffsetPixel)
                    );
                    totalPHat += tempBilinearWeight * tempPHat * tempJacobian * tempConfidence;
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
                neighborConfidence,
                shiftedReservoir,
                sg
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
    lt_di_store_collect_temporal_sample_result(
        prevPixel,
        dstReservoir,
        dstReconnectionData
    );
}

#endif
