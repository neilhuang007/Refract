package at.redi2go.photonic.client.rendering.patching;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class ComplementaryMainLightingPixelatedPositionPatchTest {
   private static final Path PATCH_FILE = Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r5.7.1_EuphoriaPatches_1.8.6/mainLighting.glsl");

   @Test
   void euphoriaMainLightingExportsPixelatedPositionForPhotonicsCache() throws IOException {
      String patch = Files.readString(PATCH_FILE);

      // Sharp TexelSnap capture (pre-center-bias) is the authoritative position.
      // No late playerPosM capture — center biasing blurs the texel grid.
      assertTrue(patch.contains("ph_pixelated_player_pos = playerPosPixelated;"));
      assertTrue(patch.contains("// Shadow bias without peter-panning //"));
   }
}
