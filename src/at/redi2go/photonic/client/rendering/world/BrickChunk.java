package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.rendering.schematics.AirEntry;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import it.unimi.dsi.fastutil.objects.Object2IntMap;
import it.unimi.dsi.fastutil.objects.Object2IntOpenHashMap;
import java.nio.IntBuffer;
import java.util.Arrays;
import java.util.concurrent.CompletableFuture;

public class BrickChunk implements WorldChunk {
   static final int chunkEdge = 16;
   static final int brickIntCount = chunkEdge * chunkEdge * chunkEdge;
   static final int byteSize = brickIntCount * Integer.BYTES;
   private static final int maxShaderBlockIndex = 0x1FFF;
   private static final int debugLogLimit = 16;
   private static int blockPointerOverflowLogs = 0;
   private final int[] brickData = new int[brickIntCount];
   private final PBlock[] blockRefs = new PBlock[brickIntCount];
   private final Object2IntMap<PBlock> blocks = new Object2IntOpenHashMap<>();
   private MemoryRegion chunkMemory;
   private boolean dirty = true;
   private int dirtyVoxelWrites = 0;

   public BrickChunk() {
      this.resetBrickData();
   }

   @Override
   public void freeBlocks() {
      for (Object2IntMap.Entry<PBlock> entry : this.blocks.object2IntEntrySet()) {
         entry.getKey().changeTimesUsed(-entry.getIntValue());
      }
      this.blocks.clear();
      Arrays.fill(this.blockRefs, null);
      this.resetBrickData();
      this.dirtyVoxelWrites = brickIntCount;
      this.dirty = true;
   }

   @Override
   public boolean set(int x, int y, int z, PBlock block, int skyBrightness) {
      int encodedValue = this.encodeBlockValue(block, skyBrightness);
      int index = Schematic.toSchematicIndex(x, y, z);
      int newValue = encodedValue == 0
         ? AirEntry.toAirEntry(x, y, z, x + 1, y + 1, z + 1)
         : -encodedValue;
      if (this.brickData[index] == newValue) {
         return false;
      }

      PBlock previousBlock = this.blockRefs[index];
      if (previousBlock != block) {
         this.releaseTrackedBlock(previousBlock);
         this.trackBlock(block);
         this.blockRefs[index] = block;
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

   int getTrackedBlockTypeCount() {
      return this.blocks.size();
   }

   int getTrackedBlockReferenceCount() {
      int total = 0;
      for (Object2IntMap.Entry<PBlock> entry : this.blocks.object2IntEntrySet()) {
         total += entry.getIntValue();
      }
      return total;
   }

   @Override
   public int getSize() {
      return byteSize;
   }

   @Override
   public MemoryRegion getMemory() {
      return this.chunkMemory;
   }

   private int encodeBlockValue(PBlock block, int skyBrightness) {
      int value;
      if (block != null) {
         value = block.getMemory().begin >> 2;
      } else {
         value = 0;
      }

      value /= PBlock.BYTE_SIZE / 4;
      if (value > maxShaderBlockIndex) {
         if (blockPointerOverflowLogs < debugLogLimit) {
            blockPointerOverflowLogs++;
            Photonic.warn(
               "[BrickChunkDebug] Block pointer overflow: blockId={} shaderIndex={} exceeds 13-bit budget, falling back to air",
               block == null ? -1 : block.blockId,
               value
            );
         }
         return 0;
      }
      if (skyBrightness != -1 && value != 0) {
         value |= skyBrightness << 13;
      }
      return value;
   }

   private void resetBrickData() {
      for (int y = 0; y < chunkEdge; y++) {
         for (int x = 0; x < chunkEdge; x++) {
            for (int z = 0; z < chunkEdge; z++) {
               this.brickData[Schematic.toSchematicIndex(x, y, z)] = AirEntry.toAirEntry(x, y, z, x + 1, y + 1, z + 1);
            }
         }
      }
   }

   private void trackBlock(PBlock block) {
      if (block == null) {
         return;
      }
      block.changeTimesUsed(1);
      this.blocks.mergeInt(block, 1, Integer::sum);
   }

   private void releaseTrackedBlock(PBlock block) {
      if (block == null) {
         return;
      }
      block.changeTimesUsed(-1);
      int remaining = this.blocks.getInt(block) - 1;
      if (remaining <= 0) {
         this.blocks.removeInt(block);
      } else {
         this.blocks.put(block, remaining);
      }
   }
}
