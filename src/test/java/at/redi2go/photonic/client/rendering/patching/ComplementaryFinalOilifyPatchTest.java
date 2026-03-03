package at.redi2go.photonic.client.rendering.patching;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ComplementaryFinalOilifyPatchTest {
   private static final Path PATCH_FILE =
      Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r5.7.1_EuphoriaPatches_1.8.6/final.glsl");
   private static final Path SOURCE_FILE =
      Path.of("run/shaderpacks/ComplementaryReimagined_r5.7.1 + EuphoriaPatches_1.8.6/shaders/program/final.glsl");

   @Test
   void oilifyPatchInjectsInsaneShaderCompatibleKernel() throws IOException {
      String patch = Files.readString(PATCH_FILE);

      assertTrue(patch.contains("const float PH_GAUSSIAN_WEIGHTS[5] = float[5](0.095766, 0.303053, 0.20236, 0.303053, 0.095766);"));
      assertTrue(patch.contains("uniform float ph_mod_oilify_iterations;"));
      assertTrue(patch.contains("uniform float ph_mod_oilify_depth_scaling;"));
      assertTrue(patch.contains("uniform float ph_mod_oilify_stroke_strength;"));
      assertTrue(patch.contains("vec4 phOilifyKuwahara(sampler2D tex, vec2 texCoord, float sizeParam, vec3 anisotropyData, float adaptiveScale) {"));
      assertTrue(patch.contains("float effectiveSize = clamp(ph_mod_oilify_size + max(floor(ph_mod_oilify_iterations + 0.5) - 1.0, 0.0), 3.0, 15.0);"));
      assertTrue(patch.contains("dFdx(dx)"));
      assertTrue(patch.contains("dFdy(dy)"));
      assertTrue(patch.contains("float oilifyScale = clamp(adaptiveScale, 0.5, 16.0);"));
      assertTrue(patch.contains("float oilifyTuning = clamp(ph_mod_oilify_tuning, 0.0, 4.0);"));
      assertTrue(patch.contains("float tuningA = tuning / (anisotropy + tuning);"));
      assertTrue(patch.contains("float tuningB = (tuning + anisotropy) / tuning;"));
      assertTrue(patch.contains("vec2 rotatedOffset = vec2(offset.x * t.x + offset.y * t.y, offset.x * -t.y + offset.y * t.x);"));
      assertTrue(patch.contains("float sharpnessMultiplier = max(1023.0 * pow((2.0 * oilifySharpness / 3.0) + 0.333333, 4.0), 1e-10);"));
      assertTrue(patch.contains("if (ph_mod_oilify_enabled > 0.5) {"));
      assertTrue(patch.contains("depthtex0"), "Depth texture access must exist for adaptive scaling");
      assertTrue(patch.contains("GetLinearDepth"), "Linear depth function must be used");
      assertTrue(patch.contains("strokeStr"), "Stroke strength logic must exist");
   }

   @Test
   void oilifyPatchRunsAfterFinalColorButBeforeDithering() throws IOException {
      String patched = applyPatch(Files.readString(PATCH_FILE), Files.readString(SOURCE_FILE));

      int colorBaseIdx = patched.indexOf("color = textureFinal(colortex3);");
      int oilifyIdx = patched.indexOf("if (ph_mod_oilify_enabled > 0.5) {");
      int ditherIdx = patched.indexOf("#ifdef SCREEN_DITHERING_INTERNAL");
      int drawBuffersIdx = patched.indexOf("/* DRAWBUFFERS:0 */");

      assertTrue(colorBaseIdx >= 0, "Base final color assignment must exist");
      assertTrue(oilifyIdx > colorBaseIdx, "Oilify must run after final base color is resolved");
      assertTrue(ditherIdx > 0 && ditherIdx < oilifyIdx, "Oilify must execute after screen dithering in final pass");
      assertTrue(drawBuffersIdx > oilifyIdx, "Oilify must execute at the very end before final write");
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
                  }
                  anchor.append("\n").append(next);
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
}
