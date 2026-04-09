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
import at.redi2go.photonic.client.rendering.opengl.rendering.RegirComputeProgram;
import at.redi2go.photonic.client.rendering.util.IrisUtil;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.SimpleMemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import at.redi2go.photonic.client.rendering.world.position.PBlockPos;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.HashMap;
import java.util.HashSet;
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
import net.minecraft.util.math.BlockPos;
import org.apache.commons.lang3.tuple.Pair;
import org.joml.Vector2f;
import org.joml.Vector3f;

public class LightRegistry implements Destructable {
   private static final int LIGHT_BYTE_SIZE = 64;
   private static final int GRID_CELL_SIZE = 32;
   private static final float REGIR_CELL_RADIUS = (float)(Math.sqrt(3.0) * GRID_CELL_SIZE);
   // User-facing ReGIR jitter in grid-cell units.
   // RTXDI doubles this before upload because the shader multiplies (rand - 0.5)
   // by samplingJitter * cellSize, so a runtime value of 2.0 means +/- one cell.
   private static final float REGIR_SAMPLING_JITTER = 1.0F;
   private static final int REGIR_MAX_LIGHTS_PER_CELL_FALLBACK = 16;
   // RTXDI default from ReGIR.h:141 = 8 build samples per cell slot
   private static final int REGIR_BUILD_SAMPLES = 8;
   private static final int INCREMENTAL_PARALLEL_THRESHOLD = 32;
   private static final float POSITION_MATCH_EPSILON = 1.0e-4F;
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

   private static boolean sameSemanticLight(LightInstance before, LightInstance after) {
      return before != null
         && after != null
         && before.blockId() == after.blockId()
         && samePosition(before.position(), after.position())
         && sameLightDescriptor(before.type(), after.type());
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

   private GlMemoryManager lightsMemoryManager;
  private MemoryOwner lightsMemory;
  private GlMemoryManager previousLightsMemoryManager;
  private SimpleMemoryOwner previousLightsMemory;
  private GlMemoryManager lightMappingMemoryManager;
  private MemoryOwner lightMappingMemory;
  private GlMemoryManager lightReverseMappingMemoryManager;
  private MemoryOwner lightReverseMappingMemory;
  private GlMemoryManager globalLightCdfMemoryManager;
  private MemoryOwner globalLightCdfMemory;
  private final GlMemoryManager regirCellCountMemoryManager;
  private final MemoryOwner regirCellCountMemory;
  private final GlMemoryManager regirLightIndexMemoryManager;
  private final MemoryOwner regirLightIndexMemory;
  private final GlMemoryManager regirLightPdfMemoryManager;
  private final MemoryOwner regirLightPdfMemory;
  private final GlMemoryManager regirCompactLightDataMemoryManager;
  private final MemoryOwner regirCompactLightDataMemory;
  private static final int NEIGHBOR_OFFSET_COUNT = 8192;
  private final GlMemoryManager neighborOffsetMemoryManager;
  private final SimpleMemoryOwner neighborOffsetMemory;
  private final int maxLights;
  private final float minTracedLightSelectionLuma;
  private int lightCapacity;
  private final int regirGridResolution;
  private final int regirCellCount;
  private final int regirLightsPerCell;
  private short[] newLightIndices;
  private PBlockPos offset = new PBlockPos(0, 0, 0);
  private int lightCount = 0;
  private LightInstance[] tracedLights = new LightInstance[0];
  private final Map<Vector3f, TracedLightPosition> tracedLightPositions = new ConcurrentHashMap<>();
  private final Set<Long> loadedLightChunks = ConcurrentHashMap.newKeySet();
  private final PhotonicsConfig.Observer<LightList> lightListObserver;
  private LightList lightList = new LightList();
  private final ReadWriteLock lock;
  private boolean building = false;
  private int compileCount = 0;
  private LightsProvider lightsProvider = null;
  private volatile boolean tracedLightSetDirty = true;
   private HashMap<Long, List<Integer>> lightGrid;
  private int lightGridAssignments = 0;
  private final LightChurnStats churnStats = new LightChurnStats();
  private boolean identityLightMappingPending = false;
  private int regirActiveCellCount = 0;
  private int regirActiveLightSlotCount = 0;
  // RTXDI: stores the center of the grid (= camera position, snapped to cell boundaries).
  // The origin is derived in the shader as: origin = center - vec3(gridRes) * cellSize * 0.5
  private final Vector3f regirGridCenter = new Vector3f();
  private boolean regirGridCenterInitialized = false;
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
  private int mutationDebugLogsRemaining = 48;

  public LightRegistry(int maxLights, int maxLightsPerNode, float minTracedLightSelectionLuma, int nodeSize, int worldSize) {
     if (16 % nodeSize != 0) {
        throw new IllegalArgumentException();
     }

     this.maxLights = maxLights;
     this.minTracedLightSelectionLuma = Math.max(0.0F, minTracedLightSelectionLuma);
     this.lightCapacity = Math.max(1, maxLights);
     this.regirLightsPerCell = Math.max(1, maxLightsPerNode > 0 ? maxLightsPerNode : REGIR_MAX_LIGHTS_PER_CELL_FALLBACK);
     this.regirGridResolution = Math.max(1, worldSize / GRID_CELL_SIZE);
     this.regirCellCount = this.regirGridResolution * this.regirGridResolution * this.regirGridResolution;
     this.newLightIndices = new short[this.lightCapacity];
     this.lightsMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_light_list", this.lightCapacity * LIGHT_BYTE_SIZE + 4, true);
     this.lightsMemory = new SimpleMemoryOwner(this.lightsMemoryManager, this.lightsMemoryManager.getCapacity());
     this.previousLightsMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_light_list_previous", this.lightCapacity * LIGHT_BYTE_SIZE + 4, true);
     this.previousLightsMemory = new SimpleMemoryOwner(this.previousLightsMemoryManager, this.previousLightsMemoryManager.getCapacity());
     this.lightMappingMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_light_list_mapping", this.lightCapacity * 4, false);
     this.lightMappingMemory = new SimpleMemoryOwner(this.lightMappingMemoryManager, this.lightMappingMemoryManager.getCapacity());
      this.lightReverseMappingMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_light_reverse_mapping", this.lightCapacity * 4, false);
      this.lightReverseMappingMemory = new SimpleMemoryOwner(this.lightReverseMappingMemoryManager, this.lightReverseMappingMemoryManager.getCapacity());
      this.globalLightCdfMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_global_light_cdf", this.lightCapacity * Float.BYTES, false);
      this.globalLightCdfMemory = new SimpleMemoryOwner(this.globalLightCdfMemoryManager, this.globalLightCdfMemoryManager.getCapacity());
      this.regirCellCountMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_regir_cell_counts", this.regirCellCount * Integer.BYTES, false);
      this.regirCellCountMemory = new SimpleMemoryOwner(this.regirCellCountMemoryManager, this.regirCellCountMemoryManager.getCapacity());
      // Unified RIS buffer (RTXDI_RIS_BUFFER): presample tiles + ReGIR output in one SSBO.
      // Layout: [0, tileCount*tileSize) = presample tiles; [tileCount*tileSize, ...) = ReGIR output.
      // Fragment shaders bind this as ph_ris_buffer and read the ReGIR region via ph_regir_ris_buffer_offset.
      int risBufferTileEntries = RegirComputeProgram.tileCount * RegirComputeProgram.tileSize;
      this.regirLightIndexMemoryManager = new GlMemoryManager(
         GlTarget.SSBO,
         "ph_ris_buffer",
         (risBufferTileEntries + this.regirCellCount * this.regirLightsPerCell) * 8, // 8 bytes per uvec2
         false
      );
      this.regirLightIndexMemory = new SimpleMemoryOwner(this.regirLightIndexMemoryManager, this.regirLightIndexMemoryManager.getCapacity());
      // PDF buffer is retained for the CPU-side (non-GPU) build path only.
      // When GPU build is active it is unused; kept to avoid breaking existing CPU code paths.
      this.regirLightPdfMemoryManager = new GlMemoryManager(
         GlTarget.SSBO,
         "ph_regir_light_pdfs",
         this.regirCellCount * this.regirLightsPerCell * Float.BYTES,
         false
      );
      this.regirLightPdfMemory = new SimpleMemoryOwner(this.regirLightPdfMemoryManager, this.regirLightPdfMemoryManager.getCapacity());
      // Compact light data buffer uses the full 4*uvec4 companion layout per RIS slot.
      int compactTotalEntries = risBufferTileEntries + this.regirCellCount * this.regirLightsPerCell;
      this.regirCompactLightDataMemoryManager = new GlMemoryManager(
         GlTarget.SSBO,
         "ph_ris_compact_light_data",
         compactTotalEntries * 4 * 16,
         false
      );
      this.regirCompactLightDataMemory = new SimpleMemoryOwner(this.regirCompactLightDataMemoryManager, this.regirCompactLightDataMemoryManager.getCapacity());
      this.neighborOffsetMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_neighbor_offsets", NEIGHBOR_OFFSET_COUNT * 2, false);
      this.neighborOffsetMemory = new SimpleMemoryOwner(this.neighborOffsetMemoryManager, this.neighborOffsetMemoryManager.getCapacity());
      this.fillNeighborOffsets();
      this.lightListObserver = PhotonicsConfig.observe(c -> PhotonicsConfig.getLightList(), c -> {
         this.lightList = c;
         this.registerLightBlocks(this.lightList);
         this.tracedLightSetDirty = true;
         MinecraftClient.getInstance().worldRenderer.reload();
      });
      this.lock = new ReentrantReadWriteLock();
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

      float refreshDistance = Math.max(GRID_CELL_SIZE * 0.25F, 4.0F);
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
         boolean rebuildSpatialGrid = lightsChanged || this.lightGrid == null;
         if (rebuildSpatialGrid) {
            this.buildSpatialGrid(this.tracedLights);
         }
         if (profiling) {
            tGrid = System.nanoTime();
         }

         boolean regirDirty = rebuildSpatialGrid || offsetChanged;
         if (regirDirty && !this.gpuRegirBuildEnabled) {
            this.buildRegirGrid();
         } else if (regirDirty) {
            this.updateRegirGridOriginOnly();
         }

         Vector3f selectionCamera = this.getTracedLightSelectionCameraPosition();
         boolean refreshGlobalLightCdf = this.shouldRefreshGlobalLightCdf(selectionCamera, lightsChanged);

         boolean identityQueued = false;
         if (lightsChanged) {
            this.copyCurrentLightsToPrevious();
            this.storeLights();
            this.storeLightMappings();
            this.storeLightReverseMappings();
            this.storeGlobalLightCdf(selectionCamera);
            this.markGlobalLightCdfCamera(selectionCamera);
            this.lightsMemoryManager.queueUpload(this.lightsMemory);
            this.previousLightsMemoryManager.queueUpload(this.previousLightsMemory);
            this.lightMappingMemoryManager.queueUpload(this.lightMappingMemory);
            this.lightReverseMappingMemoryManager.queueUpload(this.lightReverseMappingMemory);
            this.globalLightCdfMemoryManager.queueUpload(this.globalLightCdfMemory);
            this.identityLightMappingPending = true;
         } else {
            if (refreshGlobalLightCdf) {
               this.storeGlobalLightCdf(selectionCamera);
               this.markGlobalLightCdfCamera(selectionCamera);
               this.globalLightCdfMemoryManager.queueUpload(this.globalLightCdfMemory);
            }
            identityQueued = this.queueIdentityLightMappingsIfNeeded();
         }
         if (regirDirty && !this.gpuRegirBuildEnabled) {
            this.regirCellCountMemoryManager.queueUpload(this.regirCellCountMemory);
            this.regirLightIndexMemoryManager.queueUpload(this.regirLightIndexMemory);
            this.regirLightPdfMemoryManager.queueUpload(this.regirLightPdfMemory);
            this.regirCompactLightDataMemoryManager.queueUpload(this.regirCompactLightDataMemory);
         }
         if (profiling) {
            tStore = System.nanoTime();
            String rebuildReason;
            if (offsetChanged) {
               rebuildReason = "offset";
            } else if (lightsChanged) {
               rebuildReason = "lights";
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
               this.lightGrid == null ? 0 : this.lightGrid.size(),
               this.lightGridAssignments,
               this.describeRecentChurn(),
               lightsChanged,
               lightsChanged,
               regirDirty,
               identityQueued,
               gatherMs,
               diffMs,
               gridMs,
               storeMs,
               totalMs
            );
            if (lightsChanged) {
               Photonic.info(
                  "[Profiler] regirBuild: lights={} activeCells={} lightSlots={} gridResolution={}x{}x{} cellSize={} compileCount={} churn={}",
                  this.tracedLights.length,
                  this.regirActiveCellCount,
                  this.regirActiveLightSlotCount,
                  this.regirGridResolution,
                  this.regirGridResolution,
                  this.regirGridResolution,
                  GRID_CELL_SIZE,
                  this.compileCount,
                  this.describeRecentChurn()
               );
            }
         }
      } finally {
         this.building = false;
      }
   }

   private void copyCurrentLightsToPrevious() {
      java.nio.ByteBuffer src = this.lightsMemory.getMemory().getBuffer();
      java.nio.ByteBuffer dst = this.previousLightsMemory.getMemory().getBuffer();
      int copyLength = Math.min(src.capacity(), dst.capacity());
      src.rewind();
      dst.rewind();
      for (int i = 0; i < copyLength; i++) {
         dst.put(src.get());
      }
      src.rewind();
      dst.rewind();
   }

   private void storeLights() {
      FloatBuffer buffer = this.lightsMemory.getMemory().getBuffer().asFloatBuffer();
      Vector3f colorSum = Photonic.automationEnabled() && !this.loggedAutomationLightColors ? new Vector3f() : null;
      StringBuilder sampleLights = Photonic.automationEnabled() && !this.loggedAutomationLightColors ? new StringBuilder() : null;
      int sampledLights = 0;
      for (LightInstance light : this.tracedLights) {
         buffer.position(16 * light.index());
         BlockLightInfo lightInfo = light.type();
         Vector3f rawColor = lightInfo.getRawColorAsVector();
         float lightIntensity = light.active() ? lightInfo.adjustedIntensity() : 0.0F;
         store(light.position(), buffer);                       // vec4[0].xyz = position
         buffer.put(Float.intBitsToFloat(light.blockId()));     // vec4[0].w = blockId
         store(rawColor, buffer);                               // vec4[1].xyz = color
         buffer.put(lightIntensity);                            // vec4[1].w = intensity
         store(lightInfo.getAttenuationAsVector(), buffer);     // vec4[2].xy = attenuation
         buffer.put(lightInfo.falloff());                       // vec4[2].z = falloff
         buffer.put(lightInfo.radiusInBlocks());                // vec4[2].w = block_radius
         store(lightInfo.emissionAxis(), buffer);               // vec4[3].xyz = emissionAxis
         buffer.put(lightInfo.orientationSpread() + lightInfo.emissionSpread()); // vec4[3].w = orientationSpread + emissionSpread

         if (colorSum != null) {
            colorSum.add(rawColor.x * lightIntensity, rawColor.y * lightIntensity, rawColor.z * lightIntensity);
            if (sampledLights < 5) {
               sampleLights.append(" idx=")
                  .append(light.index())
                  .append(" blockId=")
                  .append(light.blockId())
                  .append(" pos=")
                  .append(light.position())
                  .append(" color=")
                  .append(rawColor)
                  .append(" intensity=")
                  .append(lightIntensity);
               sampledLights++;
            }
         }
      }

      // Always log first 3 lights for brightness debugging
      if (this.tracedLights.length > 0 && this.compileCount % 60 == 0) {
         StringBuilder debugLights = new StringBuilder();
         int debugCount = Math.min(3, this.tracedLights.length);
         for (int i = 0; i < debugCount; i++) {
            LightInstance dl = this.tracedLights[i];
            BlockLightInfo dli = dl.type();
            Vector3f dc = dli.getRawColorAsVector();
            debugLights.append(String.format(
               " [%d] pos=%s rawColor=(%.4f,%.4f,%.4f) intensity=%.4f attenuation=(%.4f,%.4f) falloff=%.4f radius=%.2f",
               dl.index(), dl.position(), dc.x, dc.y, dc.z, dli.adjustedIntensity(),
               dli.getAttenuationAsVector().x, dli.getAttenuationAsVector().y, dli.falloff(), dli.radiusInBlocks()
            ));
         }
         Photonic.info("[LightDebug] tracedLights={} lights:{}", this.tracedLights.length, debugLights);
      }
      if (colorSum != null && this.tracedLights.length > 0) {
         colorSum.div((float) this.tracedLights.length);
         this.loggedAutomationLightColors = true;
         Photonic.info(
            "[LightRegistryDebug] uploadedLights={} meanColor={}{}",
            this.tracedLights.length,
            colorSum,
            sampleLights == null || sampleLights.isEmpty() ? "" : sampleLights.toString()
         );
      }
   }

   private void storeLightMappings() {
      IntBuffer buffer = this.lightMappingMemory.getMemory().getBuffer().asIntBuffer();
      int capacity = this.getLightCapacity();
      for (int i = 0; i < capacity; i++) {
         buffer.put(i, this.newLightIndices[i]);
      }
   }

   private void storeLightReverseMappings() {
      // Build reverse mapping: reverseMapping[currentIndex] = previousIndex.
      // newLightIndices[previousIndex] = currentIndex (the forward mapping).
      // Initialize all entries to -1 (no mapping).
      IntBuffer buffer = this.lightReverseMappingMemory.getMemory().getBuffer().asIntBuffer();
      int capacity = this.getLightCapacity();
      for (int i = 0; i < capacity; i++) {
         buffer.put(i, -1);
      }
      for (int previousIndex = 0; previousIndex < capacity; previousIndex++) {
         int currentIndex = this.newLightIndices[previousIndex];
         if (currentIndex >= 0 && currentIndex < capacity) {
            buffer.put(currentIndex, previousIndex);
         }
      }
   }

   private void storeGlobalLightCdf(Vector3f selectionCamera) {
      FloatBuffer buffer = this.globalLightCdfMemory.getMemory().getBuffer().asFloatBuffer();
      int tracedCount = this.tracedLights.length;
      int capacity = this.getLightCapacity();
      this.lightPowers = new float[tracedCount];
      float cumulativeWeight = 0.0F;
      boolean hasPositiveWeight = false;
      int activeLightCount = 0;
      for (int i = 0; i < capacity; i++) {
         if (i < tracedCount) {
            LightInstance light = this.tracedLights[i];
            float weight = Math.max(selectionSourceScore(light, selectionCamera, this.minTracedLightSelectionLuma), 0.0F);
            if (weight > 1.0e-6F) {
               cumulativeWeight += weight;
               hasPositiveWeight = true;
            }
            if (light.active()) {
               activeLightCount++;
            }
            this.lightPowers[i] = weight;
         }
         buffer.put(i, cumulativeWeight);
      }

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
      IntBuffer forwardBuffer = this.lightMappingMemory.getMemory().getBuffer().asIntBuffer();
      IntBuffer reverseBuffer = this.lightReverseMappingMemory.getMemory().getBuffer().asIntBuffer();
      int capacity = this.getLightCapacity();
      for (int i = 0; i < capacity; i++) {
         forwardBuffer.put(i, i);
         reverseBuffer.put(i, i);
      }
   }

   private void updateRegirGridOriginOnly() {
      Vector3f gridCenter = this.resolveRegirGridCenter();
      this.regirGridCenter.set(gridCenter);
      this.updateRegirActivityStats(gridCenter);
   }

   private void updateRegirActivityStats(Vector3f gridCenter) {
      this.regirActiveCellCount = 0;
      this.regirActiveLightSlotCount = 0;

      if (this.lightGrid == null || this.lightGrid.isEmpty() || this.tracedLights.length == 0) {
         return;
      }

      float halfExtent = this.regirGridResolution * GRID_CELL_SIZE * 0.5f;
      int originCellX = (int) Math.floor((gridCenter.x - halfExtent) / GRID_CELL_SIZE);
      int originCellY = (int) Math.floor((gridCenter.y - halfExtent) / GRID_CELL_SIZE);
      int originCellZ = (int) Math.floor((gridCenter.z - halfExtent) / GRID_CELL_SIZE);
      Vector3f cellCenter = new Vector3f();

      for (int z = 0; z < this.regirGridResolution; z++) {
         for (int y = 0; y < this.regirGridResolution; y++) {
            for (int x = 0; x < this.regirGridResolution; x++) {
               List<Integer> cellLights = this.lightGrid.get(gridKey(originCellX + x, originCellY + y, originCellZ + z));
               if (cellLights == null || cellLights.isEmpty()) {
                  continue;
               }

               cellCenter.set(
                  (float)(originCellX * GRID_CELL_SIZE) + (x + 0.5F) * GRID_CELL_SIZE,
                  (float)(originCellY * GRID_CELL_SIZE) + (y + 0.5F) * GRID_CELL_SIZE,
                  (float)(originCellZ * GRID_CELL_SIZE) + (z + 0.5F) * GRID_CELL_SIZE
               );

               int cellIndex = x + this.regirGridResolution * (y + this.regirGridResolution * z);
               int count = 0;
               for (int slot = 0; slot < this.regirLightsPerCell; slot++) {
                  long seed = (((long) cellIndex) << 32)
                     ^ (((long) slot + 1L) * 0x9E3779B97F4A7C15L);
                  WeightedLightSelection selection = sampleRegirCellLight(cellLights, this.tracedLights, cellCenter, this.getRegirBuildCellRadius(), seed);
                  if (selection.lightIndex() >= 0 && selection.invSourcePdf() > 0.0F) {
                     count++;
                  }
               }

               if (count > 0) {
                  this.regirActiveCellCount++;
                  this.regirActiveLightSlotCount += count;
               }
            }
         }
      }
   }

   private void buildRegirGrid() {
      IntBuffer cellCountBuffer = this.regirCellCountMemory.getMemory().getBuffer().asIntBuffer();
      IntBuffer lightIndexBuffer = this.regirLightIndexMemory.getMemory().getBuffer().asIntBuffer();
      FloatBuffer lightPdfBuffer = this.regirLightPdfMemory.getMemory().getBuffer().asFloatBuffer();
      for (int i = 0; i < this.regirCellCount; i++) {
         cellCountBuffer.put(i, 0);
      }
      int totalSlots = this.regirCellCount * this.regirLightsPerCell;
      for (int i = 0; i < totalSlots; i++) {
         lightIndexBuffer.put(i, -1);
         lightPdfBuffer.put(i, 0.0F);
      }

      Vector3f gridCenter = this.resolveRegirGridCenter();
      this.regirGridCenter.set(gridCenter);
      // Derive origin for CPU-side cell iteration (mirrors shader derivation)
      float halfExtent = this.regirGridResolution * GRID_CELL_SIZE * 0.5f;
      int originCellX = (int) Math.floor((gridCenter.x - halfExtent) / GRID_CELL_SIZE);
      int originCellY = (int) Math.floor((gridCenter.y - halfExtent) / GRID_CELL_SIZE);
      int originCellZ = (int) Math.floor((gridCenter.z - halfExtent) / GRID_CELL_SIZE);
      this.regirActiveCellCount = 0;
      this.regirActiveLightSlotCount = 0;

      if (this.lightGrid == null || this.lightGrid.isEmpty() || this.tracedLights.length == 0) {
         return;
      }

      Vector3f cellCenter = new Vector3f();
      for (int z = 0; z < this.regirGridResolution; z++) {
         for (int y = 0; y < this.regirGridResolution; y++) {
            for (int x = 0; x < this.regirGridResolution; x++) {
               List<Integer> cellLights = this.lightGrid.get(gridKey(originCellX + x, originCellY + y, originCellZ + z));
               if (cellLights == null || cellLights.isEmpty()) {
                  continue;
               }

               cellCenter.set(
                  (float)(originCellX * GRID_CELL_SIZE) + (x + 0.5F) * GRID_CELL_SIZE,
                  (float)(originCellY * GRID_CELL_SIZE) + (y + 0.5F) * GRID_CELL_SIZE,
                  (float)(originCellZ * GRID_CELL_SIZE) + (z + 0.5F) * GRID_CELL_SIZE
               );

               int cellIndex = x + this.regirGridResolution * (y + this.regirGridResolution * z);
               int bufferOffset = cellIndex * this.regirLightsPerCell;
               int count = 0;
               for (int slot = 0; slot < this.regirLightsPerCell; slot++) {
                  // Keep the ReGIR cell contents stable while the traced-light set and
                  // camera-relative grid cell stay the same. compileCount-driven slot
                  // churn destabilizes DI history because the same camera pose ends up
                  // seeing a different presampled cell every rebuild.
                  long seed = (((long) cellIndex) << 32)
                     ^ (((long) slot + 1L) * 0x9E3779B97F4A7C15L);
                  WeightedLightSelection selection = sampleRegirCellLight(cellLights, this.tracedLights, cellCenter, this.getRegirBuildCellRadius(), seed);
                  if (selection.lightIndex() < 0 || selection.invSourcePdf() <= 0.0F) {
                     continue;
                  }

                  lightIndexBuffer.put(bufferOffset + count, selection.lightIndex());
                  lightPdfBuffer.put(bufferOffset + count, selection.invSourcePdf());
                  count++;
               }

               if (count <= 0) {
                  continue;
               }

               cellCountBuffer.put(cellIndex, count);

               this.regirActiveCellCount++;
               this.regirActiveLightSlotCount += count;
            }
         }
      }
   }

   private static WeightedLightSelection sampleRegirCellLight(
      List<Integer> cellLights,
      LightInstance[] tracedLights,
      Vector3f cellCenter,
      float cellRadius,
      long seed
   ) {
      if (cellLights.isEmpty()) {
         return new WeightedLightSelection(-1, 0.0F);
      }

      int proposalCount = Math.max(1, REGIR_BUILD_SAMPLES);
      int cellLightCount = Math.max(cellLights.size(), 1);
      float invNumSamples = 1.0F / proposalCount;
      float invSourcePdf = cellLightCount * invNumSamples;
      float weightSum = 0.0F;
      int selectedLightIndex = -1;
      float selectedTargetPdf = 0.0F;

      for (int sampleIndex = 0; sampleIndex < proposalCount; sampleIndex++) {
         long sampleSeed = seed ^ (((long) sampleIndex + 1L) * 0xD1B54A32D192ED03L);
         int cellSlot = Math.min(cellLights.size() - 1, (int) (regirHashUnitFloat(sampleSeed) * cellLights.size()));
         int lightIndex = cellLights.get(cellSlot);
         if (lightIndex < 0 || lightIndex >= tracedLights.length) {
            continue;
         }

         float targetPdf = regirCellImportance(tracedLights[lightIndex], cellCenter, cellRadius);
         if (targetPdf <= 0.0F) {
            continue;
         }

         float risWeight = targetPdf * invSourcePdf;
         weightSum += risWeight;
         float risRandom = regirHashUnitFloat(sampleSeed ^ 0x9E3779B97F4A7C15L);
         if (risRandom * weightSum <= risWeight) {
            selectedLightIndex = lightIndex;
            selectedTargetPdf = targetPdf;
         }
      }

      if (selectedLightIndex < 0 || selectedTargetPdf <= 1.0e-6F || weightSum <= 1.0e-6F) {
         return new WeightedLightSelection(-1, 0.0F);
      }

      return new WeightedLightSelection(selectedLightIndex, Math.max(weightSum / selectedTargetPdf, 1.0e-6F));
   }

   private static float regirCellImportance(LightInstance light, Vector3f cellCenter, float cellRadius) {
      BlockLightInfo lightInfo = light.type();
      Vector3f lightPosition = light.position();
      float dx = cellCenter.x - lightPosition.x;
      float dy = cellCenter.y - lightPosition.y;
      float dz = cellCenter.z - lightPosition.z;
      float distance = (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
      float averageDistance = regirAverageDistanceToVolume(distance, cellRadius);
      float dirX = distance > 1.0e-4F ? dx / distance : 0.0F;
      float dirY = distance > 1.0e-4F ? dy / distance : 0.0F;
      float dirZ = distance > 1.0e-4F ? dz / distance : 1.0F;

      float shaping = 1.0F;
      float spread = lightInfo.orientationSpread() + lightInfo.emissionSpread();
      if (spread < Math.PI) {
         Vector3f axis = lightInfo.emissionAxis();
         float axisDot = Math.max(-1.0F, Math.min(1.0F, axis.dot(dirX, dirY, dirZ)));
         float axisAngle = (float) Math.acos(axisDot);
         shaping = Math.max((float) Math.cos(Math.max(axisAngle - spread, 0.0F)), 0.0F);
      }

      if (shaping <= 0.0F) {
         return 0.0F;
      }

      return lightInfo.luminanceFrom(lightPosition, new Vector3f(
         lightPosition.x + dirX * averageDistance,
         lightPosition.y + dirY * averageDistance,
         lightPosition.z + dirZ * averageDistance
      )) * shaping;
   }

   private static float regirAverageDistanceToVolume(float distanceToCenter, float volumeRadius) {
      final float nonlinearFactor = 1.1547F;
      float radiusSq = volumeRadius * volumeRadius;
      float denom = distanceToCenter + volumeRadius * nonlinearFactor;
      return distanceToCenter + volumeRadius * radiusSq / Math.max(denom * denom, 1.0e-4F);
   }

   private static float regirHashUnitFloat(long seed) {
      long hashed = regirHash64(seed);
      return (float) (((hashed >>> 40) & 0xFFFFFFL) / (double) 0x1000000L);
   }

   private static long regirHash64(long value) {
      value ^= (value >>> 30);
      value *= 0xBF58476D1CE4E5B9L;
      value ^= (value >>> 27);
      value *= 0x94D049BB133111EBL;
      value ^= (value >>> 31);
      return value;
   }

   boolean queueIdentityLightMappingsIfNeeded() {
      if (!this.identityLightMappingPending) {
         return false;
      }
      this.copyCurrentLightsToPrevious();
      this.storeIdentityLightMappings();
      this.previousLightsMemoryManager.queueUpload(this.previousLightsMemory);
      this.lightMappingMemoryManager.queueUpload(this.lightMappingMemory);
      this.lightReverseMappingMemoryManager.queueUpload(this.lightReverseMappingMemory);
      this.identityLightMappingPending = false;
      return true;
   }

   private boolean createTracedLights(LightInstance[] gatheredLights) {
      LightInstance[] sortedLights = Arrays.copyOf(gatheredLights, gatheredLights.length);
      Arrays.sort(sortedLights, STABLE_LIGHT_ORDER);
      this.ensureLightCapacity(Math.max(sortedLights.length, this.tracedLights.length));
      Arrays.fill(this.newLightIndices, (short) -1);
      LightInstance[] prevLights = this.tracedLights;
      LightChurnStats.Frame frameStats = this.churnStats.beginFrame(prevLights.length, sortedLights.length);
      boolean[] matchedCurrent = new boolean[sortedLights.length];
      LightInstance[] nextLights = new LightInstance[sortedLights.length];
      int nextSize = 0;
      boolean anyDirty = prevLights.length != sortedLights.length;

      for (int previousIndex = 0; previousIndex < prevLights.length; previousIndex++) {
         LightInstance previous = prevLights[previousIndex];
         int semanticMatchIndex = findSemanticMatch(previous, sortedLights, matchedCurrent);
         if (semanticMatchIndex >= 0) {
            LightInstance current = sortedLights[semanticMatchIndex];
            matchedCurrent[semanticMatchIndex] = true;
            current.setIndex(nextSize);
            nextLights[nextSize] = current;
            this.newLightIndices[previousIndex] = (short) nextSize;
            if (previousIndex == nextSize && previous.active() == current.active()) {
               frameStats.stableMappings++;
            } else {
               anyDirty = true;
               if (previous.active() != current.active()) {
                  frameStats.activityChanges++;
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
            nextLights[nextSize] = current;
            this.newLightIndices[previousIndex] = (short) nextSize;
            anyDirty = true;
            if (previous.blockId() != current.blockId()) {
               frameStats.blockIdChanges++;
            } else if (previous.active() != current.active()) {
               frameStats.activityChanges++;
            } else {
               frameStats.lightInfoChanges++;
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
         ? frameStats.additions + frameStats.removals + frameStats.blockIdChanges + frameStats.lightInfoChanges + frameStats.activityChanges
         : 0;
      this.pendingTracedLightMutations = Math.max(this.pendingTracedLightMutations, remappedMutationCount);
      return anyDirty;
   }

   /**
    * Port of RTXDI's FillNeighborOffsetBuffer (RtxdiUtils.cpp lines 48-69).
    * Generates 8192 R2 low-discrepancy samples within a unit-radius disk, quantized
    * exactly like the SDK into two uint8 entries per neighbor. The GPU side then
    * sign-extends those bytes when reading them as integer offsets.
    * Called once at construction — never per-frame.
    */
   private void fillNeighborOffsets() {
      float phi2 = 1.0f / 1.3247179572447f;
      float u = 0.5f;
      float v = 0.5f;
      int num = 0;
      java.nio.ByteBuffer buf = this.neighborOffsetMemory.getMemory().getBuffer();
      buf.order(java.nio.ByteOrder.nativeOrder());
      while (num < NEIGHBOR_OFFSET_COUNT * 2) {
         u += phi2;
         v += phi2 * phi2;
         if (u >= 1.0f) u -= 1.0f;
         if (v >= 1.0f) v -= 1.0f;
         float rSq = (u - 0.5f) * (u - 0.5f) + (v - 0.5f) * (v - 0.5f);
         if (rSq > 0.25f) continue;
         buf.put(num++, (byte)((u - 0.5f) * 250.0f));
         buf.put(num++, (byte)((v - 0.5f) * 250.0f));
      }
      this.neighborOffsetMemoryManager.queueUpload(this.neighborOffsetMemory);
   }

   public GlMemoryManager getNeighborOffsetMemoryManager() {
      return this.neighborOffsetMemoryManager;
   }

   public boolean upload() {
      boolean uploadDone = true;
      uploadDone &= this.lightsMemoryManager.upload();
      uploadDone &= this.previousLightsMemoryManager.upload();
      uploadDone &= this.lightMappingMemoryManager.upload();
      uploadDone &= this.lightReverseMappingMemoryManager.upload();
      uploadDone &= this.regirCellCountMemoryManager.upload();
      if (!this.gpuRegirBuildEnabled) {
         uploadDone &= this.regirLightIndexMemoryManager.upload();
         uploadDone &= this.regirLightPdfMemoryManager.upload();
         uploadDone &= this.regirCompactLightDataMemoryManager.upload();
      }
      uploadDone &= this.neighborOffsetMemoryManager.upload();
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
         this.syncTracedLight(level, blockPos, level.getBlockState(blockPos));
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
         this.syncTracedLight(level, blockPos, level.getBlockState(blockPos));
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
         this.syncTracedLight(blockPos, blockState, lightInfo);
      } finally {
         this.lock.writeLock().unlock();
      }
   }

   public void synchronizeChunkLights(ClientWorld level, PChunkPos chunkPos) {
      if (ShaderAutomation.suppressWorldMutationIngress()) {
         return;
      }
      this.lock.writeLock().lock();
      try {
         this.loadedLightChunks.add(chunkKey(chunkPos));
         PBlockPos chunkMin = chunkPos.toBlockPos();
         BlockPos.Mutable mutableBlockPos = new BlockPos.Mutable();
         for (int x = 0; x < 16; x++) {
            for (int y = 0; y < 16; y++) {
               for (int z = 0; z < 16; z++) {
                  mutableBlockPos.set(chunkMin.x + x, chunkMin.y + y, chunkMin.z + z);
                  this.syncTracedLight(level, mutableBlockPos, level.getBlockState(mutableBlockPos));
               }
            }
         }
      } finally {
         this.lock.writeLock().unlock();
      }
   }

   public void clearChunkLights(PChunkPos chunkPos) {
      if (ShaderAutomation.suppressWorldMutationIngress()) {
         return;
      }
      this.lock.writeLock().lock();
      try {
         this.loadedLightChunks.remove(chunkKey(chunkPos));
         PBlockPos chunkMin = chunkPos.toBlockPos();
         int maxX = chunkMin.x + 16;
         int maxY = chunkMin.y + 16;
         int maxZ = chunkMin.z + 16;
         boolean removed = false;
         Iterator<Entry<Vector3f, TracedLightPosition>> itr = this.tracedLightPositions.entrySet().iterator();
         while (itr.hasNext()) {
            Entry<Vector3f, TracedLightPosition> entry = itr.next();
            Vector3f pos = entry.getKey();
            if (pos.x >= chunkMin.x && pos.x < maxX && pos.y >= chunkMin.y && pos.y < maxY && pos.z >= chunkMin.z && pos.z < maxZ) {
               itr.remove();
               removed = true;
            }
         }
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

   public int consumePendingTracedLightMutations() {
      int pending = this.pendingTracedLightMutations;
      this.pendingTracedLightMutations = 0;
      return pending;
   }

   public GlMemoryManager getLightsMemoryManager() {
      return this.lightsMemoryManager;
   }

   public GlMemoryManager getPreviousLightsMemoryManager() {
      return this.previousLightsMemoryManager;
   }

   public GlMemoryManager getLightMappingMemoryManager() {
      return this.lightMappingMemoryManager;
   }

   public GlMemoryManager getLightReverseMappingMemoryManager() {
      return this.lightReverseMappingMemoryManager;
   }

   public GlMemoryManager getRegirCellCountMemoryManager() {
      return this.regirCellCountMemoryManager;
   }

   public GlMemoryManager getGlobalLightCdfMemoryManager() {
      return this.globalLightCdfMemoryManager;
   }

   public GlMemoryManager getRegirLightIndexMemoryManager() {
      return this.regirLightIndexMemoryManager;
   }

   public GlMemoryManager getRegirLightPdfMemoryManager() {
      return this.regirLightPdfMemoryManager;
   }

   public GlMemoryManager getRegirCompactLightDataMemoryManager() {
      return this.regirCompactLightDataMemoryManager;
   }

   /** Returns the world-space center of the ReGIR grid (RTXDI: gridCenter = camera position). */
   public Vector3f getRegirGridCenter() {
      Vector3f center = this.resolveRegirGridCenter();
      this.regirGridCenter.set(center);
      return new Vector3f(this.regirGridCenter);
   }

   /** @deprecated Use {@link #getRegirGridCenter()} — kept for backward compatibility. */
   @Deprecated
   public Vector3f getRegirGridOrigin() {
      // Derive origin from center for callers that still need it.
      float halfExtent = this.regirGridResolution * GRID_CELL_SIZE * 0.5f;
      Vector3f center = this.getRegirGridCenter();
      return new Vector3f(
         center.x - halfExtent,
         center.y - halfExtent,
         center.z - halfExtent
      );
   }

   public int getRegirGridResolution() {
      return this.regirGridResolution;
   }

   public int getRegirLightsPerCell() {
      return this.regirLightsPerCell;
   }

   public float getRegirSamplingJitter() {
      String override = System.getProperty("photonics.regirSamplingJitter");
      float jitterInCells = REGIR_SAMPLING_JITTER;
      if (override != null && !override.isBlank()) {
         try {
            jitterInCells = Float.parseFloat(override.trim());
         } catch (NumberFormatException ignored) {
         }
      }

      return Math.max(0.0F, jitterInCells * 2.0F);
   }

   private float getRegirBuildCellRadius() {
      return REGIR_CELL_RADIUS * (this.getRegirSamplingJitter() + 1.0F);
   }

   public int getRegirActiveCellCount() {
      return this.regirActiveCellCount;
   }

   public int getRegirActiveLightSlotCount() {
      return this.regirActiveLightSlotCount;
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

   private LightInstance[] toLightInstanceArray() {
      List<LightInstance> lights = new ArrayList<>(this.tracedLightPositions.size());
      for (Entry<Vector3f, TracedLightPosition> e : this.tracedLightPositions.entrySet()) {
         lights.add(new LightInstance(e.getValue().blockId(), e.getKey(), e.getValue().lightInfo()));
      }
      lights.sort(STABLE_LIGHT_ORDER);
      return lights.toArray(LightInstance[]::new);
   }

   private LightInstance[] toLightInstanceArrayClearUnloaded(ClientWorld level) {
      List<LightInstance> lights = new ArrayList<>(this.tracedLightPositions.size());
      Iterator<Entry<Vector3f, TracedLightPosition>> itr = this.tracedLightPositions.entrySet().iterator();
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
            lights.add(new LightInstance(tracedPos.blockId(), pos, tracedPos.lightInfo()));
         }
      }
      lights.sort(STABLE_LIGHT_ORDER);
      return lights.toArray(LightInstance[]::new);
   }

   @Override
   public void free() {
      this.lightsMemoryManager.free();
      this.previousLightsMemoryManager.free();
      this.lightMappingMemoryManager.free();
      this.lightReverseMappingMemoryManager.free();
      this.globalLightCdfMemoryManager.free();
      this.regirCellCountMemoryManager.free();
      this.regirLightIndexMemoryManager.free();
      this.regirLightPdfMemoryManager.free();
      this.regirCompactLightDataMemoryManager.free();
      this.neighborOffsetMemoryManager.free();
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
      this.lightsMemoryManager = this.replaceManager(this.lightsMemoryManager, "ph_light_list", newCapacity * LIGHT_BYTE_SIZE + 4, true, this.lightsMemory, true, owner -> this.lightsMemory = owner);
      this.previousLightsMemoryManager = this.replaceManager(this.previousLightsMemoryManager, "ph_light_list_previous", newCapacity * LIGHT_BYTE_SIZE + 4, true, this.previousLightsMemory, true, owner -> this.previousLightsMemory = owner);
      this.lightMappingMemoryManager = this.replaceManager(this.lightMappingMemoryManager, "ph_light_list_mapping", newCapacity * Integer.BYTES, false, this.lightMappingMemory, false, owner -> this.lightMappingMemory = owner);
      this.lightReverseMappingMemoryManager = this.replaceManager(this.lightReverseMappingMemoryManager, "ph_light_reverse_mapping", newCapacity * Integer.BYTES, false, this.lightReverseMappingMemory, false, owner -> this.lightReverseMappingMemory = owner);
      this.globalLightCdfMemoryManager = this.replaceManager(this.globalLightCdfMemoryManager, "ph_global_light_cdf", newCapacity * Float.BYTES, false, this.globalLightCdfMemory, false, owner -> this.globalLightCdfMemory = owner);
      this.newLightIndices = Arrays.copyOf(this.newLightIndices, newCapacity);
      this.lightCapacity = newCapacity;
      this.identityLightMappingPending = true;
      this.tracedLightSetDirty = true;
      Photonic.info("[LightRegistry] Resized traced-light capacity from {} to {}", previousCapacity, newCapacity);
   }

   private GlMemoryManager replaceManager(
      GlMemoryManager previousManager,
      String name,
      int byteSize,
      boolean staticData,
      MemoryOwner previousOwner,
      boolean preserveContents,
      java.util.function.Consumer<SimpleMemoryOwner> ownerSetter
   ) {
      GlMemoryManager manager = new GlMemoryManager(GlTarget.SSBO, name, byteSize, staticData);
      SimpleMemoryOwner owner = new SimpleMemoryOwner(manager, manager.getCapacity());
      if (preserveContents && previousOwner != null && previousOwner.getMemory() != null) {
         copyMemory(previousOwner.getMemory(), owner.getMemory());
      }
      ownerSetter.accept(owner);
      if (previousManager != null) {
         previousManager.free();
      }
      return manager;
   }

   private static void copyMemory(MemoryRegion src, MemoryRegion dst) {
      java.nio.ByteBuffer srcBuffer = src.getBuffer();
      java.nio.ByteBuffer dstBuffer = dst.getBuffer();
      int copyLength = Math.min(srcBuffer.capacity(), dstBuffer.capacity());
      srcBuffer.position(0);
      srcBuffer.limit(copyLength);
      dstBuffer.position(0);
      dstBuffer.put(srcBuffer);
      dstBuffer.position(0);
      dstBuffer.limit(dstBuffer.capacity());
   }

   private void syncTracedLight(ClientWorld level, BlockPos blockPos, BlockState blockState) {
      if (!level.isChunkLoaded(blockPos)) {
         return;
      }

      BlockLightInfo lightInfo = this.resolveLightInfo(blockPos, blockState, level);
      this.syncTracedLight(blockPos, blockState, lightInfo);
   }

   private void syncTracedLight(BlockPos blockPos, BlockState blockState, BlockLightInfo lightInfo) {
      Vector3f lightPos = new Vector3f(blockPos.getX() + 0.5F, blockPos.getY() + 0.5F, blockPos.getZ() + 0.5F);
      TracedLightPosition previous = this.tracedLightPositions.get(lightPos);
      if (lightInfo == null) {
         if (previous != null && this.isTrackedChunkLoaded(blockPos) && this.tracedLightPositions.remove(lightPos, previous)) {
            this.logLightMutation(DirtyReason.REMOVED_NO_LIGHT, blockPos, blockState, previous, null);
            this.noteTracedLightMutation(DirtyReason.REMOVED_NO_LIGHT, blockPos, previous, null);
         }
         return;
      }

      // Keep traced-light activity stable. RTXDI and the original local implementation do
      // not toggle emitters active/inactive based on enclosure culling, and doing so here
      // churns the light buffer and ReGIR state during pure camera motion.
      boolean tracedVisible = lightInfo.isTraced();
      if (!tracedVisible) {
         if (previous != null && this.tracedLightPositions.remove(lightPos, previous)) {
            DirtyReason reason = lightInfo.isTraced() ? DirtyReason.CULLED : DirtyReason.REMOVED_NO_LIGHT;
            this.logLightMutation(reason, blockPos, blockState, previous, null);
            this.noteTracedLightMutation(reason, blockPos, previous, null);
         }
         return;
      }

      int blockId = IrisUtil.getBlockId(blockState);
      TracedLightPosition updated = new TracedLightPosition(blockId, lightInfo);
      if (previous == null) {
         TracedLightPosition raced = this.tracedLightPositions.putIfAbsent(lightPos, updated);
         if (raced == null) {
            this.logLightMutation(DirtyReason.ADDED, blockPos, blockState, null, updated);
            this.noteTracedLightMutation(DirtyReason.ADDED, blockPos, null, updated);
            return;
         }
         previous = raced;
      }

      if (sameLightDescriptor(previous, blockId, lightInfo)) {
         this.churnStats.noteNoopSync();
         return;
      }

      if (this.tracedLightPositions.replace(lightPos, previous, updated)) {
         DirtyReason reason = previous.blockId() != blockId ? DirtyReason.BLOCK_ID_CHANGED : DirtyReason.LIGHT_INFO_CHANGED;
         this.logLightMutation(reason, blockPos, blockState, previous, updated);
         this.noteTracedLightMutation(reason, blockPos, previous, updated);
      }
   }

   private void logLightMutation(DirtyReason reason, BlockPos blockPos, BlockState blockState, TracedLightPosition previous, TracedLightPosition updated) {
      if (!PhotonicsStorage.PROFILER_ENABLED.value || !Photonic.automationEnabled() || this.mutationDebugLogsRemaining <= 0) {
         return;
      }

      this.mutationDebugLogsRemaining--;
      Photonic.info(
         "[Profiler] lightMutation: reason={} pos=({}, {}, {}) state={} prev={} next={}",
         reason,
         blockPos.getX(),
         blockPos.getY(),
         blockPos.getZ(),
         blockState,
         previous == null ? "null" : previous.blockId() + "/" + System.identityHashCode(previous.lightInfo()),
         updated == null ? "null" : updated.blockId() + "/" + System.identityHashCode(updated.lightInfo())
      );
   }

   private static long gridKey(int gx, int gy, int gz) {
      return ((long) gx & 0xFFFFF) | (((long) gy & 0xFFFFF) << 20) | (((long) gz & 0xFFFFF) << 40);
   }

   private void noteTracedLightMutation(DirtyReason reason, BlockPos blockPos, TracedLightPosition previous, TracedLightPosition updated) {
      this.tracedLightSetDirty = true;
      this.pendingTracedLightMutations++;
      this.churnStats.noteMutation(reason, blockPos, previous, updated);
   }

   private static long chunkKey(int chunkX, int chunkY, int chunkZ) {
      return (((long) chunkX) & 0x1FFFFFL)
         | ((((long) chunkY) & 0x1FFFFFL) << 21)
         | ((((long) chunkZ) & 0x1FFFFFL) << 42);
   }

   private static long chunkKey(PChunkPos chunkPos) {
      return chunkKey(chunkPos.x, chunkPos.y, chunkPos.z);
   }

   private static long chunkKey(BlockPos blockPos) {
      return chunkKey(blockPos.getX() >> 4, blockPos.getY() >> 4, blockPos.getZ() >> 4);
   }

   private boolean isTrackedChunkLoaded(BlockPos blockPos) {
      return this.loadedLightChunks.contains(chunkKey(blockPos));
   }

   public String describeRecentChurn() {
      return this.churnStats.describe();
   }

   private void buildSpatialGrid(LightInstance[] lights) {
      this.lightGrid = new HashMap<>(lights.length * 4);
      this.lightGridAssignments = 0;
      float regirBuildCellRadius = this.getRegirBuildCellRadius();
      for (int i = 0; i < lights.length; i++) {
         LightInstance light = lights[i];
         if (!light.active()) {
            continue;
         }
         Vector3f pos = light.position();
         float lightRadius = Math.max(light.type().radiusInBlocks(), 0.0F);
         float coverageRadius = lightRadius + regirBuildCellRadius;
         int minGx = (int) Math.floor((pos.x - coverageRadius) / GRID_CELL_SIZE);
         int minGy = (int) Math.floor((pos.y - coverageRadius) / GRID_CELL_SIZE);
         int minGz = (int) Math.floor((pos.z - coverageRadius) / GRID_CELL_SIZE);
         int maxGx = (int) Math.floor((pos.x + coverageRadius) / GRID_CELL_SIZE);
         int maxGy = (int) Math.floor((pos.y + coverageRadius) / GRID_CELL_SIZE);
         int maxGz = (int) Math.floor((pos.z + coverageRadius) / GRID_CELL_SIZE);
         for (int gx = minGx; gx <= maxGx; gx++) {
            for (int gy = minGy; gy <= maxGy; gy++) {
               for (int gz = minGz; gz <= maxGz; gz++) {
                  this.lightGrid.computeIfAbsent(gridKey(gx, gy, gz), k -> new ArrayList<>(8)).add(i);
                  this.lightGridAssignments++;
               }
            }
         }
      }
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
      LIGHT_INFO_CHANGED
   }

   private static final class LightChurnStats {
      private static final int MAX_SAMPLES = 4;
      private final EnumMap<DirtyReason, LongAdder> mutationCounts = new EnumMap<>(DirtyReason.class);
      private final Map<DirtyReason, String> samples = new LinkedHashMap<>();
      private boolean samplesTruncated = false;
      private final LongAdder noopSyncs = new LongAdder();
      private volatile Frame lastFrame = new Frame(0, 0);

      private LightChurnStats() {
         for (DirtyReason reason : DirtyReason.values()) {
            this.mutationCounts.put(reason, new LongAdder());
         }
      }

      private Frame beginFrame(int previousCount, int gatheredCount) {
         Frame frame = new Frame(previousCount, gatheredCount);
         this.lastFrame = frame;
         return frame;
      }

      private void noteMutation(DirtyReason reason, BlockPos blockPos, TracedLightPosition previous, TracedLightPosition updated) {
         this.mutationCounts.get(reason).increment();
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

      private String describe() {
         Frame frame = this.lastFrame;
         return String.format(
            "frame(prev=%d,gathered=%d,stable=%d,added=%d,removed=%d,blockId=%d,lightInfo=%d,activity=%d) mutations(add=%d,remove=%d,cull=%d,blockId=%d,lightInfo=%d,noop=%d)%s",
            frame.previousCount,
            frame.gatheredCount,
            frame.stableMappings,
            frame.additions,
            frame.removals,
            frame.blockIdChanges,
            frame.lightInfoChanges,
            frame.activityChanges,
            this.mutationCounts.get(DirtyReason.ADDED).sum(),
            this.mutationCounts.get(DirtyReason.REMOVED_NO_LIGHT).sum(),
            this.mutationCounts.get(DirtyReason.CULLED).sum(),
            this.mutationCounts.get(DirtyReason.BLOCK_ID_CHANGED).sum(),
            this.mutationCounts.get(DirtyReason.LIGHT_INFO_CHANGED).sum(),
            this.noopSyncs.sum(),
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



