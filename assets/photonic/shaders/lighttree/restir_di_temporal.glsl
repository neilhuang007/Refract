#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_GLSL

void lt_di_collect_temporal_samples_stage(
    ivec2 pixel);

RTXDI_DIReservoir lt_di_gather_temporal_resampling_stage(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData);

void lt_di_reproject_temporal_samples_stage(
    ivec2 pixel);

void lt_SortReprojectedReservoirs_compute_cell_offsets(
    ivec2 pixel);

void lt_SortReprojectedReservoirs_sort_cell_data(
    uint index);

RTXDI_DIReservoir lt_di_scatter_temporal_resampling_stage(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData);

void lt_di_multi_reproject_temporal_samples_stage(
    ivec2 pixel);

void lt_MultiSortReprojectedReservoirs_compute_cell_offsets(
    ivec2 pixel);

void lt_MultiSortReprojectedReservoirs_sort_cell_data(
    uint index);

RTXDI_DIReservoir lt_di_scatter_backup_temporal_resampling_stage(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData);

RTXDI_DIReservoir lt_di_multi_scatter_temporal_resampling_stage(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData);

RTXDI_DIReservoir lt_di_spatial_resampling_stage(
    ivec2 pixel,
    RAB_Surface centerSurface,
    RTXDI_DIReservoir centralReservoir,
    inout RTXDI_RandomSamplerState sg,
    out ReservoirSplattingReconnectionData currReconnectionData);

#endif

