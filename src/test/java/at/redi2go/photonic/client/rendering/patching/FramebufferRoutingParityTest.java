package at.redi2go.photonic.client.rendering.patching;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class FramebufferRoutingParityTest {
   private static final Path COLOR_FRAMEBUFFER =
      Path.of("src/at/redi2go/photonic/client/rendering/opengl/rendering/ColorFramebuffer.java");
   private static final Path COMPOSITE_RENDERER_MIXIN =
      Path.of("src/at/redi2go/photonic/client/mixin/CompositeRendererMixin.java");
   private static final Path COMPOSITE_RENDERER_PASS_MIXIN =
      Path.of("src/at/redi2go/photonic/client/mixin/CompositeRendererPassMixin.java");

   @Test
   void colorFramebufferUnbindRestoresPreviousDrawFramebufferBinding() throws IOException {
      String source = Files.readString(COLOR_FRAMEBUFFER);

      assertTrue(source.contains("previousDrawFramebuffer"));
      assertTrue(source.contains("GL30.GL_DRAW_FRAMEBUFFER_BINDING"));
      assertTrue(source.contains("GL30.glBindFramebuffer(36160, this.previousDrawFramebuffer);"));
      assertFalse(source.contains("iris$bindFramebuffer"));
      assertFalse(source.contains("getMethod(\"iris$bindFramebuffer\")"));
      assertFalse(source.contains("getFramebuffer().fbo"));
   }

   @Test
   void compositeFramebufferOverrideMatchesDecompilerScope() throws IOException {
      String passMixin = Files.readString(COMPOSITE_RENDERER_PASS_MIXIN);
      String rendererMixin = Files.readString(COMPOSITE_RENDERER_MIXIN);

      assertTrue(passMixin.contains("@Mixin(value = CompositeRenderer.class, remap = false)"));
      assertTrue(passMixin.contains("@Redirect(method = \"renderAll\""));
      assertTrue(passMixin.contains("GlFramebuffer;bind()V"));
      assertFalse(passMixin.contains("setupState"));
      assertTrue(rendererMixin.contains("Raytracer.CURRENT_FRAMEBUFFER.bind();"));
      assertTrue(rendererMixin.contains("Raytracer.CURRENT_FRAMEBUFFER.unbind();"));
   }
}
