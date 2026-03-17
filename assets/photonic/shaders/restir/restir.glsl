#ifndef PH_RESTIR_INCLUDE
#define PH_RESTIR_INCLUDE

float light_importance = ph_light_count > 0 ? 1f / ph_light_count : 0f;
vec3 ph_trace_surface_radiance(vec3 surfacePos, vec3 surfaceNormal, int sampleIndexBase, int remainingBounces);
void ph_seed_indirect_cache(vec3 samplePosition, vec3 sampleNormal, vec3 color);

struct LightSample {
    int index; // Index of the light
    vec3 position; // The position of the light
    vec3 sample_pos;
    vec3 color; // The sampled color
    vec3 dir; // Normalized direction from the fragment to the light

    float weight;
};

LightSample NULL_SAMPLE = LightSample(-1, vec3(0f), vec3(0f), vec3(0f), vec3(0f), 0f);

void light_sample_compute_weight(inout LightSample smple) {
    smple.weight = ph_luminance(smple.color);
}

LightSample light_sample_new(Light light, vec3 sample_pos) {
    vec3 to_light = light.position - sample_pos;
    float distance_squared = dot(to_light, to_light) * light.falloff;
    vec3 light_dir = distance_squared > 0.0f ? normalize(to_light) : vec3(0.0f);

    LightSample result = LightSample(
        light.index,
        light.position,
        sample_pos,
        vec3(0f),
        light_dir,
        0f
    );

    result.color = light.color / dot(vec2(1, distance_squared), light.attenuation);
    result.color *= max(dot(light_dir, normal), 0.0f);
    result.color *= step(0.001f, ph_luminance(result.color));

    light_sample_compute_weight(result);

    return result;
}

void light_sample_trace_hit(inout LightSample smple, bool jitter) {
    ray.origin = rt_pos + block_normal * 0.02f;
    Light light = load_light(smple.index);

    if (jitter) {
        jitter_sample_position(smple.position);
    }

    light.position = smple.position;
    vec3 to_light = light.position - smple.sample_pos;
    smple.dir = normalize(to_light);
    float distance_squared = dot(to_light, to_light) * light.falloff;
    smple.color = light.color / dot(vec2(1, distance_squared), light.attenuation);
    smple.color *= max(dot(smple.dir, normal), 0.0f);
    smple.color *= step(0.001f, ph_luminance(smple.color));
    light_sample_compute_weight(smple);
    float target_weight = smple.weight;
    vec3 visible_color = smple.color;

    ray.direction = smple.dir;

    // Scale shadow ray iterations based on light distance
    vec3 ray_to_light = smple.position - ray.origin;
    float light_dist = length(ray_to_light);
    RAY_ITERATION_COUNT = clamp(int(light_dist * 2.0), 8, 32);

    ray_target = ivec3(smple.position);
    trace_ray(ray, true);
    RAY_ITERATION_COUNT = 100;

    if (!ray.result_hit || floor(smple.position) != floor(ray.result_position)) {
        smple.color = vec3(0f);
        smple.weight = 0f;

        return;
    }

    // ReSTIR weights are built from the target PDF used during reservoir
    // construction (here: the unshadowed contribution). Visibility/tint affect
    // the shaded contribution, but not the target PDF normalization term.
    smple.weight = target_weight;
    smple.color = visible_color * result_tint_color;
}

float light_sample_encode(LightSample smple) {
    return float(smple.index);
}

LightSample light_sample_decode(float value, vec3 sample_pos, bool remap) {
    int index = int(value);
    if (index < 0 || index >= ph_light_count) return NULL_SAMPLE;

    if (remap) {
        index = ph_lights_array_mapping[index];
        if (index < 0 || index >= ph_light_count) return NULL_SAMPLE;
    }

    return light_sample_new(load_light(index), sample_pos);
}

struct Reservoir {
    LightSample light;
    float weight;
    float weight_sum;
    float samples;
};

Reservoir reservoir_new() {
    return Reservoir(NULL_SAMPLE, 0f, 0f, 0f);
}

Reservoir NULL_RESERVOIR = reservoir_new();

bool reservoir_update(
    inout Reservoir reservoir,
    LightSample smple, // giSample is a keyword
    float weight,
    float samples
) {
    reservoir.weight_sum+= weight;
    reservoir.samples+= samples;

    if (rand_next_float() < (weight / reservoir.weight_sum)) {
        reservoir.light = smple;

        return true;
    }

    return false;
}

void reservoir_init(inout Reservoir reservoir) {
    if (ph_light_count <= 0) return;

    for (int i = 0; i < PH_RESTIR_INITIAL_SAMPLES; i++) {
        int rand_index = rand_next_int(0, ph_light_count);
        LightSample smple = light_sample_new(load_light(rand_index), rt_pos);

        reservoir_update(
            reservoir,
            smple,
            smple.weight / light_importance,
            1
        );
    }
}

void reservoir_compute_weight(inout Reservoir reservoir) {
    reservoir.weight = reservoir.light.weight > 0 ?
        (1 / reservoir.light.weight) * (reservoir.weight_sum / reservoir.samples) : 0;
}

bool reservoir_is_valid(Reservoir resevoir) {
    return resevoir.light.index != -1;
}

vec4 reservoir_encode(Reservoir reservoir) {
    return vec4(
        light_sample_encode(reservoir.light),
        reservoir.weight,
        reservoir.weight_sum,
        reservoir.samples
    );
}

void reservoir_decode(inout Reservoir reservoir, vec4 color, vec3 sample_pos, bool remap) {
    reservoir.light = light_sample_decode(color.x, sample_pos, remap);
    reservoir.weight = color.y;
    reservoir.weight_sum = color.z;
    reservoir.samples = color.w;
}

bool reservoir_reuse(inout Reservoir reservoir, ivec2 uv) {
    ivec2 tex_size = textureSize(radiosity_reservoirs, 0);
    if (any(lessThan(uv, ivec2(0))) || any(greaterThanEqual(uv, tex_size))) return false;

    vec3 n = texelFetch(radiosity_normal, uv, 0).xyz;
    if (dot(n, block_normal) < 0.975f) return false;

    vec3 smple_rt_pos = texelFetch(
        radiosity_position,
        uv,
        0
    ).xyz - world_offset;
    if (!ph_surface_positions_compatible(rt_pos, smple_rt_pos, 0.35f)) return false;

    reservoir_decode(
        reservoir,
        texelFetch(
            radiosity_reservoirs,
            uv,
            0
        ),
        rt_pos,
        false
    );

    return !isnan(reservoir.weight) && !isnan(reservoir.weight_sum);
}

bool reservoir_reproject(inout Reservoir reservoir) {
    vec2 uv = ph_reprojectf(
        previous_modelview_projection,
        world_pos + block_normal * 0.01f,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    );

    ivec2 prev_uv = ivec2(uv);
    ivec2 prev_tex_size = textureSize(prev_radiosity_reservoirs, 0);
    if (any(lessThan(prev_uv, ivec2(0))) || any(greaterThanEqual(prev_uv, prev_tex_size))) return false;

    vec3 n = texelFetch(prev_radiosity_normal, prev_uv, 0).xyz;
    if (dot(n, block_normal) < 0.975f) return false;

    vec3 prev_rt_pos = texelFetch(
        prev_radiosity_position,
        prev_uv,
        0
    ).xyz - world_offset;
    if (!ph_surface_positions_compatible(rt_pos, prev_rt_pos, 0.35f)) return false;

    reservoir_decode(
        reservoir,
        texelFetch(
            prev_radiosity_reservoirs,
            prev_uv,
            0
        ),
        rt_pos,
        true
    );

    return true;
}

// RTXDI recommends enough initial samples to keep GI from boiling before
// spatiotemporal reuse and denoising have a chance to converge.
// ReSTIR GI is much less denoiser-friendly when the initial candidate set is
// too sparse; give it a few more seeds so the temporal/spatial passes do not
// start from isolated fireflies.
const int PH_RESTIR_GI_INITIAL_SAMPLES = 16;
const float PH_RESTIR_GI_TARGET_EPSILON = 1e-4f;
const float PH_RESTIR_GI_POSITION_THRESHOLD_SQ = 0.35f;
const float PH_RESTIR_GI_NORMAL_THRESHOLD = 0.93f;
const float PH_RESTIR_GI_MAX_HISTORY = 30.0f;
const float PH_RESTIR_GI_JACOBIAN_REJECT = 30.0f;
const float PH_RESTIR_GI_JACOBIAN_CLAMP_MIN = 1.0f / 10.0f;
const float PH_RESTIR_GI_JACOBIAN_CLAMP_MAX = 10.0f;
const float PH_RESTIR_GI_FLAG_SKY = 1.0f;
const float PH_INV_PI = 0.31830988618f;

struct GISample {
    vec3 position;
    vec3 normal;
    vec3 radiance;
    float pdf;
    float flags;
};

struct GIReservoir {
    GISample giSample;
    float weight;
    float weight_sum;
    float samples;
    float age;
};

GISample gi_sample_null() {
    return GISample(vec3(0.0f), vec3(0.0f), vec3(0.0f), 0.0f, 0.0f);
}

GIReservoir gi_reservoir_new() {
    return GIReservoir(gi_sample_null(), 0.0f, 0.0f, 0.0f, 0.0f);
}

// Target function p_hat for ReSTIR GI: luminance × cosine.
// Paper specifies p_hat ∝ L_i × f_r × cos(θ), but we omit albedo (f_r = albedo/π)
// since albedo is not available at neighbor pixels during spatial reuse.
// Albedo is applied at final shading (lighting.fsh resolved output).
float gi_sample_target_at_surface(GISample giSample, vec3 surfacePosition, vec3 surfaceNormal) {
    if (giSample.pdf <= 0.0f) {
        return 0.0f;
    }

    vec3 sampleDirection = giSample.flags > 0.5f
        ? normalize(-giSample.normal)
        : normalize(giSample.position - surfacePosition);
    float cosine = max(dot(normalize(surfaceNormal), sampleDirection), 0.0f);
    return ph_luminance(giSample.radiance) * cosine;
}

float gi_sample_receiver_cosine_at_surface(
    GISample giSample,
    vec3 surfacePosition,
    vec3 surfaceNormal
) {
    if (giSample.pdf <= 0.0f) {
        return 0.0f;
    }

    vec3 sampleDirection = giSample.flags > 0.5f
        ? normalize(-giSample.normal)
        : normalize(giSample.position - surfacePosition);
    return max(dot(normalize(surfaceNormal), sampleDirection), 0.0f);
}

float gi_sample_target(GISample giSample) {
    return gi_sample_target_at_surface(giSample, rt_pos, block_normal);
}

float gi_sample_target_from_source_surface(
    GISample giSample,
    vec3 sourcePosition,
    vec3 sourceNormal
) {
    return gi_sample_target_at_surface(giSample, sourcePosition, sourceNormal);
}

bool gi_sample_is_valid(GISample giSample) {
    return giSample.pdf > 0.0f && gi_sample_target(giSample) > PH_RESTIR_GI_TARGET_EPSILON;
}

bool gi_sample_is_sky(GISample giSample) {
    return giSample.flags > 0.5f;
}

float gi_history_encode(float age, bool sky) {
    float encodedAge = max(age, 0.0f) + 1.0f;
    return sky ? -encodedAge : encodedAge;
}

void gi_history_decode(float encodedAge, out float age, out bool sky) {
    sky = encodedAge < 0.0f;
    age = max(abs(encodedAge) - 1.0f, 0.0f);
}

bool gi_reservoir_update(inout GIReservoir reservoir, GISample giSample, float weight, float samples, float age) {
    if (weight <= 0.0f || !gi_sample_is_valid(giSample)) {
        return false;
    }

    reservoir.weight_sum += weight;
    reservoir.samples += samples;

    if (rand_next_float() < (weight / max(reservoir.weight_sum, 1e-6f))) {
        reservoir.giSample = giSample;
        reservoir.age = age;
        return true;
    }

    return false;
}

void gi_reservoir_compute_weight(inout GIReservoir reservoir) {
    float normalizationDenominator = reservoir.samples * gi_sample_target(reservoir.giSample);
    reservoir.weight = normalizationDenominator > PH_RESTIR_GI_TARGET_EPSILON
        ? (reservoir.weight_sum / max(normalizationDenominator, 1e-6f))
        : 0.0f;
}

void gi_reservoir_finalize(inout GIReservoir reservoir, float normalizationDenominator) {
    reservoir.weight = normalizationDenominator > PH_RESTIR_GI_TARGET_EPSILON
        ? (reservoir.weight_sum / max(normalizationDenominator, 1e-6f))
        : 0.0f;
}

bool gi_reservoir_is_valid(GIReservoir reservoir) {
    return reservoir.weight > 0.0f && reservoir.samples > 0.0f && gi_sample_is_valid(reservoir.giSample);
}

void gi_reservoir_encode(
    GIReservoir reservoir,
    out vec4 posFrag,
    out vec4 normalFrag,
    out vec4 radianceFrag,
    out vec4 metaFrag
) {
    if (!gi_reservoir_is_valid(reservoir)) {
        posFrag = vec4(0.0f);
        normalFrag = vec4(0.0f);
        radianceFrag = vec4(0.0f);
        metaFrag = vec4(0.0f);
        return;
    }

    posFrag = vec4(reservoir.giSample.position, reservoir.weight);
    normalFrag = vec4(reservoir.giSample.normal, reservoir.samples);
    radianceFrag = vec4(
        reservoir.giSample.radiance,
        gi_history_encode(reservoir.age, gi_sample_is_sky(reservoir.giSample))
    );
    metaFrag = vec4(reservoir.giSample.pdf, reservoir.weight_sum, 0.0f, 0.0f);
}

void gi_reservoir_decode(
    inout GIReservoir reservoir,
    vec4 posData,
    vec4 normalData,
    vec4 radianceData,
    vec4 metaData
) {
    reservoir = gi_reservoir_new();
    if (posData.w <= 0.0f || normalData.w <= 0.0f || radianceData.w == 0.0f || metaData.x <= 0.0f) {
        return;
    }

    reservoir.giSample = GISample(
        posData.xyz,
        normalize(normalData.xyz),
        max(radianceData.rgb, vec3(0.0f)),
        max(metaData.x, PH_RESTIR_GI_TARGET_EPSILON),
        0.0f
    );
    reservoir.weight = posData.w;
    reservoir.samples = normalData.w;
    bool sky = false;
    gi_history_decode(radianceData.w, reservoir.age, sky);
    reservoir.giSample.flags = sky ? PH_RESTIR_GI_FLAG_SKY : 0.0f;
    reservoir.weight_sum = metaData.y > 0.0f
        ? metaData.y
        : reservoir.weight * gi_sample_target(reservoir.giSample) * reservoir.samples;
}

float gi_jacobian(vec3 sourcePosition, GISample giSample) {
    if (gi_sample_is_sky(giSample)) {
        return 1.0f;
    }

    vec3 toCurrent = giSample.position - rt_pos;
    vec3 toSource = giSample.position - sourcePosition;
    float currentDistanceSq = max(dot(toCurrent, toCurrent), 1e-4f);
    float sourceDistanceSq = max(dot(toSource, toSource), 1e-4f);
    float currentCos = max(abs(dot(giSample.normal, normalize(-toCurrent))), 1e-4f);
    float sourceCos = max(abs(dot(giSample.normal, normalize(-toSource))), 1e-4f);
    return (sourceCos * currentDistanceSq) / (currentCos * sourceDistanceSq);
}

bool gi_validate_jacobian(inout float jacobian) {
    if (jacobian > PH_RESTIR_GI_JACOBIAN_REJECT || jacobian < (1.0f / PH_RESTIR_GI_JACOBIAN_REJECT)) {
        return false;
    }

    jacobian = clamp(jacobian, PH_RESTIR_GI_JACOBIAN_CLAMP_MIN, PH_RESTIR_GI_JACOBIAN_CLAMP_MAX);
    return true;
}

GISample gi_sample_trace_candidate(int sampleIndex) {
    GISample giSample = gi_sample_null();
    vec3 firstDirection = ph_sample_hemisphere_blue(block_normal, tex_coord, sampleIndex);
    float pdf = max(dot(block_normal, firstDirection), 0.0f) * PH_INV_PI;

    lightEmittance = vec3(0.0f);
    ray.origin = rt_pos + 0.1f * block_normal;
    ray.direction = firstDirection;
    breakOnEmpty = true;
    trace_ray(ray, true);
    breakOnEmpty = false;

    if (!ray.result_hit && !ray_iteration_bound_reached) {
        giSample.position = rt_pos + firstDirection * 64.0f;
        giSample.normal = -firstDirection;
        giSample.radiance = ph_clamp_indirect_radiance(indirect_light_color);
        giSample.pdf = max(pdf, PH_RESTIR_GI_TARGET_EPSILON);
        giSample.flags = PH_RESTIR_GI_FLAG_SKY;
        return giSample;
    }

    if (dot(lightEmittance, lightEmittance) > 0.0f) {
        giSample.position = ray.result_position;
        giSample.normal = ray.result_normal;
        giSample.radiance = ph_clamp_indirect_radiance(lightEmittance);
        giSample.pdf = max(pdf, PH_RESTIR_GI_TARGET_EPSILON);
        return giSample;
    }

    giSample.position = ray.result_position;
    giSample.normal = ray.result_normal;
    giSample.radiance = ph_clamp_indirect_radiance(
        ray.result_color * ph_trace_surface_radiance(giSample.position, giSample.normal, sampleIndex + 13, 1)
    );
    giSample.pdf = max(pdf, PH_RESTIR_GI_TARGET_EPSILON);
    return giSample;
}

void gi_reservoir_init(inout GIReservoir reservoir) {
    for (int i = 0; i < PH_RESTIR_GI_INITIAL_SAMPLES; i++) {
        GISample giSample = gi_sample_trace_candidate(i);
        float target = gi_sample_target(giSample);
        if (!gi_sample_is_valid(giSample) || target <= PH_RESTIR_GI_TARGET_EPSILON) {
            continue;
        }

        gi_reservoir_update(
            reservoir,
            giSample,
            target / max(giSample.pdf, PH_RESTIR_GI_TARGET_EPSILON),
            1.0f,
            0.0f
        );
    }
}

bool gi_surface_reuse_valid(
    ivec2 uv,
    bool previousFrame,
    out vec3 sourcePosition,
    out vec3 sourceNormal
) {
    ivec2 texSize = previousFrame
        ? textureSize(prev_radiosity_position, 0)
        : textureSize(radiosity_position, 0);
    if (any(lessThan(uv, ivec2(0))) || any(greaterThanEqual(uv, texSize))) {
        return false;
    }

    sourceNormal = previousFrame
        ? texelFetch(prev_radiosity_normal, uv, 0).xyz
        : texelFetch(radiosity_normal, uv, 0).xyz;
    if (dot(sourceNormal, block_normal) < PH_RESTIR_GI_NORMAL_THRESHOLD) {
        return false;
    }

    sourcePosition = (previousFrame
        ? texelFetch(prev_radiosity_position, uv, 0)
        : texelFetch(radiosity_position, uv, 0)).xyz - world_offset;
    if (!ph_surface_positions_compatible(rt_pos, sourcePosition, PH_RESTIR_GI_POSITION_THRESHOLD_SQ)) {
        return false;
    }

    return true;
}

bool gi_reservoir_load_current(
    inout GIReservoir reservoir,
    ivec2 uv,
    out vec3 sourcePosition,
    out vec3 sourceNormal
) {
    if (!gi_surface_reuse_valid(uv, false, sourcePosition, sourceNormal)) {
        return false;
    }

    gi_reservoir_decode(
        reservoir,
        texelFetch(radiosity_gi_reservoir_pos, uv, 0),
        texelFetch(radiosity_gi_reservoir_normal, uv, 0),
        texelFetch(radiosity_gi_reservoir_radiance, uv, 0),
        texelFetch(radiosity_gi_reservoir_meta, uv, 0)
    );
    return gi_reservoir_is_valid(reservoir);
}

bool gi_reservoir_reproject(
    inout GIReservoir reservoir,
    out vec3 sourcePosition,
    out vec3 sourceNormal
) {
    vec2 uv = ph_reprojectf(
        previous_modelview_projection,
        world_pos + block_normal * 0.01f,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    );
    ivec2 prevUv = ivec2(uv);
    if (!gi_surface_reuse_valid(prevUv, true, sourcePosition, sourceNormal)) {
        return false;
    }

    gi_reservoir_decode(
        reservoir,
        texelFetch(prev_radiosity_gi_reservoir_pos, prevUv, 0),
        texelFetch(prev_radiosity_gi_reservoir_normal, prevUv, 0),
        texelFetch(prev_radiosity_gi_reservoir_radiance, prevUv, 0),
        texelFetch(prev_radiosity_gi_reservoir_meta, prevUv, 0)
    );
    return gi_reservoir_is_valid(reservoir);
}

vec3 gi_sample_direction(GISample giSample) {
    return gi_sample_is_sky(giSample)
        ? normalize(-giSample.normal)
        : normalize(giSample.position - rt_pos);
}

bool gi_sample_has_conservative_visibility_from_surface(
    GISample giSample,
    vec3 surfacePosition,
    vec3 surfaceNormal
) {
    if (!gi_sample_is_valid(giSample)) {
        return false;
    }

    ray.origin = surfacePosition + surfaceNormal * 0.02f;
    ray.direction = gi_sample_is_sky(giSample)
        ? normalize(-giSample.normal)
        : normalize(giSample.position - surfacePosition);
    ray_target = gi_sample_is_sky(giSample) ? ivec3(-9999) : ivec3(giSample.position);
    int previousIterations = RAY_ITERATION_COUNT;
    float distanceToSample = gi_sample_is_sky(giSample) ? 64.0f : length(giSample.position - ray.origin);
    RAY_ITERATION_COUNT = clamp(int(distanceToSample * 1.5f), 8, 32);
    trace_ray(ray, true);
    RAY_ITERATION_COUNT = previousIterations;

    if (gi_sample_is_sky(giSample)) {
        return !ray.result_hit && !ray_iteration_bound_reached;
    }

    return ray.result_hit && floor(giSample.position) == floor(ray.result_position);
}

bool gi_sample_has_conservative_visibility(GISample giSample) {
    return gi_sample_has_conservative_visibility_from_surface(giSample, rt_pos, block_normal);
}

vec3 gi_sample_trace_visibility_from_surface(
    GISample giSample,
    vec3 surfacePosition,
    vec3 surfaceNormal
) {
    if (!gi_sample_is_valid(giSample)) {
        return vec3(0.0f);
    }

    ray.origin = surfacePosition + surfaceNormal * 0.02f;
    ray.direction = gi_sample_is_sky(giSample)
        ? normalize(-giSample.normal)
        : normalize(giSample.position - surfacePosition);
    ray_target = gi_sample_is_sky(giSample) ? ivec3(-9999) : ivec3(giSample.position);
    int previousIterations = RAY_ITERATION_COUNT;
    float distanceToSample = gi_sample_is_sky(giSample) ? 64.0f : length(giSample.position - ray.origin);
    RAY_ITERATION_COUNT = clamp(int(distanceToSample * 2.0f), 8, 48);
    trace_ray(ray, true);
    RAY_ITERATION_COUNT = previousIterations;

    vec3 visibleRadiance = giSample.radiance * result_tint_color;
    if (gi_sample_is_sky(giSample)) {
        return (!ray.result_hit && !ray_iteration_bound_reached)
            ? visibleRadiance
            : vec3(0.0f);
    }

    if (!ray.result_hit || floor(giSample.position) != floor(ray.result_position)) {
        return vec3(0.0f);
    }

    return visibleRadiance;
}

vec3 gi_sample_trace_visibility(GISample giSample) {
    return gi_sample_trace_visibility_from_surface(giSample, rt_pos, block_normal);
}

struct SampleHistory {
    vec4 lighting;
    vec4 variance;
};

const SampleHistory NULL_HISTORY = SampleHistory(vec4(-999), vec4(-999));
const vec3 PH_HISTORY_LUMA_COEFF = vec3(0.2126f, 0.7152f, 0.0722f);

void sample_history_load(out SampleHistory smple) {
    smple.lighting = texelFetch(radiosity_lighting, tex_coord, 0),
    smple.variance = vec4(0f);
}

SampleHistory sample_history_mix(SampleHistory s1, SampleHistory s2, float a) {
    if (s1 == NULL_HISTORY) {
        a = 1f;
    } else if (s2 == NULL_HISTORY) {
        a = 0f;
    } else if (s1 == NULL_HISTORY && s2 == NULL_HISTORY) {
        return NULL_HISTORY;
    }

    return SampleHistory(
        mix(s1.lighting, s2.lighting, a),
        mix(s1.variance, s2.variance, a)
    );
}

SampleHistory sample_history_reproject_single(vec2 uv) {
    ivec2 iuv = ivec2(uv);
    ivec2 history_tex_size = textureSize(prev_radiosity_lighting, 0);
    if (any(lessThan(iuv, ivec2(0))) || any(greaterThanEqual(iuv, history_tex_size))) return NULL_HISTORY;

    vec3 historyPosition = texelFetch(prev_radiosity_position, iuv, 0).xyz;
    if (!ph_surface_positions_compatible(world_pos, historyPosition, 0.2f)) return NULL_HISTORY;

    vec3 n = texelFetch(prev_radiosity_normal, iuv, 0).xyz;
    if (dot(n, block_normal) < 0.975f) return NULL_HISTORY;

    vec4 lighting = texelFetch(prev_radiosity_lighting, iuv, 0);
    if (any(isnan(lighting))) return NULL_HISTORY;

    vec4 variance = texelFetch(prev_radiosity_lighting_variance, iuv, 0);
    if (any(isnan(variance))) return NULL_HISTORY;

    return SampleHistory(lighting, variance);
}

SampleHistory sample_history_reproject_mixed(vec2 center) {
    ivec2 icenter = ivec2(center);

    SampleHistory c_00 = sample_history_reproject_single(icenter + ivec2(0, 0));
    SampleHistory c_10 = sample_history_reproject_single(icenter + ivec2(1, 0));
    SampleHistory c_01 = sample_history_reproject_single(icenter + ivec2(0, 1));
    SampleHistory c_11 = sample_history_reproject_single(icenter + ivec2(1, 1));

    SampleHistory result = sample_history_mix(
        sample_history_mix(c_00, c_10, fract(center.x)),
        sample_history_mix(c_01, c_11, fract(center.x)),
        fract(center.y)
    );

    if (result == NULL_HISTORY)
        return SampleHistory(vec4(0f), vec4(0f));

    return result;
}

void sample_history_reproject(out SampleHistory smple) {
    vec2 center = ph_reprojectf(
        previous_modelview_projection,
        world_pos + block_normal * 0.01f,
        vec2(viewWidth, viewHeight),
        get_taa_jitter()
    ) - 0.5f;

    smple = sample_history_reproject_mixed(center);
}

void sample_history_combine_lighting(inout SampleHistory history, in SampleHistory smple) {
    #if PH_RESTIR_DENOISER_PASSES != 0
    history.lighting.w = min(history.lighting.w, PH_RESTIR_ACCUMULATION_FRAMES);
    history.lighting.rgb = mix(history.lighting.rgb, smple.lighting.rgb, 1f / (++history.lighting.w));
    #else
    if (history.lighting.a >= PH_RESTIR_ACCUMULATION_FRAMES - 1f)
        history.lighting *= ((PH_RESTIR_ACCUMULATION_FRAMES - 1f) / history.lighting.a);

    history.lighting.rgb+= smple.lighting.rgb;
    history.lighting.a++;
    #endif
}

void sample_history_combine_moment(inout SampleHistory history, in SampleHistory smple) {
    float moment_alpha = clamp(1f / max(history.lighting.a, 1f), 0.05f, 1.0f);
    vec2 moments = vec2(0f);

    moments.x = dot(smple.lighting.rgb, PH_HISTORY_LUMA_COEFF);
    moments.y = moments.x * moments.x;

    history.variance.xy = mix(history.variance.xy, moments, moment_alpha);
}

void sample_history_compute_variance(inout SampleHistory history, in SampleHistory smple) {
    float samples = history.lighting.a;
    float sample_variance = max(
        history.variance.y - (history.variance.x * history.variance.x),

        // With few samples, variance estimate is unreliable — use a high floor
        (samples < 4f) ? 10f : 0
    );

    history.variance.z = sample_variance / samples;
}

// --- Dirty-region invalidation ---
// These uniforms are set by the CPU when a local world edit occurs.
// They define an AABB in world-space and a blend factor [0,1].
#ifndef PH_DIRTY_REGION_DEFINED
#define PH_DIRTY_REGION_DEFINED
uniform float light_blend_factor;
uniform int light_blend_region_count;
uniform vec3 light_blend_min;
uniform vec3 light_blend_max;
uniform vec3 light_blend_min_1;
uniform vec3 light_blend_max_1;
uniform vec3 light_blend_min_2;
uniform vec3 light_blend_max_2;
uniform vec3 light_blend_min_3;
uniform vec3 light_blend_max_3;
uniform vec3 light_blend_min_4;
uniform vec3 light_blend_max_4;
uniform vec3 light_blend_min_5;
uniform vec3 light_blend_max_5;
uniform vec3 light_blend_min_6;
uniform vec3 light_blend_max_6;
uniform vec3 light_blend_min_7;
uniform vec3 light_blend_max_7;

bool ph_dirty_region_contains(vec3 worldPosition, vec3 regionMin, vec3 regionMax) {
    bvec3 insideMin = greaterThanEqual(worldPosition, regionMin);
    bvec3 insideMax = lessThan(worldPosition, regionMax);
    return all(insideMin) && all(insideMax);
}

// Returns invalidation strength [0,1] for the given world position.
// 0 = no invalidation (outside dirty region), 1 = full reset.
float ph_dirty_region_factor(vec3 worldPosition) {
    if (light_blend_factor <= 0.0f || light_blend_region_count <= 0) return 0.0f;
    if (ph_dirty_region_contains(worldPosition, light_blend_min, light_blend_max)) return light_blend_factor;
    if (light_blend_region_count <= 1) return 0.0f;
    if (ph_dirty_region_contains(worldPosition, light_blend_min_1, light_blend_max_1)) return light_blend_factor;
    if (light_blend_region_count <= 2) return 0.0f;
    if (ph_dirty_region_contains(worldPosition, light_blend_min_2, light_blend_max_2)) return light_blend_factor;
    if (light_blend_region_count <= 3) return 0.0f;
    if (ph_dirty_region_contains(worldPosition, light_blend_min_3, light_blend_max_3)) return light_blend_factor;
    if (light_blend_region_count <= 4) return 0.0f;
    if (ph_dirty_region_contains(worldPosition, light_blend_min_4, light_blend_max_4)) return light_blend_factor;
    if (light_blend_region_count <= 5) return 0.0f;
    if (ph_dirty_region_contains(worldPosition, light_blend_min_5, light_blend_max_5)) return light_blend_factor;
    if (light_blend_region_count <= 6) return 0.0f;
    if (ph_dirty_region_contains(worldPosition, light_blend_min_6, light_blend_max_6)) return light_blend_factor;
    if (light_blend_region_count <= 7) return 0.0f;
    return ph_dirty_region_contains(worldPosition, light_blend_min_7, light_blend_max_7) ? light_blend_factor : 0.0f;
}
#endif

#endif
