package at.redi2go.photonic.client.rendering.patching;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

class ComplementaryAdapterPatchTest {
   private static final Path PATCH_ROOT = Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r2.0.3");
   private static final Path PHOTONIC_SHADER_ROOT = Path.of("assets/photonic/shaders");
   private static final Path COMPLEMENTARY_SHADER_ROOT = Path.of("run/ComplementaryReimagined_r2.0.3/shaders");

   @BeforeAll
   static void requireR2Assets() {
      assumeTrue(Files.exists(PATCH_ROOT), () -> "Missing r2 patch root: " + PATCH_ROOT);
      assumeTrue(Files.exists(COMPLEMENTARY_SHADER_ROOT), () -> "Missing r2 shaderpack root: " + COMPLEMENTARY_SHADER_ROOT);
   }

   @Test
   void adapterPatchFilesExistAndTargetPhotonicsFiles() throws IOException {
      assertPatchHeader("ph_screen.glsl", "#file \"/photonics/ph_screen.glsl\"");
      assertPatchHeader("shader_interface.glsl", "#file \"/photonics/shader_interface.glsl\"");
      assertPatchHeader("ph_indirect.glsl", "#file \"/photonics/write_indirect.glsl\"");
   }

   @Test
   void adapterReplaceAnchorsExistExactlyOnceInBasePhotonicSources() throws IOException {
      assertAnchorsExistExactlyOnce("ph_screen.glsl", "ph_screen.glsl");
      assertAnchorsExistExactlyOnce("shader_interface.glsl", "shader_interface.glsl");
      assertAnchorsExistExactlyOnce("ph_indirect.glsl", "write_indirect.glsl");
   }

   @Test
   void shaderInterfacePatchedOutputProvidesRequiredSymbolsWithComplementaryApis() throws IOException {
      String patched = applyPatch(
         PATCH_ROOT.resolve("shader_interface.glsl"),
         PHOTONIC_SHADER_ROOT.resolve("shader_interface.glsl")
      );

      assertTrue(patched.contains("vec3 load_world_position()"));
      assertTrue(patched.contains("void load_fragment_variables("));
      assertTrue(patched.contains("vec3 sun_direction ="));
      assertTrue(patched.contains("vec3 indirect_light_color ="));
      assertTrue(patched.contains("vec3 get_sky_color("));
      assertTrue(patched.contains("ViewToPlayer(ScreenToView(screenPos))"));
      assertTrue(patched.contains("horizonFactor"));
      assertTrue(patched.contains("sunScatter"));
      assertTrue(patched.contains("flat in vec3 sunVecWorld;"));
      assertTrue(patched.contains("flat in vec3 sunVec;"));
      assertTrue(patched.contains("flat in vec3 upVec;"));

      // Ensure the old placeholder adapter values are gone.
      assertFalse(patched.contains("vec3(0.3f, 1.0f, 0.2f)"));
      assertFalse(patched.contains("return vec3(0.53f, 0.71f, 1.0f)"));
      assertFalse(patched.contains("#include \"/lib/common.glsl\""));
      assertFalse(patched.contains("#include \"/lib/atmospherics/sky.glsl\""));
   }

   @Test
   void phScreenPatchedOutputExportsSunAndUpVectors() throws IOException {
      String patched = applyPatch(
         PATCH_ROOT.resolve("ph_screen.glsl"),
         PHOTONIC_SHADER_ROOT.resolve("ph_screen.glsl")
      );

      assertTrue(patched.contains("flat out vec3 sunVecWorld;"));
      assertTrue(patched.contains("flat out vec3 sunVec;"));
      assertTrue(patched.contains("flat out vec3 upVec;"));
      assertTrue(patched.contains("uniform vec3 sunPosition;"));
      assertTrue(patched.contains("uniform vec3 upPosition;"));
      assertTrue(patched.contains("uniform mat4 gbufferModelViewInverse;"));
      assertTrue(patched.contains("write_shaderpack_vectors();"));
   }

   @Test
   void phIndirectPatchedOutputWritesRenderTarget12() throws IOException {
      String patched = applyPatch(
         PATCH_ROOT.resolve("ph_indirect.glsl"),
         PHOTONIC_SHADER_ROOT.resolve("write_indirect.glsl")
      );

      assertTrue(patched.contains("layout(location = 0) out vec4 fragColor;"));
      assertTrue(patched.contains("/* RENDERTARGETS:12 */"));
      assertTrue(patched.contains("fragColor = vec4(color, 1.0f);"));
   }

   @Test
   void referencedComplementaryIncludesExist() {
      assertTrue(Files.exists(COMPLEMENTARY_SHADER_ROOT.resolve("lib/util/spaceConversion.glsl")));
      assertTrue(Files.exists(COMPLEMENTARY_SHADER_ROOT.resolve("lib/util/dither.glsl")));
   }

   private static void assertPatchHeader(String patchFile, String requiredHeader) throws IOException {
      Path path = PATCH_ROOT.resolve(patchFile);
      assertTrue(Files.exists(path), "Missing patch file: " + patchFile);
      String content = Files.readString(path);
      assertTrue(content.contains(requiredHeader), "Missing #file header in " + patchFile);
   }

   private static void assertAnchorsExistExactlyOnce(String patchFile, String sourceFile) throws IOException {
      String patch = Files.readString(PATCH_ROOT.resolve(patchFile));
      String source = Files.readString(PHOTONIC_SHADER_ROOT.resolve(sourceFile));
      for (String anchor : extractReplaceAnchors(patch)) {
         assertTrue(source.contains(anchor), "Missing anchor in source: " + anchor);
         assertEquals(1, countOccurrences(source, anchor), "Anchor must appear once: " + anchor);
      }
   }

   private static String applyPatch(Path patchFile, Path sourceFile) throws IOException {
      String patch = Files.readString(patchFile);
      String source = Files.readString(sourceFile);
      List<String> anchors = extractReplaceAnchors(patch);
      List<String> replacements = extractReplaceBlocks(patch);
      assertEquals(anchors.size(), replacements.size(), "Anchor/replacement mismatch in " + patchFile);

      String result = source;
      for (int i = 0; i < anchors.size(); i++) {
         String before = result;
         result = result.replace(anchors.get(i), replacements.get(i));
         assertNotEquals(before, result, "Replacement had no effect for anchor: " + anchors.get(i));
      }
      return result;
   }

   private static List<String> extractReplaceAnchors(String patchContent) {
      List<String> anchors = new ArrayList<>();
      Matcher matcher = Pattern.compile("#replace \"(.+?)\"").matcher(patchContent);
      while (matcher.find()) {
         anchors.add(matcher.group(1));
      }
      return anchors;
   }

   private static List<String> extractReplaceBlocks(String patchContent) {
      List<String> blocks = new ArrayList<>();
      boolean inReplace = false;
      StringBuilder current = null;

      for (String line : patchContent.lines().toList()) {
         if (line.startsWith("#replace ")) {
            inReplace = true;
            current = new StringBuilder();
         } else if (line.equals("#endreplace")) {
            if (current != null) {
               String block = current.toString();
               if (block.endsWith("\n")) {
                  block = block.substring(0, block.length() - 1);
               }
               blocks.add(block);
            }
            inReplace = false;
            current = null;
         } else if (inReplace && current != null) {
            current.append(line).append("\n");
         }
      }

      return blocks;
   }

   private static int countOccurrences(String source, String needle) {
      int count = 0;
      int index = 0;
      while ((index = source.indexOf(needle, index)) >= 0) {
         count++;
         index += needle.length();
      }
      return count;
   }
}
