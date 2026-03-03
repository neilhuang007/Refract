#version 430
flat out vec3 sunVecWorld;
flat out vec3 sunVec;
flat out vec3 upVec;
uniform vec3 sunPosition;
uniform vec3 upPosition;
uniform mat4 gbufferModelViewInverse;


layout(location = 0) in vec3 position;

uniform mat4 direction_transformation_matrix_in;

out vec4 direction_vert_out;

void write_shaderpack_vectors() {
    sunVec = normalize(sunPosition);
    upVec = normalize(upPosition);
    sunVecWorld = normalize(mat3(gbufferModelViewInverse) * sunVec);
}
void main() {
    write_shaderpack_vectors();

    gl_Position = vec4(2.0f * position - 1.0f, 1.0f);

    // vertex_coord_in.z is -1; normally it is 1
    direction_vert_out = direction_transformation_matrix_in * vec4(2.0f * position - 1.0f, 1.0f);
    direction_vert_out.w = 1.0f / direction_vert_out.w;
    direction_vert_out.xyz *= direction_vert_out.w;

    direction_vert_out.xyz = normalize(direction_vert_out.xyz);
}
