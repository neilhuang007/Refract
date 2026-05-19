package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.config.lights.BlockLightInfo;
import at.redi2go.photonic.client.rendering.world.position.PBlockPos;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import java.util.Iterator;
import java.util.Map;
import java.util.Map.Entry;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.BiConsumer;
import java.util.function.BiFunction;
import net.minecraft.block.BlockState;
import net.minecraft.block.Blocks;
import net.minecraft.client.world.ClientWorld;
import net.minecraft.util.math.BlockPos;
import org.joml.Vector3f;

/**
 * Owns the per-block traced-light tracking state: the position map, chunk
 * residency bookkeeping, and the scan-count deferred-removal maps.
 *
 * <p>All mutating methods assume the caller (LightRegistry) holds the write lock.
 * The ConcurrentHashMap fields remain safe for off-thread reads.
 *
 * <p>Dirty-flag side effects are communicated back to LightRegistry via the
 * return value of {@link #clearChunkLights} (a boolean indicating whether any
 * entries were removed) and via the {@code noopSyncCallback} / per-block sync
 * callback passed into {@link #synchronizeChunkLights}. This keeps the
 * LightTracingManager free of any reference to LightRegistry while avoiding the
 * complexity of a result-object hierarchy.
 */
final class LightTracingManager {

   final Map<Vector3f, TracedLightPosition> tracedLightPositions = new ConcurrentHashMap<>();
   final Set<Long> loadedLightChunks = ConcurrentHashMap.newKeySet();
   final Map<Long, Long> chunkLightHashes = new ConcurrentHashMap<>();
   final Map<Vector3f, Integer> residentMissingLightScans = new ConcurrentHashMap<>();
   final Map<Vector3f, Integer> tracedVisibilityMissScans = new ConcurrentHashMap<>();

   LightTracingManager() {
   }

   int tracedLightCount() {
      return this.tracedLightPositions.size();
   }

   // -------------------------------------------------------------------------
   // Tracking-state queries
   // -------------------------------------------------------------------------

   boolean isTrackedChunkLoaded(BlockPos blockPos) {
      return this.loadedLightChunks.contains(LightRegistry.chunkKey(blockPos));
   }

   // -------------------------------------------------------------------------
   // Mutators — assume caller holds the write lock
   // -------------------------------------------------------------------------

   /**
    * Synchronizes traced-light entries for an entire chunk section.
    *
    * @param level              the client world (used for block-state lookup inside
    *                           computeChunkLightHash and for the per-block sync)
    * @param chunkPos           the chunk section being synced
    * @param lightInfoResolver  callback to resolve {@link BlockLightInfo} for a
    *                           (pos, state, level) triple — delegates to
    *                           LightRegistry.resolveLightInfo
    * @param blockSyncer        callback that performs the per-block
    *                           syncTracedLight call — receives (blockPos, blockState,
    *                           deferMissingResidentLight=true)
    * @param noopSyncCallback   called when the chunk hash is unchanged (delegates
    *                           to churnStats.noteNoopSync)
    */
   void synchronizeChunkLights(
      ClientWorld level,
      PChunkPos chunkPos,
      TriFunction<BlockPos, BlockState, ClientWorld, BlockLightInfo> lightInfoResolver,
      BiConsumer<BlockPos, BlockState> blockSyncer,
      Runnable noopSyncCallback
   ) {
      long key = LightRegistry.chunkKey(chunkPos);
      long chunkLightHash = this.computeChunkLightHash(level, chunkPos, lightInfoResolver);
      Long previousHash = this.chunkLightHashes.get(key);
      this.loadedLightChunks.add(key);
      if (previousHash != null && previousHash == chunkLightHash) {
         noopSyncCallback.run();
         return;
      }
      this.chunkLightHashes.put(key, chunkLightHash);
      PBlockPos chunkMin = chunkPos.toBlockPos();
      BlockPos.Mutable mutableBlockPos = new BlockPos.Mutable();
      for (int x = 0; x < 16; x++) {
         for (int y = 0; y < 16; y++) {
            for (int z = 0; z < 16; z++) {
               mutableBlockPos.set(chunkMin.x + x, chunkMin.y + y, chunkMin.z + z);
               blockSyncer.accept(mutableBlockPos, level.getBlockState(mutableBlockPos));
            }
         }
      }
   }

   /**
    * Removes all traced-light entries that fall inside the given chunk section and
    * clears its residency and hash bookkeeping.
    *
    * @return {@code true} if at least one entry was removed (caller should set
    *         dirty flags and increment pendingTracedLightMutations)
    */
   boolean clearChunkLights(PChunkPos chunkPos) {
      long key = LightRegistry.chunkKey(chunkPos);
      this.loadedLightChunks.remove(key);
      this.chunkLightHashes.remove(key);
      PBlockPos chunkMin = chunkPos.toBlockPos();
      int maxX = chunkMin.x + 16;
      int maxY = chunkMin.y + 16;
      int maxZ = chunkMin.z + 16;
      boolean removed = false;
      Iterator<Entry<Vector3f, TracedLightPosition>> itr = this.tracedLightPositions.entrySet().iterator();
      while (itr.hasNext()) {
         Entry<Vector3f, TracedLightPosition> entry = itr.next();
         Vector3f pos = entry.getKey();
         if (pos.x >= chunkMin.x && pos.x < maxX && pos.y >= chunkMin.y && pos.y < maxY && pos.z >= chunkMin.z && pos.z < maxZ) {
            itr.remove();
            this.residentMissingLightScans.remove(pos);
            this.tracedVisibilityMissScans.remove(pos);
            removed = true;
         }
      }
      return removed;
   }

   // -------------------------------------------------------------------------
   // Private helpers
   // -------------------------------------------------------------------------

   private long computeChunkLightHash(
      ClientWorld level,
      PChunkPos chunkPos,
      TriFunction<BlockPos, BlockState, ClientWorld, BlockLightInfo> lightInfoResolver
   ) {
      long hash = LightRegistry.CHUNK_LIGHT_HASH_OFFSET;
      PBlockPos chunkMin = chunkPos.toBlockPos();
      BlockPos.Mutable mutableBlockPos = new BlockPos.Mutable();

      for (int x = 0; x < 16; x++) {
         for (int y = 0; y < 16; y++) {
            for (int z = 0; z < 16; z++) {
               mutableBlockPos.set(chunkMin.x + x, chunkMin.y + y, chunkMin.z + z);
               if (level == null || !level.isChunkLoaded(mutableBlockPos)) {
                  hash = LightRegistry.mixChunkLightHash(hash, 0x6d697373L);
                  continue;
               }

               BlockState blockState;
               try {
                  blockState = level.getBlockState(mutableBlockPos);
               } catch (Exception ignored) {
                  blockState = Blocks.AIR.getDefaultState();
               }

               BlockLightInfo lightInfo = lightInfoResolver.apply(mutableBlockPos, blockState, level);
               hash = LightRegistry.mixChunkLightHash(hash, Integer.toUnsignedLong(blockState.hashCode()));
               hash = LightRegistry.mixChunkLightHash(hash, lightInfo == null ? 0L : 1L);
               if (lightInfo != null) {
                  hash = LightRegistry.mixChunkLightHash(hash,
                     at.redi2go.photonic.client.rendering.util.IrisUtil.getBlockId(blockState));
                  hash = LightRegistry.mixChunkLightHash(hash,
                     LightRegistry.semanticLightDescriptorHash(lightInfo));
               }
            }
         }
      }

      return hash;
   }

   // -------------------------------------------------------------------------
   // Functional interface for the three-argument lightInfoResolver callback
   // -------------------------------------------------------------------------

   @FunctionalInterface
   interface TriFunction<A, B, C, R> {
      R apply(A a, B b, C c);
   }
}
