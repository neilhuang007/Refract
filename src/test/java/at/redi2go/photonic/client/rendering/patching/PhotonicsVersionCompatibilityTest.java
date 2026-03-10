package at.redi2go.photonic.client.rendering.patching;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class PhotonicsVersionCompatibilityTest {
   private static final Path GRADLE_PROPERTIES = Path.of("gradle.properties");
   private static final Path SHADER_PACK_MIXIN = Path.of("src/at/redi2go/photonic/client/mixin/ShaderPackMixin.java");

   @Test
   void backportAdvertisesPhotonics301Compatibility() throws IOException {
      String gradleProperties = Files.readString(GRADLE_PROPERTIES);
      String shaderPackMixin = Files.readString(SHADER_PACK_MIXIN);

      assertTrue(gradleProperties.contains("mod_version=0.3.1+1.21.1"));
      assertTrue(shaderPackMixin.contains("SemanticVersion"));
   }
}
