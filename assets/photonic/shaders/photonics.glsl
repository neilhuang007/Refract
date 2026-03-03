#ifndef PHOTONICS
#define PHOTONICS

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

layout(std430) restrict buffer debug_pixelation_block {
    vec4 ph_debug_probe[4];
};

layout (std140) uniform lights_uniform {
    vec4 lights_array[2000];
};

/*
    -- UNIFORM VARIABLES --
*/
uniform bool left_handed;
uniform bool light_reload;
uniform int light_time;
uniform int mask;
uniform mat4 direction_transformation_matrix_in;
uniform mat4 modelview_projection; // TODO: just use Iris'
uniform mat4 previous_modelview_projection;
uniform vec3 camera_position;
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
    vec3 position;
    vec3 color;
    vec2 attenuation;
};

/*
    -- CONSTANTS --
*/
ivec2 res = textureSize(radiosity_position, 0);
// ivec2 half_res = res / ivec2(2, 1);

ivec2 indirect_res = imageSize(gi_x).xy;
const vec3 NULL = vec3(424242.424242);

#include "ph_core.glsl"
#include "ph_raytracing.glsl"

#endif // PHOTONICS
