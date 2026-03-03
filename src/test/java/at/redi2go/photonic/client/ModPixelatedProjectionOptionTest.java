package at.redi2go.photonic.client;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ModPixelatedProjectionOptionTest {
   private static final Path STORAGE_FILE = Path.of("src/at/redi2go/photonic/client/PhotonicsStorage.java");
   private static final Path STORAGE_IO_FILE = Path.of("src/at/redi2go/photonic/client/StorageIO.java");
   private static final Path SETTINGS_SCREEN_FILE = Path.of("src/at/redi2go/photonic/client/ModSettingsScreen.java");
   private static final Path COMMON_UNIFORMS_MIXIN_FILE = Path.of("src/at/redi2go/photonic/client/mixin/CommonUniformsMixin.java");

   @Test
   void storageDeclaresShadowPixelationParameters() throws IOException {
      String source = Files.readString(STORAGE_FILE);

      assertTrue(source.contains("public static final Parameter<Boolean> SHADOW_PIXELATION_ENABLED"));
      assertTrue(source.contains("\"shadow_pixelation_enabled\""));
      assertTrue(source.contains("public static final Parameter<Float> SHADOW_PIXELATION_SIZE"));
      assertTrue(source.contains("\"shadow_pixelation_size\""));
      assertTrue(source.contains("floatParam(\"shadow_pixelation_size\", 8.0F)"));
      assertFalse(source.contains("PIXELATED_PROJECTION"));
      assertFalse(source.contains("CAST_LIGHT_PIXEL_SIZE"));
      assertFalse(source.contains("\"cast_light_pixel_size\""));
   }

   @Test
   void settingsScreenExposesShadowPixelationControls() throws IOException {
      String source = Files.readString(SETTINGS_SCREEN_FILE);

      assertTrue(source.contains("PhotonicsStorage.Parameter<Boolean> shadowPixelation = PhotonicsStorage.SHADOW_PIXELATION_ENABLED;"));
      assertTrue(source.contains("PhotonicsStorage.Parameter<Float> shadowPixelationSize = PhotonicsStorage.SHADOW_PIXELATION_SIZE;"));
      assertTrue(source.contains("\"Pixelated Lighting: \" + (shadowPixelation.value ? \"On\" : \"Off\")"));
      assertTrue(source.contains("new ModSettingsScreen.ShadowPixelationSizeSlider("));
      assertTrue(source.contains("float[] STEPS = new float[]{1.0f, 2.0f, 4.0f, 8.0f, 16.0f};"));
      assertTrue(source.contains("\"Pixelated Lighting Size: \""));
      assertFalse(source.contains("ShadowBiasSlider"));
      assertFalse(source.contains("Pixelated Projection:"));
      assertFalse(source.contains("CastLightPixelSizeSlider"));
      assertFalse(source.contains("castLightPixelSize"));
      assertFalse(source.contains("pixelatedProjection"));
   }

   @Test
   void commonUniformsPublishShadowPixelationUniforms() throws IOException {
      String source = Files.readString(COMMON_UNIFORMS_MIXIN_FILE);

      assertTrue(source.contains("\"ph_mod_shadow_pixelation_enabled\""));
      assertTrue(source.contains("() -> PhotonicsStorage.SHADOW_PIXELATION_ENABLED.value ? 1.0F : 0.0F"));
      assertTrue(source.contains("\"ph_mod_shadow_pixel_size_rt\""));
      assertTrue(source.contains("float shadowSize = Math.max(1.0F, PhotonicsStorage.SHADOW_PIXELATION_SIZE.value);"));
      assertTrue(source.contains("return shadowSize;"));
      assertFalse(source.contains("\"ph_mod_shadow_bias_center_normal_offset\""));
      assertFalse(source.contains("\"ph_mod_shadow_bias_subsurface_sign_coupling\""));
      assertFalse(source.contains("\"ph_mod_cast_light_pixelation_enabled\""));
      assertFalse(source.contains("PhotonicsStorage.PIXELATED_PROJECTION"));
      assertFalse(source.contains("\"ph_mod_cast_light_pixel_size\""));
      assertFalse(source.contains("PhotonicsStorage.CAST_LIGHT_PIXEL_SIZE"));
   }
}
