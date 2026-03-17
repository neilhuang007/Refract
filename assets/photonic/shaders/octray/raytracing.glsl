#ifndef PH_OCTRAY_RAYTRACING
#define PH_OCTRAY_RAYTRACING

// Shared chunk traversal path.
// The shared ray marcher now reads direct chunk-page entries from root_uniform/cb_block
// so this wrapper only includes the common implementation.
#include "/photonics/ph_raytracing.glsl"

#endif
