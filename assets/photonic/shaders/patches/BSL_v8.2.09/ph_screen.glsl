#file "/photonics/ph_screen.glsl"

#replace "#version 430"
#version 430

flat out vec3 sunVecWorld;
flat out vec3 sunVec;
flat out vec3 upVec;

uniform mat4 gbufferModelView;
uniform float timeAngle;

#include "/lib/settings.glsl"
#endreplace

#replace "void main() {"
vec3 get_sun_vec() {
    const vec2 sunRotationData = vec2(cos(sunPathRotation * 0.01745329251994), -sin(sunPathRotation * 0.01745329251994));
    float ang = fract(timeAngle - 0.25);
    ang = (ang + (cos(ang * 3.14159265358979) * -0.5 + 0.5 - ang) / 3.0) * 6.28318530717959;

    return normalize(vec3(-sin(ang), cos(ang) * sunRotationData) * 2000.0);
}

void writeShaderpack() {
    sunVecWorld = get_sun_vec();
    sunVec = normalize((gbufferModelView * vec4(sunVecWorld, 1.0f)).xyz);

    upVec = normalize(gbufferModelView[1].xyz);
}

void main() {
writeShaderpack();
#endreplace