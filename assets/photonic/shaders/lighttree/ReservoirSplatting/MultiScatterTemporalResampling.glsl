#ifndef PHOTONICS_RESERVOIR_SPLATTING_MULTI_SCATTER_TEMPORAL_RESAMPLING_GLSL
#define PHOTONICS_RESERVOIR_SPLATTING_MULTI_SCATTER_TEMPORAL_RESAMPLING_GLSL

#include "/photonics/lighttree/restir_di_temporal_bridge.glsl"

RTXDI_DIReservoir MultiScatterTemporalResampling_run(
    ivec2 pixel,
    out ReservoirSplattingReconnectionData currReconnectionData)
{
    return lt_di_multi_scatter_temporal_resampling_stage(pixel, currReconnectionData);
}

#endif
