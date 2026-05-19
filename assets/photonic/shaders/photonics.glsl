#ifndef PH_INCLUDE
#define PH_INCLUDE

const int ph_block_size = 16;
const int ph_int_size = 4;
const int ph_schematic_size = ph_int_size * (ph_block_size * ph_block_size * ph_block_size);

const int ph_byte_size =
ph_int_size
+ ph_int_size
+ ph_schematic_size;

const int ph_entry_data_flag = -2147483648;

/*
    -- SSBO --
*/
layout(std430) restrict readonly buffer root_uniform {
    int root_array[32768];
};

layout (std430) restrict readonly buffer cb_block {
    int cb_array[];
};

int ph_decode_data_entry(int entry) {
    return entry & 0x7fffffff;
}

bool ph_is_data_entry(int entry) {
    return (entry & ph_entry_data_flag) != 0;
}


const int light_size = 4; // 4 vec4s per light

// Resolve PH_LIGHTTREE_USES_* feature flags from the calling .fsh's pass
// identity flags. The manifest is idempotent so multiple SSBO sites can
// include it safely.
#include "/photonics/lighttree/lt_buffer_features.glsl"

#ifdef PH_LIGHTTREE_USES_LIGHT_DATA
layout (std140) restrict readonly buffer ph_light_list {
    // vec 1: position (xyz) + block_id (w)
    // vec 2: color (xyz) + intensity (w)
    // vec 3: attenutation (xy) + falloff (z) + block_radius (w)
    // vec 4: emission axis (xyz) + orientation spread (w)
    vec4 ph_lights_array[];
};

layout (std430) restrict readonly buffer ph_light_list_mapping {
    int ph_lights_array_mapping[];
};
#else
// Buffer stubs for passes that don't sample lights. Same names so consumer
// functions (load_light, RTXDI light-id mapping helpers) still compile; those
// functions are not reachable from the reprojection entry point so the stub
// contents are never read at runtime.
const vec4 ph_lights_array[1] = vec4[1](vec4(0.0));
const int  ph_lights_array_mapping[1] = int[1](-1);
#endif

/*
    -- UNIFORM VARIABLES --
*/
uniform bool left_handed;
uniform bool light_reload;
uniform int light_time;
uniform int mask;
uniform int ph_light_count;
uniform mat4 direction_transformation_matrix_in;
uniform vec3 rt_camera_position;
uniform vec3 handheld_color;
uniform vec3 world_max_voxel;
uniform vec3 world_min_voxel;
uniform vec3 world_offset;

// Reprojection must use Iris' real current/previous view state, not a custom Java-side
// snapshot. Our surfaces are stored in absolute world space, while Iris' gbuffer model-view
// transforms operate on camera-relative positions, so we explicitly subtract the matching
// camera position before projection.
mat4 ph_translation_matrix(vec3 delta) {
    return mat4(
        vec4(1.0f, 0.0f, 0.0f, 0.0f),
        vec4(0.0f, 1.0f, 0.0f, 0.0f),
        vec4(0.0f, 0.0f, 1.0f, 0.0f),
        vec4(delta, 1.0f)
    );
}

mat4 ph_modelview_projection_matrix(mat4 projectionMatrix, mat4 modelViewMatrix, vec3 worldCameraPosition) {
    return projectionMatrix * modelViewMatrix * ph_translation_matrix(-worldCameraPosition);
}

mat4 ph_current_modelview_projection() {
    return ph_modelview_projection_matrix(gbufferProjection, gbufferModelView, cameraPosition);
}

mat4 ph_previous_modelview_projection() {
    return ph_modelview_projection_matrix(gbufferPreviousProjection, gbufferPreviousModelView, previousCameraPosition);
}

#define modelview_projection ph_current_modelview_projection()
#define previous_modelview_projection ph_previous_modelview_projection()
#define world_camera_position cameraPosition
#define previous_world_camera_position previousCameraPosition

/*
    -- SAMPLERS/IMAGES --
*/
#ifdef PH_DECLARE_GI_IMAGES
uniform layout(r32ui) uimage3D gi_x;
uniform layout(r32ui) uimage3D gi_y;
uniform layout(r32ui) uimage3D gi_z;
uniform layout(r32ui) uimage3D gi_w;
uniform layout(r32ui) uimage3D gi_d;
#endif

#include "/photonics/ph_samplers.glsl"

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

struct RAB_LightInfo {
    int index;
    int blockId;
    vec3 position;
    vec3 color;
    float intensity;
    vec2 attenuation;
    float falloff;
    float block_radius;
    vec3 emissionAxis;
    float orientationSpread;
};

// Keep the existing helper code readable while exposing the exact RTXDI bridge type.
#define Light RAB_LightInfo

/*
    -- CONSTANTS --
*/
ivec2 ires = textureSize(radiosity_position, 0);
// ivec2 half_res = res / ivec2(2, 1);

#ifdef PH_DECLARE_GI_IMAGES
ivec2 indirect_res = imageSize(gi_x).xy;
#endif
const vec3 NULL = vec3(424242.424242);

#include "ph_core.glsl"

#include "ph_raytracing.glsl"

#endif // PHOTONICS
