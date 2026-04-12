package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Field;
import java.util.Deque;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;

@Disabled("Requires Minecraft/LWJGL runtime classpath")
class GlMemoryManagerUploadPriorityTest {
   @Test
   void memoryRegionAllocationTracksBeginEndCorrectly() {
      GlMemoryManager manager = new GlMemoryManager(GlTarget.SSBO, "test", 1024, false);
      MemoryRegion first = manager.allocate(256);
      MemoryRegion second = manager.allocate(128);

      assertEquals(0, first.begin);
      assertEquals(256, first.end);
      assertEquals(256, second.begin);
      assertEquals(384, second.end);

      manager.free();
   }

   @Test
   void freedRegionCanBeReallocated() {
      GlMemoryManager manager = new GlMemoryManager(GlTarget.SSBO, "test", 1024, false);
      MemoryRegion region = manager.allocate(64);
      int originalBegin = region.begin;
      int originalEnd = region.end;

      manager.free(region);
      assertFalse(region.allocated, "Region must be marked unallocated after free");

      MemoryRegion recycled = manager.allocate(64);
      assertEquals(originalBegin, recycled.begin, "Recycled region must have same begin");
      assertEquals(originalEnd, recycled.end, "Recycled region must have same end");
      assertTrue(recycled.allocated, "Recycled region must be marked allocated");

      manager.free();
   }

   @Test
   void queueUploadDeduplicatesRepeatedOwners() throws Exception {
      GlMemoryManager manager = new GlMemoryManager(GlTarget.SSBO, "test", 1024, false);
      StubMemoryOwner owner = new StubMemoryOwner(manager.allocate(64));

      manager.queueUpload(owner);
      manager.queueUpload(owner);
      manager.queueUpload(owner);

      @SuppressWarnings("unchecked")
      Deque<MemoryOwner> uploadQueue = (Deque<MemoryOwner>) getField(manager, "uploadQueue");
      assertEquals(1, uploadQueue.size());
      assertSame(owner, uploadQueue.peekFirst());
      assertEquals(1, manager.getPendingUploadCount());

      manager.free();
   }

   private static Object getField(Object instance, String name) throws Exception {
      Field field = instance.getClass().getDeclaredField(name);
      field.setAccessible(true);
      return field.get(instance);
   }

   private static final class StubMemoryOwner implements MemoryOwner {
      private final MemoryRegion memory;

      private StubMemoryOwner(MemoryRegion memory) {
         this.memory = memory;
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
