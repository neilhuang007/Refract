package at.redi2go.photonic.client.rendering.patching;

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
import static org.junit.jupiter.api.Assumptions.assumeTrue;

class ComplementaryCastLightPixelizationPatchTest {
   private static final Path R2_PATCH = Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r2.0.3/deferred1.glsl");
   private static final Path R2_SOURCE = Path.of("run/ComplementaryReimagined_r2.0.3/shaders/program/deferred1.glsl");
   private static final Path R2_PROPERTIES = Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r2.0.3/shaders.properties");
   private static final Path EUPHORIA_PATCH = Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r5.7.1_EuphoriaPatches_1.8.6/deferred1.glsl");
   private static final Path EUPHORIA_SOURCE = Path.of("run/shaderpacks/ComplementaryReimagined_r5.7.1 + EuphoriaPatches_1.8.6/shaders/program/deferred1.glsl");
   private static final Path EUPHORIA_PROPERTIES =
      Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r5.7.1_EuphoriaPatches_1.8.6/shaders.properties");

   @Test
   void r2PatchDeclaresCastLightPixelizationControls() throws IOException {
      assumeTrue(Files.exists(R2_PATCH), () -> "Missing r2 patch file: " + R2_PATCH);
      String patch = Files.readString(R2_PATCH);

      assertTrue(patch.contains("uniform sampler2D colortex11;"));
      assertTrue(patch.contains("uniform float ph_debug_cast_light_pixel_size;"));
      assertTrue(patch.contains("uniform float ph_mod_cast_light_pixel_size;"));
      assertFalse(patch.contains("uniform float ph_debug_cast_light_value_steps;"));
      assertTrue(patch.contains("uniform float ph_debug_cast_light_threshold;"));
      assertFalse(patch.contains("uniform float ph_mod_cast_light_pixelation_enabled;"));
      assertTrue(patch.contains("uniform float ph_mod_shadow_pixelation_enabled;"));
      assertTrue(patch.contains("uniform float ph_mod_shadow_pixel_size_rt;"));
      assertFalse(patch.contains("uniform float ph_mod_shadow_pixel_range_rt;"));
      assertFalse(patch.contains("vec3 phQuantizeCastLight("));
      assertTrue(patch.contains("vec2 phComputeTexelOffset("));
      assertTrue(patch.contains("vec3 phTexelSnap(vec3 value, vec2 texelOffset)"));
   }

   @Test
   void r2PatchedDeferredPixelizesCastDirectLightingOnly() throws IOException {
      assumeTrue(Files.exists(R2_PATCH), () -> "Missing r2 patch file: " + R2_PATCH);
      assumeTrue(Files.exists(R2_SOURCE), () -> "Missing r2 source file: " + R2_SOURCE);
      String patched = applyPatch(Files.readString(R2_PATCH), Files.readString(R2_SOURCE));

      assertTrue(patched.contains("float castPixelSize = phGetCastPixelSize();"));
      assertTrue(patched.contains("ivec2 castTexelCoord = phSnapTexelCoord(texelCoord, castTexSize, castPixelSize);"));
      assertTrue(patched.contains("vec4 castDirectSoft = texelFetch(radiosity_direct_soft, castTexelCoord, 0);"));
      assertTrue(patched.contains("vec3 pixelatedDirect = texelFetch(radiosity_handheld, castTexelCoord, 0).rgb"));
      assertFalse(patched.contains("phQuantizeCastLight("));
      assertTrue(patched.contains("rtDirect = pixelatedDirect;"));
      assertTrue(patched.contains("ph_mod_cast_light_pixelation_enabled > 0.5"));
      assertTrue(patched.contains("if (ph_mod_cast_light_pixelation_enabled > 0.5) {"));
      assertTrue(patched.contains("rtIndirect = texelFetch(colortex12, texelCoord, 0).rgb * 0.30;"));
      assertFalse(patched.contains("rtIndirect = texelFetch(colortex12, castTexelCoord, 0).rgb"));
      assertFalse(patched.contains("rtIndirect = phQuantizeCastLight("));
   }

   @Test
   void euphoriaPatchPixelizesFilteredCastLightOnly() throws IOException {
      String patched = applyPatch(Files.readString(EUPHORIA_PATCH), Files.readString(EUPHORIA_SOURCE));

      assertFalse(patched.contains("float castPixelSize = phGetCastPixelSize();"));
      assertFalse(patched.contains("ivec2 castTexelCoord = phSnapTexelCoord(texelCoord, castTexSize, castPixelSize);"));
      assertTrue(patched.contains("vec4 castDirectSoft = texelFetch(radiosity_direct_soft, texelCoord, 0);"));
      assertTrue(patched.contains("vec3 baseDirect = texelFetch(radiosity_handheld, texelCoord, 0).rgb"));
      assertTrue(patched.contains("vec3 pixelatedDirect = baseDirect;"));
      assertFalse(patched.contains("uniform sampler2D colortex11;"));
      assertFalse(patched.contains("uniform float ph_mod_shadow_pixelation_enabled;"));
      assertFalse(patched.contains("uniform float ph_mod_shadow_pixel_size_rt;"));
      assertFalse(patched.contains("vec3 centerNormal = phDecodeCacheNormal(texelFetch(colortex11, texelCoord, 0).xyz);"));
      assertFalse(patched.contains("ivec2 snapTexelCoord = phSnapTexelCoord(texelCoord, vec2(textureSize(radiosity_direct, 0)), shadowPixelSize);"));
      assertFalse(patched.contains("float edgeWeight = phComputeSnapEdgeWeight(texelCoord, centerNormal, centerLinearDepth);"));
      assertFalse(patched.contains("float surfaceWeight = phSurfaceContinuityWeight(texelCoord, snapTexelCoord, centerNormal, centerLinearDepth);"));
      assertFalse(patched.contains("float topDepthWeight = phTopSurfaceDepthWeight(snapTexelCoord, centerNormal, centerLinearDepth);"));
      assertFalse(patched.contains("float snapWeight = edgeWeight * surfaceWeight * topDepthWeight;"));
      assertFalse(patched.contains("vec3 stableSnappedDirect = mix(snappedDerivativeDirect, snappedDirect, sameCellWeight);"));
      assertFalse(patched.contains("snapWeight *= sameCellWeight;"));
      assertFalse(patched.contains("vec3 snappedDerivativeDirect = phTexelSnap(baseDirect, phTexelOffset);"));
      assertFalse(patched.contains("snappedDirect = mix(snappedDerivativeDirect, snappedDirect, surfaceWeight);"));
      assertTrue(patched.contains("// Upstream shadow pixelation already applied in ph_lighting.glsl."));
      assertTrue(patched.contains("pixelatedDirect = baseDirect;"));
      assertFalse(patched.contains("vec2 phTexelOffset = phComputeTexelOffset(radiosity_direct, texCoord, shadowPixelSize);"));
      assertFalse(patched.contains("float depthDiscontinuity = max(abs(depthX - centerLinearDepth), abs(depthY - centerLinearDepth));"));
      assertFalse(patched.contains("if (depthDiscontinuity < 0.02) {"));
      assertFalse(patched.contains("pixelatedDirect = phTexelSnap(pixelatedDirect, phTexelOffset);"));
      assertFalse(patched.contains("phQuantizeCastLight("));
      assertFalse(patched.contains("stableDirect = pixelatedDirect;"));
      assertFalse(patched.contains("if (ph_mod_shadow_pixelation_enabled > 0.5) {"));
      assertTrue(patched.contains("vec3 photonicsLighting = max(centerIndirect + pixelatedDirect, vec3(0.0));"));

      assertFalse(patched.contains("const int FILTER_RADIUS = 3;"));
      assertFalse(patched.contains("for (int ox = -FILTER_RADIUS; ox <= FILTER_RADIUS; ox++)"));
      assertFalse(patched.contains("for (int oy = -FILTER_RADIUS; oy <= FILTER_RADIUS; oy++)"));
   }

   @Test
   void euphoriaCastPixelizationUsesEdgeGuardAndDarkPixelFastPath() throws IOException {
      String patch = Files.readString(EUPHORIA_PATCH);

      assertFalse(patch.contains("float castEdgeMetric = phCastEdgeMetric(texelCoord, centerNormal, photonicsDepth);"));
      assertFalse(patch.contains("float castEdgeBlend = step(castEdgeMetric, 0.04);"));
      assertFalse(patch.contains("float castSurfaceBlend = phCastSnapSurfaceBlend(texelCoord, castTexelCoord, centerNormal, centerLinearDepth);"));
      assertFalse(patch.contains("float castPixelBlend = castEdgeBlend * castSurfaceBlend;"));
      assertFalse(patch.contains("vec2 castTexSize = vec2(textureSize(radiosity_direct, 0));"));
      assertFalse(patch.contains("ivec2 castTexelCoord = phSnapTexelCoord(texelCoord, castTexSize, castPixelSize);"));
      assertFalse(patch.contains("float centerLinearDepth = GetLinearDepth(z0ph);"));
      assertFalse(patch.contains("vec3 centerNormal = phDecodeCacheNormal(texelFetch(colortex11, texelCoord, 0).xyz);"));
      assertFalse(patch.contains("uniform sampler2D colortex11;"));
      assertFalse(patch.contains("uniform float ph_mod_shadow_pixelation_enabled;"));
      assertFalse(patch.contains("uniform float ph_mod_shadow_pixel_size_rt;"));
      assertFalse(patch.contains("ivec2 snapTexelCoord = phSnapTexelCoord(texelCoord, vec2(textureSize(radiosity_direct, 0)), shadowPixelSize);"));
      assertFalse(patch.contains("float edgeWeight = phComputeSnapEdgeWeight(texelCoord, centerNormal, centerLinearDepth);"));
      assertFalse(patch.contains("float surfaceWeight = phSurfaceContinuityWeight(texelCoord, snapTexelCoord, centerNormal, centerLinearDepth);"));
      assertFalse(patch.contains("float topDepthWeight = phTopSurfaceDepthWeight(snapTexelCoord, centerNormal, centerLinearDepth);"));
      assertFalse(patch.contains("float snapWeight = edgeWeight * surfaceWeight * topDepthWeight;"));
      assertFalse(patch.contains("vec3 stableSnappedDirect = mix(snappedDerivativeDirect, snappedDirect, sameCellWeight);"));
      assertFalse(patch.contains("snapWeight *= sameCellWeight;"));
      assertTrue(patch.contains("// Upstream shadow pixelation already applied in ph_lighting.glsl."));
      assertTrue(patch.contains("pixelatedDirect = baseDirect;"));
      assertFalse(patch.contains("ivec2 sampleCoordXp = ivec2(min(texelCoord.x + 1, maxCoord.x), texelCoord.y);"));
      assertFalse(patch.contains("ivec2 sampleCoordXn = ivec2(max(texelCoord.x - 1, 0), texelCoord.y);"));
      assertFalse(patch.contains("ivec2 sampleCoordYp = ivec2(texelCoord.x, min(texelCoord.y + 1, maxCoord.y));"));
      assertFalse(patch.contains("ivec2 sampleCoordYn = ivec2(texelCoord.x, max(texelCoord.y - 1, 0));"));
      assertFalse(patch.contains("float sameSample = float(all(equal(centerCoord, sampleCoord)));"));
      assertFalse(patch.contains("return max(sameSample, clamp(depthWeight * normalWeight, 0.0, 1.0));"));
      assertFalse(patch.contains("snappedDirect = mix(snappedDerivativeDirect, snappedDirect, surfaceWeight);"));
      assertFalse(patch.contains("pixelatedDirect = mix(baseDirect, snappedDirect, snapWeight);"));
      assertFalse(patch.contains("pixelatedDirect = mix(baseDirect, stableSnappedDirect, snapWeight);"));
      assertFalse(patch.contains("vec3 centerNormal = phDecodeViewNormal(texelFetch(colortex4, texelCoord, 0).xyz);"));
      assertFalse(patch.contains("ivec2 sampleCoordX = ivec2(min(texelCoord.x + 1, maxCoord.x), texelCoord.y);"));
      assertFalse(patch.contains("ivec2 sampleCoordY = ivec2(texelCoord.x, min(texelCoord.y + 1, maxCoord.y));"));
      assertFalse(patch.contains("float depthX = GetLinearDepth(texelFetch(depthtex0, sampleCoordX, 0).r);"));
      assertFalse(patch.contains("float depthY = GetLinearDepth(texelFetch(depthtex0, sampleCoordY, 0).r);"));
      assertFalse(patch.contains("float depthDiscontinuity = max(abs(depthX - centerLinearDepth), abs(depthY - centerLinearDepth));"));
      assertFalse(patch.contains("texelFetch(colortex11, sampleCoordX, 0).rgb * 2.0 - 1.0"));
      assertFalse(patch.contains("float phCastSnapSurfaceBlend(ivec2 texelCoord, ivec2 snapTexelCoord, vec3 centerNormal, float centerLinearDepth)"));
      assertFalse(patch.contains("phQuantizeCastLight("));
      assertFalse(patch.contains("centerAlbedo"));
   }

   @Test
   void euphoriaDebugPixelationBypassesAlbedoShading() throws IOException {
      String patch = Files.readString(EUPHORIA_PATCH);

      assertTrue(patch.contains("uniform float ph_mod_pixelation_debug_enabled;"));
      assertTrue(patch.contains("if (ph_mod_pixelation_debug_enabled > 0.5) {"));
      assertTrue(patch.contains("color.rgb = pixelatedDirect;"));
   }

   @Test
   void castPixelizationDefaultsAreStrongEnoughToBeVisible() throws IOException {
      assumeTrue(Files.exists(EUPHORIA_PROPERTIES), () -> "Missing Euphoria properties: " + EUPHORIA_PROPERTIES);
      String euphoriaProperties = Files.readString(EUPHORIA_PROPERTIES);

      assumeTrue(Files.exists(R2_PROPERTIES), () -> "Missing r2 properties: " + R2_PROPERTIES);
      String r2Properties = Files.readString(R2_PROPERTIES);

      assertTrue(r2Properties.contains("uniform.float.ph_debug_cast_light_pixel_size=8.0"));
      assertTrue(r2Properties.contains("uniform.float.ph_debug_cast_light_threshold=0.001"));
      assertFalse(r2Properties.contains("uniform.float.ph_debug_cast_light_pixelation_enabled=1.0"));
      assertTrue(euphoriaProperties.contains("uniform.float.ph_debug_cast_light_pixel_size=8.0"));
      assertFalse(euphoriaProperties.contains("uniform.float.ph_mod_shadow_pixelation_size="));
      assertFalse(euphoriaProperties.contains("uniform.float.ph_debug_cast_light_pixelation_enabled=1.0"));
   }

   void euphoriaPatchAvoidsExtraSpatialFilteringInPixelizedMode() throws IOException {
      String patch = Files.readString(EUPHORIA_PATCH);

      assertFalse(patch.contains("const int FILTER_RADIUS = 3;"));
      assertFalse(patch.contains("const float SIGMA_SPATIAL = 2.0;"));
      assertFalse(patch.contains("const float SIGMA_NORMAL = 32.0;"));
      assertFalse(patch.contains("for (int ox = -FILTER_RADIUS; ox <= FILTER_RADIUS; ox++)"));
      assertFalse(patch.contains("for (int oy = -FILTER_RADIUS; oy <= FILTER_RADIUS; oy++)"));
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
