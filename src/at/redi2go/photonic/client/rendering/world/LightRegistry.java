package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.PhotonicsStorage;
import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.rendering.MinecraftAccessor;
import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;
import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.util.MultiThreader;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.SimpleMemoryOwner;
import at.redi2go.photonic.client.rendering.world.position.LightNodePos;
import at.redi2go.photonic.client.rendering.world.position.PBlockPos;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.util.AbstractQueue;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.PriorityQueue;
import java.util.Set;
import java.util.Map.Entry;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Consumer;
import java.util.function.Predicate;
import net.minecraft.block.Block;
import net.minecraft.util.math.BlockPos;
import net.minecraft.block.BlockState;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.world.ClientWorld;
import org.apache.commons.lang3.tuple.Pair;
import org.joml.Vector2f;
import org.joml.Vector3f;

public class LightRegistry implements Destructable {
   public static final int MAX_LIGHT_COUNT = 1000;
   private static final int LIGHT_BYTE_SIZE = 32;
   private final Predicate<PChunkPos> chunkEmptyPredicate;
   private final GlMemoryManager registryMemoryManager;
   private final MemoryOwner registryMemory;
   private final GlMemoryManager lightsMemoryManager;
   private final MemoryOwner lightsMemory;
   private final int maxLightsPerNode;
   private final int nodeSize;
   private final int worldSize;
   private final int nodeCount;
   private PBlockPos offset = new PBlockPos(0, 0, 0);
   private List<Pair<LightInstance, Integer>> tracedLights = new ArrayList<>();
   private final Set<Vector3f> tracedLightPositions = ConcurrentHashMap.newKeySet();
   private final Consumer<Set<LightBlock>> lightBlockUpdated;
   private final Map<Block, LightType> lightTypes = new HashMap<>();
   private volatile boolean building = false;
   private volatile boolean tracedLightSetDirty = true;

   public LightRegistry(int maxLightsPerNode, int nodeSize, int worldSize, Predicate<PChunkPos> chunkEmptyPredicate) {
      if (16 % nodeSize != 0) {
         throw new IllegalArgumentException();
      } else {
         this.chunkEmptyPredicate = chunkEmptyPredicate;
         this.maxLightsPerNode = maxLightsPerNode;
         this.nodeSize = nodeSize;
         this.worldSize = worldSize;
         this.nodeCount = worldSize / nodeSize;
         this.registryMemoryManager = new GlMemoryManager(
            GlTarget.SSBO, "light_registry_block", 4 * this.nodeCount * this.nodeCount * this.nodeCount * (1 + maxLightsPerNode), false
         );
         this.registryMemory = new SimpleMemoryOwner(this.registryMemoryManager, this.registryMemoryManager.getCapacity());
         this.lightsMemoryManager = new GlMemoryManager(GlTarget.UBO, "lights_uniform", 32004, true);
         this.lightsMemory = new SimpleMemoryOwner(this.lightsMemoryManager, this.lightsMemoryManager.getCapacity());
         PhotonicsStorage.Parameter<Set<LightBlock>> lightBlocksParameter = PhotonicsStorage.TRACED_LIGHT_BLOCKS;
         this.lightBlockUpdated = lightBlocks -> {
            this.registerLightBlocks(lightBlocks);
            this.tracedLightSetDirty = true;
            MinecraftClient.getInstance().worldRenderer.reload();
         };
         lightBlocksParameter.addObserver(this.lightBlockUpdated);
      }
   }

   public void init() {
      PhotonicsStorage.Parameter<Set<LightBlock>> lightBlocksParameter = PhotonicsStorage.TRACED_LIGHT_BLOCKS;
      this.registerLightBlocks(lightBlocksParameter.value);
   }

   public void compileRegistry(PBlockPos blockOffset) {
      if (this.building) {
         throw new IllegalStateException();
      } else if (MinecraftAccessor.getLevel() != null) {
         this.building = true;
         this.offset = blockOffset;
         this.createTracedLights();
         MultiThreader.runAndWait(this.nodeCount, x -> {
            for (int y = 0; y < this.nodeCount; y++) {
               for (int z = 0; z < this.nodeCount; z++) {
                  LightNodePos lightNodePos = new LightNodePos(x, y, z);
                  if (!this.chunkEmptyPredicate.test(lightNodePos.toBlockPos(this.nodeSize, blockOffset).toChunkPos())) {
                     this.compileAndStoreNode(lightNodePos);
                  }
               }
            }
         });
         this.storeLights();
         this.registryMemoryManager.queueUpload(this.registryMemory);
         this.lightsMemoryManager.queueUpload(this.lightsMemory);
         this.tracedLightSetDirty = false;
         this.building = false;
      }
   }

   private void compileAndStoreNode(LightNodePos pos) {
      PBlockPos blockPos = pos.toBlockPos(this.nodeSize, this.offset);
      Vector3f middleBlockPos = new Vector3f(blockPos.x + this.nodeSize / 2.0F, blockPos.y + this.nodeSize / 2.0F, blockPos.z + this.nodeSize / 2.0F);
      float[] luminanceCache = new float[this.tracedLights.size()];
      AbstractQueue<Entry<LightInstance, Integer>> sortedLights = new PriorityQueue<>(
         this.maxLightsPerNode, Comparator.comparing(l -> luminanceCache[l.getValue()])
      );

      for (Entry<LightInstance, Integer> light : this.tracedLights) {
         float luminance = light.getKey().getType().luminanceFrom(light.getKey().getPosition(), middleBlockPos);
         luminanceCache[light.getValue()] = luminance;
         if (!(luminance < 0.001F)) {
            sortedLights.add(light);
            if (sortedLights.size() > this.maxLightsPerNode) {
               sortedLights.poll();
            }
         }
      }

      IntBuffer buffer = this.registryMemory.getMemory().getBuffer().asIntBuffer();
      int index = (1 + this.maxLightsPerNode) * (pos.y * this.nodeCount * this.nodeCount + pos.z * this.nodeCount + pos.x);
      buffer.put(index, sortedLights.size());
      index += sortedLights.size();

      while (!sortedLights.isEmpty()) {
         buffer.put(index--, sortedLights.remove().getValue());
      }
   }

   private void storeLights() {
      FloatBuffer buffer = this.lightsMemory.getMemory().getBuffer().asFloatBuffer();

      for (Entry<LightInstance, Integer> entry : this.tracedLights) {
         LightInstance lightInstance = entry.getKey();
         buffer.position(8 * entry.getValue());
         store(lightInstance.getPosition(), buffer);
         store(lightInstance.getType().getColor(), buffer);
         store(lightInstance.getType().getAttenuation(), buffer);
      }
   }

   private void createTracedLights() {
      ClientWorld level = MinecraftAccessor.getLevel();
      HashMap<BlockState, AtomicInteger> usages = new HashMap<>();
      List<LightInstance> lightInstances = new ArrayList<>();

      for (Vector3f lightPosition : this.tracedLightPositions) {
         BlockState blockState = level.getBlockState(
            new BlockPos((int)Math.floor(lightPosition.x), (int)Math.floor(lightPosition.y), (int)Math.floor(lightPosition.z))
         );
         LightType lightType = this.lightTypes.get(blockState.getBlock());
         if (lightType != null && lightType.isTraced() && lightType.blockStateEmitsLight(blockState)) {
            lightInstances.add(new LightInstance(lightPosition, lightType));
            usages.computeIfAbsent(blockState, k -> new AtomicInteger(0)).addAndGet(1);
         } else {
            this.tracedLightPositions.remove(lightPosition);
         }
      }

      if (lightInstances.size() > 1000) {
         Vector3f cameraPosition = MinecraftAccessor.getCameraPosition();
         lightInstances = lightInstances.stream()
            .sorted(Comparator.comparingDouble(l -> -l.getType().luminanceFrom(l.getPosition(), cameraPosition)))
            .limit(1000L)
            .toList();
      }

      AtomicInteger lightIdCounter = new AtomicInteger(0);
      this.tracedLights = lightInstances.stream().map(lightInstance -> Pair.of(lightInstance, lightIdCounter.getAndIncrement())).toList();
   }

   public boolean upload() {
      boolean uploadDone = true;
      uploadDone &= this.registryMemoryManager.upload();
      return uploadDone & this.lightsMemoryManager.upload();
   }

   public void registerBlockState(BlockState blockState, PBlock pBlock) {
      LightType lightType = this.lightTypes.get(blockState.getBlock());
      if (lightType != null && lightType.blockStateEmitsLight(blockState)) {
         Vector3f lightColor = new Vector3f(lightType.getColor());
         if (lightType.isTraced()) {
            lightColor.mul(0.5F);
         }

         Raytracer.INSTANCE.getWorldRegistry().registerEmittableBlock(pBlock, lightColor);
      }
   }

   private void registerLightBlocks(Collection<LightBlock> lightBLocks) {
      for (LightBlock lightBlock : lightBLocks) {
         this.lightTypes.put(lightBlock.block, lightBlock.lightType);
         Vector3f emittingColor = lightBlock.lightType.isTraced() ? new Vector3f(0.0F) : lightBlock.lightType.getColor();
         Map<BlockState, PBlock> blockSchematicCache = Map.copyOf(Raytracer.INSTANCE.getBlockRegistry().getBlockSchematicCache());

         for (Entry<BlockState, PBlock> entry : blockSchematicCache.entrySet()) {
            if (entry.getKey().getBlock() == lightBlock.block && lightBlock.lightType.blockStateEmitsLight(entry.getKey())) {
               Raytracer.INSTANCE.getWorldRegistry().registerEmittableBlock(entry.getValue(), emittingColor);
            }
         }
      }
   }

   public void onBlockLoad(Vector3f position) {
      ClientWorld level = MinecraftAccessor.getLevel();
      if (level != null) {
         Vector3f tracedPosition = new Vector3f(position).add(0.5F, 0.5F, 0.5F);
         BlockState blockState = level.getBlockState(new BlockPos((int)position.x, (int)position.y, (int)position.z));
         LightType lightType = this.lightTypes.get(blockState.getBlock());
         boolean isTracedLight = lightType != null && lightType.isTraced() && lightType.blockStateEmitsLight(blockState);
         if (isTracedLight) {
            if (this.tracedLightPositions.add(tracedPosition)) {
               this.tracedLightSetDirty = true;
            }
         } else if (this.tracedLightPositions.remove(tracedPosition)) {
            this.tracedLightSetDirty = true;
         }
      }
   }

   public boolean consumeTracedLightSetDirty() {
      boolean dirty = this.tracedLightSetDirty;
      this.tracedLightSetDirty = false;
      return dirty;
   }

   public GlMemoryManager getRegistryMemoryManager() {
      return this.registryMemoryManager;
   }

   public GlMemoryManager getLightsMemoryManager() {
      return this.lightsMemoryManager;
   }

   @Override
   public void free() {
      this.lightsMemoryManager.free();
      this.registryMemoryManager.free();
      PhotonicsStorage.Parameter<Set<LightBlock>> lightBlocks = PhotonicsStorage.TRACED_LIGHT_BLOCKS;
      lightBlocks.removeObserver(this.lightBlockUpdated);
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
}
