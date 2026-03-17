//ph_required: uniform int frameCounter, frameTime;
//ph_required: uniform float frameTimeCounter, rainStrength, shadowFade, viewWidth, viewHeight;
//ph_required: uniform sampler2D depthtex0, noisetex;
//ph_required: uniform mat4 gbufferProjectionInverse, gbufferModelViewInverse, shadowProjection, shadowModelView;
//ph_required: uniform vec3 cameraPosition, eyePosition;

#include "/photonics/shader_interface.glsl"

// Debug uniforms for deep isolation
uniform float ph_debug_freeze_rng;
uniform float ph_debug_constant_albedo;
uniform float ph_debug_disable_taa_jitter;

ivec2 tex_coord = ivec2(gl_FragCoord.xy);
// rng_state is initialized with frameCounter; freeze_rng is applied in light_tree_sampling.fsh main()
uint rng_state = uint(uint(gl_FragCoord.x) * uint(1973) + uint(gl_FragCoord.y) * uint(9277) + uint(frameCounter) * uint(26699)) | uint(1);

vec3 albedo = vec3(0f);
vec3 world_pos = vec3(0f);
vec3 rt_pos = vec3(0f);

vec3 block_normal = vec3(0f);
vec3 normal = vec3(0f);
bool bad_angle = false;

#include "/photonics/photonics.glsl"

RayJob ray = RayJob(vec3(0f), vec3(0f), vec3(0f), vec3(0f), vec3(0f), false);

#include "/photonics/common/util.glsl"
