package at.redi2go.photonic.client.api;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class OctrayLightingModeTest {
   @Test
   void octrayEnumExistsAtOrdinalThree() {
      LightingMode octray = LightingMode.valueOf("OCTRAY");
      assertEquals(3, octray.ordinal(), "OCTRAY must be the fourth mode (ordinal 3) to match PH_LIGHTING_MODE == 3");
   }

   @Test
   void allFourModesArePresent() {
      LightingMode[] modes = LightingMode.values();
      assertEquals(4, modes.length, "LightingMode must have exactly four entries: OFF, BASIC, RESTIR, OCTRAY");
      assertEquals("OFF", modes[0].name());
      assertEquals("BASIC", modes[1].name());
      assertEquals("RESTIR", modes[2].name());
      assertEquals("OCTRAY", modes[3].name());
   }

   @Test
   void defaultLightingModeIsOctray() {
      assertEquals(LightingMode.OCTRAY, PhotonicsProperties.DEFAULT_LIGHTING_MODE);
   }
}
