package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.world.position.PBlockPos;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

@Disabled("Requires Minecraft/LWJGL runtime classpath")
class WorldRegistryLightBlendRegionTest {
   @Test
   void disjointRegionsStaySeparateWhileCapacityRemains() {
      PBlockPos[] mins = new PBlockPos[WorldRegistry.MAX_LIGHT_BLEND_REGIONS];
      PBlockPos[] maxs = new PBlockPos[WorldRegistry.MAX_LIGHT_BLEND_REGIONS];

      int count = WorldRegistry.appendLightBlendRegion(mins, maxs, 0, WorldRegistry.MAX_LIGHT_BLEND_REGIONS, 0, 0, 0, 16, 16, 16);
      count = WorldRegistry.appendLightBlendRegion(mins, maxs, count, WorldRegistry.MAX_LIGHT_BLEND_REGIONS, 256, 0, 0, 272, 16, 16);

      assertEquals(2, count);
      assertEquals(new PBlockPos(0, 0, 0), mins[0]);
      assertEquals(new PBlockPos(16, 16, 16), maxs[0]);
      assertEquals(new PBlockPos(256, 0, 0), mins[1]);
      assertEquals(new PBlockPos(272, 16, 16), maxs[1]);
   }

   @Test
   void containedRegionsCollapseIntoSingleBounds() {
      PBlockPos[] mins = new PBlockPos[WorldRegistry.MAX_LIGHT_BLEND_REGIONS];
      PBlockPos[] maxs = new PBlockPos[WorldRegistry.MAX_LIGHT_BLEND_REGIONS];

      int count = WorldRegistry.appendLightBlendRegion(mins, maxs, 0, WorldRegistry.MAX_LIGHT_BLEND_REGIONS, 0, -4, 0, 24, 20, 24);
      count = WorldRegistry.appendLightBlendRegion(mins, maxs, count, WorldRegistry.MAX_LIGHT_BLEND_REGIONS, 8, 0, 8, 16, 16, 16);

      assertEquals(1, count);
      assertEquals(new PBlockPos(0, -4, 0), mins[0]);
      assertEquals(new PBlockPos(24, 20, 24), maxs[0]);
   }

   @Test
   void capacityPressureMergesIntoLowestExpansionRegion() {
      PBlockPos[] mins = new PBlockPos[WorldRegistry.MAX_LIGHT_BLEND_REGIONS];
      PBlockPos[] maxs = new PBlockPos[WorldRegistry.MAX_LIGHT_BLEND_REGIONS];

      int count = WorldRegistry.appendLightBlendRegion(mins, maxs, 0, 2, 0, 0, 0, 16, 16, 16);
      count = WorldRegistry.appendLightBlendRegion(mins, maxs, count, 2, 1024, 0, 0, 1040, 16, 16);
      count = WorldRegistry.appendLightBlendRegion(mins, maxs, count, 2, 24, 0, 0, 40, 16, 16);

      assertEquals(2, count);
      assertEquals(new PBlockPos(0, 0, 0), mins[0]);
      assertEquals(new PBlockPos(40, 16, 16), maxs[0]);
      assertEquals(new PBlockPos(1024, 0, 0), mins[1]);
      assertEquals(new PBlockPos(1040, 16, 16), maxs[1]);
   }
}
