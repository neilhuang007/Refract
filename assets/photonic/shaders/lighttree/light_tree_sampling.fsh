#version 430

in vec4 direction_vert_out;

layout(location = 0) out vec4 position_frag_out;
layout(location = 1) out vec4 normal_frag_out;
layout(location = 2) out vec4 mapped_normal_frag_out;
layout(location = 3) out vec4 reservoir_frag_out;

#include "/photonics/common/header.glsl"
#include "/photonics/lighttree/reuse_bridge.glsl"
#include "/photonics/lighttree/light_tree.glsl"
#include "/photonics/common/lighting.glsl"

uniform float ph_direct_sample_budget_scale;

const int lt_sample_count = PH_LIGHTTREE_INITIAL_SAMPLES;
const int lt_min_sample_count = 2;

vec4 lt_encode_direct_proposal(Reservoir reservoir) {
    if (!reservoir_is_valid(reservoir) || reservoir.weight_sum <= 0.0f || reservoir.samples <= 0.0f) {
        return reservoir_encode(reservoir_new());
    }

    reservoir_compute_weight(reservoir);
    return reservoir_encode(reservoir);
}

vec4 lt_build_direct_proposal(vec3 shadingPos, vec3 shadingNormal, vec3 mappedNormal, vec3 albedoColor, inout uint rng) {
    if (ph_light_count <= 0 || ph_light_tree_node_count <= 0) {
        return reservoir_encode(reservoir_new());
    }

    int sampleCount = int(round(float(lt_sample_count) * ph_direct_sample_budget_scale));
    sampleCount = clamp(sampleCount, lt_min_sample_count, lt_sample_count);

    // Adaptive splitting seeds the ReSTIR DI proposal reservoir with multiple
    // candidates from high-variance subtrees before we spend the remaining
    // budget on additional stochastic picks from the same tree.
    float splitThreshold = 0.75f;
    int lightIndices[8];
    float lightPdfs[8];
    for (int i = 0; i < 8; i++) { lightIndices[i] = -1; lightPdfs[i] = 0.0f; }

    int splitLightCount = lt_get_lights_split(
        shadingPos, shadingNormal, mappedNormal, albedoColor,
        splitThreshold, rng, lightIndices, lightPdfs, min(sampleCount, 8)
    );

    Reservoir reservoir = reservoir_new();

    // Process lights from adaptive splitting
    for (int i = 0; i < splitLightCount; i++) {
        if (lightIndices[i] < 0 || lightPdfs[i] <= 0.0f) continue;

        LightSample smple = light_sample_decode(float(lightIndices[i]), shadingPos, false);
        if (smple.index < 0 || smple.weight <= 0.0f) continue;

        reservoir_update(reservoir, smple, smple.weight / lightPdfs[i], 1.0f);
    }

    // Additional pure PickLight samples for remaining budget
    for (int s = splitLightCount; s < sampleCount; s++) {
        float xi = float(ph_rand_pcg(rng)) / 4294967295.0f;
        int lightIndex = -1;
        float lightPdf = 0.0f;

        if (!lt_pick_light(shadingPos, shadingNormal, mappedNormal, albedoColor, xi, lightIndex, lightPdf)) {
            continue;
        }
        if (lightIndex < 0 || lightPdf <= 0.0f) continue;

        LightSample smple = light_sample_decode(float(lightIndex), shadingPos, false);
        if (smple.index < 0 || smple.weight <= 0.0f) continue;

        reservoir_update(reservoir, smple, smple.weight / lightPdf, 1.0f);
    }

    return lt_encode_direct_proposal(reservoir);
}

vec4 lt_build_indirect_stage(vec3 shadingPos, vec3 shadingNormal) {
    ivec3 inside = ivec3(lessThan(abs(fract(shadingPos) - 0.5f), vec3(0.48f)));
    bool onEdge = inside.x + inside.y + inside.z <= 1;

    vec3 indirectLighting = ph_trace_surface_radiance(shadingPos, shadingNormal, 0, 2);
    if (!onEdge) {
        ph_seed_indirect_cache(world_pos, block_normal, indirectLighting);
    }

    return vec4(indirectLighting, 1.0f);
}

void main() {
    if (!is_in_world()) {
        position_frag_out = vec4(0.0f);
        normal_frag_out = vec4(0.0f);
        mapped_normal_frag_out = vec4(0.0f);
        reservoir_frag_out = vec4(0.0f);
        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);
    rt_pos = world_pos - world_offset;
    bad_angle = is_bad_angle(world_pos, block_normal);

    if (ph_debug_freeze_rng > 0.5f) {
        rng_state = uint(uint(gl_FragCoord.x) * uint(1973) + uint(gl_FragCoord.y) * uint(9277)) | uint(1);
    }

    position_frag_out = vec4(world_pos, 1.0f);
    normal_frag_out = vec4(normalize(block_normal), 1.0f);
    mapped_normal_frag_out = vec4(normalize(normal), 1.0f);

    uint lt_rng = rng_state;
    if (ph_debug_lock_traversal_rng > 0.5f) {
        rng_state = lt_rng;
    }

    reservoir_frag_out = lt_build_direct_proposal(rt_pos, block_normal, normal, albedo, lt_rng);
}
