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

class ComplementaryGbufferPatchTest {
   private static final Path PATCH_ROOT = Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r2.0.3");
   private static final Path SHADERPACK_ROOT = Path.of("run/ComplementaryReimagined_r2.0.3/shaders");
   private static final String[] ALL_GBUFFERS = {
      "gbuffers_terrain.glsl",
      "gbuffers_block.glsl",
      "gbuffers_entities.glsl",
      "gbuffers_hand.glsl",
      "gbuffers_basic.glsl"
   };
   private static final String[] NON_BASIC_GBUFFERS = {
      "gbuffers_terrain.glsl",
      "gbuffers_block.glsl",
      "gbuffers_entities.glsl",
      "gbuffers_hand.glsl"
   };

   @BeforeAll
   static void requireR2Assets() {
      assumeTrue(Files.exists(PATCH_ROOT), () -> "Missing r2 patch root: " + PATCH_ROOT);
      assumeTrue(Files.exists(SHADERPACK_ROOT), () -> "Missing r2 shaderpack root: " + SHADERPACK_ROOT);
   }

   @Test
   void allPatchFilesExistAndTargetCorrectProgram() throws IOException {
      for (String filename : ALL_GBUFFERS) {
         assertTrue(Files.exists(PATCH_ROOT.resolve(filename)), "Patch file missing: " + filename);
         String patch = Files.readString(PATCH_ROOT.resolve(filename));
         assertTrue(patch.contains("#file \"/program/" + filename + "\""),
            "Patch must target /program/" + filename);
      }
   }

   @Test
   void allReplaceAnchorsExistExactlyOnceInSource() throws IOException {
      for (String filename : ALL_GBUFFERS) {
         String patchContent = Files.readString(PATCH_ROOT.resolve(filename));
         String sourceContent = Files.readString(SHADERPACK_ROOT.resolve("program/" + filename));
         List<String> anchors = extractReplaceAnchors(patchContent);
         assertFalse(anchors.isEmpty(), filename + ": must have at least one #replace");

         for (String anchor : anchors) {
            assertTrue(sourceContent.contains(anchor),
               filename + ": anchor not found in source: \"" + anchor + "\"");
            assertEquals(1, countOccurrences(sourceContent, anchor),
               filename + ": anchor must appear exactly once: \"" + anchor + "\"");
         }
      }
   }

   @Test
   void patchedOutputContainsOldAlbedoAndRenderTargets() throws IOException {
      for (String filename : ALL_GBUFFERS) {
         String patched = applyPatch(filename);
         assertTrue(patched.contains("oldAlbedo"), filename + ": must declare oldAlbedo");
         assertTrue(patched.contains("RENDERTARGETS:"), filename + ": must use RENDERTARGETS");
         assertTrue(patched.contains(",10,11"), filename + ": RENDERTARGETS must include 10,11");
      }
   }

   @Test
   void allDrawbuffersReplacedWithRenderTargets() throws IOException {
      for (String filename : ALL_GBUFFERS) {
         String patched = applyPatch(filename);
         assertFalse(patched.contains("DRAWBUFFERS:"),
            filename + ": all DRAWBUFFERS must be replaced with RENDERTARGETS");
      }
   }

   @Test
   void nonBasicPatchesUseNormalM() throws IOException {
      for (String filename : NON_BASIC_GBUFFERS) {
         String patched = applyPatch(filename);
         assertTrue(patched.contains("0.5 * normalM + 0.5"),
            filename + ": must encode normalM");
      }
   }

   @Test
   void basicPatchUsesNormalNotNormalM() throws IOException {
      String patched = applyPatch("gbuffers_basic.glsl");
      assertTrue(patched.contains("0.5 * normal + 0.5"), "basic: must encode normal");
      assertFalse(patched.contains("normalM"), "basic: must not reference normalM");
   }

   @Test
   void fragDataIndicesDoNotExceedRenderTargetCount() throws IOException {
      for (String filename : ALL_GBUFFERS) {
         String patched = applyPatch(filename);
         Pattern rtPattern = Pattern.compile("/\\* RENDERTARGETS:((?:\\d+,)*\\d+) \\*/");
         Matcher matcher = rtPattern.matcher(patched);

         while (matcher.find()) {
            String targets = matcher.group(1);
            int targetCount = targets.split(",").length;
            int blockEnd = findBlockEnd(patched, matcher.end());
            String block = patched.substring(matcher.end(), blockEnd);

            Pattern fragPattern = Pattern.compile("gl_FragData\\[(\\d+)\\]");
            Matcher fragMatcher = fragPattern.matcher(block);
            int maxIndex = -1;
            while (fragMatcher.find()) {
               int idx = Integer.parseInt(fragMatcher.group(1));
               if (idx > maxIndex) maxIndex = idx;
            }

            if (maxIndex >= 0) {
               assertTrue(maxIndex < targetCount,
                  filename + ": gl_FragData[" + maxIndex + "] exceeds RENDERTARGETS count "
                  + targetCount + " for targets " + targets);
            }
         }
      }
   }

   @Test
   void eachPatchHasAtLeastTwoRenderTargetDirectives() throws IOException {
      for (String filename : ALL_GBUFFERS) {
         String patched = applyPatch(filename);
         int count = countOccurrences(patched, "RENDERTARGETS:");
         assertTrue(count >= 2,
            filename + ": must have >= 2 RENDERTARGETS (base + conditional), found " + count);
      }
   }

   private String applyPatch(String filename) throws IOException {
      String patchContent = Files.readString(PATCH_ROOT.resolve(filename));
      String source = Files.readString(SHADERPACK_ROOT.resolve("program/" + filename));
      List<String> anchors = extractReplaceAnchors(patchContent);
      List<String> replacements = extractReplaceBlocks(patchContent);
      assertEquals(anchors.size(), replacements.size(), "Anchor/replacement count mismatch in " + filename);

      String result = source;
      for (int i = 0; i < anchors.size(); i++) {
         String before = result;
         result = result.replace(anchors.get(i), replacements.get(i));
         assertNotEquals(before, result,
            filename + ": replacement had no effect for anchor: \"" + anchors.get(i) + "\"");
      }
      return result;
   }

   private List<String> extractReplaceAnchors(String patchContent) {
      List<String> anchors = new ArrayList<>();
      Pattern pattern = Pattern.compile("#replace \"(.+?)\"");
      Matcher matcher = pattern.matcher(patchContent);
      while (matcher.find()) {
         anchors.add(matcher.group(1));
      }
      return anchors;
   }

   private List<String> extractReplaceBlocks(String patchContent) {
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
               if (block.endsWith("\n")) block = block.substring(0, block.length() - 1);
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

   private int findBlockEnd(String source, int start) {
      int nextRT = source.indexOf("/* RENDERTARGETS:", start);
      int nextEndif = source.indexOf("#endif", start);
      int nextBrace = source.indexOf("}", start);
      int end = source.length();
      if (nextRT > 0 && nextRT < end) end = nextRT;
      if (nextEndif > 0 && nextEndif < end) end = nextEndif;
      if (nextBrace > 0 && nextBrace < end) end = nextBrace;
      return end;
   }

   private static int countOccurrences(String source, String needle) {
      int count = 0, index = 0;
      while ((index = source.indexOf(needle, index)) >= 0) {
         count++;
         index += needle.length();
      }
      return count;
   }
}
