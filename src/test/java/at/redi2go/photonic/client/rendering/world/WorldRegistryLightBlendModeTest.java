package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

@Disabled("Requires Minecraft/LWJGL runtime classpath")
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

   @Test
   void collectTrimEligibleChunksSkipsInboundWorkingSet() {
      List<PChunkPos> loaded = List.of(
         new PChunkPos(0, 0, 0),
         new PChunkPos(1, 0, 0),
         new PChunkPos(2, 0, 0),
         new PChunkPos(3, 0, 0),
         new PChunkPos(4, 0, 0)
      );

      List<PChunkPos> trimmed = WorldRegistry.collectTrimEligibleChunks(
         loaded,
         3,
         Set.of(new PChunkPos(3, 0, 0))
      );

      assertEquals(List.of(new PChunkPos(4, 0, 0)), trimmed);
   }

   @Test
   void localLightMutationUsesRegionalBlendInsteadOfFullTemporalReset() {
      assertFalse(WorldRegistry.shouldForceTemporalResetForLightMutation(false, 1));
      assertFalse(WorldRegistry.shouldForceTemporalResetForLightMutation(false, 4));
      assertFalse(WorldRegistry.shouldForceTemporalResetForLightMutation(false, 0));
   }

   @Test
   void topologyDrivenLightMutationStillForcesFullTemporalReset() {
      assertTrue(WorldRegistry.shouldForceTemporalResetForLightMutation(true, 1));
      assertTrue(WorldRegistry.shouldForceTemporalResetForLightMutation(true, 8));
      assertTrue(WorldRegistry.shouldForceTemporalResetForLightMutation(true, 0));
   }

   @Test
   void ordinaryWorldOffsetRecenteringDoesNotTriggerFullTemporalReset() {
      assertFalse(WorldRegistry.shouldForceTemporalResetForWorldOffset(
         new PChunkPos(10, 0, 10),
         new PChunkPos(11, 0, 10),
         32
      ));
      assertFalse(WorldRegistry.shouldForceTemporalResetForWorldOffset(
         new PChunkPos(10, 0, 10),
         new PChunkPos(14, 0, 12),
         32
      ));
   }

   @Test
   void hugeWorldOffsetJumpStillTriggersFullTemporalReset() {
      assertTrue(WorldRegistry.shouldForceTemporalResetForWorldOffset(
         new PChunkPos(0, 0, 0),
         new PChunkPos(32, 0, 0),
         32
      ));
   }

   @Test
   void resetReasonMatchingTreatsCombinedPendingReasonsAsAlreadyPresent() {
      assertTrue(WorldRegistry.hasResetReason("light_set", "light_set"));
      assertTrue(WorldRegistry.hasResetReason("initial+light_set", "light_set"));
      assertTrue(WorldRegistry.hasResetReason("world_offset+camera_jump+light_set", "camera_jump"));
      assertFalse(WorldRegistry.hasResetReason("initial+light_set", "topology"));
      assertFalse(WorldRegistry.hasResetReason("", "light_set"));
   }
}
