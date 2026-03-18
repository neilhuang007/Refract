//ph_required: uniform int frameCounter, frameTime;
//ph_required: uniform float frameTimeCounter, rainStrength, shadowFade, viewWidth, viewHeight;
//ph_required: uniform sampler2D depthtex0, noisetex;
//ph_required: uniform mat4 gbufferProjectionInverse, gbufferModelViewInverse, shadowProjection, shadowModelView;
//ph_required: uniform vec3 cameraPosition, eyePosition, relativeEyePosition;

#include "/photonics/shader_interface.glsl"

uniform float ph_debug_freeze_rng;
uniform float ph_debug_lock_traversal_rng;
uniform float ph_debug_disable_taa_jitter;

vec3 ph_clamp_indirect_radiance(vec3 value) {
    return clamp(value, vec3(0.0f), vec3(64.0f));
}

ivec2 tex_coord = ivec2(gl_FragCoord.xy);
uint rng_state = uint(uint(gl_FragCoord.x) * uint(1973) + uint(gl_FragCoord.y) * uint(9277) + uint(frameCounter) * uint(26699)) | uint(1);

#include "/photonics/photonics.glsl"

RayJob ray = RayJob(vec3(0f), vec3(0f), vec3(0f), vec3(0f), vec3(0f), false);

vec3 albedo = vec3(0f);
vec3 world_pos = vec3(0f);
vec3 rt_pos = vec3(0f);

vec3 block_normal = vec3(0f);
vec3 normal = vec3(0f);
bool bad_angle = false;
float ray_normal_scale = 0f;
vec3 ray_local_offset = vec3(0f);

#include "/photonics/common/util.glsl"
#include "/photonics/common/impl/is_hand.glsl"
#include "/photonics/common/impl/attenuation.glsl"
