#ifndef PHOTONICS_LT_INITIAL_SAMPLING_MIS_GLSL
#define PHOTONICS_LT_INITIAL_SAMPLING_MIS_GLSL

#ifndef PH_LIGHTTREE_INITIAL_SAMPLE_COUNT_HELPERS
#define PH_LIGHTTREE_INITIAL_SAMPLE_COUNT_HELPERS
int lt_resolve_initial_num_environment_samples();
int lt_resolve_initial_num_brdf_samples();
#endif

// RTXDI initial-sampling MIS data: needed by the ReSTIR_DI initial-candidate
// stage regardless of whether the scatter buffers are wired in, so it lives at
// top level instead of inside the SCATTER_BUFFERS gate further below.
#ifndef PH_LIGHTTREE_INITIAL_SAMPLING_MIS_DATA_DECLARED
#define PH_LIGHTTREE_INITIAL_SAMPLING_MIS_DATA_DECLARED
struct RTXDI_InitialSamplingMisData {
    int numMisSamples;              // total candidates across all techniques
    float localLightMisWeight;      // fraction of candidates from local-light sampling
    float environmentMapMisWeight;  // fraction of candidates from environment sampling
    float brdfMisWeight;            // fraction of candidates from BRDF sampling
};
#endif

#endif
