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

uniform int frameCounter, frameTime;
uniform float frameTimeCounter, rainStrength, shadowFade, viewWidth, viewHeight;
uniform float ph_mod_shadow_pixelation_enabled;
uniform float ph_mod_shadow_pixel_size_rt;
uniform float ph_mod_pixelation_debug_enabled;
uniform sampler2D colortex6, colortex10, colortex11, depthtex0, noisetex;
uniform mat4 gbufferProjectionInverse, gbufferModelViewInverse, shadowProjection, shadowModelView;
uniform vec3 cameraPosition, eyePosition;

//#uniforms

#include "/photonics/photonics.glsl"
#include "/photonics/shader_interface.glsl"

uint rngState = uint(uint(gl_FragCoord.x) * uint(1973) + uint(gl_FragCoord.y) * uint(9277) + uint(frameCounter) * uint(26699)) | uint(1);

//#forward

RayJob light_ray = RayJob(vec3(0), vec3(0), vec3(0), vec3(0), vec3(0), false);
vec3 base_position = vec3(0.0f);
vec3 base_normal = vec3(0.0f);
vec3 mapped_normal = vec3(0.0f);

void main(void) {
    if (texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).x > 0.99999f) {
        if (ph_mod_pixelation_debug_enabled > 0.5f && phIsCenterProbePixel()) {
            ph_debug_probe[0] = vec4(0.0f, 0.0f, 0.0f, -1.0f);
            ph_debug_probe[1] = vec4(0.0f);
            ph_debug_probe[2] = vec4(0.0f);
            ph_debug_probe[3] = vec4(0.0f);
        }
        return;
    }

    vec3 albedo = vec3(0.0f);
    load_fragment_variables(albedo, base_position, base_normal, mapped_normal);

    base_position -= world_offset;
    handheld_frag_out = vec4(0.0f);

    reproject(true);

    // TODO: Handheld torch experimentation (looks *really* cool)
    if (any(notEqual(handheld_color, vec3(0.0f)))) {
        vec4 direction_vert_out = direction_transformation_matrix_in * vec4(left_handed ? 1.0f : -1.0f, -1.0f, 0.0f, 1.0f);
        direction_vert_out.w = 1.0f / direction_vert_out.w;
        direction_vert_out.xyz *= direction_vert_out.w;

        light_ray.origin = direction_vert_out.xyz + eyePosition - world_offset;
        //                light_ray.origin.y = camera_position.y - 0.5f;

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

        brightness *= (h(frameCounter / 300.0f) * 0.1f + h(frameCounter / 100.0f) * 0.05f) + 0.4f;

        handheld_frag_out.xyz = brightness * handheld_color;
    } else {
        handheld_frag_out.xyz = vec3(0.0f);
    }

    handheld_frag_out.w = 1.0f;
}

const float F = 2.0f;

// Pulse function
float g(float x) {
    return sin(F * 3.141592f * clamp(x, 0.0f, 1.0f / F));
}

// Noise
float n(float x) {
    return 0.5f * sin(1000.0f * x) + 0.5f;
}

// Periodic function with random offset
float h(float x) {
    return g(fract(x) - (1.0f - 1.0f / F) * n(floor(x)));
}

float luminance(vec3 rgb) {
    return dot(rgb, vec3(0.2126f, 0.7152f, 0.0722f));
}

bool phIsCenterProbePixel() {
    ivec2 fragCoord = ivec2(gl_FragCoord.xy);
    ivec2 centerCoord = ivec2(int(viewWidth * 0.5f), int(viewHeight * 0.5f));
    return all(equal(fragCoord, centerCoord));
}

void phWritePixelationDebugProbe(
    vec3 basePos,
    vec3 snappedPos,
    vec2 texelOffset,
    float centerFactor,
    float pixelMeta,
    float yBias,
    float centerBlend,
    float centerBranch
) {
    if (ph_mod_pixelation_debug_enabled <= 0.5f || !phIsCenterProbePixel()) {
        return;
    }

    float sameCell = all(equal(floor(snappedPos), floor(basePos))) ? 1.0f : 0.0f;
    ph_debug_probe[0] = vec4(basePos, float(frameCounter));
    ph_debug_probe[1] = vec4(snappedPos, length(snappedPos - basePos));
    ph_debug_probe[2] = vec4(texelOffset, centerFactor, pixelMeta);
    ph_debug_probe[3] = vec4(yBias, centerBlend, centerBranch, sameCell);
}

const Frag NULL4 = Frag(vec4(-999), vec4(-999));

vec4 texelFetch0(sampler2D sampler, ivec2 pos, int level) {
    return texelFetch(sampler, pos, level);
}

#define texelFetch(sampler, pos, level) \
    texelFetch0(sampler, pos, level)

Frag get(vec2 uv) {
    ivec2 pos = ivec2(uv);
    if (any(lessThan(pos, ivec2(0))) || any(greaterThanEqual(pos, res))) {
        return NULL4;
    }

    vec3 d = texelFetch(prev_radiosity_position, pos, 0).xyz - base_position - world_offset;
    if (dot(d, d) >= 0.1f) {
        return NULL4;
    }

    vec3 n = texelFetch(prev_radiosity_normal, pos, 0).xyz;
    if (dot(n, base_normal) < 0.99f) {
        return NULL4;
    }

    vec4 direct = texelFetch(prev_radiosity_direct, pos, 0);
    vec4 direct_soft = texelFetch(prev_radiosity_direct_soft, pos, 0);

    return Frag(direct, direct_soft);
}

Frag get_mixed(vec2 center) {
    ivec2 icenter = ivec2(center);

    Frag c_00 = get(icenter + ivec2(0, 0));
    Frag c_10 = get(icenter + ivec2(1, 0));
    Frag c_01 = get(icenter + ivec2(0, 1));
    Frag c_11 = get(icenter + ivec2(1, 1));

    Frag frag = mixNullable4(
        mixNullable4(c_00, c_10, fract(center.x)),
        mixNullable4(c_01, c_11, fract(center.x)),
        fract(center.y)
    );

    if (frag != NULL4) {
        vec3 directMin = vec3(1e10f);
        vec3 directMax = vec3(-1e10f);
        vec3 directSoftMin = vec3(1e10f);
        vec3 directSoftMax = vec3(-1e10f);
        int validCount = 0;

        if (c_00 != NULL4) {
            directMin = min(directMin, c_00.direct.xyz);
            directMax = max(directMax, c_00.direct.xyz);
            directSoftMin = min(directSoftMin, c_00.direct_soft.xyz);
            directSoftMax = max(directSoftMax, c_00.direct_soft.xyz);
            validCount++;
        }
        if (c_10 != NULL4) {
            directMin = min(directMin, c_10.direct.xyz);
            directMax = max(directMax, c_10.direct.xyz);
            directSoftMin = min(directSoftMin, c_10.direct_soft.xyz);
            directSoftMax = max(directSoftMax, c_10.direct_soft.xyz);
            validCount++;
        }
        if (c_01 != NULL4) {
            directMin = min(directMin, c_01.direct.xyz);
            directMax = max(directMax, c_01.direct.xyz);
            directSoftMin = min(directSoftMin, c_01.direct_soft.xyz);
            directSoftMax = max(directSoftMax, c_01.direct_soft.xyz);
            validCount++;
        }
        if (c_11 != NULL4) {
            directMin = min(directMin, c_11.direct.xyz);
            directMax = max(directMax, c_11.direct.xyz);
            directSoftMin = min(directSoftMin, c_11.direct_soft.xyz);
            directSoftMax = max(directSoftMax, c_11.direct_soft.xyz);
            validCount++;
        }

        if (validCount > 0) {
            vec3 directRange = max(directMax - directMin, vec3(0.01f));
            vec3 directSoftRange = max(directSoftMax - directSoftMin, vec3(0.01f));
            frag.direct.xyz = clamp(frag.direct.xyz, directMin - 0.35f * directRange, directMax + 0.35f * directRange);
            frag.direct_soft.xyz = clamp(frag.direct_soft.xyz, directSoftMin - 0.35f * directSoftRange, directSoftMax + 0.35f * directSoftRange);
        }
    }

    return frag;
}

Frag mixNullable4(Frag s1, Frag s2, float a) {
    if (s1 == NULL4) {
        a = 1.0f;
    } else if (s2 == NULL4) {
        a = 0.0f;
    }

    vec4 direct = mix(s1.direct, s2.direct, a);
    vec4 direct_soft = mix(s1.direct_soft, s2.direct_soft, a);

    return Frag(direct, direct_soft);
}

// TODO: reproject in voxel pattern to hide noise in texture
void reproject(bool sample_indirect) {
    vec2 center = reprojectf(previous_modelview_projection, base_position + world_offset + 0.01f * base_normal);

    position_frag_out = vec4(base_position + world_offset, 1.0f);
    normal_frag_out = vec4(base_normal, 1.0f);

    center -= 0.5f;
    Frag frag = get_mixed(center);

    if (light_reload || frag == NULL4) {
        frag.direct = vec4(0.0f);
        frag.direct_soft = vec4(0.0f);
    }

    if (ph_mod_shadow_pixelation_enabled > 0.5f) {
        frag.direct = vec4(0.0f);
        frag.direct_soft = vec4(0.0f);
    }

    // direct light
    vec3 directPosition = base_position;
    vec3 directNormal = base_normal;
    vec3 directMappedNormal = mapped_normal;
    vec2 debugTexelOffset = vec2(0.0f);
    float debugCenterFactor = 1.0f;
    float debugPixelMeta = 0.0f;
    float debugYBias = 0.0f;
    float debugCenterBlend = 0.0f;
    float debugCenterBranch = 0.0f;
    vec3 debugRawLocalPos = vec3(0.0);
    vec3 debugTexelIdx = vec3(0.0);
    vec3 debugFaceMask = vec3(0.0);
    if (ph_mod_shadow_pixelation_enabled > 0.5f) {
        vec3 worldPos = base_position + world_offset;
        float safePixelSize = max(ph_mod_shadow_pixel_size_rt, 1.0f);

        // Quantize normal to a single dominant axis to avoid tie-driven jitter.
        vec3 absN = abs(base_normal);
        vec3 faceAxis = vec3(0.0);
        float axisIndex = 2.0;
        if (absN.x >= absN.y && absN.x >= absN.z) {
            faceAxis = vec3(1.0, 0.0, 0.0);
            axisIndex = 0.0;
        } else if (absN.y >= absN.z) {
            faceAxis = vec3(0.0, 1.0, 0.0);
            axisIndex = 1.0;
        } else {
            faceAxis = vec3(0.0, 0.0, 1.0);
            axisIndex = 2.0;
        }
        float faceSign = sign(dot(base_normal, faceAxis));
        if (faceSign == 0.0) {
            faceSign = 1.0;
        }
        vec3 faceNormal = faceAxis * faceSign;
        vec3 faceMask = vec3(1.0) - faceAxis;
        debugFaceMask = faceMask;

        // Determine block ownership by moving slightly toward the face interior.
        // This avoids axis-specific ownership glitches on side faces.
        const float faceInset = 1.0 / 512.0;
        vec3 ownedPos = worldPos - faceInset * faceNormal;
        vec3 blockOrigin = floor(ownedPos);

        // Block-local coordinates (0..1 range = higher float precision)
        vec3 localPos = ownedPos - blockOrigin;
        localPos = clamp(localPos, vec3(0.0), vec3(0.9999));
        debugRawLocalPos = localPos;
        debugYBias = localPos.y;

        // Snap to texel centers at (k + 0.5) / pixelSize.
        vec3 texelIdx = floor(localPos * safePixelSize);
        vec3 snappedLocal = (texelIdx + 0.5) / safePixelSize;
        debugTexelIdx = texelIdx;
        vec3 texelFrac = fract(localPos * safePixelSize);
        float checker = float(mod(int(debugTexelIdx.x + debugTexelIdx.y + debugTexelIdx.z), 2));
        vec2 planeFrac = vec2(0.0);
        if (faceAxis.x > 0.5) {
            planeFrac = texelFrac.yz;
        } else if (faceAxis.y > 0.5) {
            planeFrac = texelFrac.xz;
        } else {
            planeFrac = texelFrac.xy;
        }
        debugTexelOffset = planeFrac;
        debugCenterFactor = axisIndex;
        debugPixelMeta = faceSign;
        debugCenterBlend = checker;

        // Clamp to valid texel centers within the block
        float centerMin = 0.5 / safePixelSize;
        float centerMax = (safePixelSize - 0.5) / safePixelSize;
        snappedLocal = clamp(snappedLocal, vec3(centerMin), vec3(centerMax));

        // Use deterministic face depth and snapped position on the face plane.
        float faceDepth = dot(blockOrigin, faceAxis) + (faceSign > 0.0 ? 1.0 : 0.0);
        worldPos = (blockOrigin + snappedLocal) * faceMask + faceDepth * faceAxis;

        directPosition = worldPos - world_offset;
        // Use quantized face normal for stable shadow-ray origin bias.
        directNormal = faceNormal;
        debugCenterBranch = 3.0f;
    }
    phWritePixelationDebugProbe(
        base_position,
        directPosition,
        debugTexelOffset,
        debugCenterFactor,
        debugPixelMeta,
        debugYBias,
        debugCenterBlend,
        debugCenterBranch
    );

    int light_offset = load_light_offset(base_position);

    int light_count = light_registry_array[light_offset];
    int soft_light_count = min(3, light_count);

    process_direct(frag, directPosition, directNormal, directMappedNormal, light_offset, light_count, soft_light_count);

    // Detect edge
    // TODO: we probably should do fract(2.0f * base_position)
    ivec3 inside = ivec3(lessThan(abs(fract(base_position) - 0.5f), vec3(0.48f)));
    bool onEdge = inside.x + inside.y + inside.z <= 1;

    if (!onEdge) { // TODO: not actually completely working
        process_indirect();
    }

    frag.direct.w = max(frag.direct.w, 0.01f);
    direct_frag_out = frag.direct;
    frag.direct_soft.w = max(frag.direct_soft.w, 0.01f);
    direct_soft_frag_out = frag.direct_soft;

    // Keep debug probe logging in SSBO only. Do not override visible lighting output.
}

void process_direct(inout Frag frag, vec3 directPosition, vec3 directNormal, vec3 directMappedNormal, int light_offset, int light_count, int soft_light_count) {
    for (; frag.direct.w < light_count - soft_light_count; frag.direct.w++) {
        int index = light_registry_array[soft_light_count + int(frag.direct.w) + light_offset + 1];
        Light light = load_light(index);
        vec3 directContribution = sample_direct_lighting(directPosition, directNormal, directMappedNormal, light);
        frag.direct.xyz += directContribution;
    }

    for (int i = 0; i < soft_light_count; i++) {
        int index = light_registry_array[(int(frag.direct_soft.w) % soft_light_count) + light_offset + 1];
        Light light = load_light(index);
        if (ph_mod_shadow_pixelation_enabled <= 0.5f) {
            sample_light_direction(light, 1.0f / 16.0f);
        }
        vec3 directContribution = sample_direct_lighting(directPosition, directNormal, directMappedNormal, light);
        frag.direct_soft.xyz += soft_light_count * directContribution;
        frag.direct_soft.w++;
    }
}

void process_indirect() {
    vec3 sample_position = base_position + world_offset;
    ivec3 write = write(sample_position, base_normal, modelview_projection, world_camera_position);

    uint w = imageAtomicAdd(gi_w, write, uint(1));
    if (w == 0) {
        ivec3 read = read(sample_position, base_normal, previous_modelview_projection, previous_world_camera_position);

        vec4 result = vec4(0.0f);
        result.x += imageLoad(gi_x, read).x / 255.0f;
        result.y += imageLoad(gi_y, read).x / 255.0f;
        result.z += imageLoad(gi_z, read).x / 255.0f;
        result.w = imageLoad(gi_w, read).x;

        float historyDecay = light_reload ? 0.0f : 0.985f;
        result *= historyDecay;

        imageAtomicAdd(gi_x, write, uint(result.x * 255.0f));
        imageAtomicAdd(gi_y, write, uint(result.y * 255.0f));
        imageAtomicAdd(gi_z, write, uint(result.z * 255.0f));
        imageAtomicAdd(gi_w, write, uint(result.w));
    } else if (w < 2048) {
        vec3 result = sample_indirect_lighting();

        imageAtomicAdd(gi_x, write, uint(result.x * 255.0f));
        imageAtomicAdd(gi_y, write, uint(result.y * 255.0f));
        imageAtomicAdd(gi_z, write, uint(result.z * 255.0f));
    } else {
        imageAtomicAdd(gi_w, write, uint(-1));
    }
}

// TODO: take sun light into account
vec3 sample_indirect_lighting() {
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
        light_ray.direction = normalize(light_ray.result_normal + sample_random_direction(rngState));

        bool sun = RandomFloat01(rngState) < 0.25f && dot(sun_direction, light_ray.result_normal) > 0.707f;
        if (sun) {
            light_ray.direction = sun_direction;
        }

        RAY_ITERATION_COUNT = 20;
        breakOnEmpty = true;
        trace_ray(light_ray);
        breakOnEmpty = false;
        RAY_ITERATION_COUNT = 100;

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

float blue_noise(int index) {
    return texelFetch(noisetex, ivec2(rand_pcg(rngState), rand_pcg(rngState)) & 511, 0).b;
}

void sample_light_direction(inout Light light, float light_radius) {
    vec3 light_position = floor(light.position) + 0.5f;

    // Fetch a blue noise value for this frame.
    vec2 rnd_sample      = vec2(blue_noise(0), blue_noise(1));

    vec3 light_dir       = light_position - light_ray.origin;

    vec3 light_tangent   = normalize(cross(light_dir, normalize(vec3(0.0f, 1.0f, 1.0f))));
    vec3 light_bitangent = normalize(cross(light_tangent, light_dir));

    // calculate disk point
    float point_radius = light_radius * sqrt(rnd_sample.x);

    float point_angle  = rnd_sample.y * 2.0f * 3.14159265f;
    vec2  disk_point   = vec2(point_radius * cos(point_angle), point_radius * sin(point_angle));

    light.position = light_position + disk_point.x * light_tangent + disk_point.y * light_bitangent;
}

vec3 sample_direct_lighting(vec3 position, vec3 normal, vec3 mapped_normal, Light light) {
    float surfaceBias = 0.02f;
    if (ph_mod_shadow_pixelation_enabled > 0.5f) {
        // Use a smaller, deterministic bias in pixelated mode to reduce face-direction flicker.
        surfaceBias = max(0.003f, 0.25f / max(ph_mod_shadow_pixel_size_rt, 1.0f));
    }
    light_ray.origin = position + normal * surfaceBias;
    vec3 to_light = light.position - light_ray.origin;
    light_ray.direction = normalize(to_light);
    if (ph_mod_shadow_pixelation_enabled > 0.5f) {
        // Push the origin slightly along the ray to avoid DDA tie breaks on voxel boundaries.
        light_ray.origin += light_ray.direction * 0.0015f;
    }

    // light attenuation
    float distance_squared = dot(to_light, to_light);
    light.color /= dot(vec2(1, distance_squared), light.attenuation);

    if (floor(light.position) == floor(base_position)) {
        return light.color;
    }

    if (dot(light_ray.direction, mapped_normal) <= 0.01f) {
        return vec3(0.0f);
    }

    float cosine = clamp(dot(mapped_normal, light_ray.direction) * 2.0, 0.0, 1.0);
    light.color *= cosine;
    if (luminance(light.color) < 0.00002) {
        return vec3(0.0f);
    }

    ray_target = ivec3(light.position);
    // Avoid hard radius cutoffs by scaling ray budget with source distance.
    int directTraceBudget = int(clamp(ceil(length(to_light)) + 12.0f, 24.0f, 120.0f));
    RAY_ITERATION_COUNT = directTraceBudget;
    trace_ray(light_ray);
    RAY_ITERATION_COUNT = 100;

    if (!light_ray.result_hit) {
        return light.attenuation.y == 0.0f ? light.color * cosine : vec3(0.0f);
    }

    if (floor(light.position) != floor(light_ray.result_position)) {
        return vec3(0.0f);
    }

    return light.color;
}
