#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_REPROJECT_SORT_PIPELINE_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_REPROJECT_SORT_PIPELINE_GLSL

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS) \
    || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE) \
    || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING)
#include "/photonics/lighttree/restir_di_temporal.glsl"

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_REPROJECT_STAGE)
#include "/photonics/lighttree/ReservoirSplatting/ReprojectTemporalSamples.glsl"
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE) \
    || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING)
#include "/photonics/lighttree/ReservoirSplatting/SortReprojectedReservoirs.glsl"
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_REPROJECT_STAGE)
#include "/photonics/lighttree/ReservoirSplatting/MultiReprojectTemporalSamples.glsl"
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE)
void computeCellOffsetsStage(
    ivec2 pixel)
{
    SortReprojectedReservoirs_computeCellOffsets(pixel);
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING)
void sortCellDataStage(
    uint index)
{
    SortReprojectedReservoirs_sortCellData(index);
}
#endif

#endif

#endif
