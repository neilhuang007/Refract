package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.schematics.AirEntry;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import at.redi2go.photonic.client.rendering.world.octray.OctrayChunk;
import java.nio.IntBuffer;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class OctrayRootDataLayoutTest {
   private static final int WORLD_CHUNK_SIZE = 32;
   private static final int TOTAL_ROOT_INTS = WORLD_CHUNK_SIZE * WORLD_CHUNK_SIZE * WORLD_CHUNK_SIZE;

   @Test
   void emptyRootDataContainsExpectedPerCellAirEncodings() {
      int[] rootData = new int[TOTAL_ROOT_INTS];
      for (int y = 0; y < WORLD_CHUNK_SIZE; y++) {
         for (int x = 0; x < WORLD_CHUNK_SIZE; x++) {
            for (int z = 0; z < WORLD_CHUNK_SIZE; z++) {
               rootData[Schematic.toSchematicIndex(x, y, z)] = AirEntry.toAirEntry(x, y, z, x + 1, y + 1, z + 1);
            }
         }
      }

      for (int y = 0; y < WORLD_CHUNK_SIZE; y++) {
         for (int x = 0; x < WORLD_CHUNK_SIZE; x++) {
            for (int z = 0; z < WORLD_CHUNK_SIZE; z++) {
               int value = rootData[Schematic.toSchematicIndex(x, y, z)];
               assertEquals(x, AirEntry.getX1(value));
               assertEquals(y, AirEntry.getY1(value));
               assertEquals(z, AirEntry.getZ1(value));
               assertEquals(x + 1, AirEntry.getX2(value));
               assertEquals(y + 1, AirEntry.getY2(value));
               assertEquals(z + 1, AirEntry.getZ2(value));
            }
         }
      }
   }

   @Test
   void occupiedChunkEntryIsNegativeMemoryPointer() {
      GlMemoryManager chunkMem = new GlMemoryManager(GlTarget.SSBO, "test_chunk", 65536, true);
      OctrayChunk chunk = new OctrayChunk();
      chunk.allocate(chunkMem);

      int expectedRootValue = -(chunk.getMemory().begin >> 2);
      assertTrue(expectedRootValue <= 0);
      assertTrue(AirEntry.isData(expectedRootValue));

      chunk.free(chunkMem);
      chunkMem.free();
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
      int testValue = -42;

      MemoryRegion slice = root.slice(index * Integer.BYTES, Integer.BYTES);
      IntBuffer entryBuffer = slice.getBuffer().asIntBuffer();
      entryBuffer.position(0);
      entryBuffer.put(testValue);

      IntBuffer fullBuf = root.getBuffer().asIntBuffer();
      assertEquals(testValue, fullBuf.get(index));
      assertEquals(0, fullBuf.get(Schematic.toSchematicIndex(13, 7, 25)));

      rootMem.free();
   }
}
