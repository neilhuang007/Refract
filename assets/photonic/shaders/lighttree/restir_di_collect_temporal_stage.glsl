#ifndef PHOTONICS_RESTIR_DI_COLLECT_TEMPORAL_STAGE_GLSL
#define PHOTONICS_RESTIR_DI_COLLECT_TEMPORAL_STAGE_GLSL

#include "/photonics/lighttree/ReservoirSplatting/CollectTemporalSamples.glsl"

void lt_di_collect_temporal_samples_stage(ivec2 currPixel)
{
    CollectTemporalSamples_execute(currPixel);
}

#endif
