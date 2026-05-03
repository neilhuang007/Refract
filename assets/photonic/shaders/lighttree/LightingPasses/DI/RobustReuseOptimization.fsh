#version 430
#define PH_LIGHTTREE_ENABLE_LOCAL_LIGHT_SAMPLING_BUFFERS 0
#define PH_LIGHTTREE_ENABLE_POWER_LIGHT_CDF 0
#define PH_LIGHTTREE_ENABLE_SPATIAL_NEIGHBOR_OFFSETS 0
#define PH_LIGHTTREE_ENABLE_ROBUST_REUSE_STAGE 1

in vec4 direction_vert_out;

// Robust-only prepass: fills the 8-neighbor shifted-path buffer consumed by
// CollectTemporalSamples when GatherMechanism == Robust.
#include "/photonics/lighttree/robust_reuse_optimization_stage.glsl"
