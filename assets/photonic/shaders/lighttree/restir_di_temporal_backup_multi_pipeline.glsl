#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_BACKUP_MULTI_PIPELINE_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_BACKUP_MULTI_PIPELINE_GLSL

#include "/photonics/lighttree/ReservoirSplatting/ScatterBackupTemporalResampling.glsl"
#include "/photonics/lighttree/ReservoirSplatting/MultiReprojectTemporalSamples.glsl"
#include "/photonics/lighttree/ReservoirSplatting/MultiSortReprojectedReservoirs.glsl"
#include "/photonics/lighttree/ReservoirSplatting/MultiScatterTemporalResampling.glsl"

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_STAGE)
void multiComputeCellOffsetsStage(
    ivec2 pixel)
{
    MultiSortReprojectedReservoirs_computeCellOffsets(pixel);
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING)
void multiSortCellDataStage(
    uint index)
{
    MultiSortReprojectedReservoirs_sortCellData(index);
}
#endif

#endif
