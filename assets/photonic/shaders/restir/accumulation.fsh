#version 430

/*
    -- INPUT VARIABLES --
*/
in vec4 direction_vert_out;

/*
    -- OUTPUT VARIABLES --
*/
layout(location = 3) out vec4 lighting_frag_out;
layout(location = 4) out vec4 lighting_variance_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/restir/restir.glsl"

void main() {
    if (ph_light_count == 0 || !is_in_world()) {
        lighting_frag_out = vec4(0f);
        lighting_variance_frag_out = vec4(0f);

        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);
    rt_pos = world_pos - world_offset;
    bad_angle = is_bad_angle(world_pos, block_normal);

    SampleHistory smple;
    sample_history_load(smple);

    SampleHistory accumulator;
    sample_history_reproject(accumulator);


    sample_history_combine_lighting(accumulator, smple);

    #if PH_RESTIR_DENOISER_PASSES != 0
    sample_history_combine_moment(accumulator, smple);
    sample_history_compute_variance(accumulator, smple);
    #endif

    lighting_frag_out = accumulator.lighting;
    lighting_variance_frag_out = accumulator.variance;
}