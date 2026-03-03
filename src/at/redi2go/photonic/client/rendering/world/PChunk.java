package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import java.util.concurrent.ExecutionException;

public class PChunk implements MemoryOwner {
   public static final int CHUNK_SIZE = 16;
   private final Schematic schematic;
   private MemoryRegion chunkMemory;
   private boolean dirty = true;
   public static int loaded = 0;

   public PChunk() {
      this.schematic = new Schematic(16, 16, 16);
   }

   public void set(int x, int y, int z, PBlock block) {
      this.schematic.setEntry(x, y, z, block != null ? block.getMemory().begin >> 2 : 0);
      this.dirty = true;
   }

   @Override
   public void allocate(GlMemoryManager memoryManager) {
      this.chunkMemory = memoryManager.allocate(this.getSize());
      loaded++;
   }

   @Override
   public void free(GlMemoryManager memoryManager) {
      if (this.chunkMemory != null) {
         memoryManager.free(this.chunkMemory);
         this.chunkMemory = null;
         loaded--;
      }
   }

   @Override
   public boolean update(GlMemoryManager memoryManager) {
      if (!this.dirty) {
         return false;
      } else {
         try {
            this.schematic.reset();
            this.schematic.initialize();
            this.schematic.optimizeThreaded().get();
            this.chunkMemory.getBuffer().asIntBuffer().put(this.schematic.getData());
            memoryManager.queueUpload(this);
            return true;
         } catch (ExecutionException | InterruptedException var3) {
            throw new RuntimeException(var3);
         }
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
}
