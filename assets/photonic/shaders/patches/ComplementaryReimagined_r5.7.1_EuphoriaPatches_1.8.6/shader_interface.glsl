#file "/photonics/shader_interface.glsl"

#replace "// HEAD"
#define shadow2D texture
#define texture2D texture

#include "/lib/util/spaceConversion.glsl"
#include "/lib/util/dither.glsl"
#include "/lib/antialiasing/jitter.glsl"

flat in vec3 sunVecWorld;
flat in vec3 sunVec;
flat in vec3 upVec;

float sunVisibilitySaturated = smoothstep(-0.10f, 0.15f, dot(sunVec, upVec));
vec3 lightVecWorld = normalize(sunVecWorld);
#endreplace

#replace "vec3 load_world_position();"
vec3 load_world_position() {
    vec2 texCoord = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    float z0 = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).r;
    #ifdef TAA
        // Debug: bypass TAA jitter when toggle is on
        vec3 screenPos = (ph_debug_disable_taa_jitter > 0.5f)
            ? vec3(texCoord, z0)
            : vec3(TAAJitter(texCoord, -0.5), z0);
    #else
        vec3 screenPos = vec3(texCoord, z0);
    #endif
    vec3 playerPos = ViewToPlayer(ScreenToView(screenPos));
    return playerPos + cameraPosition;
}
#endreplace

#replace "void load_fragment_variables(out vec3 albedo, out vec3 world_pos, out vec3 world_normal, out vec3 world_normal_mapped);"
void load_fragment_variables(out vec3 albedo, out vec3 world_pos, out vec3 world_normal, out vec3 world_normal_mapped) {
    ivec2 texelCoord = ivec2(gl_FragCoord.xy);
    // Debug: use constant gray albedo to isolate g-buffer jitter
    albedo = (ph_debug_constant_albedo > 0.5f)
        ? vec3(0.5f)
        : texelFetch(colortex10, texelCoord, 0).xyz;
    vec3 normalEncoded = 2.0f * texelFetch(colortex11, texelCoord, 0).xyz - 1.0f;
    world_normal = normalize(mat3(gbufferModelViewInverse) * normalEncoded);
    world_normal_mapped = world_normal;
    world_pos = load_world_position() - 0.01f * world_normal;
}
#endreplace

#replace "vec3 sun_direction;"
vec3 sun_direction = normalize(lightVecWorld);
#endreplace

#replace "vec3 indirect_light_color;"
vec3 indirect_light_color = mix(vec3(0.08f, 0.10f, 0.14f), vec3(0.90f, 0.95f, 1.00f), sunVisibilitySaturated)
    * (0.20f + 0.40f * sunVisibilitySaturated);
#endreplace

#replace "vec3 get_sky_color(ivec2 gBufferLoc, vec3 worldPos, vec3 newNormal);"
vec3 get_sky_color(ivec2 gBufferLoc, vec3 worldPos, vec3 newNormal) {
    vec2 texCoord = vec2(gBufferLoc) / vec2(viewWidth, viewHeight);
    vec3 screenPos = vec3(texCoord, texture(depthtex0, texCoord).r);
    vec3 viewDir = normalize(ScreenToView(screenPos));
    vec3 viewNormal = normalize(mat3(transpose(gbufferModelViewInverse)) * newNormal);
    vec3 reflectedDir = reflect(viewDir, viewNormal);
    float horizonFactor = clamp(dot(reflectedDir, upVec) * 0.5f + 0.5f, 0.0f, 1.0f);
    float sunScatter = pow(max(dot(reflectedDir, normalize(lightVecWorld)), 0.0f), 64.0f);
    vec3 skyTop = mix(vec3(0.02f, 0.03f, 0.05f), vec3(0.32f, 0.55f, 0.95f), sunVisibilitySaturated);
    vec3 skyHorizon = mix(vec3(0.01f, 0.02f, 0.04f), vec3(0.58f, 0.65f, 0.78f), sunVisibilitySaturated);
    float dither = Bayer8(gl_FragCoord.xy);

    return mix(skyHorizon, skyTop, pow(horizonFactor, 1.25f)) + vec3(1.1f, 0.95f, 0.8f) * sunScatter + (dither - 0.5f) / 256.0f;
}
#endreplace
