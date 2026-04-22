#ifndef PHOTONICS_RESERVOIR_SPLATTING_MULTI_REPROJECT_TEMPORAL_SAMPLES_GLSL
#define PHOTONICS_RESERVOIR_SPLATTING_MULTI_REPROJECT_TEMPORAL_SAMPLES_GLSL

#include "/photonics/lighttree/restir_di_temporal_scatter_bridge.glsl"

void MultiReprojectTemporalSamples_run(ivec2 pixel)
{
    lt_di_multi_reproject_temporal_samples_stage(pixel);
}

#endif
