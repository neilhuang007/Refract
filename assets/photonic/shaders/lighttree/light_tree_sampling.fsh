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
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/lighttree/restir_di_bridge.glsl"

void storeEmptySurfaceOutputs() {
    position_frag_out = vec4(0.0f);
    normal_frag_out = vec4(0.0f);
    mapped_normal_frag_out = vec4(0.0f);
    albedo_frag_out = vec4(0.0f);
    motion_frag_out = vec4(0.0);
}

void storeEmptyProposalReservoirOutputs() {
    RTXDI_DIReservoir emptyReservoir = RTXDI_EmptyDIReservoir();
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

    RAB_Surface currentSurface = lt_current_surface();
    vec3 worldPos = currentSurface.worldPos;
    vec3 geometryNormal = currentSurface.geoNormal;
    vec3 shadingNormal = currentSurface.normal;
    vec3 surfaceAlbedo = currentSurface.material.diffuseAlbedo;

    position_frag_out = vec4(worldPos, ph_linear_view_depth(modelview_projection, worldPos));
    normal_frag_out = vec4(geometryNormal, 1.0f);
    mapped_normal_frag_out = vec4(shadingNormal, 1.0f);
    albedo_frag_out = vec4(surfaceAlbedo, 1.0f);

    RTXDI_RandomSamplerState rng = RTXDI_InitRandomSampler(uvec2(pixelPosition), uint(frameCounter), RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED);
    RTXDI_RandomSamplerState tileRng = RTXDI_InitRandomSampler(uvec2(pixelPosition / RTXDI_TILE_SIZE_IN_PIXELS), uint(frameCounter), RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED);
    const RTXDI_DIInitialSamplingParameters initialSamplingParams = lt_build_di_initial_sampling_parameters();
    RAB_LightSample lightSample = RAB_EmptyLightSample();
    RTXDI_DIReservoir reservoir = RTXDI_SampleLightsForSurface(rng, tileRng, currentSurface, initialSamplingParams, lightSample);

    reservoir_frag_out = rtxdi_pack_reservoir(reservoir);
    reservoir_sample_frag_out = rtxdi_pack_reservoir_sample(reservoir);
    reservoir_meta_frag_out = PathReservoir_packMeta(reservoir);

    vec2 currentPixelCenter = vec2(pixelPosition) + vec2(0.5f);
    motion_frag_out = ph_compute_temporal_motion(
        worldPos,
        currentPixelCenter,
        vec2(viewWidth, viewHeight)
    );
}
