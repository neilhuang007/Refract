#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_REPROJECT_SORT_PIPELINE_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_REPROJECT_SORT_PIPELINE_GLSL

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)
#include "/photonics/lighttree/restir_di_temporal.glsl"

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_REPROJECT_STAGE)
#include "/photonics/lighttree/ReservoirSplatting/MultiReprojectTemporalSamples.glsl"
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_REPROJECT_STAGE)
void ReprojectTemporalSamples_run(
    ivec2 pixel)
{
    if (!lt_is_viewport_uv_in_bounds(pixel)) {
        return;
    }

    RTXDI_DIReservoir prevReservoir = RTXDI_LoadPreviousDIReservoir(
        lt_build_restir_di_parameters().reservoirBufferParams,
        uvec2(pixel)
    );
    if (all(equal(PathReservoir_getIntegrand(prevReservoir), vec3(0.0f)))) {
        return;
    }

    ReconnectionData prevReconnection = RestirDI_loadPreviousFrameReconnection(pixel);

    RTXDI_RandomSamplerState sg = lt_init_random_sampler(
        uvec2(pixel),
        uint(frameCounter),
        5u
    );
    ShiftedPathData shiftedPrev = scatterReprojectionShift(
        sg,
        prevReconnection,
        prevReconnection.time,
        prevReconnection.firstHit,
        prevReconnection.lensSample,
        prevReservoir,
        true,
        false,
        false
    );
    if (any(lessThan(shiftedPrev.fractionalPixel, vec2(0.0f)))) {
        return;
    }

    ivec2 newPixel = ivec2(floor(shiftedPrev.fractionalPixel));
    lt_reproject_temporal_samples_append_record(pixel, newPixel);
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE)
void computeCellOffsetsStage(
    ivec2 pixel)
{
    SortReprojectedReservoirs_computeCellOffsets(pixel);
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE)
void sortCellDataStage(
    uint index)
{
    SortReprojectedReservoirs_sortCellData(index);
}
#endif

#endif

#endif
