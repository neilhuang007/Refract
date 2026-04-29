#ifndef PHOTONICS_RESTIR_DI_BRIDGE_GLSL
#define PHOTONICS_RESTIR_DI_BRIDGE_GLSL

// Shader-local bridge for Reservoir Splatting DI.
// Stage logic stays in the stage-named modules, matching the reference pass
// structure instead of collapsing stage bodies into the bridge itself.

#include "/photonics/lighttree/restir_di_spatial.glsl"
#include "/photonics/lighttree/restir_gi_initial_sampling_impl.glsl"

#endif
