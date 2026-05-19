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

// Reference current-frame reconnection payload (currReconnectionData).
// Packed as a 5-layer sampler2DArray (layers 0..4).
uniform sampler2DArray scatter_reconnections;
// Reference current-frame temporal output (currReservoirs / currReconnectionData).
uniform sampler2D temporal_reservoir_data;
uniform sampler2D temporal_reservoir_sample;
uniform sampler2D temporal_reservoir_meta;

// Reference gather-side intermediate buffers
// (intermediateReservoirs / intermediateReconnectionData).
uniform sampler2D temporal_gather_intermediate_reservoir_data;
uniform sampler2D temporal_gather_intermediate_reservoir_sample;
uniform sampler2D temporal_gather_intermediate_reservoir_meta;
// Packed as a 5-layer sampler2DArray (layers 0..4).
uniform sampler2DArray temporal_gather_intermediate_reconnections;
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
// Reference previous-frame reconnection history (prevReconnectionData).
// Packed as a 5-layer sampler2DArray (layers 0..4).
uniform sampler2DArray prev_scatter_reconnections;

uniform sampler2D prev_spec_slow_input;
uniform sampler2D prev_spec_fast_input;
uniform sampler2D prev_spec_history_length_input;

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
    if (ph_debug_show_direct < 0.5) return vec3(0.0);
    return texture(radiosity_direct, tex_coord).rgb;
}

vec3 sample_photonics_handheld(vec2 tex_coord) {
    if (ph_debug_view_mode > 0.5) return vec3(0.0);
    if (ph_debug_show_handheld < 0.5) return vec3(0.0);
    #ifdef PH_ENABLE_HANDHELD_LIGHT
    return texture(radiosity_handheld, tex_coord).rgb;
    #else
    return vec3(0.0f);
    #endif
}

vec3 sample_photonics_indirect(vec2 tex_coord) {
    if (ph_debug_view_mode > 0.5) return vec3(0.0);
    if (ph_debug_show_indirect < 0.5) return vec3(0.0);
    return texture(radiosity_indirect_resolved, tex_coord).rgb;
}

// ---------------------------------------------------------------------------
// NRD RELAX_DiffuseSpecular pipeline samplers (contract section 6).
// Java agent registers these against the corresponding FBOs.
// ---------------------------------------------------------------------------
uniform sampler2D nrd_in_tiles;                       // R8   nrdTilesFb
uniform sampler2D nrd_in_diff_radiance_hitdist;       // RGBA16F  lightingStageBuffer.direct
uniform sampler2D nrd_in_spec_radiance_hitdist;       // RGBA16F  lightingStageBuffer.direct_specular
uniform sampler2D nrd_diff_illum_ping;                // RGBA16F  nrdDiffIllumPingFb
uniform sampler2D nrd_diff_illum_pong;                // RGBA16F  nrdDiffIllumPongFb
uniform sampler2D nrd_spec_illum_ping;                // RGBA16F  nrdSpecIllumPingFb
uniform sampler2D nrd_spec_illum_pong;                // RGBA16F  nrdSpecIllumPongFb
uniform sampler2D nrd_history_length;                 // R8   nrdHistoryLengthFb
uniform sampler2D nrd_spec_reprojection_confidence;   // R8   nrdSpecReprojectionConfidenceFb
uniform sampler2D nrd_diff_illum_prev;                // RGBA16F  nrdDiffIllumPrevFb.read
uniform sampler2D nrd_diff_illum_responsive_prev;     // RGBA16F  nrdDiffIllumResponsivePrevFb.read
uniform sampler2D nrd_spec_illum_prev;                // RGBA16F  nrdSpecIllumPrevFb.read
uniform sampler2D nrd_spec_illum_responsive_prev;     // RGBA16F  nrdSpecIllumResponsivePrevFb.read
uniform sampler2D nrd_history_length_prev;            // R8   nrdHistoryLengthPrevFb.read
uniform sampler2D nrd_reflection_hit_t_curr;          // R16F nrdReflectionHitTCurrFb
uniform sampler2D nrd_reflection_hit_t_prev;          // R16F nrdReflectionHitTPrevFb.read
uniform sampler2D nrd_out_diff_radiance_hitdist;      // RGBA16F  nrdOutDiffRadianceHitDistFb
uniform sampler2D nrd_out_spec_radiance_hitdist;      // RGBA16F  nrdOutSpecRadianceHitDistFb
// A-trous ping-pong inputs (Java rebinds per pass to nrdDiffIllumPing/PongFb)
uniform sampler2D nrd_diff_atrous_input;              // RGBA16F  ping or pong (previous pass output)
uniform sampler2D nrd_spec_atrous_input;              // RGBA16F  ping or pong (previous pass output)

// Reservoir Splatting temporal pipeline uniforms
uniform float ph_reservoir_splatting_camera_aperture_radius;
uniform float ph_reservoir_splatting_artificial_frame_time;
uniform float ph_reservoir_splatting_shutter_speed;
uniform int ph_restir_active_checkerboard_field;
uniform int ph_restir_frame_index;

#endif
