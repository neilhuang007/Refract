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
import java.util.Map;
import java.util.PriorityQueue;
import java.util.Set;
import java.util.StringJoiner;
import java.util.Map.Entry;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.ExecutionException;
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
   /** Kept for test and static-utility access; canonical value lives in LightBlendController. */
   static final int MAX_LIGHT_BLEND_REGIONS = LightBlendController.MAX_LIGHT_BLEND_REGIONS;
   private static final int RT_VISIBILITY_KEEP_ALIVE_FRAMES = 96;
   private static final float RT_ALWAYS_KEEP_DISTANCE_BLOCKS = 48.0F;
   private static final float RT_MAX_RESIDENT_DISTANCE_BLOCKS = 96.0F;
   private static final float RT_RESIDENT_UNLOAD_HYSTERESIS_BLOCKS = 16.0F;
   private static final int RT_MAX_RESIDENT_CHUNKS = 192;
   private static final long CHUNK_CONTENT_HASH_OFFSET = 1469598103934665603L;
   private static final long CHUNK_CONTENT_HASH_PRIME = 1099511628211L;
   final IRenderDispatcher renderDispatcher;
   private final ChunkResidencyManager residency = new ChunkResidencyManager();
   private final LightBlendController lightBlend = new LightBlendController();
   private final WorldCompilerThread worldCompilerThread;
   final LightRegistry lightRegistry;
   private final WorldBackend backend;
   final GlMemoryManager cbMemoryManager;
   final BlockRegistry blockRegistry;
   final GlMemoryManager rootMemoryManager;
   private MemoryRegion rootMemory;
   private final Schematic rootSchematic;
   private final Set<PChunkPos> pendingBuildChunks = ConcurrentHashMap.newKeySet();
   final Map<PChunkPos, WorldChunk> chunks = new ConcurrentHashMap<>();
   PBlockPos rtToWorldBlockOffset = new PBlockPos(0, 0, 0);
   PChunkPos rtToWorldChunkOffset = new PChunkPos(0, 0, 0);
   Vector3d liveWorldBlockOffset = new Vector3d();
   PBlockPos liveWorldMinVoxel = new PBlockPos(0, 0, 0);
   PBlockPos liveWorldMaxVoxel = new PBlockPos(0, 0, 0);
   private int lastLoggedChunkChurn = -1;
   private String lastLoggedRootUploadSignature = "";
   private String lastLoggedBrickUploadSignature = "";
   final int worldBlockSize;
   final int worldChunkSize;
   PBlockPos worldMinVoxel = new PBlockPos(0, 0, 0);
   PBlockPos worldMaxVoxel = new PBlockPos(0, 0, 0);
   final boolean blockLightEnabled;
   volatile boolean chunkSyncNeeded = true;
   long lastRebuildRateLogNanos = 0;
   int rebuildsSinceLastLog = 0;
   private int chunkMutationDebugLogsRemaining = 96;
   final PriorityQueue<PChunkPos> pendingChunkLoads = new PriorityQueue<>(
      Comparator.comparingDouble(this::chunkDistanceToCamera)
   );
   private final Set<PChunkPos> pendingChunkSet = new HashSet<>();
   private final Map<PChunkPos, Long> chunkContentHashes = new HashMap<>();
   private final BlockUpdateQueue blockUpdateQueue = new BlockUpdateQueue();
   int pendingSemanticChunkMutations = 0;
   private final Map<PChunkPos, Integer> recentlyVisibleRtChunks = new HashMap<>();
   private final WorldBuildOrchestrator orchestrator = new WorldBuildOrchestrator();
   private static final int CHUNK_LOAD_BUDGET = 256;
   private long automationResetRequestsTotal = 0L;
   private long automationResetRequestsWorldOffset = 0L;
   private long automationResetRequestsTopology = 0L;
   private long automationResetRequestsOther = 0L;
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
      this.orchestrator.upload(this, this.lightRegistry, this.blockRegistry, this.cbMemoryManager, this.rootMemoryManager, this.lightBlend);
   }

   public void compileWorld() {
      this.orchestrator.compileWorld(this, this.lightRegistry, this.lightBlend);
   }

   int profLoadChunkCount;
   long profLoadChunkNanos;
   long profRootOptNanos;
   int profDirtyChunkCount;
   int profLoadedChunkCount;
   int profUnloadedChunkCount;
   int profRootUploadBytes;
   int profRootEntriesDirty;
   int profRootEntriesLoaded;
   String profRootUploadCause = "none";

   private boolean isRtChunkResidencyFrozenForDebug() {
      return Boolean.getBoolean("photonics.freezeRtChunkResidency");
   }

   public boolean synchronizeChunks() {
      this.ensureWorldThread();
      int frame = SystemTimeUniforms.COUNTER.getAsInt();
      boolean profiling = PhotonicsStorage.PROFILER_ENABLED.value;

      // clStart[0] is set just before the first loadChunk call to preserve the
      // original per-load-batch timing granularity.
      long[] clStart = {0L};
      boolean changed = this.residency.synchronizeChunks(
         this.renderDispatcher,
         this.rtToWorldChunkOffset,
         this.worldChunkSize,
         this.chunks,
         this.pendingChunkLoads,
         this.pendingChunkSet,
         this.recentlyVisibleRtChunks,
         frame,
         this.isRtChunkResidencyFrozenForDebug(),
         chunkPos -> {
            if (clStart[0] == 0L && profiling) {
               clStart[0] = System.nanoTime();
            }
            this.loadChunk(chunkPos);
         },
         chunkPos -> {
            this.unloadChunk(chunkPos);
            this.profUnloadedChunkCount++;
         },
         count -> {
            this.profLoadedChunkCount = count;
         },
         () -> {}
      );
      if (clStart[0] != 0L) {
         this.profLoadChunkNanos = System.nanoTime() - clStart[0];
         this.profLoadChunkCount = this.profLoadedChunkCount;
      }

      this.worldMinVoxel = new PBlockPos(Integer.MAX_VALUE, Integer.MAX_VALUE, Integer.MAX_VALUE);
      this.worldMaxVoxel = new PBlockPos(Integer.MIN_VALUE, Integer.MIN_VALUE, Integer.MIN_VALUE);

      for (PChunkPos chunkPos : this.chunks.keySet()) {
         PBlockPos blockPos = chunkPos.toBlockPos();
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
      return this.residency.shouldKeepChunkForRt(chunkPos);
   }

   /** Delegates to ChunkResidencyManager; kept for backward-compatible test access. */
   static List<PChunkPos> collectTrimEligibleChunks(List<PChunkPos> loadedChunks, int residentChunkBudget, Set<PChunkPos> inboundNonEmptyChunks) {
      return ChunkResidencyManager.collectTrimEligibleChunks(loadedChunks, residentChunkBudget, inboundNonEmptyChunks);
   }

   private double chunkDistanceToCamera(PChunkPos chunkPos) {
      return this.residency.chunkDistanceToCamera(chunkPos);
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
      if (!this.blockUpdateQueue.hasDeferredLightUpdates()) {
         return;
      }
      ClientWorld level = MinecraftAccessor.getLevel();
      if (level == null) {
         return;
      }
      List<BlockUpdateSnapshot> deferredSnapshots = this.blockUpdateQueue.drainDeferredLightUpdatesForChunk(chunkPos);
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
            this.orchestrator.clearDirty();
            return false;
         }
      }

      if (fullRootRebuild) {
         Arrays.fill(this.rootSchematic.getData(), 0);
         this.orchestrator.invalidateRootData();
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
         this.backend.updateRootData(this.rtToWorldChunkOffset, this.worldChunkSize, fullRootRebuild || !this.orchestrator.isRootDataValid());
         this.orchestrator.markRootDataValid();
      }

      this.orchestrator.markDirty();
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

   String describeRootUploadCause(boolean worldOffsetChanged, boolean chunkTopologyChanged, boolean rootDataValid) {
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

   void logChunkChurnDiagnostics(boolean chunkTopologyChanged) {
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

   void logRootUploadDiagnostics(boolean rootUploadNeeded) {
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

   void logBrickUploadDiagnostics() {
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
      this.orchestrator.afterUpload();
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
         this.orchestrator.requestCloseChunkUpdate();
      }
   }

   @Override
   public void free() {
      this.worldCompilerThread.free();
      this.orchestrator.drainBuildQueue();
      this.orchestrator.drainGlQueue();
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
      this.orchestrator.queueBuildJob(job);
   }

   public void queueChunkLoad(PChunkPos chunkPos) {
      if (this.pendingBuildChunks.add(chunkPos)) {
         this.orchestrator.queueBuildJob(() -> {
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
      this.blockUpdateQueue.enqueueSingleUpdate(snapshot, refreshLight);
      if (this.blockUpdateQueue.tryScheduleFlush()) {
         this.orchestrator.queueBuildJob(this::flushPendingBlockUpdates);
         this.wakeUpWorldBuilder();
      }
   }

   private void flushPendingBlockUpdates() {
      this.blockUpdateQueue.flushPendingBlockUpdates(
         (blockPos, snapshot, refreshLight) -> {
            BlockUpdateSnapshot resolved = snapshot;
            if (resolved == null) {
               ClientWorld level = MinecraftAccessor.getLevel();
               resolved = this.captureBlockUpdateSnapshot(level, blockPos, this.captureBlockStateSnapshot(level, blockPos), refreshLight);
            }
            this.refreshBlock(resolved, refreshLight);
         },
         () -> this.orchestrator.queueBuildJob(this::flushPendingBlockUpdates)
      );
   }

   private void queueDeferredLightBlockUpdate(BlockUpdateSnapshot snapshot) {
      this.blockUpdateQueue.enqueueDeferredLightUpdate(snapshot);
   }

   private void queueChunkRefresh(PChunkPos chunkPos) {
      if (this.pendingBuildChunks.add(chunkPos)) {
         this.orchestrator.queueBuildJob(() -> {
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
         this.blockUpdateQueue.removeDeferredLightUpdate(blockPos);
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

      this.blockUpdateQueue.removeDeferredLightUpdate(blockPos);
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
         if (BlockStateCanonicalizer.isRtNonLightDynamicBooleanProperty(propertyName)) {
            canonicalState = BlockStateCanonicalizer.withBooleanProperty(canonicalState, property, false);
         } else if ("power".equals(propertyName)) {
            canonicalState = BlockStateCanonicalizer.withIntegerProperty(canonicalState, property, false);
         }
      }
      return canonicalState;
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

   void markLightBlendBlock(BlockPos blockPos) {
      this.lightBlend.markLightBlendBlock(blockPos);
   }

   private void markLightBlendChunk(PChunkPos chunkPos) {
      this.lightBlend.markLightBlendChunk(chunkPos);
   }

   public void queueGlJob(Runnable job) {
      this.orchestrator.queueGlJob(job);
   }

   public Vector3d toRt(Vector3d vector3d) {
      return new Vector3d(vector3d).sub(this.liveWorldBlockOffset);
   }

   public boolean fetchLightReload() {
      return this.lightBlend.fetchLightReload();
   }

   public float getFirstBuildTime() {
      int frame = this.orchestrator.getFirstBuildFrame();
      return frame > 0 ? (float) frame : 0.0F;
   }

   public boolean hasActiveLightBlend() {
      return this.lightBlend.hasActiveLightBlend();
   }

   public float fetchLightBlendFactor() {
      return this.lightBlend.fetchLightBlendFactor();
   }

   public void advanceLightBlendFrame(int frame) {
      this.lightBlend.advanceLightBlendFrame(frame);
   }

   static boolean isGlobalLightReloadActive(int lightBlendAge, boolean fullLightBlendActive) {
      return lightBlendAge > 0 && fullLightBlendActive;
   }

   public int getLightBlendRegionCount() {
      return this.lightBlend.getLightBlendRegionCount();
   }

   public Vector3d getLightBlendMin() {
      return this.lightBlend.getLightBlendMin(0);
   }

   public Vector3d getLightBlendMax() {
      return this.lightBlend.getLightBlendMax(0);
   }

   public Vector3d getLightBlendMin(int index) {
      return this.lightBlend.getLightBlendMin(index);
   }

   public Vector3d getLightBlendMax(int index) {
      return this.lightBlend.getLightBlendMax(index);
   }

   static boolean shouldForceTemporalResetForLightMutation(boolean chunkTopologyChanged, int pendingTracedLightMutations) {
      // Chunk topology changes happen continuously while the player walks at the
      // render-distance edge. Forcing a full NRD history reset on every load/unload
      // wipes the entire denoised image once or twice a second, which the user sees
      // as the world being constantly re-converged. Newly loaded chunks begin with
      // empty NRD history naturally, and unloaded chunks become invisible — neither
      // case needs a global flush. World-offset re-centering still triggers a reset
      // separately (shouldForceTemporalResetForWorldOffset).
      return false;
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

   void requestFullLightBlendReset(String reason) {
      String resolvedReason = reason == null || reason.isBlank() ? "unknown" : reason;
      boolean isNewRequest = this.lightBlend.requestFullLightBlendReset(resolvedReason);
      if (isNewRequest) {
         this.automationResetRequestsTotal++;
         if (resolvedReason.contains("world_offset")) {
            this.automationResetRequestsWorldOffset++;
         }
         if (resolvedReason.contains("topology")) {
            this.automationResetRequestsTopology++;
         }
         if (!resolvedReason.contains("world_offset") && !resolvedReason.contains("topology")) {
            this.automationResetRequestsOther++;
         }
      }
   }

   /**
    * Kept as a static entry point on WorldRegistry so that tests (WorldRegistryLightBlendRegionTest)
    * can call it without changes; the actual implementation is in LightBlendController.
    */
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
         if (LightBlendController.lightBlendRegionContains(mins[i], maxs[i], newMin, newMax)
            || LightBlendController.lightBlendRegionContains(newMin, newMax, mins[i], maxs[i])) {
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
         long addedVolume = LightBlendController.lightBlendRegionUnionVolume(mins[i], maxs[i], newMin, newMax)
            - LightBlendController.lightBlendRegionVolume(mins[i], maxs[i]);
         if (addedVolume < bestAddedVolume) {
            bestAddedVolume = addedVolume;
            bestIndex = i;
         }
      }

      mins[bestIndex].min(minX, minY, minZ);
      maxs[bestIndex].max(maxX, maxY, maxZ);
      return regionCount;
   }

   void recordAutomationFrameDiagnostics(
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
      return this.orchestrator.hasPendingBuildWork() || !this.pendingChunkLoads.isEmpty();
   }

   public long getAutomationResetRequestsTotal() {
      return this.automationResetRequestsTotal;
   }

   public long getAutomationResetRequestsWorldOffset() {
      return this.automationResetRequestsWorldOffset;
   }

   public long getAutomationResetRequestsTopology() {
      return this.automationResetRequestsTopology;
   }

   public long getAutomationResetRequestsOther() {
      return this.automationResetRequestsOther;
   }

   public long getAutomationBlendFullActivations() {
      return this.lightBlend.getAutomationBlendFullActivations();
   }

   public long getAutomationBlendRegionActivations() {
      return this.lightBlend.getAutomationBlendRegionActivations();
   }

   public long getAutomationBlendCompletions() {
      return this.lightBlend.getAutomationBlendCompletions();
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
      return this.lightBlend.getAutomationPendingBlendMutationEvents();
   }

   public int getAutomationMaxPendingBlendRegions() {
      return this.lightBlend.getAutomationMaxPendingBlendRegions();
   }

   public long getAutomationMaxPendingBlendVolume() {
      return this.lightBlend.getAutomationMaxPendingBlendVolume();
   }

   public boolean hasPendingChunkLoads() {
      return !this.pendingChunkLoads.isEmpty();
   }

   public Vector3d getWorldOffset() {
      return this.liveWorldBlockOffset;
   }

   public ConcurrentLinkedQueue<Runnable> getGlQueue() {
      return this.orchestrator.getGlQueue();
   }

   public void changeBuildStage(WorldRegistry.BuildStage buildStage) {
      this.orchestrator.changeBuildStage(buildStage);
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










