package at.redi2go.photonic.client.rendering.patching;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class MainRendererPixelationDebugLogFormatTest {
   private static final Path MAIN_RENDERER = Path.of("src/at/redi2go/photonic/client/rendering/opengl/rendering/MainRenderer.java");

   @Test
   void pixelationDebugLogIncludesDecodedSurfaceFields() throws IOException {
      String source = Files.readString(MAIN_RENDERER);
      assertTrue(source.contains("String faceLabel = switch (axisIndex)"));
      assertTrue(source.contains("planeFrac=({}, {})"));
      assertTrue(source.contains("blockY={}"));
      assertTrue(source.contains("checker={}"));
      assertTrue(source.contains("face={}"));
   }
}
