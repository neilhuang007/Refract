package at.redi2go.photonic.client.rendering.world.octray;

import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.PBlock;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import java.nio.IntBuffer;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class OctrayChunkLayoutTest {
   @Test
   void chunkPageMatchesExpectedMipLayout() {
      OctrayChunk chunk = new OctrayChunk();
      assertEquals(4096, OctrayChunk.LEAF_INT_COUNT);
      assertEquals(4096, OctrayChunk.LOD1_OFFSET);
      assertEquals(4608, OctrayChunk.LOD2_OFFSET);
      assertEquals(4672, OctrayChunk.LOD3_OFFSET);
      assertEquals(4680, OctrayChunk.LOD4_OFFSET);
      assertEquals(4681, OctrayChunk.CHUNK_PAGE_INT_COUNT);
      assertEquals(4681 * Integer.BYTES, chunk.getSize());
   }

   @Test
   void subChunkAddressingMatchesOctrayStyleAxisStrides() {
      assertEquals(4096, OctrayChunk.getSubChunkAddr(0, 0, 0, 1));
      assertEquals(4104, OctrayChunk.getSubChunkAddr(2, 0, 0, 1));
      assertEquals(4160, OctrayChunk.getSubChunkAddr(0, 2, 0, 1));
      assertEquals(4097, OctrayChunk.getSubChunkAddr(0, 0, 2, 1));
      assertEquals(4680, OctrayChunk.getSubChunkAddr(15, 15, 15, 4));
   }

   @Test
   void finishUpdateWritesLegacyDenseEntriesAndAppendedOccupancyMips() {
      GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test_chunk", 65536, true);
      GlMemoryManager blockMemory = new GlMemoryManager(GlTarget.SSBO, "test_block", PBlock.BYTE_SIZE * 4, true);
      OctrayChunk chunk = new OctrayChunk();
      PBlock block = new PBlock(7, () -> new Schematic(16, 16, 16));

      blockMemory.allocate(PBlock.BYTE_SIZE);
      block.allocate(blockMemory);
      chunk.allocate(chunkMemory);
      chunk.set(1, 2, 3, block, 5);
      chunk.finishUpdate(chunkMemory);

      IntBuffer ints = chunk.getMemory().getBuffer().asIntBuffer();
      int shaderBlockIndex = block.getMemory().begin / PBlock.BYTE_SIZE;
      int encodedBlock = shaderBlockIndex | (5 << 12);
      int leafIndex = Schematic.toSchematicIndex(1, 2, 3);

      assertEquals(-encodedBlock, ints.get(leafIndex));
      assertTrue(ints.get(OctrayChunk.getSubChunkAddr(1, 2, 3, 1)) > 0);
      assertTrue(ints.get(OctrayChunk.getSubChunkAddr(1, 2, 3, 2)) > 0);
      assertTrue(ints.get(OctrayChunk.getSubChunkAddr(1, 2, 3, 3)) > 0);
      assertTrue(ints.get(OctrayChunk.getSubChunkAddr(1, 2, 3, 4)) > 0);

      chunk.free(chunkMemory);
      block.free(blockMemory);
      chunkMemory.free();
      blockMemory.free();
   }
}
