package at.redi2go.photonic.client.rendering.opengl.rendering.renderers;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.rendering.opengl.GpuTimerQuery;
import at.redi2go.photonic.client.rendering.world.LightRegistry;
import at.redi2go.photonic.client.rendering.world.WorldRegistry;
import net.minecraft.client.MinecraftClient;

/**
 * Encapsulates the GPU/CPU profiler subsystem extracted from LightTreeRenderer.
 * Owns the GpuTimerQuery, all region-index constants, and the per-frame logging logic.
 */
class LightTreePipelineProfiler {

   // -------------------------------------------------------------------------
   // Region-index constants — public so LightTreeRenderer's pass code can use them.
   // -------------------------------------------------------------------------
   public static final int lightTreeSamplingStageRegionIndex = 0;
   public static final int initialCandidatesRegionIndex = 1;
   public static final int diTemporalResamplingRegionIndex = 2;
   public static final int diSpatialResamplingRegionIndex = 3;
   public static final int diShadeSamplesRegionIndex = 4;
   public static final int nrdClassifyTilesRegionIndex = 5;
   public static final int nrdHitDistReconstructionRegionIndex = 6;
   public static final int nrdPrepassRegionIndex = 7;
   public static final int relaxTemporalAccumulationRegionIndex = 8;
   public static final int relaxHistoryFixRegionIndex = 9;
   public static final int relaxHistoryClampingRegionIndex = 10;
   public static final int nrdCopyRegionIndex = 11;
   public static final int relaxAntiFireflyRegionIndex = 12;
   public static final int relaxAtrousSmemRegionIndex = 13;
   public static final int relaxAtrousRegionIndex = 14;
   public static final int restirGIRegionIndex = 15;
   public static final int indirectDenoiseRegionIndex = 16;
   public static final int lightingAccumulationRegionIndex = 17;
   public static final int indirectCompositeRegionIndex = 18;
   // NRD history-confidence cascade region (gradient pass + 5-pass blur loop).
   public static final int nrdConfidenceCascadeRegionIndex = 19;

   // -------------------------------------------------------------------------
   // Region names — canonical array, private; nothing outside this class needs it.
   // -------------------------------------------------------------------------
   private static final String[] gpuProfilerRegionNames = new String[]{
      "LightTreeSamplingStage", "InitialCandidates", "DITemporalResampling", "DISpatialResampling", "DIShadeSamples",
      "NRDClassifyTiles", "NRDHitDistReconstruction", "NRDPrepass",
      "RELAXTemporalAccumulation", "RELAXHistoryFix", "RELAXHistoryClamping",
      "NRDCopy", "RELAXAntiFirefly", "RELAXAtrousSmem", "RELAXAtrous",
      "ReSTIRGI", "IndirectDenoise", "LightingAccumulation", "IndirectComposite",
      "NRDConfidenceCascade"
   };

   private static final int profilerLogIntervalFrames = 60;

   // -------------------------------------------------------------------------
   // Instance state
   // -------------------------------------------------------------------------
   private final GpuTimerQuery gpuTimerQuery;
   private int profilerFrameCounter = 0;

   // -------------------------------------------------------------------------
   // Constructor / lifecycle
   // -------------------------------------------------------------------------

   LightTreePipelineProfiler() {
      this.gpuTimerQuery = new GpuTimerQuery(gpuProfilerRegionNames);
   }

   /** Returns the underlying timer query so pass code can call begin/end. */
   public GpuTimerQuery timerQuery() {
      return this.gpuTimerQuery;
   }

   /** Destroys the underlying GPU timer query object. Call from the renderer's free() path. */
   public void destroy() {
      this.gpuTimerQuery.destroy();
   }

   // -------------------------------------------------------------------------
   // Per-frame logging
   // -------------------------------------------------------------------------

   /**
    * Increments the frame counter and, every {@code profilerLogIntervalFrames} frames,
    * emits the full RTXDI/NRD profiler summary via {@code Photonic.info}.
    *
    * @param totalCpuNanos              wall-clock span for the full render() call
    * @param cpuPassNanos               per-pass CPU times, indexed by *RegionIndex constants
    * @param worldRegistry              live world/light registry for blend/light counts
    * @param renderScale                render-scale fraction (e.g. 1.0f or 0.5f)
    * @param lastCpuDirectAtrousIter    per-atrous-iteration CPU times (from LightTreeRenderer)
    * @param nrdAtrousStrides           stride values matching each atrous iteration
    */
   public void logFrameSummaryIfDue(long totalCpuNanos,
                                     long[] cpuPassNanos,
                                     WorldRegistry worldRegistry,
                                     float renderScale,
                                     long[] lastCpuDirectAtrousIter,
                                     int[] nrdAtrousStrides) {
      this.profilerFrameCounter++;
      if (this.profilerFrameCounter < profilerLogIntervalFrames) {
         return;
      }
      this.profilerFrameCounter = 0;
      long[] gpuPassNanos = this.getGpuPassNanos();
      int worstCpuIndex = this.getWorstPassIndex(cpuPassNanos);
      int worstGpuIndex = this.getWorstPassIndex(gpuPassNanos);
      LightRegistry lightRegistry = worldRegistry.getLightRegistry();
      long totalGpuNanos = this.sumNanos(gpuPassNanos);
      int fbWidth = MinecraftClient.getInstance().getWindow().getFramebufferWidth();
      int fbHeight = MinecraftClient.getInstance().getWindow().getFramebufferHeight();
      int renderWidth = Math.round(fbWidth * renderScale);
      int renderHeight = Math.round(fbHeight * renderScale);
      long renderPixels = (long) renderWidth * renderHeight;
      Photonic.info(
         "[Profiler] RTXDI/NRD summary: cpuTotal={}us gpuTotal={}us worstCpu={}={}us worstGpu={}={}us reloadActive={} blendFactor={} blendRegions={} tracedLights={}/{} regirCells={} regirLightSlots={} regirGrid={}^3 viewport={}x{} renderRes={}x{} pixels={} lightTreeSamplingStageNsPerPixel={} stageGeometry={}",
         this.toMicros(totalCpuNanos),
         this.toMicros(totalGpuNanos),
         gpuProfilerRegionNames[worstCpuIndex],
         this.toMicros(cpuPassNanos[worstCpuIndex]),
         gpuProfilerRegionNames[worstGpuIndex],
         this.toMicros(gpuPassNanos[worstGpuIndex]),
         worldRegistry.fetchLightReload(),
         this.formatBlendFactor(worldRegistry.fetchLightBlendFactor()),
         worldRegistry.getLightBlendRegionCount(),
         lightRegistry.lightCount(),
         lightRegistry.totalLights(),
         lightRegistry.getRegirActiveCellCount(),
         lightRegistry.getRegirActiveLightSlotCount(),
         lightRegistry.getRegirGridResolution(),
         fbWidth, fbHeight,
         renderWidth, renderHeight,
         renderPixels,
         renderPixels > 0 ? (gpuPassNanos[lightTreeSamplingStageRegionIndex] / renderPixels) : 0,
         this.describeStageGeometryUsage()
      );
      Photonic.info(
         "[Profiler] RTXDI/NRD CPU passes: LightTreeSamplingStage={}us InitialCandidates={}us DITemporalResampling={}us DISpatialResampling={}us DIShadeSamples={}us NRDClassifyTiles={}us NRDHitDistReconstruction={}us NRDPrepass={}us RELAXTemporalAccumulation={}us RELAXHistoryFix={}us RELAXHistoryClamping={}us NRDCopy={}us RELAXAntiFirefly={}us RELAXAtrousSmem={}us RELAXAtrous={}us ReSTIRGI={}us IndirectDenoise={}us LightingAccumulation={}us IndirectComposite={}us",
         this.toMicros(cpuPassNanos[lightTreeSamplingStageRegionIndex]),
         this.toMicros(cpuPassNanos[initialCandidatesRegionIndex]),
         this.toMicros(cpuPassNanos[diTemporalResamplingRegionIndex]),
         this.toMicros(cpuPassNanos[diSpatialResamplingRegionIndex]),
         this.toMicros(cpuPassNanos[diShadeSamplesRegionIndex]),
         this.toMicros(cpuPassNanos[nrdClassifyTilesRegionIndex]),
         this.toMicros(cpuPassNanos[nrdHitDistReconstructionRegionIndex]),
         this.toMicros(cpuPassNanos[nrdPrepassRegionIndex]),
         this.toMicros(cpuPassNanos[relaxTemporalAccumulationRegionIndex]),
         this.toMicros(cpuPassNanos[relaxHistoryFixRegionIndex]),
         this.toMicros(cpuPassNanos[relaxHistoryClampingRegionIndex]),
         this.toMicros(cpuPassNanos[nrdCopyRegionIndex]),
         this.toMicros(cpuPassNanos[relaxAntiFireflyRegionIndex]),
         this.toMicros(cpuPassNanos[relaxAtrousSmemRegionIndex]),
         this.toMicros(cpuPassNanos[relaxAtrousRegionIndex]),
         this.toMicros(cpuPassNanos[restirGIRegionIndex]),
         this.toMicros(cpuPassNanos[indirectDenoiseRegionIndex]),
         this.toMicros(cpuPassNanos[lightingAccumulationRegionIndex]),
         this.toMicros(cpuPassNanos[indirectCompositeRegionIndex])
      );
      this.logGpuRenderProfile(gpuPassNanos, worldRegistry, renderScale);
      this.logDirectAtrousBreakdown(lastCpuDirectAtrousIter, nrdAtrousStrides);
   }

   // -------------------------------------------------------------------------
   // Private helpers
   // -------------------------------------------------------------------------

   private long[] getGpuPassNanos() {
      return new long[]{
         this.gpuTimerQuery.getTimeNanos(lightTreeSamplingStageRegionIndex),      // 0
         this.gpuTimerQuery.getTimeNanos(initialCandidatesRegionIndex),           // 1
         this.gpuTimerQuery.getTimeNanos(diTemporalResamplingRegionIndex),        // 2
         this.gpuTimerQuery.getTimeNanos(diSpatialResamplingRegionIndex),         // 3
         this.gpuTimerQuery.getTimeNanos(diShadeSamplesRegionIndex),              // 4
         this.gpuTimerQuery.getTimeNanos(nrdClassifyTilesRegionIndex),            // 5
         this.gpuTimerQuery.getTimeNanos(nrdHitDistReconstructionRegionIndex),    // 6
         this.gpuTimerQuery.getTimeNanos(nrdPrepassRegionIndex),                  // 7
         this.gpuTimerQuery.getTimeNanos(relaxTemporalAccumulationRegionIndex),   // 8
         this.gpuTimerQuery.getTimeNanos(relaxHistoryFixRegionIndex),             // 9
         this.gpuTimerQuery.getTimeNanos(relaxHistoryClampingRegionIndex),        // 10
         this.gpuTimerQuery.getTimeNanos(nrdCopyRegionIndex),                     // 11
         this.gpuTimerQuery.getTimeNanos(relaxAntiFireflyRegionIndex),            // 12
         this.gpuTimerQuery.getTimeNanos(relaxAtrousSmemRegionIndex),             // 13
         this.gpuTimerQuery.getTimeNanos(relaxAtrousRegionIndex),                 // 14
         this.gpuTimerQuery.getTimeNanos(restirGIRegionIndex),                    // 15
         this.gpuTimerQuery.getTimeNanos(indirectDenoiseRegionIndex),             // 16
         this.gpuTimerQuery.getTimeNanos(lightingAccumulationRegionIndex),        // 17
         this.gpuTimerQuery.getTimeNanos(indirectCompositeRegionIndex),           // 18
         this.gpuTimerQuery.getTimeNanos(nrdConfidenceCascadeRegionIndex)         // 19
      };
   }

   private void logGpuRenderProfile(long[] gpuPassNanos, WorldRegistry worldRegistry, float renderScale) {
      long diTotal = gpuPassNanos[lightTreeSamplingStageRegionIndex]
         + gpuPassNanos[initialCandidatesRegionIndex]
         + gpuPassNanos[diTemporalResamplingRegionIndex]
         + gpuPassNanos[diSpatialResamplingRegionIndex]
         + gpuPassNanos[diShadeSamplesRegionIndex];
      long relaxTotal = gpuPassNanos[nrdClassifyTilesRegionIndex]
         + gpuPassNanos[nrdHitDistReconstructionRegionIndex]
         + gpuPassNanos[nrdPrepassRegionIndex]
         + gpuPassNanos[relaxTemporalAccumulationRegionIndex]
         + gpuPassNanos[relaxHistoryFixRegionIndex]
         + gpuPassNanos[relaxHistoryClampingRegionIndex]
         + gpuPassNanos[nrdCopyRegionIndex]
         + gpuPassNanos[relaxAntiFireflyRegionIndex]
         + gpuPassNanos[relaxAtrousSmemRegionIndex]
         + gpuPassNanos[relaxAtrousRegionIndex];
      long indirectTotal = gpuPassNanos[restirGIRegionIndex]
         + gpuPassNanos[indirectDenoiseRegionIndex];
      long compositeTotal = gpuPassNanos[lightingAccumulationRegionIndex]
         + gpuPassNanos[indirectCompositeRegionIndex];
      LightRegistry lightRegistry = worldRegistry.getLightRegistry();
      int fbWidth = MinecraftClient.getInstance().getWindow().getFramebufferWidth();
      int fbHeight = MinecraftClient.getInstance().getWindow().getFramebufferHeight();
      int renderWidth = Math.round(fbWidth * renderScale);
      int renderHeight = Math.round(fbHeight * renderScale);
      long renderPixels = (long) renderWidth * renderHeight;
      Photonic.info(
         "[Profiler] RTXDI/NRD GPU passes: LightTreeSamplingStage={}us InitialCandidates={}us DITemporalResampling={}us DISpatialResampling={}us DIShadeSamples={}us NRDClassifyTiles={}us NRDHitDistReconstruction={}us NRDPrepass={}us RELAXTemporalAccumulation={}us RELAXHistoryFix={}us RELAXHistoryClamping={}us NRDCopy={}us RELAXAntiFirefly={}us RELAXAtrousSmem={}us RELAXAtrous={}us ReSTIRGI={}us IndirectDenoise={}us LightingAccumulation={}us IndirectComposite={}us",
         this.toMicros(gpuPassNanos[lightTreeSamplingStageRegionIndex]),
         this.toMicros(gpuPassNanos[initialCandidatesRegionIndex]),
         this.toMicros(gpuPassNanos[diTemporalResamplingRegionIndex]),
         this.toMicros(gpuPassNanos[diSpatialResamplingRegionIndex]),
         this.toMicros(gpuPassNanos[diShadeSamplesRegionIndex]),
         this.toMicros(gpuPassNanos[nrdClassifyTilesRegionIndex]),
         this.toMicros(gpuPassNanos[nrdHitDistReconstructionRegionIndex]),
         this.toMicros(gpuPassNanos[nrdPrepassRegionIndex]),
         this.toMicros(gpuPassNanos[relaxTemporalAccumulationRegionIndex]),
         this.toMicros(gpuPassNanos[relaxHistoryFixRegionIndex]),
         this.toMicros(gpuPassNanos[relaxHistoryClampingRegionIndex]),
         this.toMicros(gpuPassNanos[nrdCopyRegionIndex]),
         this.toMicros(gpuPassNanos[relaxAntiFireflyRegionIndex]),
         this.toMicros(gpuPassNanos[relaxAtrousSmemRegionIndex]),
         this.toMicros(gpuPassNanos[relaxAtrousRegionIndex]),
         this.toMicros(gpuPassNanos[restirGIRegionIndex]),
         this.toMicros(gpuPassNanos[indirectDenoiseRegionIndex]),
         this.toMicros(gpuPassNanos[lightingAccumulationRegionIndex]),
         this.toMicros(gpuPassNanos[indirectCompositeRegionIndex])
      );
      Photonic.info(
         "[Profiler] RTXDI/NRD GPU buckets: DITotal={}us RELAXTotal={}us IndirectTotal={}us CompositeTotal={}us DIShare={} RELAXShare={} IndirectShare={} CompositeShare={}",
         this.toMicros(diTotal),
         this.toMicros(relaxTotal),
         this.toMicros(indirectTotal),
         this.toMicros(compositeTotal),
         this.formatShare(diTotal, gpuPassNanos),
         this.formatShare(relaxTotal, gpuPassNanos),
         this.formatShare(indirectTotal, gpuPassNanos),
         this.formatShare(compositeTotal, gpuPassNanos)
      );
      long diNs = diTotal;
      long relaxNs = relaxTotal;
      long indirectNs = indirectTotal;
      long compositeNs = compositeTotal;
      Photonic.info(
         "[Profiler] RTXDI/NRD per-pixel: diNspp={}ns relaxNspp={}ns indirectNspp={}ns compositeNspp={}ns regirCells={} regirLightSlots={}",
         renderPixels > 0 ? diNs / renderPixels : 0,
         renderPixels > 0 ? relaxNs / renderPixels : 0,
         renderPixels > 0 ? indirectNs / renderPixels : 0,
         renderPixels > 0 ? compositeNs / renderPixels : 0,
         lightRegistry.getRegirActiveCellCount(),
         lightRegistry.getRegirActiveLightSlotCount()
      );
   }

   private void logDirectAtrousBreakdown(long[] lastCpuDirectAtrousIterationNanos, int[] nrdAtrousStrides) {
      if (lastCpuDirectAtrousIterationNanos.length == 0) {
         return;
      }
      StringBuilder passSummary = new StringBuilder();
      long worstNanos = 0L;
      int worstPass = 0;
      for (int i = 0; i < lastCpuDirectAtrousIterationNanos.length; i++) {
         long iterationNanos = lastCpuDirectAtrousIterationNanos[i];
         if (i > 0) {
            passSummary.append(' ');
         }
         passSummary.append("pass")
            .append(i)
            .append("(step=")
            .append(nrdAtrousStrides[i])
            .append(")=")
            .append(this.toMicros(iterationNanos))
            .append("us");
         if (iterationNanos > worstNanos) {
            worstNanos = iterationNanos;
            worstPass = i;
         }
      }
      Photonic.info(
         "[Profiler] RTXDI/NRD RELAXDiffuseAtrous breakdown: passes={} worstPass=pass{}(step={})={}us",
         passSummary,
         worstPass,
         nrdAtrousStrides[worstPass],
         this.toMicros(worstNanos)
      );
   }

   private int getWorstPassIndex(long[] passNanos) {
      int worstIndex = 0;
      for (int i = 1; i < passNanos.length; i++) {
         if (passNanos[i] > passNanos[worstIndex]) {
            worstIndex = i;
         }
      }
      return worstIndex;
   }

   private long sumNanos(long[] passNanos) {
      long total = 0L;
      for (long passNano : passNanos) {
         total += passNano;
      }
      return total;
   }

   private String formatShare(long bucketNanos, long[] allPassNanos) {
      long total = this.sumNanos(allPassNanos);
      if (total <= 0L) {
         return "0.000";
      }
      return String.format(java.util.Locale.ROOT, "%.3f", (double) bucketNanos / (double) total);
   }

   private String formatBlendFactor(float blendFactor) {
      return String.format(java.util.Locale.ROOT, "%.3f", blendFactor);
   }

   private String describeStageGeometryUsage() {
      return "DIShadeSamples+NRDClassifyTiles+NRDHitDistReconstruction+NRDPrepass+RELAXTemporalAccumulation+RELAXHistoryFix+RELAXHistoryClamping+NRDCopy+RELAXAntiFirefly+RELAXAtrousSmem+RELAXAtrous+IndirectDenoise";
   }

   private long toMicros(long nanos) {
      return nanos / 1_000L;
   }
}
