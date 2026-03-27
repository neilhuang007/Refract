package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.schematics.AirEntry;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import java.lang.reflect.Field;
import java.nio.IntBuffer;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class BrickChunkTest {
   @Test
   void finishUpdateWritesDenseBrickEntriesOnly() {
      GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test_chunk", 65536, true);
      GlMemoryManager blockMemory = new GlMemoryManager(GlTarget.SSBO, "test_block", PBlock.BYTE_SIZE * 4, true);
      BrickChunk chunk = new BrickChunk();
      PBlock block = new PBlock(7, () -> new Schematic(16, 16, 16));

      blockMemory.allocate(PBlock.BYTE_SIZE);
      block.allocate(blockMemory);
      chunk.allocate(chunkMemory);
      chunk.set(1, 2, 3, block, 5);
      chunk.finishUpdate(chunkMemory);

      IntBuffer ints = chunk.getMemory().getBuffer().asIntBuffer();
      int shaderBlockIndex = block.getMemory().begin / PBlock.BYTE_SIZE;
      int encodedBlock = shaderBlockIndex | (5 << 13);
      int leafIndex = Schematic.toSchematicIndex(1, 2, 3);

      assertEquals(4096, ints.limit());
      assertEquals(-encodedBlock, ints.get(leafIndex));
      assertEquals(AirEntry.toAirEntry(0, 0, 0, 1, 1, 1), ints.get(Schematic.toSchematicIndex(0, 0, 0)));

      chunk.free(chunkMemory);
      block.free(blockMemory);
      chunkMemory.free();
      blockMemory.free();
   }

   @Test
   void freeBlocksRestoresDenseAirEntries() {
      GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test_chunk", 65536, true);
      GlMemoryManager blockMemory = new GlMemoryManager(GlTarget.SSBO, "test_block", PBlock.BYTE_SIZE * 4, true);
      BrickChunk chunk = new BrickChunk();
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
      assertTrue(chunk.isDirty());

      chunk.free(chunkMemory);
      block.free(blockMemory);
      chunkMemory.free();
      blockMemory.free();
   }

   @Test
   void setDoesNotLeakReferencesOnNoopWrites() throws Exception {
      GlMemoryManager blockMemory = new GlMemoryManager(GlTarget.SSBO, "test_block", PBlock.BYTE_SIZE * 4, true);
      BrickChunk chunk = new BrickChunk();
      PBlock block = new PBlock(9, () -> new Schematic(16, 16, 16));

      blockMemory.allocate(PBlock.BYTE_SIZE);
      block.allocate(blockMemory);

      assertTrue(chunk.set(1, 2, 3, block, 4));
      assertFalse(chunk.set(1, 2, 3, block, 4));
      assertEquals(1, chunk.getTrackedBlockReferenceCount());
      assertEquals(1, getTimesUsed(block));

      block.free(blockMemory);
      blockMemory.free();
   }

   @Test
   void setPreservesReferenceCountsWhenOnlySkyLightChanges() throws Exception {
      GlMemoryManager blockMemory = new GlMemoryManager(GlTarget.SSBO, "test_block", PBlock.BYTE_SIZE * 4, true);
      BrickChunk chunk = new BrickChunk();
      PBlock block = new PBlock(9, () -> new Schematic(16, 16, 16));

      blockMemory.allocate(PBlock.BYTE_SIZE);
      block.allocate(blockMemory);

      assertTrue(chunk.set(1, 2, 3, block, 4));
      assertTrue(chunk.set(1, 2, 3, block, 5));
      assertEquals(1, chunk.getTrackedBlockReferenceCount());
      assertEquals(1, getTimesUsed(block));

      block.free(blockMemory);
      blockMemory.free();
   }

   private static int getTimesUsed(PBlock block) throws Exception {
      Field field = PBlock.class.getDeclaredField("timesUsed");
      field.setAccessible(true);
      return (int) field.get(block);
   }
}
