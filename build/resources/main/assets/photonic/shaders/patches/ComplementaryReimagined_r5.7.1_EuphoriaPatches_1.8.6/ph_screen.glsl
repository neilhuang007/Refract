#file "/photonics/ph_screen.glsl"

#replace "#version 430"
#version 430

flat out vec3 sunVecWorld;
flat out vec3 sunVec;
flat out vec3 upVec;

uniform vec3 sunPosition;
uniform vec3 upPosition;
uniform mat4 gbufferModelViewInverse;
#endreplace

#replace "void main() {"
void write_shaderpack_vectors() {
    sunVec = normalize(sunPosition);
    upVec = normalize(upPosition);
    sunVecWorld = normalize(mat3(gbufferModelViewInverse) * sunVec);
}

void main() {
    write_shaderpack_vectors();
#endreplace
