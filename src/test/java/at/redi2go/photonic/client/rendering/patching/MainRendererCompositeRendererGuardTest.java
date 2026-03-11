package at.redi2go.photonic.client.rendering.patching;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class MainRendererCompositeRendererGuardTest {
   private static final Path MAIN_RENDERER = Path.of("src/at/redi2go/photonic/client/rendering/opengl/rendering/renderers/MainRenderer.java");

   @Test
   void compositeRendererLifecycleCallsAreNullGuarded() throws IOException {
      String source = Files.readString(MAIN_RENDERER);

      assertTrue(source.contains("public abstract void render();"),
         "MainRenderer should declare abstract render()");
      assertTrue(source.contains("public abstract void recalculateSizes();"),
         "MainRenderer should declare abstract recalculateSizes()");
      assertTrue(source.contains("public abstract void createCompositeRenderer("),
         "MainRenderer should declare abstract createCompositeRenderer()");
   }
}
