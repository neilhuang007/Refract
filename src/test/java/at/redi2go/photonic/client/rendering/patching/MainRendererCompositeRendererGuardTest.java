package at.redi2go.photonic.client.rendering.patching;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class MainRendererCompositeRendererGuardTest {
   private static final Path MAIN_RENDERER = Path.of("src/at/redi2go/photonic/client/rendering/opengl/rendering/MainRenderer.java");
   private static final Pattern COMPOSITE_RENDERER_GUARD = Pattern.compile("if \\(this\\.compositeRenderer != null\\)");

   @Test
   void compositeRendererLifecycleCallsAreNullGuarded() throws IOException {
      String source = Files.readString(MAIN_RENDERER);
      long guardCount = COMPOSITE_RENDERER_GUARD.matcher(source).results().count();

      assertTrue(guardCount >= 3, "MainRenderer should guard renderAll, destroy, and recalculateSizes against null compositeRenderer");
      assertTrue(source.contains("this.compositeRenderer.renderAll();"));
      assertTrue(source.contains("this.compositeRenderer.destroy();"));
      assertTrue(source.contains("this.compositeRenderer.recalculateSizes();"));
   }
}
