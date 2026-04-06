#ifndef PH_CORE_INCLUDE
#define PH_CORE_INCLUDE

int exposure_clear_index = 2 * ((frameCounter + 0) % 3);
int exposure_read_index  = 2 * ((frameCounter + 1) % 3);
int exposure_write_index = 2 * ((frameCounter + 2) % 3);

#ifdef FLIP_INDIRECT_INDEX
int indirect_write_index = frameCounter & 1;
int indirect_read_index = indirect_write_index ^ 1;
#else
int indirect_read_index = frameCounter & 1;
int indirect_write_index = indirect_read_index ^ 1;
#endif

//#forward

Light load_light(int index) {
    int real_index = index;
    index *= light_size;

    vec4 position_full = ph_lights_array[index + 0];
    vec4 color_full = ph_lights_array[index + 1];
    vec4 attenuation_full = ph_lights_array[index + 2];
    vec4 orientation_full = ph_lights_array[index + 3];

    return Light(
        real_index,
        floatBitsToInt(position_full.w),
        position_full.xyz - world_offset,
        color_full.xyz,
        color_full.w,
        attenuation_full.xy,
        attenuation_full.z,
        attenuation_full.w,
        normalize(orientation_full.xyz + vec3(1e-6f)),
        orientation_full.w
    );
}

#ifdef PH_DECLARE_GI_IMAGES
void ph_get_key(vec3 world_pos, vec3 normal, vec3 world_camera_pos, inout ivec3 key, out uint pos_i) {
    vec3 to_camera = world_pos - world_camera_pos;
    float view_distance_sq = dot(to_camera, to_camera);
    float dist = sqrt(view_distance_sq);
    bool badAngle = view_distance_sq > 1e-6f
        && dot(normal, to_camera * inversesqrt(view_distance_sq)) > -0.2f
        && dist > 16.0f;

    // How rough GI is, where resolution is roughly one block.
    float resolution = max(1.0f + floor(dist / 16.0f), 1.0f) / (4.0f * PH_RENDER_SCALE);
    if (badAngle) resolution*= 2f;

    world_pos = floor(world_pos / resolution) * resolution;

    uvec3 pos = uvec3(ivec3(floor(2.0f * world_pos)) & ivec3(511));
    pos_i = pos.x | (pos.y << 9u) | (pos.z << 18u);

    vec3 abs_normal = abs(normal);
    uint n_i = abs_normal.x > abs_normal.y ? 0 : 1;
    n_i = abs_normal[n_i] > abs_normal.z ? n_i : 2;

    n_i += 3 * uint(normal[n_i] > 0);

    //    if (is_axis_aligned) {
    //        n_i = normal[0] != 0 ? 0 : (normal[1] != 0 ? 1 : 2);
    //        n_i += 3 * uint(normal[n_i] > 0);
    //    }

    pos_i |= n_i << 27;

    uint hash = ph_wang_hash(pos_i);

    key.xy = ivec2(hash >> 16, hash & 0xffffu);

    key.xy %= indirect_res;
}

ivec3 ph_write(vec3 world_pos, vec3 normal, mat4 mvp, vec3 world_camera_pos) {
    ivec3 key = ivec3(0, 0, indirect_write_index);
    uint pos_i = 0;
    ph_get_key(world_pos, normal, world_camera_pos, key, pos_i);

    for (uint i = 0; i < 5; i++) {
        uint d = imageAtomicCompSwap(gi_d, key, 0, pos_i).x;
        if (d == 0 || d == pos_i) {
            return key;
        }
        key.xy = (key.xy + 1) % indirect_res;
    }

    return ivec3(NULL);
}

ivec3 ph_read(vec3 world_pos, vec3 normal, mat4 mvp, vec3 world_camera_pos) {
    ivec3 key = ivec3(0, 0, indirect_read_index);
    uint pos_i = 0;
    ph_get_key(world_pos, normal, world_camera_pos, key, pos_i);

    bool mismatch = false;
    for (uint i = 0, d = 0; i < 5 && (mismatch = (d = imageLoad(gi_d, key).x) != pos_i); i++) {
        key.xy = (key.xy + 1) % indirect_res;
    }

    return !mismatch ? key : ivec3(NULL);
}
#endif

ivec2 ph_reproject(mat4 mvp_matrix, vec3 world_position, vec2 viewSize, vec2 jitter) {
    return ivec2(floor(ph_reprojectf(mvp_matrix, world_position, viewSize, jitter)));
}

vec2 ph_reprojectf(mat4 mvp_matrix, vec3 world_position, vec2 viewSize, vec2 jitter) {
    vec4 viewspace_position = mvp_matrix * vec4(world_position, 1.0f);
    float w = viewspace_position.w;
    vec2 xy = viewspace_position.xy;
    xy = (xy/w + jitter) * 0.5f + 0.5f;

    return xy * viewSize * PH_RENDER_SCALE;
}

bool ph_is_valid_clip_projection(vec4 clipPosition) {
    return clipPosition.w > 0.0f
        && !any(isnan(clipPosition))
        && !any(isinf(clipPosition));
}

// RTXDI's DI temporal pass consumes pixel-space motion:
//   motion.xy = previousPixel - currentPixelCenter
//   motion.z  = previousLinearDepth - currentLinearDepth
// Invalid current/previous clip-space positions must produce an empty motion vector,
// matching GBufferHelpers.hlsli::getMotionVector.
// The Z term must stay in the same linear-depth space we store in stage_radiosity_position.w,
// otherwise temporal neighbor validation compares mismatched units and destabilizes reuse.
vec4 ph_compute_temporal_motion(vec3 worldPosition, vec2 currentPixelCenter, vec2 viewSize) {
    vec4 clipPosition = modelview_projection * vec4(worldPosition, 1.0f);
    vec4 previousClipPosition = previous_modelview_projection * vec4(worldPosition, 1.0f);

    if (!ph_is_valid_clip_projection(clipPosition) || !ph_is_valid_clip_projection(previousClipPosition)) {
        return vec4(0.0f);
    }

    vec2 previousPixel = (previousClipPosition.xy / previousClipPosition.w) * 0.5f + 0.5f;
    previousPixel *= viewSize * PH_RENDER_SCALE;

    float currentLinearDepth = ph_linear_view_depth(modelview_projection, worldPosition);
    float previousLinearDepth = ph_linear_view_depth(previous_modelview_projection, worldPosition);

    return vec4(
        previousPixel - currentPixelCenter,
        previousLinearDepth - currentLinearDepth,
        1.0f
    );
}

float ph_linear_view_depth(mat4 mvp_matrix, vec3 world_position) {
    // RTXDI's bridge compares surfaces using the G-buffer's linear view depth.
    // For the perspective matrices used here, clip.w tracks the absolute view-space z depth.
    return abs((mvp_matrix * vec4(world_position, 1.0f)).w);
}

int ph_hash(ivec3 v) {
    return ph_cantor(ph_hash(v.x), ph_cantor(ph_hash(v.y), ph_hash(v.z)));
}

int ph_cantor(int a, int b) {
    return (a + b + 1) * (a + b) / 2 + b;
}

int ph_hash(int seed) {
    seed = int(seed ^ int(61)) ^ int(seed >> int(16));
    seed *= int(9);
    seed = seed ^ (seed >> 4);
    seed *= int(0x27d4eb2d);
    seed = seed ^ (seed >> 15);

    return seed;
}

uint ph_wang_hash(inout uint seed)
{
    seed = uint(seed ^ uint(61)) ^ uint(seed >> uint(16));
    seed *= uint(9);
    seed = seed ^ (seed >> 4);
    seed *= uint(0x27d4eb2d);
    seed = seed ^ (seed >> 15);
    return seed;
}

uint oh_hash(uint seed) {
    seed = uint(seed ^ uint(61)) ^ uint(seed >> uint(16));
    seed *= uint(9);
    seed = seed ^ (seed >> 4);
    seed *= uint(0x27d4eb2d);
    seed = seed ^ (seed >> 15);

    return seed;
}

bool ph_RandomBool(inout uint state)
{
    return bool(ph_wang_hash(state) & 1u);
}

uint ph_rand_pcg(inout uint rng_state)
{
    uint state = rng_state;
    rng_state = rng_state * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

float ph_RandomFloat01(inout uint state)
{
    uint x = ph_rand_pcg(state);
    state = x;
    return float(x)*uintBitsToFloat(0x2f800000u);
}

float RandomFloat01(inout uint state)
{
    return ph_RandomFloat01(state);
}

vec3 ph_sample_random_direction(inout uint state)
{
    const float c_pi = 3.14159265359f;
    const float c_twopi = 2.0f * c_pi;

    float z = ph_RandomFloat01(state) * 2.0f - 1.0f;
    float a = ph_RandomFloat01(state) * c_twopi;
    float r = sqrt(1.0f - z * z);
    float x = r * cos(a);
    float y = r * sin(a);
    return vec3(x, y, z);
}

// Blue noise sampling with golden ratio temporal animation
// Uses Iris-provided noisetex (512x512) for spatially coherent sampling
vec2 ph_blue_noise_2d(ivec2 pixel_coord, int sample_index) {
    // Offset by sample index for independent samples within same pixel
    ivec2 coord = (pixel_coord + ivec2(sample_index * 97, sample_index * 151)) & 511;
    vec2 noise = texelFetch(noisetex, coord, 0).rg;
    // Golden ratio animation for temporal de-correlation
    float golden_ratio = 0.6180339887498949f;
    noise = fract(noise + float(frameCounter) * golden_ratio);
    return noise;
}

// Cosine-weighted hemisphere sample using blue noise
vec3 ph_sample_hemisphere_blue(vec3 normal, ivec2 pixel_coord, int sample_index) {
    vec2 blue = ph_blue_noise_2d(pixel_coord, sample_index);
    float z = blue.x * 2.0f - 1.0f;
    float a = blue.y * 2.0f * 3.14159265359f;
    float r = sqrt(1.0f - z * z);
    vec3 random_dir = vec3(r * cos(a), r * sin(a), z);
    return normalize(normal + random_dir);
}

vec3 ph_build_tangent(vec3 normal) {
    vec3 axis = abs(normal.z) < 0.999f ? vec3(0.0f, 0.0f, 1.0f) : vec3(0.0f, 1.0f, 0.0f);
    return normalize(cross(axis, normal));
}

vec3 ph_sample_cosine_hemisphere(vec3 normal, ivec2 pixel_coord, int sample_index) {
    vec2 blue = ph_blue_noise_2d(pixel_coord, sample_index);
    float phi = blue.x * 2.0f * 3.14159265359f;
    float r = sqrt(blue.y);
    float x = r * cos(phi);
    float y = r * sin(phi);
    float z = sqrt(max(0.0f, 1.0f - blue.y));

    vec3 tangent = ph_build_tangent(normal);
    vec3 bitangent = cross(normal, tangent);
    return normalize(tangent * x + bitangent * y + normal * z);
}

vec3 ph_sample_ggx_vndf(vec3 V, vec3 N, float roughness, ivec2 pixel_coord, int sample_index) {
    vec2 blue = ph_blue_noise_2d(pixel_coord, sample_index);
    float a = max(roughness * roughness, 0.02f);

    vec3 tangent = ph_build_tangent(N);
    vec3 bitangent = cross(N, tangent);
    mat3 basis = mat3(tangent, bitangent, N);

    vec3 Ve = transpose(basis) * normalize(V);
    vec3 Vh = normalize(vec3(a * Ve.x, a * Ve.y, max(Ve.z, 1e-4f)));

    float lensq = Vh.x * Vh.x + Vh.y * Vh.y;
    vec3 T1 = lensq > 1e-7f ? vec3(-Vh.y, Vh.x, 0.0f) * inversesqrt(lensq) : vec3(1.0f, 0.0f, 0.0f);
    vec3 T2 = cross(Vh, T1);

    float r = sqrt(blue.x);
    float phi = 2.0f * 3.14159265359f * blue.y;
    float t1 = r * cos(phi);
    float t2 = r * sin(phi);
    float s = 0.5f * (1.0f + Vh.z);
    t2 = mix(sqrt(max(0.0f, 1.0f - t1 * t1)), t2, s);

    vec3 Nh = t1 * T1 + t2 * T2 + sqrt(max(0.0f, 1.0f - t1 * t1 - t2 * t2)) * Vh;
    vec3 Ne = normalize(vec3(a * Nh.x, a * Nh.y, max(0.0f, Nh.z)));
    vec3 H = normalize(basis * Ne);
    return normalize(reflect(-V, H));
}

vec3 ph_sample_brdf_direction(vec3 normal, vec3 viewDir, vec3 albedoColor, float roughness, float metalness, ivec2 pixel_coord, int sample_index) {
    vec3 F0 = mix(vec3(0.04f), albedoColor, clamp(metalness, 0.0f, 1.0f));
    float F = clamp(max(F0.r, max(F0.g, F0.b)), 0.04f, 0.98f);
    vec2 selector = ph_blue_noise_2d(pixel_coord, sample_index + 37);

    if (selector.x < F) {
        vec3 reflected = ph_sample_ggx_vndf(viewDir, normal, roughness, pixel_coord, sample_index + 73);
        if (dot(reflected, normal) > 0.0f) {
            return reflected;
        }
    }

    return ph_sample_cosine_hemisphere(normal, pixel_coord, sample_index + 19);
}

#endif // PH_CORE
