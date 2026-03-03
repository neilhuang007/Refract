#file "/world0/gbuffers_voxels.fsh" "/world1/gbuffers_voxels.fsh" "/world-1/gbuffers_voxels.fsh"
#create

// Compatibility profile keeps fixed-function symbols available for Sodium chunk shader integration.
#version 430 compatibility

#define FRAGMENT_SHADER
#define OVERWORLD
#define GBUFFERS_BLOCK
#define GBUFFERS_VOXELS

#include "/program/gbuffers_voxels.glsl"
