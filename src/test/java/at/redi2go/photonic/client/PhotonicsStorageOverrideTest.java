package at.redi2go.photonic.client;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class PhotonicsStorageOverrideTest {
   @Test
   void explicitLightingModePropertyWinsOverStoredOverride() {
      String previousProperty = System.getProperty("photonics.lightingMode");
      String previousStoredValue = PhotonicsStorage.LIGHTING_MODE_OVERRIDE.value;

      try {
         System.setProperty("photonics.lightingMode", "OCTRAY");
         PhotonicsStorage.LIGHTING_MODE_OVERRIDE.value = "RESTIR";

         PhotonicsStorage.applySystemPropertyOverrides();

         assertEquals("OCTRAY", System.getProperty("photonics.lightingMode"));
      } finally {
         restoreProperty("photonics.lightingMode", previousProperty);
         PhotonicsStorage.LIGHTING_MODE_OVERRIDE.value = previousStoredValue;
      }
   }

   @Test
   void storedLightingModeAppliesWhenSystemPropertyIsMissing() {
      String previousProperty = System.getProperty("photonics.lightingMode");
      String previousStoredValue = PhotonicsStorage.LIGHTING_MODE_OVERRIDE.value;

      try {
         System.clearProperty("photonics.lightingMode");
         PhotonicsStorage.LIGHTING_MODE_OVERRIDE.value = "OCTRAY";

         PhotonicsStorage.applySystemPropertyOverrides();

         assertEquals("OCTRAY", System.getProperty("photonics.lightingMode"));
      } finally {
         restoreProperty("photonics.lightingMode", previousProperty);
         PhotonicsStorage.LIGHTING_MODE_OVERRIDE.value = previousStoredValue;
      }
   }

   private static void restoreProperty(String key, String value) {
      if (value == null) {
         System.clearProperty(key);
      } else {
         System.setProperty(key, value);
      }
   }
}
