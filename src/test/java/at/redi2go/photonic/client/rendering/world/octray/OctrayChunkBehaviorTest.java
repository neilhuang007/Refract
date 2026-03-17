package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.schematics.AirEntry;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import java.nio.IntBuffer;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class PChunkBehaviorTest {
   @Test
   void fullyEmptyChunkHasAirEntriesThatCoverEveryVoxel() {
      GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test", 65536, true);
      PChunk chunk = new PChunk();
      chunk.allocate(chunkMemory);
      chunk.finishUpdate(chunkMemory);

      IntBuffer ints = chunk.getMemory().getBuffer().asIntBuffer();
      for (int y = 0; y < 16; y++) {
         for (int x = 0; x < 16; x++) {
            for (int z = 0; z < 16; z++) {
               assertAirEntryContains(ints.get(Schematic.toSchematicIndex(x, y, z)), x, y, z);
            }
         }
      }

      chunk.free(chunkMemory);
      chunkMemory.free();
   }

   @Test
   void occupiedBlockUpdatesOnlyItsMortonCell() {
      GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test", 65536, true);
      GlMemoryManager blockMemory = new GlMemoryManager(GlTarget.SSBO, "test_blk", PBlock.BYTE_SIZE * 4, true);
      PChunk chunk = new PChunk();
      PBlock block = new PBlock(2, () -> new Schematic(16, 16, 16));
      blockMemory.allocate(PBlock.BYTE_SIZE);
      block.allocate(blockMemory);
      chunk.allocate(chunkMemory);

      chunk.set(3, 5, 7, block, 0);
      chunk.finishUpdate(chunkMemory);

      IntBuffer ints = chunk.getMemory().getBuffer().asIntBuffer();
      assertEquals(-(block.getMemory().begin / PBlock.BYTE_SIZE), -ints.get(Schematic.toSchematicIndex(3, 5, 7)));
      assertAirEntryContains(ints.get(Schematic.toSchematicIndex(3, 5, 6)), 3, 5, 6);
      assertAirEntryContains(ints.get(Schematic.toSchematicIndex(2, 5, 7)), 2, 5, 7);

      chunk.free(chunkMemory);
      block.free(blockMemory);
      chunkMemory.free();
      blockMemory.free();
   }

   private static void assertAirEntryContains(int airEntry, int x, int y, int z) {
      assertEquals(true, AirEntry.isAirEntry(airEntry));
      assertEquals(true, AirEntry.getX1(airEntry) <= x && x < AirEntry.getX2(airEntry));
      assertEquals(true, AirEntry.getY1(airEntry) <= y && y < AirEntry.getY2(airEntry));
      assertEquals(true, AirEntry.getZ1(airEntry) <= z && z < AirEntry.getZ2(airEntry));
   }
}
