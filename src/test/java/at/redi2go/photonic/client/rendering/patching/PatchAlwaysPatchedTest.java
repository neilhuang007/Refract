package at.redi2go.photonic.client.rendering.patching;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.ShaderPackPath;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PatchAlwaysPatchedTest {
   @TempDir
   Path tempDir;

   @Test
   void patchKeepsOnlyAlwaysPatchedFilesWhenPhotonicsIsDisabled() throws IOException {
      Path patchDir = tempDir.resolve("patches").resolve("TestPack");
      Files.createDirectories(patchDir);

      Photonic.MOD_VERSION = "0.2.9";
      Files.writeString(
         patchDir.resolve("patch.json"),
         """
         {
           "formatVersion": 1,
           "shaderPackNames": [ "TestPack" ],
           "supportedVersions": [ "0.2.9" ],
           "debug": false,
           "alwaysPatched": [ "/always.glsl" ]
         }
         """
      );

      Files.writeString(
         patchDir.resolve("always.patch"),
         """
         #file "/always.glsl"
         #create
         always-content
         """
      );
      Files.writeString(
         patchDir.resolve("optional.patch"),
         """
         #file "/optional.glsl"
         #create
         optional-content
         """
      );

      Patch patch = Patch.of(patchDir, false);
      Path shaderpackRoot = tempDir.resolve("shaderpack");
      Files.createDirectories(shaderpackRoot.resolve("shaders"));

      String alwaysSource = patch.readPatchedFile(new ShaderPackPath(shaderpackRoot.resolve("shaders/always.glsl")));
      String optionalSource = patch.readPatchedFile(new ShaderPackPath(shaderpackRoot.resolve("shaders/optional.glsl")));

      assertNotNull(alwaysSource);
      assertNull(optionalSource);
      assertTrue(patch.files.contains("/shaders/always.glsl"));
      assertFalse(patch.files.contains("/shaders/optional.glsl"));
      assertTrue(patch.canBeApplied("My TestPack Preset", false));
      assertFalse(patch.canBeApplied("My TestPack Preset", true));
   }
}
