#version 150

in vec3 Position;
in vec4 Color;
in vec2 UV0;
in ivec2 UV2;
in vec3 Normal;

uniform int RenderIndex;

out vec2 texCoord0;
out vec3 normal;
out vec3 pos;
out vec4 tint;

// TODO: D.R.Y.
void main() {
//    gl_Position = ProjMat * ModelViewMat * vec4(Position + ChunkOffset, 1.0);

    pos = Position * 16.0f - 0.5f * Normal;

    vec2 transformed_position;
    vec3 transformed_normal;
    if (RenderIndex == 0) {
        transformed_position = Position.xy;
        transformed_normal = Normal.xyz;
    } else if (RenderIndex == 1) {
        transformed_position = Position.xz;
        transformed_normal = Normal.xzy;
    } else {
        transformed_position = Position.zy;
        transformed_normal = Normal.zyx;
    }

//    transformed_position = floor(transformed_position * 16.0f) / 16.0f + 0.5f;

    // TODO: 45° is not 0.5, it's cos(45°) ~ 0.71
    // TODO: BUG! Normals are (0,0,0) for minecraft:chest
    if (abs(dot(transformed_normal, vec3(0, 0, 1))) < 0.5f) {
        gl_Position = vec4(-999.0f, -999.0f, -999.0f, 0.0f);
        return;
    }

    gl_Position = vec4(transformed_position.xy * 2.0f - 1.0f, 0.0f, 1.0f);

    texCoord0 = UV0;
    normal = Normal;
    tint = Color;
}
