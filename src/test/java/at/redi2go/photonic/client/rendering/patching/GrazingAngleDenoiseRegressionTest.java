package at.redi2go.photonic.client.rendering.patching;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

class GrazingAngleDenoiseRegressionTest {
   private static final Path PH_CORE = Path.of("assets/photonic/shaders/ph_core.glsl");
   private static final Path PH_LIGHTING = Path.of("assets/photonic/shaders/ph_lighting.glsl");
   private static final Path EUPHORIA_DEFERRED1 = Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r5.7.1_EuphoriaPatches_1.8.6/deferred1.glsl");
   private static final Path R2_DEFERRED1 = Path.of("assets/photonic/shaders/patches/ComplementaryReimagined_r2.0.3/deferred1.glsl");

   @Test
   void phCoreBadAngleResolutionDowngrade() throws IOException {
      String shader = Files.readString(PH_CORE);

      assertTrue(shader.contains("dot(normal, normalize(world_pos - world_camera_pos)) > -0.2f"),
         "badAngle must use dot product threshold of -0.2f");
      assertTrue(shader.contains("bool badAngle = dot(normal, normalize(world_pos - world_camera_pos)) > -0.2f && dist > 16.0f;"),
         "badAngle must only trigger for near-grazing angles and moderate distance");
      assertTrue(shader.contains("if (dist > 32.0f || badAngle)"),
         "Resolution must drop to 1.0 when dist > 32 OR badAngle");
      assertTrue(shader.contains("resolution = 1.0f;"),
         "Resolution must be set to 1.0f for mid-range or bad-angle surfaces");
      assertTrue(shader.contains("if (dist > 128.0f)"),
         "Resolution must further drop when dist > 128");
      assertTrue(shader.contains("resolution = 2.0f;"),
         "Resolution must be set to 2.0f for far surfaces");
      assertTrue(shader.contains("float resolution = 0.5f;"),
         "Base resolution must start at 0.5f");
      assertTrue(shader.contains("floor(world_pos / resolution) * resolution"),
         "world_pos must be quantized using floor(world_pos / resolution) * resolution");
   }

   @Test
   void phLightingEdgeDetectionSkipsIndirectAtEdges() throws IOException {
      String shader = Files.readString(PH_LIGHTING);

      assertTrue(shader.contains("fract(base_position)"),
         "onEdge detection must use fract(base_position)");
      assertTrue(shader.contains("bool onEdge ="),
         "onEdge variable must be declared");
      assertTrue(shader.contains("if (!onEdge)"),
         "process_indirect() must be guarded by !onEdge check");
      assertTrue(shader.contains("ph_process_indirect();"),
         "ph_process_indirect() call must be present");

      int onEdgeIndex = shader.indexOf("bool onEdge =");
      int processIndirectIndex = shader.indexOf("ph_process_indirect();");
      assertTrue(onEdgeIndex >= 0 && processIndirectIndex >= 0 && onEdgeIndex < processIndirectIndex,
         "onEdge must be declared before ph_process_indirect() call");
   }

   @Test
   void euphoriadeferred1BilateralFilterParameters() throws IOException {
      String patch = Files.readString(EUPHORIA_DEFERRED1);

      assertFalse(patch.contains("GetLinearDepth"),
         "Deferred patch should no longer perform local depth-based snap gating");
      assertTrue(patch.contains("texelFetch(radiosity_direct_soft, texelCoord, 0)"),
         "Center fallback should use direct_soft center sample to avoid flicker");
      assertTrue(patch.contains("any(isnan(photonicsLighting)) || any(isinf(photonicsLighting))"),
         "NaN/Inf sanitization must be present for photonicsLighting");
      assertTrue(patch.contains("any(isnan(photonicsAlbedo)) || any(isinf(photonicsAlbedo))"),
         "NaN/Inf sanitization must be present for photonicsAlbedo");
      assertFalse(patch.contains("if (ph_mod_shadow_pixelation_enabled > 0.5) {"),
         "Deferred patch should not apply shadow-pixelation snap logic anymore");
      assertFalse(patch.contains("vec2 phTexelOffset = phComputeTexelOffset(radiosity_direct, texCoord, shadowPixelSize);"),
         "Deferred patch should not compute screen-space texel offset for cast pixelation");
      assertFalse(patch.contains("float snapWeight = edgeWeight * surfaceWeight * topDepthWeight;"),
         "Deferred patch should not combine deferred snap weights");
      assertFalse(patch.contains("vec3 stableSnappedDirect = mix(snappedDerivativeDirect, snappedDirect, sameCellWeight);"),
         "Deferred patch should not mix snapped direct in deferred stage");
      assertFalse(patch.contains("pixelatedDirect = mix(baseDirect, stableSnappedDirect, snapWeight);"),
         "Final deferred mix should use upstream-provided direct lighting");
      assertTrue(patch.contains("// Upstream shadow pixelation already applied in ph_lighting.glsl."),
         "Patch should document upstream ownership of pixelation");
      assertTrue(patch.contains("pixelatedDirect = baseDirect;"),
         "Deferred stage must keep direct lighting unchanged when composing");
      assertFalse(patch.contains("pixelatedDirect = phTexelSnap(pixelatedDirect, phTexelOffset);"),
         "Direct lighting should no longer hard-snap in deferred stage");
      assertTrue(patch.contains("vec3 photonicsLighting = max(centerIndirect + pixelatedDirect, vec3(0.0));"),
         "Final lighting must combine centerIndirect and upstream direct lighting");
   }

   @Test
   void r2Deferred1LacksBilateralFiltering() throws IOException {
      assumeTrue(Files.exists(R2_DEFERRED1), () -> "Missing r2 deferred1 patch: " + R2_DEFERRED1);
      String patch = Files.readString(R2_DEFERRED1);

      assertFalse(patch.contains("FILTER_RADIUS"),
         "r2.0.3 deferred1 must not contain FILTER_RADIUS (no spatial denoising)");
      assertFalse(patch.contains("SIGMA_SPATIAL"),
         "r2.0.3 deferred1 must not contain SIGMA_SPATIAL (no spatial denoising)");
   }

   @Test
   void phLightingTemporalAccumulationDecay() throws IOException {
      String shader = Files.readString(PH_LIGHTING);

      assertTrue(shader.contains("float historyDecay;"),
         "historyDecay must be declared");
      assertTrue(shader.contains("historyDecay = mix(0.5f, 0.0f,"),
         "historyDecay must blend to 0.0 during strong blend factor");
      assertTrue(shader.contains("historyDecay = 0.9f;"),
         "historyDecay must be 0.9 for low sample count");
      assertTrue(shader.contains("historyDecay = 0.95f;"),
         "historyDecay must be 0.95 for medium sample count");
      assertTrue(shader.contains("historyDecay = 0.985f;"),
         "historyDecay must reach 0.985 for high sample count");
      assertTrue(shader.contains("result *= historyDecay;"),
         "History must be multiplied by historyDecay");
      assertTrue(shader.contains("if (frag == NULL4)"),
         "History must be fully reset when frag is NULL4");
      assertTrue(shader.contains("dot(d, d) >= 0.1f"),
         "Reprojection must reject samples with position distance dot(d,d) >= 0.1f");
      assertTrue(shader.contains("dot(n, base_normal) < 0.99f"),
         "Reprojection must reject samples with normal similarity below 0.99f");
   }

   @Test
   void phLightingIndirectBouncesAndEarlyTermination() throws IOException {
      String shader = Files.readString(PH_LIGHTING);

      assertTrue(shader.contains("for (int i = 0; i < 2; i++)"),
         "sample_indirect_lighting must use exactly 2 bounces");
      assertTrue(shader.contains("RAY_ITERATION_COUNT = 32;"),
         "Indirect bounce ray iteration count must be 32");
      assertFalse(shader.contains("sample_blue_noise_hemisphere"),
         "Reference shader should not include unstable blue-noise hemisphere helper");
      assertTrue(shader.contains("breakOnEmpty = true;"),
         "breakOnEmpty optimization must be enabled for indirect bounces");
      assertTrue(shader.contains("RandomFloat01(rngState) < 0.25f"),
         "Sun sampling probability must be 0.25");
      assertTrue(shader.contains("dot(sun_direction, light_ray.result_normal) > 0.707f"),
         "Sun sampling must check normal angle with threshold 0.707f");
   }
}
