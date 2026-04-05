#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 indirect_initial_position_frag_out;
layout(location = 1) out vec4 indirect_initial_normal_frag_out;
layout(location = 2) out vec4 indirect_initial_radiance_frag_out;
layout(location = 3) out vec4 indirect_initial_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/restir_gi_bridge.glsl"

void main() {
    RTXDI_GIReservoirStore initialStore = gi_make_invalid_reservoir_store();
    RAB_Surface currentSurface = lt_load_surface(tex_coord);
    if (!lt_is_valid_surface(currentSurface)) {
        indirect_initial_position_frag_out = initialStore.positionData;
        indirect_initial_normal_frag_out = initialStore.normalData;
        indirect_initial_radiance_frag_out = initialStore.radianceData;
        indirect_initial_meta_frag_out = initialStore.metaData;
        return;
    }

    initialStore = gi_build_initial_reservoir_store(currentSurface);
    indirect_initial_position_frag_out = initialStore.positionData;
    indirect_initial_normal_frag_out = initialStore.normalData;
    indirect_initial_radiance_frag_out = initialStore.radianceData;
    indirect_initial_meta_frag_out = initialStore.metaData;
}
