package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.world.buffer.MemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import at.redi2go.photonics.core.model.VoxelEntry;
import java.nio.IntBuffer;
import java.util.Arrays;
import java.util.concurrent.CompletableFuture;

public class ReferenceChunk implements WorldChunk {
   static final int chunkEdge = 16;
   static final int brickIntCount = chunkEdge * chunkEdge * chunkEdge;
   static final int byteSize = brickIntCount * Integer.BYTES;
   private final int[] brickData = new int[brickIntCount];
   private MemoryRegion chunkMemory;
   private boolean dirty = true;
   private int dirtyVoxelWrites = 0;

   public ReferenceChunk() {
      this.resetBrickData();
   }

   @Override
   public void freeBlocks() {
      this.resetBrickData();
      this.dirtyVoxelWrites = brickIntCount;
      this.dirty = true;
   }


   @Override
   public boolean setPackedEntry(int x, int y, int z, int packedEntry) {
      int index = at.redi2go.photonic.client.rendering.schematics.Schematic.toSchematicIndex(x, y, z);
      int newValue = packedEntry == 0
         ? VoxelEntry.toAir(x, y, z, x + 1, y + 1, z + 1)
         : VoxelEntry.toData(packedEntry);
      if (this.brickData[index] == newValue) {
         return false;
      }

      this.brickData[index] = newValue;
      this.dirtyVoxelWrites++;
      this.dirty = true;
      return true;
   }

   @Override
   public CompletableFuture<Void> optimizeAsync() {
      return CompletableFuture.completedFuture(null);
   }

   @Override
   public void finishUpdate(MemoryManager memoryManager) {
      if (!this.dirty || this.chunkMemory == null) {
         return;
      }

      IntBuffer buffer = this.chunkMemory.getBuffer().asIntBuffer();
      buffer.position(0);
      buffer.put(this.brickData);
      memoryManager.queueUpload(this);
   }

   @Override
   public boolean isDirty() {
      return this.dirty;
   }

   @Override
   public void allocate(MemoryManager memoryManager) {
      this.chunkMemory = memoryManager.allocate(this.getSize());
   }

   @Override
   public void free(MemoryManager memoryManager) {
      if (this.chunkMemory != null) {
         memoryManager.free(this.chunkMemory);
         this.chunkMemory = null;
      }
   }

   @Override
   public boolean update(MemoryManager memoryManager) {
      if (!this.dirty) {
         return false;
      }

      this.finishUpdate(memoryManager);
      return true;
   }

   @Override
   public void afterUpload() {
      this.dirty = false;
      this.dirtyVoxelWrites = 0;
   }

   int getDirtyVoxelWrites() {
      return this.dirtyVoxelWrites;
   }

   @Override
   public int getSize() {
      return byteSize;
   }

   @Override
   public MemoryRegion getMemory() {
      return this.chunkMemory;
   }

   private void resetBrickData() {
      Arrays.fill(this.brickData, 0);
      for (int y = 0; y < chunkEdge; y++) {
         for (int x = 0; x < chunkEdge; x++) {
            for (int z = 0; z < chunkEdge; z++) {
               this.brickData[at.redi2go.photonic.client.rendering.schematics.Schematic.toSchematicIndex(x, y, z)] = VoxelEntry.toAir(x, y, z, x + 1, y + 1, z + 1);
            }
         }
      }
   }
}
