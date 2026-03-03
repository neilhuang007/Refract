package at.redi2go.photonic.client.rendering.patching;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ComplementaryCastLightAntiAliasingPatchTest {
   private static final Path PATCH_ROOT = Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r5.7.1_EuphoriaPatches_1.8.6");
   private static final Path SOURCE_ROOT = Path.of("run/shaderpacks/ComplementaryReimagined_r5.7.1 + EuphoriaPatches_1.8.6/shaders/program");

   @Test
   void composite6PatchSkipsTaaHistoryWhenCastLightIsPixelated() throws IOException {
      String patch = Files.readString(PATCH_ROOT.resolve("composite6.glsl"));
      String patched = applyPatch(patch, Files.readString(SOURCE_ROOT.resolve("composite6.glsl")));

      assertTrue(patch.contains("#file \"/program/composite6.glsl\""));
      assertFalse(patch.contains("ph_mod_cast_light_pixelation_enabled > 0.5 || ph_mod_shadow_pixelation_enabled > 0.5"));
      assertTrue(patch.contains("if (!(ph_mod_shadow_pixelation_enabled > 0.5)"));
      assertFalse(patch.contains("ph_debug_cast_light_value_steps"));
      assertTrue(patched.contains("DoTAA(color, temp, z1);"));
      assertTrue(patched.contains("if (phHasPixelatedCastLight()) {"));
      assertTrue(patched.contains("color = texelFetch(colortex3, texelCoord, 0).rgb;"));
      assertTrue(patched.contains("temp = color;"));
   }

   @Test
   void composite7PatchSkipsFxaaWhenCastLightIsPixelated() throws IOException {
      String patch = Files.readString(PATCH_ROOT.resolve("composite7.glsl"));
      String patched = applyPatch(patch, Files.readString(SOURCE_ROOT.resolve("composite7.glsl")));

      assertTrue(patch.contains("#file \"/program/composite7.glsl\""));
      assertFalse(patch.contains("float phCastSnapSurfaceBlend("));
      assertFalse(patch.contains("ph_mod_cast_light_pixelation_enabled > 0.5 || ph_mod_shadow_pixelation_enabled > 0.5"));
      assertTrue(patch.contains("if (!(ph_mod_shadow_pixelation_enabled > 0.5)"));
      assertFalse(patch.contains("ph_debug_cast_light_value_steps"));
      assertFalse(patch.contains("uniform sampler2D colortex11;"));
      assertTrue(patched.contains("bool phSkipFXAA = phHasPixelatedCastLight();"));
      assertTrue(patched.contains("if (!phSkipFXAA) {"));
      assertTrue(patched.contains("FXAA311(color);"));
   }

   private static String applyPatch(String patchContent, String source) {
      List<String> anchors = extractReplaceAnchors(patchContent);
      List<String> replacements = extractReplaceBlocks(patchContent);
      assertEquals(anchors.size(), replacements.size(), "Anchor/replacement mismatch");

      String result = source.replace("\r\n", "\n");
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
}
