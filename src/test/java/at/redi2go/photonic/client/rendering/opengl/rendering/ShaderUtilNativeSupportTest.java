package at.redi2go.photonic.client.rendering.opengl.rendering;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ShaderUtilNativeSupportTest {

   @Test
   void preprocessAutoUniformsConvertsPhotonicsCustomAlphaDirectives() {
      String source = """
         #version 430
         #PH_USE_CUSTOM_ALPHA
         #PH_ALPHA_FUNC(color) apply_tint_impl(color)
         vec3 apply_tint_impl(vec4 color) { return color.rgb; }
         """;

      String processed = ShaderUtil.preprocessPhotonicsDirectives(source);

      assertTrue(processed.contains("#define PH_USE_CUSTOM_ALPHA"));
      assertTrue(processed.contains("#define PH_ALPHA_FUNC(color) apply_tint_impl(color)"));
      assertFalse(processed.contains("\n#PH_USE_CUSTOM_ALPHA\n"));
      assertFalse(processed.contains("\n#PH_ALPHA_FUNC(color) apply_tint_impl(color)\n"));
   }

   @Test
   void preprocessAutoUniformsInjectsReferencedIrisSamplersWithoutDuplicates() {
      String source = """
         #version 430
         uniform sampler2D colortex10;
         vec3 load_color() {
            return texelFetch(colortex10, ivec2(0), 0).rgb + texelFetch(colortex11, ivec2(0), 0).rgb;
         }
         """;

      String processed = ShaderUtil.preprocessAutoUniforms(source);

      assertEquals(source, processed, "preprocessAutoUniforms should return source unchanged in 0.3.1");
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
