package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.world.buffer.MemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import java.util.concurrent.CompletableFuture;

public interface WorldChunk extends MemoryOwner {
   void freeBlocks();

   void set(int x, int y, int z, PBlock block, int skyBrightness);

   CompletableFuture<Void> optimizeAsync();

   void finishUpdate(MemoryManager memoryManager);

   boolean isDirty();
}
