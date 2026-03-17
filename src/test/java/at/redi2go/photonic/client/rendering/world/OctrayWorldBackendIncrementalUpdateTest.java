package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.schematics.AirEntry;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import java.nio.IntBuffer;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class LegacyWorldBackendDirectRootMappingTest {
   private static final int WORLD_CHUNK_SIZE = 32;
   private static final int TOTAL_ROOT_INTS = WORLD_CHUNK_SIZE * WORLD_CHUNK_SIZE * WORLD_CHUNK_SIZE;

   @Test
   void rebuildRootDataMapsChunksDirectlyToWorldRelativeRootCells() {
      Map<PChunkPos, WorldChunk> chunks = new HashMap<>();
      LegacyWorldBackend backend = new LegacyWorldBackend(WORLD_CHUNK_SIZE, chunks, 4096);
      MemoryRegion rootMemory = backend.getRootMemoryManager().allocate(TOTAL_ROOT_INTS * Integer.BYTES);
      backend.setRootMemory(rootMemory);

      StubWorldChunk chunkA = new StubWorldChunk(backend.getCbMemoryManager().allocate(64));
      StubWorldChunk chunkB = new StubWorldChunk(backend.getCbMemoryManager().allocate(64));
      PChunkPos worldOffset = new PChunkPos(10, 20, 30);
      chunks.put(new PChunkPos(11, 22, 33), chunkA);
      chunks.put(new PChunkPos(14, 25, 36), chunkB);

      int[] rootData = backend.getRootSchematic().getData();
      for (int i = 0; i < rootData.length; i++) {
         rootData[i] = -1;
      }

      rebuildRootData(backend, worldOffset);

      IntBuffer updatedRoot = rootMemory.getBuffer().asIntBuffer();
      int indexA = Schematic.toSchematicIndex(1, 2, 3);
      int indexB = Schematic.toSchematicIndex(4, 5, 6);
      int untouchedIndex = Schematic.toSchematicIndex(7, 8, 9);
      assertEquals(-(chunkA.getMemory().begin >> 2), updatedRoot.get(indexA));
      assertEquals(-(chunkB.getMemory().begin >> 2), updatedRoot.get(indexB));
      assertEquals(AirEntry.toAirEntry(7, 8, 9, 8, 9, 10), updatedRoot.get(untouchedIndex));

      backend.free();
   }

   @Test
   void rebuildRootDataResetsOldMappingsBackToAir() {
      Map<PChunkPos, WorldChunk> chunks = new HashMap<>();
      LegacyWorldBackend backend = new LegacyWorldBackend(WORLD_CHUNK_SIZE, chunks, 4096);
      MemoryRegion rootMemory = backend.getRootMemoryManager().allocate(TOTAL_ROOT_INTS * Integer.BYTES);
      backend.setRootMemory(rootMemory);
      PChunkPos worldOffset = new PChunkPos(0, 0, 0);

      StubWorldChunk chunk = new StubWorldChunk(backend.getCbMemoryManager().allocate(64));
      PChunkPos worldChunkPos = new PChunkPos(2, 3, 4);
      chunks.put(worldChunkPos, chunk);
      rebuildRootData(backend, worldOffset);

      chunks.clear();
      rebuildRootData(backend, worldOffset);

      IntBuffer updatedRoot = rootMemory.getBuffer().asIntBuffer();
      assertEquals(AirEntry.toAirEntry(2, 3, 4, 3, 4, 5), updatedRoot.get(Schematic.toSchematicIndex(2, 3, 4)));

      backend.free();
   }

   private static void rebuildRootData(LegacyWorldBackend backend, PChunkPos rtToWorldChunkOffset) {
      int[] rootData = backend.getRootSchematic().getData();
      for (int y = 0; y < WORLD_CHUNK_SIZE; y++) {
         for (int x = 0; x < WORLD_CHUNK_SIZE; x++) {
            for (int z = 0; z < WORLD_CHUNK_SIZE; z++) {
               rootData[Schematic.toSchematicIndex(x, y, z)] = AirEntry.toAirEntry(x, y, z, x + 1, y + 1, z + 1);
            }
         }
      }

      for (Map.Entry<PChunkPos, WorldChunk> entry : backend.getChunks().entrySet()) {
         PChunkPos worldChunkPos = entry.getKey();
         int rtX = worldChunkPos.x - rtToWorldChunkOffset.x;
         int rtY = worldChunkPos.y - rtToWorldChunkOffset.y;
         int rtZ = worldChunkPos.z - rtToWorldChunkOffset.z;
         if (rtX < 0 || rtY < 0 || rtZ < 0 || rtX >= WORLD_CHUNK_SIZE || rtY >= WORLD_CHUNK_SIZE || rtZ >= WORLD_CHUNK_SIZE) {
            continue;
         }
         rootData[Schematic.toSchematicIndex(rtX, rtY, rtZ)] = -(entry.getValue().getMemory().begin >> 2);
      }

      IntBuffer rootBuffer = backend.getRootMemory().getBuffer().asIntBuffer();
      rootBuffer.position(0);
      rootBuffer.put(rootData);
   }

   private static final class StubWorldChunk implements WorldChunk {
      private final MemoryRegion memory;

      private StubWorldChunk(MemoryRegion memory) {
         this.memory = memory;
      }

      @Override
      public void freeBlocks() {
      }

      @Override
      public void set(int x, int y, int z, PBlock block, int skyBrightness) {
      }

      @Override
      public CompletableFuture<Void> optimizeAsync() {
         return CompletableFuture.completedFuture(null);
      }

      @Override
      public void finishUpdate(MemoryManager memoryManager) {
      }

      @Override
      public boolean isDirty() {
         return false;
      }

      @Override
      public void allocate(MemoryManager memoryManager) {
      }

      @Override
      public void free(MemoryManager memoryManager) {
      }

      @Override
      public boolean update(MemoryManager memoryManager) {
         return false;
      }

      @Override
      public void afterUpload() {
      }

      @Override
      public int getSize() {
         return this.memory.end - this.memory.begin;
      }

      @Override
      public MemoryRegion getMemory() {
         return this.memory;
      }
   }
}
