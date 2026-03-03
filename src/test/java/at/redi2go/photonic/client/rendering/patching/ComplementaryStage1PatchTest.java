package at.redi2go.photonic.client.rendering.patching;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import java.util.stream.StreamSupport;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

class ComplementaryStage1PatchTest {
   private static final Path PATCH_ROOT = Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r2.0.3");
   private static final Path SHADERPACK_ROOT = Path.of("run/ComplementaryReimagined_r2.0.3/shaders");

   @BeforeAll
   static void requireR2Assets() {
      assumeTrue(Files.exists(PATCH_ROOT), () -> "Missing r2 patch root: " + PATCH_ROOT);
      assumeTrue(Files.exists(SHADERPACK_ROOT), () -> "Missing r2 shaderpack root: " + SHADERPACK_ROOT);
   }

   @Test
   void patchMetadataUsesAlwaysPatchedPathsCompatibleWithPatchEngine() throws IOException {
      JsonObject patchJson = JsonParser.parseString(Files.readString(PATCH_ROOT.resolve("patch.json"))).getAsJsonObject();

      JsonArray alwaysPatchedArray = patchJson.getAsJsonArray("alwaysPatched");
      Set<String> alwaysPatched = StreamSupport.stream(alwaysPatchedArray.spliterator(), false)
         .map(element -> element.getAsString())
         .collect(Collectors.toSet());
      assertEquals(Set.of("/block.properties", "/shaders.properties", "/lang/en_US.lang"), alwaysPatched);
      assertFalse(alwaysPatched.contains("/shaders/lang/en_US.lang"));

      JsonArray shaderPackNamesArray = patchJson.getAsJsonArray("shaderPackNames");
      Set<String> shaderPackNames = StreamSupport.stream(shaderPackNamesArray.spliterator(), false)
         .map(element -> element.getAsString())
         .collect(Collectors.toSet());
      assertTrue(shaderPackNames.contains("Complementary"));
      assertTrue(shaderPackNames.contains("ComplementaryReimagined"));
      assertTrue(shaderPackNames.stream().noneMatch(name -> name.contains("Euphoria")));
   }

   @Test
   void shadersPropertiesPatchDefinesToggleProperty() throws IOException {
      String source = Files.readString(PATCH_ROOT.resolve("shaders.properties"));

      assertTrue(source.contains("#file \"/shaders.properties\""));
      assertTrue(source.contains("photonics.enabled=true"));
      // PHOTONICS_ENABLED must NOT appear in screen= line because Iris parses the
      // original (unpatched) shaderpack for #define directives to build its option
      // registry. Since PHOTONICS_ENABLED only exists in patched common.glsl, Iris
      // cannot resolve it and the StringElementWidget receives null display text,
      // causing a NullPointerException crash when rendering the shader options screen.
      assertFalse(source.contains("PHOTONICS_ENABLED"));
   }

   @Test
   void languagePatchTargetsLangFileAndDefinesToggleTextExactlyOnce() throws IOException {
      String source = Files.readString(PATCH_ROOT.resolve("en_US.lang"));

      assertTrue(source.contains("#file \"/lang/en_US.lang\""));
      assertEquals(1, count(source, "option.PHOTONICS_ENABLED="));
      assertEquals(1, count(source, "option.PHOTONICS_ENABLED.comment="));
      assertTrue(source.contains("Should Photonics be used in this shaderpack?"));
   }

   @Test
   void stage1ShadersPropertiesPatchAppliesToCurrentShaderpack() throws IOException {
      String patched = applyPatch("shaders.properties", "shaders.properties");

      assertTrue(patched.contains("photonics.enabled=true"));
      assertFalse(patched.contains("screen=<empty> <empty> CMPR SHADER_STYLE <profile> RP_MODE PHOTONICS_ENABLED"),
         "screen= must not reference PHOTONICS_ENABLED, Iris cannot resolve it from patched sources");
   }

   @Test
   void stage1LanguagePatchAppliesToCurrentShaderpack() throws IOException {
      String patched = applyPatch("en_US.lang", "lang/en_US.lang");

      assertEquals(1, count(patched, "option.PHOTONICS_ENABLED="));
      assertEquals(1, count(patched, "option.PHOTONICS_ENABLED.comment="));
   }

   @Test
   void stage1BlockPropertiesPatchRemovesLegacyVariantTokens() throws IOException {
      String patched = applyPatch("block.properties", "block.properties");

      assertFalse(patched.contains("stone_slab:variant=stone_brick "));
      assertFalse(patched.contains("stone:variant=granite "));
      assertFalse(patched.contains("stone:variant=diorite "));
      assertFalse(patched.contains("stone:variant=andesite "));
      assertFalse(patched.contains("stone:variant=smooth_granite "));
      assertFalse(patched.contains("stone:variant=smooth_diorite "));
      assertFalse(patched.contains("stone:variant=smooth_andesite "));
      assertFalse(patched.contains("stone_slab:variant=cobblestone "));
      assertFalse(patched.contains("stone_slab:variant=sandstone "));
      assertFalse(patched.contains("stone_slab:variant=quartz "));
      assertFalse(patched.contains("stone_slab:variant=nether_brick "));
   }

   private static String applyPatch(String patchFileName, String sourceFileRelativePath) throws IOException {
      String patchContent = Files.readString(PATCH_ROOT.resolve(patchFileName));
      String source = Files.readString(SHADERPACK_ROOT.resolve(sourceFileRelativePath));
      List<String> anchors = extractReplaceAnchors(patchContent);
      List<String> replacements = extractReplaceBlocks(patchContent);

      assertEquals(anchors.size(), replacements.size(), "Anchor/replacement count mismatch in " + patchFileName);
      String result = source;
      for (int i = 0; i < anchors.size(); i++) {
         String anchor = anchors.get(i);
         assertEquals(1, count(result, anchor), "Anchor must appear exactly once before patch: " + anchor);
         String before = result;
         result = result.replace(anchor, replacements.get(i));
         assertNotEquals(before, result, "Replacement had no effect for anchor: " + anchor);
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

   private static int count(String source, String needle) {
      int count = 0;
      int index = 0;

      while ((index = source.indexOf(needle, index)) >= 0) {
         count++;
         index += needle.length();
      }

      return count;
   }
}
