layout(location = 0) out vec4 fragColor;
void write_indirect(vec3 color) {
    /* RENDERTARGETS:12 */
    fragColor = vec4(color, 1.0f);
}

