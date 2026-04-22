#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_IMPL_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_IMPL_GLSL

#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"
#include "/photonics/lighttree/restir_di_reconnection_surface.glsl"
#include "/photonics/lighttree/restir_di_reconnection_packing.glsl"
#include "/photonics/lighttree/restir_di_spatial_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_shared.glsl"
#include "/photonics/lighttree/restir_di_temporal_shift_mapping.glsl"
#include "/photonics/lighttree/restir_di_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_collect_temporal_stage.glsl"
#include "/photonics/lighttree/restir_di_gather_temporal_stage.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_pipeline.glsl"

void lt_di_collect_temporal_samples(
    ivec2 pixel,
    RAB_Surface surface,
    inout RTXDI_RandomSamplerState sg)
{
    lt_di_collect_temporal_samples_stage(pixel);
}

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_GATHER_STAGE)
RTXDI_DIReservoir lt_di_gather_temporal_resampling(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    return GatherTemporalResampling_run(
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

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_REPROJECT_STAGE)
void lt_di_reproject_temporal_samples(
    ivec2 pixel,
    RAB_Surface surface,
    inout RTXDI_RandomSamplerState sg)
{
    ReprojectTemporalSamples_run(pixel);
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE)
void computeCellOffsets(
    ivec2 pixel)
{
    computeCellOffsetsStage(pixel);
}

void sortCellData(
    uint index)
{
    sortCellDataStage(index);
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_STAGE)
RTXDI_DIReservoir lt_di_scatter_temporal_resampling(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    return ScatterTemporalResampling_run(
        pixel,
        currReconnectionData
    );
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_BACKUP_STAGE)
RTXDI_DIReservoir lt_di_scatter_backup_temporal_resampling(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    return ScatterBackupTemporalResampling_run(
        pixel,
        currReconnectionData
    );
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_REPROJECT_STAGE)
void lt_di_multi_reproject_temporal_samples(
    ivec2 pixel,
    RAB_Surface surface,
    inout RTXDI_RandomSamplerState sg)
{
    MultiReprojectTemporalSamples_run(pixel);
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_STAGE)
void multiComputeCellOffsets(
    ivec2 pixel)
{
    multiComputeCellOffsetsStage(pixel);
}

void multiSortCellData(
    uint index)
{
    multiSortCellDataStage(index);
}
#endif

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SCATTER_STAGE)
RTXDI_DIReservoir lt_di_multi_scatter_temporal_resampling(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    return MultiScatterTemporalResampling_run(
        pixel,
        currReconnectionData
    );
}
#endif

#endif
