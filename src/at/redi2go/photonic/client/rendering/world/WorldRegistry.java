package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.rendering.MinecraftAccessor;
import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;
import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.opengl.rendering.IRenderDispatcher;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.util.BufferUtils;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import at.redi2go.photonic.client.rendering.world.buffer.SimpleMemoryOwner;
import at.redi2go.photonic.client.rendering.world.position.PBlockPos;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.Map.Entry;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.ExecutionException;
import org.joml.Vector3f;

public class WorldRegistry implements MemoryOwner, Destructable {
   private final IRenderDispatcher renderDispatcher;
   private final WorldCompilerThread worldCompilerThread;
   private final LightRegistry lightRegistry;
   private final GlMemoryManager cbMemoryManager;
   private final SimpleMemoryOwner blockLightRegistry;
   private final GlMemoryManager rootMemoryManager;
   private MemoryRegion rootMemory;
   private final Schematic rootSchematic;
   private final ConcurrentLinkedQueue<Runnable> buildQueue = new ConcurrentLinkedQueue<>();
   private final ConcurrentLinkedQueue<Runnable> glQueue = new ConcurrentLinkedQueue<>();
   private final Map<PChunkPos, PChunk> chunks = new HashMap<>();
   private PBlockPos rtToWorldBlockOffset = new PBlockPos(0, 0, 0);
   private PChunkPos rtToWorldChunkOffset = new PChunkPos(0, 0, 0);
   private Vector3f liveWorldBlockOffset = new Vector3f();
   private PBlockPos liveWorldMinVoxel = new PBlockPos(0, 0, 0);
   private PBlockPos liveWorldMaxVoxel = new PBlockPos(0, 0, 0);
   private WorldRegistry.BuildStage buildStage = WorldRegistry.BuildStage.IDLE;
   private boolean closeChunkUpdate = false;
   private boolean closeChunkUpload = false;
   private volatile boolean shadowStateDirty = true;
   private final int worldBlockSize;
   private final int worldChunkSize;
   private PBlockPos worldMinVoxel = new PBlockPos(0, 0, 0);
   private PBlockPos worldMaxVoxel = new PBlockPos(0, 0, 0);
   private boolean dirty = true;
   private volatile boolean chunkSyncNeeded = true;

   public WorldRegistry(IRenderDispatcher renderDispatcher) {
      this.renderDispatcher = renderDispatcher;
      this.worldChunkSize = 32;
      this.worldBlockSize = 16 * this.worldChunkSize;
      this.rootSchematic = new Schematic(this.worldChunkSize, this.worldChunkSize, this.worldChunkSize);
      this.lightRegistry = new LightRegistry(20, 8, this.worldBlockSize, renderDispatcher::isChunkEmpty);
      this.cbMemoryManager = new GlMemoryManager(GlTarget.SSBO, "cb_block", 536870912, true);
      int maxBlockCount = this.cbMemoryManager.getCapacity() / 16384;
      this.blockLightRegistry = new SimpleMemoryOwner(this.cbMemoryManager, 32 * maxBlockCount);
      this.rootMemoryManager = new GlMemoryManager(GlTarget.SSBO, "root_uniform", 4 * this.worldChunkSize * this.worldChunkSize * this.worldChunkSize, false);
      this.worldCompilerThread = new WorldCompilerThread(this);
      this.allocate(this.rootMemoryManager);
   }

   public void upload() {
      if (this.buildStage == WorldRegistry.BuildStage.WAIT_FOR_UPLOAD) {
         this.changeBuildStage(WorldRegistry.BuildStage.UPLOAD);
         this.cbMemoryManager.queueUpload(this.blockLightRegistry);
         boolean uploadDone = true;
         uploadDone &= this.lightRegistry.upload();
         uploadDone &= this.cbMemoryManager.upload();
         if (!uploadDone) {
            this.buildStage = WorldRegistry.BuildStage.WAIT_FOR_UPLOAD;
         } else {
            this.rootMemoryManager.upload();
            this.liveWorldBlockOffset = new Vector3f(this.rtToWorldBlockOffset.x, this.rtToWorldBlockOffset.y, this.rtToWorldBlockOffset.z);
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
         if (worldOffsetChanged || this.chunkSyncNeeded) {
            this.chunkSyncNeeded = false;
            chunkTopologyChanged = this.synchronizeChunks();
         }
         boolean rootNeedsRebuild = worldOffsetChanged || chunkTopologyChanged;
         boolean chunkContentChanged = this.update(this.rootMemoryManager, rootNeedsRebuild);
         if (chunkContentChanged) {
            this.closeChunkUpdate = true;
         }

         if (chunkContentChanged || rootNeedsRebuild || this.lightRegistry.consumeTracedLightSetDirty() || this.consumeShadowStateDirty()) {
            this.lightRegistry.compileRegistry(this.rtToWorldBlockOffset);
         }

         this.changeBuildStage(WorldRegistry.BuildStage.WAIT_FOR_UPLOAD);
      }
   }

   public boolean synchronizeChunks() {
      this.ensureWorldThread();
      boolean changed = false;
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

      for (PChunkPos chunkPosx : inboundNonEmptyChunks) {
         if (!this.chunks.containsKey(chunkPosx)) {
            this.loadChunk(chunkPosx);
            changed = true;
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

   public void loadChunk(PChunkPos chunkPos) {
      this.ensureWorldThread();
      this.onChunkLoad(chunkPos);
      PChunk chunk = this.chunks.computeIfAbsent(chunkPos, k -> {
         PChunk newChunk = new PChunk();
         newChunk.allocate(this.cbMemoryManager);
         return newChunk;
      });

      for (int x = 0; x < 16; x++) {
         for (int y = 0; y < 16; y++) {
            for (int z = 0; z < 16; z++) {
               PBlockPos blockPos = new PBlockPos(16 * chunkPos.x + x, 16 * chunkPos.y + y, 16 * chunkPos.z + z);
               PBlock block = Raytracer.INSTANCE.getBlockRegistry().getBlock(blockPos);
               if (block != null && block.getMemory() == null) {
                  throw new IllegalStateException();
               }

               chunk.set(x, y, z, block);
            }
         }
      }
   }

   public void unloadChunk(PChunkPos chunkPos) {
      this.ensureWorldThread();
      PChunk chunk = this.chunks.remove(chunkPos);
      if (chunk != null) {
         chunk.free(this.cbMemoryManager);
      }
   }

   @Override
   public void allocate(GlMemoryManager memoryManager) {
      this.rootMemory = memoryManager.allocate(this.getSize());
   }

   @Override
   public void free(GlMemoryManager memoryManager) {
      memoryManager.free(this.rootMemory);
      this.rootMemory = null;
   }

   @Override
   public boolean update(GlMemoryManager memoryManager) {
      return this.update(memoryManager, true);
   }

   public boolean update(GlMemoryManager memoryManager, boolean forceRootUpload) {
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

      for (Entry<PChunkPos, PChunk> entry : this.chunks.entrySet()) {
         PChunkPos chunkPos = entry.getKey();
         PChunk chunk = entry.getValue();
         PChunkPos rtChunkPos = new PChunkPos(chunkPos.x, chunkPos.y, chunkPos.z);
         rtChunkPos.sub(this.rtToWorldChunkOffset.x, this.rtToWorldChunkOffset.y, this.rtToWorldChunkOffset.z);
         if (isRtChunkInBounds(rtChunkPos)) {
            chunk.update(this.cbMemoryManager);
            if (forceRootUpload) {
               this.rootSchematic.setEntry(rtChunkPos.x, rtChunkPos.y, rtChunkPos.z, chunk.getMemory().begin >> 2);
            }
         }
      }

      if (forceRootUpload) {
         try {
            this.rootSchematic.reset();
            this.rootSchematic.initialize();
            this.rootSchematic.optimizeThreaded().get();
            this.rootMemory.getBuffer().asIntBuffer().put(this.rootSchematic.getData());
            memoryManager.queueUpload(this);
         } catch (ExecutionException | InterruptedException var7) {
            throw new RuntimeException(var7);
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

   public void registerEmittableBlock(PBlock block, Vector3f color) {
      int index = block.getMemory().begin / 16384;
      this.blockLightRegistry.getMemory().getBuffer().put(4 * index, BufferUtils.packUnorm4x8(color.x, color.y, color.z, 0.0F));
      block.setLightSourceRegistered(true);
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
      float cameraDistance = new Vector3f(chunkBlockPos.x, chunkBlockPos.y, chunkBlockPos.z)
         .add(new Vector3f(8.0F))
         .add(new Vector3f(cameraPosition).mul(-1.0F))
         .length();
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
      this.chunkSyncNeeded = true;
   }

   public void markChunkSyncNeeded() {
      this.chunkSyncNeeded = true;
   }

   public void queueGlJob(Runnable job) {
      this.glQueue.add(job);
   }

   public Vector3f toRt(Vector3f vector3f) {
      return new Vector3f(vector3f).sub(this.liveWorldBlockOffset);
   }

   public boolean fetchLightReload() {
      boolean lightReload = this.closeChunkUpload;
      this.closeChunkUpload = false;
      return lightReload;
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

   public Vector3f getWorldOffset() {
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

   static {
      WorldRegistry.BuildStage.IDLE.before = WorldRegistry.BuildStage.UPLOAD;
      WorldRegistry.BuildStage.COMPILE.before = WorldRegistry.BuildStage.IDLE;
      WorldRegistry.BuildStage.WAIT_FOR_UPLOAD.before = WorldRegistry.BuildStage.COMPILE;
      WorldRegistry.BuildStage.UPLOAD.before = WorldRegistry.BuildStage.WAIT_FOR_UPLOAD;
   }

   public static enum BuildStage {
      IDLE,
      COMPILE,
      WAIT_FOR_UPLOAD,
      UPLOAD;

      public WorldRegistry.BuildStage before;
   }
}
