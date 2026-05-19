package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.BlockRegistry;
import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.PhotonicsStorage;
import at.redi2go.photonic.client.rendering.MinecraftAccessor;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.position.PBlockPos;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import java.util.concurrent.ConcurrentLinkedQueue;
import net.irisshaders.iris.uniforms.SystemTimeUniforms;
import net.minecraft.client.world.ClientWorld;
import net.minecraft.util.math.BlockPos;
import org.joml.Vector3d;
import org.joml.Vector3f;

/**
 * Owns the per-frame build state machine: IDLE → COMPILE → WAIT_FOR_UPLOAD → UPLOAD.
 *
 * <p>Design choice: {@code compileWorld} and {@code upload} accept a {@code WorldRegistry self}
 * parameter rather than a large BuildContext record.  Both methods reference ~15 WorldRegistry
 * fields (profiling counters, coordinate state, collaborator references) that are not being
 * extracted.  Passing the owner object is the smaller diff and avoids a 15-field record that
 * would have to be kept in sync with every future WorldRegistry change.
 */
public final class WorldBuildOrchestrator {

    private WorldRegistry.BuildStage buildStage = WorldRegistry.BuildStage.IDLE;
    private final ConcurrentLinkedQueue<Runnable> buildQueue = new ConcurrentLinkedQueue<>();
    private final ConcurrentLinkedQueue<Runnable> glQueue = new ConcurrentLinkedQueue<>();
    private boolean dirty;
    private boolean rootDataValid;
    private int firstBuildFrame = -1;
    private boolean closeChunkUpdate;

    public WorldBuildOrchestrator() { }

    // -------------------------------------------------------------------------
    // State accessors
    // -------------------------------------------------------------------------

    public WorldRegistry.BuildStage getBuildStage() {
        return buildStage;
    }

    public boolean isDirty() {
        return dirty;
    }

    public boolean isRootDataValid() {
        return rootDataValid;
    }

    public int getFirstBuildFrame() {
        return firstBuildFrame;
    }

    public boolean isCloseChunkUpdate() {
        return closeChunkUpdate;
    }

    public boolean hasPendingBuildWork() {
        return !buildQueue.isEmpty();
    }

    // -------------------------------------------------------------------------
    // State mutators
    // -------------------------------------------------------------------------

    public void changeBuildStage(WorldRegistry.BuildStage stage) {
        if (stage.before != this.buildStage) {
            throw new IllegalStateException();
        }
        this.buildStage = stage;
    }

    public void markDirty() {
        dirty = true;
    }

    public void clearDirty() {
        dirty = false;
    }

    public void markRootDataValid() {
        rootDataValid = true;
    }

    public void invalidateRootData() {
        rootDataValid = false;
    }

    public void setFirstBuildFrame(int frame) {
        firstBuildFrame = frame;
    }

    public void requestCloseChunkUpdate() {
        closeChunkUpdate = true;
    }

    // -------------------------------------------------------------------------
    // Queue operations
    // -------------------------------------------------------------------------

    public void queueBuildJob(Runnable r) {
        buildQueue.add(r);
    }

    public void queueGlJob(Runnable r) {
        glQueue.add(r);
    }

    public ConcurrentLinkedQueue<Runnable> getGlQueue() {
        return glQueue;
    }

    public Runnable pollBuildJob() {
        return buildQueue.poll();
    }

    public boolean isBuildQueueEmpty() {
        return buildQueue.isEmpty();
    }

    public void drainBuildQueue() {
        buildQueue.clear();
    }

    public void drainGlQueue() {
        glQueue.clear();
    }

    // -------------------------------------------------------------------------
    // compileWorld — exact body from WorldRegistry.compileWorld(), zero changes
    // -------------------------------------------------------------------------

    /**
     * Runs one build frame.  All collaborator references that live in WorldRegistry are
     * passed as parameters; the {@code self} parameter covers the remaining WorldRegistry
     * state that is not being extracted (profiling counters, coordinate fields, etc.).
     */
    public void compileWorld(
            WorldRegistry self,
            LightRegistry lightRegistry,
            LightBlendController lightBlend) {

        if (buildStage != WorldRegistry.BuildStage.IDLE) {
            return;
        }

        boolean profiling = PhotonicsStorage.PROFILER_ENABLED.value;
        long t0 = profiling ? System.nanoTime() : 0;
        self.ensureWorldThread();
        changeBuildStage(WorldRegistry.BuildStage.COMPILE);
        PBlockPos previousBlockOffset = self.rtToWorldBlockOffset;

        while (!buildQueue.isEmpty()) {
            buildQueue.poll().run();
        }
        long t1 = profiling ? System.nanoTime() : 0;

        ClientWorld level = MinecraftAccessor.getLevel();
        int currentRenderFrame = SystemTimeUniforms.COUNTER.getAsInt();
        long currentWorldTick = level != null ? level.getTime() : Long.MIN_VALUE;
        Vector3f worldOffset = new Vector3f(MinecraftAccessor.getCameraPosition());
        worldOffset.floor();
        worldOffset.add(-self.worldBlockSize / 2.0F, -self.worldBlockSize / 2.0F, -self.worldBlockSize / 2.0F);
        worldOffset.mul(0.0625F);
        worldOffset.floor();
        PChunkPos newRtToWorldChunkOffset = new PChunkPos((int)worldOffset.x, (int)worldOffset.y, (int)worldOffset.z);
        boolean worldOffsetChanged = !newRtToWorldChunkOffset.equals(self.rtToWorldChunkOffset);
        self.rtToWorldChunkOffset = newRtToWorldChunkOffset;
        self.rtToWorldBlockOffset = new PChunkPos(self.rtToWorldChunkOffset.x, self.rtToWorldChunkOffset.y, self.rtToWorldChunkOffset.z).toBlockPos();
        boolean chunkTopologyChanged = false;
        boolean needsChunkDiscovery = self.chunks.isEmpty();
        self.profLoadChunkCount = 0;
        self.profLoadChunkNanos = 0;
        self.profLoadedChunkCount = 0;
        self.profUnloadedChunkCount = 0;
        if (worldOffsetChanged || self.chunkSyncNeeded || !self.pendingChunkLoads.isEmpty() || needsChunkDiscovery) {
            self.chunkSyncNeeded = false;
            chunkTopologyChanged = self.synchronizeChunks();
        }
        long t2 = profiling ? System.nanoTime() : 0;

        boolean rootUploadNeeded = worldOffsetChanged || chunkTopologyChanged || !rootDataValid;
        boolean fullRootRebuild = worldOffsetChanged || !rootDataValid;
        self.profRootOptNanos = 0;
        self.profRootUploadBytes = 0;
        self.profRootEntriesDirty = 0;
        self.profRootEntriesLoaded = 0;
        self.profRootUploadCause = rootUploadNeeded
            ? self.describeRootUploadCause(worldOffsetChanged, chunkTopologyChanged, rootDataValid)
            : "none";
        int semanticChunkMutations = self.pendingSemanticChunkMutations;
        self.pendingSemanticChunkMutations = 0;
        boolean chunkContentChanged = semanticChunkMutations > 0;
        self.update(self.rootMemoryManager, rootUploadNeeded, fullRootRebuild);
        boolean tracedLightSetDirty = self.blockLightEnabled && lightRegistry.consumeTracedLightSetDirty();
        boolean lightActivityDirty = self.blockLightEnabled && lightRegistry.consumeLightActivityDirty();
        int pendingTracedLightMutations = self.blockLightEnabled ? lightRegistry.consumePendingTracedLightMutations() : 0;
        if (self.blockLightEnabled) {
            for (BlockPos dirtyLightBlock : lightRegistry.consumeDirtyLightBlocks()) {
                self.markLightBlendBlock(dirtyLightBlock);
            }
        }
        boolean lightWorkNeeded = self.blockLightEnabled && (chunkTopologyChanged || tracedLightSetDirty || lightActivityDirty);
        String pendingResetReason = null;
        if (WorldRegistry.shouldForceTemporalResetForLightMutation(chunkTopologyChanged, pendingTracedLightMutations)) {
            pendingResetReason = "light_set";
            self.requestFullLightBlendReset(pendingResetReason);
        }
        if (WorldRegistry.shouldForceTemporalResetForWorldOffset(previousBlockOffset.toChunkPos(), self.rtToWorldChunkOffset, self.worldChunkSize)) {
            pendingResetReason = pendingResetReason == null ? "world_offset" : pendingResetReason + "+world_offset";
            self.requestFullLightBlendReset("world_offset");
        }

        long t3 = profiling ? System.nanoTime() : 0;

        boolean lightCompiled = false;
        if (lightWorkNeeded) {
            lightRegistry.compileRegistry(self.rtToWorldBlockOffset, previousBlockOffset);
            lightCompiled = true;
        }

        self.recordAutomationFrameDiagnostics(
            worldOffsetChanged,
            chunkTopologyChanged,
            chunkContentChanged,
            tracedLightSetDirty,
            lightWorkNeeded,
            lightCompiled,
            chunkTopologyChanged || tracedLightSetDirty
        );
        if (lightCompiled && profiling) {
            self.rebuildsSinceLastLog++;
            long now = System.nanoTime();
            long elapsed = now - self.lastRebuildRateLogNanos;
            if (elapsed >= 5_000_000_000L) {
                float rate = self.rebuildsSinceLastLog / (elapsed / 1_000_000_000.0f);
                Photonic.info(
                    "[Profiler] lightRebuildRate: rebuilds={} in {}s rate={}/s tracedDirty={} topology={} pendingMutations={}",
                    self.rebuildsSinceLastLog,
                    String.format("%.1f", elapsed / 1_000_000_000.0f),
                    String.format("%.1f", rate),
                    tracedLightSetDirty,
                    chunkTopologyChanged,
                    pendingTracedLightMutations
                );
                self.rebuildsSinceLastLog = 0;
                self.lastRebuildRateLogNanos = now;
            }
        }
        long t4 = profiling ? System.nanoTime() : 0;

        changeBuildStage(WorldRegistry.BuildStage.WAIT_FOR_UPLOAD);
        if (profiling) {
            long totalMs = (t4 - t0) / 1_000_000L;
            long buildQueueMs = (t1 - t0) / 1_000_000L;
            long syncMs = (t2 - t1) / 1_000_000L;
            long updateMs = (t3 - t2) / 1_000_000L;
            long rootOptMs = self.profRootOptNanos / 1_000_000L;
            long chunkUpdateMs = updateMs - rootOptMs;
            long lightMs = (t4 - t3) / 1_000_000L;
            long loadMs = self.profLoadChunkNanos / 1_000_000L;
            int dirtyCount = self.profDirtyChunkCount;
            Photonic.info(
                "[Profiler] compileWorld: total={}ms | queue={}ms sync={}ms (load={}ms x{}) update={}ms (rootOpt={}ms dirty={}ms x{}) light={}ms (compiled={} workNeeded={} tracedDirty={} offsetChanged={} topology={} rootUpload={} fullRoot={} chunkContent={} blendPendingReset={} blendPendingDirty={}) | chunks={} pending={} tracedLights={}/{}",
                totalMs, buildQueueMs, syncMs, loadMs, self.profLoadChunkCount,
                updateMs, rootOptMs, chunkUpdateMs, dirtyCount,
                lightMs, lightCompiled, lightWorkNeeded, tracedLightSetDirty, worldOffsetChanged, chunkTopologyChanged, rootUploadNeeded, fullRootRebuild, chunkContentChanged, lightBlend.isPendingFullLightBlendReset(), lightBlend.isPendingLightBlendDirty(),
                self.chunks.size(), self.pendingChunkLoads.size(),
                lightRegistry.lightCount(), lightRegistry.totalLights());
            self.logChunkChurnDiagnostics(chunkTopologyChanged);
            self.logRootUploadDiagnostics(rootUploadNeeded);
            self.logBrickUploadDiagnostics();
            Photonic.info(
                "[Profiler] lightScheduling: wantsWork={} executed={} pendingMutations={} topology={} tracedDirty={}",
                lightWorkNeeded,
                lightCompiled,
                pendingTracedLightMutations,
                chunkTopologyChanged,
                tracedLightSetDirty
            );
        }
    }

    // -------------------------------------------------------------------------
    // upload — exact body from WorldRegistry.upload(), zero changes
    // -------------------------------------------------------------------------

    /**
     * Performs the GPU upload step.  Order is preserved exactly:
     * lightRegistry → blockRegistry → cbMemoryManager → rootMemoryManager.
     */
    public void upload(
            WorldRegistry self,
            LightRegistry lightRegistry,
            BlockRegistry blockRegistry,
            GlMemoryManager cbMemoryManager,
            GlMemoryManager rootMemoryManager,
            LightBlendController lightBlend) {

        if (buildStage != WorldRegistry.BuildStage.WAIT_FOR_UPLOAD) {
            if (self.blockLightEnabled && lightRegistry.queueIdentityLightMappingsIfNeeded()) {
                lightRegistry.getPreviousLightsMemoryManager().upload();
                lightRegistry.getLightMappingMemoryManager().upload();
                lightRegistry.getLightReverseMappingMemoryManager().upload();
            }
            return;
        }
        boolean profiling = PhotonicsStorage.PROFILER_ENABLED.value;
        long profilerStart = profiling ? System.nanoTime() : 0;
        changeBuildStage(WorldRegistry.BuildStage.UPLOAD);
        boolean uploadDone = true;
        int lightUploadsBefore = lightRegistry.getLightsMemoryManager().getPendingUploadCount();
        int cbUploadsBefore = cbMemoryManager.getPendingUploadCount();
        int rootUploadsBefore = rootMemoryManager.getPendingUploadCount();
        uploadDone &= lightRegistry.upload();
        uploadDone &= blockRegistry.upload();
        uploadDone &= cbMemoryManager.upload();
        if (!uploadDone) {
            buildStage = WorldRegistry.BuildStage.WAIT_FOR_UPLOAD;
        } else {
            uploadDone &= rootMemoryManager.upload();
            if (!uploadDone) {
                buildStage = WorldRegistry.BuildStage.WAIT_FOR_UPLOAD;
                return;
            }
            self.liveWorldBlockOffset = new Vector3d(self.rtToWorldBlockOffset.x, self.rtToWorldBlockOffset.y, self.rtToWorldBlockOffset.z);
            self.liveWorldMinVoxel = self.worldMinVoxel;
            self.liveWorldMaxVoxel = self.worldMaxVoxel;
            String blendMode = "none";
            if (lightBlend.isPendingFullLightBlendReset()) {
                lightBlend.activateFullLightBlendReset(lightBlend.getPendingFullLightBlendResetReason(), self.liveWorldBlockOffset, self.worldBlockSize);
                lightBlend.clearPendingFullLightBlendReset();
                lightBlend.clearPendingLightBlendRegions();
                blendMode = "full";
            } else {
                blendMode = lightBlend.activatePendingLightBlend() ? "region" : "none";
            }
            if (closeChunkUpdate) {
                self.renderDispatcher.onChunkLoad();
                closeChunkUpdate = false;
            }
            if (firstBuildFrame < 0) {
                firstBuildFrame = Math.max(1, SystemTimeUniforms.COUNTER.getAsInt());
            }
            changeBuildStage(WorldRegistry.BuildStage.IDLE);
            if (!buildQueue.isEmpty()) {
                self.wakeUpWorldBuilder();
            }
            if (profiling) {
                long uploadMs = (System.nanoTime() - profilerStart) / 1_000_000L;
                Photonic.info("[Profiler] upload: ms={} chunks={} lights={}/{} glQueueSize={} queueBefore(light={},chunk={},root={}) uploaded(light={}B/{} ops,chunk={}B/{} ops,root={}B/{} ops)",
                    uploadMs,
                    self.chunks.size(),
                    lightRegistry.lightCount(),
                    lightRegistry.totalLights(),
                    glQueue.size(),
                    lightUploadsBefore,
                    cbUploadsBefore,
                    rootUploadsBefore,
                    lightRegistry.getLightsMemoryManager().getLastUploadedBytes(),
                    lightRegistry.getLightsMemoryManager().getLastUploadCount(),
                    cbMemoryManager.getLastUploadedBytes(),
                    cbMemoryManager.getLastUploadCount(),
                    rootMemoryManager.getLastUploadedBytes(),
                    rootMemoryManager.getLastUploadCount());
                Photonic.info("[Profiler] lightBlend: mode={} age={} globalReload={} liveRegions={} pendingRegions={} pendingDirty={}",
                    blendMode,
                    lightBlend.getLightBlendAge(),
                    self.fetchLightReload(),
                    lightBlend.getLightBlendRegionCount(),
                    lightBlend.getPendingLightBlendRegionCount(),
                    lightBlend.isPendingLightBlendDirty());
            }
        }
    }

    // -------------------------------------------------------------------------
    // afterUpload
    // -------------------------------------------------------------------------

    public void afterUpload() {
        dirty = false;
    }
}
