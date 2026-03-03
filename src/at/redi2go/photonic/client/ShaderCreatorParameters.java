package at.redi2go.photonic.client;

import at.redi2go.photonic.client.rendering.opengl.rendering.ColorFramebuffer;

public record ShaderCreatorParameters(String name, String fragmentName, String vertexName, ColorFramebuffer framebuffer) {
}
