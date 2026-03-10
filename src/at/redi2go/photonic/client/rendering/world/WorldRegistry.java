package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.BlockRegistry;
import at.redi2go.photonic.client.rendering.MinecraftAccessor;
import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;
import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
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
import java.util.Map.Entry;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.ExecutionException;
import net.minecraft.client.world.ClientWorld;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Direction;
import net.minecraft.world.LightType;
import net.minecraft.world.chunk.light.ChunkLightingView;
import org.joml.Vector3d;
import org.joml.Vector3f;

public class WorldRegistry implements MemoryOwner, Destructable {
   private static final Direction[] FACES = new Direction[6];
   private static final int INITIAL_CHUNK_LOAD_BUDGET = 512;
   private final IRenderDispatcher renderDispatcher;
   private final WorldCompilerThread worldCompilerThread;
   private final LightRegistry lightRegistry;
   private final GlMemoryManager cbMemoryManager;
   private final BlockRegistry blockRegistry;
   private final GlMemoryManager rootMemoryManager;
   private MemoryRegion rootMemory;
   private final Schematic rootSchematic;
   private final ConcurrentLinkedQueue<Runnable> buildQueue = new ConcurrentLinkedQueue<>();
   private final ConcurrentLinkedQueue<Runnable> glQueue = new ConcurrentLinkedQueue<>();
   private final Map<PChunkPos, PChunk> chunks = new HashMap<>();
   private PBlockPos rtToWorldBlockOffset = new PBlockPos(0, 0, 0);
   private PChunkPos rtToWorldChunkOffset = new PChunkPos(0, 0, 0);
   private Vector3d liveWorldBlockOffset = new Vector3d();
   private PBlockPos liveWorldMinVoxel = new PBlockPos(0, 0, 0);
   private PBlockPos liveWorldMaxVoxel = new PBlockPos(0, 0, 0);
   private WorldRegistry.BuildStage buildStage = WorldRegistry.BuildStage.IDLE;
   private boolean closeChunkUpdate = false;
   private boolean closeChunkUpload = false;
   private int chunkUploadAge = 0;
   private static final int TEMPORAL_BLEND_FRAMES = 8;
   private final int worldBlockSize;
   private final int worldChunkSize;
   private PBlockPos worldMinVoxel = new PBlockPos(0, 0, 0);
   private PBlockPos worldMaxVoxel = new PBlockPos(0, 0, 0);
   private boolean dirty = true;
   private final boolean blockLightEnabled;
   private volatile boolean shadowStateDirty = true;
   private volatile boolean chunkSyncNeeded = true;
   private final PriorityQueue<PChunkPos> pendingChunkLoads = new PriorityQueue<>(
      Comparator.comparingDouble(this::chunkDistanceToCamera)
   );
   private final Set<PChunkPos> pendingChunkSet = new HashSet<>();
   private static final int CHUNK_LOAD_BUDGET = 64;

   public WorldRegistry(IRenderDispatcher renderDispatcher, int maxLights, int maxLightsPerNode, boolean blockLightEnabled) {
      this.renderDispatcher = renderDispatcher;
      this.blockLightEnabled = blockLightEnabled;
      this.worldChunkSize = 32;
      this.worldBlockSize = 16 * this.worldChunkSize;
      this.rootSchematic = new Schematic(this.worldChunkSize, this.worldChunkSize, this.worldChunkSize);
      this.lightRegistry = new LightRegistry(maxLights, maxLightsPerNode, 8, this.worldBlockSize, renderDispatcher::isChunkEmpty);
      this.cbMemoryManager = new GlMemoryManager(GlTarget.SSBO, "cb_block", 536870912, true);
      this.blockRegistry = new BlockRegistry(this.cbMemoryManager.allocateRegion(4096 * PBlock.BYTE_SIZE));
      this.rootMemoryManager = new GlMemoryManager(GlTarget.SSBO, "root_uniform", 4 * this.worldChunkSize * this.worldChunkSize * this.worldChunkSize, false);
      this.worldCompilerThread = new WorldCompilerThread(this);
      this.allocate(this.rootMemoryManager);
   }

   public void upload() {
      if (this.buildStage == WorldRegistry.BuildStage.WAIT_FOR_UPLOAD) {
         this.changeBuildStage(WorldRegistry.BuildStage.UPLOAD);
         boolean uploadDone = true;
         uploadDone &= this.lightRegistry.upload();
         uploadDone &= this.blockRegistry.upload();
         uploadDone &= this.cbMemoryManager.upload();
         if (!uploadDone) {
            this.buildStage = WorldRegistry.BuildStage.WAIT_FOR_UPLOAD;
         } else {
            this.rootMemoryManager.upload();
            this.liveWorldBlockOffset = new Vector3d(this.rtToWorldBlockOffset.x, this.rtToWorldBlockOffset.y, this.rtToWorldBlockOffset.z);
            this.liveWorldMinVoxel = this.worldMinVoxel;
            this.liveWorldMaxVoxel = this.worldMaxVoxel;
            if (this.closeChunkUpdate) {
               this.renderDispatcher.onChunkLoad();
               this.closeChunkUpload = true;
               this.closeChunkUpdate = false;
            }
            this.changeBuildStage(WorldRegistry.BuildStage.IDLE);
            if (!this.buildQueue.isEmpty()) {
               this.wakeUpWorldBuilder();
            }
         }
      }
   }

   public void compileWorld() {
      if (this.buildStage == WorldRegistry.BuildStage.IDLE) {
         this.ensureWorldThread();
         this.changeBuildStage(WorldRegistry.BuildStage.COMPILE);
         PBlockPos previousBlockOffset = this.rtToWorldBlockOffset;

         while (!this.buildQueue.isEmpty()) {
            this.buildQueue.poll().run();
         }

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
         if (worldOffsetChanged || this.chunkSyncNeeded || !this.pendingChunkLoads.isEmpty()) {
            this.chunkSyncNeeded = false;
            chunkTopologyChanged = this.synchronizeChunks();
         }

         boolean rootNeedsRebuild = worldOffsetChanged || chunkTopologyChanged;
         boolean chunkContentChanged = this.update(this.rootMemoryManager, rootNeedsRebuild);
         if (chunkContentChanged) {
            this.closeChunkUpdate = true;
         }

         if (this.blockLightEnabled && (rootNeedsRebuild || this.consumeShadowStateDirty() || this.lightRegistry.consumeTracedLightSetDirty())) {
            this.lightRegistry.compileRegistry(this.rtToWorldBlockOffset, previousBlockOffset);
         }

         this.changeBuildStage(WorldRegistry.BuildStage.WAIT_FOR_UPLOAD);
      }
   }

   public boolean synchronizeChunks() {
      this.ensureWorldThread();
      Set<PChunkPos> inboundNonEmptyChunks = new HashSet<>();

      for (PChunkPos chunkPos : this.renderDispatcher.getInboundChunks()) {
         if (!this.renderDispatcher.isChunkEmpty(chunkPos)) {
            PChunkPos rtChunkPos = new PChunkPos(
               chunkPos.x - this.rtToWorldChunkOffset.x, chunkPos.y - this.rtToWorldChunkOffset.y, chunkPos.z - this.rtToWorldChunkOffset.z
            );
            if (isRtChunkInBounds(rtChunkPos)) {
               inboundNonEmptyChunks.add(chunkPos);
            }
         }
      }

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

      int loaded = 0;
      int chunkLoadBudget = this.chunks.isEmpty() ? INITIAL_CHUNK_LOAD_BUDGET : CHUNK_LOAD_BUDGET;
      while (!this.pendingChunkLoads.isEmpty() && loaded < chunkLoadBudget) {
         PChunkPos nextChunk = this.pendingChunkLoads.poll();
         this.pendingChunkSet.remove(nextChunk);
         if (inboundNonEmptyChunks.contains(nextChunk) && !this.chunks.containsKey(nextChunk)) {
            this.loadChunk(nextChunk);
            changed = true;
            loaded++;
         }
      }

      for (PChunkPos chunkPosxx : this.chunks.keySet().toArray(new PChunkPos[0])) {
         if (!inboundNonEmptyChunks.contains(chunkPosxx)) {
            this.unloadChunk(chunkPosxx);
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
      this.onChunkLoad(chunkPos);
      PChunk chunk = this.chunks.computeIfAbsent(chunkPos, k -> {
         PChunk newChunk = new PChunk();
         newChunk.allocate(this.cbMemoryManager);
         this.chunkSyncNeeded = true;
         return newChunk;
      });
      chunk.freeBlocks();

      for (int x = 0; x < 16; x++) {
         for (int y = 0; y < 16; y++) {
            for (int z = 0; z < 16; z++) {
               PBlockPos rtBlockPos = new PBlockPos(16 * chunkPos.x + x, 16 * chunkPos.y + y, 16 * chunkPos.z + z);
               BlockPos blockPos = new BlockPos(rtBlockPos.x, rtBlockPos.y, rtBlockPos.z);
               PBlock block = this.blockRegistry.getBlock(rtBlockPos);
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
                  int skyBrightness = 0;
                  ClientWorld level = MinecraftAccessor.getLevel();
                  if (level != null) {
                     ChunkLightingView skyLightView = level.getLightingProvider().get(LightType.SKY);
                     int brightness = skyLightView.getLightLevel(blockPos) / 2;

                     for (int i = 5; i >= 0; i--) {
                        skyBrightness = skyBrightness << 3 | Math.max(skyLightView.getLightLevel(blockPos.offset(FACES[i])) / 2, brightness);
                     }
                  }

                  chunk.set(x, y, z, block, skyBrightness);
               }
            }
         }
      }
   }

   public void unloadChunk(PChunkPos chunkPos) {
      this.ensureWorldThread();
      PChunk chunk = this.chunks.remove(chunkPos);
      if (chunk != null) {
         chunk.free(this.cbMemoryManager);
         chunk.freeBlocks();
      }
   }

   @Override
   public void allocate(MemoryManager memoryManager) {
      this.rootMemory = memoryManager.allocate(this.getSize());
   }

   @Override
   public void free(MemoryManager memoryManager) {
      memoryManager.free(this.rootMemory);
      this.rootMemory = null;
   }

   @Override
   public boolean update(MemoryManager memoryManager) {
      return this.update(memoryManager, true);
   }

   public boolean update(MemoryManager memoryManager, boolean forceRootUpload) {
      if (!forceRootUpload) {
         boolean anyChunkDirty = false;
         for (PChunk chunk : this.chunks.values()) {
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

      if (forceRootUpload) {
         Arrays.fill(this.rootSchematic.getData(), 0);
      }

      List<CompletableFuture<Void>> pendingOptimizations = new ArrayList<>();
      List<PChunk> dirtyChunks = new ArrayList<>();

      for (Entry<PChunkPos, PChunk> entry : this.chunks.entrySet()) {
         PChunkPos chunkPos = entry.getKey();
         PChunk chunk = entry.getValue();
         PChunkPos rtChunkPos = new PChunkPos(chunkPos.x, chunkPos.y, chunkPos.z);
         rtChunkPos.sub(this.rtToWorldChunkOffset.x, this.rtToWorldChunkOffset.y, this.rtToWorldChunkOffset.z);
         if (isRtChunkInBounds(rtChunkPos)) {
            if (chunk.isDirty()) {
               pendingOptimizations.add(chunk.optimizeAsync());
               dirtyChunks.add(chunk);
            }
            if (forceRootUpload) {
               this.rootSchematic.setEntry(rtChunkPos.x, rtChunkPos.y, rtChunkPos.z, chunk.getMemory().begin >> 2);
            }
         }
      }

      if (!pendingOptimizations.isEmpty()) {
         try {
            CompletableFuture.allOf(pendingOptimizations.toArray(CompletableFuture[]::new)).get();
         } catch (ExecutionException | InterruptedException e) {
            throw new RuntimeException(e);
         }
         for (PChunk chunk : dirtyChunks) {
            chunk.finishUpdate(this.cbMemoryManager);
         }
      }

      if (forceRootUpload) {
         try {
            this.rootSchematic.reset();
            this.rootSchematic.initialize();
            this.rootSchematic.optimizeThreaded().get();
            this.rootMemory.getBuffer().asIntBuffer().put(this.rootSchematic.getData());
            memoryManager.queueUpload(this);
         } catch (ExecutionException | InterruptedException e) {
            throw new RuntimeException(e);
         }
      }

      this.dirty = true;
      return true;
   }

   private boolean isRtChunkInBounds(PChunkPos rtChunkPos) {
      return rtChunkPos.x >= 0 && rtChunkPos.x < this.worldChunkSize
          && rtChunkPos.y >= 0 && rtChunkPos.y < this.worldChunkSize
          && rtChunkPos.z >= 0 && rtChunkPos.z < this.worldChunkSize;
   }

   public BlockRegistry getBlockRegistry() {
      return this.blockRegistry;
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

   public Map<PChunkPos, PChunk> getChunks() {
      return this.chunks;
   }

   public void ensureWorldThread() {
      if (Thread.currentThread() != this.worldCompilerThread) {
         throw new IllegalStateException("Called from wrong thread!");
      }
   }

   public void queueBuildJob(Runnable job) {
      this.buildQueue.add(job);
      this.shadowStateDirty = true;
   }

   public void queueGlJob(Runnable job) {
      this.glQueue.add(job);
   }

   public Vector3d toRt(Vector3d vector3d) {
      return new Vector3d(vector3d).sub(this.liveWorldBlockOffset);
   }

   public boolean fetchLightReload() {
      if (this.closeChunkUpload) {
         this.closeChunkUpload = false;
         this.chunkUploadAge = TEMPORAL_BLEND_FRAMES;
      }
      if (this.chunkUploadAge > 0) {
         this.chunkUploadAge--;
      }
      return false;
   }

   public float fetchLightBlendFactor() {
      if (this.chunkUploadAge > 0) {
         return (float) this.chunkUploadAge / TEMPORAL_BLEND_FRAMES;
      }
      return 0.0f;
   }

   public boolean consumeShadowStateDirty() {
      boolean shadowDirty = this.shadowStateDirty;
      this.shadowStateDirty = false;
      return shadowDirty;
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
