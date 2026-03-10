package at.redi2go.photonic.client.rendering.patching;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.ShaderPackPath;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import static org.junit.jupiter.api.Assertions.assertEquals;

class PatchRecursiveDiscoveryTest {
   @TempDir
   Path tempDir;

   @Test
   void patchLoaderIncludesNestedPatchFiles() throws IOException {
      Path patchRoot = tempDir.resolve("patch");
      Files.createDirectories(patchRoot.resolve("nested/deeper"));
      Files.createDirectories(tempDir.resolve("shaderpack/shaders/program"));

      Photonic.MOD_VERSION = "0.2.10";
      Files.writeString(
         patchRoot.resolve("patch.json"),
         """
         {
           "formatVersion": 1,
           "shaderPackNames": [ "NestedPack" ],
           "supportedVersions": [ "0.2.10" ],
           "debug": false,
           "alwaysPatched": []
         }
         """
      );
      Files.writeString(
         patchRoot.resolve("nested/deeper/custom.patch"),
         """
         #file "/program/example.glsl"
         #create
         // nested patch
         """
      );

      Patch patch = Patch.of(patchRoot, true);
      ShaderPackPath target = new ShaderPackPath(tempDir.resolve("shaderpack/shaders/program/example.glsl"));

      assertEquals("// nested patch\n", patch.readPatchedFile(target));
   }
}
