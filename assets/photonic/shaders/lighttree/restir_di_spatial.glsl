#ifndef PHOTONICS_RESTIR_DI_SPATIAL_GLSL
#define PHOTONICS_RESTIR_DI_SPATIAL_GLSL

// Stage 3 — SpatialResampling.rt.slang
RTXDI_DIReservoir lt_di_spatial_resampling_stage(
    ivec2 pixelPosition,
    RAB_Surface centerSurface,
    RTXDI_DIReservoir centerSample,
    inout RTXDI_RandomSamplerState rng,
    out ReservoirSplattingReconnectionData reconnection);

#endif
