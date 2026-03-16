package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import java.util.Map;

public class LegacyWorldBackend implements WorldBackend {
   private static final int DEFAULT_CB_MEMORY_CAPACITY = 536870912;
   private final GlMemoryManager cbMemoryManager;
   private final GlMemoryManager rootMemoryManager;
   private final Schematic rootSchematic;
   private final Map<PChunkPos, WorldChunk> chunks;
   private MemoryRegion rootMemory;

   public LegacyWorldBackend(int worldChunkSize, Map<PChunkPos, WorldChunk> chunks) {
      this(worldChunkSize, chunks, DEFAULT_CB_MEMORY_CAPACITY);
   }

   protected LegacyWorldBackend(int worldChunkSize, Map<PChunkPos, WorldChunk> chunks, int cbMemoryCapacity) {
      this.cbMemoryManager = new GlMemoryManager(GlTarget.SSBO, "cb_block", cbMemoryCapacity, true);
      this.rootMemoryManager = new GlMemoryManager(GlTarget.SSBO, "root_uniform", 4 * worldChunkSize * worldChunkSize * worldChunkSize, false);
      this.rootSchematic = new Schematic(worldChunkSize, worldChunkSize, worldChunkSize);
      this.chunks = chunks;
   }

   @Override
   public GlMemoryManager getRootMemoryManager() {
      return this.rootMemoryManager;
   }

   @Override
   public GlMemoryManager getCbMemoryManager() {
      return this.cbMemoryManager;
   }

   @Override
   public Schematic getRootSchematic() {
      return this.rootSchematic;
   }

   @Override
   public MemoryRegion getRootMemory() {
      return this.rootMemory;
   }

   @Override
   public void setRootMemory(MemoryRegion rootMemory) {
      this.rootMemory = rootMemory;
   }

   @Override
   public Map<PChunkPos, WorldChunk> getChunks() {
      return this.chunks;
   }

   @Override
   public void free() {
      this.cbMemoryManager.free();
      this.rootMemoryManager.free();
   }
}
