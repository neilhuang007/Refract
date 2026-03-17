package at.redi2go.photonic.client;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class PhotonicsStorageOverrideTest {
   @Test
   void explicitLightingModePropertyWinsOverStoredOverride() {
      String previousProperty = System.getProperty("photonics.lightingMode");
      String previousStoredValue = PhotonicsStorage.LIGHTING_MODE_OVERRIDE.value;

      try {
         System.setProperty("photonics.lightingMode", "LIGHT_TREE");
         PhotonicsStorage.LIGHTING_MODE_OVERRIDE.value = "BASIC";

         PhotonicsStorage.applySystemPropertyOverrides();

         assertEquals("LIGHT_TREE", System.getProperty("photonics.lightingMode"));
      } finally {
         restoreProperty("photonics.lightingMode", previousProperty);
         PhotonicsStorage.LIGHTING_MODE_OVERRIDE.value = previousStoredValue;
      }
   }

   @Test
   void explicitLightBinningPropertyWinsOverStoredOverride() {
      String previousProperty = System.getProperty("photonics.enableLightBinning");
      String previousNewProperty = System.getProperty("photonics.lightBinningEnabled");
      String previousStoredValue = PhotonicsStorage.LIGHT_BINNING_OVERRIDE.value;

      try {
         System.setProperty("photonics.enableLightBinning", "false");
         System.clearProperty("photonics.lightBinningEnabled");
         PhotonicsStorage.LIGHT_BINNING_OVERRIDE.value = "true";

         PhotonicsStorage.applySystemPropertyOverrides();

         assertEquals("false", System.getProperty("photonics.enableLightBinning"));
      } finally {
         restoreProperty("photonics.enableLightBinning", previousProperty);
         restoreProperty("photonics.lightBinningEnabled", previousNewProperty);
         PhotonicsStorage.LIGHT_BINNING_OVERRIDE.value = previousStoredValue;
      }
   }

   @Test
   void storedLightingModeAppliesWhenSystemPropertyIsMissing() {
      String previousProperty = System.getProperty("photonics.lightingMode");
      String previousStoredValue = PhotonicsStorage.LIGHTING_MODE_OVERRIDE.value;

      try {
         System.clearProperty("photonics.lightingMode");
         PhotonicsStorage.LIGHTING_MODE_OVERRIDE.value = "LIGHT_TREE";

         PhotonicsStorage.applySystemPropertyOverrides();

         assertEquals("LIGHT_TREE", System.getProperty("photonics.lightingMode"));
      } finally {
         restoreProperty("photonics.lightingMode", previousProperty);
         PhotonicsStorage.LIGHTING_MODE_OVERRIDE.value = previousStoredValue;
      }
   }

   @Test
   void storedLightBinningAppliesWhenSystemPropertyIsMissing() {
      String previousProperty = System.getProperty("photonics.enableLightBinning");
      String previousNewProperty = System.getProperty("photonics.lightBinningEnabled");
      String previousStoredValue = PhotonicsStorage.LIGHT_BINNING_OVERRIDE.value;

      try {
         System.clearProperty("photonics.enableLightBinning");
         System.clearProperty("photonics.lightBinningEnabled");
         PhotonicsStorage.LIGHT_BINNING_OVERRIDE.value = "false";

         PhotonicsStorage.applySystemPropertyOverrides();

         assertEquals("false", System.getProperty("photonics.enableLightBinning"));
         assertEquals("false", System.getProperty("photonics.lightBinningEnabled"));
      } finally {
         restoreProperty("photonics.enableLightBinning", previousProperty);
         restoreProperty("photonics.lightBinningEnabled", previousNewProperty);
         PhotonicsStorage.LIGHT_BINNING_OVERRIDE.value = previousStoredValue;
      }
   }

   @Test
   void explicitNewLightBinningPropertyWinsOverStoredOverride() {
      String previousProperty = System.getProperty("photonics.lightBinningEnabled");
      String previousLegacyProperty = System.getProperty("photonics.enableLightBinning");
      String previousStoredValue = PhotonicsStorage.LIGHT_BINNING_OVERRIDE.value;

      try {
         System.setProperty("photonics.lightBinningEnabled", "true");
         System.clearProperty("photonics.enableLightBinning");
         PhotonicsStorage.LIGHT_BINNING_OVERRIDE.value = "false";

         PhotonicsStorage.applySystemPropertyOverrides();

         assertEquals("true", System.getProperty("photonics.lightBinningEnabled"));
      } finally {
         restoreProperty("photonics.lightBinningEnabled", previousProperty);
         restoreProperty("photonics.enableLightBinning", previousLegacyProperty);
         PhotonicsStorage.LIGHT_BINNING_OVERRIDE.value = previousStoredValue;
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
