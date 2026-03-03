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

class ComplementaryDeferredPatchTest {
   private static final Path PATCH_FILE = Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r2.0.3/deferred1.glsl");
   private static final Path SOURCE_FILE = Path.of("run/ComplementaryReimagined_r2.0.3/shaders/program/deferred1.glsl");

   @BeforeAll
   static void requireR2Assets() {
      assumeTrue(Files.exists(PATCH_FILE), () -> "Missing r2 patch file: " + PATCH_FILE);
      assumeTrue(Files.exists(SOURCE_FILE), () -> "Missing r2 source file: " + SOURCE_FILE);
   }

   @Test
   void deferredPatchTargetsCorrectProgram() throws IOException {
      String patch = Files.readString(PATCH_FILE);
      assertTrue(patch.contains("#file \"/program/deferred1.glsl\""));
   }

   @Test
   void deferredPatchAnchorsExistExactlyOnceInSource() throws IOException {
      String patch = Files.readString(PATCH_FILE);
      String source = Files.readString(SOURCE_FILE);

      for (String anchor : extractReplaceAnchors(patch)) {
         assertTrue(source.contains(anchor), "Missing anchor in source: " + anchor);
         assertEquals(1, countOccurrences(source, anchor), "Anchor must appear once: " + anchor);
      }
   }

   @Test
   void deferredPatchedOutputContainsPhotonicsAdditiveComposition() throws IOException {
      String patched = applyPatch(Files.readString(PATCH_FILE), Files.readString(SOURCE_FILE));

      assertTrue(patched.contains("uniform sampler2D radiosity_handheld;"));
      assertTrue(patched.contains("uniform sampler2D radiosity_direct;"));
      assertTrue(patched.contains("uniform sampler2D radiosity_direct_soft;"));
      assertTrue(patched.contains("uniform sampler2D colortex10;"));
      assertTrue(patched.contains("uniform sampler2D colortex12;"));
      assertTrue(patched.contains("vec4 direct_soft = texelFetch(radiosity_direct_soft, texelCoord, 0);"));
      assertTrue(patched.contains("vec3 rtIndirect = texelFetch(colortex12, texelCoord, 0).rgb * 0.30;"));
      assertTrue(patched.contains("direct_soft.rgb / max(direct_soft.a, 1.0)"));
      assertTrue(patched.contains("if (any(isnan(photonicsLighting)) || any(isinf(photonicsLighting))) {"));
      assertTrue(patched.contains("photonicsLighting = min(photonicsLighting, vec3(5.0));"));
      assertTrue(patched.contains("vec3 photonicsAlbedo = texelFetch(colortex10, texelCoord, 0).rgb;"));
      assertTrue(patched.contains("color += photonicsLighting * photonicsAlbedo * 0.05;"));
   }

   private static String applyPatch(String patchContent, String source) {
      List<String> anchors = extractReplaceAnchors(patchContent);
      List<String> replacements = extractReplaceBlocks(patchContent);
      assertEquals(anchors.size(), replacements.size(), "Anchor/replacement mismatch");

      String result = source;
      for (int i = 0; i < anchors.size(); i++) {
         String before = result;
         result = result.replace(anchors.get(i), replacements.get(i));
         assertNotEquals(before, result, "Replacement did not change source for anchor: " + anchors.get(i));
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
