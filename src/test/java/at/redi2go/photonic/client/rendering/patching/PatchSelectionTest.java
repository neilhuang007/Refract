package at.redi2go.photonic.client.rendering.patching;

import at.redi2go.photonic.client.Photonic;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PatchSelectionTest {
   @TempDir
   Path tempDir;

   @Test
   void selectBestPatchPrefersLoadedShaderNameOverFirstMatch() throws IOException {
      Patch generic = createPatch("Complementary", List.of("Complementary"), true);
      Patch specific = createPatch("ComplementaryReimagined_r2.0.3", List.of("ComplementaryReimagined"), true);

      Patch selected = Patch.selectBestPatch(List.of(generic, specific), "ComplementaryReimagined_r2.0.3.zip", true);
      assertSame(specific, selected);
   }

   @Test
   void selectBestPatchHandlesSeparatorDifferences() throws IOException {
      Patch specific = createPatch("ComplementaryReimagined_r2.0.3", List.of("ComplementaryReimagined"), true);

      Patch selected = Patch.selectBestPatch(List.of(specific), "Complementary Reimagined r2.0.3.zip", true);
      assertSame(specific, selected);
   }

   @Test
   void selectBestPatchReturnsNullWhenPhotonicsEnabledStateDoesNotMatch() throws IOException {
      Patch enabledPatch = createPatch("ComplementaryReimagined_r2.0.3", List.of("ComplementaryReimagined"), true);

      Patch selected = Patch.selectBestPatch(List.of(enabledPatch), "ComplementaryReimagined_r2.0.3.zip", false);
      assertNull(selected);
   }

   @Test
   void canBeAppliedSupportsZipNames() throws IOException {
      Patch patch = createPatch("ComplementaryReimagined_r2.0.3", List.of("ComplementaryReimagined"), true);
      assertTrue(patch.canBeApplied("ComplementaryReimagined_r2.0.3.zip", true));
   }

   private Patch createPatch(String patchFolder, List<String> shaderPackNames, boolean photonicsEnabled) throws IOException {
      Path patchDir = tempDir.resolve("patches").resolve(patchFolder);
      Files.createDirectories(patchDir);

      Photonic.MOD_VERSION = "0.2.9";
      Files.writeString(
         patchDir.resolve("patch.json"),
         """
         {
           "formatVersion": 1,
           "shaderPackNames": [ "%s" ],
           "supportedVersions": [ "0.2.9" ],
           "debug": false,
           "alwaysPatched": []
         }
         """.formatted(String.join("\", \"", shaderPackNames))
      );
      Files.writeString(
         patchDir.resolve("dummy.patch"),
         """
         #file "/program/dummy.glsl"
         #create
         void main() {}
         """
      );

      return Patch.of(patchDir, photonicsEnabled);
   }
}
