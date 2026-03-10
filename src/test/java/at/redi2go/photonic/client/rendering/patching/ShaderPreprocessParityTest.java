package at.redi2go.photonic.client.rendering.patching;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ShaderPreprocessParityTest {
   private static final Path MIXINS_JSON = Path.of("photonics.mixins.json");
   private static final Path PH_LIGHTING = Path.of("assets/photonic/shaders/ph_lighting.glsl");
   private static final Path PH_INDIRECT = Path.of("assets/photonic/shaders/ph_indirect.glsl");
   private static final Path SHADER_PACK_MIXIN = Path.of("src/at/redi2go/photonic/client/mixin/ShaderPackMixin.java");
   private static final Pattern INLINE_FRAME_COUNTER_UNIFORM =
      Pattern.compile("(?m)^(?!\\s*//)\\s*uniform int frameCounter, frameTime;");

   @Test
   void mixinConfigIncludesDecompilerPreprocessorHooks() throws IOException {
      String mixins = Files.readString(MIXINS_JSON);

      assertTrue(mixins.contains("\"JcppProcessorMixin\""));
      assertTrue(mixins.contains("\"ShaderPackSourceNamesMixin\""));
   }

   @Test
   void photonicsShadersUseRequiredUniformMarkersInsteadOfInlineIrisUniforms() throws IOException {
      String lighting = Files.readString(PH_LIGHTING);
      String indirect = Files.readString(PH_INDIRECT);

      assertTrue(lighting.contains("//ph_required: uniform int frameCounter, frameTime;"));
      assertTrue(indirect.contains("//ph_required: uniform int frameCounter, frameTime;"));
      assertFalse(INLINE_FRAME_COUNTER_UNIFORM.matcher(lighting).find());
      assertFalse(INLINE_FRAME_COUNTER_UNIFORM.matcher(indirect).find());
   }

   @Test
   void shaderPackPreprocessorNormalizesPhotonicsCustomDirectivesBeforeJcpp() throws IOException {
      String mixin = Files.readString(SHADER_PACK_MIXIN);

      assertTrue(
         mixin.contains("ShaderUtil.preprocessPhotonicsDirectives"),
         "ShaderPackMixin should normalize #PH_* directives before JCPP preprocessing"
      );
   }
}
