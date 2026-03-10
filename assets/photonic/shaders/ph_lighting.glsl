#version 430

/*
    -- INPUT VARIABLES --
*/
in vec4 direction_vert_out;

/*
    -- OUTPUT VARIABLES --
*/
layout(location = 0) out vec4 position_frag_out;
layout(location = 1) out vec4 normal_frag_out;
layout(location = 2) out vec4 direct_frag_out;
layout(location = 3) out vec4 direct_soft_frag_out;
layout(location = 4) out vec4 handheld_frag_out;

struct Frag {
    vec4 direct;
    vec4 direct_soft;
};

//#uniforms
uniform float ph_mod_shadow_pixelation_enabled;
uniform float ph_mod_shadow_pixel_size_rt;
uniform float light_blend_factor;
uniform vec3 light_blend_min;
uniform vec3 light_blend_max;

//ph_required: uniform int frameCounter, frameTime;
//ph_required: uniform float frameTimeCounter, rainStrength, shadowFade, viewWidth, viewHeight;
//ph_required: uniform sampler2D depthtex0, noisetex;
//ph_required: uniform mat4 gbufferProjectionInverse, gbufferModelViewInverse, shadowProjection, shadowModelView;
//ph_required: uniform vec3 cameraPosition, eyePosition;

#include "/photonics/shader_interface.glsl"
#include "/photonics/photonics.glsl"

vec3 ph_sun_direction = ph_signed_nudge(sun_direction);

ivec2 gBufferLoc = ivec2(gl_FragCoord.xy);

uint rngState = uint(uint(gl_FragCoord.x) * uint(1973) + uint(gl_FragCoord.y) * uint(9277) + uint(frameCounter) * uint(26699)) | uint(1);

//#forward

RayJob light_ray = RayJob(vec3(0), vec3(0), vec3(0), vec3(0), vec3(0), false);
vec3 base_position = vec3(0.0f);
vec3 base_normal = vec3(0.0f);
vec3 mapped_normal = vec3(0.0f);

void main(void) {
    if (!is_in_world()) {
        return;
    }

    vec3 albedo = vec3(0.0f);
    load_fragment_variables(albedo, base_position, base_normal, mapped_normal);

    base_position -= world_offset;
    handheld_frag_out = vec4(0.0f);

    ph_reproject(true);

    // TODO: Handheld torch experimentation (looks *really* cool)
    #ifdef PH_ENABLE_HANDHELD_LIGHT
    if (any(notEqual(handheld_color, vec3(0.0f)))) {
        vec4 direction_vert_out = direction_transformation_matrix_in * vec4(left_handed ? 1.0f : -1.0f, -1.0f, 0.0f, 1.0f);
        direction_vert_out.w = 1.0f / direction_vert_out.w;
        direction_vert_out.xyz *= direction_vert_out.w;

        light_ray.origin = direction_vert_out.xyz + eyePosition - world_offset;
        //                light_ray.origin.y = rt_camera_position.y - 0.5f;

        vec3 to_light = base_position - light_ray.origin;
        light_ray.direction = normalize(to_light);
        trace_ray(light_ray); // TODO: early terminate, if ray is too far away anyway

        float distance_squared = dot(to_light, to_light);
        float brightness = 2.1f / dot(vec2(1, distance_squared), vec2(0.9f, 0.1f));
        brightness = max(brightness, 0.02f);

        float hand_to_base_distance = distance(light_ray.origin, base_position);
        float hand_to_result_distance = distance(light_ray.origin, light_ray.result_position);
        brightness *= clamp(30.0f * (hand_to_result_distance - hand_to_base_distance + 0.05f), 0.0f, 1.0f);

        brightness *= dot(mapped_normal, -light_ray.direction);

        brightness *= (ph_h(frameCounter / 300.0f) * 0.1f + ph_h(frameCounter / 100.0f) * 0.05f) + 0.4f;

        handheld_frag_out.xyz = brightness * handheld_color;
    } else {
        handheld_frag_out.xyz = vec3(0.0f);
    }
    #endif

    handheld_frag_out.w = 1.0f;
}

const float F = 2.0f;

// Pulse function
float ph_g(float x) {
    return sin(F * 3.141592f * clamp(x, 0.0f, 1.0f / F));
}

// Noise
float ph_n(float x) {
    return 0.5f * sin(1000.0f * x) + 0.5f;
}

// Periodic function with random offset
float ph_h(float x) {
    return ph_g(fract(x) - (1.0f - 1.0f / F) * ph_n(floor(x)));
}

float ph_luminance(vec3 rgb) {
    return dot(rgb, vec3(0.2126f, 0.7152f, 0.0722f));
}

const Frag NULL4 = Frag(vec4(-999), vec4(-999));

vec4 ph_texelFetch0(sampler2D sampler, ivec2 pos, int level) {
    return texelFetch(sampler, pos, level);
}

#define texelFetch(sampler, pos, level) \
    ph_texelFetch0(sampler, pos, level)

Frag ph_get(vec2 uv) {
    ivec2 iuv = ivec2(uv);
    ivec2 texSize = textureSize(prev_radiosity_position, 0);
    if (iuv.x < 0 || iuv.y < 0 || iuv.x >= texSize.x || iuv.y >= texSize.y) {
        return NULL4;
    }

    vec3 d = texelFetch(prev_radiosity_position, iuv, 0).xyz - base_position - world_offset;
    if (dot(d, d) >= 0.1f) {
        return NULL4;
    }

    vec3 n = texelFetch(prev_radiosity_normal, iuv, 0).xyz;
    if (dot(n, base_normal) < 0.99f) {
        return NULL4;
    }

    vec4 direct = texelFetch(prev_radiosity_direct, iuv, 0);
    vec4 direct_soft = texelFetch(prev_radiosity_direct_soft, iuv, 0);

    return Frag(direct, direct_soft);
}

Frag ph_get_mixed(vec2 center) {
    ivec2 icenter = ivec2(center);

    Frag c_00 = ph_get(icenter + ivec2(0, 0));
    Frag c_10 = ph_get(icenter + ivec2(1, 0));
    Frag c_01 = ph_get(icenter + ivec2(0, 1));
    Frag c_11 = ph_get(icenter + ivec2(1, 1));

    Frag frag = ph_mixNullable4(
        ph_mixNullable4(c_00, c_10, fract(center.x)),
        ph_mixNullable4(c_01, c_11, fract(center.x)),
        fract(center.y)
    );

    return frag;
}

Frag ph_mixNullable4(Frag s1, Frag s2, float a) {
    if (s1 == NULL4) {
        a = 1.0f;
    } else if (s2 == NULL4) {
        a = 0.0f;
    }

    vec4 direct = mix(s1.direct, s2.direct, a);
    vec4 direct_soft = mix(s1.direct_soft, s2.direct_soft, a);

    return Frag(direct, direct_soft);
}

float ph_local_light_blend(vec3 world_pos) {
    if (light_blend_factor <= 0.0f) {
        return 0.0f;
    }
    bvec3 insideMin = greaterThanEqual(world_pos, light_blend_min);
    bvec3 insideMax = lessThan(world_pos, light_blend_max);
    return all(insideMin) && all(insideMax) ? light_blend_factor : 0.0f;
}

// TODO: reproject in voxel pattern to hide noise in texture
void ph_reproject(bool sample_indirect) {
    vec2 center = ph_reprojectf(previous_modelview_projection, base_position + world_offset + 0.01f * base_normal, vec2(viewWidth, viewHeight), get_taa_jitter());

    position_frag_out = vec4(base_position + world_offset, 1.0f);
    normal_frag_out = vec4(base_normal, 1.0f);

    center -= 0.5f;
    Frag frag = ph_get_mixed(center);

    float localBlend = ph_local_light_blend(base_position + world_offset);
    if (frag == NULL4) {
        frag.direct = vec4(0.0f);
        frag.direct_soft = vec4(0.0f);
    } else if (localBlend > 0.0f) {
        float colorDecay = 1.0f - localBlend * 0.5f;
        frag.direct.xyz *= colorDecay;
        frag.direct_soft.xyz *= colorDecay;
    }

    // direct light
    int light_offset = load_light_offset(base_position);

    int light_count = light_registry_array[light_offset];
    int soft_light_count = min(3, light_count);

    #ifdef PH_ENABLE_BLOCKLIGHT
    ph_process_direct(frag, light_offset, light_count, soft_light_count);
    #endif

    #ifdef PH_ENABLE_GI
    // Detect edge
    // TODO: we probably should do fract(2.0f * base_position)
    ivec3 inside = ivec3(lessThan(abs(fract(base_position) - 0.5f), vec3(0.48f)));
    bool onEdge = inside.x + inside.y + inside.z <= 1;

    if (!onEdge) { // TODO: not actually completely working
        ph_process_indirect();
    }
    #endif

    frag.direct.w = max(frag.direct.w, 0.01f);
    direct_frag_out = frag.direct;
    frag.direct_soft.w = max(frag.direct_soft.w, 0.01f);
    direct_soft_frag_out = frag.direct_soft;
}

void ph_process_direct(inout Frag frag, int light_offset, int light_count, int soft_light_count) {
    for (; frag.direct.w < light_count - soft_light_count; frag.direct.w++) {
        int index = light_registry_array[soft_light_count + int(frag.direct.w) + light_offset + 1];
        Light light = load_light(index);
        frag.direct.xyz += ph_sample_direct_lighting(base_position, base_normal, mapped_normal, light);
    }

    for (int i = 0; i < soft_light_count; i++) {
        int index = light_registry_array[(int(frag.direct_soft.w) % soft_light_count) + light_offset + 1];
        Light light = load_light(index);
        ph_sample_light_direction(light, 1.0f / 16.0f);
        frag.direct_soft.xyz += soft_light_count * ph_sample_direct_lighting(base_position, base_normal, mapped_normal, light);
        frag.direct_soft.w++;
    }
}

void ph_process_indirect() {
    vec3 sample_position = base_position + world_offset;
    float localBlend = ph_local_light_blend(sample_position);
    ivec3 write = ph_write(sample_position, base_normal, modelview_projection, world_camera_position);

    uint w = imageAtomicAdd(gi_w, write, uint(1));
    if (w == 0) {
        ivec3 read = ph_read(sample_position, base_normal, previous_modelview_projection, previous_world_camera_position);

        vec4 result = vec4(0.0f);
        result.x += imageLoad(gi_x, read).x / 255.0f;
        result.y += imageLoad(gi_y, read).x / 255.0f;
        result.z += imageLoad(gi_z, read).x / 255.0f;
        result.w = imageLoad(gi_w, read).x;

        // Adaptive history decay: fast convergence initially, stable once accumulated
        // result.w tracks sample count from previous frame
        float historyDecay;
        if (localBlend > 0.5f) {
            historyDecay = mix(0.5f, 0.0f, (localBlend - 0.5f) * 2.0f);
        } else if (localBlend > 0.0f) {
            historyDecay = mix(0.9f, 0.5f, localBlend * 2.0f);
        } else if (result.w < 32.0f) {
            // Early frames: aggressive decay for fast initial convergence
            historyDecay = 0.9f;
        } else if (result.w < 256.0f) {
            // Medium convergence: transition to stable
            historyDecay = 0.95f;
        } else {
            // Fully converged: slow decay for temporal stability
            historyDecay = 0.985f;
        }
        result *= historyDecay;

        imageAtomicAdd(gi_x, write, uint(result.x * 255.0f));
        imageAtomicAdd(gi_y, write, uint(result.y * 255.0f));
        imageAtomicAdd(gi_z, write, uint(result.z * 255.0f));
        imageAtomicAdd(gi_w, write, uint(result.w));
    } else if (w < 4096) {
        vec3 result = ph_sample_indirect_lighting();

        imageAtomicAdd(gi_x, write, uint(result.x * 255.0f));
        imageAtomicAdd(gi_y, write, uint(result.y * 255.0f));
        imageAtomicAdd(gi_z, write, uint(result.z * 255.0f));
    } else {
        imageAtomicAdd(gi_w, write, uint(-1));
    }
}

// TODO: take sun light into account
vec3 ph_sample_indirect_lighting() {
    light_ray.result_position = base_position;
    light_ray.result_normal = base_normal;

    //    bool is_axis_aligned = is_axis_aligned(base_normal);

    // If normal is not axis aligned, sample both hemispheres
    //    if (!is_axis_aligned) {
    //        light_ray.result_normal = vec3(0.0f);
    //    }

    vec3 indirect_color = vec3(1.0f);

    for (int i = 0; i < 2; i++) {
        lightEmittance = vec3(0.0f);
        light_ray.origin = light_ray.result_position + 0.1f * light_ray.result_normal;
        // Blue noise hemisphere sampling for lower-variance GI
        light_ray.direction = ph_sample_hemisphere_blue(light_ray.result_normal, ivec2(gl_FragCoord.xy), i);

        bool sun = RandomFloat01(rngState) < 0.25f && dot(sun_direction, light_ray.result_normal) > 0.707f;
        if (sun) {
            light_ray.direction = ph_sun_direction;
        }

        RAY_ITERATION_COUNT = 32;
        breakOnEmpty = true;
        trace_ray(light_ray, true);
        breakOnEmpty = false;
        RAY_ITERATION_COUNT = 100;  // Restore primary ray budget

        indirect_color*= result_tint_color;
        if (!light_ray.result_hit && !ray_iteration_bound_reached) {
            if (!sun) {
                indirect_color *= (float(i > 0) * 5 + 1) * indirect_light_color;
            } else {
                indirect_color *= (float(i > 0) * 15 + 1) * indirect_light_color;
            }

            return indirect_color;
        } else if (dot(lightEmittance, lightEmittance) > 0.0f) {
            indirect_color *= 2.0f * lightEmittance;
            //            indirect_color = vec3(0.0f);

            return indirect_color;
        }

        indirect_color *= light_ray.result_color;
    }

    return vec3(0.0f);
}

float ph_blue_noise(int index) {
    ivec2 coord = (ivec2(gl_FragCoord.xy) + ivec2(index * 97, index * 151)) & 511;
    float noise = texelFetch(noisetex, coord, 0).b;
    return fract(noise + float(frameCounter) * 0.6180339887498949f);
}

void ph_sample_light_direction(inout Light light, float light_radius) {
    vec3 light_position = floor(light.position) + 0.5f;

    // Fetch a blue noise value for this frame.
    vec2 rnd_sample      = vec2(ph_blue_noise(0), ph_blue_noise(1));

    vec3 light_dir       = light_position - light_ray.origin;

    vec3 light_tangent   = normalize(cross(light_dir, normalize(vec3(0.0f, 1.0f, 1.0f))));
    vec3 light_bitangent = normalize(cross(light_tangent, light_dir));

    // calculate disk point
    float point_radius = light_radius * sqrt(rnd_sample.x);

    float point_angle  = rnd_sample.y * 2.0f * 3.14159265f;
    vec2  disk_point   = vec2(point_radius * cos(point_angle), point_radius * sin(point_angle));

    light.position = light_position + disk_point.x * light_tangent + disk_point.y * light_bitangent;
}

vec3 ph_snap_shadow_world_position() {
    vec3 worldPos = base_position + world_offset;
    vec3 absN = abs(base_normal);
    vec3 faceAxis = vec3(0.0);
    float axisIndex = 0.0f;
    if (ph_mod_shadow_pixelation_enabled <= 0.5f) {
        return worldPos - world_offset;
    }
    if (absN.x >= absN.y && absN.x >= absN.z) {
        faceAxis.x = 1.0f;
        axisIndex = 0.0f;
    } else if (absN.y >= absN.z) {
        faceAxis.y = 1.0f;
        axisIndex = 1.0f;
    } else {
        faceAxis.z = 1.0f;
        axisIndex = 2.0f;
    }

    float safePixelSize = max(ph_mod_shadow_pixel_size_rt, 1.0f);
    float faceSign = sign(dot(base_normal, faceAxis));
    if (faceSign == 0.0f) {
        faceSign = 1.0f;
    }
    vec3 faceNormal = faceAxis * faceSign;
    const float faceInset = 1.0 / 512.0;
    vec3 ownedPos = worldPos - faceInset * faceNormal;
    vec3 blockOrigin = floor(ownedPos);
    vec3 localPos = ownedPos - blockOrigin;
    vec3 texelIdx = floor(localPos * safePixelSize);
    vec3 snappedLocal = (texelIdx + 0.5f) / safePixelSize;
    vec3 faceMask = vec3(1.0f) - faceAxis;
    float faceDepth = dot(blockOrigin, faceAxis) + (faceSign > 0.0 ? 1.0 : 0.0);
    worldPos = (blockOrigin + snappedLocal) * faceMask + faceDepth * faceAxis;

    vec2 planeFrac = vec2(0.0);
    if (faceAxis.x > 0.5f) {
        planeFrac = localPos.yz;
    } else if (faceAxis.y > 0.5f) {
        planeFrac = localPos.xz;
    } else {
        planeFrac = localPos.xy;
    }

    float checker = mod(texelIdx.x + texelIdx.y + texelIdx.z, 2.0f);
    vec2 debugTexelOffset = vec2(0.0f);
    float debugCenterFactor = 0.0f;
    float debugPixelMeta = 0.0f;
    float debugYBias = 0.0f;
    float debugCenterBlend = 0.0f;
    debugTexelOffset = planeFrac;
    debugCenterFactor = axisIndex;
    debugPixelMeta = faceSign;
    debugYBias = localPos.y;
    debugCenterBlend = checker;

    return worldPos - world_offset;
}

vec3 ph_sample_direct_lighting(vec3 position, vec3 normal, vec3 mapped_normal, Light light) {
    vec3 directPosition = ph_snap_shadow_world_position();
    light_ray.origin = directPosition + normal * 0.02f;
    vec3 to_light = light.position - light_ray.origin;
    light_ray.direction = normalize(to_light);

    // light attenuation
    float distance_squared = dot(to_light, to_light) * light.falloff;
    light.color /= dot(vec2(1, distance_squared), light.attenuation);

    if (floor(light.position) == floor(base_position)) {
        return light.color;
    }

    if (dot(light_ray.direction, mapped_normal) <= 0.01f) {
        return vec3(0.0f);
    }

    float cosine = clamp(dot(mapped_normal, light_ray.direction) * 2.0, 0.0, 1.0);
    light.color *= cosine;
    if (ph_luminance(light.color) < 0.001) {
        return vec3(0.0f);
    }

    ray_target = ivec3(light.position);
    // Scale shadow ray iterations based on light distance
    // Nearby lights need fewer steps, distant lights need more
    float light_dist = length(to_light);
    RAY_ITERATION_COUNT = clamp(int(light_dist * 2.0), 8, 32);
    trace_ray(light_ray, true);
    RAY_ITERATION_COUNT = 100;

    if (!light_ray.result_hit && light.attenuation.y == 0.0f) {
        light.color = vec3(0f);
    }

    if (floor(light.position) != floor(light_ray.result_position)) {
        light.color = vec3(0f);
    }

    light.color *= result_tint_color;

    return light.color;
}
