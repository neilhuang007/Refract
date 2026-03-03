package at.redi2go.photonic.client.rendering.patching;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PhotonicsLightingShaderTemporalTest {
   private static final Path LIGHTING_SHADER = Path.of("assets/photonic/shaders/ph_lighting.glsl");

   @Test
   void handheldLightingUsesReferenceVisibilityAndNormalDot() throws IOException {
      String shader = Files.readString(LIGHTING_SHADER);
      assertTrue(shader.contains("brightness *= clamp(30.0f * (hand_to_result_distance - hand_to_base_distance + 0.05f), 0.0f, 1.0f);"));
      assertTrue(shader.contains("brightness *= dot(mapped_normal, -light_ray.direction);"));
      assertFalse(shader.contains("if (light_ray.result_hit)"));
      assertFalse(shader.contains("smoothstep(0.12f, 0.35f, hitDistanceError)"));
   }

   @Test
   void directAndSoftTemporalBuffersUseReferenceResetPath() throws IOException {
      String shader = Files.readString(LIGHTING_SHADER);
      assertTrue(shader.contains("if (light_reload || frag == NULL4)"));
      assertTrue(shader.contains("frag.direct = vec4(0.0f);"));
      assertTrue(shader.contains("frag.direct_soft = vec4(0.0f);"));
      assertFalse(shader.contains("} else if (light_reload) {"));
      assertFalse(shader.contains("if (hard_light_count == 0)"));
   }

   @Test
   void directLightingUsesReferencePerLightIteration() throws IOException {
      String shader = Files.readString(LIGHTING_SHADER);
      assertTrue(shader.contains("for (; frag.direct.w < light_count - soft_light_count; frag.direct.w++) {"));
      assertTrue(shader.contains("int index = light_registry_array[(int(frag.direct_soft.w) % soft_light_count) + light_offset + 1];"));
      assertFalse(shader.contains("int hardSamples = min(4, hardLightCount);"));
      assertFalse(shader.contains("bilateralNeighborDenoise("));
      assertFalse(shader.contains("temporalClamp("));
   }

   @Test
   void temporalBuffersUseReferenceDecay() throws IOException {
      String shader = Files.readString(LIGHTING_SHADER);
      assertTrue(shader.contains("float historyDecay = light_reload ? 0.0f : 0.985f;"));
      assertTrue(shader.contains("result *= historyDecay;"));
      assertFalse(shader.contains("reprojectionValid"));
      assertFalse(shader.contains("result *= 0.90f;"));
   }

   @Test
   void lightingPathsDoNotUseSanitizationHelpersInReferenceShader() throws IOException {
      String shader = Files.readString(LIGHTING_SHADER);
      assertTrue(shader.contains("if (dot(d, d) >= 0.1f)"));
      assertTrue(shader.contains("if (dot(n, base_normal) < 0.99f)"));
      assertTrue(shader.contains("indirect_color *= (float(i > 0) * 5 + 1) * indirect_light_color;"));
      assertTrue(shader.contains("indirect_color *= (float(i > 0) * 15 + 1) * indirect_light_color;"));
      assertFalse(shader.contains("bool finite_vec3(vec3 value)"));
      assertFalse(shader.contains("vec3 sanitize_radiance(vec3 value)"));
      assertFalse(shader.contains("float attenuation_denom = max(dot(vec2(1, distance_squared), light.attenuation), 0.0001f);"));
   }

   @Test
   void softShadowSamplingUsesReferenceBasisConstruction() throws IOException {
      String shader = Files.readString(LIGHTING_SHADER);
      assertTrue(shader.contains("vec3 light_tangent   = normalize(cross(light_dir, normalize(vec3(0.0f, 1.0f, 1.0f))));"));
      assertTrue(shader.contains("vec3 light_bitangent = normalize(cross(light_tangent, light_dir));"));
      assertFalse(shader.contains("vec3 basis = abs(light_dir.y) > 0.8f ?"));
      assertFalse(shader.contains("vec3 sample_blue_noise_hemisphere"));
   }

   @Test
   void shadowPixelationUsesDeterministicFaceAxisAndInwardBias() throws IOException {
      String shader = Files.readString(LIGHTING_SHADER);
      assertTrue(shader.contains("vec3 faceAxis = vec3(0.0);"));
      assertTrue(shader.contains("if (absN.x >= absN.y && absN.x >= absN.z) {"));
      assertTrue(shader.contains("float safePixelSize = max(ph_mod_shadow_pixel_size_rt, 1.0f);"));
      assertTrue(shader.contains("float faceSign = sign(dot(base_normal, faceAxis));"));
      assertTrue(shader.contains("vec3 faceNormal = faceAxis * faceSign;"));
      assertTrue(shader.contains("const float faceInset = 1.0 / 512.0;"));
      assertTrue(shader.contains("vec3 ownedPos = worldPos - faceInset * faceNormal;"));
      assertTrue(shader.contains("vec3 blockOrigin = floor(ownedPos);"));
      assertTrue(shader.contains("vec3 texelIdx = floor(localPos * safePixelSize);"));
      assertTrue(shader.contains("float faceDepth = dot(blockOrigin, faceAxis) + (faceSign > 0.0 ? 1.0 : 0.0);"));
      assertTrue(shader.contains("worldPos = (blockOrigin + snappedLocal) * faceMask + faceDepth * faceAxis;"));
      assertFalse(shader.contains("float faceBias = 0.02;"));
      assertFalse(shader.contains("float verticalBiasTarget = faceAxis.z > 0.5 ? 0.02 : 0.0;"));
      assertFalse(shader.contains("float verticalBias = min(verticalBiasTarget, max(worldYFrac - 0.001, 0.0));"));
      assertFalse(shader.contains("vec3 blockOrigin = floor(worldPos - faceBias * faceNormal - vec3(0.0, verticalBias, 0.0));"));
      assertFalse(shader.contains("vec3 normalAxis = step(dominant - 0.001, absN);"));
      assertFalse(shader.contains("vec3 blockOrigin = floor(worldPos + 0.01 * base_normal);"));
   }

   @Test
   void pixelationDebugDoesNotOverrideVisibleLightingOutput() throws IOException {
      String shader = Files.readString(LIGHTING_SHADER);
      assertFalse(shader.contains("vec3 debugGridColor = checker > 0.5 ? vec3(1.0) : vec3(1.0, 1.0, 0.0);"));
      assertFalse(shader.contains("direct_frag_out = vec4(debugGridColor, 1.0);"));
      assertFalse(shader.contains("direct_soft_frag_out = vec4(0.0, 0.0, 0.0, 0.01);"));
   }

   @Test
   void pixelationDebugProbeEncodesSurfaceMetadata() throws IOException {
      String shader = Files.readString(LIGHTING_SHADER);
      assertTrue(shader.contains("vec2 planeFrac = vec2(0.0);"));
      assertTrue(shader.contains("debugTexelOffset = planeFrac;"));
      assertTrue(shader.contains("debugCenterFactor = axisIndex;"));
      assertTrue(shader.contains("debugPixelMeta = faceSign;"));
      assertTrue(shader.contains("debugYBias = localPos.y;"));
      assertTrue(shader.contains("debugCenterBlend = checker;"));
   }
}
