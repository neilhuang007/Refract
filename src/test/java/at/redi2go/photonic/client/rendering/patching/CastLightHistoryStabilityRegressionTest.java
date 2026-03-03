package at.redi2go.photonic.client.rendering.patching;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class CastLightHistoryStabilityRegressionTest {
   private static final Path PH_LIGHTING = Path.of("assets/photonic/shaders/ph_lighting.glsl");

   @Test
   void shadowPixelationUsesRtSpaceSurfaceSnappingWithoutBreakingLightLookup() throws IOException {
      String source = Files.readString(PH_LIGHTING);

      assertFalse(source.contains("uniform float ph_mod_cast_light_pixelation_enabled;"));
      assertFalse(source.contains("uniform vec3 cameraPositionInt, cameraPositionFract;"));
      assertFalse(source.contains("vec3 phGetStableCameraPosition()"));
      assertFalse(source.contains("vec3 worldPosition = position + stableCameraWorld;"));
      assertFalse(source.contains("vec3 snappedWorldPosition = floor(worldPosition / safePixelSize + 0.5f) * safePixelSize;"));
      assertTrue(source.contains("vec3 worldPos = base_position + world_offset;"));
      assertFalse(source.contains("vec4 precomputedPlayerPos = texelFetch(colortex13, ivec2(gl_FragCoord.xy), 0);"));
      assertFalse(source.contains("if (precomputedPlayerPos.a > 0.5f) {"));
      assertFalse(source.contains("directPosition = precomputedPlayerPos.xyz + cameraPosition - world_offset;"));
      assertFalse(source.contains("directPosition = precomputedPlayerPos.xyz + eyePosition - world_offset;"));
      assertFalse(source.contains("if (floor(light.position) == floor(position))"));
      assertTrue(source.contains("if (floor(light.position) == floor(base_position))"));
   }
}
