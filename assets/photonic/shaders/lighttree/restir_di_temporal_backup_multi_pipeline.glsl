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
#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
    MultiSortReprojectedReservoirs_computeCellOffsets(pixel);
#endif
}

void multiSortCellDataStage(
    uint index)
{
#if !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_RESOLVE_ONLY) && !defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_OWNERSHIP_ONLY)
    MultiSortReprojectedReservoirs_sortCellData(index);
#endif
}
#endif

#endif
