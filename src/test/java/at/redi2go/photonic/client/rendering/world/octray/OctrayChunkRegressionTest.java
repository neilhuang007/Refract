package at.redi2go.photonic.client.rendering.world.octray;

import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.schematics.AirEntry;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.PBlock;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import java.nio.IntBuffer;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class OctrayChunkRegressionTest {
   @Test
   void finishUpdateClearsMipOccupancyAfterBlockRemoval() {
      GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test_chunk", 65536, true);
      GlMemoryManager blockMemory = new GlMemoryManager(GlTarget.SSBO, "test_block", PBlock.BYTE_SIZE * 4, true);
      OctrayChunk chunk = new OctrayChunk();
      PBlock block = new PBlock(7, () -> new Schematic(16, 16, 16));

      blockMemory.allocate(PBlock.BYTE_SIZE);
      block.allocate(blockMemory);
      chunk.allocate(chunkMemory);

      chunk.set(5, 6, 7, block, 3);
      chunk.finishUpdate(chunkMemory);

      IntBuffer ints = chunk.getMemory().getBuffer().asIntBuffer();
      assertTrue(ints.get(OctrayChunk.getSubChunkAddr(5, 6, 7, 1)) > 0);
      assertTrue(ints.get(OctrayChunk.getSubChunkAddr(5, 6, 7, 2)) > 0);
      assertTrue(ints.get(OctrayChunk.getSubChunkAddr(5, 6, 7, 3)) > 0);
      assertTrue(ints.get(OctrayChunk.getSubChunkAddr(5, 6, 7, 4)) > 0);

      chunk.afterUpload();
      chunk.set(5, 6, 7, null, -1);
      chunk.finishUpdate(chunkMemory);

      ints = chunk.getMemory().getBuffer().asIntBuffer();
      int leafIndex = Schematic.toSchematicIndex(5, 6, 7);
      assertEquals(AirEntry.toAirEntry(5, 6, 7, 6, 7, 8), ints.get(leafIndex));
      assertEquals(0, ints.get(OctrayChunk.getSubChunkAddr(5, 6, 7, 1)));
      assertEquals(0, ints.get(OctrayChunk.getSubChunkAddr(5, 6, 7, 2)));
      assertEquals(0, ints.get(OctrayChunk.getSubChunkAddr(5, 6, 7, 3)));
      assertEquals(0, ints.get(OctrayChunk.getSubChunkAddr(5, 6, 7, 4)));

      chunk.free(chunkMemory);
      block.free(blockMemory);
      chunkMemory.free();
      blockMemory.free();
   }

   @Test
   void freeBlocksRestoresAirLeafDataAndZeroMips() {
      GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test_chunk", 65536, true);
      GlMemoryManager blockMemory = new GlMemoryManager(GlTarget.SSBO, "test_block", PBlock.BYTE_SIZE * 4, true);
      OctrayChunk chunk = new OctrayChunk();
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
      assertEquals(AirEntry.toAirEntry(1, 2, 3, 2, 3, 4), ints.get(Schematic.toSchematicIndex(1, 2, 3)));
      for (int i = OctrayChunk.LEAF_INT_COUNT; i < OctrayChunk.CHUNK_PAGE_INT_COUNT; i++) {
         assertEquals(0, ints.get(i), "freeBlocks must clear all occupancy mip entries");
      }

      chunk.free(chunkMemory);
      block.free(blockMemory);
      chunkMemory.free();
      blockMemory.free();
   }

   @Test
   void overflowingBlockPointerFallsBackToAir() {
      GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test_chunk", 65536, true);
      GlMemoryManager blockMemory = new GlMemoryManager(GlTarget.SSBO, "test_block", (OctrayChunkRegressionTest.maxShaderIndexPlusOne() + 1) * PBlock.BYTE_SIZE, true);
      OctrayChunk chunk = new OctrayChunk();
      PBlock block = new PBlock(11, () -> new Schematic(16, 16, 16));

      blockMemory.allocate(maxShaderIndexPlusOne() * PBlock.BYTE_SIZE);
      block.allocate(blockMemory);
      chunk.allocate(chunkMemory);
      chunk.set(2, 3, 4, block, 6);
      chunk.finishUpdate(chunkMemory);

      IntBuffer ints = chunk.getMemory().getBuffer().asIntBuffer();
      int leafIndex = Schematic.toSchematicIndex(2, 3, 4);
      assertEquals(AirEntry.toAirEntry(2, 3, 4, 3, 4, 5), ints.get(leafIndex));
      assertEquals(0, ints.get(OctrayChunk.getSubChunkAddr(2, 3, 4, 1)));
      assertFalse(chunk.getMemory() == null);

      chunk.free(chunkMemory);
      block.free(blockMemory);
      chunkMemory.free();
      blockMemory.free();
   }

   @Test
   void finishUpdateEncodesSkyBrightnessInUpperBits() {
      GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test_chunk", 65536, true);
      GlMemoryManager blockMemory = new GlMemoryManager(GlTarget.SSBO, "test_block", PBlock.BYTE_SIZE * 4, true);
      OctrayChunk chunk = new OctrayChunk();
      PBlock block = new PBlock(13, () -> new Schematic(16, 16, 16));

      blockMemory.allocate(PBlock.BYTE_SIZE);
      block.allocate(blockMemory);
      chunk.allocate(chunkMemory);
      chunk.set(4, 5, 6, block, 7);
      chunk.finishUpdate(chunkMemory);

      IntBuffer ints = chunk.getMemory().getBuffer().asIntBuffer();
      int encoded = -ints.get(Schematic.toSchematicIndex(4, 5, 6));
      assertEquals(block.getMemory().begin / PBlock.BYTE_SIZE, encoded & 0xFFF);
      assertEquals(7, encoded >> 12);

      chunk.free(chunkMemory);
      block.free(blockMemory);
      chunkMemory.free();
      blockMemory.free();
   }

   private static int maxShaderIndexPlusOne() {
      return 0x1000;
   }
}
