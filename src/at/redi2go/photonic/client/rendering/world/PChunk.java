package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import it.unimi.dsi.fastutil.objects.Object2IntMap;
import it.unimi.dsi.fastutil.objects.Object2IntOpenHashMap;
import java.util.Arrays;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;

public class PChunk implements WorldChunk {
   public static final int CHUNK_SIZE = 16;
   private static final int MAX_SHADER_BLOCK_INDEX = 0x1FFF;
   private static final int DEBUG_LOG_LIMIT = 16;
   private static int blockPointerOverflowLogs = 0;
   private final Schematic schematic;
   private final PBlock[] blockRefs = new PBlock[16 * 16 * 16];
   private MemoryRegion chunkMemory;
   private boolean dirty = true;
   private final Object2IntMap<PBlock> blocks = new Object2IntOpenHashMap<>();
   private CompletableFuture<Void> pendingOptimization;
   public static int loaded = 0;

   public PChunk() {
      this.schematic = new Schematic(16, 16, 16);
   }

   public void freeBlocks() {
      for (Object2IntMap.Entry<PBlock> e : this.blocks.object2IntEntrySet()) {
         e.getKey().changeTimesUsed(-e.getIntValue());
      }
      this.blocks.clear();
      Arrays.fill(this.blockRefs, null);
   }

   public boolean set(int x, int y, int z, PBlock block, int skyBrightness) {
      int value;
      if (block != null) {
         value = block.getMemory().begin >> 2;
      } else {
         value = 0;
      }

      value /= PBlock.BYTE_SIZE / 4;
      if (value > MAX_SHADER_BLOCK_INDEX) {
         if (blockPointerOverflowLogs < DEBUG_LOG_LIMIT) {
            blockPointerOverflowLogs++;
            Photonic.warn(
               "[PChunkDebug] Block pointer overflow: blockId={} shaderIndex={} exceeds 13-bit budget, falling back to air",
               block == null ? -1 : block.blockId,
               value
            );
         }
         value = 0;
      }
      if (skyBrightness != -1 && value != 0) {
         value |= skyBrightness << 13;
      }

      int index = Schematic.toSchematicIndex(x, y, z);
      if (this.schematic.getEntry(x, y, z) == value) {
         return false;
      }
      PBlock previousBlock = this.blockRefs[index];
      if (previousBlock != block) {
         this.releaseTrackedBlock(previousBlock);
         this.trackBlock(block);
         this.blockRefs[index] = block;
      }
      this.schematic.setEntry(x, y, z, value);
      this.dirty = true;
      return true;
   }

   @Override
   public void allocate(MemoryManager memoryManager) {
      this.chunkMemory = memoryManager.allocate(this.getSize());
      loaded++;
   }

   @Override
   public void free(MemoryManager memoryManager) {
      if (this.chunkMemory != null) {
         memoryManager.free(this.chunkMemory);
         this.chunkMemory = null;
         this.pendingOptimization = null;
         loaded--;
      }
   }

   @Override
   public boolean update(MemoryManager memoryManager) {
      if (!this.dirty) {
         return false;
      }

      this.optimizeAsync();
      this.finishUpdate(memoryManager);
      return true;
   }

   public CompletableFuture<Void> optimizeAsync() {
      if (!this.dirty) {
         return CompletableFuture.completedFuture(null);
      }
      if (this.pendingOptimization != null) {
         return this.pendingOptimization;
      }

      this.schematic.reset();
      this.schematic.initialize();
      this.pendingOptimization = this.schematic.optimizeThreaded();
      return this.pendingOptimization;
   }

   public void finishUpdate(MemoryManager memoryManager) {
      if (!this.dirty) {
         return;
      }

      CompletableFuture<Void> optimization = this.pendingOptimization;
      if (optimization == null) {
         optimization = this.optimizeAsync();
      }

      try {
         optimization.get();
         this.chunkMemory.getBuffer().asIntBuffer().put(this.schematic.getData());
         memoryManager.queueUpload(this);
      } catch (ExecutionException | InterruptedException e) {
         throw new RuntimeException(e);
      } finally {
         this.pendingOptimization = null;
      }
   }

   @Override
   public void afterUpload() {
      this.dirty = false;
   }

   @Override
   public int getSize() {
      return 16384;
   }

   public boolean isDirty() {
      return this.dirty;
   }

   @Override
   public MemoryRegion getMemory() {
      return this.chunkMemory;
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
