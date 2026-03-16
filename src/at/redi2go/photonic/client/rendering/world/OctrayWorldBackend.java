package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.schematics.AirEntry;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import java.nio.IntBuffer;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

public class OctrayWorldBackend extends LegacyWorldBackend {
   private static final int BULK_ROOT_UPLOAD_THRESHOLD = 64;
   private final int worldChunkSize;
   private final Set<PChunkPos> dirtyRootEntries = new HashSet<>();

   public OctrayWorldBackend(int worldChunkSize, Map<PChunkPos, WorldChunk> chunks) {
      this(worldChunkSize, chunks, 536870912);
   }

   OctrayWorldBackend(int worldChunkSize, Map<PChunkPos, WorldChunk> chunks, int cbMemoryCapacity) {
      super(worldChunkSize, chunks, cbMemoryCapacity);
      this.worldChunkSize = worldChunkSize;
   }

   @Override
   public boolean usesIncrementalRootUpdates() {
      return true;
   }

   @Override
   public void markRootEntryDirty(PChunkPos chunkPos, PChunkPos rtToWorldChunkOffset, int worldChunkSize) {
      this.markRtRootEntryDirty(this.toRtChunkPos(chunkPos, rtToWorldChunkOffset), worldChunkSize);
   }

   @Override
   public void markRtRootEntryDirty(PChunkPos rtChunkPos, int worldChunkSize) {
      if (this.isRtChunkInBounds(rtChunkPos, worldChunkSize)) {
         this.dirtyRootEntries.add(new PChunkPos(rtChunkPos.x, rtChunkPos.y, rtChunkPos.z));
      }
   }

   @Override
   public void updateRootData(PChunkPos rtToWorldChunkOffset, int worldChunkSize, boolean fullRootRebuild) {
      if (fullRootRebuild || this.getRootMemory() == null) {
         this.rebuildRootData(rtToWorldChunkOffset);
         this.getRootMemoryManager().queueUploadPriority(new RootUpload(this.getRootMemory()));
         return;
      }
      if (this.dirtyRootEntries.isEmpty()) {
         return;
      }
      if (this.dirtyRootEntries.size() >= BULK_ROOT_UPLOAD_THRESHOLD) {
         for (PChunkPos rtChunkPos : this.dirtyRootEntries) {
            int value = this.getRootEntryValue(rtChunkPos, rtToWorldChunkOffset);
            this.getRootSchematic().setEntry(rtChunkPos.x, rtChunkPos.y, rtChunkPos.z, value);
         }
         this.copyFullRootToGpu();
         this.dirtyRootEntries.clear();
         return;
      }

      for (PChunkPos rtChunkPos : this.dirtyRootEntries) {
         int value = this.getRootEntryValue(rtChunkPos, rtToWorldChunkOffset);
         this.getRootSchematic().setEntry(rtChunkPos.x, rtChunkPos.y, rtChunkPos.z, value);
         this.copyRootEntryToGpu(rtChunkPos);
      }
      this.dirtyRootEntries.clear();
   }

   private void rebuildRootData(PChunkPos rtToWorldChunkOffset) {
      int[] rootData = this.getRootSchematic().getData();
      for (int y = 0; y < this.worldChunkSize; y++) {
         for (int x = 0; x < this.worldChunkSize; x++) {
            for (int z = 0; z < this.worldChunkSize; z++) {
               rootData[Schematic.toSchematicIndex(x, y, z)] = AirEntry.toAirEntry(x, y, z, x + 1, y + 1, z + 1);
            }
         }
      }
      for (Map.Entry<PChunkPos, WorldChunk> entry : this.getChunks().entrySet()) {
         PChunkPos rtChunkPos = this.toRtChunkPos(entry.getKey(), rtToWorldChunkOffset);
         if (this.isRtChunkInBounds(rtChunkPos, this.worldChunkSize)) {
            rootData[Schematic.toSchematicIndex(rtChunkPos.x, rtChunkPos.y, rtChunkPos.z)] = -(entry.getValue().getMemory().begin >> 2);
         }
      }
      MemoryRegion rootMemory = this.getRootMemory();
      if (rootMemory != null) {
         IntBuffer rootBuffer = rootMemory.getBuffer().asIntBuffer();
         rootBuffer.position(0);
         rootBuffer.put(rootData);
      }
      this.dirtyRootEntries.clear();
   }

   private int getRootEntryValue(PChunkPos rtChunkPos, PChunkPos rtToWorldChunkOffset) {
      PChunkPos worldChunkPos = new PChunkPos(rtChunkPos.x, rtChunkPos.y, rtChunkPos.z);
      worldChunkPos.add(rtToWorldChunkOffset.x, rtToWorldChunkOffset.y, rtToWorldChunkOffset.z);
      WorldChunk chunk = this.getChunks().get(worldChunkPos);
      if (chunk == null || chunk.getMemory() == null) {
         return AirEntry.toAirEntry(rtChunkPos.x, rtChunkPos.y, rtChunkPos.z, rtChunkPos.x + 1, rtChunkPos.y + 1, rtChunkPos.z + 1);
      }
      return -(chunk.getMemory().begin >> 2);
   }

   private void copyFullRootToGpu() {
      MemoryRegion rootMemory = this.getRootMemory();
      if (rootMemory == null) {
         return;
      }
      IntBuffer rootBuffer = rootMemory.getBuffer().asIntBuffer();
      rootBuffer.position(0);
      rootBuffer.put(this.getRootSchematic().getData());
      this.getRootMemoryManager().queueUploadPriority(new RootUpload(rootMemory));
   }

   private void copyRootEntryToGpu(PChunkPos rtChunkPos) {
      MemoryRegion rootMemory = this.getRootMemory();
      if (rootMemory == null) {
         return;
      }
      int index = Schematic.toSchematicIndex(rtChunkPos.x, rtChunkPos.y, rtChunkPos.z);
      MemoryRegion rootEntryMemory = rootMemory.slice(index * Integer.BYTES, Integer.BYTES);
      IntBuffer entryBuffer = rootEntryMemory.getBuffer().asIntBuffer();
      entryBuffer.position(0);
      entryBuffer.put(this.getRootSchematic().getData()[index]);
      this.getRootMemoryManager().queueUploadPriority(new RootUpload(rootEntryMemory));
   }

   private PChunkPos toRtChunkPos(PChunkPos chunkPos, PChunkPos rtToWorldChunkOffset) {
      PChunkPos rtChunkPos = new PChunkPos(chunkPos.x, chunkPos.y, chunkPos.z);
      rtChunkPos.sub(rtToWorldChunkOffset.x, rtToWorldChunkOffset.y, rtToWorldChunkOffset.z);
      return rtChunkPos;
   }

   private boolean isRtChunkInBounds(PChunkPos rtChunkPos, int worldChunkSize) {
      return rtChunkPos.x >= 0 && rtChunkPos.x < worldChunkSize
         && rtChunkPos.y >= 0 && rtChunkPos.y < worldChunkSize
         && rtChunkPos.z >= 0 && rtChunkPos.z < worldChunkSize;
   }

   private static final class RootUpload implements MemoryOwner {
      private final MemoryRegion memory;

      private RootUpload(MemoryRegion memory) {
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
