package at.redi2go.photonic.client.rendering.patching;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class RenderDispatcherParityTest {
   private static final Path RENDER_DISPATCHER = Path.of("src/at/redi2go/photonic/client/RenderDispatcher.java");

   @Test
   void renderDispatcherPreservesDecompilerGiRenderScaleAndHandheldLightSource() throws IOException {
      String source = Files.readString(RENDER_DISPATCHER);

      assertTrue(source.contains("return new Vector3f(window.getFramebufferWidth() * renderScale, window.getFramebufferHeight() * renderScale, 2.0F);"));
      assertTrue(source.contains("BlockLightInfo light = PhotonicsConfig.getLightList().getDefault(block);"));
      assertTrue(source.contains("if (light != null) {"));
      assertTrue(source.contains("color.add(light.getColorAsVector());"));
   }
}
