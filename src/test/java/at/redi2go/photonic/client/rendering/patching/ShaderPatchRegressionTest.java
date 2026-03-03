package at.redi2go.photonic.client.rendering.patching;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIf;

import static org.junit.jupiter.api.Assertions.assertTrue;

class ShaderPatchRegressionTest {
   private static final Path BSL_DEFERRED_PATCH = Path.of("assets/photonic/shaders/patches/BSL_v8.2.09/deferred1.glsl");
   private static final Path COMPLEMENTARY_PROPERTIES_PATCH =
      Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r5.7.1_EuphoriaPatches_1.8.6/shaders.properties");

   @Test
   void bslDeferredPatchIncludesRadiosityUniforms() throws IOException {
      String patch = Files.readString(BSL_DEFERRED_PATCH);
      assertTrue(patch.contains("uniform sampler2D radiosity_direct;"), "BSL deferred patch should declare radiosity_direct");
      assertTrue(patch.contains("uniform sampler2D colortex10;"), "BSL deferred patch should declare colortex10 (albedo cache)");
      assertTrue(patch.contains("uniform sampler2D colortex12;"), "BSL deferred patch should declare colortex12 (indirect)");
   }

   @Test
   void complementaryPatchDeclaresPhotonicsSupport() throws IOException {
      String patch = Files.readString(COMPLEMENTARY_PROPERTIES_PATCH);
      assertTrue(patch.contains("photonics.supported=true"), "Complementary patch must advertise photonics support");
      assertTrue(patch.contains("photonics.enabled=true"), "Complementary patch should default Photonics to enabled");
   }
}
