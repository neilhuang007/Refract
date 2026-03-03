package at.redi2go.photonic.client.rendering.patching;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
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

class WaterSurfaceReflectionPatchTest {
   private static final Path EUPHORIA_PATCH_ROOT = Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r5.7.1_EuphoriaPatches_1.8.6");
   private static final Path EUPHORIA_SHADERPACK_ROOT = Path.of("run/shaderpacks/ComplementaryReimagined_r5.7.1 + EuphoriaPatches_1.8.6/shaders");
   private static final Path R2_PATCH_ROOT = Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r2.0.3");

   @BeforeAll
   static void requireAssets() {
      assumeTrue(Files.exists(EUPHORIA_PATCH_ROOT), () -> "Missing Euphoria patch root: " + EUPHORIA_PATCH_ROOT);
      assumeTrue(Files.exists(EUPHORIA_SHADERPACK_ROOT), () -> "Missing Euphoria shaderpack root: " + EUPHORIA_SHADERPACK_ROOT);
   }

   @Test
   void waterPatchFileExistsAndTargetsCorrectProgram() throws IOException {
      Path patchFile = EUPHORIA_PATCH_ROOT.resolve("gbuffers_water.glsl");
      assertTrue(Files.exists(patchFile), "gbuffers_water.glsl patch file must exist for Euphoria");
      String patchContent = Files.readString(patchFile);
      assertTrue(patchContent.contains("#file \"/program/gbuffers_water.glsl\""),
         "Water patch must target /program/gbuffers_water.glsl");
   }

   @Test
   void allWaterPatchAnchorsResolveExactlyOnceInSource() throws IOException {
      String patchContent = Files.readString(EUPHORIA_PATCH_ROOT.resolve("gbuffers_water.glsl"));
      String source = Files.readString(EUPHORIA_SHADERPACK_ROOT.resolve("program/gbuffers_water.glsl"))
         .replace("\r\n", "\n");
      List<String> anchors = extractReplaceAnchors(patchContent);
      assertFalse(anchors.isEmpty(), "Water patch must have at least one #replace anchor");

      for (String anchor : anchors) {
         assertEquals(1, countOccurrences(source, anchor),
            "Anchor must appear exactly once in source: \"" + anchor + "\"");
      }
   }

   @Test
   void patchedWaterContainsOldAlbedoBeforeDoLighting() throws IOException {
      String patchContent = Files.readString(EUPHORIA_PATCH_ROOT.resolve("gbuffers_water.glsl"));
      String source = Files.readString(EUPHORIA_SHADERPACK_ROOT.resolve("program/gbuffers_water.glsl"));
      String patched = applyPatch(patchContent, source);

      assertTrue(patched.contains("oldAlbedo"), "Patched water must declare oldAlbedo");
      int oldAlbedoDecl = patched.indexOf("vec3 oldAlbedo");
      int doLightingCall = patched.indexOf("DoLighting(");
      assertTrue(oldAlbedoDecl >= 0, "oldAlbedo declaration must be present");
      assertTrue(doLightingCall >= 0, "DoLighting call must be present");
      assertTrue(oldAlbedoDecl < doLightingCall, "oldAlbedo must be declared before DoLighting call");

      int assignIndex = patched.indexOf("oldAlbedo = color.rgb");
      assertTrue(assignIndex >= 0, "oldAlbedo = color.rgb assignment must be present");
      assertTrue(assignIndex < doLightingCall, "oldAlbedo must be assigned before DoLighting call");
   }

   @Test
   void patchedWaterHasNoRemainingDrawbuffersDirectives() throws IOException {
      String patchContent = Files.readString(EUPHORIA_PATCH_ROOT.resolve("gbuffers_water.glsl"));
      String source = Files.readString(EUPHORIA_SHADERPACK_ROOT.resolve("program/gbuffers_water.glsl"));
      String patched = applyPatch(patchContent, source);

      assertFalse(patched.contains("DRAWBUFFERS:"),
         "All DRAWBUFFERS directives must be replaced with RENDERTARGETS after patching");
   }

   @Test
   void allRenderTargetDirectivesIncludePhotonicsBuffers() throws IOException {
      String patchContent = Files.readString(EUPHORIA_PATCH_ROOT.resolve("gbuffers_water.glsl"));
      String source = Files.readString(EUPHORIA_SHADERPACK_ROOT.resolve("program/gbuffers_water.glsl"));
      String patched = applyPatch(patchContent, source);

      assertTrue(patched.contains("RENDERTARGETS:"), "Patched water must use RENDERTARGETS directives");

      Pattern rtPattern = Pattern.compile("/\\* RENDERTARGETS:((?:\\d+,)*\\d+) \\*/");
      Matcher matcher = rtPattern.matcher(patched);
      int rtCount = 0;
      while (matcher.find()) {
         rtCount++;
         String targets = matcher.group(1);
         assertTrue(targets.contains(",10") || targets.endsWith(",10"),
            "RENDERTARGETS must include target 10: " + targets);
         assertTrue(targets.contains(",11") || targets.endsWith(",11"),
            "RENDERTARGETS must include target 11: " + targets);
         assertTrue(targets.contains(",10,11"),
            "RENDERTARGETS must include ,10,11: " + targets);
      }
      assertTrue(rtCount > 0, "Must have at least one RENDERTARGETS directive after patching");
   }

   @Test
   void patchedWaterWritesOldAlbedoAndGeoNormalFragData() throws IOException {
      String patchContent = Files.readString(EUPHORIA_PATCH_ROOT.resolve("gbuffers_water.glsl"));
      String source = Files.readString(EUPHORIA_SHADERPACK_ROOT.resolve("program/gbuffers_water.glsl"));
      String patched = applyPatch(patchContent, source);

      assertTrue(patched.contains("vec4(oldAlbedo, 1.0)"),
         "Patched water must write vec4(oldAlbedo, 1.0) to a fragData buffer");
      assertTrue(patched.contains("vec4(0.5 * geoNormal + 0.5, 1.0)"),
         "Patched water must write encoded geoNormal to a fragData buffer");
   }

   @Test
   void fragDataIndicesDoNotExceedRenderTargetCount() throws IOException {
      String patchContent = Files.readString(EUPHORIA_PATCH_ROOT.resolve("gbuffers_water.glsl"));
      String source = Files.readString(EUPHORIA_SHADERPACK_ROOT.resolve("program/gbuffers_water.glsl"));
      String patched = applyPatch(patchContent, source);

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
               "gl_FragData[" + maxIndex + "] exceeds RENDERTARGETS count "
               + targetCount + " for targets " + targets);
         }
      }
   }

   @Test
   void r2PatchDoesNotHaveWaterPatch() {
      assertFalse(Files.exists(R2_PATCH_ROOT.resolve("gbuffers_water.glsl")),
         "r2.0.3 Complementary pack must NOT have a gbuffers_water patch");
   }

   @Test
   void r2PatchJsonDoesNotContainEuphoriaSpecificIdentifiers() throws IOException {
      assumeTrue(Files.exists(R2_PATCH_ROOT.resolve("patch.json")), () -> "Missing r2 patch.json: " + R2_PATCH_ROOT.resolve("patch.json"));
      JsonObject patchJson = JsonParser.parseString(Files.readString(R2_PATCH_ROOT.resolve("patch.json"))).getAsJsonObject();
      JsonArray shaderPackNames = patchJson.getAsJsonArray("shaderPackNames");
      List<String> names = new ArrayList<>();
      shaderPackNames.forEach(entry -> names.add(entry.getAsString()));

      assertFalse(names.stream().anyMatch(name -> name.contains("Euphoria")),
         "r2.0.3 patch.json must not include Euphoria in any shaderPackName");
      assertFalse(names.stream().anyMatch(name -> name.contains("r5.7.1")),
         "r2.0.3 patch.json must not include r5.7.1 in any shaderPackName");
   }

   private static String applyPatch(String patchContent, String source) {
      source = source.replace("\r\n", "\n");
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
      List<String> lines = patchContent.lines().toList();
      for (int i = 0; i < lines.size(); i++) {
         String line = lines.get(i);
         if (line.startsWith("#replace ")) {
            String rest = line.substring("#replace ".length());
            if (rest.startsWith("\"") && rest.endsWith("\"") && rest.length() > 1) {
               anchors.add(rest.substring(1, rest.length() - 1));
            } else if (rest.startsWith("\"")) {
               StringBuilder anchor = new StringBuilder(rest.substring(1));
               for (int j = i + 1; j < lines.size(); j++) {
                  String next = lines.get(j);
                  if (next.endsWith("\"")) {
                     anchor.append("\n").append(next, 0, next.length() - 1);
                     break;
                  } else {
                     anchor.append("\n").append(next);
                  }
               }
               anchors.add(anchor.toString());
            }
         }
      }

      return anchors;
   }

   private static List<String> extractReplaceBlocks(String patchContent) {
      List<String> blocks = new ArrayList<>();
      List<String> lines = patchContent.lines().toList();
      int i = 0;
      while (i < lines.size()) {
         String line = lines.get(i);
         if (line.startsWith("#replace ")) {
            String rest = line.substring("#replace ".length());
            if (rest.startsWith("\"") && rest.endsWith("\"") && rest.length() > 1) {
               i++;
            } else if (rest.startsWith("\"")) {
               i++;
               while (i < lines.size() && !lines.get(i).endsWith("\"")) {
                  i++;
               }
               i++;
            }
            StringBuilder current = new StringBuilder();
            while (i < lines.size() && !lines.get(i).equals("#endreplace")) {
               current.append(lines.get(i)).append("\n");
               i++;
            }
            String block = current.toString();
            if (block.endsWith("\n")) {
               block = block.substring(0, block.length() - 1);
            }
            blocks.add(block);
         }
         i++;
      }

      return blocks;
   }

   private static int findBlockEnd(String source, int start) {
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
      int count = 0;
      int index = 0;
      while ((index = source.indexOf(needle, index)) >= 0) {
         count++;
         index += needle.length();
      }

      return count;
   }
}
