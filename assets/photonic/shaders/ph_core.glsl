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
    index *= light_size;

    vec4 position_full = lights_array[index + 0];
    vec4 color_full = lights_array[index + 1];
    vec4 attenuation_full = lights_array[index + 2];

    return Light(
        floatBitsToInt(position_full.w),
        position_full.xyz - world_offset,
        color_full.xyz,
        color_full.w,
        attenuation_full.xy,
        attenuation_full.z,
        attenuation_full.w
    );
}

void ph_get_key(vec3 world_pos, vec3 normal, vec3 world_camera_pos, inout ivec3 key, out uint pos_i) {
    float dist = distance(floor(world_pos), floor(world_camera_pos));
    
    bool badAngle = dot(normal, normalize(world_pos - world_camera_pos)) > -0.2f && dist > 16.0f;

    // Quantize more aggressively at distance and for grazing angles to stabilize GI history.
    float resolution = 0.5f;
    if (dist > 32.0f || badAngle) {
        resolution = 1.0f;
    }
    if (dist > 128.0f) {
        resolution = 2.0f;
    }

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

    for (uint i = 0, d = 0; i < 5 && (d = imageAtomicCompSwap(gi_d, key, 0, pos_i).x) != 0 && d != pos_i; i++) {
        key.xy = (key.xy + 1) % indirect_res;
    }

    return key;
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

ivec2 ph_reproject(mat4 mvp_matrix, vec3 world_position) {
    vec4 viewspace_position = mvp_matrix * vec4(world_position, 1.0f);

    ivec2 pos = ivec2(floor((viewspace_position.xy / viewspace_position.w * 0.5f + 0.5f) * ires));

    return pos % ires;
}

vec2 ph_reprojectf(mat4 mvp_matrix, vec3 world_position, vec2 viewSize, vec2 jitter) {
    vec4 viewspace_position = mvp_matrix * vec4(world_position, 1.0f);
    float w = viewspace_position.w;
    vec2 xy = viewspace_position.xy;
    xy = (xy/w + jitter) * 0.5f + 0.5f;


    return xy * viewSize * PH_RENDER_SCALE;
}

int load_light_offset(vec3 position) {
    vec3 o = floor(position / 8.0f);

    return (1 + PH_MAX_SAMPLES) * int(o.y * 64 * 64 + o.z * 64 + o.x);
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

#endif // PH_CORE
