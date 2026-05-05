#ifndef PH_RAYTRACING
#define PH_RAYTRACING

//#forward

const int[] morton = int[](0, 1, 8, 9, 64, 65, 72, 73, 512, 513, 520, 521, 576, 577, 584, 585, 4096,
                           4097, 4104, 4105, 4160, 4161, 4168, 4169, 4608, 4609, 4616, 4617, 4672, 4673, 4680, 4681);

const float tint_darken_cutoff = 0.7f;
const float tint_darken_offset = 1f - 0.7f;
const float tint_darken_factor = 1f / tint_darken_offset;

//public static final int BLOCK_SIZE = 16;
//
//public static final int INT_SIZE = 4;
//public static final int SCHEMATIC_SIZE = INT_SIZE * (BLOCK_SIZE * BLOCK_SIZE * BLOCK_SIZE);

int RAY_ITERATION_COUNT = 100;
bool ray_iteration_bound_reached = false;
bool ray_distance_limit_reached = false;

int result_block_id = -1;
vec3 result_tint_color = vec3(1f);
int ph_result_sky_brightness = 0;

ivec3 ray_target = ivec3(-9999);
ivec3 ray_constraint = ivec3(-9999);
bool breakOnEmpty = false;
float ray_min_trace_distance = 0.0f;
float ray_max_trace_distance = -1.0f;
int ray_ignore_block_id = -1;
bool ray_stop_on_target = false;

vec3 lightEmittance = vec3(0.0f);

int ph_lookup_chunk_entry(int chunk_base, ivec3 block_position);
float ph_signed_nudge(float value);
vec3 ph_signed_nudge(vec3 value);
float ph_intersects_world(vec3 direction_inv, vec3 origin);
bool ph_is_inside(vec3 position);
int ph_get_index(ivec3 position);
int ph_get_world_index(ivec3 position);
int ph_to_fake_air_entry(ivec3 pos);

int ph_to_air_entry_bounds(ivec3 min_pos, ivec3 max_pos) {
    return (min_pos.x << 0)
        | (min_pos.y << 5)
        | (min_pos.z << 10)
        | ((max_pos.x - 1) << 15)
        | ((max_pos.y - 1) << 20)
        | ((max_pos.z - 1) << 25);
}

void trace_ray(inout RayJob job, bool transparency) {
    job.result_hit = false;
    job.result_normal = vec3(0.0f);
    job.result_color = vec3(0.0f);

    job.direction = normalize(ph_signed_nudge(job.direction));

    vec3 direction_inv = 1.0f / job.direction;
    vec3 origin16 = 16.0f * job.origin;
    float t0 = ph_intersects_world(direction_inv, origin16);
    if (t0 == -1.0f) {
        job.result_position = vec3(47823934.0f) - world_offset;
        return;
    }

    vec3 position = origin16 + (t0 + 0.03f) * job.direction;
    //    vec3 position = 16.0f * job.origin;

    vec3 ray_direction_sign = sign(job.direction);
    ivec3 world_min_block = ivec3(world_min_voxel);
    ivec3 world_max_block = ivec3(world_max_voxel);
    ivec3 target_block = ray_target;
    ivec3 constraint_block = ray_constraint;
    bool hasRayTarget = target_block.x != -9999;
    bool hasRayConstraint = constraint_block.x != -9999;
    bool stopOnTarget = ray_stop_on_target;
    bool boundedVisibilityRay = ray_max_trace_distance > 0.0f;
    bool useShortRayAbort = RAY_ITERATION_COUNT <= 32;
    float min_trace_sq = ray_min_trace_distance > 0.0f
        ? ray_min_trace_distance * ray_min_trace_distance * 256.0f
        : 0.0f;
    float max_trace_sq = ray_max_trace_distance > 0.0f
        ? ray_max_trace_distance * ray_max_trace_distance * 256.0f
        : 0.0f;
    bool needsTravelDistance = min_trace_sq > 0.0f || max_trace_sq > 0.0f || useShortRayAbort;

    int emission_ptr = -1;
    ivec3 intersection_index = ivec3(7.5f * ray_direction_sign + vec3(7.5f, 12.5f, 17.5f));
    vec3 skipDelta = ray_direction_sign * 0.00001f;
    ivec3 intersection_offset = max(ivec3(ray_direction_sign), 0);

    int t_min = -1;

    int block_index = -1;

    int voxel_index = 0;


    ivec3 new_index = ivec3(0);
    ivec3 old_index = ivec3(0);

    ivec3 entries = ivec3(0);

    result_tint_color = vec3(1f);
    result_block_id = -1;

    ph_result_sky_brightness = 0;

    vec3 previous_tint = vec3(-1.0f);
    ray_distance_limit_reached = false;
    #ifdef PH_FULL_TRANSPARENCY
    bool usePerVoxelTransparency = true;
    #else
    // RTXDI visibility rays need exact segment occlusion against the voxelized
    // scene, even if the shaderpack's global transparency mode is the cheaper
    // per-block variant. Restrict the more exact stepping to bounded rays so
    // long-path GI/secondary traces keep the pack's intended performance mode.
    bool usePerVoxelTransparency = transparency && ray_max_trace_distance > 0.0f;
    #endif

    for (int i = RAY_ITERATION_COUNT; !(ray_iteration_bound_reached = i < 0); i--) {
        // GLSL integer casts truncate toward zero, which misindexes negative voxel
        // coordinates. The ray tracer operates in a signed RT space, so use floor().
        ivec3 w = ivec3(floor(position));
        ivec3 block_position = w >> 4;

        if (any(lessThan(w, world_min_block)) || any(greaterThanEqual(w, world_max_block))) // outside of world?
            return;

        float travel_dist_sq = 0.0f;
        if (needsTravelDistance) {
            vec3 travel_delta = position - origin16;
            travel_dist_sq = dot(travel_delta, travel_delta);
        }
        bool before_min_trace_distance = false;

        if (min_trace_sq > 0.0f) {
            before_min_trace_distance = travel_dist_sq < min_trace_sq;
        }

        // Visibility rays emulate RTXDI's TMax with an explicit distance cap so
        // transparent segments stop at the sampled light instead of running through
        // geometry that lies beyond the RTXDI shadow-ray segment.
        if (max_trace_sq > 0.0f) {
            if (travel_dist_sq > max_trace_sq) {
                ray_distance_limit_reached = true;
                break;
            }
        }

        // Early termination: secondary rays (GI/shadow) that travel too far
        // are unlikely to contribute useful lighting information
        if (useShortRayAbort) {
            if (travel_dist_sq > 4194304.0f) { // > 128 blocks (2048 voxels squared)
                return;
            }
        }

        bool targetReached = !before_min_trace_distance
            && hasRayTarget
            && all(equal(block_position, target_block))
            && (max_trace_sq <= 0.0f || stopOnTarget);
        if (targetReached) { // ray target reached?
            job.result_hit = true;
            result_block_id = -1;
            break;
        }
        if (hasRayConstraint && any(notEqual(block_position, constraint_block)))
            return;

        int scale = 0;
        int entry = 0;

        new_index.x = ph_get_world_index((w >> 8) & 31);
        if (new_index.x != old_index.x) { // TODO: CRITICAL! UBOs are too tiny for 32x32x32
            entries.x = root_array[new_index.x];
        }

        if (entries.x < 0) { // found chunk?
            ivec3 block_pos = (w >> 4) & 15;
            new_index.y = -entries.x + ph_get_index(block_pos);

            if (new_index.y != old_index.y) {
                entries.y = ph_lookup_chunk_entry(-entries.x, block_pos);
                if (entries.y < 0) { // found block
                    int block_data = -entries.y;

                    block_index = block_data & 0x1fff;
                    block_index = block_index * (ph_byte_size / 4);

                    ph_result_sky_brightness = block_data >> 13;

                    result_block_id = cb_array[block_index];
                    emission_ptr = block_index + 1;

                    voxel_index = block_index + 2;
                } else {
                    block_index = -1;
                }
            }

            if (block_index != -1) { // found block
                bool ignoreTargetHostBlock = ray_ignore_block_id >= 0
                    && ray_max_trace_distance > 0.0f
                    && all(equal(block_position, ray_target))
                    && result_block_id == ray_ignore_block_id;

                if (ignoreTargetHostBlock) {
                    scale = 4;
                    entry = ph_to_fake_air_entry(block_pos);
                } else {
                    ivec3 voxel_pos = w & 15;
                    new_index.z = voxel_index + ph_get_index(voxel_pos);
                    if (new_index.z != old_index.z) {
                        entries.z = cb_array[new_index.z];

                        if (breakOnEmpty && entries.z == 519536640) {
                            job.result_hit = false;
                            entries.z = -0;

                            break;
                        }
                    }

                    if (entries.z < 0) { // found bloxel
                        if (before_min_trace_distance) {
                            if (usePerVoxelTransparency) {
                                scale = 0;
                                entry = ph_to_fake_air_entry(voxel_pos);
                            } else {
                                scale = 4;
                                entry = ph_to_fake_air_entry(block_pos);
                            }
                        #ifdef PH_USE_TRANSPARENCY
                        } else if (!transparency) {
                            job.result_hit = true;
                            break;
                        } else {
                            int packedColor = -entries.z;
                            int packedTransparencySteps = (packedColor >> 24) & 0x7f;

                            // The block voxelizer stores alpha in 7 bits. Treat voxels that land one
                            // quantization step away from fully opaque as opaque here so tiny alpha loss
                            // from filtering / blended model layers doesn't leak tinted background light
                            // through walls and other nearly-opaque surfaces.
                            if (packedTransparencySteps <= 1) {
                                job.result_hit = true;
                                break;
                            }

                            vec4 color = ph_unpack_color(packedColor);
                            if (previous_tint != color.rgb) {
                                #if defined PH_USE_CUSTOM_ALPHA
                                result_tint_color*= PH_ALPHA_FUNC(color);
                                #else
                                if (color.a > tint_darken_cutoff) {
                                    result_tint_color*= color.rgb *
                                        (tint_darken_offset - (color.a - tint_darken_cutoff)) * tint_darken_factor;
                                } else if (color.a > 0.5f) {
                                    result_tint_color*= color.rgb;
                                } else {
                                    result_tint_color*= mix(
                                        color.rgb,
                                        vec3(1f),
                                        1f - (color.a * 2f)
                                    );
                                }
                                #endif

                                previous_tint = color.rgb;
                            }

                            if (usePerVoxelTransparency) {
                                scale = 0;
                                entry = ph_to_fake_air_entry(voxel_pos);
                            } else {
                                scale = 4;
                                entry = ph_to_fake_air_entry(block_pos);
                            }
                        }
                        #else
                        } else {
                            job.result_hit = true;
                            break;
                        }
                        #endif
                    } else { scale = 0; entry = entries.z; }
                }
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

        // Root-level empty space look-ahead is useful for long unbounded rays,
        // but bounded ReSTIR shadow rays are short enough that the extra branch
        // and chunk probes usually cost more than they save.
        if (!boundedVisibilityRay && scale == 13 && entries.x >= 0) {  // scale 13 = root level (8+4+1)
            for (int skip = 0; skip < 8; skip++) {
                ivec3 skip_w = ivec3(floor(position));
                if (any(lessThan(skip_w, world_min_block)) || any(greaterThanEqual(skip_w, world_max_block))) break;

                ivec3 skip_chunk = (skip_w >> 8) & 31;
                int skip_idx = ph_get_world_index(skip_chunk);
                if (skip_idx == new_index.x) break;  // Same chunk, stop

                int skip_entry = root_array[skip_idx];
                if (skip_entry < 0) break;  // Found occupied chunk, stop

                // Step through this empty chunk too
                new_index.x = skip_idx;
                entries.x = skip_entry;

                ivec3 skip_intersection = (((ivec3(skip_entry) >> intersection_index) & 31) + intersection_offset) << 8;
                skip_intersection += skip_w & (-1 << 13);

                vec3 skip_t = (skip_intersection - position) * direction_inv;
                int skip_axis = int(skip_t.x >= skip_t.y);
                skip_axis = skip_t.z < skip_t[skip_axis] ? 2 : skip_axis;

                position += skip_t[skip_axis] * job.direction;
                position[skip_axis] = (skip_intersection[skip_axis] * 0.01f + skipDelta[skip_axis]) * 100.0f;
                t_min = skip_axis;
            }
        }

        // Block-level empty space look-ahead has the same tradeoff as the root
        // skip and is also bypassed for bounded visibility rays.
        if (!boundedVisibilityRay && scale == 8 && entries.y >= 0 && entries.x < 0) {  // scale 8 = block level (4+4)
            for (int bskip = 0; bskip < 6; bskip++) {
                ivec3 bskip_w = ivec3(floor(position));
                if (any(lessThan(bskip_w, world_min_block)) || any(greaterThanEqual(bskip_w, world_max_block))) break;

                ivec3 bskip_chunk = (bskip_w >> 8) & 31;
                int bskip_chunk_idx = ph_get_world_index(bskip_chunk);
                int bskip_chunk_entry = root_array[bskip_chunk_idx];
                if (bskip_chunk_entry >= 0) break;  // Different or empty chunk

                ivec3 bskip_block = (bskip_w >> 4) & 15;
                int bskip_block_idx = -bskip_chunk_entry + ph_get_index(bskip_block);
                if (bskip_block_idx == new_index.y) break;  // Same block

                int bskip_entry = ph_lookup_chunk_entry(-bskip_chunk_entry, bskip_block);
                if (bskip_entry < 0) break;  // Found occupied block, stop

                // Step through this empty block
                new_index.y = bskip_block_idx;
                entries.y = bskip_entry;

                ivec3 bskip_intersection = (((ivec3(bskip_entry) >> intersection_index) & 31) + intersection_offset) << 4;
                bskip_intersection += bskip_w & (-1 << 8);

                vec3 bskip_t = (bskip_intersection - position) * direction_inv;
                int bskip_axis = int(bskip_t.x >= bskip_t.y);
                bskip_axis = bskip_t.z < bskip_t[bskip_axis] ? 2 : bskip_axis;

                position += bskip_t[bskip_axis] * job.direction;
                position[bskip_axis] = (bskip_intersection[bskip_axis] * 0.01f + skipDelta[bskip_axis]) * 100.0f;
                t_min = bskip_axis;
            }
        }
    }

    if (job.result_hit) {
        lightEmittance = unpackUnorm4x8(cb_array[emission_ptr]).xyz;
    } else {
        lightEmittance = vec3(0f);
    }

    job.result_color = vec3((-entries.z >> 0) & 0xff, (-entries.z >> 8) & 0xff, (-entries.z >> 16) & 0xff) / 0xff;
    job.result_position = job.result_hit ? vec3(position / 16.0f) : (vec3(47823934.0f) - world_offset);

    if (t_min != -1)
        job.result_normal[t_min] = sign(-ray_direction_sign[t_min]);

    ray_target = ivec3(-1);
    ray_ignore_block_id = -1;
    ray_stop_on_target = false;
}

void trace_ray(inout RayJob job) { trace_ray(job, false); }

int get_block_pointer(vec3 position) {
    if (!ph_is_inside(16.0f * position)) {
        return -1;
    }

    ivec3 w = ivec3(floor(position));
    int index = 0;

    index = root_array[ph_get_world_index((w >> 4) & 31)];
    if (index >= 0) return -1;

    int chunk_base = -index;
    index = ph_lookup_chunk_entry(chunk_base, w & 15);
    if (index >= 0) return -1;

    return (-index & 0x1fff) * (ph_byte_size / 4);
}

int get_block_id(vec3 pos) {
    int ptr = get_block_pointer(pos);
    if (ptr == -1) {
        #if defined PH_USE_CUSTOM_AIR_ID
        return PH_AIR_ID;
        #else
        return -1;
        #endif
    }

    return cb_array[ptr];
}

// TODO: calculate normals; normals are always (0, 1, 0) at first iteration
float ph_intersects_world(vec3 direction_inv, vec3 origin) {
    if (ph_is_inside(origin)) {
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

bool ph_is_inside(vec3 position) {
    vec3 s = step(world_min_voxel, position) - step(world_max_voxel, position);
    return bool(s.x * s.y * s.z);
}

int ph_get_index(ivec3 position) {
    return morton[position.x] | (morton[position.y] << 1) | (morton[position.z] << 2);
}

int ph_get_world_index(ivec3 position) {
    return morton[position.x] | (morton[position.y] << 1) | (morton[position.z] << 2);
}

#ifndef PH_CHUNK_LOOKUP_DEFINED
#define PH_CHUNK_LOOKUP_DEFINED

int ph_lookup_chunk_entry(int chunk_base, ivec3 block_position) {
    return cb_array[chunk_base + ph_get_index(block_position & 15)];
}

#endif

int get_result_sky_light(vec3 normal) {
    int index = clamp(
        int(
                abs(normal.x)*(normal.x*0.5+0.5)
                + abs(normal.y)*(normal.y*0.5+2.5)
                + abs(normal.z)*(normal.z*0.5+4.5)
                + 0.5),
        0,
        5
    );

    int level = (ph_result_sky_brightness >> (index * 3)) & 0x7;

    return int((level / 7f) * 15f);
}

vec4 ph_unpack_color(int packedColor) {
    vec3 rgb = vec3(
        (packedColor >> 0) & 0xff,
        (packedColor >> 8) & 0xff,
        (packedColor >> 16) & 0xff
    ) / 255f;

    return vec4(
        rgb,
        // Alpha uses only 7 bits
        (127 - (packedColor >> 24)) / 127f
    );
}

int ph_to_fake_air_entry(ivec3 pos) {
    return ph_to_air_entry_bounds(pos, pos + ivec3(1));
}

float ph_signed_nudge(float value) {
    if (value <= 0f)
    return min(value, -0.0001f);
    else if (value >= 0)
    return max(value, 0.0001);
    else
    return value;
}

vec3 ph_signed_nudge(vec3 value) {
    return vec3(
        ph_signed_nudge(value.x),
        ph_signed_nudge(value.y),
        ph_signed_nudge(value.z)
    );
}

#endif // PH_RAYTRACING
