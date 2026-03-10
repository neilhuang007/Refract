package at.redi2go.photonic.client;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class ModOilifyOptionTest {
   private static final Path STORAGE_FILE = Path.of("src/at/redi2go/photonic/client/PhotonicsStorage.java");
   private static final Path SETTINGS_SCREEN_FILE = Path.of("src/at/redi2go/photonic/client/ModSettingsScreen.java");
   @Test
   void storageDeclaresOilifyEnabledParameter() throws IOException {
      String source = Files.readString(STORAGE_FILE);

      assertTrue(source.contains("OILIFY_ENABLED"));
      assertTrue(source.contains("\"oilify_enabled\""));
   }

   @Test
   void settingsScreenExposesOilifyToggle() throws IOException {
      String source = Files.readString(SETTINGS_SCREEN_FILE);

      assertTrue(source.contains("PhotonicsStorage.Parameter<Boolean> oilify = PhotonicsStorage.OILIFY_ENABLED;"));
      assertTrue(source.contains("\"Oilify: \" + (oilify.value ? \"On\" : \"Off\")"));
      assertTrue(source.contains("oilify.value = !oilify.value;"));
      assertTrue(source.contains("oilify.modified();"));
   }

   @Test
   void storageDeclaresoilifyConfigParameters() throws IOException {
      String source = Files.readString(STORAGE_FILE);

      assertTrue(source.contains("OILIFY_SIZE"), "OILIFY_SIZE parameter must exist");
      assertTrue(source.contains("\"oilify_size\""), "oilify_size config key must exist");
      assertTrue(source.contains("OILIFY_SHARPNESS"), "OILIFY_SHARPNESS parameter must exist");
      assertTrue(source.contains("\"oilify_sharpness\""), "oilify_sharpness config key must exist");
      assertTrue(source.contains("OILIFY_SCALE"), "OILIFY_SCALE parameter must exist");
      assertTrue(source.contains("\"oilify_scale\""), "oilify_scale config key must exist");
      assertTrue(source.contains("OILIFY_TUNING"), "OILIFY_TUNING parameter must exist");
      assertTrue(source.contains("\"oilify_tuning\""), "oilify_tuning config key must exist");
      assertTrue(source.contains("OILIFY_ITERATIONS"), "OILIFY_ITERATIONS parameter must exist");
      assertTrue(source.contains("\"oilify_iterations\""), "oilify_iterations config key must exist");
      assertTrue(source.contains("OILIFY_DEPTH_SCALING"), "OILIFY_DEPTH_SCALING parameter must exist");
      assertTrue(source.contains("\"oilify_depth_scaling\""), "oilify_depth_scaling config key must exist");
      assertTrue(source.contains("OILIFY_STROKE_STRENGTH"), "OILIFY_STROKE_STRENGTH parameter must exist");
      assertTrue(source.contains("\"oilify_stroke_strength\""), "oilify_stroke_strength config key must exist");
   }

   @Test
   void settingsScreenUsesUnifiedOilifySlider() throws IOException {
      String source = Files.readString(SETTINGS_SCREEN_FILE);

      assertTrue(source.contains("class OilifySlider extends SliderWidget"), "unified OilifySlider class must exist");

      assertTrue(source.contains("new OilifySlider(PhotonicsStorage.OILIFY_SIZE, 3.0f, 15.0f, \"OILIFY_SIZE\", true)"),
         "size slider with correct range");
      assertTrue(source.contains("new OilifySlider(PhotonicsStorage.OILIFY_SHARPNESS, 0.0f, 1.0f, \"Sharpness\", false)"),
         "sharpness slider with correct range");
      assertTrue(source.contains("new OilifySlider(PhotonicsStorage.OILIFY_SCALE, 1.0f, 4.0f, \"Scale\", false)"),
         "scale slider with correct range");
      assertTrue(source.contains("new OilifySlider(PhotonicsStorage.OILIFY_TUNING, 0.0f, 4.0f, \"Anistropy Tuning\", false)"),
         "tuning slider with correct range");
      assertTrue(source.contains("new OilifySlider(PhotonicsStorage.OILIFY_ITERATIONS, 1.0f, 8.0f, \"OILIFY_ITERATIONS\", true)"),
         "iterations slider with correct range");
      assertTrue(source.contains("new OilifySlider(PhotonicsStorage.OILIFY_DEPTH_SCALING, 0.0f, 2.0f, \"Depth Scaling\", false)"),
         "depth scaling slider with correct range");
      assertTrue(source.contains("new OilifySlider(PhotonicsStorage.OILIFY_STROKE_STRENGTH, 0.0f, 1.0f, \"Stroke Strength\", false)"),
         "stroke strength slider with correct range");

      assertTrue(source.contains("oilifySliders.forEach(s -> s.active = PhotonicsStorage.OILIFY_ENABLED.value)"),
         "unified active-state management must exist");
   }
}
