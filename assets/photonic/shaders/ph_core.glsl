#ifndef PH_CORE
#define PH_CORE

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
    index *= 2;
    vec4 lower = lights_array[index + 0];
    vec4 upper = lights_array[index + 1];

    return Light(lower.xyz - world_offset, vec3(lower.w, upper.xy), upper.zw);
}

void get_key(vec3 world_pos, vec3 normal, vec3 world_camera_pos, inout ivec3 key, out uint pos_i) {
    float dist = distance(floor(world_pos), floor(world_camera_pos));

    bool badAngle = dot(normal, normalize(world_pos - world_camera_pos)) > -0.2f && dist > 16.0f;
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

    uint hash = wang_hash(pos_i);

    key.xy = ivec2(hash >> 16, hash & 0xffffu);

    key.xy %= indirect_res;
}

ivec3 write(vec3 world_pos, vec3 normal, mat4 mvp, vec3 world_camera_pos) {
    ivec3 key = ivec3(0, 0, indirect_write_index);
    uint pos_i = 0;
    get_key(world_pos, normal, world_camera_pos, key, pos_i);

    for (uint i = 0, d = 0; i < 5 && (d = imageAtomicCompSwap(gi_d, key, 0, pos_i).x) != 0 && d != pos_i; i++) {
        key.xy = (key.xy + 1) % indirect_res;
    }

    return key;
}

ivec3 read(vec3 world_pos, vec3 normal, mat4 mvp, vec3 world_camera_pos) {
    ivec3 key = ivec3(0, 0, indirect_read_index);
    uint pos_i = 0;
    get_key(world_pos, normal, world_camera_pos, key, pos_i);

    bool mismatch = false;
    for (uint i = 0, d = 0; i < 5 && (mismatch = (d = imageLoad(gi_d, key).x) != pos_i); i++) {
        key.xy = (key.xy + 1) % indirect_res;
    }

    return !mismatch ? key : ivec3(NULL);
}

ivec2 reproject(mat4 mvp_matrix, vec3 world_position) {
    vec4 viewspace_position = mvp_matrix * vec4(world_position, 1.0f);

    ivec2 pos = ivec2(floor((viewspace_position.xy / viewspace_position.w * 0.5f + 0.5f) * res));

    return pos % res;
}

vec2 reprojectf(mat4 mvp_matrix, vec3 world_position) {
    vec4 viewspace_position = mvp_matrix * vec4(world_position, 1.0f);

    return (viewspace_position.xy / viewspace_position.w * 0.5f + 0.5f) * res;
}

int load_light_offset(vec3 position) {
    vec3 o = floor(position / 8.0f);

    return 21 * int(o.y * 64 * 64 + o.z * 64 + o.x);
}

int mod(int divident, int divisor) {
    return divident - int(divident / divisor) * divisor;
}

uint mod(uint divident, uint divisor) {
    return divident - uint(divident / divisor) * divisor;
}

int hash(ivec3 v) {
    return cantor(hash(v.x), cantor(hash(v.y), hash(v.z)));
}

int cantor(int a, int b) {
    return (a + b + 1) * (a + b) / 2 + b;
}

int hash(int seed) {
    seed = int(seed ^ int(61)) ^ int(seed >> int(16));
    seed *= int(9);
    seed = seed ^ (seed >> 4);
    seed *= int(0x27d4eb2d);
    seed = seed ^ (seed >> 15);

    return seed;
}

uint wang_hash(inout uint seed)
{
    seed = uint(seed ^ uint(61)) ^ uint(seed >> uint(16));
    seed *= uint(9);
    seed = seed ^ (seed >> 4);
    seed *= uint(0x27d4eb2d);
    seed = seed ^ (seed >> 15);
    return seed;
}

uint hash(uint seed) {
    seed = uint(seed ^ uint(61)) ^ uint(seed >> uint(16));
    seed *= uint(9);
    seed = seed ^ (seed >> 4);
    seed *= uint(0x27d4eb2d);
    seed = seed ^ (seed >> 15);

    return seed;
}

bool RandomBool(inout uint state)
{
    return bool(wang_hash(state) & 1u);
}

uint rand_pcg(inout uint rng_state)
{
    uint state = rng_state;
    rng_state = rng_state * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

float RandomFloat01(inout uint state)
{
    uint x = rand_pcg(state);
    state = x;
    return float(x)*uintBitsToFloat(0x2f800000u);
}

vec3 sample_random_direction(inout uint state)
{
    const float c_pi = 3.14159265359f;
    const float c_twopi = 2.0f * c_pi;

    float z = RandomFloat01(state) * 2.0f - 1.0f;
    float a = RandomFloat01(state) * c_twopi;
    float r = sqrt(1.0f - z * z);
    float x = r * cos(a);
    float y = r * sin(a);
    return vec3(x, y, z);
}

#endif // PH_CORE