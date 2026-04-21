package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import at.redi2go.photonics.core.model.VoxelEntry;
import java.nio.IntBuffer;
import java.util.Map;

public class MultiVersionWorldBackend extends LegacyWorldBackend {
   private MultiVersionUploadSummary lastUploadSummary = MultiVersionUploadSummary.empty();

   public MultiVersionWorldBackend(int worldChunkSize, Map<PChunkPos, WorldChunk> chunks) {
      super(worldChunkSize, chunks);
   }

   @Override
   public void updateRootData(PChunkPos rtToWorldChunkOffset, int worldChunkSize, boolean fullRootRebuild) {
      MemoryRegion rootMemory = this.getRootMemory();
      if (rootMemory == null) {
         this.lastUploadSummary = MultiVersionUploadSummary.empty();
         return;
      }

      int[] rootData = this.getRootSchematic().getData();
      fillRootWithAir(rootData, worldChunkSize);
      int populatedRootEntries = 0;
      for (Map.Entry<PChunkPos, WorldChunk> entry : this.getChunks().entrySet()) {
         PChunkPos rtChunkPos = toRtChunkPos(entry.getKey(), rtToWorldChunkOffset);
         if (!isRtChunkInBounds(rtChunkPos, worldChunkSize)) {
            continue;
         }

         WorldChunk chunk = entry.getValue();
         if (chunk.getMemory() == null) {
            continue;
         }

         rootData[Schematic.toSchematicIndex(rtChunkPos.x, rtChunkPos.y, rtChunkPos.z)] = VoxelEntry.toData(chunk.getMemory().begin >> 2);
         populatedRootEntries++;
      }

      IntBuffer rootBuffer = rootMemory.getBuffer().asIntBuffer();
      rootBuffer.position(0);
      rootBuffer.put(rootData);
      this.getRootMemoryManager().queueUploadPriority(new RootUpload(rootMemory));
      this.lastUploadSummary = this.buildUploadSummary(populatedRootEntries);
   }

   public MultiVersionUploadSummary consumeUploadSummary() {
      MultiVersionUploadSummary summary = this.lastUploadSummary;
      this.lastUploadSummary = MultiVersionUploadSummary.empty();
      return summary;
   }

   public MultiVersionUploadSummary buildCurrentSummary() {
      int populatedRootEntries = this.countLoadedRootEntries();
      return this.buildUploadSummary(populatedRootEntries);
   }

   private MultiVersionUploadSummary buildUploadSummary(int populatedRootEntries) {
      int dirtyChunks = 0;
      int dirtyVoxels = 0;
      for (WorldChunk chunk : this.getChunks().values()) {
         if (!(chunk instanceof MultiVersionChunk multiVersionChunk)) {
            continue;
         }
         if (!multiVersionChunk.isDirty()) {
            continue;
         }
         dirtyChunks++;
         dirtyVoxels += multiVersionChunk.getDirtyVoxelWrites();
      }

      int chunkUploadOps = this.getCbMemoryManager().getPendingUploadCount();
      long chunkUploadBytes = (long) chunkUploadOps * MultiVersionChunk.byteSize;
      long rootUploadBytes = this.getRootMemoryManager().getPendingUploadCount() > 0 ? this.getRootSchematic().getData().length * (long) Integer.BYTES : 0L;
      return new MultiVersionUploadSummary(dirtyChunks, dirtyVoxels, chunkUploadOps, chunkUploadBytes, populatedRootEntries, rootUploadBytes);
   }

   private int countLoadedRootEntries() {
      int count = 0;
      for (WorldChunk chunk : this.getChunks().values()) {
         if (chunk.getMemory() != null) {
            count++;
         }
      }
      return count;
   }

   private static void fillRootWithAir(int[] rootData, int worldChunkSize) {
      for (int y = 0; y < worldChunkSize; y++) {
         for (int x = 0; x < worldChunkSize; x++) {
            for (int z = 0; z < worldChunkSize; z++) {
               rootData[Schematic.toSchematicIndex(x, y, z)] = VoxelEntry.toAir(x, y, z, x + 1, y + 1, z + 1);
            }
         }
      }
   }

   private static PChunkPos toRtChunkPos(PChunkPos chunkPos, PChunkPos rtToWorldChunkOffset) {
      PChunkPos rtChunkPos = new PChunkPos(chunkPos.x, chunkPos.y, chunkPos.z);
      rtChunkPos.sub(rtToWorldChunkOffset.x, rtToWorldChunkOffset.y, rtToWorldChunkOffset.z);
      return rtChunkPos;
   }

   private static boolean isRtChunkInBounds(PChunkPos rtChunkPos, int worldChunkSize) {
      return rtChunkPos.x >= 0 && rtChunkPos.x < worldChunkSize
         && rtChunkPos.y >= 0 && rtChunkPos.y < worldChunkSize
         && rtChunkPos.z >= 0 && rtChunkPos.z < worldChunkSize;
   }

   public static final class MultiVersionUploadSummary {
      public final int dirtyChunks;
      public final int dirtyVoxels;
      public final int chunkUploadOps;
      public final long chunkUploadBytes;
      public final int populatedRootEntries;
      public final long rootUploadBytes;

      private MultiVersionUploadSummary(int dirtyChunks, int dirtyVoxels, int chunkUploadOps, long chunkUploadBytes, int populatedRootEntries, long rootUploadBytes) {
         this.dirtyChunks = dirtyChunks;
         this.dirtyVoxels = dirtyVoxels;
         this.chunkUploadOps = chunkUploadOps;
         this.chunkUploadBytes = chunkUploadBytes;
         this.populatedRootEntries = populatedRootEntries;
         this.rootUploadBytes = rootUploadBytes;
      }

      private static MultiVersionUploadSummary empty() {
         return new MultiVersionUploadSummary(0, 0, 0, 0L, 0, 0L);
      }

      public boolean hasWork() {
         return this.dirtyChunks > 0 || this.chunkUploadOps > 0 || this.rootUploadBytes > 0;
      }
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
