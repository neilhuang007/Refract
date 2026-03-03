
// Compatibility profile keeps fixed-function symbols available for Sodium chunk shader integration.
#version 430 compatibility

#define FRAGMENT_SHADER
#define OVERWORLD
#define GBUFFERS_BLOCK
#define GBUFFERS_VOXELS

#include "/program/gbuffers_voxels.glsl"
