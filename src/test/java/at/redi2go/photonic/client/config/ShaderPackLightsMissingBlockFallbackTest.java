package at.redi2go.photonic.client.config;

import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ShaderPackLightsMissingBlockFallbackTest {
   private static final Path SHADER_PACK_LIGHTS = Path.of("src/at/redi2go/photonic/client/config/ShaderPackLights.java");

   @Test
   void missingShaderpackBlockIdsDoNotFallBackToAir() throws Exception {
      String source = Files.readString(SHADER_PACK_LIGHTS);

      assertTrue(source.contains("Registries.BLOCK.getOrEmpty(id).ifPresent"));
      assertFalse(source.contains("Block resolved = Registries.BLOCK.get(id);"));
   }
}
