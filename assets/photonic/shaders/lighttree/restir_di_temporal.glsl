#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_GLSL

void lt_di_collect_temporal_samples_stage(
    ivec2 pixel);

RTXDI_DIReservoir GatherTemporalResampling_run(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData);

void ReprojectTemporalSamples_run(
    ivec2 pixel);

void SortReprojectedReservoirs_computeCellOffsets(
    ivec2 pixel);

void SortReprojectedReservoirs_sortCellData(
    uint index);

RTXDI_DIReservoir ScatterTemporalResampling_run(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData);

void MultiReprojectTemporalSamples_run(
    ivec2 pixel);

void MultiSortReprojectedReservoirs_computeCellOffsets(
    ivec2 pixel);

void MultiSortReprojectedReservoirs_sortCellData(
    uint index);

RTXDI_DIReservoir ScatterBackupTemporalResampling_run(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData);

RTXDI_DIReservoir MultiScatterTemporalResampling_run(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData);

RTXDI_DIReservoir SpatialResampling_run(
    ivec2 pixel,
    RAB_Surface centerSurface,
    RTXDI_DIReservoir centralReservoir,
    inout RTXDI_RandomSamplerState sg,
    out ReservoirSplattingReconnectionData currReconnectionData);

#endif

