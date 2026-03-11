package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.config.PhotonicsConfig;
import at.redi2go.photonic.client.config.ShaderPackLights;
import at.redi2go.photonic.client.config.lights.BlockLightInfo;
import at.redi2go.photonic.client.config.lights.LightList;
import at.redi2go.photonic.client.config.lights.LightsProvider;
import at.redi2go.photonic.client.mixin.ShaderPackAccessor;
import at.redi2go.photonic.client.rendering.MinecraftAccessor;
import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;
import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.util.IrisUtil;
import at.redi2go.photonic.client.rendering.util.MultiThreader;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.SimpleMemoryOwner;
import at.redi2go.photonic.client.rendering.world.position.LightNodePos;
import at.redi2go.photonic.client.rendering.world.position.PBlockPos;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import it.unimi.dsi.fastutil.objects.Object2ObjectOpenHashMap;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.util.AbstractQueue;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.PriorityQueue;
import java.util.Map.Entry;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReadWriteLock;
import java.util.concurrent.locks.ReentrantReadWriteLock;
import java.util.function.Predicate;
import net.irisshaders.iris.Iris;
import net.irisshaders.iris.shaderpack.ShaderPack;
import net.irisshaders.iris.shaderpack.include.AbsolutePackPath;
import net.minecraft.block.BlockState;
import net.minecraft.block.Blocks;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.world.ClientWorld;
import net.minecraft.util.math.BlockPos;
import org.apache.commons.lang3.tuple.Pair;
import org.joml.Vector2f;
import org.joml.Vector3f;

public class LightRegistry implements Destructable {
   private static final int LIGHT_BYTE_SIZE = 48;
   private static final float MIN_NODE_LUMINANCE = 0.001F;

   private static final BlockPos[] NEIGHBORS = {
      new BlockPos(0, 1, 0), new BlockPos(0, -1, 0),
      new BlockPos(1, 0, 0), new BlockPos(-1, 0, 0),
      new BlockPos(0, 0, 1), new BlockPos(0, 0, -1)
   };

   private final Predicate<PChunkPos> chunkEmptyPredicate;
   private final boolean lightBinningEnabled;
   private final GlMemoryManager registryMemoryManager;
   private final MemoryOwner registryMemory;
   private final GlMemoryManager lightsMemoryManager;
   private final MemoryOwner lightsMemory;
   private final GlMemoryManager lightMappingMemoryManager;
   private final MemoryOwner lightMappingMemory;
   private final int maxLights;
   private final int maxLightsPerNode;
   private final int nodeSize;
   private final int worldSize;
   private final int nodeCount;
   private short[] lightRegions;
   private short[] lightRegionsPrev;
   private short[] newLightIndices;
   private PBlockPos offset = new PBlockPos(0, 0, 0);
   private int lightCount = 0;
   private LightInstance[] tracedLights = new LightInstance[0];
   private final Map<Vector3f, TracedLightPosition> tracedLightPositions = new ConcurrentHashMap<>();
   private final PhotonicsConfig.Observer<LightList> lightListObserver;
   private LightList lightList = new LightList();
   private final ReadWriteLock lock;
   private boolean building = false;
   private int compileCount = 0;
   private LightsProvider lightsProvider = null;
   private volatile boolean tracedLightSetDirty = true;

   public LightRegistry(int maxLights, int maxLightsPerNode, int nodeSize, int worldSize, Predicate<PChunkPos> chunkEmptyPredicate, boolean lightBinningEnabled) {
      if (16 % nodeSize != 0) {
         throw new IllegalArgumentException();
      }
      this.chunkEmptyPredicate = chunkEmptyPredicate;
      this.lightBinningEnabled = lightBinningEnabled;
      this.maxLights = maxLights;
      this.maxLightsPerNode = maxLightsPerNode;
      this.nodeSize = nodeSize;
      this.worldSize = worldSize;
      this.nodeCount = worldSize / nodeSize;
      int lightSize = this.nodeCount * this.nodeCount * this.nodeCount * (1 + maxLightsPerNode);
      this.registryMemoryManager = new GlMemoryManager(GlTarget.SSBO, "light_registry_block", 4 * lightSize, false);
      this.registryMemory = new SimpleMemoryOwner(this.registryMemoryManager, this.registryMemoryManager.getCapacity());
      this.lightRegions = new short[lightSize];
      this.lightRegionsPrev = new short[lightSize];
      this.newLightIndices = new short[maxLights];
      this.lightsMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_light_list", maxLights * LIGHT_BYTE_SIZE + 4, true);
      this.lightsMemory = new SimpleMemoryOwner(this.lightsMemoryManager, this.lightsMemoryManager.getCapacity());
      this.lightMappingMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_light_list_mapping", maxLights * 4, false);
      this.lightMappingMemory = new SimpleMemoryOwner(this.lightMappingMemoryManager, this.lightMappingMemoryManager.getCapacity());
      this.lightListObserver = PhotonicsConfig.observe(c -> PhotonicsConfig.getLightList(), c -> {
         this.lightList = c;
         this.registerLightBlocks(this.lightList);
         this.tracedLightSetDirty = true;
         MinecraftClient.getInstance().worldRenderer.reload();
      });
      this.lock = new ReentrantReadWriteLock();
   }

   public Lock readLock() {
      return this.lock.readLock();
   }

   public void init() {
      this.lightList = PhotonicsConfig.getLightList();
      this.registerLightBlocks(this.lightList);
      String shaderPackName = (String) Iris.getIrisConfig()
         .getShaderPackName()
         .orElseThrow(() -> new RuntimeException("No shaderpack selected!"));
      this.lightsProvider = Iris.getCurrentPack().map(it -> (ShaderPackAccessor) it).flatMap(it -> {
         String contents = it.getSourceProvider().apply(AbsolutePackPath.fromAbsolutePath("/ph_lights.json"));
         if (contents == null) {
            return Optional.empty();
         }
         try {
            ShaderPackLights lights = ShaderPackLights.parse(contents);
            lights.setShaderPack((ShaderPack) it);
            PhotonicsConfig.registerLightProvider(lights);
            return Optional.of(lights);
         } catch (Exception e) {
            Photonic.error("Error while parsing ph_lights.json for " + shaderPackName, e);
            return Optional.empty();
         }
      }).orElse(null);
   }

   public int totalLights() {
      return this.tracedLightPositions.size();
   }

   public int lightCount() {
      return this.lightCount;
   }

   public void compileRegistry(PBlockPos blockOffset, PBlockPos previousOffset) {
      if (this.building) {
         throw new IllegalStateException();
      }
      ClientWorld level = MinecraftAccessor.getLevel();
      if (level == null) {
         return;
      }
      this.building = true;
      this.offset = blockOffset;
      this.lock.writeLock().lock();
      LightInstance[] lights;
      try {
         if (++this.compileCount % 10 == 0) {
            this.compileCount = 0;
            lights = this.toLightInstanceArrayClearUnloaded(level);
         } else {
            lights = this.toLightInstanceArray();
         }
      } finally {
         this.lock.writeLock().unlock();
      }

      boolean lightsChanged = this.createTracedLights(lights, previousOffset);
      short[] tmp = this.lightRegionsPrev;
      this.lightRegionsPrev = this.lightRegions;
      this.lightRegions = tmp;

      if (lightsChanged || !blockOffset.equals(previousOffset)) {
         boolean fullRebuild = !blockOffset.equals(previousOffset);
         MultiThreader.runAndWait(this.nodeCount, x -> {
            for (int y = 0; y < this.nodeCount; y++) {
               for (int z = 0; z < this.nodeCount; z++) {
                  LightNodePos lightNodePos = new LightNodePos(x, y, z);
                  if (this.chunkEmptyPredicate.test(lightNodePos.toBlockPos(this.nodeSize, blockOffset).toChunkPos())) {
                     continue;
                  }
                  this.compileAndStoreNode(lightNodePos, previousOffset);
               }
            }
         });
      }

      this.storeLights();
      this.registryMemoryManager.queueUpload(this.registryMemory);
      this.lightsMemoryManager.queueUpload(this.lightsMemory);
      this.building = false;
   }

   private int toLightIndex(int x, int y, int z) {
      return (1 + this.maxLightsPerNode) * (y * this.nodeCount * this.nodeCount + z * this.nodeCount + x);
   }

   private int toLightIndex(LightNodePos pos) {
      return (1 + this.maxLightsPerNode) * (pos.y * this.nodeCount * this.nodeCount + pos.z * this.nodeCount + pos.x);
   }

   public void markDirtyRegions(PBlockPos pos, float lightRadius, PBlockPos previousOffset) {
      int radius = (int) Math.ceil(lightRadius / this.nodeSize);
      LightNodePos start = pos.toLightPos(this.nodeSize, previousOffset);
      LightNodePos end = new LightNodePos(start);
      start.sub(radius);
      end.add(radius);

      for (int x = start.x; x <= end.x; x++) {
         for (int y = start.y; y <= end.y; y++) {
            for (int z = start.z; z <= end.z; z++) {
               int index = this.toLightIndex(x, y, z);
               if (index >= 0 && index < this.lightRegions.length) {
                  this.lightRegions[index] = (short) (this.lightRegions[index] & 32767);
               }
            }
         }
      }
   }

   private boolean compileAndStoreNode(LightNodePos pos, PBlockPos previousOffset) {
      PBlockPos blockPos = pos.toBlockPos(this.nodeSize, this.offset);
      IntBuffer buffer = this.registryMemory.getMemory().getBuffer().asIntBuffer();
      int curIndex = this.toLightIndex(pos);
      LightNodePos prevLightPos = blockPos.toLightPos(this.nodeSize, previousOffset);
      int prevIndex = this.toLightIndex(prevLightPos);

      if (prevIndex >= 0 && prevIndex < this.lightRegions.length) {
         short count = this.lightRegionsPrev[prevIndex];
         if ((count & -32768) != 0) {
            int length = count & 32767;
            buffer.put(curIndex, length);
            this.lightRegions[curIndex] = count;
            for (int i = 1; i <= length; i++) {
               short light = this.lightRegionsPrev[prevIndex + i];
               light = this.newLightIndices[light];
               buffer.put(curIndex + i, light);
               this.lightRegions[curIndex + i] = light;
            }
            return true;
         }
      }

      Vector3f middleBlockPos = new Vector3f(
         blockPos.x + this.nodeSize * 0.5F,
         blockPos.y + this.nodeSize * 0.5F,
         blockPos.z + this.nodeSize * 0.5F
      );
      float[] luminanceCache = new float[this.tracedLights.length];
      AbstractQueue<LightInstance> sortedLights = new PriorityQueue<>(
         this.maxLightsPerNode, compareWithCache(luminanceCache)
      );

      for (LightInstance light : this.tracedLights) {
         float luminance = light.type().luminanceFrom(light.position(), middleBlockPos);
         luminanceCache[light.index()] = luminance;
         if (!(luminance < MIN_NODE_LUMINANCE)) {
            sortedLights.add(light);
            if (sortedLights.size() > this.maxLightsPerNode) {
               sortedLights.poll();
            }
         }
      }

      buffer.put(curIndex, sortedLights.size());
      this.lightRegions[curIndex] = (short) (sortedLights.size() | -32768);

      for (int offsetIdx = sortedLights.size(); !sortedLights.isEmpty(); offsetIdx--) {
         int lightIdx = sortedLights.remove().index();
         buffer.put(curIndex + offsetIdx, lightIdx);
         this.lightRegions[curIndex + offsetIdx] = (short) lightIdx;
      }
      return false;
   }

   private void storeLights() {
      FloatBuffer buffer = this.lightsMemory.getMemory().getBuffer().asFloatBuffer();
      for (LightInstance light : this.tracedLights) {
         buffer.position(12 * light.index());
         BlockLightInfo lightInfo = light.type();
         store(light.position(), buffer);
         buffer.put(Float.intBitsToFloat(light.blockId()));
         store(lightInfo.getColorAsVector(), buffer);
         buffer.put(lightInfo.intensity() / 100.0F);
         store(lightInfo.getAttenuationAsVector(), buffer);
         buffer.put(lightInfo.falloff());
         buffer.put(lightInfo.radiusInBlocks());
      }
   }

   private boolean createTracedLights(LightInstance[] lights, PBlockPos previousOffset) {
      Arrays.fill(this.newLightIndices, (short) 0);
      if (lights.length > this.maxLights) {
         Vector3f cameraPosition = new Vector3f(MinecraftAccessor.getCameraPosition());
         Arrays.sort(lights, Comparator.comparingDouble(l -> -l.type().luminanceFrom(l.position(), cameraPosition)));
         lights = Arrays.copyOf(lights, this.maxLights);
      }

      LightInstance[] prevLights = this.tracedLights;
      Object2ObjectOpenHashMap<Vector3f, LightInvalidation> differences = new Object2ObjectOpenHashMap<>(
         Math.max(lights.length, prevLights.length)
      );

      for (int i = 0; i < prevLights.length; i++) {
         LightInstance light = prevLights[i];
         LightInvalidation diff = differences.computeIfAbsent(light.position(), LightInvalidation::new);
         diff.before = light.type();
         diff.beforeIndex = i;
      }

      for (int i = 0; i < lights.length; i++) {
         LightInstance light = lights[i];
         LightInvalidation diff = differences.computeIfAbsent(light.position(), LightInvalidation::new);
         diff.after = light.type();
         diff.afterIndex = i;
         light.setIndex(i);
      }

      boolean anyDirty = false;
      for (Entry<Vector3f, LightInvalidation> e : differences.entrySet()) {
         LightInvalidation diff = e.getValue();
         BlockLightInfo before = diff.before;
         int beforeIndex = diff.beforeIndex;
         BlockLightInfo after = diff.after;
         int afterIndex = diff.afterIndex;
         if (before == after) {
            this.newLightIndices[beforeIndex] = (short) afterIndex;
         } else {
            anyDirty = true;
            float radius = 0.0F;
            if (before != null) radius = before.radiusInBlocks();
            if (after != null) radius = Math.max(radius, after.radiusInBlocks());
            this.markDirtyRegions(new PBlockPos((int) e.getKey().x, (int) e.getKey().y, (int) e.getKey().z), radius, previousOffset);
         }
      }

      this.tracedLights = lights;
      return anyDirty;
   }

   public void clearLightMappings() {
      java.nio.IntBuffer buffer = this.lightMappingMemory.getMemory().getBuffer().asIntBuffer();
      for (int i = 0; i < this.maxLights; i++) {
         buffer.put(i, i);
      }
      this.lightMappingMemoryManager.queueUpload(this.lightMappingMemory);
      this.lightMappingMemoryManager.upload();
   }

   public boolean upload() {
      boolean uploadDone = true;
      uploadDone &= this.registryMemoryManager.upload();
      uploadDone &= this.lightsMemoryManager.upload();
      uploadDone &= this.lightMappingMemoryManager.upload();
      this.lightCount = this.tracedLights.length;
      return uploadDone;
   }

   public void registerBlockState(BlockState blockState, PBlock pBlock) {
      BlockLightInfo lightInfo = this.lightList.get(blockState);
      if (lightInfo != null) {
         if (lightInfo.isTraced()) {
            pBlock.setEmissionColor(new Vector3f(0.0F));
         } else {
            pBlock.setEmissionColor(lightInfo.getColorAsVector());
         }
      }
   }

   private void registerLightBlocks(LightList lights) {
      Raytracer.INSTANCE.getBlockRegistry().getBlockSchematicCache().entrySet().stream()
         .map(e -> Pair.of(e.getValue(), lights.get(e.getKey())))
         .filter(e -> e.getValue() != null)
         .forEach(entry -> {
            PBlock pBlock = entry.getKey();
            BlockLightInfo lightInfo = entry.getValue();
            if (lightInfo.isTraced()) {
               pBlock.setEmissionColor(new Vector3f(0.0F));
            } else {
               pBlock.setEmissionColor(lightInfo.getColorAsVector());
            }
         });
   }

   public boolean hasPossibleLight(BlockState blockState) {
      return this.lightList.get(blockState) != null;
   }

   public void onBlockLoad(Vector3f position) {
      ClientWorld level = MinecraftAccessor.getLevel();
      if (level == null) {
         return;
      }
      BlockPos blockPos = new BlockPos((int) position.x, (int) position.y, (int) position.z);
      BlockState blockState = level.getBlockState(blockPos);
      BlockLightInfo lightInfo = this.lightList.get(blockState);
      if (lightInfo == null) {
         Vector3f lightPos = new Vector3f(position).add(0.5F, 0.5F, 0.5F);
         if (this.tracedLightPositions.remove(lightPos) != null) {
            this.tracedLightSetDirty = true;
         }
         return;
      }
      Vector3f lightPos = new Vector3f(position).add(0.5F, 0.5F, 0.5F);
      if (lightInfo.isTraced() && !shouldCull(level, blockPos)) {
         int blockId = IrisUtil.getBlockId(blockState);
         TracedLightPosition previous = this.tracedLightPositions.put(lightPos, new TracedLightPosition(blockId, lightInfo));
         if (previous == null || previous.blockId() != blockId || previous.lightInfo() != lightInfo) {
            this.tracedLightSetDirty = true;
         }
      } else if (this.tracedLightPositions.remove(lightPos) != null) {
         this.tracedLightSetDirty = true;
      }
   }

   public boolean consumeTracedLightSetDirty() {
      boolean dirty = this.tracedLightSetDirty;
      this.tracedLightSetDirty = false;
      return dirty;
   }

   public boolean isLightBinningEnabled() {
      return this.lightBinningEnabled;
   }

   public GlMemoryManager getRegistryMemoryManager() {
      return this.registryMemoryManager;
   }

   public GlMemoryManager getLightsMemoryManager() {
      return this.lightsMemoryManager;
   }

   public GlMemoryManager getLightMappingMemoryManager() {
      return this.lightMappingMemoryManager;
   }

   private LightInstance[] toLightInstanceArray() {
      LightInstance[] lights = new LightInstance[this.tracedLightPositions.size()];
      int i = 0;
      for (Entry<Vector3f, TracedLightPosition> e : this.tracedLightPositions.entrySet()) {
         lights[i++] = new LightInstance(e.getValue().blockId(), e.getKey(), e.getValue().lightInfo());
      }
      return lights;
   }

   private LightInstance[] toLightInstanceArrayClearUnloaded(ClientWorld level) {
      List<LightInstance> lights = new ArrayList<>(this.tracedLightPositions.size());
      Iterator<Entry<Vector3f, TracedLightPosition>> itr = this.tracedLightPositions.entrySet().iterator();
      while (itr.hasNext()) {
         Entry<Vector3f, TracedLightPosition> e = itr.next();
         Vector3f pos = e.getKey();
         TracedLightPosition tracedPos = e.getValue();
         BlockPos blockPos = new BlockPos((int) pos.x, (int) pos.y, (int) pos.z);
         if (!level.isChunkLoaded(blockPos)) {
            itr.remove();
            this.tracedLightSetDirty = true;
         } else {
            lights.add(new LightInstance(tracedPos.blockId(), pos, tracedPos.lightInfo()));
         }
      }
      return lights.toArray(LightInstance[]::new);
   }

   @Override
   public void free() {
      this.lightsMemoryManager.free();
      this.registryMemoryManager.free();
      this.lightMappingMemoryManager.free();
      this.lightListObserver.unregister();
      if (this.lightsProvider != null) {
         PhotonicsConfig.removeLightProvider(this.lightsProvider);
      }
   }

   private static void store(Vector3f vector3f, FloatBuffer buffer) {
      buffer.put(vector3f.x);
      buffer.put(vector3f.y);
      buffer.put(vector3f.z);
   }

   private static void store(Vector2f vector2f, FloatBuffer buffer) {
      buffer.put(vector2f.x);
      buffer.put(vector2f.y);
   }

   private static Comparator<LightInstance> compareWithCache(float[] luminanceCache) {
      return (e1, e2) -> Float.compare(luminanceCache[e1.index()], luminanceCache[e2.index()]);
   }

   private static boolean shouldCull(ClientWorld level, BlockPos blockPos) {
      for (BlockPos offset : NEIGHBORS) {
         BlockPos neighborPos = blockPos.add(offset);
         BlockState neighbor = level.getBlockState(neighborPos);
         if (neighbor.getBlock() != Blocks.LAVA && (!neighbor.isSolidBlock(level, neighborPos) || !neighbor.isOpaque())) {
            return false;
         }
      }
      return true;
   }
}
