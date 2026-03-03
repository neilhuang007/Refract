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
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

class ComplementaryEnergyRebalancePatchTest {
   private static final Path PATCH_FILE = Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r2.0.3/mainLighting.glsl");
   private static final Path SOURCE_FILE = Path.of("run/ComplementaryReimagined_r2.0.3/shaders/lib/lighting/mainLighting.glsl");

   @BeforeAll
   static void requireR2Assets() {
      assumeTrue(Files.exists(PATCH_FILE), () -> "Missing r2 patch file: " + PATCH_FILE);
      assumeTrue(Files.exists(SOURCE_FILE), () -> "Missing r2 source file: " + SOURCE_FILE);
   }

   @Test
   void patchTargetsMainLighting() throws IOException {
      String patch = Files.readString(PATCH_FILE);
      assertTrue(patch.contains("#file \"/lib/lighting/mainLighting.glsl\""));
   }

   @Test
   void anchorsExistExactlyOnceInSource() throws IOException {
      String patch = Files.readString(PATCH_FILE);
      String source = Files.readString(SOURCE_FILE);

      for (String anchor : extractReplaceAnchors(patch)) {
         assertTrue(source.contains(anchor), "Missing anchor in source: " + anchor);
         assertEquals(1, countOccurrences(source, anchor), "Anchor must appear once: " + anchor);
      }
   }

   @Test
   void patchedOutputUsesGuardedConservativeAttenuation() throws IOException {
      String patched = applyPatch(Files.readString(PATCH_FILE), Files.readString(SOURCE_FILE));

      assertTrue(patched.contains("vec3 blockLighting = lightmapXM * blocklightCol;"));
      assertTrue(patched.contains("vec3 sceneLighting = shadowLighting * shadowMult + ambientColor * ambientMult;"));
      assertTrue(patched.contains("#ifdef PHOTONICS_ENABLED"));
      assertTrue(patched.contains("blockLighting = vec3(0.0);"));
      assertTrue(patched.contains("ambientColor * ambientMult * 0.6"));
      assertTrue(countOccurrences(patched, "#ifdef PHOTONICS_ENABLED") >= 2, "Expected guard on both lighting changes");
   }

   private static String applyPatch(String patchContent, String source) {
      List<String> anchors = extractReplaceAnchors(patchContent);
      List<String> replacements = extractReplaceBlocks(patchContent);
      assertEquals(anchors.size(), replacements.size(), "Anchor/replacement mismatch");

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
