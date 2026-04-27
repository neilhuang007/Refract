#ifndef PHOTONICS_RESTIR_DI_TEMPORAL_BRIDGE_GLSL
#define PHOTONICS_RESTIR_DI_TEMPORAL_BRIDGE_GLSL

// Reference-parity temporal bridge for Reservoir Splatting.
//
// The reference pass order is:
//   1. InitialCandidates
//   2. RobustReuseOptimization         (GatherOnly / ScatterBackup when gatherOption == Robust)
//   3. CollectTemporalSamples          (GatherOnly / ScatterBackup)
//   4. GatherTemporalResampling        (GatherOnly)
//   5. ReprojectTemporalSamples        (ScatterOnly / ScatterBackup)
//   6. SortReprojectedReservoirs       (ScatterOnly / ScatterBackup)
//   7. ScatterTemporalResampling       (ScatterOnly)
//   8. ScatterBackupTemporalResampling (ScatterBackup)
//   9. MultiReprojectTemporalSamples   (MultiScatter)
//  10. MultiSortReprojectedReservoirs  (MultiScatter)
//  11. MultiScatterTemporalResampling  (MultiScatter)
//
// This bridge keeps the OpenGL port wired to those exact stage modules instead
// of introducing a separate temporal pipeline abstraction.

#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/restir_di_temporal_impl.glsl"

#endif


