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

void storeEmptySurfaceOutputs() {
    position_frag_out = vec4(0.0f);
    normal_frag_out = vec4(0.0f);
    mapped_normal_frag_out = vec4(0.0f);
    albedo_frag_out = vec4(0.0f);
    motion_frag_out = vec4(0.0);
}

void storeEmptyProposalReservoirOutputs() {
    Reservoir emptyReservoir = rtxdi_empty_reservoir();
    reservoir_frag_out = rtxdi_pack_reservoir(emptyReservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(emptyReservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(emptyReservoir);
}

void main() {
    ivec2 reservoirPos = lt_current_reservoir_pos();
    if (!lt_is_active_reservoir_lane(reservoirPos)) {
        storeEmptySurfaceOutputs();
        storeEmptyProposalReservoirOutputs();
        return;
    }

    ivec2 pixelPosition = lt_current_pixel_pos();
    if (!lt_is_viewport_uv_in_bounds(pixelPosition) || !is_in_world()) {
        storeEmptySurfaceOutputs();
        storeEmptyProposalReservoirOutputs();
        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);
    rt_pos = world_pos - world_offset;
    bad_angle = is_bad_angle(world_pos, block_normal);

    DirectSurface currentSurface = lt_current_surface();
    vec3 worldPos = currentSurface.worldPos;
    vec3 geometryNormal = currentSurface.geometryNormal;
    vec3 shadingNormal = currentSurface.shadingNormal;
    vec3 surfaceAlbedo = currentSurface.albedo;

    position_frag_out = vec4(worldPos, 1.0f);
    normal_frag_out = vec4(geometryNormal, 1.0f);
    mapped_normal_frag_out = vec4(shadingNormal, 1.0f);
    albedo_frag_out = vec4(surfaceAlbedo, 1.0f);

    // RTXDI_SampleLightsForSurface: initial sampling (local lights + stubs for infinite/env/BRDF).
    // Initial visibility (RTXDI InitialSampling.hlsli:661-668) is applied INSIDE
    // RTXDI_SampleLightsForSurface on the combined reservoir, matching RTXDI structure exactly.
    Reservoir reservoir = RTXDI_SampleLightsForSurface(currentSurface);

    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = rtxdi_pack_reservoir_meta(reservoir);

    // Compute screen-space motion vector using the same current/previous pixel semantics
    // consumed by the RTXDI temporal path:
    //   motion.xy = previousPixel - currentPixel
    //   motion.z  = previousLinearDepth - currentLinearDepth
    vec2 previousPixel = ph_reprojectf(
        previous_modelview_projection,
        worldPos,
        vec2(viewWidth, viewHeight),
        vec2(0.0f)
    );
    // Match RTXDI GBufferHelpers.hlsli: motion is measured from the current pixel center,
    // not the integer pixel index. Using the integer corner injects a constant half-pixel
    // offset, which breaks round() in temporal reprojection and prevents DI history reuse.
    vec2 currentPixelCenter = vec2(pixelPosition) + vec2(0.5f);
    vec2 motionXY = previousPixel - currentPixelCenter;
    float currentLinearDepth = ph_linear_view_depth(modelview_projection, worldPos);
    float expectedPrevLinearDepth = ph_linear_view_depth(previous_modelview_projection, worldPos);
    float motionZ = expectedPrevLinearDepth - currentLinearDepth;
    motion_frag_out = vec4(motionXY, motionZ, 1.0);
}
