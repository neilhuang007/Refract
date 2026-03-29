#version 430

const int[32] morton = int[32](0x0,    0x1,    0x8,    0x9,
                               0x40,   0x41,   0x48,   0x49,
                               0x200,  0x201,  0x208,  0x209,
                               0x240,  0x241,  0x248,  0x249,
                               0x1000, 0x1001, 0x1008, 0x1009,
                               0x1040, 0x1041, 0x1048, 0x1049,
                               0x1200, 0x1201, 0x1208, 0x1209,
                               0x1240, 0x1241, 0x1248, 0x1249);

layout (std430) buffer world_array_block {
    int world_array[];
};

uniform sampler2D Sampler0;

uniform int RenderIndex;

in vec2 texCoord0;
in vec3 normal;
in vec3 pos;
in vec4 tint;

out vec4 fragColor;

int get_index(ivec3 position) {
    return morton[position.x] | (morton[position.y] << 1) | (morton[position.z] << 2);
}

void main() {
    vec4 color = texture(Sampler0, texCoord0);
    if (color.a < 0.0078125) {
        discard;
    }

    color.xyz *= tint.xyz;

//    if (color.x == color.y && color.x == color.z) {
//        color.xyz *= tint;
//    }

//    color.xyz = vec3(1.0f, 0.0f, 0.0f);

    ivec3 icolor = ivec3(color * 0xff);
    icolor = max(icolor, ivec3(1, 1, 1));

    // Use 7 bits to store alpha and round to the nearest representable value so
    // nearly-opaque texels do not lose the voxel to a brighter translucent layer.
    int alpha = min(int(color.a * 127.0 + 0.5), 127);
    if (alpha >= 126) {
        alpha = 127;
    }

    // Use atomic max so the result is not dependent on vertex order.
    // The build-time packing is intentionally different from the runtime format:
    // store opacity in the most significant bits so opaque wall fragments win the
    // per-voxel selection before the CPU repacks the word into the tracer format.
    atomicMax(
        world_array[get_index(clamp(ivec3(pos), ivec3(0), ivec3(15)))],
        (alpha << 24) | (icolor.x << 16) | (icolor.y << 8) | icolor.z
    );

    discard;
}
