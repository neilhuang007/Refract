#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 indirect_initial_position_frag_out;
layout(location = 1) out vec4 indirect_initial_normal_frag_out;
layout(location = 2) out vec4 indirect_initial_radiance_frag_out;
layout(location = 3) out vec4 indirect_initial_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/restir_gi_bridge.glsl"

void lt_emit_gi_initial_store(RTXDI_GIReservoirStore store) {
    indirect_initial_position_frag_out = store.positionData;
    indirect_initial_normal_frag_out = store.normalData;
    indirect_initial_radiance_frag_out = store.radianceData;
    indirect_initial_meta_frag_out = store.metaData;
}

void main() {
    RTXDI_GIReservoirStore emptyStore = gi_make_invalid_reservoir_store();
    ivec2 reservoirPos = lt_current_reservoir_pos();
    if (!lt_is_active_reservoir_lane(reservoirPos)) {
        lt_emit_gi_initial_store(emptyStore);
        return;
    }

    // Reference parity: InitialCandidates::run always produces a reservoir per pixel,
    // including the primary-miss path (handlePrimaryMiss + addCandidateReservoir).
    RAB_Surface currentSurface = lt_load_surface(tex_coord);
    if (!lt_is_valid_surface(currentSurface)) {
        vec3 primaryRayDir = normalize(direction_vert_out.xyz);
        lt_emit_gi_initial_store(gi_build_primary_miss_initial_reservoir_store(world_camera_position, primaryRayDir));
        return;
    }

    lt_emit_gi_initial_store(gi_build_initial_reservoir_store(currentSurface));
}
