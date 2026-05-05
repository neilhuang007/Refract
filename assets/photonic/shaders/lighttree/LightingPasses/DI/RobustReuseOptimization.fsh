#version 430
#define PH_LIGHTTREE_ENABLE_ROBUST_REUSE_STAGE 1

in vec4 direction_vert_out;

// Robust-only prepass: fills the 8-neighbor shifted-path buffer consumed by
// CollectTemporalSamples when GatherMechanism == Robust.
#include "/photonics/lighttree/robust_reuse_optimization_stage.glsl"
