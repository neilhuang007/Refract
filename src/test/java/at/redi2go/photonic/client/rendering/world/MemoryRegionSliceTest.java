package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import java.nio.IntBuffer;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

class MemoryRegionSliceTest {
   @Test
   void sliceCreatesSubRegionWithCorrectBeginEnd() {
      int totalInts = 32 * 32 * 32;
      GlMemoryManager manager = new GlMemoryManager(GlTarget.SSBO, "test_root", totalInts * Integer.BYTES, false);
      MemoryRegion root = manager.allocate(totalInts * Integer.BYTES);

      int index = Schematic.toSchematicIndex(5, 10, 3);
      MemoryRegion slice = root.slice(index * Integer.BYTES, Integer.BYTES);

      assertNotNull(slice);
      assertEquals(root.begin + index * Integer.BYTES, slice.begin);
      assertEquals(root.begin + index * Integer.BYTES + Integer.BYTES, slice.end);
      assertEquals(Integer.BYTES, slice.end - slice.begin);

      manager.free();
   }

   @Test
   void sliceBufferWritesAreVisibleFromParentBuffer() {
      int totalInts = 32 * 32 * 32;
      GlMemoryManager manager = new GlMemoryManager(GlTarget.SSBO, "test_root", totalInts * Integer.BYTES, false);
      MemoryRegion root = manager.allocate(totalInts * Integer.BYTES);

      int index = Schematic.toSchematicIndex(7, 3, 15);
      int testValue = 0x0BADB002;

      MemoryRegion slice = root.slice(index * Integer.BYTES, Integer.BYTES);
      IntBuffer sliceBuf = slice.getBuffer().asIntBuffer();
      sliceBuf.position(0);
      sliceBuf.put(testValue);

      IntBuffer rootBuf = root.getBuffer().asIntBuffer();
      assertEquals(testValue, rootBuf.get(index));

      manager.free();
   }

   @Test
   void sliceRejectsOutOfBoundsAccess() {
      int totalInts = 32 * 32 * 32;
      GlMemoryManager manager = new GlMemoryManager(GlTarget.SSBO, "test_root", totalInts * Integer.BYTES, false);
      MemoryRegion root = manager.allocate(totalInts * Integer.BYTES);

      assertThrows(IllegalArgumentException.class, () -> root.slice(-1, Integer.BYTES));
      assertThrows(IllegalArgumentException.class, () -> root.slice(totalInts * Integer.BYTES, Integer.BYTES));
      assertThrows(IllegalArgumentException.class, () -> root.slice(0, totalInts * Integer.BYTES + 1));
      assertThrows(IllegalArgumentException.class, () -> root.slice(totalInts * Integer.BYTES - 2, Integer.BYTES));

      manager.free();
   }
}
