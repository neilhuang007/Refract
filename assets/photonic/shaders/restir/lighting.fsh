#version 430

/*
    -- INPUT VARIABLES --
*/
in vec4 direction_vert_out;

/*
    -- OUTPUT VARIABLES --
*/
layout(location = 0) out vec4 reservoir_frag_out;
layout(location = 1) out vec4 lighting_frag_out;

#ifdef PH_ENABLE_HANDHELD_LIGHT
layout(location = 2) out vec4 handheld_frag_out;
#define PH_INDIRECT_OUT_LOCATION 3
#define PH_GI_RESERVOIR_POS_OUT_LOCATION 4
#define PH_GI_RESERVOIR_NORMAL_OUT_LOCATION 5
#define PH_GI_RESERVOIR_RADIANCE_OUT_LOCATION 6
#define PH_GI_RESERVOIR_META_OUT_LOCATION 7
#else
#define PH_INDIRECT_OUT_LOCATION 2
#define PH_GI_RESERVOIR_POS_OUT_LOCATION 3
#define PH_GI_RESERVOIR_NORMAL_OUT_LOCATION 4
#define PH_GI_RESERVOIR_RADIANCE_OUT_LOCATION 5
#define PH_GI_RESERVOIR_META_OUT_LOCATION 6
#endif

layout(location = PH_INDIRECT_OUT_LOCATION) out vec4 indirect_frag_out;
layout(location = PH_GI_RESERVOIR_POS_OUT_LOCATION) out vec4 gi_reservoir_pos_frag_out;
layout(location = PH_GI_RESERVOIR_NORMAL_OUT_LOCATION) out vec4 gi_reservoir_normal_frag_out;
layout(location = PH_GI_RESERVOIR_RADIANCE_OUT_LOCATION) out vec4 gi_reservoir_radiance_frag_out;
layout(location = PH_GI_RESERVOIR_META_OUT_LOCATION) out vec4 gi_reservoir_meta_frag_out;

#include "/photonics/common/header.glsl"

const float ph_spatial_reuse_radius = PH_RESTIR_SPATIAL_REUSE_RADIUS * PH_RENDER_SCALE;
vec3 ph_sun_direction = ph_signed_nudge(sun_direction);
const vec3 INDIRECT_LUMA_COEFF = vec3(0.2126f, 0.7152f, 0.0722f);
const float INDIRECT_REPROJECT_NORMAL_THRESHOLD = 0.975f;
const float INDIRECT_REPROJECT_POSITION_THRESHOLD_SQ = 0.2f;
const float INDIRECT_REUSE_NORMAL_THRESHOLD = 0.93f;
const float INDIRECT_REUSE_POSITION_THRESHOLD_SQ = 0.35f;
const float INDIRECT_TEMPORAL_GRADIENT_START = 0.35f;
const float INDIRECT_TEMPORAL_RESPONSE_SCALE = 0.25f;
const float INDIRECT_EDGE_HISTORY_RESPONSE = 0.2f;
const float GI_MIS_ROUGHNESS_FLOOR = 0.3f;
const float GI_MIS_GLOSS_THRESHOLD = 0.15f;
const float GI_MIS_MAX_RESPONSE = 1e4f;
const float GI_DISOCCLUSION_BOOST_AGE = 4.0f;
const float GI_DISOCCLUSION_BOOST_SAMPLES = 3.0f;
const float GI_BOILING_FILTER_STRENGTH = 0.75f;
const int GI_BOILING_FILTER_RADIUS = 1;

#include "/photonics/restir/restir.glsl"
#include "/photonics/common/lighting.glsl"

vec3 clamp_indirect_luma(vec3 color, float maxLuma) {
    float lum = dot(color, INDIRECT_LUMA_COEFF);
    if (lum > maxLuma) {
        return color * (maxLuma / max(lum, 1e-4f));
    }
    return color;
}

bool indirect_reproject(out vec4 indirect) {
    vec2 uv = ph_reprojectf(
        previous_modelview_projection,
        world_pos + block_normal * 0.01f,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    );

    ivec2 prev_uv = ivec2(uv);
    ivec2 tex_size = textureSize(prev_radiosity_indirect, 0);
    if (any(lessThan(prev_uv, ivec2(0))) || any(greaterThanEqual(prev_uv, tex_size))) return false;

    vec3 n = texelFetch(prev_radiosity_normal, prev_uv, 0).xyz;
    if (dot(n, block_normal) < INDIRECT_REPROJECT_NORMAL_THRESHOLD) return false;

    vec3 prev_rt_pos = texelFetch(prev_radiosity_position, prev_uv, 0).xyz - world_offset;
    if (!ph_surface_positions_compatible(rt_pos, prev_rt_pos, INDIRECT_REPROJECT_POSITION_THRESHOLD_SQ)) return false;

    indirect = texelFetch(prev_radiosity_indirect, prev_uv, 0);
    return !any(isnan(indirect)) && indirect.a > 0.0f;
}

bool indirect_reuse_neighbor(ivec2 uv, out vec4 indirect) {
    ivec2 tex_size = textureSize(prev_radiosity_indirect, 0);
    if (any(lessThan(uv, ivec2(0))) || any(greaterThanEqual(uv, tex_size))) return false;

    vec3 n = texelFetch(prev_radiosity_normal, uv, 0).xyz;
    if (dot(n, block_normal) < INDIRECT_REUSE_NORMAL_THRESHOLD) return false;

    vec3 neighbor_rt_pos = texelFetch(prev_radiosity_position, uv, 0).xyz - world_offset;
    if (!ph_surface_positions_compatible(rt_pos, neighbor_rt_pos, INDIRECT_REUSE_POSITION_THRESHOLD_SQ)) return false;

    indirect = texelFetch(prev_radiosity_indirect, uv, 0);
    return !any(isnan(indirect)) && indirect.a > 0.0f;
}

float indirect_surface_similarity(ivec2 uv, bool previous_frame) {
    vec3 n = previous_frame ? texelFetch(prev_radiosity_normal, uv, 0).xyz : texelFetch(radiosity_normal, uv, 0).xyz;
    float normalWeight = clamp(dot(n, block_normal), 0.0f, 1.0f);

    vec3 pos = previous_frame ? texelFetch(prev_radiosity_position, uv, 0).xyz - world_offset : texelFetch(radiosity_position, uv, 0).xyz - world_offset;
    vec3 d = pos - rt_pos;
    float positionWeight = exp(-dot(d, d) * 6.0f);

    return normalWeight * positionWeight;
}

float gi_gloss_proxy() {
    vec3 shadingNormal = normalize(normal);
    vec3 viewDirection = normalize(rt_camera_position - rt_pos);
    float flatness = smoothstep(0.92f, 0.995f, clamp(dot(shadingNormal, block_normal), 0.0f, 1.0f));
    float grazing = smoothstep(0.2f, 0.75f, 1.0f - clamp(dot(shadingNormal, viewDirection), 0.0f, 1.0f));
    return flatness * grazing;
}

float gi_specular_power(float roughnessProxy) {
    return mix(64.0f, 8.0f, clamp(roughnessProxy, 0.0f, 1.0f));
}

float gi_surface_response(GISample giSample, float roughnessProxy) {
    if (!gi_sample_is_valid(giSample)) {
        return 0.0f;
    }

    vec3 shadingNormal = normalize(normal);
    vec3 viewDirection = normalize(rt_camera_position - rt_pos);
    vec3 sampleDirection = gi_sample_direction(giSample);
    float diffuse = max(dot(shadingNormal, sampleDirection), 0.0f);
    float specular = pow(max(dot(reflect(-viewDirection, shadingNormal), sampleDirection), 0.0f), gi_specular_power(roughnessProxy));
    return ph_luminance(giSample.radiance) * max(mix(diffuse, specular, gi_gloss_proxy()), 0.0f);
}

float gi_get_mis_weight(float roughResponse, float trueResponse) {
    roughResponse = clamp(roughResponse, 1e-4f, GI_MIS_MAX_RESPONSE);
    trueResponse = clamp(trueResponse, 0.0f, GI_MIS_MAX_RESPONSE);
    float initialWeight = clamp(trueResponse / max(trueResponse + roughResponse, 1e-4f), 0.0f, 1.0f);
    return initialWeight * initialWeight * initialWeight;
}

float gi_temporal_buffer_weighted_radiance(ivec2 uv) {
    ivec2 texSize = textureSize(radiosity_gi_reservoir_pos, 0);
    if (any(lessThan(uv, ivec2(0))) || any(greaterThanEqual(uv, texSize))) {
        return 0.0f;
    }

    vec4 posData = texelFetch(radiosity_gi_reservoir_pos, uv, 0);
    vec4 radianceData = texelFetch(radiosity_gi_reservoir_radiance, uv, 0);
    vec4 metaData = texelFetch(radiosity_gi_reservoir_meta, uv, 0);
    if (posData.w <= 0.0f || radianceData.w == 0.0f || metaData.x <= 0.0f) {
        return 0.0f;
    }

    return ph_luminance(max(radianceData.rgb, vec3(0.0f))) * posData.w;
}

bool gi_should_reject_boiling_reservoir(GIReservoir giReservoir) {
    if (!gi_reservoir_is_valid(giReservoir)) {
        return false;
    }

    float reservoirWeight = ph_luminance(giReservoir.giSample.radiance) * giReservoir.weight;
    if (reservoirWeight <= 0.0f) {
        return false;
    }

    float sumWeight = 0.0f;
    int nonzeroCount = 0;
    for (int yy = -GI_BOILING_FILTER_RADIUS; yy <= GI_BOILING_FILTER_RADIUS; yy++) {
        for (int xx = -GI_BOILING_FILTER_RADIUS; xx <= GI_BOILING_FILTER_RADIUS; xx++) {
            float neighborWeight = gi_temporal_buffer_weighted_radiance(tex_coord + ivec2(xx, yy));
            if (neighborWeight > 0.0f) {
                sumWeight += neighborWeight;
                nonzeroCount++;
            }
        }
    }

    if (nonzeroCount == 0) {
        return false;
    }

    // RTXDI's GI boiling filter compares weighted radiance against the
    // neighborhood average and discards reservoirs that are far above it.
    float averageNonzeroWeight = sumWeight / float(nonzeroCount);
    float boilingFilterMultiplier = 10.0f / clamp(GI_BOILING_FILTER_STRENGTH, 1e-6f, 1.0f) - 9.0f;
    return reservoirWeight > averageNonzeroWeight * boilingFilterMultiplier;
}

void main() {
    if (!is_in_world()) {
        reservoir_frag_out = vec4(0f);
        lighting_frag_out = vec4(0f);
        indirect_frag_out = vec4(0f);
        gi_reservoir_pos_frag_out = vec4(0f);
        gi_reservoir_normal_frag_out = vec4(0f);
        gi_reservoir_radiance_frag_out = vec4(0f);
        gi_reservoir_meta_frag_out = vec4(0f);
        #ifdef PH_ENABLE_HANDHELD_LIGHT
        handheld_frag_out = vec4(0f);
        #endif

        return;
    }

    load_fragment_variables(albedo, world_pos, block_normal, normal);
    rt_pos = world_pos - world_offset;
    bad_angle = is_bad_angle(world_pos, block_normal);

    #ifdef PH_ENABLE_HANDHELD_LIGHT
    sample_handheld(handheld_frag_out);
    #endif

    indirect_frag_out = vec4(0f);
    gi_reservoir_pos_frag_out = vec4(0f);
    gi_reservoir_normal_frag_out = vec4(0f);
    gi_reservoir_radiance_frag_out = vec4(0f);
    gi_reservoir_meta_frag_out = vec4(0f);

    #ifdef PH_ENABLE_GI
    RAY_ITERATION_COUNT = 20;

    GIReservoir giReservoir = gi_reservoir_new();
    vec3 giSourcePosition = vec3(0.0f);
    vec3 giSourceNormal = vec3(0.0f);
    bool hasGiReservoir = gi_reservoir_load_current(giReservoir, tex_coord, giSourcePosition, giSourceNormal);

    if (hasGiReservoir) {
        GIReservoir giSpatialReservoir = gi_reservoir_new();
        float centerGiSamples = giReservoir.samples;
        bool centerGiVisible = gi_sample_has_conservative_visibility_from_surface(
            giReservoir.giSample,
            giSourcePosition,
            giSourceNormal
        );
        bool centerGiContributed = false;
        if (centerGiVisible) {
            centerGiContributed = true;
            gi_reservoir_update(
                giSpatialReservoir,
                giReservoir.giSample,
                gi_sample_target(giReservoir.giSample) * giReservoir.weight * giReservoir.samples,
                giReservoir.samples,
                giReservoir.age
            );
        }

        int giSpatialSamples = PH_RESTIR_SPATIAL_REUSE_SAMPLES;
        float giReuseRadius = ph_spatial_reuse_radius;
        uint giSpatialLoopRngState = rng_state;

        for (int i = 0; i < giSpatialSamples; i++) {
            float radius = sqrt(rand_next_float()) * giReuseRadius;
            float angle = rand_next_float() * 2.0f * 3.14159265359f;
            ivec2 uv = ivec2(tex_coord + vec2(cos(angle), sin(angle)) * radius);

            GIReservoir neighborGiReservoir = gi_reservoir_new();
            vec3 neighborSourcePosition = vec3(0.0f);
            vec3 neighborSourceNormal = vec3(0.0f);
            if (!gi_reservoir_load_current(neighborGiReservoir, uv, neighborSourcePosition, neighborSourceNormal)) {
                continue;
            }
            if (!gi_sample_has_conservative_visibility_from_surface(
                neighborGiReservoir.giSample,
                neighborSourcePosition,
                neighborSourceNormal
            )) {
                continue;
            }

            float jacobian = gi_jacobian(neighborSourcePosition, neighborGiReservoir.giSample);
            if (!gi_validate_jacobian(jacobian)) {
                continue;
            }

            gi_reservoir_update(
                giSpatialReservoir,
                neighborGiReservoir.giSample,
                gi_sample_target(neighborGiReservoir.giSample) * neighborGiReservoir.weight * neighborGiReservoir.samples / jacobian,
                neighborGiReservoir.samples,
                neighborGiReservoir.age
            );
        }
        uint giSpatialLoopPostState = rng_state;

        giReservoir = giSpatialReservoir;
        float normalizationDenominator = 0.0f;
        if (gi_sample_is_valid(giReservoir.giSample)) {
            if (centerGiContributed) {
                normalizationDenominator += centerGiSamples * gi_sample_target(giReservoir.giSample);
            }

            rng_state = giSpatialLoopRngState;
            for (int i = 0; i < giSpatialSamples; i++) {
                float radius = sqrt(rand_next_float()) * giReuseRadius;
                float angle = rand_next_float() * 2.0f * 3.14159265359f;
                ivec2 uv = ivec2(tex_coord + vec2(cos(angle), sin(angle)) * radius);

                GIReservoir neighborGiReservoir = gi_reservoir_new();
                vec3 neighborSourcePosition = vec3(0.0f);
                vec3 neighborSourceNormal = vec3(0.0f);
                if (!gi_reservoir_load_current(neighborGiReservoir, uv, neighborSourcePosition, neighborSourceNormal)) {
                    continue;
                }
                if (!gi_sample_has_conservative_visibility_from_surface(
                    neighborGiReservoir.giSample,
                    neighborSourcePosition,
                    neighborSourceNormal
                )) {
                    continue;
                }

                float candidateJacobian = gi_jacobian(neighborSourcePosition, neighborGiReservoir.giSample);
                if (!gi_validate_jacobian(candidateJacobian)) {
                    continue;
                }

                float selectedJacobian = gi_jacobian(neighborSourcePosition, giReservoir.giSample);
                if (!gi_validate_jacobian(selectedJacobian)) {
                    continue;
                }

                normalizationDenominator += neighborGiReservoir.samples * gi_sample_target_from_source_surface(
                    giReservoir.giSample,
                    neighborSourcePosition,
                    neighborSourceNormal
                );
            }
            rng_state = giSpatialLoopPostState;
        }

        gi_reservoir_finalize(giReservoir, normalizationDenominator);
    }

    if (gi_reservoir_is_valid(giReservoir)) {
        float resolvedBrdfFactor = gi_sample_receiver_cosine_at_surface(
            giReservoir.giSample,
            rt_pos,
            block_normal
        ) * PH_INV_PI;
        vec3 resolvedIndirect = gi_sample_trace_visibility(giReservoir.giSample)
            * (giReservoir.weight * resolvedBrdfFactor);
        indirect_frag_out = vec4(ph_clamp_indirect_radiance(resolvedIndirect), 1.0f);
    }
    if (indirect_frag_out.a <= 0.0f) {
        indirect_frag_out = vec4(0.0f);
        giReservoir = gi_reservoir_new();
    }

    gi_reservoir_encode(
        giReservoir,
        gi_reservoir_pos_frag_out,
        gi_reservoir_normal_frag_out,
        gi_reservoir_radiance_frag_out,
        gi_reservoir_meta_frag_out
    );

    RAY_ITERATION_COUNT = 100;
    #endif

    if (ph_light_count == 0) {
        reservoir_frag_out = vec4(-1.0f, 0.0f, 0.0f, 0.0f);
        lighting_frag_out = vec4(0f);
        return;
    }

    Reservoir reservoir = reservoir_new();
    vec4 frag = texelFetch(radiosity_reservoirs, tex_coord, 0);

    reservoir_decode(reservoir, frag, rt_pos, false);
    Reservoir temp_reservoir = reservoir_new();

    int spatial_samples = PH_RESTIR_SPATIAL_REUSE_SAMPLES;
    if (reservoir.samples <= float(PH_RESTIR_INITIAL_SAMPLES)) {
        spatial_samples *= 3;
    }
    float effectiveRadius = ph_spatial_reuse_radius;

    for (int i = 0; i < spatial_samples; i++) {
        float radius = sqrt(rand_next_float()) * effectiveRadius;
        float angle = rand_next_float() * 2.0f * 3.14159265359f;
        vec2 offset = vec2(cos(angle), sin(angle)) * radius;
        ivec2 uv = ivec2(tex_coord + offset);

        if (!reservoir_reuse(temp_reservoir, uv)) continue;

        reservoir_update(
            reservoir,
            temp_reservoir.light,
            temp_reservoir.light.weight * temp_reservoir.weight * temp_reservoir.samples,
            temp_reservoir.samples
        );
    }

    if (reservoir_is_valid(reservoir)) {
        // Bitterli 2020 Algorithms 4/5 keep M as the sum of reused reservoir
        // candidate counts. reservoir_update() already accumulated that for us.

        #ifdef PH_RESTIR_SOFT_SHADOWS
        light_sample_trace_hit(reservoir.light, true);
        #else
        light_sample_trace_hit(reservoir.light, false);
        #endif

        reservoir_compute_weight(reservoir);

        reservoir_frag_out = reservoir_encode(reservoir);
        lighting_frag_out = vec4(reservoir.light.color * reservoir.weight, 1f);
    } else {
        reservoir_frag_out = reservoir_encode(reservoir);
        lighting_frag_out = vec4(0f);
    }
}
