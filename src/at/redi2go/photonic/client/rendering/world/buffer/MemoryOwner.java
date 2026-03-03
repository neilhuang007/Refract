package at.redi2go.photonic.client.rendering.world.buffer;

public interface MemoryOwner {
   void allocate(GlMemoryManager var1);

   void free(GlMemoryManager var1);

   boolean update(GlMemoryManager var1);

   void afterUpload();

   int getSize();

   MemoryRegion getMemory();
}
