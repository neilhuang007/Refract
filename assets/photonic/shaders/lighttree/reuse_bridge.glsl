#ifndef PH_LIGHTTREE_REUSE_INCLUDE
#define PH_LIGHTTREE_REUSE_INCLUDE

float light_importance = 1f / ph_light_count;

bool lt_is_viewport_uv_in_bounds(ivec2 uv) {
    return all(greaterThanEqual(uv, ivec2(0))) && all(lessThan(uv, ivec2(viewWidth, viewHeight)));
}

bool lt_is_viewport_uv_in_bounds(vec2 uv) {
    return all(greaterThanEqual(uv, vec2(0.0f))) && all(lessThan(uv, vec2(viewWidth, viewHeight)));
}

vec3 lt_resolve_reuse_normal(vec3 geometryNormal, vec3 mappedNormal) {
    float mappedLengthSq = dot(mappedNormal, mappedNormal);
    if (mappedLengthSq > 1e-6f) {
        return normalize(mappedNormal);
    }

    float geometryLengthSq = dot(geometryNormal, geometryNormal);
    if (geometryLengthSq > 1e-6f) {
        return normalize(geometryNormal);
    }

    return vec3(0.0f, 1.0f, 0.0f);
}

vec3 lt_current_reuse_normal() {
    return lt_resolve_reuse_normal(block_normal, normal);
}

vec3 lt_load_reuse_normal(ivec2 uv) {
    vec3 geometryNormal = texelFetch(radiosity_normal, uv, 0).xyz;
    vec3 mappedNormal = texelFetch(radiosity_mapped_normal, uv, 0).xyz;
    return lt_resolve_reuse_normal(geometryNormal, mappedNormal);
}

vec3 lt_load_previous_reuse_normal(ivec2 uv) {
    vec3 geometryNormal = texelFetch(prev_radiosity_normal, uv, 0).xyz;
    vec3 mappedNormal = texelFetch(prev_radiosity_mapped_normal, uv, 0).xyz;
    return lt_resolve_reuse_normal(geometryNormal, mappedNormal);
}

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
    sample_pos+= ray_local_offset + block_normal * ray_normal_scale;

    LightSample result = LightSample(
        light.index,
        light.position,
        sample_pos,
        vec3(0f),
        light.position - sample_pos,
        0f
    );

    result.color = ph_compute_attenuation(
        light,
        result.dir,
        sample_pos,
        light.position,
        block_normal,
        normal
    );

    result.dir = normalize(result.dir);
    if (ph_luminance(result.color) < 0.0001f) {
        result.color = vec3(0f);
        result.weight = 0f;

        return result;
    }

    light_sample_compute_weight(result);

    return result;
}

float light_sample_trace_hit(inout LightSample smple, bool jitter) {
    if (jitter) {
        jitter_sample_position(smple.position);
        smple.dir = normalize(smple.position - smple.sample_pos);
    }

    float lightDistance = length(smple.position - smple.sample_pos);
    ray.origin = smple.sample_pos;
    ray.direction = smple.dir;

    ray_target = ivec3(smple.position);
    trace_ray(ray, true);

    if (!ray.result_hit || floor(smple.position) != floor(ray.result_position)) {
        smple.color = vec3(0f);
        smple.weight = 0f; // Weight needs to be non zero

        return 0.0f;
    }

    light_sample_compute_weight(smple); // Update weight for reuse.
    return lightDistance;
}

float light_sample_encode(LightSample smple) {
    return float(smple.index);
}

LightSample light_sample_decode(float value, vec3 sample_pos, bool remap) {
    int index = int(value);
    if (index < 0 || index > ph_light_count) return NULL_SAMPLE;

    if (remap) {
        index = ph_lights_array_mapping[index];
        if (index < 0 || index > ph_light_count) return NULL_SAMPLE;
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
    LightSample smple, // sample is a keyword
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
    for (int i = 0; i < PH_LIGHTTREE_INITIAL_SAMPLES; i++) {
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

float reservoir_target_pdf(Reservoir reservoir) {
    return max(reservoir.light.weight, 1e-6f);
}

float reservoir_mis_weight(Reservoir reservoir) {
    float targetPdf = reservoir_target_pdf(reservoir);
    if (reservoir.samples <= 0.0f || targetPdf <= 0.0f) {
        return 0.0f;
    }
    return reservoir.weight_sum / max(reservoir.samples * targetPdf, 1e-6f);
}

void reservoir_merge_ris(inout Reservoir reservoir, Reservoir candidate, float candidateM) {
    if (!reservoir_is_valid(candidate)) {
        return;
    }

    float candidateTargetPdf = reservoir_target_pdf(candidate);
    float candidateWeight = candidateTargetPdf * reservoir_mis_weight(candidate) * max(candidateM, 1.0f);
    reservoir_update(
        reservoir,
        candidate.light,
        candidateWeight,
        candidateM
    );
}

bool reservoir_reuse(inout Reservoir reservoir, ivec2 uv) {
    if (!lt_is_viewport_uv_in_bounds(uv)) {
        return false;
    }

    if (!bad_angle) {
        vec3 smple_rt_pos = texelFetch(
            radiosity_position,
            uv,
            0
        ).xyz - world_offset;

        vec3 d = smple_rt_pos - rt_pos;
        if (dot(d, d) >= 0.3f) return false;
    }

    vec3 reuseNormal = lt_load_reuse_normal(uv);
    vec3 currentReuseNormal = lt_current_reuse_normal();
    if (dot(reuseNormal, currentReuseNormal) < 0.96f) return false;

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
    if (!lt_is_viewport_uv_in_bounds(uv)) {
        return false;
    }

    ivec2 previousUv = ivec2(uv);

    if (!bad_angle) {
        vec3 prev_rt_pos = texelFetch(
            prev_radiosity_position,
            previousUv,
            0
        ).xyz - world_offset;

        vec3 d = prev_rt_pos - rt_pos;
        if (dot(d, d) >= 0.3f) return false;
    }

    vec3 previousReuseNormal = lt_load_previous_reuse_normal(previousUv);
    vec3 currentReuseNormal = lt_current_reuse_normal();
    if (dot(previousReuseNormal, currentReuseNormal) < 0.96f) return false;

    reservoir_decode(
        reservoir,
        texelFetch(
            prev_radiosity_reservoirs,
            previousUv,
            0
        ),
        rt_pos,
        true
    );

    return true;
}

struct SampleHistory {
    vec4 lighting;
    vec4 variance;
};

const SampleHistory NULL_HISTORY = SampleHistory(vec4(-999), vec4(-999));

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
    if (!lt_is_viewport_uv_in_bounds(uv)) {
        return NULL_HISTORY;
    }

    ivec2 previousUv = ivec2(uv);

    if (!bad_angle) {
        vec3 d = texelFetch(prev_radiosity_position, previousUv, 0).xyz - world_pos;
        if (dot(d, d) >= 0.1f) return NULL_HISTORY;
    }

    vec3 previousReuseNormal = lt_load_previous_reuse_normal(previousUv);
    vec3 currentReuseNormal = lt_current_reuse_normal();
    if (dot(previousReuseNormal, currentReuseNormal) < 0.99f) return NULL_HISTORY;

    vec4 lighting = texelFetch(prev_radiosity_lighting, previousUv, 0);
    if (any(isnan(lighting))) return NULL_HISTORY;

    vec4 variance = texelFetch(prev_radiosity_lighting_variance, previousUv, 0);
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
    #if PH_LIGHTTREE_DENOISER_PASSES != 0
    history.lighting.w = min(history.lighting.w, PH_LIGHTTREE_ACCUMULATION_FRAMES);
    history.lighting.rgb = mix(history.lighting.rgb, smple.lighting.rgb, 1f / (++history.lighting.w));
    #else
    if (history.lighting.a >= PH_LIGHTTREE_ACCUMULATION_FRAMES - 1f)
        history.lighting *= ((PH_LIGHTTREE_ACCUMULATION_FRAMES - 1f) / history.lighting.a);

    history.lighting.rgb+= smple.lighting.rgb;
    history.lighting.a++;
    #endif
}

void sample_history_combine_moment(inout SampleHistory history, in SampleHistory smple) {
    float moment_alpha = 1f / history.lighting.a;
    vec2 moments = vec2(0f);

    moments.x = dot(smple.lighting.rgb, vec3(0.299, 0.587, 0.114));
    moments.y = moments.x * moments.x;

    history.variance.xy = mix(history.variance.xy, moments, moment_alpha);
    history.variance.w = 1f;
}

void sample_history_compute_variance(inout SampleHistory history, in SampleHistory smple) {
    float samples = history.lighting.a;
    float sample_variance = max(
        history.variance.y - (history.variance.x * history.variance.x),

        // With few samples, variance estimate is unreliable — use a moderate floor
        (samples < 4f) ? 1f : 0
    );

    history.variance.z = sample_variance / samples;
}
#endif

