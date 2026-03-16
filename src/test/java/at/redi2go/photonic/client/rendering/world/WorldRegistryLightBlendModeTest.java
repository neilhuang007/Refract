package at.redi2go.photonic.client.rendering.world;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class WorldRegistryLightBlendModeTest {
   @Test
   void regionalBlendDoesNotTriggerGlobalLightReload() {
      assertFalse(WorldRegistry.isGlobalLightReloadActive(8, false));
      assertFalse(WorldRegistry.isGlobalLightReloadActive(1, false));
   }

   @Test
   void fullBlendResetTriggersGlobalLightReloadOnlyWhileActive() {
      assertTrue(WorldRegistry.isGlobalLightReloadActive(8, true));
      assertTrue(WorldRegistry.isGlobalLightReloadActive(1, true));
      assertFalse(WorldRegistry.isGlobalLightReloadActive(0, true));
   }
}
