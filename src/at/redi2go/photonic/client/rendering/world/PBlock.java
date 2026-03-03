package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import java.util.function.Supplier;

public class PBlock implements MemoryOwner {
   public static final int BLOCK_SIZE = 16;
   private MemoryRegion blockMemory;
   private Supplier<Schematic> compiledSchematicSupplier;
   private boolean lightSourceRegistered = false;
   private boolean empty = false;
   public static int loaded = 0;

   public PBlock(Supplier<Schematic> compiledSchematicSupplier) {
      if (compiledSchematicSupplier == null) {
         throw new IllegalArgumentException("compiledSchematicSupplier must not be null");
      } else {
         this.compiledSchematicSupplier = compiledSchematicSupplier;
      }
   }

   @Override
   public void allocate(GlMemoryManager memoryManager) {
      this.blockMemory = memoryManager.allocate(this.getSize());
      loaded++;
   }

   @Override
   public void free(GlMemoryManager memoryManager) {
      if (this.blockMemory != null) {
         memoryManager.free(this.blockMemory);
         this.blockMemory = null;
         loaded--;
      }
   }

   @Override
   public boolean update(GlMemoryManager memoryManager) {
      if (this.compiledSchematicSupplier == null) {
         return false;
      } else {
         this.blockMemory.getBuffer().asIntBuffer().put(this.compiledSchematicSupplier.get().getData());
         memoryManager.queueUploadPriority(this);
         this.compiledSchematicSupplier = null;
         return true;
      }
   }

   @Override
   public void afterUpload() {
   }

   @Override
   public int getSize() {
      return 16384;
   }

   @Override
   public MemoryRegion getMemory() {
      return this.blockMemory;
   }

   public void setCompiledSchematicSupplier(Supplier<Schematic> compiledSchematicSupplier) {
      this.compiledSchematicSupplier = compiledSchematicSupplier;
   }

   public boolean isEmpty() {
      return this.empty;
   }

   public void setEmpty(boolean empty) {
      this.empty = empty;
   }

   public boolean isLightSourceRegistered() {
      return this.lightSourceRegistered;
   }

   public void setLightSourceRegistered(boolean lightSourceRegistered) {
      this.lightSourceRegistered = lightSourceRegistered;
   }
}
