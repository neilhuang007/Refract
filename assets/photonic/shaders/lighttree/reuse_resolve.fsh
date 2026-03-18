#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 direct_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/nrd_common.glsl"


const float lt_spatial_reuse_radius = 2.5f * PH_RENDER_SCALE;
const float lt_direct_max_history = 48.0f;

vec4 lt_encode_direct_output(vec3 lighting, float hitDistance, vec3 albedoColor) {
    return nrd_pack_direct_signal(max(lighting, vec3(0.0f)), hitDistance);
}

bool lt_is_valid_reservoir(Reservoir reservoir) {
    return reservoir_is_valid(reservoir);
}

void lt_merge_reservoir(inout Reservoir dst, Reservoir src) {
    if (!lt_is_valid_reservoir(src)) {
        return;
    }
    reservoir_update(
        dst,
        src.light,
        src.light.weight * src.weight * src.samples,
        src.samples
    );
}

void main() {
    if (!is_in_world()) {
        reservoir_frag_out = vec4(0.0f);
        direct_frag_out = vec4(0.0f);
        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);
    rt_pos = world_pos - world_offset;
    bad_angle = is_bad_angle(world_pos, block_normal);

    Reservoir reservoir = reservoir_new();
    reservoir_decode(reservoir, texelFetch(radiosity_reservoirs, tex_coord, 0), rt_pos, false);

    Reservoir mergedReservoir = reservoir_new();
    lt_merge_reservoir(mergedReservoir, reservoir);

    Reservoir previousReservoir = reservoir_new();
    if (reservoir_reproject(previousReservoir)) {
        previousReservoir.samples = min(20.0f * max(reservoir.samples, 1.0f), previousReservoir.samples);
        lt_merge_reservoir(mergedReservoir, previousReservoir);
    }

    Reservoir spatialReservoir = reservoir_new();
    for (int i = 0; i < PH_LIGHTTREE_SPATIAL_REUSE_SAMPLES; i++) {
        vec2 offset = 2.0 * vec2(rand_next_float(), rand_next_float()) - 1.0f;
        ivec2 uv = ivec2(vec2(tex_coord) + offset * lt_spatial_reuse_radius);
        if (!reservoir_reuse(spatialReservoir, uv)) {
            continue;
        }
        lt_merge_reservoir(mergedReservoir, spatialReservoir);
    }

    if (!lt_is_valid_reservoir(mergedReservoir)) {
        reservoir_frag_out = reservoir_encode(reservoir_new());
        direct_frag_out = vec4(0.0f);
        return;
    }

    float directHitDistance = 0.0f;
    #ifdef PH_LIGHTTREE_SOFT_SHADOWS
    directHitDistance = light_sample_trace_hit(mergedReservoir.light, true);
    #else
    directHitDistance = light_sample_trace_hit(mergedReservoir.light, false);
    #endif
    reservoir_compute_weight(mergedReservoir);
    vec3 shadedDirect = mergedReservoir.light.color * mergedReservoir.weight * result_tint_color;
    reservoir_frag_out = reservoir_encode(mergedReservoir);

    direct_frag_out = lt_encode_direct_output(shadedDirect, directHitDistance, albedo);
}
