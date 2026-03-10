package at.redi2go.photonic.client.rendering.world.buffer;

import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;

public interface MemoryManager extends Destructable {
   int getCapacity();

   MemoryRegion allocate(int byteSize);

   boolean upload();

   void queueUpload(MemoryOwner memoryOwner);

   void queueUploadPriority(MemoryOwner memoryOwner);

   void free(MemoryRegion memoryRegion);
}
