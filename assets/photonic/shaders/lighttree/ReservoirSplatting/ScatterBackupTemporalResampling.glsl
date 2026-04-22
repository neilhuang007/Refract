#ifndef PHOTONICS_RESERVOIR_SPLATTING_SCATTER_BACKUP_TEMPORAL_RESAMPLING_GLSL
#define PHOTONICS_RESERVOIR_SPLATTING_SCATTER_BACKUP_TEMPORAL_RESAMPLING_GLSL

#include "/photonics/lighttree/restir_di_temporal_bridge.glsl"

RTXDI_DIReservoir ScatterBackupTemporalResampling_run(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    return lt_di_scatter_backup_temporal_resampling_stage(pixel, currReconnectionData);
}

#endif
