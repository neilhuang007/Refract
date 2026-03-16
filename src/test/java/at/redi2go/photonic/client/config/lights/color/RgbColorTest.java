package at.redi2go.photonic.client.config.lights.color;

import org.joml.Vector3f;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class RgbColorTest {
   @Test
   void constructorPreservesRgbChannelOrder() {
      RgbColor color = new RgbColor(255, 128, 64);

      assertEquals(255, color.red());
      assertEquals(128, color.green());
      assertEquals(64, color.blue());
      assertEquals(0xFF8040, color.toOpaque());
   }

   @Test
   void rgbStringParsingKeepsGreenInMiddleChannel() throws Exception {
      RgbColor color = RgbColor.fromRgbString("rgb(1.0, 0.5, 0.25)");

      assertEquals(255, color.red());
      assertEquals(127, color.green());
      assertEquals(63, color.blue());
   }

   @Test
   void vectorConversionUsesStandardRgbOrder() {
      LightColor color = new RgbColor(255, 128, 64);

      assertEquals(new Vector3f(1.0f, 128.0f / 255.0f, 64.0f / 255.0f), color.toVec3f());
   }
}
