#ifndef PHOTONICS_RESERVOIR_SPLATTING_SORT_REPROJECTED_RESERVOIRS_GLSL
#define PHOTONICS_RESERVOIR_SPLATTING_SORT_REPROJECTED_RESERVOIRS_GLSL

#if defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SORT_STAGE) && (defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE) || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING))
#include "/photonics/lighttree/restir_di_temporal_sort_offsets_minimal.glsl"
#else
#include "/photonics/lighttree/restir_di_temporal_scatter_bridge.glsl"
#endif

#endif
