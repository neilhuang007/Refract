package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.MinecraftAccessor;
import at.redi2go.photonic.client.rendering.opengl.rendering.IRenderDispatcher;
import at.redi2go.photonic.client.rendering.world.position.PBlockPos;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.PriorityQueue;
import java.util.Set;
import java.util.function.Consumer;
import java.util.function.IntConsumer;
import org.joml.Vector3f;

/**
 * Stateless decision helper for chunk residency and pruning logic.
 * WorldRegistry retains all data structures; this class implements
 * only the residency-decision algorithms (Alternative B: callback-based
 * side effects for synchronizeChunks because load/unload calls are
 * deeply interleaved with the decision loop and reordering them would
 * alter observable timing).
 */
public class ChunkResidencyManager {

    private static final float RT_ALWAYS_KEEP_DISTANCE_BLOCKS = 48.0F;
    private static final float RT_MAX_RESIDENT_DISTANCE_BLOCKS = 96.0F;
    private static final float RT_RESIDENT_UNLOAD_HYSTERESIS_BLOCKS = 16.0F;
    static final int RT_MAX_RESIDENT_CHUNKS = 192;
    private static final int RT_VISIBILITY_KEEP_ALIVE_FRAMES = 96;
    private static final int INITIAL_CHUNK_LOAD_BUDGET = 512;
    private static final int CHUNK_LOAD_BUDGET = 256;

    /**
     * Decides which chunks to load or unload based on the inbound set, camera
     * position, and budget. Side effects (loadChunk / unloadChunk) are
     * dispatched through the provided callbacks at exactly the same points
     * the original inline calls occurred — preserving ordering and timing.
     *
     * @param renderDispatcher        source of the current inbound chunk set
     * @param rtToWorldChunkOffset    offset used to convert world → RT coordinates
     * @param worldChunkSize          RT grid dimension (used for bounds check)
     * @param chunks                  currently loaded chunks (ConcurrentHashMap owned by WorldRegistry)
     * @param pendingChunkLoads       load-priority queue (owned by WorldRegistry)
     * @param pendingChunkSet         set mirror of pendingChunkLoads (owned by WorldRegistry)
     * @param recentlyVisibleRtChunks visibility-age map (owned by WorldRegistry)
     * @param frame                   current frame counter
     * @param isFrozenForDebug        whether residency mutations are frozen
     * @param onLoad                  callback executed for each chunk selected for loading
     * @param onUnload                callback executed for each chunk selected for unloading
     * @param onProfileLoaded         callback to record the count of newly loaded chunks
     * @param onProfileUnloaded       callback to increment the unloaded-chunk profiling counter
     * @return true if any residency change occurred (same semantics as original)
     */
    public boolean synchronizeChunks(
        IRenderDispatcher renderDispatcher,
        PChunkPos rtToWorldChunkOffset,
        int worldChunkSize,
        Map<PChunkPos, WorldChunk> chunks,
        PriorityQueue<PChunkPos> pendingChunkLoads,
        Set<PChunkPos> pendingChunkSet,
        Map<PChunkPos, Integer> recentlyVisibleRtChunks,
        int frame,
        boolean isFrozenForDebug,
        Consumer<PChunkPos> onLoad,
        Consumer<PChunkPos> onUnload,
        IntConsumer onProfileLoaded,
        Runnable onProfileUnloaded
    ) {
        Set<PChunkPos> inboundNonEmptyChunks = new HashSet<>();

        for (PChunkPos chunkPos : renderDispatcher.getInboundChunks()) {
            if (!renderDispatcher.isChunkEmpty(chunkPos) && this.shouldKeepChunkForRt(chunkPos)) {
                PChunkPos rtChunkPos = new PChunkPos(
                    chunkPos.x - rtToWorldChunkOffset.x,
                    chunkPos.y - rtToWorldChunkOffset.y,
                    chunkPos.z - rtToWorldChunkOffset.z
                );
                if (isRtChunkInBounds(rtChunkPos, worldChunkSize)) {
                    inboundNonEmptyChunks.add(chunkPos);
                    recentlyVisibleRtChunks.put(chunkPos, frame);
                }
            }
        }

        recentlyVisibleRtChunks.entrySet().removeIf(entry -> frame - entry.getValue() > RT_VISIBILITY_KEEP_ALIVE_FRAMES);

        boolean changed = false;

        for (PChunkPos chunkPos : inboundNonEmptyChunks) {
            if (!chunks.containsKey(chunkPos) && pendingChunkSet.add(chunkPos)) {
                pendingChunkLoads.add(chunkPos);
            }
        }

        pendingChunkLoads.removeIf(pos -> {
            if (!inboundNonEmptyChunks.contains(pos)) {
                pendingChunkSet.remove(pos);
                return true;
            }
            return false;
        });

        int trimmedChunkCount = trimResidentChunksToCameraBudget(
            inboundNonEmptyChunks, chunks, recentlyVisibleRtChunks, onUnload, onProfileUnloaded
        );
        if (trimmedChunkCount > 0) {
            changed = true;
        }

        int residentBudgetRemaining = Math.max(0, RT_MAX_RESIDENT_CHUNKS - chunks.size());
        int chunkLoadBudget = Math.min(chunks.isEmpty() ? INITIAL_CHUNK_LOAD_BUDGET : CHUNK_LOAD_BUDGET, residentBudgetRemaining);
        List<PChunkPos> chunksToLoad = new ArrayList<>();
        while (!pendingChunkLoads.isEmpty() && chunksToLoad.size() < chunkLoadBudget) {
            PChunkPos nextChunk = pendingChunkLoads.poll();
            pendingChunkSet.remove(nextChunk);
            if (inboundNonEmptyChunks.contains(nextChunk) && !chunks.containsKey(nextChunk)) {
                chunksToLoad.add(nextChunk);
            }
        }

        if (!chunksToLoad.isEmpty()) {
            changed = true;
            onProfileLoaded.accept(chunksToLoad.size());
            for (PChunkPos chunkPos : chunksToLoad) {
                onLoad.accept(chunkPos);
            }
        }

        if (!isFrozenForDebug) {
            for (PChunkPos chunkPos : chunks.keySet().toArray(new PChunkPos[0])) {
                if (inboundNonEmptyChunks.contains(chunkPos)) {
                    continue;
                }

                if (this.shouldRetainLoadedRtChunk(chunkPos)) {
                    continue;
                }

                Integer lastVisibleFrame = recentlyVisibleRtChunks.get(chunkPos);
                if (lastVisibleFrame != null && frame - lastVisibleFrame <= RT_VISIBILITY_KEEP_ALIVE_FRAMES) {
                    continue;
                }

                onUnload.accept(chunkPos);
                onProfileUnloaded.run();
                changed = true;
            }
        }

        return changed;
    }

    /**
     * Returns true if the chunk should be considered for RT inclusion based on
     * camera distance alone. Directional culling is intentionally omitted to
     * avoid destabilising ReGIR / ReSTIR temporal history during camera sweeps.
     */
    public boolean shouldKeepChunkForRt(PChunkPos chunkPos) {
        Vector3f cameraPosition = new Vector3f(MinecraftAccessor.getCameraPosition());
        PBlockPos blockPos = chunkPos.toBlockPos();
        Vector3f toChunk = new Vector3f(
            blockPos.x + 8.0F - cameraPosition.x,
            blockPos.y + 8.0F - cameraPosition.y,
            blockPos.z + 8.0F - cameraPosition.z
        );
        float distanceSquared = toChunk.lengthSquared();
        if (distanceSquared <= RT_ALWAYS_KEEP_DISTANCE_BLOCKS * RT_ALWAYS_KEEP_DISTANCE_BLOCKS) {
            return true;
        }

        if (distanceSquared > RT_MAX_RESIDENT_DISTANCE_BLOCKS * RT_MAX_RESIDENT_DISTANCE_BLOCKS) {
            return false;
        }

        // Keep all nearby chunks resident regardless of the current view direction.
        // Directional culling makes the traced-light set rotate in and out during
        // camera sweeps, which destabilizes both ReGIR cell contents and ReSTIR
        // temporal history even when the camera returns to the same pose.
        return true;
    }

    /**
     * Returns true if a currently-loaded chunk should be retained in memory,
     * applying a hysteresis margin beyond the standard max-resident distance
     * to avoid load/unload churn at the boundary.
     */
    public boolean shouldRetainLoadedRtChunk(PChunkPos chunkPos) {
        float retainDistance = RT_MAX_RESIDENT_DISTANCE_BLOCKS + RT_RESIDENT_UNLOAD_HYSTERESIS_BLOCKS;
        return chunkDistanceToCamera(chunkPos) <= retainDistance * retainDistance;
    }

    /**
     * Evicts chunks that exceed RT_MAX_RESIDENT_CHUNKS, sorted by ascending
     * retention priority (farthest / least-recently-visible chunks first).
     * Only chunks outside the current inbound set are eligible for trimming.
     *
     * @return the number of chunks trimmed
     */
    private int trimResidentChunksToCameraBudget(
        Set<PChunkPos> inboundNonEmptyChunks,
        Map<PChunkPos, WorldChunk> chunks,
        Map<PChunkPos, Integer> recentlyVisibleRtChunks,
        Consumer<PChunkPos> onUnload,
        Runnable onProfileUnloaded
    ) {
        if (chunks.size() <= RT_MAX_RESIDENT_CHUNKS) {
            return 0;
        }

        List<PChunkPos> loadedChunks = new ArrayList<>(chunks.keySet());
        loadedChunks.sort(Comparator.comparingDouble((PChunkPos pos) -> chunkRetentionPriority(pos, recentlyVisibleRtChunks)).reversed());


        int trimmedChunkCount = 0;
        for (PChunkPos chunkPos : collectTrimEligibleChunks(loadedChunks, RT_MAX_RESIDENT_CHUNKS, inboundNonEmptyChunks)) {
            onUnload.accept(chunkPos);
            onProfileUnloaded.run();
            trimmedChunkCount++;
        }
        return trimmedChunkCount;
    }

    /**
     * Returns the subset of loadedChunks (already sorted by descending retention
     * priority) that are eligible for trimming: those beyond the budget index
     * that are not in the inbound working set.
     */
    static List<PChunkPos> collectTrimEligibleChunks(
        List<PChunkPos> loadedChunks,
        int residentChunkBudget,
        Set<PChunkPos> inboundNonEmptyChunks
    ) {
        if (loadedChunks.size() <= residentChunkBudget) {
            return List.of();
        }

        List<PChunkPos> trimEligible = new ArrayList<>();
        for (int i = residentChunkBudget; i < loadedChunks.size(); i++) {
            PChunkPos chunkPos = loadedChunks.get(i);
            // Only trim chunks that are already outside the inbound RT working set.
            // Evicting inbound chunks forces avoidable unload/reload churn, which in
            // turn dirties traced-light residency and restarts local temporal blends.
            if (inboundNonEmptyChunks.contains(chunkPos)) {
                continue;
            }
            trimEligible.add(chunkPos);
        }
        return trimEligible;
    }

    /**
     * Retention priority for a chunk: higher = more important to keep.
     * Inverse-distance weighted, with a bonus for recently-visible chunks.
     */
    private double chunkRetentionPriority(PChunkPos chunkPos, Map<PChunkPos, Integer> recentlyVisibleRtChunks) {
        Vector3f cameraPosition = new Vector3f(MinecraftAccessor.getCameraPosition());
        PBlockPos blockPos = chunkPos.toBlockPos();
        Vector3f toChunk = new Vector3f(
            blockPos.x + 8.0F - cameraPosition.x,
            blockPos.y + 8.0F - cameraPosition.y,
            blockPos.z + 8.0F - cameraPosition.z
        );
        float distanceSquared = toChunk.lengthSquared();
        if (distanceSquared <= 1.0e-4F) {
            return Double.POSITIVE_INFINITY;
        }

        float inverseDistance = 1.0F / distanceSquared;
        boolean recentlyVisible = recentlyVisibleRtChunks.containsKey(chunkPos);
        return inverseDistance + (recentlyVisible ? 0.5 : 0.0);
    }

    /** Squared distance from camera to the centre of the given chunk. */
    public double chunkDistanceToCamera(PChunkPos chunkPos) {
        Vector3f cameraPosition = new Vector3f(MinecraftAccessor.getCameraPosition());
        PBlockPos blockPos = chunkPos.toBlockPos();
        float dx = blockPos.x + 8.0F - cameraPosition.x;
        float dy = blockPos.y + 8.0F - cameraPosition.y;
        float dz = blockPos.z + 8.0F - cameraPosition.z;
        return dx * dx + dy * dy + dz * dz;
    }

    /** Returns true when the RT-space chunk position is within the grid bounds. */
    private static boolean isRtChunkInBounds(PChunkPos rtChunkPos, int worldChunkSize) {
        return rtChunkPos.x >= 0 && rtChunkPos.x < worldChunkSize
            && rtChunkPos.y >= 0 && rtChunkPos.y < worldChunkSize
            && rtChunkPos.z >= 0 && rtChunkPos.z < worldChunkSize;
    }
}
