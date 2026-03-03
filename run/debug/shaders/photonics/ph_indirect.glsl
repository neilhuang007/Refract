#version 430

//#uniforms

uniform int frameCounter, frameTime;
uniform float frameTimeCounter, rainStrength, shadowFade, viewWidth, viewHeight;
uniform sampler2D colortex6, colortex10, colortex11, depthtex0, noisetex;
uniform mat4 gbufferProjectionInverse, gbufferModelViewInverse, shadowProjection, shadowModelView;
uniform vec3 cameraPosition, eyePosition;

#define FLIP_INDIRECT_INDEX
#include "/photonics/photonics.glsl"
#include "/photonics/shader_interface.glsl"

vec3 base_position = vec3(0.0f);
vec3 base_normal = vec3(0.0f);

void main();
vec3 mixNullable(vec3 s1, vec3 s2, float a);
vec3 loadIndirectRough(vec3 pos);
vec3 fetchInterpolatedLighting(vec3 world_pos);

layout(location = 0) out vec4 fragColor;
void write_indirect(vec3 color) {
    /* RENDERTARGETS:12 */
    fragColor = vec4(color, 1.0f);
}


void main() {
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

    // emittion
    vec3 emittion = vec3(0.0f);
    int pointer = get_block_pointer(base_position - world_offset);
    if (pointer != -1) {
        emittion = unpackUnorm4x8(cb_array[pointer / 4096]).xyz;
    }

    // TODO: enable interpolated light caching
    vec3 indirect_rough = vec3(0.0f);
    vec3 interpolatedLighting = fetchInterpolatedLighting(base_position);
    if (interpolatedLighting != NULL) {
        indirect_rough.xyz = interpolatedLighting;
    }

    float dist = clamp(distance(base_position, world_camera_position) * 0.005, 0.0f, 1.0f);
    indirect_rough *= 1.0f - dist;

    write_indirect(indirect_rough + 0.8f * emittion);
}

vec3 fetchInterpolatedLighting(vec3 world_pos) {
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

    vec3 t00 = loadIndirectRough(center        );
    vec3 t10 = loadIndirectRough(center + u_dir);

    vec3 t01 = loadIndirectRough(center + v_dir);
    vec3 t11 = t01 != NULL && t10 != NULL ? loadIndirectRough(center + u_dir + v_dir) : NULL;

    return mixNullable(
    mixNullable(t00, t10, u),
    mixNullable(t01, t11, u),
    v
    );
}

vec3 loadIndirectRough(vec3 pos) {
    ivec3 read = read(pos, base_normal, modelview_projection, world_camera_position);
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

vec3 mixNullable(vec3 s1, vec3 s2, float a) {
    if (s1 == NULL) {
        a = 1.0f;
    } else if (s2 == NULL) {
        a = 0.0f;
    }

    return mix(s1, s2, a);
}