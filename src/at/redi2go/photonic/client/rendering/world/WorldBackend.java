package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import java.util.Map;

public interface WorldBackend extends Destructable {
   GlMemoryManager getRootMemoryManager();

   GlMemoryManager getCbMemoryManager();

   Schematic getRootSchematic();

   MemoryRegion getRootMemory();

   void setRootMemory(MemoryRegion rootMemory);

   Map<PChunkPos, WorldChunk> getChunks();

   default boolean usesIncrementalRootUpdates() {
      return false;
   }

   default boolean usesNativeBlockPayloads() {
      return true;
   }

   default void markRootEntryDirty(PChunkPos chunkPos, PChunkPos rtToWorldChunkOffset, int worldChunkSize) {
   }

   default void markRtRootEntryDirty(PChunkPos rtChunkPos, int worldChunkSize) {
   }

   default void updateRootData(PChunkPos rtToWorldChunkOffset, int worldChunkSize, boolean fullRootRebuild) {
   }
}
