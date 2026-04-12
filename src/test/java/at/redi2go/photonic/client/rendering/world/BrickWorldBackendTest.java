package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.schematics.AirEntry;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import java.nio.IntBuffer;
import java.util.HashMap;
import java.util.Map;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

@Disabled("Requires Minecraft/LWJGL runtime classpath")
class BrickWorldBackendTest {
   private static final int worldChunkSize = 32;
   private static final int totalRootInts = worldChunkSize * worldChunkSize * worldChunkSize;

   @Test
   void updateRootDataWritesAirForMissingChunksAndPointersForLoadedChunks() {
      Map<PChunkPos, WorldChunk> chunks = new HashMap<>();
      BrickWorldBackend backend = new BrickWorldBackend(worldChunkSize, chunks);
      MemoryRegion rootMemory = backend.getRootMemoryManager().allocate(totalRootInts * Integer.BYTES);
      backend.setRootMemory(rootMemory);

      GlMemoryManager chunkMemory = new GlMemoryManager(GlTarget.SSBO, "test_chunk", 65536, true);
      BrickChunk chunk = new BrickChunk();
      chunk.allocate(chunkMemory);
      chunks.put(new PChunkPos(11, 22, 33), chunk);

      PChunkPos worldOffset = new PChunkPos(10, 20, 30);
      backend.updateRootData(worldOffset, worldChunkSize, false);

      IntBuffer root = rootMemory.getBuffer().asIntBuffer();
      int loadedIndex = Schematic.toSchematicIndex(1, 2, 3);
      int missingIndex = Schematic.toSchematicIndex(7, 8, 9);
      assertEquals(-(chunk.getMemory().begin >> 2), root.get(loadedIndex));
      assertEquals(AirEntry.toAirEntry(7, 8, 9, 8, 9, 10), root.get(missingIndex));

      chunk.free(chunkMemory);
      chunkMemory.free();
      backend.free();
   }
}
