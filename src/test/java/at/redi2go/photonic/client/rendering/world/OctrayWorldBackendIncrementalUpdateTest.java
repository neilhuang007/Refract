package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.schematics.AirEntry;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import java.nio.IntBuffer;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class OctrayWorldBackendIncrementalUpdateTest {
   private static final int WORLD_CHUNK_SIZE = 32;
   private static final int TOTAL_ROOT_INTS = WORLD_CHUNK_SIZE * WORLD_CHUNK_SIZE * WORLD_CHUNK_SIZE;
   private static final int INITIAL_SENTINEL = 0x13579BDF;
   private static final int NO_OP_SENTINEL = 0x2468ACE0;

   @Test
   void incrementalRootUpdateWritesOnlyDirtyEntriesAtMortonIndicesAndClearsDirtySet() {
      Map<PChunkPos, WorldChunk> chunks = new HashMap<>();
      OctrayWorldBackend backend = new OctrayWorldBackend(WORLD_CHUNK_SIZE, chunks, 4096);
      MemoryRegion rootMemory = backend.getRootMemoryManager().allocate(TOTAL_ROOT_INTS * Integer.BYTES);
      backend.setRootMemory(rootMemory);
      fillInts(rootMemory, INITIAL_SENTINEL);

      StubWorldChunk chunkA = new StubWorldChunk(backend.getCbMemoryManager().allocate(64));
      StubWorldChunk chunkB = new StubWorldChunk(backend.getCbMemoryManager().allocate(64));
      PChunkPos worldOffset = new PChunkPos(10, 20, 30);
      PChunkPos rtChunkA = new PChunkPos(1, 2, 3);
      PChunkPos rtChunkB = new PChunkPos(4, 5, 6);
      chunks.put(new PChunkPos(11, 22, 33), chunkA);
      chunks.put(new PChunkPos(14, 25, 36), chunkB);

      backend.markRtRootEntryDirty(rtChunkA, WORLD_CHUNK_SIZE);
      backend.markRtRootEntryDirty(rtChunkB, WORLD_CHUNK_SIZE);
      backend.updateRootData(worldOffset, WORLD_CHUNK_SIZE, false);

      IntBuffer updatedRoot = rootMemory.getBuffer().asIntBuffer();
      int indexA = Schematic.toSchematicIndex(rtChunkA.x, rtChunkA.y, rtChunkA.z);
      int indexB = Schematic.toSchematicIndex(rtChunkB.x, rtChunkB.y, rtChunkB.z);
      int untouchedIndex = Schematic.toSchematicIndex(7, 8, 9);
      assertEquals(-(chunkA.getMemory().begin >> 2), updatedRoot.get(indexA));
      assertEquals(-(chunkB.getMemory().begin >> 2), updatedRoot.get(indexB));
      assertEquals(INITIAL_SENTINEL, updatedRoot.get(untouchedIndex));

      fillInts(rootMemory, NO_OP_SENTINEL);
      backend.updateRootData(worldOffset, WORLD_CHUNK_SIZE, false);

      IntBuffer noOpRoot = rootMemory.getBuffer().asIntBuffer();
      assertEquals(NO_OP_SENTINEL, noOpRoot.get(indexA));
      assertEquals(NO_OP_SENTINEL, noOpRoot.get(indexB));
      assertEquals(NO_OP_SENTINEL, noOpRoot.get(untouchedIndex));

      backend.free();
   }


   @Test
   void largeDirtyRootSetsFallBackToSingleBulkUpload() {
      Map<PChunkPos, WorldChunk> chunks = new HashMap<>();
      OctrayWorldBackend backend = new OctrayWorldBackend(WORLD_CHUNK_SIZE, chunks, 16384);
      MemoryRegion rootMemory = backend.getRootMemoryManager().allocate(TOTAL_ROOT_INTS * Integer.BYTES);
      backend.setRootMemory(rootMemory);
      PChunkPos worldOffset = new PChunkPos(0, 0, 0);

      backend.updateRootData(worldOffset, WORLD_CHUNK_SIZE, true);
      fillInts(rootMemory, NO_OP_SENTINEL);

      for (int i = 0; i < 64; i++) {
         PChunkPos rtChunkPos = new PChunkPos(i & 31, (i >> 5) & 31, (i >> 10) & 31);
         StubWorldChunk chunk = new StubWorldChunk(backend.getCbMemoryManager().allocate(64));
         chunks.put(new PChunkPos(rtChunkPos.x, rtChunkPos.y, rtChunkPos.z), chunk);
         backend.markRtRootEntryDirty(rtChunkPos, WORLD_CHUNK_SIZE);
      }

      backend.updateRootData(worldOffset, WORLD_CHUNK_SIZE, false);

      IntBuffer updatedRoot = rootMemory.getBuffer().asIntBuffer();
      int touchedIndex = Schematic.toSchematicIndex(0, 0, 0);
      int untouchedIndex = Schematic.toSchematicIndex(31, 31, 31);
      assertEquals(-(chunks.get(new PChunkPos(0, 0, 0)).getMemory().begin >> 2), updatedRoot.get(touchedIndex));
      assertEquals(AirEntry.toAirEntry(31, 31, 31, 32, 32, 32), updatedRoot.get(untouchedIndex));

      backend.free();
   }
   private static void fillInts(MemoryRegion memoryRegion, int value) {
      IntBuffer buffer = memoryRegion.getBuffer().asIntBuffer();
      for (int i = 0; i < TOTAL_ROOT_INTS; i++) {
         buffer.put(i, value);
      }
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
