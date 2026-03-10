#ifndef PH_INCLUDE
#define PH_INCLUDE

const int ph_block_size = 16;
const int ph_int_size = 4;
const int ph_schematic_size = ph_int_size * (ph_block_size * ph_block_size * ph_block_size);

const int ph_byte_size =
ph_int_size
+ ph_int_size
+ ph_schematic_size;

/*
    -- SSBO --
*/
layout(std430) restrict readonly buffer root_uniform {
    int root_array[32768];
};

layout (std430) restrict readonly buffer cb_block {
    int cb_array[];
};

layout (std430) restrict readonly buffer light_registry_block {
    int light_registry_array[];
};


const int light_size = 3; // 3 vec4s per light

layout (std140) uniform lights_uniform {
    // vec 1: position (xyz) + 1 padding (w)
    // vec 2: color (xyz) + 1 padding (w)
    // vec 3: attenutation (xy) + falloff (z) + 1 padding (w)
    vec4 lights_array[PH_MAX_LIGHTS * light_size];
};

/*
    -- UNIFORM VARIABLES --
*/
uniform bool left_handed;
uniform bool light_reload;
uniform int light_time;
uniform int mask;
uniform int ph_light_count;
uniform mat4 direction_transformation_matrix_in;
uniform mat4 modelview_projection; // TODO: just use Iris'
uniform mat4 previous_modelview_projection;
uniform vec3 rt_camera_position;
uniform vec3 handheld_color;
uniform vec3 previous_world_camera_position;
uniform vec3 world_camera_position;
uniform vec3 world_max_voxel;
uniform vec3 world_min_voxel;
uniform vec3 world_offset;

/*
    -- SAMPLERS/IMAGES --
*/
uniform layout(r32ui) uimage3D gi_x;
uniform layout(r32ui) uimage3D gi_y;
uniform layout(r32ui) uimage3D gi_z;
uniform layout(r32ui) uimage3D gi_w;
uniform layout(r32ui) uimage3D gi_d;

uniform sampler2D prev_radiosity_position;
uniform sampler2D prev_radiosity_normal;
uniform sampler2D prev_radiosity_direct;
uniform sampler2D prev_radiosity_direct_soft;
uniform sampler2D prev_radiosity_handheld;

uniform sampler2D radiosity_position;
uniform sampler2D radiosity_normal;
uniform sampler2D radiosity_direct;
uniform sampler2D radiosity_direct_soft;
uniform sampler2D radiosity_handheld;

/*
    -- STRUCTS --
*/
struct RayJob {
    vec3 origin;
    vec3 direction;

    vec3 result_position;
    vec3 result_normal;
    vec3 result_color;
    bool result_hit;
};

struct Light {
    int blockId;
    vec3 position;
    vec3 color;
    float intensity;
    vec2 attenuation;
    float falloff;
    float block_radius;
};

/*
    -- CONSTANTS --
*/
ivec2 ires = textureSize(radiosity_position, 0);
// ivec2 half_res = res / ivec2(2, 1);

ivec2 indirect_res = imageSize(gi_x).xy;
const vec3 NULL = vec3(424242.424242);

#include "ph_core.glsl"
#include "ph_raytracing.glsl"

#endif // PHOTONICS