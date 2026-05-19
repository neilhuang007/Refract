package at.redi2go.photonic.client.rendering.world;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import net.minecraft.block.BlockState;
import net.minecraft.util.math.BlockPos;
import org.jetbrains.annotations.Nullable;

/**
 * Thread-safe queue for pending block-update notifications.
 * Enqueue from any thread; flush from the compiler thread once per frame.
 */
public final class BlockUpdateQueue {

    private final Set<BlockPos> pendingBlockUpdates = ConcurrentHashMap.newKeySet();
    private final Map<BlockPos, BlockUpdateSnapshot> pendingBlockSnapshots = new ConcurrentHashMap<>();
    private final Set<BlockPos> pendingLightBlockUpdates = ConcurrentHashMap.newKeySet();
    private final Map<BlockPos, BlockUpdateSnapshot> deferredLightBlockSnapshots = new ConcurrentHashMap<>();
    private final AtomicBoolean blockUpdateFlushQueued = new AtomicBoolean(false);

    public BlockUpdateQueue() {
        // collections initialised above
    }

    /**
     * Enqueues a block position for update (no pre-captured state).
     * The snapshot must be provided separately via {@link #enqueueSnapshot}.
     */
    void enqueuePosition(BlockPos blockPos) {
        this.pendingBlockUpdates.add(blockPos);
    }

    /**
     * Stores the snapshot associated with a pending block position.
     */
    void enqueueSnapshot(BlockPos blockPos, BlockUpdateSnapshot snapshot) {
        this.pendingBlockSnapshots.put(blockPos, snapshot);
    }

    /**
     * Marks a block position as also requiring a light update when flushed.
     */
    void enqueueLight(BlockPos blockPos) {
        this.pendingLightBlockUpdates.add(blockPos);
    }

    /**
     * Combined enqueue used by the internal queueSingleBlockUpdate path.
     * Adds the position, stores the snapshot, and optionally marks for light refresh.
     */
    void enqueueSingleUpdate(BlockUpdateSnapshot snapshot, boolean refreshLight) {
        BlockPos blockPos = snapshot.blockPos();
        this.pendingBlockUpdates.add(blockPos);
        this.pendingBlockSnapshots.put(blockPos, snapshot);
        if (refreshLight) {
            this.pendingLightBlockUpdates.add(blockPos);
        }
    }

    /**
     * Stores a snapshot that is deferred until its owning chunk is loaded.
     */
    void enqueueDeferredLightUpdate(BlockUpdateSnapshot snapshot) {
        this.deferredLightBlockSnapshots.put(snapshot.blockPos(), snapshot);
    }

    /**
     * Removes and returns all deferred light snapshots whose block positions fall
     * inside the given chunk, sorted by position for deterministic application.
     */
    List<BlockUpdateSnapshot> drainDeferredLightUpdatesForChunk(at.redi2go.photonic.client.rendering.world.position.PChunkPos chunkPos) {
        if (this.deferredLightBlockSnapshots.isEmpty()) {
            return List.of();
        }
        List<BlockUpdateSnapshot> result = new ArrayList<>();
        Iterator<Entry<BlockPos, BlockUpdateSnapshot>> itr = this.deferredLightBlockSnapshots.entrySet().iterator();
        while (itr.hasNext()) {
            Entry<BlockPos, BlockUpdateSnapshot> entry = itr.next();
            BlockPos blockPos = entry.getKey();
            if ((blockPos.getX() >> 4) == chunkPos.x
                    && (blockPos.getY() >> 4) == chunkPos.y
                    && (blockPos.getZ() >> 4) == chunkPos.z) {
                result.add(entry.getValue());
                itr.remove();
            }
        }
        result.sort(Comparator
            .comparingInt((BlockUpdateSnapshot s) -> s.blockPos().getX())
            .thenComparingInt(s -> s.blockPos().getY())
            .thenComparingInt(s -> s.blockPos().getZ()));
        return result;
    }

    /**
     * Removes a specific position from the deferred light snapshot map.
     * Called when a block is being refreshed and the deferred entry is no longer needed.
     */
    void removeDeferredLightUpdate(BlockPos blockPos) {
        this.deferredLightBlockSnapshots.remove(blockPos);
    }

    /**
     * Returns true if there are no deferred light block snapshots pending.
     */
    boolean hasDeferredLightUpdates() {
        return !this.deferredLightBlockSnapshots.isEmpty();
    }

    /**
     * Drains the pending queues and invokes the callback for each update.
     * Called from the compiler thread. The callback runs synchronously and may
     * apply side effects (chunk refresh, light marking, etc.).
     * After draining, if more updates arrived, schedules another flush via the
     * provided reschedule runnable.
     */
    public void flushPendingBlockUpdates(BlockUpdateCallback callback, Runnable onReschedule) {
        List<BlockPos> pendingUpdates = new ArrayList<>(this.pendingBlockUpdates);
        if (pendingUpdates.isEmpty()) {
            this.blockUpdateFlushQueued.set(false);
            return;
        }

        this.pendingBlockUpdates.removeAll(pendingUpdates);
        Set<BlockPos> lightUpdates = new HashSet<>(this.pendingLightBlockUpdates);
        this.pendingLightBlockUpdates.removeAll(lightUpdates);
        pendingUpdates.sort(Comparator
            .comparingInt(BlockPos::getX)
            .thenComparingInt(BlockPos::getY)
            .thenComparingInt(BlockPos::getZ));
        this.blockUpdateFlushQueued.set(false);
        for (BlockPos blockPos : pendingUpdates) {
            boolean refreshLight = lightUpdates.contains(blockPos);
            BlockUpdateSnapshot snapshot = this.pendingBlockSnapshots.remove(blockPos);
            callback.onUpdate(blockPos, snapshot, refreshLight);
        }
        if (!this.pendingBlockUpdates.isEmpty() && this.blockUpdateFlushQueued.compareAndSet(false, true)) {
            onReschedule.run();
        }
    }

    /**
     * Returns true if at least one update is pending.
     */
    public boolean hasPendingUpdates() {
        return !this.pendingBlockUpdates.isEmpty();
    }

    /**
     * Returns approximate pending count (for profiling).
     */
    public int pendingCount() {
        return this.pendingBlockUpdates.size();
    }

    /**
     * Compare-and-set used by the caller to ensure only one flush is scheduled.
     * Returns true if the caller is responsible for actually scheduling the flush.
     */
    public boolean tryScheduleFlush() {
        return this.blockUpdateFlushQueued.compareAndSet(false, true);
    }

    /**
     * Resets the flush-scheduled flag (called from the flusher after draining).
     */
    public void clearFlushScheduled() {
        this.blockUpdateFlushQueued.set(false);
    }

    /**
     * Callback invoked for each pending block update during {@link #flushPendingBlockUpdates}.
     *
     * <p>The {@code snapshot} may be {@code null} if no snapshot was pre-captured; callers
     * should re-read world state in that case.
     */
    public interface BlockUpdateCallback {
        void onUpdate(BlockPos pos, @Nullable BlockUpdateSnapshot snapshot, boolean refreshLight);
    }
}
