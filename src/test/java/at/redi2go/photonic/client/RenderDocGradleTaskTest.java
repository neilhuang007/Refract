package at.redi2go.photonic.client;

import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class RenderDocGradleTaskTest {
   private static final Path BUILD_GRADLE = Path.of("build.gradle");
   private static final Path RENDERDOC_SCRIPT = Path.of("scripts/renderdoc-launch.ps1");

   @Test
   void buildGradleExposesRenderDocShaderGameTestTask() throws Exception {
      String source = Files.readString(BUILD_GRADLE);
      String script = Files.readString(RENDERDOC_SCRIPT);

      assertTrue(source.contains("tasks.register(\"renderdocShaderGameTest\", Exec)"));
      assertTrue(source.contains("dependsOn \"classes\", \"configureClientLaunch\""));
      assertTrue(source.contains("scripts/renderdoc-launch.ps1"));
      assertTrue(source.contains("-Target\", \"ShaderGameTestClient"));
      assertTrue(source.contains("-Launch"));
      assertTrue(script.contains("renderdoccmd.exe"));
      assertTrue(script.contains("capture"));
   }
}
