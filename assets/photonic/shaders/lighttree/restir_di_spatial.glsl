#ifndef PHOTONICS_RESTIR_DI_SPATIAL_GLSL
#define PHOTONICS_RESTIR_DI_SPATIAL_GLSL

RTXDI_DIReservoir lt_area_spatial_resampling(
    ivec2 pixelPosition,
    RAB_Surface centerSurface,
    RTXDI_DIReservoir centerSample,
    inout RTXDI_RandomSamplerState rng);

#endif
