package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.schematics.AirEntry;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import java.nio.IntBuffer;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;

class PChunkRegressionTest {
   @Test
   void finishUpdateRestoresAirAfterBlockRemoval() {
      GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test_chunk", 65536, true);
      GlMemoryManager blockMemory = new GlMemoryManager(GlTarget.SSBO, "test_block", PBlock.BYTE_SIZE * 4, true);
      PChunk chunk = new PChunk();
      PBlock block = new PBlock(7, () -> new Schematic(16, 16, 16));

      blockMemory.allocate(PBlock.BYTE_SIZE);
      block.allocate(blockMemory);
      chunk.allocate(chunkMemory);

      chunk.set(5, 6, 7, block, 3);
      chunk.finishUpdate(chunkMemory);
      chunk.afterUpload();
      chunk.set(5, 6, 7, null, -1);
      chunk.finishUpdate(chunkMemory);

      IntBuffer ints = chunk.getMemory().getBuffer().asIntBuffer();
      int leafIndex = Schematic.toSchematicIndex(5, 6, 7);
      assertEquals(AirEntry.toAirEntry(5, 6, 7, 6, 7, 8), ints.get(leafIndex));

      chunk.free(chunkMemory);
      block.free(blockMemory);
      chunkMemory.free();
      blockMemory.free();
   }

   @Test
   void freeBlocksRestoresAirLeafData() {
      GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test_chunk", 65536, true);
      GlMemoryManager blockMemory = new GlMemoryManager(GlTarget.SSBO, "test_block", PBlock.BYTE_SIZE * 4, true);
      PChunk chunk = new PChunk();
      PBlock block = new PBlock(9, () -> new Schematic(16, 16, 16));

      blockMemory.allocate(PBlock.BYTE_SIZE);
      block.allocate(blockMemory);
      chunk.allocate(chunkMemory);

      chunk.set(1, 2, 3, block, 4);
      chunk.finishUpdate(chunkMemory);
      chunk.afterUpload();
      chunk.freeBlocks();
      chunk.finishUpdate(chunkMemory);

      IntBuffer ints = chunk.getMemory().getBuffer().asIntBuffer();
      assertAirEntryContains(ints.get(Schematic.toSchematicIndex(1, 2, 3)), 1, 2, 3);

      chunk.free(chunkMemory);
      block.free(blockMemory);
      chunkMemory.free();
      blockMemory.free();
   }

   @Test
   void overflowingBlockPointerFallsBackToAir() {
      GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test_chunk", 65536, true);
      GlMemoryManager blockMemory = new GlMemoryManager(GlTarget.SSBO, "test_block", (0x1000 + 2) * PBlock.BYTE_SIZE, true);
      PChunk chunk = new PChunk();
      PBlock block = new PBlock(11, () -> new Schematic(16, 16, 16));

      blockMemory.allocate((0x1000 + 1) * PBlock.BYTE_SIZE);
      block.allocate(blockMemory);
      chunk.allocate(chunkMemory);
      chunk.set(2, 3, 4, block, 6);
      chunk.finishUpdate(chunkMemory);

      IntBuffer ints = chunk.getMemory().getBuffer().asIntBuffer();
      int leafIndex = Schematic.toSchematicIndex(2, 3, 4);
      assertAirEntryContains(ints.get(leafIndex), 2, 3, 4);
      assertFalse(chunk.getMemory() == null);

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
