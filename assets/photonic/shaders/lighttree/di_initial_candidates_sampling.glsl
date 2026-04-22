#ifndef PHOTONICS_DI_INITIAL_CANDIDATES_SAMPLING_GLSL
#define PHOTONICS_DI_INITIAL_CANDIDATES_SAMPLING_GLSL

#include "/photonics/lighttree/initial_candidates_path_state.glsl"
#include "/photonics/lighttree/initial_candidates_reservoir.glsl"

void addCandidateReservoir(
    ivec2 pixel,
    RAB_Surface surface,
    inout RTXDI_DIReservoir currReservoir,
    inout ReservoirSplattingReconnectionData currReconnectionData)
{
    PathState path;
    InitialCandidates_generatePath(path, pixel, 0u);
    path.surface = surface;
    InitialCandidates_tracePath(
        lt_build_restir_di_parameters(),
        currReservoir,
        currReconnectionData,
        path
    );
}

#endif
