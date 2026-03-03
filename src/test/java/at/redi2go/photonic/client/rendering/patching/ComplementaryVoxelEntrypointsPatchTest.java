package at.redi2go.photonic.client.rendering.patching;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

class ComplementaryVoxelEntrypointsPatchTest {
   private static final Path PATCH_ROOT = Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r2.0.3");
   private static final Path SHADERPACK_ROOT = Path.of("run/ComplementaryReimagined_r2.0.3/shaders");
   private static final String[] WORLD_WRAPPERS = {
      "gbuffers_voxels.vsh",
      "gbuffers_voxels.fsh",
      "shadow_voxels.vsh",
      "shadow_voxels.fsh"
   };

   @BeforeAll
   static void requireR2Assets() {
      assumeTrue(Files.exists(PATCH_ROOT), () -> "Missing r2 patch root: " + PATCH_ROOT);
      assumeTrue(Files.exists(SHADERPACK_ROOT), () -> "Missing r2 shaderpack root: " + SHADERPACK_ROOT);
   }

   @Test
   void step05PatchFilesExist() {
      for (String filename : WORLD_WRAPPERS) {
         assertTrue(Files.exists(PATCH_ROOT.resolve(filename)), "Missing world wrapper patch file: " + filename);
      }

      assertTrue(Files.exists(PATCH_ROOT.resolve("gbuffers_voxels.glsl")), "Missing program patch: gbuffers_voxels.glsl");
      assertTrue(Files.exists(PATCH_ROOT.resolve("shadow_voxels.glsl")), "Missing program patch: shadow_voxels.glsl");
   }

   @Test
   void wrappersCoverAllThreeDimensionsExactlyOnce() throws IOException {
      for (String wrapper : WORLD_WRAPPERS) {
         String content = Files.readString(PATCH_ROOT.resolve(wrapper));
         Set<String> referencedPaths = extractQuotedWorldPaths(content);
         Set<String> expectedPaths = Set.of(
            "/world0/" + wrapper,
            "/world1/" + wrapper,
            "/world-1/" + wrapper
         );
         assertEquals(expectedPaths, referencedPaths, "Dimension coverage mismatch for " + wrapper);
      }
   }

   @Test
   void wrapperCreateAndIncludeWiringIsValid() throws IOException {
      String gbufferVsh = Files.readString(PATCH_ROOT.resolve("gbuffers_voxels.vsh"));
      String gbufferFsh = Files.readString(PATCH_ROOT.resolve("gbuffers_voxels.fsh"));
      String shadowVsh = Files.readString(PATCH_ROOT.resolve("shadow_voxels.vsh"));
      String shadowFsh = Files.readString(PATCH_ROOT.resolve("shadow_voxels.fsh"));

      assertTrue(gbufferVsh.contains("#create"));
      assertTrue(gbufferFsh.contains("#create"));
      assertTrue(shadowVsh.contains("#create"));
      assertTrue(shadowFsh.contains("#create"));

      assertTrue(gbufferVsh.contains("#include \"/program/gbuffers_voxels.glsl\""));
      assertTrue(gbufferFsh.contains("#include \"/program/gbuffers_voxels.glsl\""));
      assertTrue(shadowVsh.contains("#include \"/program/shadow_voxels.glsl\""));
      assertTrue(shadowFsh.contains("#include \"/program/shadow_voxels.glsl\""));

      assertTrue(gbufferVsh.contains("#version 130"));
      assertTrue(shadowVsh.contains("#version 130"));
      assertTrue(gbufferFsh.contains("#version 430 compatibility"));
      assertTrue(shadowFsh.contains("#version 430 compatibility"));
   }

   @Test
   void programTemplatesReferenceExistingSourcePrograms() throws IOException {
      String gbufferProgramPatch = Files.readString(PATCH_ROOT.resolve("gbuffers_voxels.glsl"));
      String shadowProgramPatch = Files.readString(PATCH_ROOT.resolve("shadow_voxels.glsl"));

      assertTrue(gbufferProgramPatch.contains("#template \"/program/gbuffers_block.glsl\""));
      assertTrue(shadowProgramPatch.contains("#template \"/program/shadow.glsl\""));

      assertTrue(Files.exists(SHADERPACK_ROOT.resolve("program/gbuffers_block.glsl")));
      assertTrue(Files.exists(SHADERPACK_ROOT.resolve("program/shadow.glsl")));
   }

   @Test
   void edgeCaseVoxelEntrypointsAreActuallyMissingInSourcePack() {
      // Guard against false confidence: these are genuinely new files and require #create / #template.
      assertFalse(Files.exists(SHADERPACK_ROOT.resolve("world0/gbuffers_voxels.vsh")));
      assertFalse(Files.exists(SHADERPACK_ROOT.resolve("world1/gbuffers_voxels.vsh")));
      assertFalse(Files.exists(SHADERPACK_ROOT.resolve("world-1/gbuffers_voxels.vsh")));
      assertFalse(Files.exists(SHADERPACK_ROOT.resolve("world0/shadow_voxels.vsh")));
      assertFalse(Files.exists(SHADERPACK_ROOT.resolve("world1/shadow_voxels.vsh")));
      assertFalse(Files.exists(SHADERPACK_ROOT.resolve("world-1/shadow_voxels.vsh")));
      assertFalse(Files.exists(SHADERPACK_ROOT.resolve("program/gbuffers_voxels.glsl")));
      assertFalse(Files.exists(SHADERPACK_ROOT.resolve("program/shadow_voxels.glsl")));
   }

   private static Set<String> extractQuotedWorldPaths(String content) {
      Matcher matcher = Pattern.compile("\"(/world(?:0|1|-1)/[^\"]+)\"").matcher(content);
      Set<String> values = new HashSet<>();
      while (matcher.find()) {
         values.add(matcher.group(1));
      }
      return values;
   }
}
