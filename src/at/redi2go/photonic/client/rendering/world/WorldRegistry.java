package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.BlockRegistry;
import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.PhotonicsStorage;
import at.redi2go.photonic.client.config.lights.BlockLightInfo;
import at.redi2go.photonic.client.rendering.MinecraftAccessor;
import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;
import at.redi2go.photonic.client.rendering.opengl.rendering.IRenderDispatcher;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import at.redi2go.photonic.client.rendering.world.position.PBlockPos;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Iterator;
import java.util.Map;
import java.util.PriorityQueue;
import java.util.Set;
import java.util.StringJoiner;
import java.util.Map.Entry;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.atomic.AtomicBoolean;
import net.minecraft.block.BlockState;
import net.minecraft.block.Blocks;
import net.minecraft.client.world.ClientWorld;
import net.minecraft.state.property.Property;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Direction;
import net.minecraft.world.LightType;
import net.minecraft.world.chunk.light.ChunkLightingView;
import net.irisshaders.iris.uniforms.SystemTimeUniforms;
import org.joml.Vector3d;
import org.joml.Vector3f;

public class WorldRegistry implements MemoryOwner, Destructable {
   private static final Direction[] FACES = new Direction[6];
   private static final int INITIAL_CHUNK_LOAD_BUDGET = 512;
   private static final int CHUNK_UPLOAD_BATCH_SIZE = 2048;
   private static final int ROOT_UPLOAD_BATCH_SIZE = 2048;
   private static final int LIGHT_BLEND_EXPANSION_BLOCKS = 16;
   static final int MAX_LIGHT_BLEND_REGIONS = 8;
   private static final int RT_VISIBILITY_KEEP_ALIVE_FRAMES = 96;
   private static final float RT_ALWAYS_KEEP_DISTANCE_BLOCKS = 48.0F;
   private static final float RT_MAX_RESIDENT_DISTANCE_BLOCKS = 96.0F;
   private static final float RT_RESIDENT_UNLOAD_HYSTERESIS_BLOCKS = 16.0F;
   private static final int RT_MAX_RESIDENT_CHUNKS = 192;
   private static final long CHUNK_CONTENT_HASH_OFFSET = 1469598103934665603L;
   private static final long CHUNK_CONTENT_HASH_PRIME = 1099511628211L;
   private final IRenderDispatcher renderDispatcher;
   private final WorldCompilerThread worldCompilerThread;
   private final LightRegistry lightRegistry;
   private final WorldBackend backend;
   private final GlMemoryManager cbMemoryManager;
   private final BlockRegistry blockRegistry;
   private final GlMemoryManager rootMemoryManager;
   private MemoryRegion rootMemory;
   private final Schematic rootSchematic;
   private final ConcurrentLinkedQueue<Runnable> buildQueue = new ConcurrentLinkedQueue<>();
   private final ConcurrentLinkedQueue<Runnable> glQueue = new ConcurrentLinkedQueue<>();
   private final Set<PChunkPos> pendingBuildChunks = ConcurrentHashMap.newKeySet();
   private final Map<PChunkPos, WorldChunk> chunks = new HashMap<>();
   private PBlockPos rtToWorldBlockOffset = new PBlockPos(0, 0, 0);
   private PChunkPos rtToWorldChunkOffset = new PChunkPos(0, 0, 0);
   private Vector3d liveWorldBlockOffset = new Vector3d();
   private PBlockPos liveWorldMinVoxel = new PBlockPos(0, 0, 0);
   private PBlockPos liveWorldMaxVoxel = new PBlockPos(0, 0, 0);
   private WorldRegistry.BuildStage buildStage = WorldRegistry.BuildStage.IDLE;
   private boolean closeChunkUpdate = false;
   private int lightBlendAge = 0;
   private int lastLightBlendFrame = -1;
   private Vector3f previousCameraPosition = new Vector3f();
   private boolean previousCameraPositionValid = false;
   private boolean forceTemporalReset = false;
   private String pendingFullLightBlendResetReason = "initial";
   private int lastLoggedPendingBlendCount = -1;
   private long lastLoggedPendingBlendVolume = -1L;
   private long lastLoggedPendingBlendLargest = -1L;
   private int lastLoggedChunkChurn = -1;
   private String lastLoggedRootUploadSignature = "";
   private String lastLoggedBrickUploadSignature = "";
   private static final int TEMPORAL_BLEND_FRAMES = 8;
   private final int worldBlockSize;
   private final int worldChunkSize;
   private PBlockPos worldMinVoxel = new PBlockPos(0, 0, 0);
   private PBlockPos worldMaxVoxel = new PBlockPos(0, 0, 0);
   private final PBlockPos[] pendingLightBlendMin = new PBlockPos[MAX_LIGHT_BLEND_REGIONS];
   private final PBlockPos[] pendingLightBlendMax = new PBlockPos[MAX_LIGHT_BLEND_REGIONS];
   private final PBlockPos[] liveLightBlendMin = new PBlockPos[MAX_LIGHT_BLEND_REGIONS];
   private final PBlockPos[] liveLightBlendMax = new PBlockPos[MAX_LIGHT_BLEND_REGIONS];
   private int pendingLightBlendRegionCount = 0;
   private int liveLightBlendRegionCount = 0;
   private boolean pendingLightBlendDirty = false;
   private boolean pendingFullLightBlendReset = true;
   private boolean fullLightBlendActive = false;
   private boolean dirty = true;
   private boolean rootDataValid = false;
   private int firstBuildFrame = -1;
   private final boolean blockLightEnabled;
   private volatile boolean chunkSyncNeeded = true;
   private long lastRebuildRateLogNanos = 0;
   private int rebuildsSinceLastLog = 0;
   private int chunkMutationDebugLogsRemaining = 96;
   private final PriorityQueue<PChunkPos> pendingChunkLoads = new PriorityQueue<>(
      Comparator.comparingDouble(this::chunkDistanceToCamera)
   );
   private final Set<PChunkPos> pendingChunkSet = new HashSet<>();
   private final Map<PChunkPos, Long> chunkContentHashes = new HashMap<>();
   private final Set<BlockPos> pendingBlockUpdates = ConcurrentHashMap.newKeySet();
   private final Map<BlockPos, BlockUpdateSnapshot> pendingBlockSnapshots = new ConcurrentHashMap<>();
   private final Set<BlockPos> pendingLightBlockUpdates = ConcurrentHashMap.newKeySet();
   private final Map<BlockPos, BlockUpdateSnapshot> deferredLightBlockSnapshots = new ConcurrentHashMap<>();
   private final AtomicBoolean blockUpdateFlushQueued = new AtomicBoolean(false);
   private int pendingSemanticChunkMutations = 0;
   private final Map<PChunkPos, Integer> recentlyVisibleRtChunks = new HashMap<>();
   private static final int CHUNK_LOAD_BUDGET = 256;
   private long automationResetRequestsTotal = 0L;
   private long automationResetRequestsWorldOffset = 0L;
   private long automationResetRequestsCameraJump = 0L;
   private long automationResetRequestsTopology = 0L;
   private long automationResetRequestsOther = 0L;
   private long automationBlendFullActivations = 0L;
   private long automationBlendRegionActivations = 0L;
   private long automationBlendCompletions = 0L;
   private long automationFramesGlobalReloadActive = 0L;
   private long automationFramesBlendActive = 0L;
   private long automationFramesPendingWork = 0L;
   private long automationFramesPendingStableLightCompile = 0L;
   private long automationFramesDeferredLightRebuildsPositive = 0L;
   private long automationCompileFramesLightWorkNeeded = 0L;
   private long automationCompileFramesLightCompiled = 0L;
   private long automationCompileFramesWorldOffsetChanged = 0L;
   private long automationCompileFramesChunkTopologyChanged = 0L;
   private long automationCompileFramesChunkContentChanged = 0L;
   private long automationCompileFramesTracedLightDirty = 0L;
   private long automationPendingBlendMutationEvents = 0L;
  private int automationMaxPendingBlendRegions = 0;
  private long automationMaxPendingBlendVolume = 0L;

   public WorldRegistry(
      IRenderDispatcher renderDispatcher,
      int maxLights,
      int maxLightsPerNode,
      float minTracedLightSelectionLuma,
      boolean blockLightEnabled
   ) {
      this.renderDispatcher = renderDispatcher;
      this.blockLightEnabled = blockLightEnabled;
      this.worldChunkSize = 32;
      this.worldBlockSize = 16 * this.worldChunkSize;
      this.backend = this.createBackend();
      this.rootSchematic = this.backend.getRootSchematic();
      this.lightRegistry = new LightRegistry(
         maxLights,
         maxLightsPerNode,
         minTracedLightSelectionLuma,
         8,
         this.worldBlockSize
      );
      this.cbMemoryManager = this.backend.getCbMemoryManager();
      this.cbMemoryManager.setUploadBatchSize(CHUNK_UPLOAD_BATCH_SIZE);
      this.blockRegistry = new BlockRegistry(this.cbMemoryManager.allocateRegion(4096 * PBlock.BYTE_SIZE));
      this.rootMemoryManager = this.backend.getRootMemoryManager();
      this.rootMemoryManager.setUploadBatchSize(ROOT_UPLOAD_BATCH_SIZE);
      this.worldCompilerThread = new WorldCompilerThread(this);
      this.allocate(this.rootMemoryManager);
   }

   public void upload() {
      if (this.buildStage != WorldRegistry.BuildStage.WAIT_FOR_UPLOAD) {
         if (this.blockLightEnabled && this.lightRegistry.queueIdentityLightMappingsIfNeeded()) {
            this.lightRegistry.getPreviousLightsMemoryManager().upload();
            this.lightRegistry.getLightMappingMemoryManager().upload();
            this.lightRegistry.getLightReverseMappingMemoryManager().upload();
         }
         return;
      }
      boolean profiling = PhotonicsStorage.PROFILER_ENABLED.value;
      long profilerStart = profiling ? System.nanoTime() : 0;
      this.changeBuildStage(WorldRegistry.BuildStage.UPLOAD);
      boolean uploadDone = true;
      int lightUploadsBefore = this.lightRegistry.getLightsMemoryManager().getPendingUploadCount();
      int cbUploadsBefore = this.cbMemoryManager.getPendingUploadCount();
      int rootUploadsBefore = this.rootMemoryManager.getPendingUploadCount();
      uploadDone &= this.lightRegistry.upload();
      uploadDone &= this.blockRegistry.upload();
      uploadDone &= this.cbMemoryManager.upload();
      if (!uploadDone) {
         this.buildStage = WorldRegistry.BuildStage.WAIT_FOR_UPLOAD;
      } else {
         uploadDone &= this.rootMemoryManager.upload();
         if (!uploadDone) {
            this.buildStage = WorldRegistry.BuildStage.WAIT_FOR_UPLOAD;
            return;
         }
         this.liveWorldBlockOffset = new Vector3d(this.rtToWorldBlockOffset.x, this.rtToWorldBlockOffset.y, this.rtToWorldBlockOffset.z);
         this.liveWorldMinVoxel = this.worldMinVoxel;
         this.liveWorldMaxVoxel = this.worldMaxVoxel;
         String blendMode = "none";
         if (this.pendingFullLightBlendReset) {
            this.activateFullLightBlendReset(this.pendingFullLightBlendResetReason);
            this.pendingFullLightBlendReset = false;
            this.pendingFullLightBlendResetReason = "none";
            this.clearPendingLightBlendRegions();
            blendMode = "full";
         } else {
            blendMode = this.activatePendingLightBlend() ? "region" : "none";
         }
         if (this.closeChunkUpdate) {
            this.renderDispatcher.onChunkLoad();
            this.closeChunkUpdate = false;
         }
         if (this.firstBuildFrame < 0) {
            this.firstBuildFrame = Math.max(1, SystemTimeUniforms.COUNTER.getAsInt());
         }
         this.changeBuildStage(WorldRegistry.BuildStage.IDLE);
         if (!this.buildQueue.isEmpty()) {
            this.wakeUpWorldBuilder();
         }
         if (profiling) {
            long uploadMs = (System.nanoTime() - profilerStart) / 1_000_000L;
            Photonic.info("[Profiler] upload: ms={} chunks={} lights={}/{} glQueueSize={} queueBefore(light={},chunk={},root={}) uploaded(light={}B/{} ops,chunk={}B/{} ops,root={}B/{} ops)",
               uploadMs,
               this.chunks.size(),
               this.lightRegistry.lightCount(),
               this.lightRegistry.totalLights(),
               this.glQueue.size(),
               lightUploadsBefore,
               cbUploadsBefore,
               rootUploadsBefore,
               this.lightRegistry.getLightsMemoryManager().getLastUploadedBytes(),
               this.lightRegistry.getLightsMemoryManager().getLastUploadCount(),
               this.cbMemoryManager.getLastUploadedBytes(),
               this.cbMemoryManager.getLastUploadCount(),
               this.rootMemoryManager.getLastUploadedBytes(),
               this.rootMemoryManager.getLastUploadCount());
            Photonic.info("[Profiler] lightBlend: mode={} age={} globalReload={} liveRegions={} liveVolume={} largestRegion={} pendingRegions={} pendingDirty={}",
               blendMode,
               this.lightBlendAge,
               this.fetchLightReload(),
               this.liveLightBlendRegionCount,
               totalLightBlendVolume(this.liveLightBlendMin, this.liveLightBlendMax, this.liveLightBlendRegionCount),
               largestLightBlendRegionVolume(this.liveLightBlendMin, this.liveLightBlendMax, this.liveLightBlendRegionCount),
               this.pendingLightBlendRegionCount,
               this.pendingLightBlendDirty);
         }
      }
   }

   public void compileWorld() {
      if (this.buildStage == WorldRegistry.BuildStage.IDLE) {
         boolean profiling = PhotonicsStorage.PROFILER_ENABLED.value;
         long t0 = profiling ? System.nanoTime() : 0;
         this.ensureWorldThread();
         this.changeBuildStage(WorldRegistry.BuildStage.COMPILE);
         PBlockPos previousBlockOffset = this.rtToWorldBlockOffset;

         while (!this.buildQueue.isEmpty()) {
            this.buildQueue.poll().run();
         }
         long t1 = profiling ? System.nanoTime() : 0;

         this.checkCameraJump(new Vector3f(MinecraftAccessor.getCameraPosition()));
         ClientWorld level = MinecraftAccessor.getLevel();
         int currentRenderFrame = SystemTimeUniforms.COUNTER.getAsInt();
         long currentWorldTick = level != null ? level.getTime() : Long.MIN_VALUE;
         Vector3f worldOffset = new Vector3f(MinecraftAccessor.getCameraPosition());
         worldOffset.floor();
         worldOffset.add(-this.worldBlockSize / 2.0F, -this.worldBlockSize / 2.0F, -this.worldBlockSize / 2.0F);
         worldOffset.mul(0.0625F);
         worldOffset.floor();
         PChunkPos newRtToWorldChunkOffset = new PChunkPos((int)worldOffset.x, (int)worldOffset.y, (int)worldOffset.z);
         boolean worldOffsetChanged = !newRtToWorldChunkOffset.equals(this.rtToWorldChunkOffset);
         this.rtToWorldChunkOffset = newRtToWorldChunkOffset;
         this.rtToWorldBlockOffset = new PChunkPos(this.rtToWorldChunkOffset.x, this.rtToWorldChunkOffset.y, this.rtToWorldChunkOffset.z).toBlockPos();
         boolean chunkTopologyChanged = false;
         boolean needsChunkDiscovery = this.chunks.isEmpty();
         this.profLoadChunkCount = 0;
         this.profLoadChunkNanos = 0;
         this.profLoadedChunkCount = 0;
         this.profUnloadedChunkCount = 0;
         if (worldOffsetChanged || this.chunkSyncNeeded || !this.pendingChunkLoads.isEmpty() || needsChunkDiscovery) {
            this.chunkSyncNeeded = false;
            chunkTopologyChanged = this.synchronizeChunks();
         }
         long t2 = profiling ? System.nanoTime() : 0;

         boolean rootUploadNeeded = worldOffsetChanged || chunkTopologyChanged || !this.rootDataValid;
         boolean fullRootRebuild = worldOffsetChanged || !this.rootDataValid;
         this.profRootOptNanos = 0;
         this.profRootUploadBytes = 0;
         this.profRootEntriesDirty = 0;
         this.profRootEntriesLoaded = 0;
         this.profRootUploadCause = rootUploadNeeded
            ? this.describeRootUploadCause(worldOffsetChanged, chunkTopologyChanged, this.rootDataValid)
            : "none";
         int semanticChunkMutations = this.pendingSemanticChunkMutations;
         this.pendingSemanticChunkMutations = 0;
         boolean chunkContentChanged = semanticChunkMutations > 0;
         this.update(this.rootMemoryManager, rootUploadNeeded, fullRootRebuild);
        boolean tracedLightSetDirty = this.blockLightEnabled && this.lightRegistry.consumeTracedLightSetDirty();
        boolean lightActivityDirty = this.blockLightEnabled && this.lightRegistry.consumeLightActivityDirty();
        int pendingTracedLightMutations = this.blockLightEnabled ? this.lightRegistry.consumePendingTracedLightMutations() : 0;
        if (this.blockLightEnabled) {
            for (BlockPos dirtyLightBlock : this.lightRegistry.consumeDirtyLightBlocks()) {
                this.markLightBlendBlock(dirtyLightBlock);
            }
        }
        boolean lightWorkNeeded = this.blockLightEnabled && (chunkTopologyChanged || tracedLightSetDirty || lightActivityDirty);
        String pendingResetReason = null;
        if (shouldForceTemporalResetForLightMutation(chunkTopologyChanged, pendingTracedLightMutations)) {
            pendingResetReason = "light_set";
            this.requestFullLightBlendReset(pendingResetReason);
        }
        if (shouldForceTemporalResetForWorldOffset(previousBlockOffset.toChunkPos(), this.rtToWorldChunkOffset, this.worldChunkSize)) {
            pendingResetReason = pendingResetReason == null ? "world_offset" : pendingResetReason + "+world_offset";
            this.requestFullLightBlendReset("world_offset");
        }
        if (this.forceTemporalReset) {
            if (pendingResetReason == null) {
                pendingResetReason = "camera_jump";
            } else if (!pendingResetReason.contains("camera_jump")) {
                pendingResetReason = pendingResetReason + "+camera_jump";
            }
            this.requestFullLightBlendReset("camera_jump");
            this.forceTemporalReset = false;
        }

        long t3 = profiling ? System.nanoTime() : 0;

        boolean lightCompiled = false;
        if (lightWorkNeeded) {
            this.lightRegistry.compileRegistry(this.rtToWorldBlockOffset, previousBlockOffset);
            lightCompiled = true;
        }

        this.recordAutomationFrameDiagnostics(
            worldOffsetChanged,
            chunkTopologyChanged,
            chunkContentChanged,
            tracedLightSetDirty,
            lightWorkNeeded,
            lightCompiled,
            chunkTopologyChanged || tracedLightSetDirty
        );
         if (lightCompiled && profiling) {
            this.rebuildsSinceLastLog++;
            long now = System.nanoTime();
            long elapsed = now - this.lastRebuildRateLogNanos;
            if (elapsed >= 5_000_000_000L) { // every 5 seconds
               float rate = this.rebuildsSinceLastLog / (elapsed / 1_000_000_000.0f);
               Photonic.info(
                  "[Profiler] lightRebuildRate: rebuilds={} in {}s rate={}/s tracedDirty={} topology={} pendingMutations={}",
                  this.rebuildsSinceLastLog,
                  String.format("%.1f", elapsed / 1_000_000_000.0f),
                  String.format("%.1f", rate),
                  tracedLightSetDirty,
                  chunkTopologyChanged,
                  pendingTracedLightMutations
               );
               this.rebuildsSinceLastLog = 0;
               this.lastRebuildRateLogNanos = now;
            }
         }
         long t4 = profiling ? System.nanoTime() : 0;

         this.changeBuildStage(WorldRegistry.BuildStage.WAIT_FOR_UPLOAD);
         if (profiling) {
            long totalMs = (t4 - t0) / 1_000_000L;
            long buildQueueMs = (t1 - t0) / 1_000_000L;
            long syncMs = (t2 - t1) / 1_000_000L;
            long updateMs = (t3 - t2) / 1_000_000L;
            long rootOptMs = this.profRootOptNanos / 1_000_000L;
            long chunkUpdateMs = updateMs - rootOptMs;
            long lightMs = (t4 - t3) / 1_000_000L;
            long loadMs = this.profLoadChunkNanos / 1_000_000L;
            int dirtyCount = this.profDirtyChunkCount;
            Photonic.info(
               "[Profiler] compileWorld: total={}ms | queue={}ms sync={}ms (load={}ms x{}) update={}ms (rootOpt={}ms dirty={}ms x{}) light={}ms (compiled={} workNeeded={} tracedDirty={} offsetChanged={} topology={} rootUpload={} fullRoot={} chunkContent={} blendPendingReset={} blendPendingDirty={}) | chunks={} pending={} tracedLights={}/{}",
               totalMs, buildQueueMs, syncMs, loadMs, this.profLoadChunkCount,
               updateMs, rootOptMs, chunkUpdateMs, dirtyCount,
               lightMs, lightCompiled, lightWorkNeeded, tracedLightSetDirty, worldOffsetChanged, chunkTopologyChanged, rootUploadNeeded, fullRootRebuild, chunkContentChanged, this.pendingFullLightBlendReset, this.pendingLightBlendDirty,
               this.chunks.size(), this.pendingChunkLoads.size(),
               this.lightRegistry.lightCount(), this.lightRegistry.totalLights());
            this.logChunkChurnDiagnostics(chunkTopologyChanged);
            this.logRootUploadDiagnostics(rootUploadNeeded);
            this.logBrickUploadDiagnostics();
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
   }

   private int profLoadChunkCount;
   private long profLoadChunkNanos;
   private long profRootOptNanos;
   private int profDirtyChunkCount;
   private int profLoadedChunkCount;
   private int profUnloadedChunkCount;
   private int profRootUploadBytes;
   private int profRootEntriesDirty;
   private int profRootEntriesLoaded;
   private String profRootUploadCause = "none";

   private boolean isRtChunkResidencyFrozenForDebug() {
      return Boolean.getBoolean("photonics.freezeRtChunkResidency");
   }

   public boolean synchronizeChunks() {
      this.ensureWorldThread();
      Set<PChunkPos> inboundNonEmptyChunks = new HashSet<>();
      int frame = SystemTimeUniforms.COUNTER.getAsInt();

      for (PChunkPos chunkPos : this.renderDispatcher.getInboundChunks()) {
         if (!this.renderDispatcher.isChunkEmpty(chunkPos) && this.shouldKeepChunkForRt(chunkPos)) {
            PChunkPos rtChunkPos = new PChunkPos(
               chunkPos.x - this.rtToWorldChunkOffset.x, chunkPos.y - this.rtToWorldChunkOffset.y, chunkPos.z - this.rtToWorldChunkOffset.z
            );
            if (isRtChunkInBounds(rtChunkPos)) {
               inboundNonEmptyChunks.add(chunkPos);
               this.recentlyVisibleRtChunks.put(chunkPos, frame);
            }
         }
      }

      this.recentlyVisibleRtChunks.entrySet().removeIf(entry -> frame - entry.getValue() > RT_VISIBILITY_KEEP_ALIVE_FRAMES);

      boolean changed = false;

      for (PChunkPos chunkPosx : inboundNonEmptyChunks) {
         if (!this.chunks.containsKey(chunkPosx) && this.pendingChunkSet.add(chunkPosx)) {
            this.pendingChunkLoads.add(chunkPosx);
         }
      }

      this.pendingChunkLoads.removeIf(pos -> {
         if (!inboundNonEmptyChunks.contains(pos)) {
            this.pendingChunkSet.remove(pos);
            return true;
         }
         return false;
      });

      int trimmedChunkCount = this.trimResidentChunksToCameraBudget(inboundNonEmptyChunks);
      if (trimmedChunkCount > 0) {
         changed = true;
      }

      int residentBudgetRemaining = Math.max(0, RT_MAX_RESIDENT_CHUNKS - this.chunks.size());
      int chunkLoadBudget = Math.min(this.chunks.isEmpty() ? INITIAL_CHUNK_LOAD_BUDGET : CHUNK_LOAD_BUDGET, residentBudgetRemaining);
      List<PChunkPos> chunksToLoad = new ArrayList<>();
      while (!this.pendingChunkLoads.isEmpty() && chunksToLoad.size() < chunkLoadBudget) {
         PChunkPos nextChunk = this.pendingChunkLoads.poll();
         this.pendingChunkSet.remove(nextChunk);
         if (inboundNonEmptyChunks.contains(nextChunk) && !this.chunks.containsKey(nextChunk)) {
            chunksToLoad.add(nextChunk);
         }
      }

      if (!chunksToLoad.isEmpty()) {
         changed = true;
         this.profLoadedChunkCount = chunksToLoad.size();
         long clStart = PhotonicsStorage.PROFILER_ENABLED.value ? System.nanoTime() : 0;
         for (PChunkPos chunkPos : chunksToLoad) {
            this.loadChunk(chunkPos);
         }
         if (clStart != 0) {
            this.profLoadChunkNanos = System.nanoTime() - clStart;
            this.profLoadChunkCount = chunksToLoad.size();
         }
      }

      if (!this.isRtChunkResidencyFrozenForDebug()) {
         for (PChunkPos chunkPosxx : this.chunks.keySet().toArray(new PChunkPos[0])) {
            if (inboundNonEmptyChunks.contains(chunkPosxx)) {
               continue;
            }

            if (this.shouldRetainLoadedRtChunk(chunkPosxx)) {
               continue;
            }

            Integer lastVisibleFrame = this.recentlyVisibleRtChunks.get(chunkPosxx);
            if (lastVisibleFrame != null && frame - lastVisibleFrame <= RT_VISIBILITY_KEEP_ALIVE_FRAMES) {
               continue;
            }

            this.unloadChunk(chunkPosxx);
            this.profUnloadedChunkCount++;
            changed = true;
         }
      }

      this.worldMinVoxel = new PBlockPos(Integer.MAX_VALUE, Integer.MAX_VALUE, Integer.MAX_VALUE);
      this.worldMaxVoxel = new PBlockPos(Integer.MIN_VALUE, Integer.MIN_VALUE, Integer.MIN_VALUE);

      for (PChunkPos chunkPosxxx : this.chunks.keySet()) {
         PBlockPos blockPos = chunkPosxxx.toBlockPos();
         this.worldMinVoxel.min(blockPos.x, blockPos.y, blockPos.z);
         this.worldMaxVoxel.max(blockPos.x, blockPos.y, blockPos.z);
      }

      this.worldMinVoxel.sub(this.rtToWorldBlockOffset.x, this.rtToWorldBlockOffset.y, this.rtToWorldBlockOffset.z);
      this.worldMinVoxel.scale(16, 16, 16);
      this.worldMaxVoxel.add(16, 16, 16);
      this.worldMaxVoxel.sub(this.rtToWorldBlockOffset.x, this.rtToWorldBlockOffset.y, this.rtToWorldBlockOffset.z);
      this.worldMaxVoxel.scale(16, 16, 16);
      return changed;
   }

   private boolean shouldKeepChunkForRt(PChunkPos chunkPos) {
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

   private boolean shouldRetainLoadedRtChunk(PChunkPos chunkPos) {
      float retainDistance = RT_MAX_RESIDENT_DISTANCE_BLOCKS + RT_RESIDENT_UNLOAD_HYSTERESIS_BLOCKS;
      return this.chunkDistanceToCamera(chunkPos) <= retainDistance * retainDistance;
   }

   private int trimResidentChunksToCameraBudget(Set<PChunkPos> inboundNonEmptyChunks) {
      if (this.chunks.size() <= RT_MAX_RESIDENT_CHUNKS) {
         return 0;
      }

      List<PChunkPos> loadedChunks = new ArrayList<>(this.chunks.keySet());
      loadedChunks.sort(Comparator.comparingDouble(this::chunkRetentionPriority).reversed());
      int trimmedChunkCount = 0;
      for (PChunkPos chunkPos : collectTrimEligibleChunks(loadedChunks, RT_MAX_RESIDENT_CHUNKS, inboundNonEmptyChunks)) {
         this.unloadChunk(chunkPos);
         this.profUnloadedChunkCount++;
         trimmedChunkCount++;
      }
      return trimmedChunkCount;
   }

   static List<PChunkPos> collectTrimEligibleChunks(List<PChunkPos> loadedChunks, int residentChunkBudget, Set<PChunkPos> inboundNonEmptyChunks) {
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

   private double chunkRetentionPriority(PChunkPos chunkPos) {
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
      boolean recentlyVisible = this.recentlyVisibleRtChunks.containsKey(chunkPos);
      return inverseDistance + (recentlyVisible ? 0.5 : 0.0);
   }
   private double chunkDistanceToCamera(PChunkPos chunkPos) {
      Vector3f cameraPosition = new Vector3f(MinecraftAccessor.getCameraPosition());
      PBlockPos blockPos = chunkPos.toBlockPos();
      float dx = blockPos.x + 8.0F - cameraPosition.x;
      float dy = blockPos.y + 8.0F - cameraPosition.y;
      float dz = blockPos.z + 8.0F - cameraPosition.z;
      return dx * dx + dy * dy + dz * dz;
   }

   public void loadChunk(PChunkPos chunkPos) {
      this.ensureWorldThread();
      ClientWorld level = MinecraftAccessor.getLevel();
      if (!this.isClientChunkReadable(level, chunkPos)) {
         return;
      }

      boolean[] chunkCreated = new boolean[1];
      WorldChunk chunk = this.chunks.computeIfAbsent(chunkPos, k -> {
         WorldChunk newChunk = this.createChunk();
         newChunk.allocate(this.cbMemoryManager);
         chunkCreated[0] = true;
         return newChunk;
      });
      if (!chunkCreated[0]) {
         this.refreshResidentChunk(level, chunkPos, chunk);
         return;
      }

      this.pendingSemanticChunkMutations++;
      this.onChunkLoad(chunkPos);
      this.markRootEntryDirty(chunkPos);
      this.markLightBlendChunk(chunkPos);
      this.chunkContentHashes.put(chunkPos, this.populateChunkContents(level, chunkPos, chunk));
      if (this.blockLightEnabled) {
         this.lightRegistry.synchronizeChunkLights(level, chunkPos);
      }
      this.applyDeferredChunkLightUpdates(chunkPos, chunk);
   }

   private void refreshResidentChunk(ClientWorld level, PChunkPos chunkPos, WorldChunk chunk) {
      if (!this.isClientChunkReadable(level, chunkPos)) {
         return;
      }

      long currentContentHash = this.computeChunkContentHash(level, chunkPos);
      Long previousContentHash = this.chunkContentHashes.get(chunkPos);
      if (previousContentHash != null && previousContentHash == currentContentHash) {
         this.applyDeferredChunkLightUpdates(chunkPos, chunk);
         return;
      }

      this.chunkContentHashes.put(chunkPos, this.populateChunkContents(level, chunkPos, chunk));
      if (this.blockLightEnabled) {
         this.lightRegistry.synchronizeChunkLights(level, chunkPos);
      }
      this.applyDeferredChunkLightUpdates(chunkPos, chunk);
   }

   private void applyDeferredChunkLightUpdates(PChunkPos chunkPos, WorldChunk chunk) {
      if (this.deferredLightBlockSnapshots.isEmpty()) {
         return;
      }
      ClientWorld level = MinecraftAccessor.getLevel();
      if (level == null) {
         return;
      }
      List<BlockUpdateSnapshot> deferredSnapshots = new ArrayList<>();
      Iterator<Entry<BlockPos, BlockUpdateSnapshot>> itr = this.deferredLightBlockSnapshots.entrySet().iterator();
      while (itr.hasNext()) {
         Entry<BlockPos, BlockUpdateSnapshot> entry = itr.next();
         BlockPos blockPos = entry.getKey();
         if ((blockPos.getX() >> 4) == chunkPos.x && (blockPos.getY() >> 4) == chunkPos.y && (blockPos.getZ() >> 4) == chunkPos.z) {
            deferredSnapshots.add(entry.getValue());
            itr.remove();
         }
      }
      deferredSnapshots.sort(Comparator
         .comparingInt((BlockUpdateSnapshot snapshot) -> snapshot.blockPos().getX())
         .thenComparingInt(snapshot -> snapshot.blockPos().getY())
         .thenComparingInt(snapshot -> snapshot.blockPos().getZ()));
      for (BlockUpdateSnapshot snapshot : deferredSnapshots) {
         BlockPos blockPos = snapshot.blockPos();
         if (this.refreshChunkBlock(level, chunkPos, chunk, blockPos, snapshot.blockState())) {
            this.chunkContentHashes.remove(chunkPos);
            this.pendingSemanticChunkMutations++;
            this.markLightBlendBlock(blockPos);
         }
         if (this.blockLightEnabled) {
            this.lightRegistry.onBlockUpdate(blockPos, snapshot.blockState(), snapshot.lightInfo());
         }
      }
   }

   private long populateChunkContents(ClientWorld level, PChunkPos chunkPos, WorldChunk chunk) {
      chunk.freeBlocks();
      ChunkLightingView skyLightView = level != null ? level.getLightingProvider().get(LightType.SKY) : null;
      PBlockPos chunkMin = chunkPos.toBlockPos();
      BlockPos.Mutable mutableBlockPos = new BlockPos.Mutable();
      long hash = CHUNK_CONTENT_HASH_OFFSET;

      for (int x = 0; x < 16; x++) {
         for (int y = 0; y < 16; y++) {
            for (int z = 0; z < 16; z++) {
               mutableBlockPos.set(chunkMin.x + x, chunkMin.y + y, chunkMin.z + z);
               BlockState blockState = this.captureBlockStateSnapshot(level, mutableBlockPos);
               BlockState rtBlockState = this.toRtContentBlockState(blockState);
               int skyBrightness = this.computeSkyBrightness(skyLightView, mutableBlockPos);
               hash = mixChunkContentHash(hash, rtBlockState.hashCode());
               hash = mixChunkContentHash(hash, skyBrightness);

               PBlock block = this.blockRegistry.getBlock(rtBlockState);
               if (block != null) {
                  if (!block.isUsed() || !block.isAllocated()) {
                     synchronized (block) {
                        this.blockRegistry.ensureAllocated(block);
                        if (block.getMemory() == null) {
                           block = null;
                        }
                     }
                  }
               }
               if (block == null) {
                  chunk.set(x, y, z, null, -1);
               } else {
                  chunk.set(x, y, z, block, skyBrightness);
               }
            }
         }
      }
      return hash;
   }

   private long computeChunkContentHash(ClientWorld level, PChunkPos chunkPos) {
      ChunkLightingView skyLightView = level.getLightingProvider().get(LightType.SKY);
      PBlockPos chunkMin = chunkPos.toBlockPos();
      BlockPos.Mutable mutableBlockPos = new BlockPos.Mutable();
      long hash = CHUNK_CONTENT_HASH_OFFSET;

      for (int x = 0; x < 16; x++) {
         for (int y = 0; y < 16; y++) {
            for (int z = 0; z < 16; z++) {
               mutableBlockPos.set(chunkMin.x + x, chunkMin.y + y, chunkMin.z + z);
               BlockState blockState = this.captureBlockStateSnapshot(level, mutableBlockPos);
               BlockState rtBlockState = this.toRtContentBlockState(blockState);
               hash = mixChunkContentHash(hash, rtBlockState.hashCode());
               hash = mixChunkContentHash(hash, this.computeSkyBrightness(skyLightView, mutableBlockPos));
            }
         }
      }

      return hash;
   }

   private boolean isClientChunkReadable(ClientWorld level, PChunkPos chunkPos) {
      if (level == null) {
         return false;
      }

      PBlockPos chunkMin = chunkPos.toBlockPos();
      return level.isChunkLoaded(new BlockPos(chunkMin.x, chunkMin.y, chunkMin.z));
   }

   private boolean isClientBlockReadable(ClientWorld level, BlockPos blockPos) {
      return level != null && level.isChunkLoaded(blockPos);
   }

   private static long mixChunkContentHash(long hash, int value) {
      return (hash ^ Integer.toUnsignedLong(value)) * CHUNK_CONTENT_HASH_PRIME;
   }

   public void unloadChunk(PChunkPos chunkPos) {
      this.ensureWorldThread();
      this.pendingSemanticChunkMutations++;
      this.markLightBlendChunk(chunkPos);
      this.chunkContentHashes.remove(chunkPos);
      if (this.blockLightEnabled) {
         this.lightRegistry.clearChunkLights(chunkPos);
      }
      this.markRootEntryDirty(chunkPos);
      WorldChunk chunk = this.chunks.remove(chunkPos);
      if (chunk != null) {
         chunk.free(this.cbMemoryManager);
         chunk.freeBlocks();
      }
   }

   private WorldBackend createBackend() {
      return new BrickWorldBackend(this.worldChunkSize, this.chunks);
   }

   private WorldChunk createChunk() {
      return new BrickChunk();
   }

   private void markRootEntryDirty(PChunkPos chunkPos) {
      this.backend.markRootEntryDirty(chunkPos, this.rtToWorldChunkOffset, this.worldChunkSize);
   }

   private PChunkPos toRtChunkPos(PChunkPos chunkPos) {
      PChunkPos rtChunkPos = new PChunkPos(chunkPos.x, chunkPos.y, chunkPos.z);
      rtChunkPos.sub(this.rtToWorldChunkOffset.x, this.rtToWorldChunkOffset.y, this.rtToWorldChunkOffset.z);
      return rtChunkPos;
   }

   private boolean isRtChunkInBounds(PChunkPos rtChunkPos) {
      return rtChunkPos.x >= 0 && rtChunkPos.x < this.worldChunkSize
         && rtChunkPos.y >= 0 && rtChunkPos.y < this.worldChunkSize
         && rtChunkPos.z >= 0 && rtChunkPos.z < this.worldChunkSize;
   }

   @Override
   public void allocate(MemoryManager memoryManager) {
      this.rootMemory = memoryManager.allocate(this.getSize());
      this.backend.setRootMemory(this.rootMemory);
   }

   @Override
   public void free(MemoryManager memoryManager) {
      memoryManager.free(this.rootMemory);
      this.rootMemory = null;
      this.backend.setRootMemory(null);
   }

   @Override
   public boolean update(MemoryManager memoryManager) {
      return this.update(memoryManager, true);
   }

   public boolean update(MemoryManager memoryManager, boolean forceRootUpload) {
      return this.update(memoryManager, forceRootUpload, forceRootUpload);
   }

   public boolean update(MemoryManager memoryManager, boolean forceRootUpload, boolean fullRootRebuild) {
      if (!forceRootUpload) {
         boolean anyChunkDirty = false;
         for (WorldChunk chunk : this.chunks.values()) {
            if (chunk.isDirty()) {
               anyChunkDirty = true;
               break;
            }
         }
         if (!anyChunkDirty) {
            this.dirty = false;
            return false;
         }
      }

      if (fullRootRebuild) {
         Arrays.fill(this.rootSchematic.getData(), 0);
         this.rootDataValid = false;
      }

      List<CompletableFuture<Void>> pendingOptimizations = new ArrayList<>();
      List<WorldChunk> dirtyChunks = new ArrayList<>();

      for (Entry<PChunkPos, WorldChunk> entry : this.chunks.entrySet()) {
         PChunkPos chunkPos = entry.getKey();
         WorldChunk chunk = entry.getValue();
         PChunkPos rtChunkPos = this.toRtChunkPos(chunkPos);
         if (!isRtChunkInBounds(rtChunkPos)) {
            continue;
         }

         if (chunk.isDirty()) {
            pendingOptimizations.add(chunk.optimizeAsync());
            dirtyChunks.add(chunk);
         }
      }

      this.profDirtyChunkCount = dirtyChunks.size();

      if (!pendingOptimizations.isEmpty()) {
         try {
            CompletableFuture.allOf(pendingOptimizations.toArray(CompletableFuture[]::new)).get();
         } catch (ExecutionException | InterruptedException e) {
            throw new RuntimeException(e);
         }
         for (WorldChunk chunk : dirtyChunks) {
            chunk.finishUpdate(this.cbMemoryManager);
         }
      }

      if (forceRootUpload) {
         this.profRootEntriesLoaded = this.countLoadedRootEntries();
         this.profRootEntriesDirty = fullRootRebuild ? this.profRootEntriesLoaded : this.profDirtyChunkCount + this.profLoadedChunkCount + this.profUnloadedChunkCount;
         this.profRootUploadBytes = this.rootSchematic.getData().length * Integer.BYTES;
         this.backend.updateRootData(this.rtToWorldChunkOffset, this.worldChunkSize, fullRootRebuild || !this.rootDataValid);
         this.rootDataValid = true;
      }

      this.dirty = true;
      return true;
   }


   private int countLoadedRootEntries() {
      int count = 0;
      for (Entry<PChunkPos, WorldChunk> entry : this.chunks.entrySet()) {
         if (entry.getValue().getMemory() == null) {
            continue;
         }
         if (this.isRtChunkInBounds(this.toRtChunkPos(entry.getKey()))) {
            count++;
         }
      }
      return count;
   }

   private String describeRootUploadCause(boolean worldOffsetChanged, boolean chunkTopologyChanged, boolean rootDataValid) {
      if (!rootDataValid) {
         return "initial";
      }
      if (worldOffsetChanged && chunkTopologyChanged) {
         return "offset+topology";
      }
      if (worldOffsetChanged) {
         return "offset";
      }
      if (chunkTopologyChanged) {
         return "topology";
      }
      return "dirty_chunks";
   }

   private void logChunkChurnDiagnostics(boolean chunkTopologyChanged) {
      if (!chunkTopologyChanged) {
         this.lastLoggedChunkChurn = -1;
         return;
      }
      int churn = this.profLoadedChunkCount + this.profUnloadedChunkCount;
      if (churn == 0) {
         this.lastLoggedChunkChurn = -1;
         return;
      }
      if (churn == this.lastLoggedChunkChurn) {
         return;
      }
      this.lastLoggedChunkChurn = churn;
      Photonic.info(
         "[Profiler] chunkChurn: loaded={} unloaded={} pendingLoads={} resident={} chunkSyncNeeded={} loadBudget={} loadTime={}ms residency(mode={},near={}m,ttl={})",
         this.profLoadedChunkCount,
         this.profUnloadedChunkCount,
         this.pendingChunkLoads.size(),
         this.chunks.size(),
         this.chunkSyncNeeded,
         this.chunks.isEmpty() ? INITIAL_CHUNK_LOAD_BUDGET : CHUNK_LOAD_BUDGET,
         this.profLoadChunkNanos / 1_000_000L,
         "omnidirectional",
         RT_ALWAYS_KEEP_DISTANCE_BLOCKS / 16.0F,
         RT_VISIBILITY_KEEP_ALIVE_FRAMES
      );
   }

   private void logRootUploadDiagnostics(boolean rootUploadNeeded) {
      if (!rootUploadNeeded || this.profRootUploadBytes <= 0) {
         this.lastLoggedRootUploadSignature = "";
         return;
      }
      String signature = this.profRootUploadCause
         + '|'
         + this.profRootEntriesDirty
         + '|'
         + this.profRootEntriesLoaded
         + '|'
         + this.profRootUploadBytes
         + '|'
         + this.rootMemoryManager.getPendingUploadCount();
      if (signature.equals(this.lastLoggedRootUploadSignature)) {
         return;
      }
      this.lastLoggedRootUploadSignature = signature;
      Photonic.info(
         "[Profiler] rootUpload: cause={} entriesDirty={} entriesLoaded={} bytes={} pendingOps={} uploadedBytes={} uploadedOps={}",
         this.profRootUploadCause,
         this.profRootEntriesDirty,
         this.profRootEntriesLoaded,
         this.profRootUploadBytes,
         this.rootMemoryManager.getPendingUploadCount(),
         this.rootMemoryManager.getLastUploadedBytes(),
         this.rootMemoryManager.getLastUploadCount()
      );
   }

   private void logBrickUploadDiagnostics() {
      if (!(this.backend instanceof BrickWorldBackend brickBackend)) {
         this.lastLoggedBrickUploadSignature = "";
         return;
      }
      BrickWorldBackend.BrickUploadSummary summary = brickBackend.consumeUploadSummary();
      if (!summary.hasWork()) {
         summary = brickBackend.buildCurrentSummary();
         if (!summary.hasWork()) {
            this.lastLoggedBrickUploadSignature = "";
            return;
         }
      }
      String signature = new StringJoiner("|")
         .add(Integer.toString(summary.dirtyChunks))
         .add(Integer.toString(summary.dirtyVoxels))
         .add(Integer.toString(summary.chunkUploadOps))
         .add(Long.toString(summary.chunkUploadBytes))
         .add(Integer.toString(summary.populatedRootEntries))
         .add(Long.toString(summary.rootUploadBytes))
         .add(Integer.toString(summary.trackedBlockTypes))
         .add(Integer.toString(summary.trackedBlockReferences))
         .toString();
      if (signature.equals(this.lastLoggedBrickUploadSignature)) {
         return;
      }
      this.lastLoggedBrickUploadSignature = signature;
      Photonic.info(
         "[Profiler] brickUpload: dirtyChunks={} dirtyVoxels={} chunkOps={} chunkBytes={} rootEntries={} rootBytes={} trackedBlockTypes={} trackedBlockRefs={}",
         summary.dirtyChunks,
         summary.dirtyVoxels,
         summary.chunkUploadOps,
         summary.chunkUploadBytes,
         summary.populatedRootEntries,
         summary.rootUploadBytes,
         summary.trackedBlockTypes,
         summary.trackedBlockReferences
      );
   }

   @Override
   public void afterUpload() {
      this.dirty = false;
   }

   @Override
   public int getSize() {
      return 4 * this.worldChunkSize * this.worldChunkSize * this.worldChunkSize;
   }

   @Override
   public MemoryRegion getMemory() {
      return this.rootMemory;
   }

   private void onChunkLoad(PChunkPos chunkPos) {
      Vector3f cameraPosition = MinecraftAccessor.getCameraPosition();
      PBlockPos chunkBlockPos = chunkPos.toBlockPos();
      float dx = chunkBlockPos.x + 8.0F - cameraPosition.x;
      float dy = chunkBlockPos.y + 8.0F - cameraPosition.y;
      float dz = chunkBlockPos.z + 8.0F - cameraPosition.z;
      double cameraDistance = Math.sqrt(dx * dx + dy * dy + dz * dz);
      if (cameraDistance < 32.0F) {
         this.closeChunkUpdate = true;
      }
   }

   @Override
   public void free() {
      this.worldCompilerThread.free();
      this.buildQueue.clear();
      this.glQueue.clear();
      this.lightRegistry.free();
      this.blockRegistry.free();
      this.cbMemoryManager.free();
      this.rootMemoryManager.free();
   }

   public Map<PChunkPos, WorldChunk> getChunks() {
      return this.chunks;
   }

   public BlockRegistry getBlockRegistry() {
      return this.blockRegistry;
   }

   public void ensureWorldThread() {
      if (Thread.currentThread() != this.worldCompilerThread) {
         throw new IllegalStateException("Called from wrong thread!");
      }
   }

   public void queueBuildJob(Runnable job) {
      this.buildQueue.add(job);
   }

   public void queueChunkLoad(PChunkPos chunkPos) {
      if (this.pendingBuildChunks.add(chunkPos)) {
         this.buildQueue.add(() -> {
            this.pendingBuildChunks.remove(chunkPos);
            if (!this.shouldKeepChunkForRt(chunkPos) || this.chunks.containsKey(chunkPos) || this.pendingChunkSet.contains(chunkPos)) {
               return;
            }

            this.pendingChunkLoads.add(chunkPos);
            this.pendingChunkSet.add(chunkPos);
            this.chunkSyncNeeded = true;
         });
      }
   }

   public void queueBlockUpdate(BlockPos blockPos) {
      ClientWorld level = MinecraftAccessor.getLevel();
      if (!this.isClientBlockReadable(level, blockPos)) {
         return;
      }
      this.queueBlockUpdate(blockPos, this.captureBlockStateSnapshot(level, blockPos));
   }

   public void queueBlockUpdate(BlockPos blockPos, BlockState blockState) {
      ClientWorld level = MinecraftAccessor.getLevel();
      if (!this.isClientBlockReadable(level, blockPos)) {
         return;
      }
      boolean refreshBlockLight = this.shouldRefreshLightForBlockUpdate(blockPos, blockState);
      this.queueSingleBlockUpdate(this.captureBlockUpdateSnapshot(level, blockPos, blockState, refreshBlockLight), refreshBlockLight);
      for (Direction face : FACES) {
         BlockPos neighborPos = blockPos.offset(face);
         if (!this.isClientBlockReadable(level, neighborPos)) {
            continue;
         }
         BlockState neighborState = this.captureBlockStateSnapshot(level, neighborPos);
         boolean refreshNeighborLight = this.shouldRefreshLightForBlockUpdate(neighborPos, neighborState);
         this.queueSingleBlockUpdate(this.captureBlockUpdateSnapshot(level, neighborPos, neighborState, refreshNeighborLight), refreshNeighborLight);
      }
   }

   private boolean shouldRefreshLightForBlockUpdate(BlockPos blockPos, BlockState blockState) {
      return this.blockLightEnabled
         && (this.lightRegistry.hasPossibleLight(blockState) || this.lightRegistry.hasTrackedLight(blockPos));
   }

   private void queueSingleBlockUpdate(BlockUpdateSnapshot snapshot, boolean refreshLight) {
      BlockPos blockPos = snapshot.blockPos();
      this.pendingBlockUpdates.add(blockPos);
      this.pendingBlockSnapshots.put(blockPos, snapshot);
      if (refreshLight) {
         this.pendingLightBlockUpdates.add(blockPos);
      }
      if (this.blockUpdateFlushQueued.compareAndSet(false, true)) {
         this.buildQueue.add(this::flushPendingBlockUpdates);
         this.wakeUpWorldBuilder();
      }
   }

   private void flushPendingBlockUpdates() {
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
         if (snapshot == null) {
            ClientWorld level = MinecraftAccessor.getLevel();
            snapshot = this.captureBlockUpdateSnapshot(level, blockPos, this.captureBlockStateSnapshot(level, blockPos), refreshLight);
         }
         this.refreshBlock(snapshot, refreshLight);
      }
      if (!this.pendingBlockUpdates.isEmpty() && this.blockUpdateFlushQueued.compareAndSet(false, true)) {
         this.buildQueue.add(this::flushPendingBlockUpdates);
      }
   }

   private void queueDeferredLightBlockUpdate(BlockUpdateSnapshot snapshot) {
      BlockPos blockPos = snapshot.blockPos();
      this.deferredLightBlockSnapshots.put(blockPos, snapshot);
   }

   private void queueChunkRefresh(PChunkPos chunkPos) {
      if (this.pendingBuildChunks.add(chunkPos)) {
         this.buildQueue.add(() -> {
            this.pendingBuildChunks.remove(chunkPos);
            if (!this.shouldKeepChunkForRt(chunkPos) || this.pendingChunkSet.contains(chunkPos)) {
               return;
            }

            if (this.chunks.containsKey(chunkPos)) {
               this.loadChunk(chunkPos);
               return;
            }

            this.pendingChunkLoads.add(chunkPos);
            this.pendingChunkSet.add(chunkPos);
            this.chunkSyncNeeded = true;
         });
      }
   }

   private void refreshBlock(BlockUpdateSnapshot snapshot, boolean refreshLight) {
      ClientWorld level = MinecraftAccessor.getLevel();
      if (level == null) {
         return;
      }

      BlockPos blockPos = snapshot.blockPos();
      PChunkPos chunkPos = new PChunkPos(blockPos.getX() >> 4, blockPos.getY() >> 4, blockPos.getZ() >> 4);
      if (!this.shouldKeepChunkForRt(chunkPos)) {
         this.deferredLightBlockSnapshots.remove(blockPos);
         return;
      }

      WorldChunk chunk = this.chunks.get(chunkPos);
      if (chunk == null) {
         if (refreshLight) {
            this.queueDeferredLightBlockUpdate(snapshot);
         }
         if (!this.renderDispatcher.isChunkEmpty(chunkPos) && this.pendingChunkSet.add(chunkPos)) {
            this.pendingChunkLoads.add(chunkPos);
            this.chunkSyncNeeded = true;
         }
         return;
      }

      this.deferredLightBlockSnapshots.remove(blockPos);
      boolean chunkMutated = this.refreshChunkBlock(level, chunkPos, chunk, blockPos, snapshot.blockState());
      if (chunkMutated) {
         this.chunkContentHashes.remove(chunkPos);
         this.pendingSemanticChunkMutations++;
      }
      if (refreshLight && this.blockLightEnabled) {
         this.lightRegistry.onBlockUpdate(blockPos, snapshot.blockState(), snapshot.lightInfo());
      }
      if (chunkMutated) {
         this.markLightBlendBlock(blockPos);
      }
   }

   private boolean refreshChunkBlock(ClientWorld level, PChunkPos chunkPos, WorldChunk chunk, BlockPos blockPos, BlockState blockState) {
      int localX = Math.floorMod(blockPos.getX(), 16);
      int localY = Math.floorMod(blockPos.getY(), 16);
      int localZ = Math.floorMod(blockPos.getZ(), 16);
      BlockState rtBlockState = this.toRtContentBlockState(blockState);
      boolean canonicalized = rtBlockState != blockState;
      PBlock block = this.blockRegistry.getBlock(rtBlockState);
      if (block != null && (!block.isUsed() || !block.isAllocated())) {
         synchronized (block) {
            this.blockRegistry.ensureAllocated(block);
            if (block.getMemory() == null) {
               block = null;
            }
         }
      }

      ChunkLightingView skyLightView = level.getLightingProvider().get(LightType.SKY);
      int skyBrightness = block == null ? -1 : this.computeSkyBrightness(skyLightView, blockPos);
      boolean changed = chunk.set(localX, localY, localZ, block, skyBrightness);
      if (changed) {
         this.logChunkBlockMutation(blockPos, blockState, rtBlockState, canonicalized, block, skyBrightness);
      }
      return changed;
   }

   private void logChunkBlockMutation(BlockPos blockPos, BlockState blockState, BlockState rtBlockState, boolean canonicalized, PBlock block, int skyBrightness) {
      if (!PhotonicsStorage.PROFILER_ENABLED.value || !Photonic.automationEnabled() || this.chunkMutationDebugLogsRemaining <= 0) {
         return;
      }

      this.chunkMutationDebugLogsRemaining--;
      Photonic.info(
         "[Profiler] chunkBlockMutation: pos=({}, {}, {}) canonicalized={} raw={} rt={} pblock={} sky={}",
         blockPos.getX(),
         blockPos.getY(),
         blockPos.getZ(),
         canonicalized,
         blockState,
         rtBlockState,
         block == null ? "air" : block.blockId,
         skyBrightness
      );
   }

   private BlockState toRtContentBlockState(BlockState blockState) {
      if (!this.blockLightEnabled) {
         return this.canonicalizeRtNonLightDynamicState(blockState);
      }

      if (this.lightRegistry.hasPossibleTracedLight(blockState)) {
         return this.lightRegistry.canonicalizeTracedLightBlockState(blockState);
      }
      if (this.lightRegistry.hasPossibleLight(blockState)) {
         return this.lightRegistry.canonicalizeLightBlockState(blockState);
      }
      return this.canonicalizeRtNonLightDynamicState(blockState);
   }

   private BlockState canonicalizeRtNonLightDynamicState(BlockState blockState) {
      BlockState canonicalState = blockState;
      for (Property<?> property : blockState.getEntries().keySet()) {
         String propertyName = property.getName();
         if (isRtNonLightDynamicBooleanProperty(propertyName)) {
            canonicalState = withBooleanProperty(canonicalState, property, false);
         } else if ("power".equals(propertyName)) {
            canonicalState = withIntegerProperty(canonicalState, property, false);
         }
      }
      return canonicalState;
   }

   private static boolean isRtNonLightDynamicBooleanProperty(String propertyName) {
      return "lit".equals(propertyName)
         || "powered".equals(propertyName)
         || "enabled".equals(propertyName)
         || "triggered".equals(propertyName);
   }

   @SuppressWarnings({"unchecked", "rawtypes"})
   private static BlockState withBooleanProperty(BlockState blockState, Property<?> property, boolean value) {
      Comparable<?> currentValue = blockState.getEntries().get(property);
      if (!(currentValue instanceof Boolean)) {
         return blockState;
      }
      return blockState.with((Property) property, Boolean.valueOf(value));
   }

   @SuppressWarnings({"unchecked", "rawtypes"})
   private static BlockState withIntegerProperty(BlockState blockState, Property<?> property, boolean maxValue) {
      Comparable<?> currentValue = blockState.getEntries().get(property);
      if (!(currentValue instanceof Integer)) {
         return blockState;
      }

      Integer selected = null;
      for (Comparable<?> value : property.getValues()) {
         if (value instanceof Integer intValue) {
            if (selected == null || (maxValue ? intValue > selected : intValue < selected)) {
               selected = intValue;
            }
         }
      }
      return selected == null ? blockState : blockState.with((Property) property, selected);
   }

   private BlockUpdateSnapshot captureBlockUpdateSnapshot(ClientWorld level, BlockPos blockPos, BlockState blockState, boolean refreshLight) {
      BlockPos immutablePos = blockPos.toImmutable();
      BlockLightInfo lightInfo = null;
      if (refreshLight && this.blockLightEnabled) {
         lightInfo = this.lightRegistry.resolveLightInfo(immutablePos, blockState, level);
      }
      return new BlockUpdateSnapshot(immutablePos, blockState, lightInfo);
   }

   private BlockState captureBlockStateSnapshot(ClientWorld level, BlockPos blockPos) {
      if (level == null || !level.isChunkLoaded(blockPos)) {
         return Blocks.AIR.getDefaultState();
      }

      try {
         return level.getBlockState(blockPos);
      } catch (Exception ignored) {
         return Blocks.AIR.getDefaultState();
      }
   }

   private int computeSkyBrightness(ChunkLightingView skyLightView, BlockPos blockPos) {
      if (skyLightView == null) {
         return 0;
      }

      BlockPos.Mutable mutableBlockPos = new BlockPos.Mutable();
      mutableBlockPos.set(blockPos.getX(), blockPos.getY(), blockPos.getZ());
      int brightness = skyLightView.getLightLevel(mutableBlockPos) / 2;
      int skyBrightness = 0;
      for (Direction face : FACES) {
         mutableBlockPos.set(blockPos.getX(), blockPos.getY(), blockPos.getZ());
         mutableBlockPos.move(face);
         skyBrightness = skyBrightness << 3 | Math.max(skyLightView.getLightLevel(mutableBlockPos) / 2, brightness);
      }
      return skyBrightness;
   }

   private void markLightBlendBlock(BlockPos blockPos) {
      int expand = LIGHT_BLEND_EXPANSION_BLOCKS;
      this.markLightBlendRegion(
         blockPos.getX() - expand,
         blockPos.getY() - expand,
         blockPos.getZ() - expand,
         blockPos.getX() + 1 + expand,
         blockPos.getY() + 1 + expand,
         blockPos.getZ() + 1 + expand
      );
   }

   private void markLightBlendChunk(PChunkPos chunkPos) {
      PBlockPos chunkMin = chunkPos.toBlockPos();
      int expand = LIGHT_BLEND_EXPANSION_BLOCKS;
      this.markLightBlendRegion(
         chunkMin.x - expand,
         chunkMin.y - expand,
         chunkMin.z - expand,
         chunkMin.x + 16 + expand,
         chunkMin.y + 16 + expand,
         chunkMin.z + 16 + expand
      );
   }

   private void markLightBlendRegion(int minX, int minY, int minZ, int maxX, int maxY, int maxZ) {
      PBlockPos newMin = new PBlockPos(minX, minY, minZ);
      PBlockPos newMax = new PBlockPos(maxX, maxY, maxZ);
      if (lightBlendRegionsContain(this.pendingLightBlendMin, this.pendingLightBlendMax, this.pendingLightBlendRegionCount, newMin, newMax)
         || this.lightBlendAge > 0
         && lightBlendRegionsContain(this.liveLightBlendMin, this.liveLightBlendMax, this.liveLightBlendRegionCount, newMin, newMax)) {
         return;
      }

      int previousCount = this.pendingLightBlendRegionCount;
      long previousVolume = totalLightBlendVolume(this.pendingLightBlendMin, this.pendingLightBlendMax, previousCount);
      long previousLargest = largestLightBlendRegionVolume(this.pendingLightBlendMin, this.pendingLightBlendMax, previousCount);
      this.pendingLightBlendRegionCount = appendLightBlendRegion(
         this.pendingLightBlendMin,
         this.pendingLightBlendMax,
         this.pendingLightBlendRegionCount,
         MAX_LIGHT_BLEND_REGIONS,
         minX,
         minY,
         minZ,
         maxX,
         maxY,
         maxZ
      );
      this.pendingLightBlendDirty = this.pendingLightBlendRegionCount > 0;
      this.automationPendingBlendMutationEvents++;
      this.automationMaxPendingBlendRegions = Math.max(this.automationMaxPendingBlendRegions, this.pendingLightBlendRegionCount);
      this.automationMaxPendingBlendVolume = Math.max(
         this.automationMaxPendingBlendVolume,
         totalLightBlendVolume(this.pendingLightBlendMin, this.pendingLightBlendMax, this.pendingLightBlendRegionCount)
      );
      this.logPendingBlendRegionTransition(previousCount, previousVolume, previousLargest, "chunk_mutation");
   }

   private boolean activatePendingLightBlend() {
      if (!this.pendingLightBlendDirty) {
         return false;
      }
      long pendingVolume = totalLightBlendVolume(this.pendingLightBlendMin, this.pendingLightBlendMax, this.pendingLightBlendRegionCount);
      long pendingLargest = largestLightBlendRegionVolume(this.pendingLightBlendMin, this.pendingLightBlendMax, this.pendingLightBlendRegionCount);
      this.automationBlendRegionActivations++;
      this.automationMaxPendingBlendRegions = Math.max(this.automationMaxPendingBlendRegions, this.pendingLightBlendRegionCount);
      this.automationMaxPendingBlendVolume = Math.max(this.automationMaxPendingBlendVolume, pendingVolume);
      this.liveLightBlendRegionCount = copyLightBlendRegions(
         this.pendingLightBlendMin,
         this.pendingLightBlendMax,
         this.pendingLightBlendRegionCount,
         this.liveLightBlendMin,
         this.liveLightBlendMax
      );
      this.lightBlendAge = TEMPORAL_BLEND_FRAMES;
      this.fullLightBlendActive = false;
      this.clearPendingLightBlendRegions();
      if (PhotonicsStorage.PROFILER_ENABLED.value && this.liveLightBlendRegionCount > 0) {
         Photonic.info("[Profiler] temporalBlend activate: mode=region regions={} volume={} largest={} frames={}",
            this.liveLightBlendRegionCount,
            pendingVolume,
            pendingLargest,
            TEMPORAL_BLEND_FRAMES);
      }
      return this.liveLightBlendRegionCount > 0;
   }

   private void activateFullLightBlendReset(String reason) {
      this.liveLightBlendMin[0] = new PBlockPos(
         (int) this.liveWorldBlockOffset.x - this.worldBlockSize,
         (int) this.liveWorldBlockOffset.y - this.worldBlockSize,
         (int) this.liveWorldBlockOffset.z - this.worldBlockSize
      );
      this.liveLightBlendMax[0] = new PBlockPos(
         (int) this.liveWorldBlockOffset.x + this.worldBlockSize,
         (int) this.liveWorldBlockOffset.y + this.worldBlockSize,
         (int) this.liveWorldBlockOffset.z + this.worldBlockSize
      );
      this.liveLightBlendRegionCount = 1;
      this.lightBlendAge = TEMPORAL_BLEND_FRAMES;
      this.fullLightBlendActive = true;
      this.automationBlendFullActivations++;
      if (PhotonicsStorage.PROFILER_ENABLED.value) {
         Photonic.info("[Profiler] temporalBlend activate: mode=full reason={} regions=1 volume={} frames={}",
            reason,
            lightBlendRegionVolume(this.liveLightBlendMin[0], this.liveLightBlendMax[0]),
            TEMPORAL_BLEND_FRAMES);
      }
   }

   public void queueGlJob(Runnable job) {
      this.glQueue.add(job);
   }

   public Vector3d toRt(Vector3d vector3d) {
      return new Vector3d(vector3d).sub(this.liveWorldBlockOffset);
   }

   public boolean fetchLightReload() {
      return isGlobalLightReloadActive(this.lightBlendAge, this.fullLightBlendActive);
   }

   public float getFirstBuildTime() {
      return this.firstBuildFrame > 0 ? (float) this.firstBuildFrame : 0.0F;
   }

   public boolean hasActiveLightBlend() {
      return this.lightBlendAge > 0 && this.liveLightBlendRegionCount > 0;
   }

   public float fetchLightBlendFactor() {
      if (this.lightBlendAge > 0) {
         return (float) this.lightBlendAge / TEMPORAL_BLEND_FRAMES;
      }
      return 0.0f;
   }

   public void advanceLightBlendFrame(int frame) {
      if (frame == this.lastLightBlendFrame) {
         return;
      }
      this.lastLightBlendFrame = frame;
      if (this.lightBlendAge > 0) {
         this.lightBlendAge--;
         if (this.lightBlendAge <= 0) {
            boolean wasFullBlend = this.fullLightBlendActive;
            int completedRegions = this.liveLightBlendRegionCount;
            long completedVolume = totalLightBlendVolume(this.liveLightBlendMin, this.liveLightBlendMax, this.liveLightBlendRegionCount);
            this.automationBlendCompletions++;
            this.fullLightBlendActive = false;
            Arrays.fill(this.liveLightBlendMin, null);
            Arrays.fill(this.liveLightBlendMax, null);
            this.liveLightBlendRegionCount = 0;
            if (PhotonicsStorage.PROFILER_ENABLED.value) {
               Photonic.info("[Profiler] temporalBlend complete: mode={} regions={} volume={}",
                  wasFullBlend ? "full" : "region",
                  completedRegions,
                  completedVolume);
            }
         }
      }
   }

   static boolean isGlobalLightReloadActive(int lightBlendAge, boolean fullLightBlendActive) {
      return lightBlendAge > 0 && fullLightBlendActive;
   }

   public void checkCameraJump(Vector3f currentCameraPosition) {
      if (!this.previousCameraPositionValid) {
         this.previousCameraPosition.set(currentCameraPosition);
         this.previousCameraPositionValid = true;
         return;
      }
      float dx = currentCameraPosition.x - this.previousCameraPosition.x;
      float dy = currentCameraPosition.y - this.previousCameraPosition.y;
      float dz = currentCameraPosition.z - this.previousCameraPosition.z;
      float distSq = dx * dx + dy * dy + dz * dz;
      if (distSq > 32.0f * 32.0f) {
         if (PhotonicsStorage.PROFILER_ENABLED.value) {
            Photonic.info("[Profiler] temporalReset queued: reason=camera_jump distance={} previous=({},{},{}) current=({},{},{})",
               Math.sqrt(distSq),
               this.previousCameraPosition.x,
               this.previousCameraPosition.y,
               this.previousCameraPosition.z,
               currentCameraPosition.x,
               currentCameraPosition.y,
               currentCameraPosition.z);
         }
         this.forceTemporalReset = true;
      }
      this.previousCameraPosition.set(currentCameraPosition);
   }

   public int getLightBlendRegionCount() {
      return this.lightBlendAge > 0 ? this.liveLightBlendRegionCount : 0;
   }

   public Vector3d getLightBlendMin() {
      return this.getLightBlendMin(0);
   }

   public Vector3d getLightBlendMax() {
      return this.getLightBlendMax(0);
   }

   public Vector3d getLightBlendMin(int index) {
      if (this.lightBlendAge > 0 && index >= 0 && index < this.liveLightBlendRegionCount && this.liveLightBlendMin[index] != null) {
         return new Vector3d(this.liveLightBlendMin[index].x, this.liveLightBlendMin[index].y, this.liveLightBlendMin[index].z);
      }
      return new Vector3d(0, 0, 0);
   }

   public Vector3d getLightBlendMax(int index) {
      if (this.lightBlendAge > 0 && index >= 0 && index < this.liveLightBlendRegionCount && this.liveLightBlendMax[index] != null) {
         return new Vector3d(this.liveLightBlendMax[index].x, this.liveLightBlendMax[index].y, this.liveLightBlendMax[index].z);
      }
      return new Vector3d(0, 0, 0);
   }

   static boolean shouldForceTemporalResetForLightMutation(boolean chunkTopologyChanged, int pendingTracedLightMutations) {
      // Local light edits should preserve the surrounding temporal history and rely on
      // localized blend regions for fast visible convergence. Full-scene resets remain
      // reserved for topology/world-offset/camera-jump class events that invalidate the
      // broader sampling domain.
      return chunkTopologyChanged;
   }

   static boolean shouldForceTemporalResetForWorldOffset(PChunkPos previousOffset, PChunkPos currentOffset, int worldChunkSize) {
      if (previousOffset == null || currentOffset == null) {
         return false;
      }
      int dx = Math.abs(currentOffset.x - previousOffset.x);
      int dy = Math.abs(currentOffset.y - previousOffset.y);
      int dz = Math.abs(currentOffset.z - previousOffset.z);
      // Re-centering the RT volume by a few chunks preserves substantial overlap and
      // should not act like a global light reload. Only force a full reset once the
      // offset jump exceeds the entire tracked world span along any axis.
      return dx >= worldChunkSize || dy >= worldChunkSize || dz >= worldChunkSize;
   }

   static boolean hasResetReason(String reasonList, String reason) {
      if (reason == null || reason.isBlank() || reasonList == null || reasonList.isBlank()) {
         return false;
      }
      for (String token : reasonList.split("\\+")) {
         if (reason.equals(token)) {
            return true;
         }
      }
      return false;
   }

   private void requestFullLightBlendReset(String reason) {
      String resolvedReason = reason == null || reason.isBlank() ? "unknown" : reason;
      String currentReason = this.pendingFullLightBlendResetReason == null || this.pendingFullLightBlendResetReason.isBlank()
         ? "none"
         : this.pendingFullLightBlendResetReason;
      boolean alreadyPendingSameReason = this.pendingFullLightBlendReset && hasResetReason(currentReason, resolvedReason);
      if (!alreadyPendingSameReason) {
         this.automationResetRequestsTotal++;
         if (resolvedReason.contains("world_offset")) {
            this.automationResetRequestsWorldOffset++;
         }
         if (resolvedReason.contains("camera_jump")) {
            this.automationResetRequestsCameraJump++;
         }
         if (resolvedReason.contains("topology")) {
            this.automationResetRequestsTopology++;
         }
         if (!resolvedReason.contains("world_offset") && !resolvedReason.contains("camera_jump") && !resolvedReason.contains("topology")) {
            this.automationResetRequestsOther++;
         }
      }
      boolean wasPending = this.pendingFullLightBlendReset;
      this.pendingFullLightBlendReset = true;
      if (!wasPending || currentReason.equals("none")) {
         this.pendingFullLightBlendResetReason = resolvedReason;
      } else if (!currentReason.equals(resolvedReason) && !currentReason.contains(resolvedReason)) {
         this.pendingFullLightBlendResetReason = currentReason + "+" + resolvedReason;
      }
      if (PhotonicsStorage.PROFILER_ENABLED.value && !wasPending) {
         Photonic.info("[Profiler] temporalReset pending: reason={} liveAge={} liveRegions={} pendingRegions={}",
            this.pendingFullLightBlendResetReason,
            this.lightBlendAge,
            this.liveLightBlendRegionCount,
            this.pendingLightBlendRegionCount);
      }
   }

   private void logPendingBlendRegionTransition(int previousCount, long previousVolume, long previousLargest, String reason) {
      if (!PhotonicsStorage.PROFILER_ENABLED.value || !this.pendingLightBlendDirty) {
         return;
      }
      long currentVolume = totalLightBlendVolume(this.pendingLightBlendMin, this.pendingLightBlendMax, this.pendingLightBlendRegionCount);
      long currentLargest = largestLightBlendRegionVolume(this.pendingLightBlendMin, this.pendingLightBlendMax, this.pendingLightBlendRegionCount);
      if (previousCount == this.pendingLightBlendRegionCount
         && previousVolume == currentVolume
         && previousLargest == currentLargest
         && this.lastLoggedPendingBlendCount == this.pendingLightBlendRegionCount
         && this.lastLoggedPendingBlendVolume == currentVolume
         && this.lastLoggedPendingBlendLargest == currentLargest) {
         return;
      }
      this.lastLoggedPendingBlendCount = this.pendingLightBlendRegionCount;
      this.lastLoggedPendingBlendVolume = currentVolume;
      this.lastLoggedPendingBlendLargest = currentLargest;
      Photonic.info("[Profiler] temporalBlend pending: reason={} regions={}→{} volume={}→{} largest={}→{} liveActive={} liveAge={}",
         reason,
         previousCount,
         this.pendingLightBlendRegionCount,
         previousVolume,
         currentVolume,
         previousLargest,
         currentLargest,
         this.liveLightBlendRegionCount,
         this.lightBlendAge);
   }

   private void clearPendingLightBlendRegions() {
      Arrays.fill(this.pendingLightBlendMin, null);
      Arrays.fill(this.pendingLightBlendMax, null);
      this.pendingLightBlendRegionCount = 0;
      this.pendingLightBlendDirty = false;
      this.lastLoggedPendingBlendCount = -1;
      this.lastLoggedPendingBlendVolume = -1L;
      this.lastLoggedPendingBlendLargest = -1L;
   }

   static int appendLightBlendRegion(PBlockPos[] mins,
                                     PBlockPos[] maxs,
                                     int regionCount,
                                     int maxRegions,
                                     int minX,
                                     int minY,
                                     int minZ,
                                     int maxX,
                                     int maxY,
                                     int maxZ) {
      PBlockPos newMin = new PBlockPos(minX, minY, minZ);
      PBlockPos newMax = new PBlockPos(maxX, maxY, maxZ);

      for (int i = 0; i < regionCount; i++) {
         if (lightBlendRegionContains(mins[i], maxs[i], newMin, newMax)
            || lightBlendRegionContains(newMin, newMax, mins[i], maxs[i])) {
            mins[i].min(minX, minY, minZ);
            maxs[i].max(maxX, maxY, maxZ);
            return regionCount;
         }
      }

      if (regionCount < maxRegions) {
         mins[regionCount] = newMin;
         maxs[regionCount] = newMax;
         return regionCount + 1;
      }

      int bestIndex = 0;
      long bestAddedVolume = Long.MAX_VALUE;
      for (int i = 0; i < regionCount; i++) {
         long addedVolume = lightBlendRegionUnionVolume(mins[i], maxs[i], newMin, newMax) - lightBlendRegionVolume(mins[i], maxs[i]);
         if (addedVolume < bestAddedVolume) {
            bestAddedVolume = addedVolume;
            bestIndex = i;
         }
      }

      mins[bestIndex].min(minX, minY, minZ);
      maxs[bestIndex].max(maxX, maxY, maxZ);
      return regionCount;
   }

   private static int copyLightBlendRegions(PBlockPos[] sourceMins,
                                            PBlockPos[] sourceMaxs,
                                            int sourceCount,
                                            PBlockPos[] targetMins,
                                            PBlockPos[] targetMaxs) {
      Arrays.fill(targetMins, null);
      Arrays.fill(targetMaxs, null);
      for (int i = 0; i < sourceCount; i++) {
         targetMins[i] = new PBlockPos(sourceMins[i].x, sourceMins[i].y, sourceMins[i].z);
         targetMaxs[i] = new PBlockPos(sourceMaxs[i].x, sourceMaxs[i].y, sourceMaxs[i].z);
      }
      return sourceCount;
   }

   private static boolean lightBlendRegionContains(PBlockPos outerMin, PBlockPos outerMax, PBlockPos innerMin, PBlockPos innerMax) {
      return outerMin.x <= innerMin.x && outerMax.x >= innerMax.x
         && outerMin.y <= innerMin.y && outerMax.y >= innerMax.y
         && outerMin.z <= innerMin.z && outerMax.z >= innerMax.z;
   }

   private static boolean lightBlendRegionsContain(PBlockPos[] mins,
                                                   PBlockPos[] maxs,
                                                   int regionCount,
                                                   PBlockPos innerMin,
                                                   PBlockPos innerMax) {
      for (int i = 0; i < regionCount; i++) {
         if (mins[i] != null && maxs[i] != null && lightBlendRegionContains(mins[i], maxs[i], innerMin, innerMax)) {
            return true;
         }
      }
      return false;
   }

   private static long lightBlendRegionUnionVolume(PBlockPos minA, PBlockPos maxA, PBlockPos minB, PBlockPos maxB) {
      return lightBlendRegionVolume(
         new PBlockPos(Math.min(minA.x, minB.x), Math.min(minA.y, minB.y), Math.min(minA.z, minB.z)),
         new PBlockPos(Math.max(maxA.x, maxB.x), Math.max(maxA.y, maxB.y), Math.max(maxA.z, maxB.z))
      );
   }

   private static long lightBlendRegionVolume(PBlockPos min, PBlockPos max) {
      long dx = Math.max(1, (long) max.x - min.x);
      long dy = Math.max(1, (long) max.y - min.y);
      long dz = Math.max(1, (long) max.z - min.z);
      return dx * dy * dz;
   }

   private static long totalLightBlendVolume(PBlockPos[] mins, PBlockPos[] maxs, int regionCount) {
      long total = 0L;
      for (int i = 0; i < regionCount; i++) {
         total += lightBlendRegionVolume(mins[i], maxs[i]);
      }
      return total;
   }

   private static long largestLightBlendRegionVolume(PBlockPos[] mins, PBlockPos[] maxs, int regionCount) {
      long largest = 0L;
      for (int i = 0; i < regionCount; i++) {
         largest = Math.max(largest, lightBlendRegionVolume(mins[i], maxs[i]));
      }
      return largest;
   }

   private void recordAutomationFrameDiagnostics(
      boolean worldOffsetChanged,
      boolean chunkTopologyChanged,
      boolean chunkContentChanged,
      boolean tracedLightSetDirty,
      boolean lightWorkNeeded,
      boolean lightCompiled,
      boolean wantsLightWork
   ) {
      if (worldOffsetChanged) {
         this.automationCompileFramesWorldOffsetChanged++;
      }
      if (chunkTopologyChanged) {
         this.automationCompileFramesChunkTopologyChanged++;
      }
      if (chunkContentChanged) {
         this.automationCompileFramesChunkContentChanged++;
      }
      if (tracedLightSetDirty) {
         this.automationCompileFramesTracedLightDirty++;
      }
      if (wantsLightWork) {
         this.automationCompileFramesLightWorkNeeded++;
      }
      if (lightCompiled) {
         this.automationCompileFramesLightCompiled++;
      }
      if (this.fetchLightReload()) {
         this.automationFramesGlobalReloadActive++;
      }
      if (this.hasActiveLightBlend()) {
         this.automationFramesBlendActive++;
      }
      if (this.hasPendingWork()) {
         this.automationFramesPendingWork++;
      }
   }

   public void startWorldBuilder() {
      this.worldCompilerThread.ensureRunning();
   }

   public void stopWorldBuilder() {
      this.worldCompilerThread.sendStopSignal();
   }

   public void wakeUpWorldBuilder() {
      synchronized (this.worldCompilerThread) {
         this.worldCompilerThread.notifyAll();
      }
   }

   public boolean hasPendingWork() {
      return !this.buildQueue.isEmpty() || !this.pendingChunkLoads.isEmpty();
   }

   public long getAutomationResetRequestsTotal() {
      return this.automationResetRequestsTotal;
   }

   public long getAutomationResetRequestsWorldOffset() {
      return this.automationResetRequestsWorldOffset;
   }

   public long getAutomationResetRequestsCameraJump() {
      return this.automationResetRequestsCameraJump;
   }

   public long getAutomationResetRequestsTopology() {
      return this.automationResetRequestsTopology;
   }

   public long getAutomationResetRequestsOther() {
      return this.automationResetRequestsOther;
   }

   public long getAutomationBlendFullActivations() {
      return this.automationBlendFullActivations;
   }

   public long getAutomationBlendRegionActivations() {
      return this.automationBlendRegionActivations;
   }

   public long getAutomationBlendCompletions() {
      return this.automationBlendCompletions;
   }

   public long getAutomationFramesGlobalReloadActive() {
      return this.automationFramesGlobalReloadActive;
   }

   public long getAutomationFramesBlendActive() {
      return this.automationFramesBlendActive;
   }

   public long getAutomationFramesPendingWork() {
      return this.automationFramesPendingWork;
   }

   public long getAutomationCompileFramesLightWorkNeeded() {
      return this.automationCompileFramesLightWorkNeeded;
   }

   public long getAutomationCompileFramesLightCompiled() {
      return this.automationCompileFramesLightCompiled;
   }

   public long getAutomationCompileFramesWorldOffsetChanged() {
      return this.automationCompileFramesWorldOffsetChanged;
   }

   public long getAutomationCompileFramesChunkTopologyChanged() {
      return this.automationCompileFramesChunkTopologyChanged;
   }

   public long getAutomationCompileFramesChunkContentChanged() {
      return this.automationCompileFramesChunkContentChanged;
   }

   public long getAutomationCompileFramesTracedLightDirty() {
      return this.automationCompileFramesTracedLightDirty;
   }

   public long getAutomationPendingBlendMutationEvents() {
      return this.automationPendingBlendMutationEvents;
   }

   public int getAutomationMaxPendingBlendRegions() {
      return this.automationMaxPendingBlendRegions;
   }

   public long getAutomationMaxPendingBlendVolume() {
      return this.automationMaxPendingBlendVolume;
   }

   public boolean hasPendingChunkLoads() {
      return !this.pendingChunkLoads.isEmpty();
   }

   public Vector3d getWorldOffset() {
      return this.liveWorldBlockOffset;
   }

   public ConcurrentLinkedQueue<Runnable> getGlQueue() {
      return this.glQueue;
   }

   public void changeBuildStage(WorldRegistry.BuildStage buildStage) {
      if (buildStage.before != this.buildStage) {
         throw new IllegalStateException();
      } else {
         this.buildStage = buildStage;
      }
   }

   public GlMemoryManager getRootMemoryManager() {
      return this.rootMemoryManager;
   }

   public GlMemoryManager getCbMemoryManager() {
      return this.cbMemoryManager;
   }

   public LightRegistry getLightRegistry() {
      return this.lightRegistry;
   }

   public PBlockPos getWorldMinVoxel() {
      return this.liveWorldMinVoxel;
   }

   public PBlockPos getWorldMaxVoxel() {
      return this.liveWorldMaxVoxel;
   }

   private static int getFaceIndexFromNormal(Direction direction) {
      int x = direction.getVector().getX();
      int y = direction.getVector().getY();
      int z = direction.getVector().getZ();
      int index = (int)(Math.abs(x) * (x * 0.5 + 0.5) + Math.abs(y) * (y * 0.5 + 2.5) + Math.abs(z) * (z * 0.5 + 4.5) + 0.5);
      return Math.max(0, Math.min(5, index));
   }

   private record BlockUpdateSnapshot(BlockPos blockPos, BlockState blockState, BlockLightInfo lightInfo) {
   }

   static {
      WorldRegistry.BuildStage.IDLE.before = WorldRegistry.BuildStage.UPLOAD;
      WorldRegistry.BuildStage.COMPILE.before = WorldRegistry.BuildStage.IDLE;
      WorldRegistry.BuildStage.WAIT_FOR_UPLOAD.before = WorldRegistry.BuildStage.COMPILE;
      WorldRegistry.BuildStage.UPLOAD.before = WorldRegistry.BuildStage.WAIT_FOR_UPLOAD;

      for (Direction direction : Direction.values()) {
         FACES[getFaceIndexFromNormal(direction)] = direction;
      }
   }

   public static enum BuildStage {
      IDLE,
      COMPILE,
      WAIT_FOR_UPLOAD,
      UPLOAD;

      public WorldRegistry.BuildStage before;
   }
}










