#ifndef PHOTONICS_RESERVOIR_SPLATTING_MULTI_SORT_REPROJECTED_RESERVOIRS_GLSL
#define PHOTONICS_RESERVOIR_SPLATTING_MULTI_SORT_REPROJECTED_RESERVOIRS_GLSL

#if defined(PH_LIGHTTREE_ENABLE_MULTI_TEMPORAL_SORT_STAGE) && (defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORT_STAGE) || defined(PH_LIGHTTREE_ENABLE_TEMPORAL_SCATTER_SORTING))
#include "/photonics/lighttree/restir_di_multi_temporal_sort_offsets_minimal.glsl"
#else
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_di_reconnection_restore.glsl"
#include "/photonics/lighttree/restir_di_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_spatial_scatter_impl.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_shared.glsl"
#include "/photonics/lighttree/restir_di_temporal_shift_mapping.glsl"
#include "/photonics/lighttree/restir_di_temporal.glsl"
#include "/photonics/lighttree/restir_di_temporal_scatter_common.glsl"
#endif

#endif
