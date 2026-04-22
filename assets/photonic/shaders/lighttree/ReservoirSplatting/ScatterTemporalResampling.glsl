#ifndef PHOTONICS_RESERVOIR_SPLATTING_SCATTER_TEMPORAL_RESAMPLING_GLSL
#define PHOTONICS_RESERVOIR_SPLATTING_SCATTER_TEMPORAL_RESAMPLING_GLSL

#include "/photonics/lighttree/restir_di_temporal_scatter_bridge.glsl"

RTXDI_DIReservoir ScatterTemporalResampling_run(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    return lt_di_scatter_temporal_resampling_stage(pixel, currReconnectionData);
}

#endif
