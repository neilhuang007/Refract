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
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ComplementaryEuphoriaPatchCompatibilityTest {
   private static final Path PATCH_ROOT = Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r5.7.1_EuphoriaPatches_1.8.6");
   private static final Path SHADERPACK_ROOT = Path.of("run/shaderpacks/ComplementaryReimagined_r5.7.1 + EuphoriaPatches_1.8.6/shaders");
   private static final Path PHOTONIC_SHADER_ROOT = Path.of("assets/photonic/shaders");
   private static final String[] GBUFFER_PATCHES = {
      "gbuffers_basic.glsl",
      "gbuffers_block.glsl",
      "gbuffers_entities.glsl",
      "gbuffers_hand.glsl",
      "gbuffers_terrain.glsl"
   };
   private static final String[] GBUFFER_PATCHES_WITH_GEONORMAL = {
      "gbuffers_block.glsl",
      "gbuffers_terrain.glsl"
   };
   private static final String[] GBUFFER_PATCHES_WITH_NORMALM = {
      "gbuffers_entities.glsl",
      "gbuffers_hand.glsl"
   };

   @Test
   void patchMetadataTargetsEuphoriaVariant() throws IOException {
      JsonObject patchJson = JsonParser.parseString(Files.readString(PATCH_ROOT.resolve("patch.json"))).getAsJsonObject();
      JsonArray shaderPackNames = patchJson.getAsJsonArray("shaderPackNames");
      List<String> names = new ArrayList<>();
      shaderPackNames.forEach(entry -> names.add(entry.getAsString()));

      assertTrue(names.stream().anyMatch(name -> name.contains("r5.7.1")));
      assertTrue(names.stream().anyMatch(name -> name.contains("Euphoria")));
      assertTrue(names.stream().noneMatch(name -> name.equals("Complementary")));
      assertTrue(names.stream().noneMatch(name -> name.equals("ComplementaryReimagined")));
   }

   @Test
   void allAnchorsResolveAgainstCurrentSources() throws IOException {
      try (var files = Files.list(PATCH_ROOT)) {
         for (Path patchFile : files.filter(Files::isRegularFile).toList()) {
            if ("patch.json".equals(patchFile.getFileName().toString())) {
               continue;
            }

            String patchContent = Files.readString(patchFile);
            List<String> targets = parseTargets(patchContent);
            List<String> anchors = extractReplaceAnchors(patchContent);
            List<String> replacements = extractReplaceBlocks(patchContent);

            assertEquals(anchors.size(), replacements.size(), "Anchor/replacement mismatch in " + patchFile.getFileName());

            boolean createPatch = patchContent.contains("#create");
            boolean templatePatch = patchContent.contains("#template");
            for (String target : targets) {
               Path sourcePath = resolveSourcePath(target);
               if (!Files.exists(sourcePath)) {
                  assertTrue(
                     createPatch || templatePatch,
                     "Missing source target without #create/#template for " + patchFile.getFileName() + ": " + target
                  );
                  continue;
               }

               String source = Files.readString(sourcePath).replace("\r\n", "\n");
               String patched = source;
               for (int i = 0; i < anchors.size(); i++) {
                  String anchor = anchors.get(i);
                  String replacement = replacements.get(i);
                  assertEquals(1, countOccurrences(patched, anchor), patchFile.getFileName() + " anchor must appear once: " + anchor);
                  String before = patched;
                  patched = patched.replace(anchor, replacement);
                  if (!anchor.equals(replacement)) {
                     assertNotEquals(before, patched, patchFile.getFileName() + " replacement had no effect for anchor: " + anchor);
                  }
               }
            }
         }
      }
   }

   @Test
   void patchedGbuffersExposePhotonicsTargets() throws IOException {
      for (String patchName : GBUFFER_PATCHES) {
         String patchContent = Files.readString(PATCH_ROOT.resolve(patchName));
         String source = Files.readString(SHADERPACK_ROOT.resolve("program").resolve(patchName));
         String patched = applyPatch(patchContent, source);

         assertTrue(patched.contains("oldAlbedo"), patchName + " should cache old albedo");
         assertTrue(patched.contains("RENDERTARGETS:"), patchName + " should switch to RENDERTARGETS directives");
         assertTrue(patched.contains(",10,11"), patchName + " should write photonics cache targets 10 and 11");
         assertFalse(patched.contains("/* DRAWBUFFERS:06 */"), patchName + " should not keep primary DRAWBUFFERS line");
      }
   }

   @Test
   void patchedGbuffersEncodeGeometricNormalForPhotonicsCache() throws IOException {
      for (String patchName : GBUFFER_PATCHES_WITH_GEONORMAL) {
         String patchContent = Files.readString(PATCH_ROOT.resolve(patchName));
         String source = Files.readString(SHADERPACK_ROOT.resolve("program").resolve(patchName));
         String patched = applyPatch(patchContent, source);

         assertTrue(
            patched.contains("0.5 * geoNormal + 0.5"),
            patchName + " should cache geoNormal encoding to reduce normal-map leakage into RT traces"
         );
      }
   }

   @Test
   void alphaDrivenGbuffersKeepNormalMCacheToAvoidScopeBreakage() throws IOException {
      for (String patchName : GBUFFER_PATCHES_WITH_NORMALM) {
         String patchContent = Files.readString(PATCH_ROOT.resolve(patchName));
         String source = Files.readString(SHADERPACK_ROOT.resolve("program").resolve(patchName));
         String patched = applyPatch(patchContent, source);

         assertTrue(
            patched.contains("0.5 * normalM + 0.5"),
            patchName + " should use normalM cache encoding because geoNormal can be alpha-scope local"
         );
         assertFalse(
            patched.contains("0.5 * geoNormal + 0.5"),
            patchName + " must not reference geoNormal in cached output paths"
         );
      }
   }

   @Test
   void deferredLightingUsesUnlitAlbedoCacheForRtContribution() throws IOException {
      String patchContent = Files.readString(PATCH_ROOT.resolve("deferred1.glsl"));
      String source = Files.readString(SHADERPACK_ROOT.resolve("program").resolve("deferred1.glsl"));
      String patched = applyPatch(patchContent, source);

      assertTrue(patched.contains("uniform sampler2D colortex10;"));
      assertFalse(patched.contains("uniform sampler2D colortex11;"));
      assertFalse(patched.contains("uniform float ph_mod_shadow_pixelation_enabled;"));
      assertFalse(patched.contains("uniform float ph_mod_cast_light_pixel_size;"));
      assertFalse(patched.contains("uniform float ph_mod_shadow_pixelation_size;"));
      assertFalse(patched.contains("uniform float ph_mod_shadow_pixel_size_rt;"));
      assertFalse(patched.contains("phQuantizeCastLight("));
      assertFalse(patched.contains("ivec2 snapTexelCoord = phSnapTexelCoord(texelCoord, vec2(textureSize(radiosity_direct, 0)), shadowPixelSize);"));
      assertFalse(patched.contains("float surfaceWeight = phSurfaceContinuityWeight(texelCoord, snapTexelCoord, centerNormal, centerLinearDepth);"));
      assertFalse(patched.contains("float topSurfaceWeight = phTopSurfaceSnapWeight(texelCoord, shadowPixelSize, centerNormal);"));
      assertFalse(patched.contains("float topDepthWeight = phTopSurfaceDepthWeight(snapTexelCoord, centerNormal, centerLinearDepth);"));
      assertFalse(patched.contains("float faceInteriorWeight = phFaceInteriorSnapWeight(texelCoord, shadowPixelSize, centerNormal);"));
      assertFalse(patched.contains("snapWeight *= topSurfaceWeight * topDepthWeight;"));
      assertFalse(patched.contains("snapWeight *= faceInteriorWeight;"));
      assertFalse(patched.contains("float snapWeight = edgeWeight * surfaceWeight * topDepthWeight;"));
      assertTrue(patched.contains("// Upstream shadow pixelation already applied in ph_lighting.glsl."));
      assertTrue(patched.contains("pixelatedDirect = baseDirect;"));
   }

   private static Path resolveSourcePath(String target) {
      if (target.startsWith("/photonics/")) {
         return PHOTONIC_SHADER_ROOT.resolve(target.substring("/photonics/".length()));
      }

      return SHADERPACK_ROOT.resolve(target.substring(1));
   }

   private static List<String> parseTargets(String patchContent) {
      Matcher fileLineMatcher = Pattern.compile("(?m)^#file\\s+(.+)$").matcher(patchContent);
      assertTrue(fileLineMatcher.find(), "Missing #file line");

      Matcher pathMatcher = Pattern.compile("\"([^\"]+)\"").matcher(fileLineMatcher.group(1));
      List<String> targets = new ArrayList<>();
      while (pathMatcher.find()) {
         targets.add(pathMatcher.group(1));
      }

      assertFalse(targets.isEmpty(), "No #file targets parsed");
      return targets;
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
