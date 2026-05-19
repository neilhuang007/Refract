package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.PhotonicsStorage;
import at.redi2go.photonic.client.config.lights.BlockLightInfo;
import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.opengl.rendering.RegirComputeProgram;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.SimpleMemoryOwner;
import it.unimi.dsi.fastutil.longs.LongOpenHashSet;
import org.lwjgl.system.MemoryUtil;
import org.joml.Vector3f;

import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

/**
 * Owns the ReGIR (Reservoir-based Grid Importance Resampling) spatial grid,
 * its 6 GPU buffer managers, and all build/sampling logic.
 */
public final class RegirGridBuilder {

   // -------------------------------------------------------------------------
   // Constants
   // -------------------------------------------------------------------------
   public static final int GRID_CELL_SIZE = 32;
   public static final float REGIR_CELL_RADIUS = (float) (Math.sqrt(3.0) * GRID_CELL_SIZE);
   public static final int REGIR_MAX_LIGHTS_PER_CELL_FALLBACK = 16;
   public static final int REGIR_DEFAULT_LIGHTS_PER_CELL = 64;
   private static final int REGIR_BUILD_SAMPLES = 6;
   public static final float REGIR_HASH_CELL_SIZE_BLOCKS = 3.0F;
   public static final int REGIR_HASH_NORMAL_BUCKETS = 1;
   public static final int REGIR_HASH_TABLE_SIZE = 262144;
   public static final int REGIR_BUILD_REGION_CELLS = 20;
   private static final int REGIR_ACTIVE_CELLS_MAX =
         REGIR_BUILD_REGION_CELLS * REGIR_BUILD_REGION_CELLS * REGIR_BUILD_REGION_CELLS;

   // -------------------------------------------------------------------------
   // Spatial grid (rebuilt when light topology changes)
   // -------------------------------------------------------------------------
   HashMap<Long, List<Integer>> lightGrid;
   int lightGridAssignments = 0;

   // -------------------------------------------------------------------------
   // Activity stats (updated by buildRegirGrid / updateRegirActivityStats)
   // -------------------------------------------------------------------------
   private int regirActiveCellCount = 0;
   private int regirActiveLightSlotCount = 0;

   // Flyweight buffer for active ReGIR cell coords uploaded to the GPU each frame.
   private IntBuffer regirActiveCellsBuffer = MemoryUtil.memAllocInt(REGIR_ACTIVE_CELLS_MAX * 4);
   private int regirActiveCellsCount = 0;

   // -------------------------------------------------------------------------
   // Grid geometry
   // -------------------------------------------------------------------------
   private final Vector3f regirGridCenter = new Vector3f();
   private final int regirGridResolution;
   private final int regirCellCount;
   private final int regirLightsPerCell;

   // -------------------------------------------------------------------------
   // 6 GPU buffer managers (SSBOs)
   // -------------------------------------------------------------------------
   final GlMemoryManager regirCellCountMemoryManager;
   final MemoryOwner regirCellCountMemory;
   final GlMemoryManager regirLightIndexMemoryManager;
   final MemoryOwner regirLightIndexMemory;
   final GlMemoryManager regirLightPdfMemoryManager;
   final MemoryOwner regirLightPdfMemory;
   final GlMemoryManager regirCompactLightDataMemoryManager;
   final MemoryOwner regirCompactLightDataMemory;
   final GlMemoryManager regirHashChecksumMemoryManager;
   final MemoryOwner regirHashChecksumMemory;
   final GlMemoryManager regirHashKeyMemoryManager;
   final MemoryOwner regirHashKeyMemory;

   // -------------------------------------------------------------------------
   // Light powers for ReGIR sampling (per-light unweighted source power)
   // -------------------------------------------------------------------------
   private float[] regirLightPowers = new float[0];

   public RegirGridBuilder(int regirGridResolution, int regirLightsPerCell) {
      this.regirGridResolution = regirGridResolution;
      this.regirCellCount = regirGridResolution * regirGridResolution * regirGridResolution;
      this.regirLightsPerCell = regirLightsPerCell;

      this.regirCellCountMemoryManager = new GlMemoryManager(
            GlTarget.SSBO, "ph_regir_cell_counts", this.regirCellCount * Integer.BYTES, false);
      this.regirCellCountMemory = new SimpleMemoryOwner(
            this.regirCellCountMemoryManager, this.regirCellCountMemoryManager.getCapacity());

      // Unified RIS buffer (RTXDI_RIS_BUFFER): presample tiles + ReGIR output in one SSBO.
      // Layout: [0, tileCount*tileSize) = presample tiles; [tileCount*tileSize, ...) = ReGIR hash slots.
      // For the hash-grid ReGIR variant the ReGIR region is sized for REGIR_HASH_TABLE_SIZE
      // hash slots (not gridCells^3) and slots are indexed by hash, not by linear position.
      int risBufferTileEntries = RegirComputeProgram.tileCount * RegirComputeProgram.tileSize;
      int regirHashSlotEntries = REGIR_HASH_TABLE_SIZE * this.regirLightsPerCell;
      this.regirLightIndexMemoryManager = new GlMemoryManager(
            GlTarget.SSBO,
            "ph_ris_buffer",
            (risBufferTileEntries + regirHashSlotEntries) * 8, // 8 bytes per uvec2
            false
      );
      this.regirLightIndexMemory = new SimpleMemoryOwner(
            this.regirLightIndexMemoryManager, this.regirLightIndexMemoryManager.getCapacity());

      // PDF buffer is retained for the CPU-side (non-GPU) build path only.
      // The hash-grid GPU build does not touch it; kept for legacy CPU paths and
      // sized identically so existing iteration code does not OOB.
      this.regirLightPdfMemoryManager = new GlMemoryManager(
            GlTarget.SSBO,
            "ph_regir_light_pdfs",
            this.regirCellCount * this.regirLightsPerCell * Float.BYTES,
            false
      );
      this.regirLightPdfMemory = new SimpleMemoryOwner(
            this.regirLightPdfMemoryManager, this.regirLightPdfMemoryManager.getCapacity());

      // Compact light data buffer uses the full 4*uvec4 companion layout per RIS slot.
      // The presample Power RIS tiles use compact light payloads. ReGIR output
      // stores only the selected light index and inverse source PDF, then reloads
      // the light from the live light list when sampled; this keeps higher ReGIR
      // slot counts from multiplying the 64-byte compact payload buffer.
      int compactTotalEntries = risBufferTileEntries;
      this.regirCompactLightDataMemoryManager = new GlMemoryManager(
            GlTarget.SSBO,
            "ph_ris_compact_light_data",
            compactTotalEntries * 4 * 16,
            false
      );
      this.regirCompactLightDataMemory = new SimpleMemoryOwner(
            this.regirCompactLightDataMemoryManager, this.regirCompactLightDataMemoryManager.getCapacity());

      // Hash-grid auxiliary buffers: per-slot checksum (atomic word) and per-slot
      // cell key (cellX,cellY,cellZ,bucket) for verification on lookup. Cleared
      // every frame before the build pass.
      this.regirHashChecksumMemoryManager = new GlMemoryManager(
            GlTarget.SSBO,
            "ph_regir_cell_checksums",
            REGIR_HASH_TABLE_SIZE * Integer.BYTES,
            false
      );
      this.regirHashChecksumMemory = new SimpleMemoryOwner(
            this.regirHashChecksumMemoryManager, this.regirHashChecksumMemoryManager.getCapacity());

      this.regirHashKeyMemoryManager = new GlMemoryManager(
            GlTarget.SSBO,
            "ph_regir_cell_keys",
            REGIR_HASH_TABLE_SIZE * 4 * Integer.BYTES, // ivec4 per slot
            false
      );
      this.regirHashKeyMemory = new SimpleMemoryOwner(
            this.regirHashKeyMemoryManager, this.regirHashKeyMemoryManager.getCapacity());
   }

   // -------------------------------------------------------------------------
   // Spatial grid build
   // -------------------------------------------------------------------------

   void buildSpatialGrid(LightInstance[] lights, float regirBuildCellRadius) {
      this.lightGrid = new HashMap<>(lights.length * 4);
      this.lightGridAssignments = 0;
      for (int i = 0; i < lights.length; i++) {
         LightInstance light = lights[i];
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

   // -------------------------------------------------------------------------
   // ReGIR grid build (CPU path)
   // -------------------------------------------------------------------------

   void buildRegirGrid(LightInstance[] tracedLights, Vector3f gridCenter, float regirBuildCellRadius) {
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

      this.regirGridCenter.set(gridCenter);
      // Derive origin for CPU-side cell iteration (mirrors shader derivation)
      float halfExtent = this.regirGridResolution * GRID_CELL_SIZE * 0.5f;
      int originCellX = (int) Math.floor((gridCenter.x - halfExtent) / GRID_CELL_SIZE);
      int originCellY = (int) Math.floor((gridCenter.y - halfExtent) / GRID_CELL_SIZE);
      int originCellZ = (int) Math.floor((gridCenter.z - halfExtent) / GRID_CELL_SIZE);
      this.regirActiveCellCount = 0;
      this.regirActiveLightSlotCount = 0;

      if (this.lightGrid == null || this.lightGrid.isEmpty() || tracedLights.length == 0) {
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
                  WeightedLightSelection selection = sampleRegirCellLight(cellLights, tracedLights, cellCenter, regirBuildCellRadius, seed);
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

   // -------------------------------------------------------------------------
   // Activity stats update (GPU path — grid center update only)
   // -------------------------------------------------------------------------

   void updateRegirGridOriginOnly(LightInstance[] tracedLights, Vector3f gridCenter, float regirBuildCellRadius) {
      this.regirGridCenter.set(gridCenter);
      this.updateRegirActivityStats(tracedLights, gridCenter, regirBuildCellRadius);
   }

   void updateRegirActivityStats(LightInstance[] tracedLights, Vector3f gridCenter, float regirBuildCellRadius) {
      this.regirActiveCellCount = 0;
      this.regirActiveLightSlotCount = 0;

      if (this.lightGrid == null || this.lightGrid.isEmpty() || tracedLights.length == 0) {
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
                  WeightedLightSelection selection = sampleRegirCellLight(cellLights, tracedLights, cellCenter, regirBuildCellRadius, seed);
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

   // -------------------------------------------------------------------------
   // Active cell list refresh (GPU hash-grid path)
   // -------------------------------------------------------------------------

   public void refreshActiveRegirCells(Vector3f cameraPos, LightInstance[] lights) {
      if (lights == null || lights.length == 0) {
         this.regirActiveCellsBuffer.clear();
         this.regirActiveCellsBuffer.flip();
         this.regirActiveCellsCount = 0;
         return;
      }
      final int halfExtent = REGIR_BUILD_REGION_CELLS / 2;
      final int camCellX = regirHashCellCoord(cameraPos.x);
      final int camCellY = regirHashCellCoord(cameraPos.y);
      final int camCellZ = regirHashCellCoord(cameraPos.z);

      LongOpenHashSet seenKeys = new LongOpenHashSet(Math.min(lights.length * 2, REGIR_ACTIVE_CELLS_MAX));
      this.regirActiveCellsBuffer.clear();
      int count = 0;
      for (LightInstance light : lights) {
         Vector3f pos = light.position();
         int cx = regirHashCellCoord(pos.x);
         int cy = regirHashCellCoord(pos.y);
         int cz = regirHashCellCoord(pos.z);
         if (Math.abs(cx - camCellX) > halfExtent
               || Math.abs(cy - camCellY) > halfExtent
               || Math.abs(cz - camCellZ) > halfExtent) {
            continue;
         }
         long key = (cx & 0xFFFFL) | ((cy & 0xFFFFL) << 16) | ((long)(cz & 0xFFFF) << 32);
         if (!seenKeys.add(key)) continue;
         if (count >= REGIR_ACTIVE_CELLS_MAX) break;
         this.regirActiveCellsBuffer.put(cx);
         this.regirActiveCellsBuffer.put(cy);
         this.regirActiveCellsBuffer.put(cz);
         this.regirActiveCellsBuffer.put(0);
         count++;
      }
      this.regirActiveCellsBuffer.flip();
      this.regirActiveCellsCount = count;
   }

   // -------------------------------------------------------------------------
   // Upload (the 6 ReGIR buffers)
   // -------------------------------------------------------------------------

   boolean upload(boolean gpuRegirBuildEnabled) {
      boolean uploadDone = this.regirCellCountMemoryManager.upload();
      if (!gpuRegirBuildEnabled) {
         uploadDone &= this.regirLightIndexMemoryManager.upload();
         uploadDone &= this.regirLightPdfMemoryManager.upload();
         uploadDone &= this.regirCompactLightDataMemoryManager.upload();
      }
      return uploadDone;
   }

   // -------------------------------------------------------------------------
   // Queue upload (called from compileRegistry on the CPU path)
   // -------------------------------------------------------------------------

   void queueUpload() {
      this.regirCellCountMemoryManager.queueUpload(this.regirCellCountMemory);
      this.regirLightIndexMemoryManager.queueUpload(this.regirLightIndexMemory);
      this.regirLightPdfMemoryManager.queueUpload(this.regirLightPdfMemory);
      this.regirCompactLightDataMemoryManager.queueUpload(this.regirCompactLightDataMemory);
   }

   // -------------------------------------------------------------------------
   // Free
   // -------------------------------------------------------------------------

   public void free() {
      this.regirCellCountMemoryManager.free();
      this.regirLightIndexMemoryManager.free();
      this.regirLightPdfMemoryManager.free();
      this.regirCompactLightDataMemoryManager.free();
      this.regirHashChecksumMemoryManager.free();
      this.regirHashKeyMemoryManager.free();
      MemoryUtil.memFree(this.regirActiveCellsBuffer);
      this.regirActiveCellsBuffer = null;
   }

   // -------------------------------------------------------------------------
   // ReGIR light power array (set by LightRegistry.storeGlobalLightCdf)
   // -------------------------------------------------------------------------

   public void setRegirLightPowers(float[] powers) {
      this.regirLightPowers = powers;
   }

   public float[] getRegirLightPowers() {
      return this.regirLightPowers;
   }

   // -------------------------------------------------------------------------
   // Accessors
   // -------------------------------------------------------------------------

   public Vector3f getGridCenter() {
      return new Vector3f(this.regirGridCenter);
   }

   /** Sets the stored grid center (called when the CPU path resolves a new center). */
   void setGridCenter(Vector3f center) {
      this.regirGridCenter.set(center);
   }

   public int getActiveCellCount() {
      return this.regirActiveCellCount;
   }

   public int getActiveLightSlotCount() {
      return this.regirActiveLightSlotCount;
   }

   public int getCellCount() {
      return this.regirCellCount;
   }

   public int getLightsPerCell() {
      return this.regirLightsPerCell;
   }

   public int getGridResolution() {
      return this.regirGridResolution;
   }

   public int getHashTableSize() {
      return REGIR_HASH_TABLE_SIZE;
   }

   public int getHashNormalBuckets() {
      return REGIR_HASH_NORMAL_BUCKETS;
   }

   public float getHashCellSizeBlocks() {
      return REGIR_HASH_CELL_SIZE_BLOCKS;
   }

   public int getBuildRegionCells() {
      return REGIR_BUILD_REGION_CELLS;
   }

   public HashMap<Long, List<Integer>> getLightGrid() {
      return this.lightGrid;
   }

   public GlMemoryManager getCellCountMemoryManager() {
      return this.regirCellCountMemoryManager;
   }

   public GlMemoryManager getLightIndexMemoryManager() {
      return this.regirLightIndexMemoryManager;
   }

   public GlMemoryManager getLightPdfMemoryManager() {
      return this.regirLightPdfMemoryManager;
   }

   public GlMemoryManager getCompactLightDataMemoryManager() {
      return this.regirCompactLightDataMemoryManager;
   }

   public GlMemoryManager getHashChecksumMemoryManager() {
      return this.regirHashChecksumMemoryManager;
   }

   public GlMemoryManager getHashKeyMemoryManager() {
      return this.regirHashKeyMemoryManager;
   }

   public int getActiveRegirCellCount() {
      return this.regirActiveCellsCount;
   }

   public IntBuffer getActiveRegirCellsBuffer() {
      return this.regirActiveCellsBuffer;
   }

   // -------------------------------------------------------------------------
   // Static helpers
   // -------------------------------------------------------------------------

   static int regirHashCellCoord(float coordinate) {
      return (int) Math.floor(coordinate / REGIR_HASH_CELL_SIZE_BLOCKS);
   }

   static long gridKey(int gx, int gy, int gz) {
      return ((long) gx & 0xFFFFF) | (((long) gy & 0xFFFFF) << 20) | (((long) gz & 0xFFFFF) << 40);
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
      if (!light.active()) {
         return 0.0F;
      }

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

      float spread = lightInfo.orientationSpread() + lightInfo.emissionSpread();
      if (!regirCellIntersectsShapedLight(lightInfo, lightPosition, cellCenter, cellRadius, spread)) {
         return 0.0F;
      }

      return lightInfo.luminanceFrom(lightPosition, new Vector3f(
         lightPosition.x + dirX * averageDistance,
         lightPosition.y + dirY * averageDistance,
         lightPosition.z + dirZ * averageDistance
      ));
   }

   private static boolean regirCellIntersectsShapedLight(
         BlockLightInfo lightInfo,
         Vector3f lightPosition,
         Vector3f cellCenter,
         float cellRadius,
         float spread
   ) {
      if (spread >= Math.PI) {
         return true;
      }

      float coneHalfAngle = Math.clamp(spread + (float) (Math.PI * 0.5), 0.0F, (float) Math.PI);
      Vector3f coneAxis = lightInfo.emissionAxis();
      float axisLength = (float) Math.sqrt(coneAxis.x * coneAxis.x + coneAxis.y * coneAxis.y + coneAxis.z * coneAxis.z);
      if (axisLength <= 1.0e-6F) {
         return true;
      }

      float sinHalfAngle = (float) Math.sin(Math.min(coneHalfAngle, Math.PI * 0.5));
      float offset = Math.max(lightInfo.radiusInBlocks(), 0.0F) / Math.max(sinHalfAngle, 1.0e-5F);
      Vector3f coneVertex = new Vector3f(
         lightPosition.x - coneAxis.x / axisLength * offset,
         lightPosition.y - coneAxis.y / axisLength * offset,
         lightPosition.z - coneAxis.z / axisLength * offset
      );
      return regirSphereIntersectsCone(coneVertex, coneAxis, coneHalfAngle, cellCenter, cellRadius);
   }

   private static boolean regirSphereIntersectsCone(
         Vector3f coneVertex,
         Vector3f coneAxis,
         float coneHalfAngle,
         Vector3f sphereCenter,
         float sphereRadius
   ) {
      if (coneHalfAngle >= Math.PI) {
         return true;
      }

      float dx = sphereCenter.x - coneVertex.x;
      float dy = sphereCenter.y - coneVertex.y;
      float dz = sphereCenter.z - coneVertex.z;
      float distance = (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
      if (distance <= sphereRadius || distance <= 1.0e-6F) {
         return true;
      }

      float axisLength = (float) Math.sqrt(coneAxis.x * coneAxis.x + coneAxis.y * coneAxis.y + coneAxis.z * coneAxis.z);
      if (axisLength <= 1.0e-6F) {
         return true;
      }

      float invDistance = 1.0F / distance;
      float invAxisLength = 1.0F / axisLength;
      float axisDot = (dx * coneAxis.x + dy * coneAxis.y + dz * coneAxis.z) * invDistance * invAxisLength;
      float axisAngle = (float) Math.acos(Math.clamp(axisDot, -1.0F, 1.0F));
      float sphereHalfAngle = (float) Math.asin(Math.clamp(sphereRadius * invDistance, 0.0F, 1.0F));
      return axisAngle <= sphereHalfAngle + coneHalfAngle;
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

   private record WeightedLightSelection(int lightIndex, float invSourcePdf) {
   }
}
