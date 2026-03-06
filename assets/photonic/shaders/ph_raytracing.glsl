#ifndef PH_RAYTRACING
#define PH_RAYTRACING

//#forward

const int[] morton = int[](0, 1, 8, 9, 64, 65, 72, 73, 512, 513, 520, 521, 576, 577, 584, 585, 4096,
                           4097, 4104, 4105, 4160, 4161, 4168, 4169, 4608, 4609, 4616, 4617, 4672, 4673, 4680, 4681);

int RAY_ITERATION_COUNT = 100;
bool ray_iteration_bound_reached = false;

vec3 debug = vec3(0.0f);

ivec3 ray_target = ivec3(-9999);
ivec3 ray_constraint = ivec3(-9999);
bool breakOnEmpty = false;

vec3 lightEmittance = vec3(0.0f);
float ray_hit_alpha = 1.0f;

void trace_ray(inout RayJob job) {
    job.direction = normalize(job.direction);
    ray_hit_alpha = 1.0f;

    vec3 direction_inv = 1.0f / job.direction;
    float t0 = intersects_world(direction_inv, 16.0f * job.origin);
    if (t0 == -1.0f) {
        job.result_position = vec3(47823934.0f) - world_offset;
        return;
    }

    vec3 position = job.origin * 16.0f + (t0 + 0.03f) * job.direction;
    //    vec3 position = 16.0f * job.origin;

    vec3 ray_direction_sign = sign(job.direction);

    ivec3 intersection_index = ivec3(7.5f * ray_direction_sign + vec3(7.5f, 12.5f, 17.5f));
    vec3 skipDelta = ray_direction_sign * 0.00001f;
    ivec3 intersection_offset = max(ivec3(ray_direction_sign), 0);

    int t_min = -1;

    ivec3 new_index = ivec3(0);
    ivec3 old_index = ivec3(0);

    ivec3 entries = ivec3(0);
    for (int i = RAY_ITERATION_COUNT; !(ray_iteration_bound_reached = i < 0); i--) {
        //        debug += vec3(0.1f);

        ivec3 w = ivec3(position); // TODO: maybe use uvec3, no negative check neccessary
        ivec3 block_position = w >> 4;

        if (!is_inside(position)) // outside of world?
            return;
        if ((job.result_hit = block_position == ray_target)) { // ray target reached?
            break;
        }
        if (ray_constraint != ivec3(-9999) && block_position != ray_constraint)
            return;

        int scale = 0;
        int entry = 0;

        new_index.x = get_world_index((w >> 8) & 31);
        if (new_index.x != old_index.x) { // TODO: CRITICAL! UBOs are too tiny for 32x32x32
            entries.x = root_array[new_index.x];
        }

        if (entries.x < 0) { // found chunk?

            new_index.y = -entries.x + get_index((w >> 4) & 15);
            if (new_index.y != old_index.y) {
                entries.y = cb_array[new_index.y];
            }

            if (entries.y < 0) { // found block

                new_index.z = -entries.y + get_index(w & 15);
                if (new_index.z != old_index.z) {
                    entries.z = cb_array[new_index.z];

                    if (breakOnEmpty && entries.z == 519536640) {
                        job.result_hit = true;
                        break;
                    }
                }

                if (entries.z < 0) { // found bloxel
                    job.result_hit = true;
                    break;
                } else { scale = 0; entry = entries.z; }
            } else { scale = 4; entry = entries.y; }
        } else { scale = 8; entry = entries.x; }

        old_index = new_index;

        ivec3 intersection = (((ivec3(entry) >> intersection_index) & 31) + intersection_offset) << scale;

        scale += 4;
        scale += int(scale == 8 + 4);
        intersection += w & (-1 << scale);

        vec3 t = (intersection - position) * direction_inv;
        t_min = int(t.x >= t.y);
        t_min = t.z < t[t_min] ? 2 : t_min;

        position += t[t_min] * job.direction;

        // "push precision" into lower decimal values to fight rounding errors
        position[t_min] = (intersection[t_min] * 0.01f + skipDelta[t_min]) * 100.0f;
    }

    lightEmittance = unpackUnorm4x8(cb_array[-entries.y / 4096]).xyz;

    job.result_color = vec3((-entries.z >> 0) & 0xff, (-entries.z >> 8) & 0xff, (-entries.z >> 16) & 0xff) / 0xff;
    ray_hit_alpha = float((-entries.z >> 24) & 0xff) / 255.0f;
    job.result_position = job.result_hit ? vec3(position / 16.0f) : (vec3(47823934.0f) - world_offset);

    if (t_min != -1)
        job.result_normal[t_min] = sign(-ray_direction_sign[t_min]);

    //    job.result_color = debug;

    ray_target = ivec3(-1);
}

int get_block_pointer(vec3 position) {
    if (!is_inside(16.0f * position)) {
        return -1;
    }

    ivec3 w = ivec3(position);
    int index = 0;

    index = root_array[get_world_index((w >> 4) & 31)];
    if (index >= 0) {
        return -1;
    }

    return -cb_array[-index + get_index(w & 15)];
}

// TODO: calculate normals; normals are always (0, 1, 0) at first iteration
float intersects_world(vec3 direction_inv, vec3 origin) {
    if (is_inside(origin)) {
        return 0.0f;
    }

    vec3 tbot = direction_inv * (world_min_voxel - origin);
    vec3 ttop = direction_inv * (world_max_voxel - origin);
    vec3 tmin = min(ttop, tbot);
    vec3 tmax = max(ttop, tbot);
    vec2 t = max(tmin.xx, tmin.yz);
    float t0 = max(t.x, t.y);
    t = min(tmax.xx, tmax.yz);
    float t1 = min(t.x, t.y);

    return t1 > max(t0, 0.0f) ? t0 : -1.0f;
}

bool is_inside(vec3 position) {
    vec3 s = step(world_min_voxel, position) - step(world_max_voxel, position);
    return bool(s.x * s.y * s.z);
}

int get_index(ivec3 position) {
    return morton[position.x] | (morton[position.y] << 1) | (morton[position.z] << 2);
}

int get_world_index(ivec3 position) {
    return morton[position.x] | (morton[position.y] << 1) | (morton[position.z] << 2);
}

#endif // PH_RAYTRACING
