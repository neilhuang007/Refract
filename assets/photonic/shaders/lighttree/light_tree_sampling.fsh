#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 position_frag_out;
layout(location = 1) out vec4 normal_frag_out;
layout(location = 2) out vec4 mapped_normal_frag_out;
layout(location = 3) out vec4 albedo_frag_out;
layout(location = 4) out vec4 motion_frag_out;  // screen-space motion vector (RTXDI convention)
layout(location = 5) out vec4 reservoir_frag_out;
layout(location = 6) out vec4 reservoir_sample_frag_out;
layout(location = 7) out vec4 reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"

void main() {
    if (!is_in_world()) {
        position_frag_out = vec4(0.0f);
        normal_frag_out = vec4(0.0f);
        mapped_normal_frag_out = vec4(0.0f);
        albedo_frag_out = vec4(0.0f);
        motion_frag_out = vec4(0.0);
        Reservoir emptyReservoir = rtxdi_empty_reservoir();
        reservoir_frag_out = rtxdi_pack_reservoir(emptyReservoir);
        reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(emptyReservoir);
        reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(emptyReservoir);
        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);
    rt_pos = world_pos - world_offset;
    bad_angle = is_bad_angle(world_pos, block_normal);

    position_frag_out = vec4(world_pos, 1.0f);
    normal_frag_out = vec4(normalize(block_normal), 1.0f);
    mapped_normal_frag_out = vec4(normalize(normal), 1.0f);
    albedo_frag_out = vec4(clamp(albedo, vec3(0.0f), vec3(1.0f)), 1.0f);

    DirectSurface currentSurface = lt_current_surface();

    // RTXDI_SampleLightsForSurface: initial sampling (local lights + stubs for infinite/env/BRDF).
    // Initial visibility (RTXDI InitialSampling.hlsli:661-668) is applied INSIDE
    // RTXDI_SampleLightsForSurface on the combined reservoir, matching RTXDI structure exactly.
    Reservoir reservoir = RTXDI_SampleLightsForSurface(currentSurface);

    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(reservoir);

    // Compute screen-space motion vector matching RTXDI's screenSpaceMotion convention:
    //   motion.xy = previousPixel - currentPixel  (RTXDI: prevPos = pixelPosition + motion.xy)
    //   motion.z  = expectedPrevLinearDepth - currentLinearDepth  (depth delta)
    // RTXDI convention: motion.xy = previousPixel - pixelPosition (integer pixel coords).
    // prevPos = pixelPosition + motion.xy = previousPixel.
    vec2 pixelPosition = vec2(tex_coord);  // integer pixel coordinate (matches RTXDI uint2 pixelPosition)
    vec2 previousPixel = ph_reprojectf(
        previous_modelview_projection,
        world_pos,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    );
    vec2 motionXY = previousPixel - pixelPosition;
    float currentLinearDepth = length(world_pos - world_camera_position);
    float expectedPrevLinearDepth = length(world_pos - previous_world_camera_position);
    float motionZ = expectedPrevLinearDepth - currentLinearDepth;
    motion_frag_out = vec4(motionXY, motionZ, 1.0);
}
