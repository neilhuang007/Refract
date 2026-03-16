package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.world.position.PBlockPos;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class WorldRegistryChunkPriorityTest {
   @Test
   void pChunkPosToBlockPosConversionIs16xMultiple() {
      PChunkPos chunkPos = new PChunkPos(3, -2, 5);
      PBlockPos blockPos = chunkPos.toBlockPos();
      assertTrue(blockPos.x == 48, "x must be 3*16=48");
      assertTrue(blockPos.y == -32, "y must be -2*16=-32");
      assertTrue(blockPos.z == 80, "z must be 5*16=80");
   }

   @Test
   void pBlockPosToChunkPosUsesFloorDiv() {
      PBlockPos blockPos = new PBlockPos(-1, 15, 32);
      PChunkPos chunkPos = blockPos.toChunkPos();
      assertTrue(chunkPos.x == -1, "floorDiv(-1, 16) must be -1");
      assertTrue(chunkPos.y == 0, "floorDiv(15, 16) must be 0");
      assertTrue(chunkPos.z == 2, "floorDiv(32, 16) must be 2");
   }
}
