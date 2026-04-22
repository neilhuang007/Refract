#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_IMPL_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_IMPL_GLSL

// Shared DI temporal ABI surface.
// This module now exposes the step-by-step local port of the Reservoir
// Splatting temporal chain:
//   CollectTemporalSamples      -> stage 2a
//   GatherTemporalResampling    -> stage 2b
//   ReprojectTemporalSamples    -> stage 2c
//   SortReprojectedReservoirs   -> stage 2d.1 / 2d.2
//   ScatterTemporalResampling   -> stage 2e
//   MultiReprojectTemporalSamples      -> stage 2f
//   MultiSortReprojectedReservoirs     -> stage 2g.1 / 2g.2
//   MultiScatterTemporalResampling     -> stage 2h

// NOTE:
// The active temporal stage implementation now lives in reuse_bridge.glsl +
// restir_di_scatter_impl.glsl. This file is retained as a thin ABI wrapper
// surface so include ordering remains stable while the reference-structured
// implementation is consolidated elsewhere.

#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_COLLECT_STAGE)
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
    if (any(lessThan(prevPixel, vec2(0.0f)))
        || any(greaterThanEqual(prevPixel, vec2(viewWidth, viewHeight))))
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
            ShiftedPathData shiftedPath = noShiftNeeded
                ? CollectTemporalSamples_make_no_shift_path(
                    neighborPixel,
                    neighborReservoir,
                    neighborReconnectionData
                )
                : CollectTemporalSamples_restore_shifted_path(
                    targetPixel,
                    relativeSubPixel,
                    neighborReconnectionData,
                    scatter_load_gather_shifted_path_data(neighborPixel, packedOffsetIndex)
                );
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

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_GATHER_STAGE)
#include "/photonics/lighttree/restir_di_temporal_dof.glsl"

RTXDI_DIReservoir lt_di_load_current_proposal_reservoir(
    ivec2 pixel)
{
    return RTXDI_LoadDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel),
        lt_build_restir_di_parameters().bufferIndices.initialSamplingOutputBufferIndex
    );
}

ReservoirSplattingReconnectionData lt_di_load_current_proposal_reconnection(ivec2 pixel)
{
    vec4 proposalReservoirMeta = texelFetch(radiosity_proposal_reservoir_meta, pixel, 0);
    RTXDI_DIReservoir reservoir = lt_di_load_current_proposal_reservoir(pixel);
    ReservoirSplattingReconnectionData reconnection;
    scatter_unpack_reconnection(
        texelFetch(current_stage_reconnection0, pixel, 0),
        texelFetch(current_stage_reconnection1, pixel, 0),
        texelFetch(radiosity_proposal_reservoir_samples, pixel, 0),
        proposalReservoirMeta.y,
        proposalReservoirMeta.z,
        reconnection
    );
    RestirDI_restoreReconnectionRadiometry(pixel, false, reservoir, reconnection);
    return reconnection;
}

RTXDI_DIReservoir lt_di_load_gather_intermediate_reservoir(ivec2 pixel)
{
    RTXDI_DIReservoir reservoir = RTXDI_EmptyDIReservoir();
    rtxdi_unpack_reservoir_at_surface(
        reservoir,
        texelFetch(temporal_gather_intermediate_reservoir_data, pixel, 0),
        texelFetch(temporal_gather_intermediate_reservoir_sample, pixel, 0),
        texelFetch(temporal_gather_intermediate_reservoir_meta, pixel, 0),
        RAB_EmptySurface(),
        false
    );
    return reservoir;
}

float lt_scatter_reservoir_confidence(
    RTXDI_DIReservoir reservoir,
    ScatterReconnectionData reconnection);
float lt_scatter_radiance_phat(vec3 radiance);
float lt_scatter_compute_ucw(
    RTXDI_DIReservoir reservoir,
    vec3 storedIntegrand);
bool lt_scatter_add_sample_from_reservoir(
    inout RTXDI_DIReservoir state,
    inout float stateConfidence,
    float misWeight,
    vec3 pHat,
    float jacobian,
    float otherUcw,
    float otherConfidence,
    RTXDI_DIReservoir otherReservoir,
    inout RTXDI_RandomSamplerState rng);

bool lt_di_gather_temporal_load_current_sample(
    ivec2 pixel,
    out RTXDI_DIReservoir currReservoir,
    out ReservoirSplattingReconnectionData currReconnectionData,
    out float currConfidence)
{
    currReservoir = lt_di_load_current_proposal_reservoir(pixel);
    currReconnectionData = lt_di_load_current_proposal_reconnection(pixel);
    currConfidence = lt_scatter_reservoir_confidence(currReservoir, currReconnectionData);
    return RTXDI_IsValidDIReservoir(currReservoir)
        && ph_luminance(PathReservoir_getIntegrand(currReservoir)) > 0.0f;
}

bool lt_di_gather_temporal_load_previous_sample(
    ivec2 pixel,
    out RTXDI_DIReservoir prevReservoir,
    out ReservoirSplattingReconnectionData prevReconnectionData,
    out float prevConfidence)
{
    prevReservoir = lt_di_load_gather_intermediate_reservoir(pixel);
    prevReconnectionData = RestirDI_loadGatherIntermediateReconnection(pixel);
    prevConfidence = lt_scatter_reservoir_confidence(prevReservoir, prevReconnectionData);
    return RTXDI_IsValidDIReservoir(prevReservoir)
        && ph_luminance(PathReservoir_getIntegrand(prevReservoir)) > 0.0f;
}

float lt_di_gather_temporal_current_sample_mis(
    ReservoirSplattingReconnectionData currReconnectionData,
    float currConfidence,
    float prevConfidence)
{
    vec3 currIntegrand = scatter_reconnection_integrand(currReconnectionData);
    float m1 = lt_scatter_radiance_phat(currIntegrand) * currConfidence;
    float m2 = lt_scatter_radiance_phat(currIntegrand) * prevConfidence;
    return ((m1 + m2) > 0.0f) ? (m1 / (m1 + m2)) : 0.0f;
}

float lt_di_gather_temporal_previous_sample_mis(
    ReservoirSplattingReconnectionData prevReconnectionData,
    float currConfidence,
    float prevConfidence)
{
    vec3 prevIntegrand = scatter_reconnection_integrand(prevReconnectionData);
    float m1 = lt_scatter_radiance_phat(prevIntegrand) * currConfidence;
    float m2 = lt_scatter_radiance_phat(prevIntegrand) * prevConfidence;
    return ((m1 + m2) > 0.0f) ? (m2 / (m1 + m2)) : 0.0f;
}

float lt_di_gather_temporal_confidence_weight(float confidence)
{
    return confidence;
}

float lt_di_gather_temporal_shifted_jacobian(
    ShiftedPathData shiftedPathData,
    ReservoirSplattingReconnectionData reconnectionData,
    bool primaryHitReconnection)
{
    if (primaryHitReconnection)
    {
        float baseJacobian = reconnectionData.lensVertexJacobian
            * reconnectionData.secondaryPathJacobian;
        if (baseJacobian <= 1e-10f)
        {
            return 0.0f;
        }
        float ratio = (shiftedPathData.lensVertexJacobian * shiftedPathData.secondaryPathJacobian)
            / baseJacobian;
        return (isnan(ratio) || isinf(ratio) || ratio < 0.0f) ? 0.0f : ratio;
    }
    if (reconnectionData.secondaryPathJacobian <= 1e-10f)
    {
        return 0.0f;
    }
    float ratio = shiftedPathData.secondaryPathJacobian / reconnectionData.secondaryPathJacobian;
    return (isnan(ratio) || isinf(ratio) || ratio < 0.0f) ? 0.0f : ratio;
}

float lt_di_gather_temporal_reference_mis(
    vec3 sourceRadiance,
    float sourceWeight,
    vec3 shiftedRadiance,
    float shiftedJacobian,
    float shiftedWeight,
    float shiftProbability,
    bool selectSource)
{
    float m1 = lt_scatter_radiance_phat(sourceRadiance) * sourceWeight;
    float m2 = lt_scatter_radiance_phat(shiftedRadiance) * shiftedJacobian * shiftedWeight * shiftProbability;
    m2 = isnan(m2) ? 0.0f : m2;
    float sum = m1 + m2;
    if (sum <= 0.0f)
    {
        return 0.0f;
    }
    return selectSource ? (m1 / sum) : (m2 / sum);
}

bool lt_di_gather_temporal_add_current_sample(
    ivec2 pixel,
    inout RTXDI_DIReservoir dstReservoir,
    inout float dstConfidence,
    inout ReservoirSplattingReconnectionData dstReconnectionData,
    RTXDI_DIReservoir currReservoir,
    ReservoirSplattingReconnectionData currReconnectionData,
    float currConfidence,
    float prevConfidence,
    bool primaryHitReconnection,
    float shiftProbability,
    int shiftedPathIndex,
    inout RTXDI_RandomSamplerState sg)
{
    float currSampleMIS = 0.0f;
    vec3 currPHat = vec3(0.0f);
    vec3 currIntegrand = PathReservoir_getIntegrand(currReservoir);
    if (any(greaterThan(currIntegrand, vec3(0.0f))))
    {
        currPHat = currIntegrand;
        vec2 floatingCoord = scatter_load_gather_floating_coords(pixel);
        vec2 shiftedPixel = primaryHitReconnection
            ? (vec2(pixel) + currReconnectionData.subPixel)
            : (floatingCoord + currReconnectionData.subPixel);
        ShiftedPathData shiftedCurr = primaryHitReconnection
            ? gatherPrimaryHitReconnectionShift(
                sg,
                currReconnectionData,
                currReconnectionData.time,
                shiftedPixel,
                currReconnectionData.firstHit,
                currReservoir
            )
            : gatherLensVertexCopyShift(
                sg,
                currReconnectionData,
                currReconnectionData.time,
                shiftedPixel,
                currReconnectionData.lensSample,
                currReservoir
            );
        float shiftedJacobian = lt_di_gather_temporal_shifted_jacobian(shiftedCurr, currReconnectionData, primaryHitReconnection);
        float m1 = lt_scatter_radiance_phat(currIntegrand)
            * lt_di_gather_temporal_confidence_weight(currConfidence);
        float m2 = lt_scatter_radiance_phat(shiftedCurr.radiance)
            * shiftedJacobian
            * lt_di_gather_temporal_confidence_weight(prevConfidence)
            * shiftProbability;
        m2 = isnan(m2) ? 0.0f : m2;
        currSampleMIS = ((m1 + m2) > 0.0f) ? (m1 / (m1 + m2)) : 0.0f;
    }

    bool currSelected = lt_scatter_add_sample_from_reservoir(
        dstReservoir,
        dstConfidence,
        currSampleMIS,
        currPHat,
        1.0f,
        lt_scatter_compute_ucw(currReservoir, currPHat),
        currConfidence,
        currReservoir,
        sg
    );
    if (currSelected)
    {
        dstReconnectionData = currReconnectionData;
    }
    return currSelected;
}

bool lt_di_gather_temporal_add_previous_sample(
    ivec2 pixel,
    inout RTXDI_DIReservoir dstReservoir,
    inout float dstConfidence,
    inout ReservoirSplattingReconnectionData dstReconnectionData,
    RTXDI_DIReservoir prevReservoir,
    ReservoirSplattingReconnectionData prevReconnectionData,
    float currConfidence,
    float prevConfidence,
    bool primaryHitReconnection,
    float shiftProbability,
    int shiftedPathIndex,
    inout RTXDI_RandomSamplerState sg)
{
    float prevSampleMIS = 0.0f;
    vec3 prevPHat = vec3(0.0f);
    float shiftedJacobian = 1.0f;
    vec3 prevIntegrand = PathReservoir_getIntegrand(prevReservoir);
    if (any(greaterThan(prevIntegrand, vec3(0.0f))))
    {
        vec2 shiftedPixel = vec2(pixel) + PathReservoir_getSubPixel(prevReservoir, pixel);
        ShiftedPathData shiftedPrev = primaryHitReconnection
            ? gatherPrimaryHitReconnectionShift(
                sg,
                prevReconnectionData,
                prevReconnectionData.time,
                shiftedPixel,
                prevReconnectionData.firstHit,
                prevReservoir
            )
            : gatherLensVertexCopyShift(
                sg,
                prevReconnectionData,
                prevReconnectionData.time,
                shiftedPixel,
                prevReconnectionData.lensSample,
                prevReservoir
            );
        shiftedJacobian = lt_di_gather_temporal_shifted_jacobian(shiftedPrev, prevReconnectionData, primaryHitReconnection);
        float m1 = lt_scatter_radiance_phat(shiftedPrev.radiance)
            * shiftedJacobian
            * lt_di_gather_temporal_confidence_weight(currConfidence);
        prevPHat = isnan(m1) ? vec3(0.0f) : max(shiftedPrev.radiance, vec3(0.0f));
        shiftedJacobian = isnan(m1) ? 1.0f : shiftedJacobian;
        float m2 = lt_scatter_radiance_phat(prevIntegrand)
            * lt_di_gather_temporal_confidence_weight(prevConfidence)
            * shiftProbability;
        prevSampleMIS = isnan(m1) ? 0.0f : (((m1 + m2) > 0.0f) ? (m2 / (m1 + m2)) : 0.0f);
        bool shiftedPrevValid = shiftedPrev.primaryHit.viewDepth > 0.0f
            || any(greaterThan(max(shiftedPrev.radiance, vec3(0.0f)), vec3(0.0f)));
        if (shiftedPrevValid)
        {
            prevReconnectionData = ReconnectionData_update(prevReconnectionData, shiftedPrev);
        }
    }

    bool prevSelected = lt_scatter_add_sample_from_reservoir(
        dstReservoir,
        dstConfidence,
        prevSampleMIS,
        prevPHat,
        shiftedJacobian,
        lt_scatter_compute_ucw(prevReservoir, prevIntegrand),
        prevConfidence,
        prevReservoir,
        sg
    );
    if (prevSelected)
    {
        dstReconnectionData = prevReconnectionData;
    }
    return prevSelected;
}

RTXDI_DIReservoir lt_di_gather_temporal_resampling_stage(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    RTXDI_RandomSamplerState sg = lt_init_random_sampler(uvec2(pixel), uint(frameCounter), 3u);
    RTXDI_DIReservoir dstReservoir = RTXDI_EmptyDIReservoir();
    float dstConfidence = 0.0f;
    currReconnectionData = ReservoirSplattingReconnectionData_init();

    RTXDI_DIReservoir currReservoir;
    ReservoirSplattingReconnectionData currentReconnectionData;
    float currConfidence = 0.0f;
    bool hasCurrentSample = lt_di_gather_temporal_load_current_sample(
        pixel,
        currReservoir,
        currentReconnectionData,
        currConfidence
    );

    RTXDI_DIReservoir prevReservoir;
    ReservoirSplattingReconnectionData prevReconnectionData;
    float prevConfidence = 0.0f;
    bool hasPreviousSample = lt_di_gather_temporal_load_previous_sample(
        pixel,
        prevReservoir,
        prevReconnectionData,
        prevConfidence
    );

    RAB_Surface centerSurface = RAB_GetGBufferSurface(pixel, false);
    const bool hasDepthOfField = lt_di_temporal_camera_aperture_radius() > 0.0f;
    vec2 depthOfFieldProbs = hasDepthOfField
        ? lt_di_temporal_resolve_dof_probabilities(centerSurface)
        : vec2(1.0f, 0.0f);
    const bool doLensVertexCopy = (depthOfFieldProbs.x > 0.0f);
    const bool doPrimaryHitReconnection = (depthOfFieldProbs.y > 0.0f);

    if (doLensVertexCopy)
    {
        if (hasCurrentSample)
        {
            lt_di_gather_temporal_add_current_sample(
                pixel,
                dstReservoir,
                dstConfidence,
                currReconnectionData,
                currReservoir,
                currentReconnectionData,
                currConfidence,
                prevConfidence,
                false,
                depthOfFieldProbs.x,
                0,
                sg
            );
        }

        if (hasPreviousSample)
        {
            lt_di_gather_temporal_add_previous_sample(
                pixel,
                dstReservoir,
                dstConfidence,
                currReconnectionData,
                prevReservoir,
                prevReconnectionData,
                currConfidence,
                prevConfidence,
                false,
                depthOfFieldProbs.x,
                1,
                sg
            );
        }

        PathReservoir_setConfidence(dstReservoir, dstConfidence);
    }

    if (hasDepthOfField && doPrimaryHitReconnection)
    {
        RTXDI_DIReservoir lensVertexCopyReservoir = dstReservoir;
        float lensVertexCopyConfidence = dstConfidence;
        ReservoirSplattingReconnectionData lensVertexCopyReconnectionData = currReconnectionData;
        dstReservoir = RTXDI_EmptyDIReservoir();
        dstConfidence = 0.0f;
        currReconnectionData = ReservoirSplattingReconnectionData_init();

        RTXDI_DIReservoir currentDomainReservoir = hasCurrentSample ? lensVertexCopyReservoir : currReservoir;
        ReservoirSplattingReconnectionData currentDomainReconnectionData = hasCurrentSample ? lensVertexCopyReconnectionData : currentReconnectionData;
        float currentDomainConfidence = hasCurrentSample ? lensVertexCopyConfidence : currConfidence;

        if (hasCurrentSample)
        {
            lt_di_gather_temporal_add_current_sample(
                pixel,
                dstReservoir,
                dstConfidence,
                currReconnectionData,
                currentDomainReservoir,
                currentDomainReconnectionData,
                currentDomainConfidence,
                prevConfidence,
                true,
                depthOfFieldProbs.y,
                2,
                sg
            );
        }

        if (doLensVertexCopy && hasPreviousSample)
        {
            lt_di_gather_temporal_add_previous_sample(
                pixel,
                dstReservoir,
                dstConfidence,
                currReconnectionData,
                prevReservoir,
                prevReconnectionData,
                currentDomainConfidence,
                prevConfidence,
                true,
                depthOfFieldProbs.y,
                3,
                sg
            );
        }

        PathReservoir_setConfidence(dstReservoir, dstConfidence);
    }

    return dstReservoir;
}

RTXDI_DIReservoir lt_di_gather_temporal_resampling(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    return lt_di_gather_temporal_resampling_stage(
        pixel,
        currReconnectionData
    );
}
#else
RTXDI_DIReservoir lt_di_gather_temporal_resampling(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    currReconnectionData = ReservoirSplattingReconnectionData_init();
    return RTXDI_EmptyDIReservoir();
}
#endif

// Reference stage 2a wrapper: CollectTemporalSamples::run(pixel).
void lt_di_collect_temporal_samples(
    ivec2 pixel,
    RAB_Surface surface,
    inout RTXDI_RandomSamplerState sg)
{
    lt_di_collect_temporal_samples_stage(pixel);
}

// Reference stage 2c wrapper: ReprojectTemporalSamples::run(pixel).
#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_REPROJECT_STAGE)
void lt_di_reproject_temporal_samples(
    ivec2 pixel,
    RAB_Surface surface,
    inout RTXDI_RandomSamplerState sg)
{
    lt_di_reproject_temporal_samples_stage(pixel);
}
#endif

// Reference stage 2d half 1 wrapper: SortReprojectedReservoirs::computeCellOffsets(pixel).
#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE)
void computeCellOffsets(
    ivec2 pixel)
{
    computeCellOffsetsStage(pixel);
}

// Reference stage 2d half 2 wrapper: SortReprojectedReservoirs::sortCellData(index).
void sortCellData(
    uint index)
{
    sortCellDataStage(index);
}
#endif

// Reference stage 2e wrapper: ScatterTemporalResampling::run(pixel).
#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_STAGE)
RTXDI_DIReservoir lt_di_scatter_temporal_resampling(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    return lt_di_scatter_temporal_resampling_stage(
        pixel,
        currReconnectionData
    );
}
#endif

// Reference stage 2e backup wrapper: ScatterBackupTemporalResampling::run(pixel).
#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_BACKUP_STAGE)
RTXDI_DIReservoir lt_di_scatter_backup_temporal_resampling(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    return lt_di_scatter_backup_temporal_resampling_stage(
        pixel,
        currReconnectionData
    );
}
#endif

// Reference stage 2f wrapper: MultiReprojectTemporalSamples::run(pixel).
#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_REPROJECT_STAGE)
void lt_di_multi_reproject_temporal_samples(
    ivec2 pixel,
    RAB_Surface surface,
    inout RTXDI_RandomSamplerState sg)
{
    lt_di_multi_reproject_temporal_samples_stage(pixel);
}
#endif

// Reference stage 2g half 1 wrapper: MultiSortReprojectedReservoirs::computeCellOffsets(pixel).
#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_STAGE)
void multiComputeCellOffsets(
    ivec2 pixel)
{
    multiComputeCellOffsetsStage(pixel);
}

// Reference stage 2g half 2 wrapper: MultiSortReprojectedReservoirs::sortCellData(index).
void multiSortCellData(
    uint index)
{
    multiSortCellDataStage(index);
}
#endif

// Reference stage 2h wrapper: MultiScatterTemporalResampling::run(pixel).
#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SCATTER_STAGE)
RTXDI_DIReservoir lt_di_multi_scatter_temporal_resampling(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    return lt_di_multi_scatter_temporal_resampling_stage(
        pixel,
        currReconnectionData
    );
}
#endif
#endif
