package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.schematics.AirEntry;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import java.nio.IntBuffer;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PChunkPageLayoutTest {
   private static final int CHUNK_EDGE = 16;
   private static final int CHUNK_INT_COUNT = CHUNK_EDGE * CHUNK_EDGE * CHUNK_EDGE;
   private static final int WORLD_CHUNK_SIZE = 32;
   private static final int TOTAL_ROOT_INTS = WORLD_CHUNK_SIZE * WORLD_CHUNK_SIZE * WORLD_CHUNK_SIZE;

   @Test
   void chunkPageMatchesDenseMortonLayout() {
      PChunk chunk = new PChunk();
      assertEquals(CHUNK_INT_COUNT * Integer.BYTES, chunk.getSize());
   }

   @Test
   void emptyChunkPageContainsAirEntriesThatCoverRepresentativeVoxels() {
      PChunk chunk = new PChunk();
      GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test_chunk", chunk.getSize() * 2, true);
      chunk.allocate(chunkMemory);
      chunk.finishUpdate(chunkMemory);

      IntBuffer ints = chunk.getMemory().getBuffer().asIntBuffer();
      assertAirEntryContains(ints.get(Schematic.toSchematicIndex(0, 0, 0)), 0, 0, 0);
      assertAirEntryContains(ints.get(Schematic.toSchematicIndex(5, 6, 7)), 5, 6, 7);
      assertAirEntryContains(ints.get(Schematic.toSchematicIndex(15, 15, 15)), 15, 15, 15);

      chunk.free(chunkMemory);
      chunkMemory.free();
   }

   @Test
   void occupiedChunkEntryIsNegativeMemoryPointer() {
      GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test_chunk", 65536, true);
      PChunk chunk = new PChunk();
      chunk.allocate(chunkMemory);

      int expectedRootValue = -(chunk.getMemory().begin >> 2);
      assertTrue(expectedRootValue <= 0);
      assertTrue(AirEntry.isData(expectedRootValue));

      chunk.free(chunkMemory);
      chunkMemory.free();
   }

   @Test
   void mortonCodedSchematicIndexIsConsistentForAllRootPositions() {
      boolean[] seen = new boolean[TOTAL_ROOT_INTS];
      for (int y = 0; y < WORLD_CHUNK_SIZE; y++) {
         for (int x = 0; x < WORLD_CHUNK_SIZE; x++) {
            for (int z = 0; z < WORLD_CHUNK_SIZE; z++) {
               int index = Schematic.toSchematicIndex(x, y, z);
               assertTrue(index >= 0 && index < TOTAL_ROOT_INTS);
               assertTrue(!seen[index]);
               seen[index] = true;
            }
         }
      }

      for (boolean value : seen) {
         assertTrue(value);
      }
   }

   @Test
   void rootEntryUploadSliceCoversExactlyOneIntAtMortonIndex() {
      GlMemoryManager rootMem = new GlMemoryManager(GlTarget.SSBO, "test_root", TOTAL_ROOT_INTS * Integer.BYTES, false);
      MemoryRegion root = rootMem.allocate(TOTAL_ROOT_INTS * Integer.BYTES);

      int index = Schematic.toSchematicIndex(12, 7, 25);
      int neighborIndex = Schematic.toSchematicIndex(13, 7, 25);
      int neighborSentinel = 0x12345678;
      int testValue = -42;

      root.getBuffer().asIntBuffer().put(neighborIndex, neighborSentinel);
      MemoryRegion slice = root.slice(index * Integer.BYTES, Integer.BYTES);
      IntBuffer entryBuffer = slice.getBuffer().asIntBuffer();
      entryBuffer.position(0);
      entryBuffer.put(testValue);

      IntBuffer fullBuf = root.getBuffer().asIntBuffer();
      assertEquals(testValue, fullBuf.get(index));
      assertEquals(neighborSentinel, fullBuf.get(neighborIndex));

      rootMem.free();
   }

   private static void assertAirEntryContains(int airEntry, int x, int y, int z) {
      assertTrue(AirEntry.isAirEntry(airEntry));
      assertTrue(AirEntry.getX1(airEntry) <= x && x < AirEntry.getX2(airEntry));
      assertTrue(AirEntry.getY1(airEntry) <= y && y < AirEntry.getY2(airEntry));
      assertTrue(AirEntry.getZ1(airEntry) <= z && z < AirEntry.getZ2(airEntry));
   }
}
