#ifndef PH_LIGHTTREE_SAMPLERS_GLSL
#define PH_LIGHTTREE_SAMPLERS_GLSL

uniform sampler2D radiosity_position;
uniform sampler2D radiosity_normal;
uniform sampler2D radiosity_mapped_normal;
uniform sampler2D radiosity_albedo;
uniform sampler2D radiosity_material;
uniform sampler2D radiosity_identity;
uniform sampler2D radiosity_proposal_reservoirs;
uniform sampler2D radiosity_proposal_reservoir_samples;
uniform sampler2D radiosity_proposal_reservoir_meta;
uniform sampler2D radiosity_reservoirs;
uniform sampler2D radiosity_reservoir_samples;
uniform sampler2D radiosity_reservoir_meta;
uniform sampler2D radiosity_spatial_reservoirs;
uniform sampler2D radiosity_spatial_reservoir_samples;
uniform sampler2D radiosity_spatial_reservoir_meta;
uniform sampler2D radiosity_direct;
uniform sampler2D radiosity_direct_soft;
uniform sampler2D radiosity_handheld;
uniform sampler2D radiosity_indirect;
uniform sampler2D radiosity_indirect_resolved;
uniform sampler2D radiosity_lighting;
uniform sampler2D radiosity_lighting_variance;
uniform sampler2D radiosity_indirect_variance;
uniform sampler2D radiosity_indirect_reservoir_position;
uniform sampler2D radiosity_indirect_reservoir_normal;
uniform sampler2D radiosity_indirect_reservoir_radiance;
uniform sampler2D radiosity_indirect_reservoir_meta;
uniform sampler2D radiosity_indirect_initial_position;
uniform sampler2D radiosity_indirect_initial_normal;
uniform sampler2D radiosity_indirect_initial_radiance;
uniform sampler2D radiosity_indirect_initial_meta;
uniform sampler2D radiosity_motion;

// Shared current-stage reconnection payload read through stage-input copies.
// Historical scatter-prefixed names are retained for ABI compatibility.
uniform sampler2D scatter_reconnection0;
uniform sampler2D scatter_reconnection1;
#define current_stage_reconnection0 scatter_reconnection0
#define current_stage_reconnection1 scatter_reconnection1
// Single-buffered temporal resampling staging/output consumed within the same frame
uniform sampler2D temporal_reservoir_data;
uniform sampler2D temporal_reservoir_sample;
uniform sampler2D temporal_reservoir_meta;

// Gather-side temporal intermediates for the full Reservoir Splatting reference pipeline.
uniform sampler2D temporal_gather_floating_coords;
uniform sampler2D temporal_gather_intermediate_reservoir_data;
uniform sampler2D temporal_gather_intermediate_reservoir_sample;
uniform sampler2D temporal_gather_intermediate_reservoir_meta;
uniform sampler2D temporal_gather_intermediate_reconnection0;
uniform sampler2D temporal_gather_intermediate_reconnection1;
uniform sampler2D temporal_gather_shifted_path_data0;
uniform sampler2D temporal_gather_shifted_path_data1;
uniform sampler2D temporal_gather_shifted_path_data2;
uniform sampler2D temporal_gather_shifted_path_data3;
uniform sampler2D temporal_gather_shifted_path_data4;
uniform sampler2D temporal_gather_shifted_path_data5;
uniform sampler2D temporal_gather_shifted_path_data6;
uniform sampler2D temporal_gather_shifted_path_data7;
uniform sampler2D temporal_gather_shifted_path_data8;
uniform sampler2D temporal_gather_shifted_path_data9;
uniform sampler2D temporal_gather_shifted_path_data10;
uniform sampler2D temporal_gather_shifted_path_data11;
uniform sampler2D temporal_gather_shifted_path_data12;
uniform sampler2D temporal_gather_shifted_path_data13;
uniform sampler2D temporal_gather_shifted_path_data14;
uniform sampler2D temporal_gather_shifted_path_data15;
uniform sampler2D prev_radiosity_position;
uniform sampler2D prev_radiosity_normal;
uniform sampler2D prev_radiosity_mapped_normal;
uniform sampler2D prev_radiosity_albedo;
uniform sampler2D prev_radiosity_material;
uniform sampler2D prev_radiosity_identity;
uniform sampler2D prev_radiosity_reservoirs;
uniform sampler2D prev_radiosity_reservoir_meta;
uniform sampler2D prev_radiosity_direct;
uniform sampler2D prev_radiosity_direct_soft;
uniform sampler2D prev_radiosity_handheld;
uniform sampler2D prev_radiosity_indirect;
uniform sampler2D prev_radiosity_indirect_variance;
uniform sampler2D prev_radiosity_reservoir_samples;
uniform sampler2D prev_radiosity_indirect_reservoir_position;
uniform sampler2D prev_radiosity_indirect_reservoir_normal;
uniform sampler2D prev_radiosity_indirect_reservoir_radiance;
uniform sampler2D prev_radiosity_indirect_reservoir_meta;
uniform sampler2D prev_radiosity_lighting;
uniform sampler2D prev_radiosity_lighting_variance;
uniform sampler2D prev_radiosity_motion;
// Shared previous-frame reconnection history.
// Historical scatter-prefixed names are retained for ABI compatibility.
uniform sampler2D prev_scatter_reconnection0;
uniform sampler2D prev_scatter_reconnection1;
#define previous_frame_reconnection0 prev_scatter_reconnection0
#define previous_frame_reconnection1 prev_scatter_reconnection1

uniform sampler2D prev_spec_slow_input;
uniform sampler2D prev_spec_fast_input;
uniform sampler2D prev_spec_history_length_input;

uniform sampler2D diffuse_confidence_input;
uniform sampler2D spec_confidence_input;
uniform sampler2D spec_history_confidence_input;
uniform sampler2D spec_reprojection_confidence_input;

// Raw stage buffers are declared here because several LIGHT_TREE passes include
// this sampler header and still read the per-frame stage direct signal.
uniform sampler2D stage_radiosity_position;
uniform sampler2D stage_radiosity_normal;
uniform sampler2D stage_radiosity_direct;
uniform sampler2D stage_radiosity_direct_specular;
uniform sampler2D stage_radiosity_mapped_normal;
uniform sampler2D stage_radiosity_albedo;
uniform sampler2D stage_radiosity_material;
uniform sampler2D stage_radiosity_identity;
uniform sampler2D stage_radiosity_handheld;
uniform sampler2D stage_radiosity_indirect;

uniform float ph_debug_show_direct;
uniform float ph_debug_show_indirect;
uniform float ph_debug_show_handheld;
uniform float ph_debug_view_mode;

vec3 sample_photonics_direct(vec2 tex_coord) {
    if (ph_debug_view_mode > 0.5) {
        // Debug overlay: return bright debug color so it survives albedo multiply
        return texture2D(radiosity_direct, tex_coord).rgb * 10.0;
    }
    if (ph_debug_show_direct < 0.5) return vec3(0.0);
    return texture2D(radiosity_direct, tex_coord).rgb;
}

vec3 sample_photonics_handheld(vec2 tex_coord) {
    if (ph_debug_view_mode > 0.5) return vec3(0.0);
    if (ph_debug_show_handheld < 0.5) return vec3(0.0);
    #ifdef PH_ENABLE_HANDHELD_LIGHT
    return texture2D(radiosity_handheld, tex_coord).rgb;
    #else
    return vec3(0.0f);
    #endif
}

vec3 sample_photonics_indirect(vec2 tex_coord) {
    if (ph_debug_view_mode > 0.5) return vec3(0.0);
    if (ph_debug_show_indirect < 0.5) return vec3(0.0);
    return texture2D(radiosity_indirect_resolved, tex_coord).rgb;
}

#endif
