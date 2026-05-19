package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.PhotonicsStorage;
import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.ShaderAutomation;
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
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.SimpleMemoryOwner;
import at.redi2go.photonic.client.rendering.world.position.PBlockPos;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.Iterator;
import java.util.List;
import java.util.EnumMap;
import java.util.Map;
import java.util.Map.Entry;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.LongAdder;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReadWriteLock;
import java.util.concurrent.locks.ReentrantReadWriteLock;
import net.irisshaders.iris.Iris;
import net.irisshaders.iris.shaderpack.ShaderPack;
import net.irisshaders.iris.shaderpack.include.AbsolutePackPath;
import net.minecraft.block.Block;
import net.minecraft.block.BlockState;
import net.minecraft.block.Blocks;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.world.ClientWorld;
import net.minecraft.state.property.Property;
import net.minecraft.util.math.BlockPos;
import org.apache.commons.lang3.tuple.Pair;
import org.joml.Vector3f;

public class LightRegistry implements Destructable {
   // RTXDI ReGIR samplingJitter in grid-cell units. The shader applies it as
   // (rand - 0.5) * samplingJitter * cellSize and expands build radius by
   // samplingJitter + 1.0.
   private static final float REGIR_SAMPLING_JITTER = 1.0F;
   private static final float REGIR_LOOKUP_JITTER = 1.0F;
   private static final int RESIDENT_LIGHT_REMOVAL_CONFIRMATION_SCANS = 64;
   private static final int INCREMENTAL_PARALLEL_THRESHOLD = 32;
   private static final float POSITION_MATCH_EPSILON = 1.0e-4F;
   static final long CHUNK_LIGHT_HASH_OFFSET = 1469598103934665603L;
   static final long CHUNK_LIGHT_HASH_PRIME = 1099511628211L;
   private static final Comparator<LightInstance> STABLE_LIGHT_ORDER = (a, b) -> {
      Vector3f pa = a.position();
      Vector3f pb = b.position();
      int cmp = Float.compare(pa.x, pb.x);
      if (cmp != 0) return cmp;
      cmp = Float.compare(pa.y, pb.y);
      if (cmp != 0) return cmp;
      cmp = Float.compare(pa.z, pb.z);
      if (cmp != 0) return cmp;
      cmp = Integer.compare(a.blockId(), b.blockId());
      if (cmp != 0) return cmp;
      return a.type().compareTo(b.type());
   };

   private static float selectionSourceScore(LightInstance light) {
      return selectionSourceScore(light, null, 0.0F);
   }

   private static float selectionSourceScore(LightInstance light, Vector3f referencePosition, float minSelectionLuma) {
      if (!light.active()) {
         return 0.0F;
      }

      BlockLightInfo lightInfo = light.type();
      float basePower = Math.max(lightInfo.sourcePower(), 0.0F);
      if (referencePosition == null) {
         return basePower;
      }

      Vector3f lightPosition = light.position();
      float cameraLuma = Math.max(lightInfo.luminanceFrom(lightPosition, referencePosition), 0.0F);
      float radius = Math.max(lightInfo.radiusInBlocks(), 1.0F);
      float distanceSq = Math.max(lightPosition.distanceSquared(referencePosition), 0.0F);
      float radiusSq = radius * radius;
      float proximity = radiusSq / (distanceSq + radiusSq);
      float nearbyImportance = cameraLuma * (1.0F + 8.0F * proximity);
      if (nearbyImportance < minSelectionLuma) {
         nearbyImportance = 0.0F;
      }

      return Math.max(basePower * 0.02F, nearbyImportance);
   }

   private static boolean samePosition(Vector3f a, Vector3f b) {
      return a.distanceSquared(b) <= POSITION_MATCH_EPSILON;
   }

  private static int mixSemanticHash(int hash, int value) {
      return 31 * hash + value;
   }

   private static int mixSemanticHash(int hash, float value) {
      return mixSemanticHash(hash, Float.floatToIntBits(value));
   }

   static long mixChunkLightHash(long hash, long value) {
      return (hash ^ value) * CHUNK_LIGHT_HASH_PRIME;
   }

   static long semanticLightDescriptorHash(BlockLightInfo lightInfo) {
      if (lightInfo == null) {
         return 0L;
      }

      int hash = 1;
      hash = mixSemanticHash(hash, lightInfo.intensity());
      hash = mixSemanticHash(hash, lightInfo.radius());
      hash = mixSemanticHash(hash, lightInfo.falloff());
      hash = mixSemanticHash(hash, lightInfo.isTraced() ? 1 : 0);
      hash = mixSemanticHash(hash, lightInfo.requestedTrace() ? 1 : 0);
      Vector3f rawColor = lightInfo.getRawColorAsVector();
      hash = mixSemanticHash(hash, rawColor.x);
      hash = mixSemanticHash(hash, rawColor.y);
      hash = mixSemanticHash(hash, rawColor.z);
      Vector3f emissionAxis = lightInfo.emissionAxis();
      hash = mixSemanticHash(hash, emissionAxis.x);
      hash = mixSemanticHash(hash, emissionAxis.y);
      hash = mixSemanticHash(hash, emissionAxis.z);
      hash = mixSemanticHash(hash, lightInfo.orientationSpread());
      hash = mixSemanticHash(hash, lightInfo.emissionSpread());
      return Integer.toUnsignedLong(hash);
   }

   static long semanticLightTopologyHash(BlockLightInfo lightInfo) {
      if (lightInfo == null) {
         return 0L;
      }

      int hash = 1;
      hash = mixSemanticHash(hash, lightInfo.radius());
      hash = mixSemanticHash(hash, lightInfo.falloff());
      hash = mixSemanticHash(hash, lightInfo.isTraced() ? 1 : 0);
      hash = mixSemanticHash(hash, lightInfo.requestedTrace() ? 1 : 0);
      Vector3f emissionAxis = lightInfo.emissionAxis();
      hash = mixSemanticHash(hash, emissionAxis.x);
      hash = mixSemanticHash(hash, emissionAxis.y);
      hash = mixSemanticHash(hash, emissionAxis.z);
      hash = mixSemanticHash(hash, lightInfo.orientationSpread());
      hash = mixSemanticHash(hash, lightInfo.emissionSpread());
      return Integer.toUnsignedLong(hash);
   }

   private static boolean sameLightDescriptor(TracedLightPosition previous, int blockId, BlockLightInfo lightInfo) {
      return previous != null
         && previous.blockId() == blockId
         && previous.semanticHash() == semanticLightDescriptorHash(lightInfo)
         && sameLightDescriptor(previous.lightInfo(), lightInfo);
   }

   private static boolean sameLightDescriptor(BlockLightInfo a, BlockLightInfo b) {
      if (a == b) {
         return true;
      }
      if (a == null || b == null) {
         return false;
      }
      return Float.compare(a.intensity(), b.intensity()) == 0
         && Float.compare(a.radius(), b.radius()) == 0
         && Float.compare(a.falloff(), b.falloff()) == 0
         && a.isTraced() == b.isTraced()
         && a.requestedTrace() == b.requestedTrace()
         && a.getRawColorAsVector().equals(b.getRawColorAsVector())
         && a.emissionAxis().equals(b.emissionAxis())
         && Float.compare(a.orientationSpread(), b.orientationSpread()) == 0
         && Float.compare(a.emissionSpread(), b.emissionSpread()) == 0;
   }

   private static boolean sameLightTopologyDescriptor(BlockLightInfo a, BlockLightInfo b) {
      if (a == b) {
         return true;
      }
      if (a == null || b == null) {
         return false;
      }
      return Float.compare(a.radius(), b.radius()) == 0
         && Float.compare(a.falloff(), b.falloff()) == 0
         && a.isTraced() == b.isTraced()
         && a.requestedTrace() == b.requestedTrace()
         && a.emissionAxis().equals(b.emissionAxis())
         && Float.compare(a.orientationSpread(), b.orientationSpread()) == 0
         && Float.compare(a.emissionSpread(), b.emissionSpread()) == 0;
   }

   private static boolean sameSemanticLight(LightInstance before, LightInstance after) {
      return before != null
         && after != null
         && before.blockId() == after.blockId()
         && samePosition(before.position(), after.position())
         && sameLightTopologyDescriptor(before.type(), after.type());
   }

   private static LightInstance inactivePlaceholder(LightInstance light) {
      return new LightInstance(light.blockId(), new Vector3f(light.position()), light.type(), false);
   }

   private static int findSemanticMatch(LightInstance target, LightInstance[] candidates, boolean[] used) {
      for (int i = 0; i < candidates.length; i++) {
         if (!used[i] && sameSemanticLight(target, candidates[i])) {
            return i;
         }
      }
      return -1;
   }

   private static int findPositionMatch(Vector3f position, LightInstance[] candidates, boolean[] used) {
      for (int i = 0; i < candidates.length; i++) {
         if (!used[i] && samePosition(position, candidates[i].position())) {
            return i;
         }
      }
      return -1;
   }


   private static Vector3f getCurrentCameraPosition() {
      MinecraftClient client = MinecraftClient.getInstance();
      if (client == null || client.gameRenderer == null || client.gameRenderer.getCamera() == null) {
         return new Vector3f();
      }
      return new Vector3f(MinecraftAccessor.getCameraPosition());
   }

   private static final BlockPos[] NEIGHBORS = {
      new BlockPos(0, 1, 0), new BlockPos(0, -1, 0),
      new BlockPos(1, 0, 0), new BlockPos(-1, 0, 0),
      new BlockPos(0, 0, 1), new BlockPos(0, 0, -1)
   };

  private final LightStorageManager storage;
  private final RegirGridBuilder regir;
  private GlMemoryManager globalLightCdfMemoryManager;
  private MemoryOwner globalLightCdfMemory;
  private final int maxLights;
  private final float minTracedLightSelectionLuma;
  private int lightCapacity;
  private short[] newLightIndices;
  private PBlockPos offset = new PBlockPos(0, 0, 0);
  private int lightCount = 0;
  private LightInstance[] tracedLights = new LightInstance[0];
  private final LightTracingManager tracing = new LightTracingManager();
  private final LightActivityGate activityGate = new LightActivityGate();
  private final PhotonicsConfig.Observer<LightList> lightListObserver;
  private LightList lightList = new LightList();
  private final ReadWriteLock lock;
  private boolean building = false;
  private int compileCount = 0;
  private LightsProvider lightsProvider = null;
  private volatile boolean tracedLightSetDirty = true;
  private volatile boolean lightActivityDirty = false;
  private final Set<BlockPos> dirtyLightBlocks = ConcurrentHashMap.newKeySet();
  private final LightChurnStats churnStats = new LightChurnStats();
  private boolean identityLightMappingPending = false;
  // Stores the most recently resolved ReGIR build center.
  private final Vector3f frozenLightSelectionCamera = new Vector3f();
  private final Vector3f frozenRegirGridCenter = new Vector3f();
  private boolean frozenLightSelectionCameraInitialized = false;
  private boolean frozenRegirGridCenterInitialized = false;
  private final Vector3f lastGlobalLightCdfCamera = new Vector3f();
  private boolean lastGlobalLightCdfCameraInitialized = false;
  private boolean loggedAutomationLightColors = false;
  private int pendingTracedLightMutations = 0;
  private volatile boolean gpuRegirBuildEnabled = false;
  private float[] lightPowers = new float[0];
   private int mutationDebugLogsRemaining = 96;
   private int activityDebugLogsRemaining = 48;

   public LightRegistry(int maxLights, int maxLightsPerNode, float minTracedLightSelectionLuma, int nodeSize, int worldSize) {
     if (16 % nodeSize != 0) {
        throw new IllegalArgumentException();
     }

     this.maxLights = maxLights;
     this.minTracedLightSelectionLuma = Math.max(0.0F, minTracedLightSelectionLuma);
     this.lightCapacity = Math.max(1, maxLights);
     int regirLightsPerCell = resolveRegirLightsPerCell(maxLightsPerNode);
     int regirGridResolution = Math.max(1, worldSize / RegirGridBuilder.GRID_CELL_SIZE);
     this.newLightIndices = new short[this.lightCapacity];
     this.storage = new LightStorageManager(this.lightCapacity);
     this.regir = new RegirGridBuilder(regirGridResolution, regirLightsPerCell);
      this.globalLightCdfMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_global_light_cdf", this.lightCapacity * Float.BYTES, false);
      this.globalLightCdfMemory = new SimpleMemoryOwner(this.globalLightCdfMemoryManager, this.globalLightCdfMemoryManager.getCapacity());
      this.lightListObserver = PhotonicsConfig.observe(c -> PhotonicsConfig.getLightList(), c -> {
         this.lightList = c;
         this.registerLightBlocks(this.lightList);
         this.tracedLightSetDirty = true;
         MinecraftClient.getInstance().worldRenderer.reload();
      });
      this.lock = new ReentrantReadWriteLock();
   }

   private static int resolveRegirLightsPerCell(int maxLightsPerNode) {
      String override = System.getProperty("photonics.regirLightsPerCell");
      int defaultSlots = Math.max(
         RegirGridBuilder.REGIR_DEFAULT_LIGHTS_PER_CELL,
         maxLightsPerNode > 0 ? maxLightsPerNode : RegirGridBuilder.REGIR_MAX_LIGHTS_PER_CELL_FALLBACK
      );
      int configuredSlots = Math.round(PhotonicsStorage.REGIR_LIGHTS_PER_CELL.value);
      if (override != null && !override.isBlank()) {
         try {
            return Math.max(1, Integer.parseInt(override.trim()));
         } catch (NumberFormatException ignored) {
         }
      }

      return Math.max(1, configuredSlots > 0 ? configuredSlots : defaultSlots);
   }

   private boolean isLightSelectionCameraFrozenForDebug() {
      return Boolean.getBoolean("photonics.freezeLightSelectionCamera");
   }

   private boolean isRegirGridCenterFrozenForDebug() {
      return Boolean.getBoolean("photonics.freezeRegirGridCenter");
   }

   private Vector3f getTracedLightSelectionCameraPosition() {
      Vector3f cameraPosition = getCurrentCameraPosition();
      if (!this.isLightSelectionCameraFrozenForDebug()) {
         return cameraPosition;
      }

      if (!this.frozenLightSelectionCameraInitialized) {
         this.frozenLightSelectionCamera.set(cameraPosition);
         this.frozenLightSelectionCameraInitialized = true;
      }

      return new Vector3f(this.frozenLightSelectionCamera);
   }

   private boolean shouldRefreshGlobalLightCdf(Vector3f selectionCamera, boolean lightsChanged) {
      if (lightsChanged || this.tracedLights.length == 0) {
         return true;
      }

      if (this.gpuRegirBuildEnabled) {
         return true;
      }

      if (!this.lastGlobalLightCdfCameraInitialized) {
         return true;
      }

      float refreshDistance = Math.max(RegirGridBuilder.GRID_CELL_SIZE * 0.25F, 4.0F);
      return this.lastGlobalLightCdfCamera.distanceSquared(selectionCamera) >= refreshDistance * refreshDistance;
   }

   private void markGlobalLightCdfCamera(Vector3f selectionCamera) {
      this.lastGlobalLightCdfCamera.set(selectionCamera);
      this.lastGlobalLightCdfCameraInitialized = true;
   }

   private Vector3f resolveRegirGridCenter() {
      Vector3f cameraPosition = getCurrentCameraPosition();
      if (!this.isRegirGridCenterFrozenForDebug()) {
         return cameraPosition;
      }

      if (!this.frozenRegirGridCenterInitialized) {
         this.frozenRegirGridCenter.set(cameraPosition);
         this.frozenRegirGridCenterInitialized = true;
      }

      return new Vector3f(this.frozenRegirGridCenter);
   }

   static int regirHashCellCoord(float coordinate) {
      return (int) Math.floor(coordinate / RegirGridBuilder.REGIR_HASH_CELL_SIZE_BLOCKS);
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
      return this.tracing.tracedLightCount();
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
      boolean freezeMutationIngress = ShaderAutomation.suppressWorldMutationIngress();
      this.building = true;
      boolean profiling = PhotonicsStorage.PROFILER_ENABLED.value;
      long t0 = profiling ? System.nanoTime() : 0;
      long tGather = t0;
      long tDiff = t0;
      long tGrid = t0;
      long tStore = t0;
      int previousLightCount = this.tracedLights.length;
      boolean offsetChanged = !blockOffset.equals(previousOffset);
      try {
         this.offset = blockOffset;
         this.lock.writeLock().lock();
         LightInstance[] lights;
         try {
            if (!freezeMutationIngress && ++this.compileCount % 10 == 0) {
               this.compileCount = 0;
               lights = this.toLightInstanceArrayClearUnloaded(level);
            } else {
               lights = this.toLightInstanceArray();
            }
         } finally {
            this.lock.writeLock().unlock();
         }
         if (profiling) {
            tGather = System.nanoTime();
         }

         boolean lightsChanged = this.createTracedLights(lights);
         if (profiling) {
            tDiff = System.nanoTime();
         }
         boolean bufferOnlyChanged = this.churnStats.lastFrameBufferOnly();
         boolean topologyChanged = lightsChanged && !bufferOnlyChanged;
         boolean rebuildSpatialGrid = topologyChanged || this.regir.getLightGrid() == null;
         if (rebuildSpatialGrid) {
            this.buildSpatialGrid(this.tracedLights);
         }
         if (profiling) {
            tGrid = System.nanoTime();
         }

         boolean regirDirty = rebuildSpatialGrid || (!this.gpuRegirBuildEnabled && offsetChanged);
         if (regirDirty && !this.gpuRegirBuildEnabled) {
            this.buildRegirGrid();
         } else if (regirDirty) {
            this.updateRegirGridOriginOnly();
         }

         Vector3f selectionCamera = this.getTracedLightSelectionCameraPosition();
         boolean refreshGlobalLightCdf = this.shouldRefreshGlobalLightCdf(selectionCamera, lightsChanged);

         boolean identityQueued = false;
         if (topologyChanged) {
            this.storage.copyCurrentLightsToPrevious();
            this.storeLights();
            this.storeLightMappings();
            this.storeLightReverseMappings();
            this.storeGlobalLightCdf(selectionCamera);
            this.markGlobalLightCdfCamera(selectionCamera);
            this.storage.queueUploadLights();
            this.storage.queueUploadPreviousLights();
            this.storage.queueUploadLightMappings();
            this.storage.queueUploadLightReverseMappings();
            this.globalLightCdfMemoryManager.queueUpload(this.globalLightCdfMemory);
            this.identityLightMappingPending = true;
            this.lightActivityDirty = false;
         } else if (lightsChanged || bufferOnlyChanged) {
            this.storage.copyCurrentLightsToPrevious();
            this.storeLights();
            this.storeGlobalLightCdf(selectionCamera);
            this.markGlobalLightCdfCamera(selectionCamera);
            this.storage.queueUploadLights();
            this.storage.queueUploadPreviousLights();
            this.globalLightCdfMemoryManager.queueUpload(this.globalLightCdfMemory);
            this.lightActivityDirty = false;
         } else {
            if (refreshGlobalLightCdf) {
               this.storeGlobalLightCdf(selectionCamera);
               this.markGlobalLightCdfCamera(selectionCamera);
               this.globalLightCdfMemoryManager.queueUpload(this.globalLightCdfMemory);
            }
            identityQueued = this.queueIdentityLightMappingsIfNeeded();
         }
         if (regirDirty && !this.gpuRegirBuildEnabled) {
            this.regir.queueUpload();
         }
         if (profiling) {
            tStore = System.nanoTime();
            String rebuildReason;
            if (offsetChanged) {
               rebuildReason = "offset";
            } else if (topologyChanged) {
               rebuildReason = "lights";
            } else if (lightsChanged || bufferOnlyChanged) {
               rebuildReason = "activity";
            } else {
               rebuildReason = "unknown";
            }
            long totalMs = (tStore - t0) / 1_000_000L;
            long gatherMs = (tGather - t0) / 1_000_000L;
            long diffMs = (tDiff - tGather) / 1_000_000L;
            long gridMs = (tGrid - tDiff) / 1_000_000L;
            long storeMs = (tStore - tGrid) / 1_000_000L;
            Photonic.info(
               "[Profiler] lightRegistry: reason={} prevLights={} gatheredLights={} tracedLights={} changed={} offsetChanged={} gridCells={} gridAssignments={} churn={} uploads(lights={},mapping={},regir={},identity={}) timings: gather={}ms diff={}ms grid={}ms store={}ms total={}ms",
               rebuildReason,
               previousLightCount,
               lights.length,
               this.tracedLights.length,
               lightsChanged,
               offsetChanged,
               this.regir.getLightGrid() == null ? 0 : this.regir.getLightGrid().size(),
               this.regir.lightGridAssignments,
               this.describeRecentChurn(),
               lightsChanged || bufferOnlyChanged,
               topologyChanged,
               regirDirty,
               identityQueued,
               gatherMs,
               diffMs,
               gridMs,
               storeMs,
               totalMs
            );
            if (topologyChanged) {
               Photonic.info(
                  "[Profiler] regirBuild: lights={} activeCells={} lightSlots={} gridResolution={}x{}x{} cellSize={} compileCount={} churn={}",
                  this.tracedLights.length,
                  this.regir.getActiveCellCount(),
                  this.regir.getActiveLightSlotCount(),
                  this.regir.getGridResolution(),
                  this.regir.getGridResolution(),
                  this.regir.getGridResolution(),
                  RegirGridBuilder.GRID_CELL_SIZE,
                  this.compileCount,
                  this.describeRecentChurn()
               );
            }
         }
      } finally {
         this.building = false;
      }
   }

   private void storeLights() {
      if (this.storage.storeLights(this.tracedLights, this.compileCount, this.loggedAutomationLightColors)) {
         this.loggedAutomationLightColors = true;
      }
   }

   private void storeLightMappings() {
      this.storage.storeLightMappings(this.newLightIndices, this.getLightCapacity());
   }

   private void storeLightReverseMappings() {
      this.storage.storeLightReverseMappings(this.newLightIndices, this.getLightCapacity());
   }

   private void storeGlobalLightCdf(Vector3f selectionCamera) {
      FloatBuffer buffer = this.globalLightCdfMemory.getMemory().getBuffer().asFloatBuffer();
      int tracedCount = this.tracedLights.length;
      int capacity = this.getLightCapacity();
      this.lightPowers = new float[tracedCount];
      float[] regirLightPowers = new float[tracedCount];
      float cumulativeWeight = 0.0F;
      boolean hasPositiveWeight = false;
      boolean hasPositiveRegirWeight = false;
      int activeLightCount = 0;
      for (int i = 0; i < capacity; i++) {
         if (i < tracedCount) {
            LightInstance light = this.tracedLights[i];
            float weight = Math.max(selectionSourceScore(light, selectionCamera, this.minTracedLightSelectionLuma), 0.0F);
            float regirWeight = Math.max(selectionSourceScore(light), 0.0F);
            if (weight > 1.0e-6F) {
               cumulativeWeight += weight;
               hasPositiveWeight = true;
            }
            if (regirWeight > 1.0e-6F) {
               hasPositiveRegirWeight = true;
            }
            if (light.active()) {
               activeLightCount++;
            }
            this.lightPowers[i] = weight;
            regirLightPowers[i] = regirWeight;
         }
         buffer.put(i, cumulativeWeight);
      }

      if (!hasPositiveRegirWeight && tracedCount > 0 && activeLightCount > 0) {
         for (int i = 0; i < tracedCount; i++) {
            regirLightPowers[i] = this.tracedLights[i].active() ? 1.0F : 0.0F;
         }
      }

      this.regir.setRegirLightPowers(regirLightPowers);

      if (hasPositiveWeight || tracedCount <= 0 || activeLightCount <= 0) {
         return;
      }

      // Fallback: uniform weights when all active source scores are zero.
      cumulativeWeight = 0.0F;
      for (int i = 0; i < capacity; i++) {
         if (i < tracedCount) {
            if (this.tracedLights[i].active()) {
               cumulativeWeight += 1.0F;
               this.lightPowers[i] = 1.0F;
            } else {
               this.lightPowers[i] = 0.0F;
            }
         }
         buffer.put(i, cumulativeWeight);
      }
   }

   private void storeIdentityLightMappings() {
      this.storage.storeIdentityLightMappings(this.getLightCapacity());
   }

   private void updateRegirGridOriginOnly() {
      Vector3f gridCenter = this.resolveRegirGridCenter();
      this.regir.updateRegirGridOriginOnly(this.tracedLights, gridCenter, this.getRegirBuildCellRadius());
   }

   private void buildRegirGrid() {
      Vector3f gridCenter = this.resolveRegirGridCenter();
      this.regir.buildRegirGrid(this.tracedLights, gridCenter, this.getRegirBuildCellRadius());
   }


   boolean queueIdentityLightMappingsIfNeeded() {
      if (!this.identityLightMappingPending) {
         return false;
      }
      this.storage.copyCurrentLightsToPrevious();
      this.storeIdentityLightMappings();
      this.storage.queueUploadPreviousLights();
      this.storage.queueUploadLightMappings();
      this.storage.queueUploadLightReverseMappings();
      this.identityLightMappingPending = false;
      return true;
   }

   private boolean createTracedLights(LightInstance[] gatheredLights) {
      LightInstance[] sortedLights = Arrays.copyOf(gatheredLights, gatheredLights.length);
      Arrays.sort(sortedLights, STABLE_LIGHT_ORDER);
      this.ensureLightCapacity(Math.max(sortedLights.length, this.tracedLights.length) + Math.min(sortedLights.length, this.tracedLights.length));
      Arrays.fill(this.newLightIndices, (short) -1);
      LightInstance[] prevLights = this.tracedLights;
      LightChurnStats.Frame frameStats = this.churnStats.beginFrame(prevLights.length, sortedLights.length);
      boolean[] matchedCurrent = new boolean[sortedLights.length];
      LightInstance[] nextLights = new LightInstance[sortedLights.length];
      int nextSize = 0;
      boolean anyDirty = false;

      for (int previousIndex = 0; previousIndex < prevLights.length; previousIndex++) {
         LightInstance previous = prevLights[previousIndex];
         int semanticMatchIndex = findSemanticMatch(previous, sortedLights, matchedCurrent);
         if (semanticMatchIndex >= 0) {
            LightInstance current = sortedLights[semanticMatchIndex];
            matchedCurrent[semanticMatchIndex] = true;
            current.setIndex(nextSize);
            nextLights = ensureNextLightCapacity(nextLights, nextSize + 1);
            nextLights[nextSize] = current;
            this.newLightIndices[previousIndex] = (short) nextSize;
            if (previousIndex == nextSize && previous.active() == current.active() && sameLightDescriptor(previous.type(), current.type())) {
               frameStats.stableMappings++;
            } else {
               anyDirty = true;
               if (previous.active() != current.active()) {
                  frameStats.activityChanges++;
                  this.logActivityTransition("semantic", previous, current);
               } else if (!sameLightDescriptor(previous.type(), current.type())) {
                  frameStats.radiometryChanges++;
               }
            }
            nextSize++;
            continue;
         }

         int positionMatchIndex = findPositionMatch(previous.position(), sortedLights, matchedCurrent);
         if (positionMatchIndex >= 0) {
            LightInstance current = sortedLights[positionMatchIndex];
            matchedCurrent[positionMatchIndex] = true;
            current.setIndex(nextSize);
            nextLights = ensureNextLightCapacity(nextLights, nextSize + 1);
            nextLights[nextSize] = current;
            this.newLightIndices[previousIndex] = (short) nextSize;
            anyDirty = true;
            if (previous.blockId() != current.blockId()) {
               frameStats.blockIdChanges++;
            } else if (previous.active() != current.active()) {
               frameStats.activityChanges++;
               this.logActivityTransition("position", previous, current);
            } else if (sameLightTopologyDescriptor(previous.type(), current.type())) {
               frameStats.radiometryChanges++;
            } else {
               frameStats.lightInfoChanges++;
            }
            nextSize++;
            continue;
         }

         if (this.shouldRetainInactivePlaceholder(previous)) {
            LightInstance inactive = previous.active() ? inactivePlaceholder(previous) : previous;
            inactive.setIndex(nextSize);
            nextLights = ensureNextLightCapacity(nextLights, nextSize + 1);
            nextLights[nextSize] = inactive;
            this.newLightIndices[previousIndex] = (short) nextSize;
            if (previous.active()) {
               frameStats.activityChanges++;
               this.logActivityTransition("placeholder", previous, inactive);
               anyDirty = true;
            } else if (previousIndex == nextSize) {
               frameStats.stableMappings++;
            }
            nextSize++;
            continue;
         }

         frameStats.removals++;
         anyDirty = true;
      }

      for (int i = 0; i < sortedLights.length; i++) {
         if (matchedCurrent[i]) {
            continue;
         }
         LightInstance current = sortedLights[i];
         current.setIndex(nextSize);
         nextLights = ensureNextLightCapacity(nextLights, nextSize + 1);
         nextLights[nextSize] = current;
         nextSize++;
         frameStats.additions++;
         anyDirty = true;
      }

      LightInstance[] remappedLights = Arrays.copyOf(nextLights, nextSize);
      for (int i = 0; i < remappedLights.length; i++) {
         remappedLights[i].setIndex(i);
      }

      this.tracedLights = remappedLights;
      int remappedMutationCount = anyDirty
         ? frameStats.additions + frameStats.removals + frameStats.blockIdChanges + frameStats.lightInfoChanges + frameStats.radiometryChanges + frameStats.activityChanges
         : 0;
      this.pendingTracedLightMutations = Math.max(this.pendingTracedLightMutations, remappedMutationCount);
      return anyDirty;
   }

   private boolean shouldRetainInactivePlaceholder(LightInstance light) {
      Vector3f pos = light.position();
      BlockPos blockPos = new BlockPos((int) pos.x, (int) pos.y, (int) pos.z);
      return this.isTrackedChunkLoaded(blockPos);
   }

   private static LightInstance[] ensureNextLightCapacity(LightInstance[] lights, int requiredSize) {
      if (requiredSize <= lights.length) {
         return lights;
      }
      return Arrays.copyOf(lights, Math.max(requiredSize, lights.length + Math.max(1, lights.length / 2)));
   }

   private void logActivityTransition(String matchType, LightInstance previous, LightInstance current) {
      if (!PhotonicsStorage.PROFILER_ENABLED.value || !Photonic.automationEnabled() || this.activityDebugLogsRemaining <= 0) {
         return;
      }

      this.activityDebugLogsRemaining--;
      Vector3f pos = current.position();
      Photonic.info(
         "[Profiler] lightActivity: match={} pos=({},{},{}) blockId={}->{} active={}->{} descriptorSame={}",
         matchType,
         (int) pos.x,
         (int) pos.y,
         (int) pos.z,
         previous.blockId(),
         current.blockId(),
         previous.active(),
         current.active(),
         sameSemanticLight(previous, current)
      );
   }

   public GlMemoryManager getNeighborOffsetMemoryManager() {
      return this.storage.getNeighborOffsetMemoryManager();
   }

   public boolean upload() {
      boolean uploadDone = this.storage.upload();
      uploadDone &= this.regir.upload(this.gpuRegirBuildEnabled);
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

   public boolean hasPossibleLight(Block block) {
      return this.lightList.keySet().contains(block);
   }

   public boolean hasPossibleLight(BlockState blockState) {
      return this.hasPossibleLight(blockState.getBlock());
   }

   public boolean hasPossibleTracedLight(BlockState blockState) {
      return blockState != null && this.lightList.getAnyTraced(blockState.getBlock()) != null;
   }

   public BlockState canonicalizeTracedLightBlockState(BlockState blockState) {
      if (!this.hasPossibleTracedLight(blockState)) {
         return blockState;
      }

      return this.canonicalizeDynamicLightBlockState(blockState);
   }

   public BlockState canonicalizeLightBlockState(BlockState blockState) {
      if (!this.hasPossibleLight(blockState)) {
         return blockState;
      }

      return this.canonicalizeDynamicLightBlockState(blockState);
   }

   private BlockState canonicalizeDynamicLightBlockState(BlockState blockState) {
      BlockState canonicalState = blockState;
      for (Property<?> property : blockState.getEntries().keySet()) {
         if (BlockStateCanonicalizer.isLightActivityProperty(property)) {
            canonicalState = BlockStateCanonicalizer.withBooleanProperty(canonicalState, property, true);
         } else if ("power".equals(property.getName())) {
            canonicalState = BlockStateCanonicalizer.withIntegerProperty(canonicalState, property, true);
         }
      }
      return canonicalState;
   }

   private int stableTracedLightBlockId(BlockState blockState) {
      return IrisUtil.getBlockId(this.canonicalizeTracedLightBlockState(blockState));
   }

   private BlockLightInfo fallbackTrackedLightInfo(BlockState blockState) {
      if (blockState == null) {
         return null;
      }

      BlockLightInfo lightInfo = this.lightList.getAnyTraced(blockState.getBlock());
      return lightInfo != null && lightInfo.requestedTrace() ? lightInfo : null;
   }

   public boolean hasTrackedLight(BlockPos blockPos) {
      if (blockPos == null) {
         return false;
      }
      Vector3f lightPos = new Vector3f(blockPos.getX() + 0.5F, blockPos.getY() + 0.5F, blockPos.getZ() + 0.5F);
      return this.tracing.tracedLightPositions.containsKey(lightPos);
   }

   public void onBlockLoad(Vector3f position) {
      if (ShaderAutomation.suppressWorldMutationIngress()) {
         return;
      }
      this.lock.writeLock().lock();
      try {
         ClientWorld level = MinecraftAccessor.getLevel();
         if (level == null) {
            return;
         }
         BlockPos blockPos = new BlockPos((int) position.x, (int) position.y, (int) position.z);
         this.tracing.chunkLightHashes.remove(chunkKey(blockPos));
         this.syncTracedLight(level, blockPos, level.getBlockState(blockPos), true, SyncSource.BLOCK_LOAD);
      } finally {
         this.lock.writeLock().unlock();
      }
   }

   public BlockLightInfo resolveLightInfo(BlockPos blockPos, BlockState blockState, ClientWorld level) {
      if (level != null && level.isChunkLoaded(blockPos)) {
         return this.lightList.get(blockPos, level);
      }
      return this.lightList.get(blockState);
   }

   public void onBlockUpdate(BlockPos blockPos) {
      if (ShaderAutomation.suppressWorldMutationIngress()) {
         return;
      }
      this.lock.writeLock().lock();
      try {
         ClientWorld level = MinecraftAccessor.getLevel();
         if (level == null) {
            return;
         }
         this.tracing.chunkLightHashes.remove(chunkKey(blockPos));
         // A client block update carries the new block state now. Do not apply
         // the resident-chunk missing-light grace window here, or removed light
         // blocks keep contributing until a later full chunk scan happens.
         this.syncTracedLight(level, blockPos, level.getBlockState(blockPos), false, SyncSource.BLOCK_UPDATE_LIVE);
      } finally {
         this.lock.writeLock().unlock();
      }
   }

   public void onBlockUpdate(BlockPos blockPos, BlockState blockState, BlockLightInfo lightInfo) {
      if (ShaderAutomation.suppressWorldMutationIngress()) {
         return;
      }
      this.lock.writeLock().lock();
      try {
         this.tracing.chunkLightHashes.remove(chunkKey(blockPos));
         // Same as the live lookup overload: this snapshot is an authoritative
         // block update, not a speculative resident chunk rescan. Re-resolve
         // from the live world state at apply time when possible — captured
         // snapshots can be stale if the chunk briefly unloaded between queue
         // and flush, which would otherwise flip activity between null and
         // the lit info on every replay.
         ClientWorld level = MinecraftAccessor.getLevel();
         if (level != null && level.isChunkLoaded(blockPos)) {
            this.syncTracedLight(level, blockPos, level.getBlockState(blockPos), false, SyncSource.BLOCK_UPDATE_SNAPSHOT);
         } else {
            this.syncTracedLight(blockPos, blockState, lightInfo, false, SyncSource.BLOCK_UPDATE_SNAPSHOT);
         }
      } finally {
         this.lock.writeLock().unlock();
      }
   }

   public void synchronizeChunkLights(ClientWorld level, PChunkPos chunkPos) {
      this.lock.writeLock().lock();
      try {
         this.tracing.synchronizeChunkLights(
            level,
            chunkPos,
            this::resolveLightInfo,
            (blockPos, blockState) -> this.syncTracedLight(level, blockPos, blockState, true, SyncSource.CHUNK_SYNC),
            this.churnStats::noteNoopSync
         );
      } finally {
         this.lock.writeLock().unlock();
      }
   }

   public void clearChunkLights(PChunkPos chunkPos) {
      this.lock.writeLock().lock();
      try {
         boolean removed = this.tracing.clearChunkLights(chunkPos);
         if (removed) {
            this.tracedLightSetDirty = true;
            this.pendingTracedLightMutations++;
         }
      } finally {
         this.lock.writeLock().unlock();
      }
   }

   public boolean consumeTracedLightSetDirty() {
      boolean dirty = this.tracedLightSetDirty;
      this.tracedLightSetDirty = false;
      return dirty;
   }

   public boolean consumeLightActivityDirty() {
      boolean dirty = this.lightActivityDirty;
      this.lightActivityDirty = false;
      return dirty;
   }

   public int consumePendingTracedLightMutations() {
      int pending = this.pendingTracedLightMutations;
      this.pendingTracedLightMutations = 0;
      return pending;
   }

   public List<BlockPos> consumeDirtyLightBlocks() {
      if (this.dirtyLightBlocks.isEmpty()) {
         return List.of();
      }
      List<BlockPos> blocks = new ArrayList<>(this.dirtyLightBlocks);
      this.dirtyLightBlocks.removeAll(blocks);
      return blocks;
   }

   public GlMemoryManager getLightsMemoryManager() {
      return this.storage.getLightsMemoryManager();
   }

   public GlMemoryManager getPreviousLightsMemoryManager() {
      return this.storage.getPreviousLightsMemoryManager();
   }

   public GlMemoryManager getLightMappingMemoryManager() {
      return this.storage.getLightMappingMemoryManager();
   }

   public GlMemoryManager getLightReverseMappingMemoryManager() {
      return this.storage.getLightReverseMappingMemoryManager();
   }

   public GlMemoryManager getRegirCellCountMemoryManager() {
      return this.regir.getCellCountMemoryManager();
   }

   public GlMemoryManager getGlobalLightCdfMemoryManager() {
      return this.globalLightCdfMemoryManager;
   }

   public GlMemoryManager getRegirLightIndexMemoryManager() {
      return this.regir.getLightIndexMemoryManager();
   }

   public GlMemoryManager getRegirLightPdfMemoryManager() {
      return this.regir.getLightPdfMemoryManager();
   }

   public GlMemoryManager getRegirCompactLightDataMemoryManager() {
      return this.regir.getCompactLightDataMemoryManager();
   }

   public GlMemoryManager getRegirHashChecksumMemoryManager() {
      return this.regir.getHashChecksumMemoryManager();
   }

   public GlMemoryManager getRegirHashKeyMemoryManager() {
      return this.regir.getHashKeyMemoryManager();
   }

   public int getRegirHashTableSize() {
      return this.regir.getHashTableSize();
   }

   public int getRegirHashNormalBuckets() {
      return this.regir.getHashNormalBuckets();
   }

   public float getRegirHashCellSizeBlocks() {
      return this.regir.getHashCellSizeBlocks();
   }

   public int getRegirBuildRegionCells() {
      return this.regir.getBuildRegionCells();
   }

   /** Returns the world-space center of the ReGIR grid. */
   public Vector3f getRegirGridCenter() {
      Vector3f center = this.resolveRegirGridCenter();
      this.regir.setGridCenter(center);
      return new Vector3f(center);
   }

   /** @deprecated Use {@link #getRegirGridCenter()} — kept for backward compatibility. */
   @Deprecated
   public Vector3f getRegirGridOrigin() {
      // Derive origin from center for callers that still need it.
      float halfExtent = this.regir.getGridResolution() * RegirGridBuilder.GRID_CELL_SIZE * 0.5f;
      Vector3f center = this.getRegirGridCenter();
      return new Vector3f(
         center.x - halfExtent,
         center.y - halfExtent,
         center.z - halfExtent
      );
   }

   public int getRegirGridResolution() {
      return this.regir.getGridResolution();
   }

   public int getRegirLightsPerCell() {
      return this.regir.getLightsPerCell();
   }

   public float getRegirSamplingJitter() {
      String override = System.getProperty("photonics.regirSamplingJitter");
      float jitterInCells = PhotonicsStorage.REGIR_BUILD_JITTER.value;
      if (override != null && !override.isBlank()) {
         try {
            jitterInCells = Float.parseFloat(override.trim());
         } catch (NumberFormatException ignored) {
         }
      }

      return Math.max(0.0F, jitterInCells);
   }

   public float getRegirLookupJitter() {
      String override = System.getProperty("photonics.regirLookupJitter");
      if (override == null || override.isBlank()) {
         override = System.getProperty("photonics.regirSamplingJitter");
      }
      float jitterInCells = PhotonicsStorage.REGIR_LOOKUP_JITTER.value;
      if (override != null && !override.isBlank()) {
         try {
            jitterInCells = Float.parseFloat(override.trim());
         } catch (NumberFormatException ignored) {
         }
      }

      return Math.max(0.0F, jitterInCells);
   }

   private float getRegirBuildCellRadius() {
      return RegirGridBuilder.REGIR_CELL_RADIUS * (this.getRegirSamplingJitter() + 1.0F);
   }

   public int getRegirActiveCellCount() {
      return this.regir.getActiveCellCount();
   }

   public int getRegirActiveLightSlotCount() {
      return this.regir.getActiveLightSlotCount();
   }

   public void setGpuRegirBuildEnabled(boolean enabled) {
      this.gpuRegirBuildEnabled = enabled;
   }

   public boolean isGpuRegirBuildEnabled() {
      return this.gpuRegirBuildEnabled;
   }

   public float[] getLightPowers() {
      return this.lightPowers;
   }

   public float[] getRegirLightPowers() {
      return this.regir.getRegirLightPowers();
   }

   public long getSemanticLayoutHash() {
      long hash = 1469598103934665603L;
      if (!this.gpuRegirBuildEnabled) {
         hash = hash * 1099511628211L + this.regir.getActiveCellCount();
         hash = hash * 1099511628211L + this.regir.getActiveLightSlotCount();
      }
      for (LightInstance light : this.tracedLights) {
         hash = hash * 1099511628211L + Integer.toUnsignedLong(light.blockId());
         hash = hash * 1099511628211L + Float.floatToIntBits(light.position().x);
         hash = hash * 1099511628211L + Float.floatToIntBits(light.position().y);
         hash = hash * 1099511628211L + Float.floatToIntBits(light.position().z);
         hash = hash * 1099511628211L + semanticLightTopologyHash(light.type());
      }
      return hash;
   }

   private LightInstance[] toLightInstanceArray() {
      List<LightInstance> lights = new ArrayList<>(this.tracing.tracedLightPositions.size());
      for (Entry<Vector3f, TracedLightPosition> e : this.tracing.tracedLightPositions.entrySet()) {
         lights.add(new LightInstance(e.getValue().blockId(), e.getKey(), e.getValue().lightInfo(), e.getValue().active()));
      }
      lights.sort(STABLE_LIGHT_ORDER);
      return lights.toArray(LightInstance[]::new);
   }

   private LightInstance[] toLightInstanceArrayClearUnloaded(ClientWorld level) {
      List<LightInstance> lights = new ArrayList<>(this.tracing.tracedLightPositions.size());
      Iterator<Entry<Vector3f, TracedLightPosition>> itr = this.tracing.tracedLightPositions.entrySet().iterator();
      while (itr.hasNext()) {
         Entry<Vector3f, TracedLightPosition> e = itr.next();
         Vector3f pos = e.getKey();
         TracedLightPosition tracedPos = e.getValue();
         BlockPos blockPos = new BlockPos((int) pos.x, (int) pos.y, (int) pos.z);
         // WorldRegistry.clearChunkLights already removes lights when an RT-owned chunk is
         // evicted. Do not also purge lights on transient ClientWorld chunk-read gaps here,
         // or the traced-light set churns while the same RT chunk is still resident.
         if (!this.isTrackedChunkLoaded(blockPos)) {
            itr.remove();
            this.tracedLightSetDirty = true;
            this.pendingTracedLightMutations++;
         } else {
            lights.add(new LightInstance(tracedPos.blockId(), pos, tracedPos.lightInfo(), tracedPos.active()));
         }
      }
      lights.sort(STABLE_LIGHT_ORDER);
      return lights.toArray(LightInstance[]::new);
   }

   @Override
   public void free() {
      this.storage.free();
      this.globalLightCdfMemoryManager.free();
      this.regir.free();
      this.lightListObserver.unregister();
      if (this.lightsProvider != null) {
         PhotonicsConfig.removeLightProvider(this.lightsProvider);
      }
   }

   private int getLightCapacity() {
      return this.newLightIndices.length;
   }

   private void ensureLightCapacity(int requiredLights) {
      int requiredCapacity = Math.max(1, requiredLights);
      if (requiredCapacity <= this.getLightCapacity()) {
         return;
      }

      int newCapacity = this.getLightCapacity();
      while (newCapacity < requiredCapacity) {
         newCapacity = Math.max(newCapacity << 1, requiredCapacity);
      }

      this.resizeLightStorage(newCapacity);
   }

   private void resizeLightStorage(int newCapacity) {
      int previousCapacity = this.getLightCapacity();
      this.storage.resize(newCapacity);
      this.globalLightCdfMemoryManager = LightStorageManager.replaceManager(this.globalLightCdfMemoryManager, "ph_global_light_cdf", newCapacity * Float.BYTES, false, this.globalLightCdfMemory, false, owner -> this.globalLightCdfMemory = owner);
      this.newLightIndices = Arrays.copyOf(this.newLightIndices, newCapacity);
      this.lightCapacity = newCapacity;
      this.identityLightMappingPending = true;
      this.tracedLightSetDirty = true;
      Photonic.info("[LightRegistry] Resized traced-light capacity from {} to {}", previousCapacity, newCapacity);
   }

   private void syncTracedLight(ClientWorld level, BlockPos blockPos, BlockState blockState, boolean deferMissingResidentLight, SyncSource source) {
      if (!level.isChunkLoaded(blockPos)) {
         return;
      }

      BlockLightInfo lightInfo = this.resolveLightInfo(blockPos, blockState, level);
      this.syncTracedLight(blockPos, blockState, lightInfo, deferMissingResidentLight, source);
   }

   private void syncTracedLight(BlockPos blockPos, BlockState blockState, BlockLightInfo lightInfo, boolean deferMissingResidentLight, SyncSource source) {
      Vector3f lightPos = new Vector3f(blockPos.getX() + 0.5F, blockPos.getY() + 0.5F, blockPos.getZ() + 0.5F);
      TracedLightPosition previous = this.tracing.tracedLightPositions.get(lightPos);
      if (lightInfo == null) {
         BlockLightInfo fallbackLightInfo = this.fallbackTrackedLightInfo(blockState);
         if (previous != null && fallbackLightInfo != null) {
            int blockId = previous.blockId() >= 0 ? previous.blockId() : this.stableTracedLightBlockId(blockState);
            TracedLightPosition inactive = new TracedLightPosition(blockId, previous.lightInfo(), false);
            if (!sameLightDescriptor(previous, blockId, previous.lightInfo())) {
               inactive = new TracedLightPosition(blockId, fallbackLightInfo, false);
            }
            this.updateTracedLightActivity(source, blockPos, blockState, previous, inactive);
            return;
         }
         if (previous == null && fallbackLightInfo != null && fallbackLightInfo.isTraced()) {
            int blockId = this.stableTracedLightBlockId(blockState);
            TracedLightPosition inactive = new TracedLightPosition(blockId, fallbackLightInfo, false);
            TracedLightPosition raced = this.tracing.tracedLightPositions.putIfAbsent(lightPos, inactive);
            if (raced == null) {
               this.logLightMutation(source, DirtyReason.ADDED, blockPos, blockState, null, inactive);
               this.noteTracedLightMutation(source, DirtyReason.ADDED, blockPos, null, inactive);
               return;
            }
            this.updateTracedLightActivity(source, blockPos, blockState, raced, inactive);
            return;
         }
         if (previous != null && deferMissingResidentLight && this.isTrackedChunkLoaded(blockPos)) {
            int missingScans = this.tracing.residentMissingLightScans.merge(lightPos, 1, Integer::sum);
            if (missingScans < RESIDENT_LIGHT_REMOVAL_CONFIRMATION_SCANS) {
               this.churnStats.noteNoopSync();
               return;
            }
         }
         if (previous != null && this.isTrackedChunkLoaded(blockPos) && this.tracing.tracedLightPositions.remove(lightPos, previous)) {
            this.tracing.residentMissingLightScans.remove(lightPos);
            this.logLightMutation(source, DirtyReason.REMOVED_NO_LIGHT, blockPos, blockState, previous, null);
            this.noteTracedLightMutation(source, DirtyReason.REMOVED_NO_LIGHT, blockPos, previous, null);
         }
         return;
      }
      this.tracing.residentMissingLightScans.remove(lightPos);

      // Keep traced-light activity stable. RTXDI and the original local implementation do
      // not toggle emitters active/inactive based on enclosure culling, and doing so here
      // churns the light buffer and ReGIR state during pure camera motion.
      boolean tracedVisible = lightInfo.isTraced();
      if (!tracedVisible) {
         if (previous != null && this.isTrackedChunkLoaded(blockPos)) {
            int missingScans = this.tracing.tracedVisibilityMissScans.merge(lightPos, 1, Integer::sum);
            if (missingScans < RESIDENT_LIGHT_REMOVAL_CONFIRMATION_SCANS) {
               this.churnStats.noteNoopSync();
               return;
            }
         }
         if (previous != null && this.tracing.tracedLightPositions.remove(lightPos, previous)) {
            this.tracing.residentMissingLightScans.remove(lightPos);
            this.tracing.tracedVisibilityMissScans.remove(lightPos);
            DirtyReason reason = lightInfo.isTraced() ? DirtyReason.CULLED : DirtyReason.REMOVED_NO_LIGHT;
            this.logLightMutation(source, reason, blockPos, blockState, previous, null);
            this.noteTracedLightMutation(source, reason, blockPos, previous, null);
         }
         return;
      }
      this.tracing.tracedVisibilityMissScans.remove(lightPos);

      int blockId = this.stableTracedLightBlockId(blockState);
      TracedLightPosition updated = new TracedLightPosition(blockId, lightInfo, true);
      if (previous == null) {
         TracedLightPosition raced = this.tracing.tracedLightPositions.putIfAbsent(lightPos, updated);
         if (raced == null) {
            this.logLightMutation(source, DirtyReason.ADDED, blockPos, blockState, null, updated);
            this.noteTracedLightMutation(source, DirtyReason.ADDED, blockPos, null, updated);
            return;
         }
         previous = raced;
      }

      if (sameLightDescriptor(previous, blockId, lightInfo)) {
         if (previous.active() != updated.active()) {
            this.updateTracedLightActivity(source, blockPos, blockState, previous, updated);
         } else {
            this.activityGate.cancelPending(lightPos);
            this.churnStats.noteNoopSync();
         }
         return;
      }

      if (this.tracing.tracedLightPositions.replace(lightPos, previous, updated)) {
         DirtyReason reason = previous.blockId() != blockId ? DirtyReason.BLOCK_ID_CHANGED : DirtyReason.LIGHT_INFO_CHANGED;
         this.logLightMutation(source, reason, blockPos, blockState, previous, updated);
         if (reason == DirtyReason.BLOCK_ID_CHANGED && sameLightDescriptor(previous.lightInfo(), updated.lightInfo())
            || sameLightTopologyDescriptor(previous.lightInfo(), updated.lightInfo())) {
            this.noteTracedLightBufferMutation(source, reason, blockPos, previous, updated);
         } else {
            this.noteTracedLightMutation(source, reason, blockPos, previous, updated);
         }
      }
   }

   private void updateTracedLightActivity(
      SyncSource source,
      BlockPos blockPos,
      BlockState blockState,
      TracedLightPosition previous,
      TracedLightPosition updated
   ) {
      if (previous == null || updated == null) {
         return;
      }
      if (previous.active() == updated.active() && sameLightDescriptor(previous, updated.blockId(), updated.lightInfo())) {
         this.churnStats.noteNoopSync();
         return;
      }

      Vector3f lightPos = new Vector3f(blockPos.getX() + 0.5F, blockPos.getY() + 0.5F, blockPos.getZ() + 0.5F);
      // Authoritative block updates carry a real state transition (e.g. redstone
      // lamp lit=true -> lit=false). The confirmation-scan gate exists to debounce
      // enclosure-culling churn during camera motion, not real state changes —
      // applying it here leaves the toggled lamp active until 32 chunk re-syncs
      // accumulate, which never happens once the chunk light hash stabilises.
      if (!isAuthoritativeBlockUpdate(source) && !this.activityGate.shouldApplyConfirmedActivityChange(lightPos, updated)) {
         this.churnStats.noteNoopSync();
         return;
      }
      if (this.tracing.tracedLightPositions.replace(lightPos, previous, updated)) {
         this.activityGate.cancelPending(lightPos);
         this.logLightActivityMutation(source, blockPos, blockState, previous, updated);
         this.noteTracedLightActivityMutation(source, blockPos, previous, updated);
      }
   }

   private static boolean isAuthoritativeBlockUpdate(SyncSource source) {
      return source == SyncSource.BLOCK_UPDATE_LIVE || source == SyncSource.BLOCK_UPDATE_SNAPSHOT;
   }

   private void logLightMutation(SyncSource source, DirtyReason reason, BlockPos blockPos, BlockState blockState, TracedLightPosition previous, TracedLightPosition updated) {
      if (!PhotonicsStorage.PROFILER_ENABLED.value || !Photonic.automationEnabled() || this.mutationDebugLogsRemaining <= 0) {
         return;
      }

      this.mutationDebugLogsRemaining--;
      Photonic.info(
         "[Profiler] lightMutation: source={} reason={} pos=({}, {}, {}) state={} prev={} next={}",
         source,
         reason,
         blockPos.getX(),
         blockPos.getY(),
         blockPos.getZ(),
         blockState,
         previous == null ? "null" : previous.blockId() + "/" + System.identityHashCode(previous.lightInfo()),
         updated == null ? "null" : updated.blockId() + "/" + System.identityHashCode(updated.lightInfo())
      );
   }

   private void logLightActivityMutation(SyncSource source, BlockPos blockPos, BlockState blockState, TracedLightPosition previous, TracedLightPosition updated) {
      if (!PhotonicsStorage.PROFILER_ENABLED.value || !Photonic.automationEnabled() || this.mutationDebugLogsRemaining <= 0) {
         return;
      }

      this.mutationDebugLogsRemaining--;
      Photonic.info(
         "[Profiler] lightMutation: source={} reason={} pos=({}, {}, {}) state={} prev={} next={}",
         source,
         DirtyReason.ACTIVITY_CHANGED,
         blockPos.getX(),
         blockPos.getY(),
         blockPos.getZ(),
         blockState,
         previous.blockId() + "/" + System.identityHashCode(previous.lightInfo()) + "/" + previous.active(),
         updated.blockId() + "/" + System.identityHashCode(updated.lightInfo()) + "/" + updated.active()
      );
   }

   private static long gridKey(int gx, int gy, int gz) {
      return ((long) gx & 0xFFFFF) | (((long) gy & 0xFFFFF) << 20) | (((long) gz & 0xFFFFF) << 40);
   }

   private void noteTracedLightMutation(SyncSource source, DirtyReason reason, BlockPos blockPos, TracedLightPosition previous, TracedLightPosition updated) {
      this.tracedLightSetDirty = true;
      this.pendingTracedLightMutations++;
      this.noteDirtyLightBlock(blockPos);
      this.churnStats.noteMutation(source, reason, blockPos, previous, updated);
   }

   private void noteTracedLightActivityMutation(SyncSource source, BlockPos blockPos, TracedLightPosition previous, TracedLightPosition updated) {
      this.lightActivityDirty = true;
      this.churnStats.noteMutation(source, DirtyReason.ACTIVITY_CHANGED, blockPos, previous, updated);
   }

   private void noteTracedLightBufferMutation(SyncSource source, DirtyReason reason, BlockPos blockPos, TracedLightPosition previous, TracedLightPosition updated) {
      this.lightActivityDirty = true;
      this.noteDirtyLightBlock(blockPos);
      this.churnStats.noteMutation(source, reason, blockPos, previous, updated);
   }

   private void noteDirtyLightBlock(BlockPos blockPos) {
      if (blockPos != null) {
         this.dirtyLightBlocks.add(new BlockPos(blockPos.getX(), blockPos.getY(), blockPos.getZ()));
      }
   }

   static long chunkKey(int chunkX, int chunkY, int chunkZ) {
      return (((long) chunkX) & 0x1FFFFFL)
         | ((((long) chunkY) & 0x1FFFFFL) << 21)
         | ((((long) chunkZ) & 0x1FFFFFL) << 42);
   }

   static long chunkKey(PChunkPos chunkPos) {
      return chunkKey(chunkPos.x, chunkPos.y, chunkPos.z);
   }

   static long chunkKey(BlockPos blockPos) {
      return chunkKey(blockPos.getX() >> 4, blockPos.getY() >> 4, blockPos.getZ() >> 4);
   }

   private boolean isTrackedChunkLoaded(BlockPos blockPos) {
      return this.tracing.isTrackedChunkLoaded(blockPos);
   }

   public String describeRecentChurn() {
      return this.churnStats.describe();
   }

   private void buildSpatialGrid(LightInstance[] lights) {
      this.regir.buildSpatialGrid(lights, this.getRegirBuildCellRadius());
   }

   public void refreshActiveRegirCells(Vector3f cameraPos) {
      this.regir.refreshActiveRegirCells(cameraPos, this.tracedLights);
   }

   public int getActiveRegirCellCount() {
      return this.regir.getActiveRegirCellCount();
   }

   public IntBuffer getActiveRegirCellsBuffer() {
      return this.regir.getActiveRegirCellsBuffer();
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

   private enum DirtyReason {
      ADDED,
      REMOVED_NO_LIGHT,
      CULLED,
      BLOCK_ID_CHANGED,
      LIGHT_INFO_CHANGED,
      ACTIVITY_CHANGED
   }

   private enum SyncSource {
      BLOCK_LOAD,
      BLOCK_UPDATE_LIVE,
      BLOCK_UPDATE_SNAPSHOT,
      CHUNK_SYNC
   }

   private static final class LightChurnStats {
      private static final int MAX_SAMPLES = 4;
      private final EnumMap<DirtyReason, LongAdder> mutationCounts = new EnumMap<>(DirtyReason.class);
      private final EnumMap<SyncSource, LongAdder> sourceCounts = new EnumMap<>(SyncSource.class);
      private final Map<DirtyReason, String> samples = new LinkedHashMap<>();
      private boolean samplesTruncated = false;
      private final LongAdder noopSyncs = new LongAdder();
      private volatile Frame lastFrame = new Frame(0, 0);

      private LightChurnStats() {
         for (DirtyReason reason : DirtyReason.values()) {
            this.mutationCounts.put(reason, new LongAdder());
         }
         for (SyncSource source : SyncSource.values()) {
            this.sourceCounts.put(source, new LongAdder());
         }
      }

      private Frame beginFrame(int previousCount, int gatheredCount) {
         Frame frame = new Frame(previousCount, gatheredCount);
         this.lastFrame = frame;
         return frame;
      }

      private void noteMutation(SyncSource source, DirtyReason reason, BlockPos blockPos, TracedLightPosition previous, TracedLightPosition updated) {
         this.mutationCounts.get(reason).increment();
         this.sourceCounts.get(source).increment();
         if (!this.samples.containsKey(reason)) {
            if (this.samples.size() < MAX_SAMPLES) {
               this.samples.put(reason, formatSample(blockPos, previous, updated));
            } else {
               this.samplesTruncated = true;
            }
         }
      }

      private void noteNoopSync() {
         this.noopSyncs.increment();
      }

      private boolean lastFrameBufferOnly() {
         Frame frame = this.lastFrame;
         return (frame.activityChanges > 0 || frame.blockIdChanges > 0 || frame.radiometryChanges > 0)
            && frame.additions == 0
            && frame.removals == 0
            && frame.lightInfoChanges == 0;
      }

      private String describe() {
         Frame frame = this.lastFrame;
         return String.format(
            "frame(prev=%d,gathered=%d,stable=%d,added=%d,removed=%d,blockId=%d,lightInfo=%d,radiometry=%d,activity=%d) mutations(add=%d,remove=%d,cull=%d,blockId=%d,lightInfo=%d,noop=%d) sources(load=%d,live=%d,snapshot=%d,chunk=%d)%s",
            frame.previousCount,
            frame.gatheredCount,
            frame.stableMappings,
            frame.additions,
            frame.removals,
            frame.blockIdChanges,
            frame.lightInfoChanges,
            frame.radiometryChanges,
            frame.activityChanges,
            this.mutationCounts.get(DirtyReason.ADDED).sum(),
            this.mutationCounts.get(DirtyReason.REMOVED_NO_LIGHT).sum(),
            this.mutationCounts.get(DirtyReason.CULLED).sum(),
            this.mutationCounts.get(DirtyReason.BLOCK_ID_CHANGED).sum(),
            this.mutationCounts.get(DirtyReason.LIGHT_INFO_CHANGED).sum(),
            this.noopSyncs.sum(),
            this.sourceCounts.get(SyncSource.BLOCK_LOAD).sum(),
            this.sourceCounts.get(SyncSource.BLOCK_UPDATE_LIVE).sum(),
            this.sourceCounts.get(SyncSource.BLOCK_UPDATE_SNAPSHOT).sum(),
            this.sourceCounts.get(SyncSource.CHUNK_SYNC).sum(),
            this.samples.isEmpty() ? "" : " samples=" + this.samples + (this.samplesTruncated ? "..." : "")
         );
      }

      private static String formatSample(BlockPos blockPos, TracedLightPosition previous, TracedLightPosition updated) {
         return String.format(
            "(%d,%d,%d):%s->%s",
            blockPos.getX(),
            blockPos.getY(),
            blockPos.getZ(),
            describe(previous),
            describe(updated)
         );
      }

      private static String describe(TracedLightPosition position) {
         if (position == null) {
            return "null";
         }
         return position.blockId() + "/" + System.identityHashCode(position.lightInfo());
      }

      private static final class Frame {
         private final int previousCount;
         private final int gatheredCount;
         private int stableMappings;
         private int additions;
         private int removals;
         private int blockIdChanges;
         private int lightInfoChanges;
         private int radiometryChanges;
         private int activityChanges;

         private Frame(int previousCount, int gatheredCount) {
            this.previousCount = previousCount;
            this.gatheredCount = gatheredCount;
         }
      }
   }

   private record WeightedLightSelection(int lightIndex, float invSourcePdf) {
   }
}



