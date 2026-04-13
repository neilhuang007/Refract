#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_GLSL

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_BUFFERS)
RTXDI_DIReservoir lt_area_temporal_reprojection_stage(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng);

RTXDI_DIReservoir lt_area_temporal_binning_stage(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng);

RTXDI_DIReservoir lt_area_temporal_scatter_stage(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng,
    out ScatterReconnectionData reconnection);
#else
RTXDI_DIReservoir lt_area_temporal_reprojection_stage(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng);

RTXDI_DIReservoir lt_area_temporal_binning_stage(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng);

RTXDI_DIReservoir lt_area_temporal_scatter_stage(
    ivec2 pixelPosition,
    RAB_Surface currentSurface,
    RTXDI_DIReservoir currentReservoir,
    inout RTXDI_RandomSamplerState rng,
    out ScatterReconnectionData reconnection);
#endif

#endif
