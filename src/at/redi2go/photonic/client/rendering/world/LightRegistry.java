package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.PhotonicsStorage;
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
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.SimpleMemoryOwner;
import at.redi2go.photonic.client.rendering.world.position.PBlockPos;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import it.unimi.dsi.fastutil.objects.Object2ObjectOpenHashMap;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.HashMap;
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
   private static final float MIN_NODE_LUMINANCE = 0.001F;
   private static final int GRID_CELL_SIZE = 32;
   private static final int INCREMENTAL_PARALLEL_THRESHOLD = 32;
   private static final float MIN_TRACED_LIGHT_SELECTION_LUMA = 0.0025F;
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
   // Dense scenes can have many lights with nearly identical view scores; keep
   // the capped top-N set sticky until a challenger is meaningfully better.
   private static final float LIGHT_SELECTION_RETENTION_RATIO = 0.85F;

   private static float selectionCameraScore(LightInstance light, Vector3f cameraPosition) {
      return light.type().luminanceFrom(light.position(), cameraPosition);
   }

   private static float selectionSourceScore(LightInstance light) {
      return light.type().luminanceFrom(light.position(), light.position());
   }

   private static LightSelectionCandidate createSelectionCandidate(
      LightInstance light,
      Vector3f cameraPosition,
      Set<LightInstance> previouslySelected
   ) {
      return new LightSelectionCandidate(
         light,
         selectionCameraScore(light, cameraPosition),
         selectionSourceScore(light),
         previouslySelected.contains(light)
      );
   }

   private static int compareLightSelectionOrder(LightSelectionCandidate a, LightSelectionCandidate b) {
      int cmp = Float.compare(b.cameraScore(), a.cameraScore());
      if (cmp != 0) return cmp;
      cmp = Float.compare(b.sourceScore(), a.sourceScore());
      if (cmp != 0) return cmp;
      return STABLE_LIGHT_ORDER.compare(a.light(), b.light());
   }

   private static LightInstance[] selectTracedLights(List<LightSelectionCandidate> candidates, int maxLights) {
      if (candidates.size() <= maxLights) {
         return candidates.stream().map(LightSelectionCandidate::light).sorted(STABLE_LIGHT_ORDER).toArray(LightInstance[]::new);
      }

      candidates.sort(LightRegistry::compareLightSelectionOrder);
      float admissionScore = candidates.get(maxLights - 1).cameraScore();
      List<LightSelectionCandidate> selected = new ArrayList<>(maxLights);
      Set<LightInstance> retainedLights = new HashSet<>();
      for (LightSelectionCandidate candidate : candidates) {
         if (!candidate.previouslySelected() || candidate.cameraScore() < admissionScore * LIGHT_SELECTION_RETENTION_RATIO) {
            continue;
         }
         selected.add(candidate);
         retainedLights.add(candidate.light());
         if (selected.size() == maxLights) {
            return selected.stream().map(LightSelectionCandidate::light).sorted(STABLE_LIGHT_ORDER).toArray(LightInstance[]::new);
         }
      }

      for (LightSelectionCandidate candidate : candidates) {
         if (retainedLights.contains(candidate.light())) {
            continue;
         }
         selected.add(candidate);
         if (selected.size() == maxLights) {
            break;
         }
      }

      return selected.stream().map(LightSelectionCandidate::light).sorted(STABLE_LIGHT_ORDER).toArray(LightInstance[]::new);
   }

   private record LightSelectionCandidate(LightInstance light, float cameraScore, float sourceScore, boolean previouslySelected) {
   }

   private static Vector3f getLightSelectionCameraPosition() {
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

   private final GlMemoryManager lightsMemoryManager;
   private final MemoryOwner lightsMemory;
   private final GlMemoryManager lightMappingMemoryManager;
   private final MemoryOwner lightMappingMemory;
   private final GlMemoryManager lightTreeMemoryManager;
   private final MemoryOwner lightTreeMemory;
   private final GlMemoryManager lightTreeIndicesMemoryManager;
   private final MemoryOwner lightTreeIndicesMemory;
   private final int maxLights;
   private final int maxLightsPerNode;
   private final int nodeSize;
   private final int worldSize;
   private final int nodeCount;
   private short[] newLightIndices;
   private PBlockPos offset = new PBlockPos(0, 0, 0);
   private int lightCount = 0;
   private int lightTreeNodeCount = 0;
   private int lightTreeIndexCount = 0;
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
   private boolean loggedAutomationLightColors = false;
   private boolean lastCompileTopologyResetRecommended = true;
   private int pendingTracedLightMutations = 0;
   private LightTreeDiagnostics lightTreeDiagnostics = LightTreeDiagnostics.empty();
   private int lightTreeRebuildCount = 0;
   private int lastLightTreeRebuildCompileCount = -1;
   private long lastTreeBuildNanos = 0;

   public LightRegistry(int maxLights, int maxLightsPerNode, float minTracedLightSelectionLuma, int nodeSize, int worldSize) {
      if (16 % nodeSize != 0) {
         throw new IllegalArgumentException();
      }
      this.maxLights = maxLights;
      this.maxLightsPerNode = maxLightsPerNode;
      this.nodeSize = nodeSize;
      this.worldSize = worldSize;
      this.nodeCount = worldSize / nodeSize;
      this.newLightIndices = new short[maxLights];
      this.lightsMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_light_list", maxLights * LIGHT_BYTE_SIZE + 4, true);
      this.lightsMemory = new SimpleMemoryOwner(this.lightsMemoryManager, this.lightsMemoryManager.getCapacity());
      this.lightMappingMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_light_list_mapping", maxLights * 4, false);
      this.lightMappingMemory = new SimpleMemoryOwner(this.lightMappingMemoryManager, this.lightMappingMemoryManager.getCapacity());
      int maxTreeNodes = Math.max(2 * maxLights, 1);
      int treeByteSize = maxTreeNodes * 16 * Float.BYTES;
      this.lightTreeMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_light_tree", treeByteSize, false);
      this.lightTreeMemory = new SimpleMemoryOwner(this.lightTreeMemoryManager, this.lightTreeMemoryManager.getCapacity());
      int indexByteSize = Math.max(maxLights, 1) * Integer.BYTES;
      this.lightTreeIndicesMemoryManager = new GlMemoryManager(GlTarget.SSBO, "ph_light_tree_indices", indexByteSize, false);
      this.lightTreeIndicesMemory = new SimpleMemoryOwner(this.lightTreeIndicesMemoryManager, this.lightTreeIndicesMemoryManager.getCapacity());
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

   public void compileRegistry(PBlockPos blockOffset, PBlockPos previousOffset, boolean forceFullRebuild) {
      if (this.building) {
         throw new IllegalStateException();
      }
      ClientWorld level = MinecraftAccessor.getLevel();
      if (level == null) {
         return;
      }
      this.building = true;
      boolean profiling = PhotonicsStorage.PROFILER_ENABLED.value;
      long t0 = profiling ? System.nanoTime() : 0;
      long tGather = t0;
      long tDiff = t0;
      long tGrid = t0;
      long tNodes = t0;
      long tStore = t0;
      int previousLightCount = this.tracedLights.length;
      boolean offsetChanged = !blockOffset.equals(previousOffset);
      try {
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
         if (profiling) {
            tGather = System.nanoTime();
         }

         boolean lightsChanged = this.createTracedLights(lights);
         this.lastCompileTopologyResetRecommended = !forceFullRebuild || lightsChanged;
         if (profiling) {
            tDiff = System.nanoTime();
         }
         if (lightsChanged || this.lightGrid == null) {
            this.buildSpatialGrid(this.tracedLights);
         }
         if (profiling) {
            tGrid = System.nanoTime();
            tNodes = tGrid;
         }

         boolean identityQueued = false;
         if (lightsChanged) {
            this.storeLights();
            this.storeLightMappings();
            this.buildLightTree();
            this.lightsMemoryManager.queueUpload(this.lightsMemory);
            this.lightMappingMemoryManager.queueUpload(this.lightMappingMemory);
            this.lightTreeMemoryManager.queueUpload(this.lightTreeMemory);
            this.lightTreeIndicesMemoryManager.queueUpload(this.lightTreeIndicesMemory);
            this.identityLightMappingPending = true;
         } else {
            identityQueued = this.queueIdentityLightMappingsIfNeeded();
         }
         if (profiling) {
            tStore = System.nanoTime();
            String rebuildReason;
            if (forceFullRebuild) {
               rebuildReason = "topology";
            } else if (offsetChanged) {
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
            long nodesMs = (tNodes - tGrid) / 1_000_000L;
            long storeMs = (tStore - tNodes) / 1_000_000L;
            Photonic.info(
               "[Profiler] lightRegistry: reason={} prevLights={} gatheredLights={} tracedLights={} changed={} offsetChanged={} gridCells={} gridAssignments={} churn={} uploads(lights={},mapping={},identity={}) timings: gather={}ms diff={}ms grid={}ms nodes={}ms store={}ms total={}ms",
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
               identityQueued,
               gatherMs,
               diffMs,
               gridMs,
               nodesMs,
               storeMs,
               totalMs
            );
            if (lightsChanged) {
               Photonic.info(
                  "[Profiler] treeRebuild: lights={} nodes={} indices={} buildTimeUs={} rebuilds={} compileCount={} churn={}",
                  this.tracedLights.length,
                  this.lightTreeNodeCount,
                  this.lightTreeIndexCount,
                  this.lastTreeBuildNanos / 1000L,
                  this.lightTreeRebuildCount,
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
      FloatBuffer buffer = this.lightsMemory.getMemory().getBuffer().asFloatBuffer();
      Vector3f colorSum = Photonic.automationEnabled() && !this.loggedAutomationLightColors ? new Vector3f() : null;
      StringBuilder sampleLights = Photonic.automationEnabled() && !this.loggedAutomationLightColors ? new StringBuilder() : null;
      int sampledLights = 0;
      for (LightInstance light : this.tracedLights) {
         buffer.position(16 * light.index());
         BlockLightInfo lightInfo = light.type();
         Vector3f rawColor = lightInfo.getRawColorAsVector();
         float lightIntensity = lightInfo.adjustedIntensity();
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
         Photonic.info("[LightDebug] tracedLights={} treeNodes={} treeIndices={} lights:{}",
            this.tracedLights.length, this.lightTreeNodeCount, this.lightTreeIndexCount, debugLights);
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
      for (int i = 0; i < this.maxLights; i++) {
         buffer.put(i, this.newLightIndices[i]);
      }
   }

   private void storeIdentityLightMappings() {
      IntBuffer buffer = this.lightMappingMemory.getMemory().getBuffer().asIntBuffer();
      for (int i = 0; i < this.maxLights; i++) {
         buffer.put(i, i);
      }
   }

   private void buildLightTree() {
      this.lightTreeNodeCount = 0;
      this.lightTreeIndexCount = 0;
      this.lightTreeDiagnostics = LightTreeDiagnostics.empty();
      this.lastTreeBuildNanos = 0;
      if (this.tracedLights.length == 0) {
         return;
      }

      long t0 = System.nanoTime();
      LightTreeBuilder builder = new LightTreeBuilder(this.tracedLights);
      this.lightTreeNodeCount = builder.build();
      this.lightTreeIndexCount = builder.getLeafIndexCount();
      if (this.lightTreeNodeCount == 0) {
         this.lastTreeBuildNanos = System.nanoTime() - t0;
         return;
      }

      this.storeLightTreeNodes(builder);
      this.storeLightTreeIndices(builder);
      this.lightTreeRebuildCount++;
      this.lastLightTreeRebuildCompileCount = this.compileCount;
      this.lastTreeBuildNanos = System.nanoTime() - t0;
      this.lightTreeDiagnostics = LightTreeDiagnostics.fromBuild(builder, this.lightTreeRebuildCount, this.lastLightTreeRebuildCompileCount, this.lastTreeBuildNanos);
   }

   private void storeLightTreeNodes(LightTreeBuilder builder) {
      this.validateLightTreeCapacity(builder.getNodeDataLength() * Float.BYTES, this.lightTreeMemoryManager.getCapacity(), "node");
      FloatBuffer buffer = this.lightTreeMemory.getMemory().getBuffer().asFloatBuffer();
      int floatCount = builder.getNodeDataLength();
      for (int i = 0; i < floatCount; i++) {
         buffer.put(i, builder.getNodeData()[i]);
      }
   }

   private void storeLightTreeIndices(LightTreeBuilder builder) {
      this.validateLightTreeCapacity(builder.getLeafIndexCount() * Integer.BYTES, this.lightTreeIndicesMemoryManager.getCapacity(), "index");
      IntBuffer buffer = this.lightTreeIndicesMemory.getMemory().getBuffer().asIntBuffer();
      int indexCount = builder.getLeafIndexCount();
      for (int i = 0; i < indexCount; i++) {
         buffer.put(i, builder.getLeafIndices()[i]);
      }
   }

   private void validateLightTreeCapacity(int requiredBytes, int availableBytes, String bufferName) {
      if (requiredBytes <= availableBytes) {
         return;
      }
      throw new IllegalStateException(
         "Preallocated light tree " + bufferName + " buffer is too small: required=" + requiredBytes + ", available=" + availableBytes
      );
   }

   boolean queueIdentityLightMappingsIfNeeded() {
      if (!this.identityLightMappingPending) {
         return false;
      }
      this.storeIdentityLightMappings();
      this.lightMappingMemoryManager.queueUpload(this.lightMappingMemory);
      this.identityLightMappingPending = false;
      return true;
   }

   private boolean createTracedLights(LightInstance[] lights) {
      Arrays.fill(this.newLightIndices, (short) -1);
      LightInstance[] prevLights = this.tracedLights;
      LightChurnStats.Frame frameStats = this.churnStats.beginFrame(prevLights.length, lights.length);
      Vector3f cameraPosition = getLightSelectionCameraPosition();
      Set<LightInstance> previouslySelected = new HashSet<>(Arrays.asList(prevLights));
      if (lights.length > 0) {
         // Include ALL lights in the tree per Conty & Kulla 2018.
         // The tree's importance-weighted traversal handles distant/dim lights efficiently
         // without needing camera-based pre-filtering that causes temporal instability.
         if (lights.length > this.maxLights) {
            List<LightSelectionCandidate> candidates = new ArrayList<>(lights.length);
            for (LightInstance light : lights) {
               LightSelectionCandidate candidate = createSelectionCandidate(light, cameraPosition, previouslySelected);
               candidates.add(candidate);
            }
            lights = selectTracedLights(candidates, this.maxLights);
         }
      }
      Object2ObjectOpenHashMap<Vector3f, LightInvalidation> differences = new Object2ObjectOpenHashMap<>(
         Math.max(lights.length, prevLights.length)
      );

      for (int i = 0; i < prevLights.length; i++) {
         LightInstance light = prevLights[i];
         LightInvalidation diff = differences.computeIfAbsent(light.position(), LightInvalidation::new);
         diff.before = light.type();
         diff.beforeBlockId = light.blockId();
         diff.beforeIndex = i;
      }

      for (int i = 0; i < lights.length; i++) {
         LightInstance light = lights[i];
         LightInvalidation diff = differences.computeIfAbsent(light.position(), LightInvalidation::new);
         diff.after = light.type();
         diff.afterBlockId = light.blockId();
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
         if (before == after && diff.beforeBlockId == diff.afterBlockId) {
            this.newLightIndices[beforeIndex] = (short) afterIndex;
            frameStats.stableMappings++;
         } else {
            anyDirty = true;
            if (before == null) {
               frameStats.additions++;
            } else if (after == null) {
               frameStats.removals++;
            } else if (diff.beforeBlockId != diff.afterBlockId) {
               frameStats.blockIdChanges++;
            } else {
               frameStats.lightInfoChanges++;
            }
         }
      }

      this.tracedLights = lights;
      this.pendingTracedLightMutations = anyDirty ? frameStats.additions + frameStats.removals + frameStats.blockIdChanges + frameStats.lightInfoChanges : 0;
      return anyDirty;
   }

   public boolean upload() {
      boolean uploadDone = true;
      uploadDone &= this.lightsMemoryManager.upload();
      uploadDone &= this.lightMappingMemoryManager.upload();
      uploadDone &= this.lightTreeMemoryManager.upload();
      uploadDone &= this.lightTreeIndicesMemoryManager.upload();
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

   public void synchronizeChunkLights(ClientWorld level, PChunkPos chunkPos) {
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

   public boolean consumeLastCompileTopologyResetRecommended() {
      boolean recommended = this.lastCompileTopologyResetRecommended;
      this.lastCompileTopologyResetRecommended = true;
      return recommended;
   }

   public GlMemoryManager getLightsMemoryManager() {
      return this.lightsMemoryManager;
   }

   public GlMemoryManager getLightMappingMemoryManager() {
      return this.lightMappingMemoryManager;
   }

   public GlMemoryManager getLightTreeMemoryManager() {
      return this.lightTreeMemoryManager;
   }

   public GlMemoryManager getLightTreeIndicesMemoryManager() {
      return this.lightTreeIndicesMemoryManager;
   }

   public int getLightTreeNodeCount() {
      return this.lightTreeNodeCount;
   }

   public LightTreeDiagnostics getLightTreeDiagnostics() {
      return this.lightTreeDiagnostics;
   }

   public long getLastTreeBuildNanos() {
      return this.lastTreeBuildNanos;
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
         if (!this.isTrackedChunkLoaded(blockPos) || !level.isChunkLoaded(blockPos)) {
            itr.remove();
            this.tracedLightSetDirty = true;
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
      this.lightMappingMemoryManager.free();
      this.lightTreeMemoryManager.free();
      this.lightTreeIndicesMemoryManager.free();
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

   private void syncTracedLight(ClientWorld level, BlockPos blockPos, BlockState blockState) {
      BlockLightInfo lightInfo = this.lightList.get(blockState);
      Vector3f lightPos = new Vector3f(blockPos.getX() + 0.5F, blockPos.getY() + 0.5F, blockPos.getZ() + 0.5F);
      TracedLightPosition previous = this.tracedLightPositions.get(lightPos);
      if (lightInfo == null) {
         if (previous != null && this.isTrackedChunkLoaded(blockPos) && this.tracedLightPositions.remove(lightPos, previous)) {
            this.noteTracedLightMutation(DirtyReason.REMOVED_NO_LIGHT, blockPos, previous, null);
         }
         return;
      }

      boolean tracedVisible = lightInfo.isTraced() && !shouldCull(level, blockPos);
      if (!tracedVisible) {
         if (previous != null && this.tracedLightPositions.remove(lightPos, previous)) {
            this.noteTracedLightMutation(lightInfo.isTraced() ? DirtyReason.CULLED : DirtyReason.REMOVED_NO_LIGHT, blockPos, previous, null);
         }
         return;
      }

      int blockId = IrisUtil.getBlockId(blockState);
      TracedLightPosition updated = new TracedLightPosition(blockId, lightInfo);
      if (previous == null) {
         TracedLightPosition raced = this.tracedLightPositions.putIfAbsent(lightPos, updated);
         if (raced == null) {
            this.noteTracedLightMutation(DirtyReason.ADDED, blockPos, null, updated);
            return;
         }
         previous = raced;
      }

      if (previous.blockId() == blockId && previous.lightInfo() == lightInfo) {
         this.churnStats.noteNoopSync();
         return;
      }

      if (this.tracedLightPositions.replace(lightPos, previous, updated)) {
         DirtyReason reason = previous.blockId() != blockId ? DirtyReason.BLOCK_ID_CHANGED : DirtyReason.LIGHT_INFO_CHANGED;
         this.noteTracedLightMutation(reason, blockPos, previous, updated);
      }
   }

   private static long gridKey(int gx, int gy, int gz) {
      return ((long) gx & 0xFFFFF) | (((long) gy & 0xFFFFF) << 20) | (((long) gz & 0xFFFFF) << 40);
   }

   private void noteTracedLightMutation(DirtyReason reason, BlockPos blockPos, TracedLightPosition previous, TracedLightPosition updated) {
      this.tracedLightSetDirty = true;
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
      for (int i = 0; i < lights.length; i++) {
         LightInstance light = lights[i];
         Vector3f pos = light.position();
         float radius = light.type().radiusInBlocks();
         int minGx = (int) Math.floor((pos.x - radius) / GRID_CELL_SIZE);
         int minGy = (int) Math.floor((pos.y - radius) / GRID_CELL_SIZE);
         int minGz = (int) Math.floor((pos.z - radius) / GRID_CELL_SIZE);
         int maxGx = (int) Math.floor((pos.x + radius) / GRID_CELL_SIZE);
         int maxGy = (int) Math.floor((pos.y + radius) / GRID_CELL_SIZE);
         int maxGz = (int) Math.floor((pos.z + radius) / GRID_CELL_SIZE);
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

   private static final class LightTreeBuilder {
      private static final int nodeFloatSize = 16;
      private static final int maxLeafLights = 4;
      private static final int saohBinCount = 12;
      private static final float luminanceRed = 0.2126F;
      private static final float luminanceGreen = 0.7152F;
      private static final float luminanceBlue = 0.0722F;
      private static final float twoPi = (float) (Math.PI * 2.0);
      private static final float halfPi = (float) (Math.PI * 0.5);
      private static final float epsilon = 1.0E-4F;
      private final LightInstance[] lights;
      private final int[] indices;
      private final float[] nodeData;
      private final int[] leafIndices;
      private int nodeCount;
      private int leafIndexCount;

      private LightTreeBuilder(LightInstance[] lights) {
         this.lights = lights;
         this.indices = new int[lights.length];
         for (int i = 0; i < lights.length; i++) {
            this.indices[i] = i;
         }
         int maxNodeCount = Math.max(2 * lights.length, 1);
         this.nodeData = new float[maxNodeCount * nodeFloatSize];
         this.leafIndices = new int[lights.length];
      }

      private int build() {
         this.nodeCount = 0;
         this.leafIndexCount = 0;
         if (this.lights.length == 0) {
            return 0;
         }
         this.buildRecursive(0, this.lights.length, 0);
         return this.nodeCount;
      }

      private int buildRecursive(int start, int end, int depth) {
         int nodeIndex = this.nodeCount++;
         int count = end - start;
         int subtreeStart = this.leafIndexCount;
         NodeBounds bounds = this.calculateNodeBounds(start, end);
         int offset = nodeIndex * nodeFloatSize;
         this.storeNodeBounds(offset, bounds, depth, subtreeStart, count);
         if (count <= maxLeafLights) {
            this.storeLeaf(offset, start, count, bounds.representativeLightIndex);
            return nodeIndex;
         }

         SplitResult split = this.findBestSplit(start, end, bounds);
         int axis = split == null ? selectSplitAxis(bounds) : split.axis;
         float splitPos = split == null ? bounds.getMidpoint(axis) : split.position;
         int mid = this.partition(start, end, axis, splitPos);
         if (mid == start || mid == end) {
            mid = (start + end) >>> 1;
         }

         int leftChild = this.buildRecursive(start, mid, depth + 1);
         int rightChild = this.buildRecursive(mid, end, depth + 1);
         this.nodeData[offset + 3] = Float.intBitsToFloat(leftChild);
         this.nodeData[offset + 7] = Float.intBitsToFloat(rightChild);
         return nodeIndex;
      }

      private SplitResult findBestSplit(int start, int end, NodeBounds parentBounds) {
         SplitResult best = null;
         for (int axis = 0; axis < 3; axis++) {
            SplitResult candidate = this.findBestSplitOnAxis(start, end, axis, parentBounds);
            if (candidate == null) {
               continue;
            }
            if (best == null || candidate.cost < best.cost) {
               best = candidate;
            }
         }
         return best;
      }

      private SplitResult findBestSplitOnAxis(int start, int end, int axis, NodeBounds parentBounds) {
         int count = end - start;
         if (count <= 1) {
            return null;
         }

         float min = parentBounds.getMin(axis);
         float max = parentBounds.getMax(axis);
         float extent = max - min;
         if (!(extent > epsilon)) {
            return null;
         }

         float bestCost = Float.POSITIVE_INFINITY;
         float bestPosition = Float.NaN;
         for (int bin = 1; bin < saohBinCount; bin++) {
            float t = (float) bin / (float) saohBinCount;
            float position = min + extent * t;
            int mid = this.partition(start, end, axis, position);
            if (mid == start || mid == end) {
               continue;
            }
            NodeBounds leftBounds = this.calculateNodeBounds(start, mid);
            NodeBounds rightBounds = this.calculateNodeBounds(mid, end);
            float splitCost = this.computeSplitCost(axis, parentBounds, leftBounds, rightBounds);
            if (splitCost < parentBounds.totalIntensity && splitCost < bestCost) {
               bestCost = splitCost;
               bestPosition = position;
            }
         }
         return Float.isNaN(bestPosition) ? null : new SplitResult(axis, bestPosition, bestCost);
      }

      private float computeSplitCost(int axis, NodeBounds parentBounds, NodeBounds leftBounds, NodeBounds rightBounds) {
         float parentSpatial = Math.max(parentBounds.surfaceArea(), epsilon);
         float parentOrientation = Math.max(parentBounds.orientationMeasure(), epsilon);
         float axisPenalty = parentBounds.axisRegularization(axis);
         float leftCost = leftBounds.totalIntensity * leftBounds.surfaceArea() * leftBounds.orientationMeasure();
         float rightCost = rightBounds.totalIntensity * rightBounds.surfaceArea() * rightBounds.orientationMeasure();
         return axisPenalty * (leftCost + rightCost) / (parentSpatial * parentOrientation);
      }

      private NodeBounds calculateNodeBounds(int start, int end) {
         NodeBounds bounds = null;
         for (int i = start; i < end; i++) {
            int lightIndex = this.indices[i];
            NodeBounds lightBounds = this.createLeafBounds(this.lights[lightIndex], lightIndex);
            bounds = bounds == null ? lightBounds : bounds.union(lightBounds);
         }
         return bounds == null ? NodeBounds.empty() : bounds;
      }

      private NodeBounds createLeafBounds(LightInstance light, int representativeLightIndex) {
         Vector3f pos = light.position();
         // Paper Section 4.1: bounding volume contains the emitter GEOMETRY,
         // not its illumination range.  A block light occupies ~1 block;
         // use a tight half-extent so the tree can spatially partition lights.
         float halfExtent = 0.5F;
         Vector3f rawColor = light.type().getRawColorAsVector();
         float lightIntensity = light.type().adjustedIntensity();
         float fluxR = rawColor.x * lightIntensity;
         float fluxG = rawColor.y * lightIntensity;
         float fluxB = rawColor.z * lightIntensity;
         float totalIntensity = (rawColor.x * luminanceRed + rawColor.y * luminanceGreen + rawColor.z * luminanceBlue) * lightIntensity;
         return new NodeBounds(
            pos.x - halfExtent,
            pos.y - halfExtent,
            pos.z - halfExtent,
            pos.x + halfExtent,
            pos.y + halfExtent,
            pos.z + halfExtent,
            new Vector3f(light.type().emissionAxis()),
            clampAngle(light.type().orientationSpread()),
            clampAngle(light.type().emissionSpread()),
            fluxR,
            fluxG,
            fluxB,
            totalIntensity,
            representativeLightIndex,
            1,
            totalIntensity * totalIntensity
         );
      }

      private void storeNodeBounds(int offset, NodeBounds bounds, int depth, int subtreeStart, int subtreeCount) {
         this.nodeData[offset] = bounds.minX;
         this.nodeData[offset + 1] = bounds.minY;
         this.nodeData[offset + 2] = bounds.minZ;
         this.nodeData[offset + 3] = Float.intBitsToFloat(-1);
         this.nodeData[offset + 4] = bounds.maxX;
         this.nodeData[offset + 5] = bounds.maxY;
         this.nodeData[offset + 6] = bounds.maxZ;
         this.nodeData[offset + 7] = Float.intBitsToFloat(-1);
         this.nodeData[offset + 8] = bounds.axis.x;
         this.nodeData[offset + 9] = bounds.axis.y;
         this.nodeData[offset + 10] = bounds.axis.z;
         this.nodeData[offset + 11] = bounds.totalIntensity;
         this.nodeData[offset + 12] = Float.intBitsToFloat(subtreeStart);
         this.nodeData[offset + 13] = Float.intBitsToFloat(subtreeCount);
         this.nodeData[offset + 14] = Float.intBitsToFloat(bounds.representativeLightIndex);
         this.nodeData[offset + 15] = Float.intBitsToFloat(packMeta(depth, bounds.orientationSpread, bounds.emissionSpread, bounds.energyVarianceCV()));
      }

      private void storeLeaf(int offset, int start, int count, int representativeLightIndex) {
         int leafStart = this.leafIndexCount;
         for (int i = 0; i < count; i++) {
            LightInstance light = this.lights[this.indices[start + i]];
            this.leafIndices[this.leafIndexCount++] = light.index();
         }
         this.nodeData[offset + 12] = Float.intBitsToFloat(leafStart);
         this.nodeData[offset + 13] = Float.intBitsToFloat(count);
         this.nodeData[offset + 14] = Float.intBitsToFloat(representativeLightIndex);
      }

      private int partition(int start, int end, int axis, float splitPos) {
         int i = start;
         int j = end - 1;
         while (i <= j) {
            float axisValue = getAxisValue(this.lights[this.indices[i]].position(), axis);
            if (axisValue < splitPos) {
               i++;
               continue;
            }
            int tmp = this.indices[i];
            this.indices[i] = this.indices[j];
            this.indices[j] = tmp;
            j--;
         }
         return i;
      }

      private static int selectSplitAxis(NodeBounds bounds) {
         float extentX = bounds.maxX - bounds.minX;
         float extentY = bounds.maxY - bounds.minY;
         float extentZ = bounds.maxZ - bounds.minZ;
         if (extentX >= extentY && extentX >= extentZ) {
            return 0;
         }
         if (extentY >= extentZ) {
            return 1;
         }
         return 2;
      }

      private static float getAxisValue(Vector3f position, int axis) {
         return axis == 0 ? position.x : axis == 1 ? position.y : position.z;
      }

      private static float clampAngle(float angle) {
         return Math.max(0.0F, Math.min(angle, (float) Math.PI));
      }

      private static int packMeta(int depth, float thetaO, float thetaE, float energyVarianceCV) {
         int packedDepth = Math.max(0, Math.min(depth, 255));
         int packedThetaO = Math.max(0, Math.min(Math.round(thetaO / (float) Math.PI * 255.0F), 255));
         int packedThetaE = Math.max(0, Math.min(Math.round(thetaE / (float) Math.PI * 255.0F), 255));
         int packedEnergyCV = Math.max(0, Math.min(Math.round(energyVarianceCV * 255.0F), 255));
         return packedDepth << 24 | packedThetaO << 16 | packedThetaE << 8 | packedEnergyCV;
      }

      private float[] getNodeData() {
         return this.nodeData;
      }

      private int getNodeDataLength() {
         return this.nodeCount * nodeFloatSize;
      }

      private int[] getLeafIndices() {
         return this.leafIndices;
      }

      private int getLeafIndexCount() {
         return this.leafIndexCount;
      }

      private BuilderStats computeDiagnostics() {
         BuilderStats stats = new BuilderStats();
         if (this.nodeCount == 0) {
            return stats;
         }
         this.collectDiagnostics(0, 0, stats);
         return stats;
      }

      private NodeBounds collectDiagnostics(int nodeIndex, int depth, BuilderStats stats) {
         int offset = nodeIndex * nodeFloatSize;
         NodeBounds bounds = this.readNodeBounds(offset);
         stats.nodeCount++;
         stats.depthSum += depth;
         stats.maxDepth = Math.max(stats.maxDepth, depth);
         if (depth == 0) {
            stats.rootBoundsVolume = bounds.volume();
         }
         int leftChild = Float.floatToRawIntBits(this.nodeData[offset + 3]);
         int rightChild = Float.floatToRawIntBits(this.nodeData[offset + 7]);
         if (leftChild < 0 && rightChild < 0) {
            int leafCount = Float.floatToRawIntBits(this.nodeData[offset + 13]);
            stats.leafCount++;
            stats.leafSizeSum += leafCount;
            stats.maxLeafSize = Math.max(stats.maxLeafSize, leafCount);
            return bounds;
         }
         NodeBounds left = this.collectDiagnostics(leftChild, depth + 1, stats);
         NodeBounds right = this.collectDiagnostics(rightChild, depth + 1, stats);
         stats.siblingPairCount++;
         stats.siblingOverlapRatioSum += bounds.subtreeOverlap(left, right);
         stats.childSeparationRatioSum += bounds.normalizedChildSeparation(left, right);
         return bounds;
      }

      private NodeBounds readNodeBounds(int offset) {
         return new NodeBounds(
            this.nodeData[offset],
            this.nodeData[offset + 1],
            this.nodeData[offset + 2],
            this.nodeData[offset + 4],
            this.nodeData[offset + 5],
            this.nodeData[offset + 6],
            new Vector3f(this.nodeData[offset + 8], this.nodeData[offset + 9], this.nodeData[offset + 10]),
            decodeOrientationSpread(Float.floatToRawIntBits(this.nodeData[offset + 15])),
            halfPi,
            0.0F,
            0.0F,
            0.0F,
            this.nodeData[offset + 11],
            Float.floatToRawIntBits(this.nodeData[offset + 14]),
            1,
            0.0F
         );
      }

      private static float decodeOrientationSpread(int packedMeta) {
         int packedThetaO = (packedMeta >> 16) & 255;
         return (packedThetaO / 255.0F) * (float) Math.PI;
      }

      private static final class SplitResult {
         private final int axis;
         private final float position;
         private final float cost;

         private SplitResult(int axis, float position, float cost) {
            this.axis = axis;
            this.position = position;
            this.cost = cost;
         }
      }

      private static final class BuilderStats {
         private int nodeCount;
         private int leafCount;
         private int maxLeafSize;
         private int maxDepth;
         private int siblingPairCount;
         private float leafSizeSum;
         private float depthSum;
         private float rootBoundsVolume;
         private float siblingOverlapRatioSum;
         private float childSeparationRatioSum;

         private float averageLeafSize() {
            return this.leafCount == 0 ? 0.0F : this.leafSizeSum / this.leafCount;
         }

         private float averageDepth() {
            return this.nodeCount == 0 ? 0.0F : this.depthSum / this.nodeCount;
         }

         private float averageSiblingOverlapRatio() {
            return this.siblingPairCount == 0 ? 0.0F : this.siblingOverlapRatioSum / this.siblingPairCount;
         }

         private float averageChildSeparationRatio() {
            return this.siblingPairCount == 0 ? 0.0F : this.childSeparationRatioSum / this.siblingPairCount;
         }
      }

      private static final class NodeBounds {
         private final float minX;
         private final float minY;
         private final float minZ;
         private final float maxX;
         private final float maxY;
         private final float maxZ;
         private final Vector3f axis;
         private final float orientationSpread;
         private final float emissionSpread;
         private final float fluxR;
         private final float fluxG;
         private final float fluxB;
         private final float totalIntensity;
         private final int representativeLightIndex;
         private final int lightCount;
         private final float intensitySumSq;

         private NodeBounds(
            float minX,
            float minY,
            float minZ,
            float maxX,
            float maxY,
            float maxZ,
            Vector3f axis,
            float orientationSpread,
            float emissionSpread,
            float fluxR,
            float fluxG,
            float fluxB,
            float totalIntensity,
            int representativeLightIndex,
            int lightCount,
            float intensitySumSq
         ) {
            this.minX = minX;
            this.minY = minY;
            this.minZ = minZ;
            this.maxX = maxX;
            this.maxY = maxY;
            this.maxZ = maxZ;
            Vector3f normalizedAxis = axis == null ? new Vector3f(0.0F, 1.0F, 0.0F) : new Vector3f(axis);
            if (normalizedAxis.lengthSquared() <= epsilon) {
               normalizedAxis.set(0.0F, 1.0F, 0.0F);
            } else {
               normalizedAxis.normalize();
            }
            this.axis = normalizedAxis;
            this.orientationSpread = clampAngle(orientationSpread);
            this.emissionSpread = clampAngle(emissionSpread);
            this.fluxR = fluxR;
            this.fluxG = fluxG;
            this.fluxB = fluxB;
            this.totalIntensity = totalIntensity;
            this.representativeLightIndex = representativeLightIndex;
            this.lightCount = lightCount;
            this.intensitySumSq = intensitySumSq;
         }

         private static NodeBounds empty() {
            return new NodeBounds(0.0F, 0.0F, 0.0F, 0.0F, 0.0F, 0.0F, new Vector3f(0.0F, 1.0F, 0.0F), (float) Math.PI, halfPi, 0.0F, 0.0F, 0.0F, 0.0F, -1, 0, 0.0F);
         }

         private NodeBounds union(NodeBounds other) {
            int representative = this.chooseRepresentative(other);
            return new NodeBounds(
               Math.min(this.minX, other.minX),
               Math.min(this.minY, other.minY),
               Math.min(this.minZ, other.minZ),
               Math.max(this.maxX, other.maxX),
               Math.max(this.maxY, other.maxY),
               Math.max(this.maxZ, other.maxZ),
               unionAxis(this.axis, this.orientationSpread, other.axis, other.orientationSpread),
               unionOrientationSpread(this.axis, this.orientationSpread, other.axis, other.orientationSpread),
               Math.max(this.emissionSpread, other.emissionSpread),
               this.fluxR + other.fluxR,
               this.fluxG + other.fluxG,
               this.fluxB + other.fluxB,
               this.totalIntensity + other.totalIntensity,
               representative,
               this.lightCount + other.lightCount,
               this.intensitySumSq + other.intensitySumSq
            );
         }

         private int chooseRepresentative(NodeBounds other) {
            return this.totalIntensity >= other.totalIntensity ? this.representativeLightIndex : other.representativeLightIndex;
         }

         private float getMidpoint(int axis) {
            if (axis == 0) {
               return (this.minX + this.maxX) * 0.5F;
            }
            if (axis == 1) {
               return (this.minY + this.maxY) * 0.5F;
            }
            return (this.minZ + this.maxZ) * 0.5F;
         }

         private float getMin(int axis) {
            return axis == 0 ? this.minX : axis == 1 ? this.minY : this.minZ;
         }

         private float getMax(int axis) {
            return axis == 0 ? this.maxX : axis == 1 ? this.maxY : this.maxZ;
         }

         private float centroidX() {
            return (this.minX + this.maxX) * 0.5F;
         }

         private float centroidY() {
            return (this.minY + this.maxY) * 0.5F;
         }

         private float centroidZ() {
            return (this.minZ + this.maxZ) * 0.5F;
         }

         private float diagonalLength() {
            float dx = Math.max(this.maxX - this.minX, 0.0F);
            float dy = Math.max(this.maxY - this.minY, 0.0F);
            float dz = Math.max(this.maxZ - this.minZ, 0.0F);
            return (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
         }

         private float volume() {
            float dx = Math.max(this.maxX - this.minX, 0.0F);
            float dy = Math.max(this.maxY - this.minY, 0.0F);
            float dz = Math.max(this.maxZ - this.minZ, 0.0F);
            return dx * dy * dz;
         }

         private float surfaceArea() {
            float dx = Math.max(this.maxX - this.minX, 0.0F);
            float dy = Math.max(this.maxY - this.minY, 0.0F);
            float dz = Math.max(this.maxZ - this.minZ, 0.0F);
            return 2.0F * (dx * dy + dy * dz + dz * dx);
         }

         private float orientationMeasure() {
            float thetaW = Math.min(this.orientationSpread + this.emissionSpread, (float) Math.PI);
            float baseMeasure = twoPi * (1.0F - (float) Math.cos(this.orientationSpread));
            float extraMeasure = thetaW <= this.orientationSpread
               ? 0.0F
               : halfPi * (
                  2.0F * thetaW * (float) Math.sin(this.orientationSpread)
                     - (float) Math.cos(this.orientationSpread - 2.0F * thetaW)
                     - 2.0F * this.orientationSpread * (float) Math.sin(this.orientationSpread)
                     + (float) Math.cos(this.orientationSpread)
               );
            return Math.max(baseMeasure + extraMeasure, epsilon);
         }

         private float axisRegularization(int axis) {
            float extent = Math.max(this.getMax(axis) - this.getMin(axis), epsilon);
            float maxExtent = Math.max(Math.max(this.maxX - this.minX, this.maxY - this.minY), this.maxZ - this.minZ);
            return Math.max(maxExtent, epsilon) / extent;
         }

         private float energyVarianceCV() {
            if (this.lightCount <= 1 || this.totalIntensity <= epsilon) {
               return 0.0F;
            }
            float meanIntensity = this.totalIntensity / this.lightCount;
            float variance = Math.max(this.intensitySumSq / this.lightCount - meanIntensity * meanIntensity, 0.0F);
            float stddev = (float) Math.sqrt(variance);
            return clampUnit(stddev / Math.max(meanIntensity, epsilon));
         }

         private float intersectionVolume(NodeBounds other) {
            float overlapX = Math.max(Math.min(this.maxX, other.maxX) - Math.max(this.minX, other.minX), 0.0F);
            float overlapY = Math.max(Math.min(this.maxY, other.maxY) - Math.max(this.minY, other.minY), 0.0F);
            float overlapZ = Math.max(Math.min(this.maxZ, other.maxZ) - Math.max(this.minZ, other.minZ), 0.0F);
            return overlapX * overlapY * overlapZ;
         }

         private float subtreeOverlap(NodeBounds left, NodeBounds right) {
            return left.intersectionVolume(right) / Math.max(this.volume(), epsilon);
         }

         private float normalizedChildSeparation(NodeBounds left, NodeBounds right) {
            float dx = left.centroidX() - right.centroidX();
            float dy = left.centroidY() - right.centroidY();
            float dz = left.centroidZ() - right.centroidZ();
            float centerDistance = (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
            float size = Math.max(0.5F * (left.diagonalLength() + right.diagonalLength()), epsilon);
            return Math.max(centerDistance / size - 1.0F, 0.0F);
         }

         private static Vector3f unionAxis(Vector3f axisA, float spreadA, Vector3f axisB, float spreadB) {
            // Paper Algorithm 1: ensure a has the larger cone
            Vector3f a_axis = axisA;
            float a_spread = spreadA;
            Vector3f b_axis = axisB;
            float b_spread = spreadB;
            if (b_spread > a_spread) {
               a_axis = axisB;
               a_spread = spreadB;
               b_axis = axisA;
               b_spread = spreadA;
            }
            float thetaD = (float) Math.acos(clamp(a_axis.dot(b_axis), -1.0F, 1.0F));
            // Check if a already covers b
            if (Math.min(thetaD + b_spread, (float) Math.PI) <= a_spread) {
               return new Vector3f(a_axis).normalize();
            }
            // New cone covering both
            float newSpread = (a_spread + thetaD + b_spread) * 0.5F;
            if (newSpread >= (float) Math.PI) {
               return new Vector3f(a_axis).normalize();
            }
            // Rotate a's axis towards b's axis
            float thetaR = newSpread - a_spread;
            Vector3f cross = new Vector3f(a_axis).cross(b_axis);
            float crossLen = cross.length();
            if (crossLen <= epsilon) {
               return new Vector3f(a_axis).normalize();
            }
            cross.normalize();
            // Rodrigues rotation: rotate a_axis by thetaR around cross axis
            float cosR = (float) Math.cos(thetaR);
            float sinR = (float) Math.sin(thetaR);
            Vector3f result = new Vector3f(a_axis).mul(cosR)
               .add(new Vector3f(cross).cross(a_axis).mul(sinR))
               .add(new Vector3f(cross).mul(cross.dot(a_axis) * (1.0F - cosR)));
            float resultLen = result.length();
            if (resultLen <= epsilon) {
               return new Vector3f(a_axis).normalize();
            }
            return result.normalize();
         }

         private static float unionOrientationSpread(Vector3f axisA, float spreadA, Vector3f axisB, float spreadB) {
            // Paper Algorithm 1: ensure a has the larger cone
            float a_spread = spreadA;
            float b_spread = spreadB;
            if (b_spread > a_spread) {
               float tmp = a_spread;
               a_spread = b_spread;
               b_spread = tmp;
            }
            float thetaD = (float) Math.acos(clamp(axisA.dot(axisB), -1.0F, 1.0F));
            // Check if a already covers b
            if (Math.min(thetaD + b_spread, (float) Math.PI) <= a_spread) {
               return a_spread;
            }
            // New covering cone
            float newSpread = (a_spread + thetaD + b_spread) * 0.5F;
            return clampAngle(Math.min(newSpread, (float) Math.PI));
         }

         private static float clamp(float value, float min, float max) {
            return Math.max(min, Math.min(value, max));
         }

         private static float clampUnit(float value) {
            return clamp(value, 0.0F, 1.0F);
         }
      }
   }

   public static record LightTreeDiagnostics(
      int nodeCount,
      int leafCount,
      float averageLeafSize,
      int maxLeafSize,
      float averageDepth,
      int maxDepth,
      float rootBoundsVolume,
      float siblingOverlapRatio,
      float childSeparationRatio,
      int rebuildCount,
      int lastRebuildCompileCount,
      long lastBuildNanos
   ) {
      private static LightTreeDiagnostics empty() {
         return new LightTreeDiagnostics(0, 0, 0.0F, 0, 0.0F, 0, 0.0F, 0.0F, 0.0F, 0, -1, 0L);
      }

      private static LightTreeDiagnostics fromBuild(LightTreeBuilder builder, int rebuildCount, int lastRebuildCompileCount, long lastBuildNanos) {
         LightTreeBuilder.BuilderStats stats = builder.computeDiagnostics();
         return new LightTreeDiagnostics(
            stats.nodeCount,
            stats.leafCount,
            stats.averageLeafSize(),
            stats.maxLeafSize,
            stats.averageDepth(),
            stats.maxDepth,
            stats.rootBoundsVolume,
            stats.averageSiblingOverlapRatio(),
            stats.averageChildSeparationRatio(),
            rebuildCount,
            lastRebuildCompileCount,
            lastBuildNanos
         );
      }

      public String describe() {
         return String.format(
            "nodes=%d leaves=%d leafAvg=%.2f leafMax=%d depthAvg=%.2f depthMax=%d rootVolume=%.2f overlap=%.3f separation=%.3f rebuilds=%d lastRebuildCompile=%d buildUs=%d",
            this.nodeCount,
            this.leafCount,
            this.averageLeafSize,
            this.maxLeafSize,
            this.averageDepth,
            this.maxDepth,
            this.rootBoundsVolume,
            this.siblingOverlapRatio,
            this.childSeparationRatio,
            this.rebuildCount,
            this.lastRebuildCompileCount,
            this.lastBuildNanos / 1000L
         );
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
            "frame(prev=%d,gathered=%d,stable=%d,added=%d,removed=%d,blockId=%d,lightInfo=%d) mutations(add=%d,remove=%d,cull=%d,blockId=%d,lightInfo=%d,noop=%d)%s",
            frame.previousCount,
            frame.gatheredCount,
            frame.stableMappings,
            frame.additions,
            frame.removals,
            frame.blockIdChanges,
            frame.lightInfoChanges,
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

         private Frame(int previousCount, int gatheredCount) {
            this.previousCount = previousCount;
            this.gatheredCount = gatheredCount;
         }
      }
   }
}



