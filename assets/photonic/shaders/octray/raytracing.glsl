#ifndef PH_OCTRAY_RAYTRACING
#define PH_OCTRAY_RAYTRACING

// Octray chunk traversal path.
// Reuses the shared ray marcher but switches chunk entry lookup to the
// OctrayChunk page layout so empty-space skipping uses the occupancy mip chain
// written by the Java Octray chunk backend.

#define PH_OCTRAY_CHUNK_LOOKUP
#include "/photonics/ph_raytracing.glsl"

#endif
