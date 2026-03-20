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
    if (!is_in_world()) {
        indirect_initial_position_frag_out = initialStore.positionData;
        indirect_initial_normal_frag_out = initialStore.normalData;
        indirect_initial_radiance_frag_out = initialStore.radianceData;
        indirect_initial_meta_frag_out = initialStore.metaData;
        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);
    rt_pos = world_pos - world_offset;
    bad_angle = is_bad_angle(world_pos, block_normal);

    RTXDI_GIReservoir reservoir = gi_build_initial_reservoir(lt_current_surface());
    initialStore = gi_make_reservoir_store(reservoir);
    indirect_initial_position_frag_out = initialStore.positionData;
    indirect_initial_normal_frag_out = initialStore.normalData;
    indirect_initial_radiance_frag_out = initialStore.radianceData;
    indirect_initial_meta_frag_out = initialStore.metaData;
}
