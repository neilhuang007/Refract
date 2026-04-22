#version 430
#define PH_LIGHTTREE_ENABLE_ROBUST_REUSE_STAGE 1

in vec4 direction_vert_out;

#include "/photonics/lighttree/robust_reuse_optimization_stage.glsl"
