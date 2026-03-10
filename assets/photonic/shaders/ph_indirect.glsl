#version 430

//#uniforms

//ph_required: uniform int frameCounter, frameTime;
//ph_required: uniform float frameTimeCounter, rainStrength, shadowFade, viewWidth, viewHeight;
//ph_required: uniform sampler2D depthtex0, noisetex;
//ph_required: uniform mat4 gbufferProjectionInverse, gbufferModelViewInverse, shadowProjection, shadowModelView;
//ph_required: uniform vec3 cameraPosition, eyePosition;

#define FLIP_INDIRECT_INDEX
#include "/photonics/shader_interface.glsl"
#include "/photonics/write_indirect.glsl"
#include "/photonics/photonics.glsl"

vec3 base_position = vec3(0.0f);
vec3 base_normal = vec3(0.0f);

//#forward

void main() {
    /* RENDERTARGETS:12 */
    ivec3 write = ivec3(gl_FragCoord.xy, indirect_write_index);
    imageStore(gi_x, write, uvec4(0));
    imageStore(gi_y, write, uvec4(0));
    imageStore(gi_z, write, uvec4(0));
    imageStore(gi_w, write, uvec4(0));
    imageStore(gi_d, write, uvec4(0));

    if (texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).x > 0.99999f) {
        return;
    }

    vec3 albedo = vec3(0.0f);
    vec3 mapped_normal = vec3(0.0f);
    load_fragment_variables(albedo, base_position, base_normal, mapped_normal);

    vec3 emission = vec3(0.0f);
    int pointer = get_block_pointer(base_position - world_offset);
    if (pointer != -1) {
        // blockId, emission, <schematic data>
        emission = unpackUnorm4x8(cb_array[pointer + 1]).xyz;
    }

    // TODO: enable interpolated light caching
    vec3 indirect_rough = vec3(0.0f);

    #ifdef PH_ENABLE_GI
    vec3 interpolatedLighting = ph_fetchInterpolatedLighting(base_position);
    if (interpolatedLighting != NULL) {
        indirect_rough.xyz = interpolatedLighting;
    }
    #endif

    float dist = clamp(distance(base_position, world_camera_position) * 0.005, 0.0f, 1.0f);
    indirect_rough *= 1.0f - dist;

    write_indirect(indirect_rough + 0.8f * emission);
}

vec3 ph_fetchInterpolatedLighting(vec3 world_pos) {
    world_pos *= 2.0f;

    vec3 center = floor(world_pos) + 0.5f + 0.49f * base_normal;
    vec3 center_delta = (world_pos - center);

    // TODO: better utilize vector arithmetic
    vec3 abs_normal = abs(base_normal);
    int t_index = int(abs_normal.y > abs_normal.x);
    t_index = abs_normal[t_index] > abs_normal.z ? t_index : 2;

    vec3 u_dir = vec3(0.0f);
    u_dir[(t_index + 1) % 3] = 1.0f;
    float u = dot(center_delta, u_dir);
    u_dir *= sign(u);
    u = abs(u);

    vec3 v_dir = vec3(0.0f);
    v_dir[(t_index + 2) % 3] = 1.0f;
    float v = dot(center_delta, v_dir);
    v_dir *= sign(v);
    v = abs(v);

    center /= 2.0f;
    u_dir /= 2.0f;
    v_dir /= 2.0f;

    vec3 t00 = ph_loadIndirectRough(center        );
    vec3 t10 = ph_loadIndirectRough(center + u_dir);

    vec3 t01 = ph_loadIndirectRough(center + v_dir);
    vec3 t11 = t01 != NULL && t10 != NULL ? ph_loadIndirectRough(center + u_dir + v_dir) : NULL;

    return ph_mixNullable(
    ph_mixNullable(t00, t10, u),
    ph_mixNullable(t01, t11, u),
    v
    );
}

vec3 ph_loadIndirectRough(vec3 pos) {
    ivec3 read = ph_read(pos, base_normal, modelview_projection, world_camera_position);
    vec3 indirect_voxel = vec3(0.0f);
    float w = imageLoad(gi_w, read).x;
    if (w <= 10.0f) {
        return NULL;
    }

    indirect_voxel.x = imageLoad(gi_x, read).x;
    indirect_voxel.y = imageLoad(gi_y, read).x;
    indirect_voxel.z = imageLoad(gi_z, read).x;
    indirect_voxel /= 255.0f * w;

    return indirect_voxel.xyz;
}

vec3 ph_mixNullable(vec3 s1, vec3 s2, float a) {
    if (s1 == NULL) {
        a = 1.0f;
    } else if (s2 == NULL) {
        a = 0.0f;
    }

    return mix(s1, s2, a);
}