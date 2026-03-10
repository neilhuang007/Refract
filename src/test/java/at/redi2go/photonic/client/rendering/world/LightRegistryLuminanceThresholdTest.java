package at.redi2go.photonic.client.rendering.world;

import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class LightRegistryLuminanceThresholdTest {
   private static final Path LIGHT_REGISTRY = Path.of("src/at/redi2go/photonic/client/rendering/world/LightRegistry.java");

   @Test
   void nodeCompilationUsesBackportedLuminanceCutoffAlignedWithShaderGate() throws Exception {
      String source = Files.readString(LIGHT_REGISTRY);

      assertTrue(source.contains("private static final float MIN_NODE_LUMINANCE = 0.001F;"));
      assertTrue(source.contains("if (!(luminance < MIN_NODE_LUMINANCE)) {"));
      assertFalse(source.contains("private static final float MIN_NODE_LUMINANCE = 0.00002F;"));
   }

   @Test
   void initLoadsShaderpackNativeLightProvider() throws Exception {
      String source = Files.readString(LIGHT_REGISTRY);

      assertTrue(source.contains("AbsolutePackPath.fromAbsolutePath(\"/ph_lights.json\")"));
      assertTrue(source.contains("ShaderPackLights.parse(contents)"));
      assertTrue(source.contains("PhotonicsConfig.registerLightProvider(lights);"));
   }
}
