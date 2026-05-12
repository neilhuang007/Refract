package at.redi2go.photonic.client.rendering.opengl.rendering.renderers;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.PhotonicsStorage;
import at.redi2go.photonic.client.api.PhotonicsProperties;
import at.redi2go.photonic.client.rendering.opengl.GpuTimerQuery;
import at.redi2go.photonic.client.rendering.opengl.objects.GLMemoryCollection;
import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.opengl.rendering.ColorFramebuffer;
import at.redi2go.photonic.client.rendering.opengl.rendering.PhotonicsShader;
import at.redi2go.photonic.client.rendering.opengl.rendering.RegirComputeProgram;
import at.redi2go.photonic.client.rendering.opengl.rendering.RoutingFramebuffer;
import at.redi2go.photonic.client.rendering.world.LightRegistry;
import at.redi2go.photonic.client.rendering.world.WorldRegistry;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import java.net.URL;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.function.Consumer;
import java.util.function.Function;
import java.util.function.IntSupplier;
import java.util.function.Supplier;
import net.irisshaders.iris.shaderpack.include.IncludeGraph;
import net.irisshaders.iris.gl.sampler.SamplerHolder;
import net.irisshaders.iris.gl.uniform.DynamicUniformHolder;
import net.irisshaders.iris.gl.uniform.UniformUpdateFrequency;
import net.irisshaders.iris.pipeline.CompositeRenderer;
import net.minecraft.client.MinecraftClient;
import org.jetbrains.annotations.Nullable;
import org.joml.Vector2f;
import org.joml.Vector3f;
import org.joml.Vector3i;
import org.joml.Vector4f;
import org.lwjgl.BufferUtils;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL15;
import org.lwjgl.opengl.GL30;
import org.lwjgl.opengl.GL42;
import org.lwjgl.opengl.GL43;

public class LightTreeRenderer extends MainRenderer {
   private enum DiReconnectionSource {
      PROPOSAL,
      TEMPORAL,
      FINAL
   }

   // NRD RELAX_DiffuseSpecular fused pipeline shader fragments (contract §9)
   private static final String relaxTemporalAccumulationFragment = "lighttree/nrd_temporal_accumulation.fsh";
   private static final String relaxHistoryFixFragment = "lighttree/nrd_history_fix.fsh";
   private static final String relaxAntiFireflyFragment = "lighttree/nrd_anti_firefly.fsh";
   private static final String relaxAtrousFragment = "lighttree/nrd_atrous.fsh";
   private static final String relaxHistoryClampingFragment = "lighttree/nrd_history_clamping.fsh";
   private static final String nrdClassifyTilesFragment = "lighttree/nrd_classify_tiles.fsh";
   private static final String nrdHitDistReconstructionFragment = "lighttree/nrd_hitdist_reconstruction.fsh";
   private static final String nrdPrepassFragment = "lighttree/nrd_prepass.fsh";
   private static final String nrdCopyFragment = "lighttree/nrd_copy.fsh";
   private static final String nrdAtrousSmemFragment = "lighttree/nrd_atrous_smem.fsh";
   // NRD history-confidence cascade (diffuse only, incremental first validation).
   // Reference: NRD-Sample/Shaders/ConfidenceBlur.cs.hlsl, NRD/Shaders/RELAX_TemporalAccumulation.cs.hlsl
   private static final String nrdConfidenceGradientFragment = "lighttree/nrd_confidence_gradient.fsh";
   private static final String nrdConfidenceBlurFragment     = "lighttree/nrd_confidence_blur.fsh";
   private static final String indirectBoilingFragment = "lighttree/light_tree_indirect_boiling_filter.fsh";
   private static final String indirectAccumulationFragment = "lighttree/light_tree_indirect_accumulation.fsh";
   private static final String indirectAccumulationLightingFragment = "lighttree/light_tree_indirect_accumulation_lighting.fsh";
   private static final String indirectAccumulationReservoirFragment = "lighttree/light_tree_indirect_accumulation_reservoir.fsh";
   private static final String indirectInitialFragment = "lighttree/light_tree_indirect_initial.fsh";
   private static final String indirectDenoisingFragment = "lighttree/light_tree_indirect_denoising.fsh";
   private static final String indirectTemporalReprojectionFragment = "lighttree/ReservoirSplatting/GIReprojectTemporalSamples.fsh";
   private static final String indirectTemporalBinningOffsetsFragment = "lighttree/ReservoirSplatting/GISortReprojectedReservoirsOffsets.fsh";
   private static final String indirectTemporalBinningFragment = "lighttree/ReservoirSplatting/GISortReprojectedReservoirs.fsh";
   private static final String indirectScatterTemporalFragment = "lighttree/ReservoirSplatting/GIScatterTemporalResampling.fsh";
   private static final String diShadeSamplesFragment = "lighttree/LightingPasses/DI/ShadeSamples.fsh";
   private static final String diInitialCandidatesFragment = "lighttree/LightingPasses/DI/InitialCandidates.fsh";
   private static final String diCollectTemporalSamplesFragment = "lighttree/LightingPasses/DI/CollectTemporalSamples.fsh";
   private static final String diRobustReuseOptimizationFragment = "lighttree/LightingPasses/DI/RobustReuseOptimization.fsh";
   private static final String diGatherTemporalResamplingFragment = "lighttree/LightingPasses/DI/GatherTemporalResampling.fsh";
   private static final String diTemporalReprojectionFragment = "lighttree/LightingPasses/DI/TemporalReprojection.fsh";
   private static final String diTemporalBinningOffsetsFragment = "lighttree/LightingPasses/DI/TemporalBinningOffsets.fsh";
   private static final String diTemporalBinningFragment = "lighttree/LightingPasses/DI/TemporalBinning.fsh";
   private static final String diMultiTemporalReprojectionFragment = "lighttree/LightingPasses/DI/MultiTemporalReprojection.fsh";
   private static final String diMultiTemporalBinningOffsetsFragment = "lighttree/LightingPasses/DI/MultiTemporalBinningOffsets.fsh";
   private static final String diMultiTemporalBinningFragment = "lighttree/LightingPasses/DI/MultiTemporalBinning.fsh";
   private static final String diScatterBackupTemporalResamplingFragment = "lighttree/LightingPasses/DI/ScatterBackupTemporalResampling.fsh";
   private static final String diMultiScatterTemporalResamplingFragment = "lighttree/LightingPasses/DI/MultiScatterTemporalResampling.fsh";
   private static final String diSpatialResamplingFragment = "lighttree/LightingPasses/DI/SpatialResampling.fsh";
   private static final String diShadeSamplesLightingFragment = "lighttree/LightingPasses/DI/ShadeSamplesLighting.fsh";
   private static final String diShadeSamplesReservoirFragment = "lighttree/LightingPasses/DI/ShadeSamplesReservoir.fsh";
   private static final String diPromoteReconnectionFragment = "lighttree/LightingPasses/DI/PromoteReconnection.fsh";
   private static final String diScatterTemporalResamplingFragment = "lighttree/LightingPasses/DI/ScatterTemporalResolve.fsh";
   private static final int[] proposalReservoirDrawBuffers = new int[]{-1, -1, -1, -1, -1, 0, 1, 2};
   private static final int[] shadeSamplesLightingDrawBuffers = new int[]{0, 1, -1, -1, -1};
   private static final int[] shadeSamplesReservoirDrawBuffers = new int[]{-1, -1, 0, 1, 2};
   private static final int profilerLogIntervalFrames = 60;
   private static final int TEMPORAL_GATHER_SHIFTED_PATH_COUNT = 8;
   // Matches one std430 ShiftedPathStorageRecord in restir_di_temporal_buffer_bridge.glsl.
   private static final int TEMPORAL_GATHER_SHIFTED_PATH_RECORD_VEC4_COUNT = 5;
   private static final int TEMPORAL_GATHER_SHIFTED_PATH_STRIDE_BYTES =
      TEMPORAL_GATHER_SHIFTED_PATH_RECORD_VEC4_COUNT * 4 * Float.BYTES;
   // GPU profiler region names match the new fused NRD pipeline (contract §9).
   private static final String[] gpuProfilerRegionNames = new String[]{
      "LightTreeSamplingStage", "InitialCandidates", "DITemporalResampling", "DISpatialResampling", "DIShadeSamples",
      "NRDClassifyTiles", "NRDHitDistReconstruction", "NRDPrepass",
      "RELAXTemporalAccumulation", "RELAXHistoryFix", "RELAXHistoryClamping",
      "NRDCopy", "RELAXAntiFirefly", "RELAXAtrousSmem", "RELAXAtrous",
      "ReSTIRGI", "IndirectDenoise", "LightingAccumulation", "IndirectComposite",
      "NRDConfidenceCascade"
   };
   private static final String[] profilerPassNames = new String[]{
      "LightTreeSamplingStage", "InitialCandidates", "DITemporalResampling", "DISpatialResampling", "DIShadeSamples",
      "NRDClassifyTiles", "NRDHitDistReconstruction", "NRDPrepass",
      "RELAXTemporalAccumulation", "RELAXHistoryFix", "RELAXHistoryClamping",
      "NRDCopy", "RELAXAntiFirefly", "RELAXAtrousSmem", "RELAXAtrous",
      "ReSTIRGI", "IndirectDenoise", "LightingAccumulation", "IndirectComposite",
      "NRDConfidenceCascade"
   };
   private static final int lightTreeSamplingStageRegionIndex = 0;
   private static final int initialCandidatesRegionIndex = 1;
   private static final int diTemporalResamplingRegionIndex = 2;
   private static final int diSpatialResamplingRegionIndex = 3;
   private static final int diShadeSamplesRegionIndex = 4;
   private static final int nrdClassifyTilesRegionIndex = 5;
   private static final int nrdHitDistReconstructionRegionIndex = 6;
   private static final int nrdPrepassRegionIndex = 7;
   private static final int relaxTemporalAccumulationRegionIndex = 8;
   private static final int relaxHistoryFixRegionIndex = 9;
   private static final int relaxHistoryClampingRegionIndex = 10;
   private static final int nrdCopyRegionIndex = 11;
   private static final int relaxAntiFireflyRegionIndex = 12;
   private static final int relaxAtrousSmemRegionIndex = 13;
   private static final int relaxAtrousRegionIndex = 14;
   private static final int restirGIRegionIndex = 15;
   private static final int indirectDenoiseRegionIndex = 16;
   private static final int lightingAccumulationRegionIndex = 17;
   private static final int indirectCompositeRegionIndex = 18;
   // NRD history-confidence cascade region (gradient pass + 5-pass blur loop).
   private static final int nrdConfidenceCascadeRegionIndex = 19;
   private boolean loggedRegirPresampleFrameSeedOverride = false;
   private boolean loggedRegirBuildFrameSeedOverride = false;
   @Nullable
   private Function<List<PhotonicsShader>, CompositeRenderer> compositeRendererCreator;

  private final PhotonicsProperties properties;
  private final ColorFramebuffer lightingBuffer;
  private final ColorFramebuffer lightingStageBuffer;
  private final ColorFramebuffer motionVectorBuffer;
  private final ColorFramebuffer directReservoirBuffer;
  private final ColorFramebuffer directSpatialReservoirBuffer;
  private final ColorFramebuffer directConfidenceBuffer;
  private final ColorFramebuffer directInitialDebugBuffer;
  private final ColorFramebuffer compatDirectSoftBuffer;
   // NRD RELAX_DiffuseSpecular permanent (swap-buffered) FBOs (contract §8).
   // These survive across frames; .read = prev frame, .write = current frame.
   private final ColorFramebuffer nrdDiffIllumPrevFb;             // RGBA16F
   private final ColorFramebuffer nrdDiffIllumResponsivePrevFb;   // RGBA16F
   private final ColorFramebuffer nrdSpecIllumPrevFb;             // RGBA16F
   private final ColorFramebuffer nrdSpecIllumResponsivePrevFb;   // RGBA16F
   private final ColorFramebuffer nrdHistoryLengthPrevFb;         // R8
   private final ColorFramebuffer nrdReflectionHitTPrevFb;        // R16F
   // NRD RELAX_DiffuseSpecular transient (single-buffered) FBOs (contract §8).
   // Written and consumed within the same frame.
   private final ColorFramebuffer nrdTilesFb;                     // R8 at ceil(w/16)xceil(h/16)
   private final ColorFramebuffer nrdDiffIllumPingFb;             // RGBA16F
   private final ColorFramebuffer nrdDiffIllumPongFb;             // RGBA16F
   private final ColorFramebuffer nrdSpecIllumPingFb;             // RGBA16F
   private final ColorFramebuffer nrdSpecIllumPongFb;             // RGBA16F
   private final ColorFramebuffer nrdHistoryLengthFb;             // R8
   private final ColorFramebuffer nrdSpecReprojectionConfidenceFb;// R8
   private final ColorFramebuffer nrdReflectionHitTCurrFb;        // R16F
   private final ColorFramebuffer nrdOutDiffRadianceHitDistFb;    // RGBA16F
   private final ColorFramebuffer nrdOutSpecRadianceHitDistFb;    // RGBA16F
   // Additional transient FBOs for hit-distance reconstruction (optional pass)
   private final ColorFramebuffer nrdDiffHitDistReconFb;          // RGBA16F
   private final ColorFramebuffer nrdSpecHitDistReconFb;          // RGBA16F
   // NRD history-confidence cascade FBOs.
   // nrdConfidenceGradientFb: gradient pass output, ping-pong src for first blur pass.
   // nrdConfidenceBlurPingFb / nrdConfidenceBlurPongFb: ping-pong pair for 5-pass blur.
   // The final blur output (in whichever side was last written) is the confidence texture
   // sampled next frame.  We use nrdConfidenceBlurPingFb as the "current confidence" read
   // after the cascade by registering it as ph_nrd_diff_confidence.
   private final ColorFramebuffer nrdConfidenceGradientFb;        // RGBA16F
   private final ColorFramebuffer nrdConfidenceBlurPingFb;        // RGBA16F (confidence read-side)
   private final ColorFramebuffer nrdConfidenceBlurPongFb;        // RGBA16F (intermediate)
  private final ColorFramebuffer indirectInitialReservoirBuffer;
  private final ColorFramebuffer indirectReservoirBuffer;
  private final ColorFramebuffer indirectDenoisedBuffer;
  // -- DI reconnection payloads --
  // Proposal and temporal reconnection outputs stay stage-local. Only the
  // frame-final spatial output is double-buffered as previous-frame history.
  private final ColorFramebuffer proposalReconnectionBuffer;
  private final ColorFramebuffer temporalReconnectionBuffer;
  private final ColorFramebuffer scatterReconnectionBuffer;
  private final ColorFramebuffer temporalReservoirBuffer;
  private final ColorFramebuffer temporalGatherBuffer;
  private DiReconnectionSource currentDiReconnectionSource = DiReconnectionSource.PROPOSAL;
  private GlMemoryManager temporalGatherFloatingCoordsMemoryManager;
  private GlMemoryManager temporalGatherShiftedPathsMemoryManager;
  private GlMemoryManager temporalScatterCurrentGlobalCountersMemoryManager;
  private GlMemoryManager temporalScatterCurrentCellCountersMemoryManager;
  private GlMemoryManager giTemporalScatterCurrentRecordsMemoryManager;
  private GlMemoryManager temporalScatterCurrentReservoirIndicesMemoryManager;
  private GlMemoryManager temporalScatterCurrentScatteredReservoirsMemoryManager;
  private GlMemoryManager temporalScatterCurrentCellOffsetsMemoryManager;
  private GlMemoryManager temporalScatterCurrentSortedReservoirsMemoryManager;
  private GlMemoryManager temporalScatterMultiGlobalCountersMemoryManager;
  private GlMemoryManager temporalScatterMultiCellCountersMemoryManager;
  private GlMemoryManager temporalScatterMultiReservoirIndicesMemoryManager;
  private GlMemoryManager temporalScatterMultiScatteredReservoirsMemoryManager;
  private GlMemoryManager temporalScatterMultiCellOffsetsMemoryManager;
  private GlMemoryManager temporalScatterMultiSortedReservoirsMemoryManager;
  private final RoutingFramebuffer proposalFramebuffer;
  private final RoutingFramebuffer proposalReservoirFramebuffer;
  private final RoutingFramebuffer reuseResolveFramebuffer;
  // NRD RELAX_DiffuseSpecular fused pipeline routing framebuffers (contract §9).
  private final RoutingFramebuffer nrdClassifyTilesFramebuffer;
  private final RoutingFramebuffer nrdHitDistReconstructionFramebuffer;
  private final RoutingFramebuffer nrdPrepassFramebuffer;
  private final RoutingFramebuffer directTemporalFramebuffer;
  private final RoutingFramebuffer directHistoryFixFramebuffer;
  private final RoutingFramebuffer directHistoryClampingFramebuffer;
  private final RoutingFramebuffer nrdCopyFramebuffer;
  private final RoutingFramebuffer directAntiFireflyFramebuffer;
  private final RoutingFramebuffer nrdAtrousSmemFramebuffer;
  private final RoutingFramebuffer directAtrousFramebuffer;
  // Confidence cascade routing framebuffers.
  // The blur framebuffer uses a dynamic supplier so each pass writes to the
  // appropriate ping or pong buffer (set via confidenceBlurIteration before renderAll).
  private final RoutingFramebuffer nrdConfidenceGradientFramebuffer;
  private final RoutingFramebuffer nrdConfidenceBlurFramebuffer;       // dynamic output
  private final RoutingFramebuffer indirectInitialFramebuffer;
  private final RoutingFramebuffer indirectBoilingFramebuffer;
  private final RoutingFramebuffer indirectAccumulationFramebuffer;
  private final RoutingFramebuffer indirectAccumulationLightingFramebuffer;
  private final RoutingFramebuffer indirectAccumulationReservoirFramebuffer;
  private final RoutingFramebuffer indirectDenoisingFramebuffer;
  private final RoutingFramebuffer positionWriteFramebuffer;
  private final RoutingFramebuffer shadeSamplesMonolithicFramebuffer;
  private final RoutingFramebuffer shadeSamplesFramebuffer;
  private final RoutingFramebuffer shadeSamplesReservoirFramebuffer;
  private final RoutingFramebuffer shadeSamplesReconnectionFramebuffer;
  private final RoutingFramebuffer temporalCollectFramebuffer;
  private final RoutingFramebuffer robustReuseOptimizationFramebuffer;
  private final RoutingFramebuffer temporalScatterStageFramebuffer;
  private final RoutingFramebuffer temporalReservoirFramebuffer;
  @Nullable
  private CompositeRenderer proposalStageRenderer;
  @Nullable
  private CompositeRenderer proposalReservoirRenderer;
  @Nullable
  private CompositeRenderer reuseResolveRenderer;
  // NRD RELAX_DiffuseSpecular fused pipeline renderers (contract §9).
  @Nullable
  private CompositeRenderer nrdClassifyTilesRenderer;
  @Nullable
  private CompositeRenderer nrdHitDistReconstructionRenderer;
  @Nullable
  private CompositeRenderer nrdPrepassRenderer;
  @Nullable
  private CompositeRenderer directTemporalRenderer;
  @Nullable
  private CompositeRenderer directHistoryFixRenderer;
  @Nullable
  private CompositeRenderer directHistoryClampingRenderer;
  @Nullable
  private CompositeRenderer nrdCopyRenderer;
  @Nullable
  private CompositeRenderer directAntiFireflyRenderer;
  @Nullable
  private CompositeRenderer nrdAtrousSmemRenderer;
  @Nullable
  private CompositeRenderer directAtrousRenderer;
  // NRD history-confidence cascade renderers (gradient pass + blur cascade).
  @Nullable
  private CompositeRenderer nrdConfidenceGradientRenderer;
  @Nullable
  private CompositeRenderer nrdConfidenceBlurRenderer;
  @Nullable
  private CompositeRenderer indirectInitialRenderer;
  @Nullable
  private CompositeRenderer indirectBoilingRenderer;
  @Nullable
  private CompositeRenderer indirectTemporalReprojectionRenderer;
  @Nullable
  private CompositeRenderer indirectTemporalBinningOffsetsRenderer;
  @Nullable
  private CompositeRenderer indirectTemporalBinningRenderer;
  @Nullable
  private CompositeRenderer indirectScatterTemporalRenderer;
  @Nullable
  private CompositeRenderer indirectAccumulationRenderer;
  @Nullable
  private CompositeRenderer indirectAccumulationLightingRenderer;
  @Nullable
  private CompositeRenderer indirectAccumulationReservoirRenderer;
  @Nullable
  private CompositeRenderer indirectDenoisingRenderer;
  @Nullable
  private CompositeRenderer accumulationRenderer;
  @Nullable
  private CompositeRenderer indirectRenderer;
  @Nullable
  private CompositeRenderer shadeSamplesMonolithicRenderer;
  @Nullable
  private CompositeRenderer shadeSamplesReservoirRenderer;
  @Nullable
  private CompositeRenderer shadeSamplesRenderer;
  @Nullable
  private CompositeRenderer shadeSamplesReconnectionRenderer;
  @Nullable
  private CompositeRenderer temporalCollectRenderer;
  @Nullable
  private CompositeRenderer robustReuseOptimizationRenderer;
  @Nullable
  private CompositeRenderer temporalGatherRenderer;
  @Nullable
  private CompositeRenderer temporalScatterReprojectionRenderer;
  @Nullable
  private CompositeRenderer temporalMultiScatterReprojectionRenderer;
  @Nullable
  private CompositeRenderer temporalScatterBinningOffsetsRenderer;
  @Nullable
  private CompositeRenderer temporalMultiScatterBinningOffsetsRenderer;
  @Nullable
  private CompositeRenderer temporalScatterBinningRenderer;
  @Nullable
  private CompositeRenderer temporalMultiScatterBinningRenderer;
  @Nullable
  private CompositeRenderer scatterTemporalRenderer;
  @Nullable
  private CompositeRenderer scatterBackupTemporalRenderer;
  @Nullable
  private CompositeRenderer multiScatterTemporalRenderer;
  private final GpuTimerQuery gpuTimerQuery;
  @Nullable
  private RegirComputeProgram regirComputeProgram;
  // Hard-coded 5-pass atrous cascade per contract §1: SMEM(stride=1) + 4 passes (strides 2,4,8,16).
  // directAtrousIteration 0 = SMEM pass (nrdAtrousSmemRenderer), 1-4 = regular atrous passes.
  private static final int[] NRD_ATROUS_STRIDES = {1, 2, 4, 8, 16};
  // Confidence blur cascade: 5 passes with step sizes matching NRD-Sample reference.
  // Reference: NRD-Sample/Shaders/ConfidenceBlur.cs.hlsl — step 1..5 in HLSL maps to
  // texel offsets 1,2,4,8,16 in our GLSL port.
  private static final int[] NRD_CONFIDENCE_BLUR_STEPS = {1, 2, 4, 8, 16};
  // Current blur step size uniform value (updated by renderConfidenceCascade each pass).
  private int currentConfidenceBlurStep = 1;
  // Whether the confidence cascade has completed at least one full frame.
  // Set to true after the first full cascade run; controls ph_nrd_has_history_confidence.
  private boolean hasHistoryConfidence = false;
  private final Consumer<String> localLightSamplingModeObserver;
  private final Consumer<String> temporalScatterIsolationModeObserver;
  private final Consumer<Boolean> indirectTemporalReuseObserver;
   private int temporalScatterPixelCapacity;
  private int temporalScatterContributorCapacity;
  private int directAtrousIteration = 0;
   private boolean compatDirectSoftDirty = true;
   private boolean reservoirHistoryDirty = true;
   private boolean directTemporalReuseActiveThisFrame = false;
   private boolean indirectTemporalSplattingActiveThisFrame = false;
   private boolean disabledIndirectOutputsCleared = false;
   private int renderFrameIndex = 0;
   // Ring buffer of recently-changed block world-space centres, used to locally cap
   // NRD historyLength near dirty pixels so new lighting converges fast.
   private static final int dirtyBlockCapacity = 32;
   private static final int dirtyBlockTtl = 24;
   private final float[] dirtyBlockCentres = new float[dirtyBlockCapacity]; // x per slot
   private final float[] dirtyBlockCentresY = new float[dirtyBlockCapacity];
   private final float[] dirtyBlockCentresZ = new float[dirtyBlockCapacity];
   private final int[] dirtyBlockFrameSeen = new int[dirtyBlockCapacity];
   // Flat float[128] buffer shipped to the shader as uniform vec4 ph_nrd_dirty_blocks[32].
   private final float[] dirtyBlockBuffer = new float[dirtyBlockCapacity * 4];
   private int dirtyBlockWriteHead = 0;
   {
      java.util.Arrays.fill(this.dirtyBlockFrameSeen, Integer.MIN_VALUE);
   }
  private int profilerFrameCounter = 0;
  private long lastCpuLightTreeSamplingStageNanos;
  private long lastCpuInitialCandidatesNanos;
  private long lastCpuDITemporalResamplingNanos;
  private long lastCpuDISpatialResamplingNanos;
  private long lastCpuDIShadeSamplesNanos;
  private long lastCpuNRDClassifyTilesNanos;
  private long lastCpuNRDHitDistReconstructionNanos;
  private long lastCpuNRDPrepassNanos;
  private long lastCpuRELAXTemporalAccumulationNanos;
  private long lastCpuRELAXHistoryFixNanos;
  private long lastCpuRELAXHistoryClampingNanos;
  private long lastCpuNRDCopyNanos;
  private long lastCpuRELAXAntiFireflyNanos;
  private long lastCpuRELAXAtrousSmemNanos;
  private long lastCpuRELAXAtrousNanos;
  private long[] lastCpuDirectAtrousIterationNanos;
  private float[] cachedRegirPdfPowers;
  private int cachedRegirPdfLightCount = -1;
  private long cachedRegirSemanticLayoutHash = Long.MIN_VALUE;
  private long cachedRegirBuildSemanticHash = Long.MIN_VALUE;
  private int cachedRegirBuildCamCellX = Integer.MIN_VALUE;
  private int cachedRegirBuildCamCellY = Integer.MIN_VALUE;
  private int cachedRegirBuildCamCellZ = Integer.MIN_VALUE;
  private boolean hasValidRegirBuild = false;
  private long lastCpuReSTIRGINanos;
  private long lastCpuIndirectDenoiseNanos;
  private long lastCpuLightingAccumulationNanos;
  private long lastCpuIndirectCompositeNanos;
  private long lastCpuNRDConfidenceCascadeNanos;
   public LightTreeRenderer(WorldRegistry worldRegistry, float renderScale, PhotonicsProperties properties) {
      super(worldRegistry, renderScale);
      this.properties = properties;
      // Hard-coded 5-pass cascade: SMEM(iter=0) + 4 regular atrous passes (iters 1-4).
      this.lastCpuDirectAtrousIterationNanos = new long[NRD_ATROUS_STRIDES.length];
      this.lightingBuffer = new ColorFramebuffer(renderScale);
      this.createLightingBufferAttachments(this.lightingBuffer);
      this.lightingStageBuffer = new ColorFramebuffer(renderScale);
      this.createLightingStageAttachments(this.lightingStageBuffer);
      this.motionVectorBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directReservoirBuffer = this.createDirectReservoirFramebuffer(renderScale);
      this.directSpatialReservoirBuffer = this.createDirectReservoirFramebuffer(renderScale);
      this.proposalReconnectionBuffer = this.createReconnectionFramebuffer(renderScale);
      this.temporalReconnectionBuffer = this.createReconnectionFramebuffer(renderScale);
      this.scatterReconnectionBuffer = this.createReconnectionFramebuffer(renderScale);
      this.temporalReservoirBuffer = this.createTemporalReservoirFramebuffer(renderScale);
      this.temporalGatherBuffer = this.createTemporalGatherFramebuffer(renderScale);
      this.temporalCollectFramebuffer = this.createTemporalCollectFramebuffer();
      this.robustReuseOptimizationFramebuffer = this.createRobustReuseOptimizationFramebuffer();
      this.temporalScatterPixelCapacity = this.getTemporalScatterPixelCapacity();
      this.temporalScatterContributorCapacity = this.getTemporalScatterContributorCapacity();
      this.allocateTemporalScatterMemoryManagers();
      this.directConfidenceBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directInitialDebugBuffer = this.createDirectPackedDebugFramebuffer(renderScale);
      this.compatDirectSoftBuffer = new ColorFramebuffer(renderScale);
      this.compatDirectSoftBuffer.createAttachment("direct_soft_compat", "RGBA16F", false);
      // NRD permanent (swap-buffered) FBOs
      this.nrdDiffIllumPrevFb           = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.nrdDiffIllumResponsivePrevFb  = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.nrdSpecIllumPrevFb           = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.nrdSpecIllumResponsivePrevFb  = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.nrdHistoryLengthPrevFb       = this.createDirectSignalFramebuffer(renderScale, "R8");
      this.nrdReflectionHitTPrevFb      = this.createDirectSignalFramebuffer(renderScale, "R16F");
      // NRD transient (single-buffered) FBOs
      this.nrdTilesFb                   = this.createNrdTileFramebuffer(renderScale);
      this.nrdDiffIllumPingFb           = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.nrdDiffIllumPongFb           = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.nrdSpecIllumPingFb           = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.nrdSpecIllumPongFb           = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.nrdHistoryLengthFb           = this.createDirectSignalFramebuffer(renderScale, "R8");
      this.nrdSpecReprojectionConfidenceFb = this.createDirectSignalFramebuffer(renderScale, "R8");
      this.nrdReflectionHitTCurrFb      = this.createDirectSignalFramebuffer(renderScale, "R16F");
      this.nrdOutDiffRadianceHitDistFb  = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.nrdOutSpecRadianceHitDistFb  = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.nrdDiffHitDistReconFb        = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.nrdSpecHitDistReconFb        = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      // Confidence cascade FBOs (RGBA16F; full render resolution)
      this.nrdConfidenceGradientFb      = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.nrdConfidenceBlurPingFb      = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.nrdConfidenceBlurPongFb      = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.indirectInitialReservoirBuffer = this.createIndirectReservoirFramebuffer(renderScale);
      this.indirectReservoirBuffer = this.createIndirectReservoirFramebuffer(renderScale);
      this.indirectDenoisedBuffer = new ColorFramebuffer(renderScale);
      this.indirectDenoisedBuffer.createAttachment("data", "RGBA16F", false);
      this.proposalFramebuffer = this.createProposalGeometryFramebuffer();
      this.proposalReservoirFramebuffer = this.createProposalReservoirFramebuffer();
      this.reuseResolveFramebuffer = this.createReuseResolveFramebuffer();
      this.nrdClassifyTilesFramebuffer      = this.createNrdClassifyTilesFramebuffer();
      this.nrdHitDistReconstructionFramebuffer = this.createNrdHitDistReconstructionFramebuffer();
      this.nrdPrepassFramebuffer            = this.createNrdPrepassFramebuffer();
      this.directTemporalFramebuffer        = this.createDirectTemporalFramebuffer();
      this.directHistoryFixFramebuffer      = this.createDirectHistoryFixFramebuffer();
      this.directHistoryClampingFramebuffer = this.createDirectHistoryClampingFramebuffer();
      this.nrdCopyFramebuffer               = this.createNrdCopyFramebuffer();
      this.directAntiFireflyFramebuffer     = this.createDirectAntiFireflyFramebuffer();
      this.nrdAtrousSmemFramebuffer         = this.createNrdAtrousSmemFramebuffer();
      this.directAtrousFramebuffer          = this.createDirectAtrousFramebuffer();
      this.nrdConfidenceGradientFramebuffer = this.createNrdConfidenceGradientFramebuffer();
      this.nrdConfidenceBlurFramebuffer     = this.createNrdConfidenceBlurFramebuffer();
      this.indirectInitialFramebuffer = this.createIndirectInitialFramebuffer();
      this.indirectBoilingFramebuffer = this.createIndirectBoilingFramebuffer();
      this.indirectAccumulationFramebuffer = this.createIndirectAccumulationFramebuffer();
      this.indirectAccumulationLightingFramebuffer = this.createIndirectAccumulationLightingFramebuffer();
      this.indirectAccumulationReservoirFramebuffer = this.createIndirectAccumulationReservoirFramebuffer();
      this.indirectDenoisingFramebuffer = this.createIndirectDenoisingFramebuffer();
      this.positionWriteFramebuffer = this.createPositionWriteFramebuffer();
      this.shadeSamplesMonolithicFramebuffer = this.createShadeSamplesMonolithicFramebuffer();
      this.shadeSamplesFramebuffer = this.createShadeSamplesLightingFramebuffer();
      this.shadeSamplesReservoirFramebuffer = this.createShadeSamplesReservoirFramebuffer();
      this.shadeSamplesReconnectionFramebuffer = this.createShadeSamplesReconnectionFramebuffer();
      this.temporalScatterStageFramebuffer = this.createTemporalScatterStageFramebuffer();
      this.temporalReservoirFramebuffer = this.createTemporalReservoirRoutingFramebuffer();
      this.gpuTimerQuery = this.createGpuTimerQuery();
      this.regirComputeProgram = new RegirComputeProgram();
      this.localLightSamplingModeObserver = ignored -> this.invalidateDirectReuseHistory();
      this.temporalScatterIsolationModeObserver = ignored -> this.invalidateDirectReuseHistory();
      this.indirectTemporalReuseObserver = ignored -> this.invalidateReservoirHistory();
      PhotonicsStorage.RESTIR_LOCAL_LIGHT_SAMPLING_MODE.addObserver(this.localLightSamplingModeObserver);
      PhotonicsStorage.RESTIR_TEMPORAL_REUSE.addObserver(this.temporalScatterIsolationModeObserver);
      PhotonicsStorage.RESTIR_GI_TEMPORAL_REUSE.addObserver(this.indirectTemporalReuseObserver);
   }

   @Override
   protected GLMemoryCollection buildGlMemoryCollection() {
      GLMemoryCollection memoryCollection = super.buildGlMemoryCollection();
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getGlobalLightCdfMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getRegirCellCountMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getRegirLightIndexMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getRegirLightPdfMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getRegirCompactLightDataMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getRegirHashChecksumMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getRegirHashKeyMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getLightReverseMappingMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getPreviousLightsMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getNeighborOffsetMemoryManager());
      this.addTemporalScatterMemoryManagers(memoryCollection);
      return memoryCollection;
   }

   private void addTemporalScatterMemoryManagers(GLMemoryCollection memoryCollection) {
      this.addTemporalScatterMemoryManager(memoryCollection, () -> this.temporalGatherFloatingCoordsMemoryManager);
      this.addTemporalScatterMemoryManager(memoryCollection, () -> this.temporalGatherShiftedPathsMemoryManager);
      this.addTemporalScatterMemoryManager(memoryCollection, () -> this.temporalScatterCurrentGlobalCountersMemoryManager);
      this.addTemporalScatterMemoryManager(memoryCollection, () -> this.temporalScatterCurrentCellCountersMemoryManager);
      this.addTemporalScatterMemoryManager(memoryCollection, () -> this.giTemporalScatterCurrentRecordsMemoryManager);
      this.addTemporalScatterMemoryManager(memoryCollection, () -> this.temporalScatterCurrentReservoirIndicesMemoryManager);
      this.addTemporalScatterMemoryManager(memoryCollection, () -> this.temporalScatterCurrentScatteredReservoirsMemoryManager);
      this.addTemporalScatterMemoryManager(memoryCollection, () -> this.temporalScatterCurrentCellOffsetsMemoryManager);
      this.addTemporalScatterMemoryManager(memoryCollection, () -> this.temporalScatterCurrentSortedReservoirsMemoryManager);
      this.addTemporalScatterMemoryManager(memoryCollection, () -> this.temporalScatterMultiGlobalCountersMemoryManager);
      this.addTemporalScatterMemoryManager(memoryCollection, () -> this.temporalScatterMultiCellCountersMemoryManager);
      this.addTemporalScatterMemoryManager(memoryCollection, () -> this.temporalScatterMultiReservoirIndicesMemoryManager);
      this.addTemporalScatterMemoryManager(memoryCollection, () -> this.temporalScatterMultiScatteredReservoirsMemoryManager);
      this.addTemporalScatterMemoryManager(memoryCollection, () -> this.temporalScatterMultiCellOffsetsMemoryManager);
      this.addTemporalScatterMemoryManager(memoryCollection, () -> this.temporalScatterMultiSortedReservoirsMemoryManager);
   }

   private void addTemporalScatterMemoryManager(GLMemoryCollection memoryCollection, Supplier<GlMemoryManager> managerSupplier) {
      memoryCollection.add(managerSupplier);
   }

   @Override
   public void createCompositeRenderer(Function<List<PhotonicsShader>, CompositeRenderer> rendererCreator) {
      this.compositeRendererCreator = rendererCreator;
      this.proposalStageRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("lighttree/light_tree_sampling_stage.fsh", "common/screen.vsh", this.memoryCollection, this.proposalFramebuffer))
      );
      this.proposalReservoirRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diInitialCandidatesFragment, "common/screen.vsh", this.memoryCollection, this.proposalReservoirFramebuffer))
      );
      this.reuseResolveRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diSpatialResamplingFragment, "common/screen.vsh", this.memoryCollection, this.reuseResolveFramebuffer))
      );
      this.temporalCollectRenderer = null;
      this.robustReuseOptimizationRenderer = null;
      this.temporalGatherRenderer = null;
      this.temporalScatterReprojectionRenderer = null;
      this.temporalMultiScatterReprojectionRenderer = null;
      this.temporalScatterBinningOffsetsRenderer = null;
      this.temporalMultiScatterBinningOffsetsRenderer = null;
      this.temporalScatterBinningRenderer = null;
      this.temporalMultiScatterBinningRenderer = null;
      this.scatterTemporalRenderer = null;
      this.scatterBackupTemporalRenderer = null;
      this.multiScatterTemporalRenderer = null;
      // NRD RELAX_DiffuseSpecular fused pipeline renderers (contract §9).
      this.nrdClassifyTilesRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(nrdClassifyTilesFragment, "common/screen.vsh", this.memoryCollection, this.nrdClassifyTilesFramebuffer))
      );
      this.nrdHitDistReconstructionRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(nrdHitDistReconstructionFragment, "common/screen.vsh", this.memoryCollection, this.nrdHitDistReconstructionFramebuffer))
      );
      this.nrdPrepassRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(nrdPrepassFragment, "common/screen.vsh", this.memoryCollection, this.nrdPrepassFramebuffer))
      );
      this.directTemporalRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(relaxTemporalAccumulationFragment, "common/screen.vsh", this.memoryCollection, this.directTemporalFramebuffer))
      );
      this.directHistoryFixRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(relaxHistoryFixFragment, "common/screen.vsh", this.memoryCollection, this.directHistoryFixFramebuffer))
      );
      this.directHistoryClampingRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(relaxHistoryClampingFragment, "common/screen.vsh", this.memoryCollection, this.directHistoryClampingFramebuffer))
      );
      this.nrdCopyRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(nrdCopyFragment, "common/screen.vsh", this.memoryCollection, this.nrdCopyFramebuffer))
      );
      this.directAntiFireflyRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(relaxAntiFireflyFragment, "common/screen.vsh", this.memoryCollection, this.directAntiFireflyFramebuffer))
      );
      this.nrdAtrousSmemRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(nrdAtrousSmemFragment, "common/screen.vsh", this.memoryCollection, this.nrdAtrousSmemFramebuffer))
      );
      this.directAtrousRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(relaxAtrousFragment, "common/screen.vsh", this.memoryCollection, this.directAtrousFramebuffer))
      );
      // Confidence cascade renderers (gradient pass + reusable blur pass).
      this.nrdConfidenceGradientRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(nrdConfidenceGradientFragment, "common/screen.vsh", this.memoryCollection, this.nrdConfidenceGradientFramebuffer))
      );
      // Blur renderer uses nrdConfidenceBlurFramebuffer whose attachment supplier is dynamic
      // (getCurrentConfidenceBlurOutputTexture), so the same renderer can be rendered 5 times
      // with different output destinations per renderConfidenceCascade().
      this.nrdConfidenceBlurRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(nrdConfidenceBlurFragment, "common/screen.vsh", this.memoryCollection, this.nrdConfidenceBlurFramebuffer))
      );
      this.indirectInitialRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(indirectInitialFragment, "common/screen.vsh", this.memoryCollection, this.indirectInitialFramebuffer))
      );
      this.indirectBoilingRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(indirectBoilingFragment, "common/screen.vsh", this.memoryCollection, this.indirectBoilingFramebuffer))
      );
      this.indirectTemporalReprojectionRenderer = null;
      this.indirectTemporalBinningOffsetsRenderer = null;
      this.indirectTemporalBinningRenderer = null;
      this.indirectScatterTemporalRenderer = null;
      // Split GI accumulation: lighting writes full-res lightingBuffer attachments
      // (indirect, indirect_variance, handheld); reservoir writes half-res
      // indirectReservoirBuffer attachments (position, normal, radiance, meta).
      // OpenGL FBO attachments must share resolution; checkerboard makes the
      // reservoir buffer half-width. The monolithic renderer is set to null.
      this.indirectAccumulationRenderer = null;
      this.indirectAccumulationLightingRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(indirectAccumulationLightingFragment, "common/screen.vsh", this.memoryCollection, this.indirectAccumulationLightingFramebuffer))
      );
      this.indirectAccumulationReservoirRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(indirectAccumulationReservoirFragment, "common/screen.vsh", this.memoryCollection, this.indirectAccumulationReservoirFramebuffer))
      );
      this.indirectDenoisingRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(indirectDenoisingFragment, "common/screen.vsh", this.memoryCollection, this.indirectDenoisingFramebuffer))
      );
      this.accumulationRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("lighttree/light_tree_accumulation.fsh", "common/screen.vsh", this.memoryCollection, this.positionWriteFramebuffer))
      );
      this.indirectRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("common/indirect.fsh", "common/screen.vsh", this.memoryCollection, null))
      );
      // Split shading path: lighting writes to full-res lightingStageBuffer, reservoir
      // writes to half-res directReservoirBuffer (when checkerboard active). Monolithic
      // path can't be used with checkerboard because it mixes full-res lighting with
      // half-res reservoir attachments in one framebuffer (RoutingFramebuffer.bind sets
      // viewport from attachment[0]; mixed-size attachments produce undefined writes).
      this.shadeSamplesMonolithicRenderer = null;
      this.shadeSamplesRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diShadeSamplesLightingFragment, "common/screen.vsh", this.memoryCollection, this.shadeSamplesFramebuffer))
      );
      this.shadeSamplesReservoirRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diShadeSamplesReservoirFragment, "common/screen.vsh", this.memoryCollection, this.shadeSamplesReservoirFramebuffer))
      );
      this.shadeSamplesReconnectionRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diPromoteReconnectionFragment, "common/screen.vsh", this.memoryCollection, this.shadeSamplesReconnectionFramebuffer))
      );
      this.compileRegirComputeShader();
   }

   @Nullable
   private CompositeRenderer createLazyRenderer(String fragment, @Nullable RoutingFramebuffer framebuffer) {
      if (this.compositeRendererCreator == null) {
         return null;
      }
      return this.compositeRendererCreator.apply(
         List.of(new PhotonicsShader(fragment, "common/screen.vsh", this.memoryCollection, framebuffer))
      );
   }

   @Nullable
   private CompositeRenderer createLazyRenderer(List<PhotonicsShader> shaders) {
      if (this.compositeRendererCreator == null) {
         return null;
      }
      return this.compositeRendererCreator.apply(shaders);
   }

   private void ensureTemporalGatherRenderers() {
      if (this.temporalCollectRenderer == null) {
         this.temporalCollectRenderer = this.createLazyRenderer(diCollectTemporalSamplesFragment, this.temporalCollectFramebuffer);
      }
      if (
         this.robustReuseOptimizationRenderer == null
            && this.compositeRendererCreator != null
            && "robust".equals(
               PhotonicsStorage.normalizeRestirTemporalGatherMode(PhotonicsStorage.RESTIR_TEMPORAL_GATHER_MODE.value)
            )
      ) {
         this.robustReuseOptimizationRenderer = this.createLazyRenderer(
            List.of(new PhotonicsShader(diRobustReuseOptimizationFragment, "common/screen.vsh", this.memoryCollection, this.robustReuseOptimizationFramebuffer))
         );
      }
      if (this.temporalGatherRenderer == null) {
         this.temporalGatherRenderer = this.createLazyRenderer(diGatherTemporalResamplingFragment, this.temporalReservoirFramebuffer);
      }
   }

   private void ensureTemporalScatterRenderers() {
      if (this.temporalScatterReprojectionRenderer == null) {
         this.temporalScatterReprojectionRenderer = this.createLazyRenderer(diTemporalReprojectionFragment, this.temporalScatterStageFramebuffer);
      }
      if (this.temporalScatterBinningOffsetsRenderer == null) {
         this.temporalScatterBinningOffsetsRenderer = this.createLazyRenderer(diTemporalBinningOffsetsFragment, this.temporalScatterStageFramebuffer);
      }
      if (this.temporalScatterBinningRenderer == null) {
         this.temporalScatterBinningRenderer = this.createLazyRenderer(diTemporalBinningFragment, this.temporalScatterStageFramebuffer);
      }
      if (this.scatterTemporalRenderer == null) {
         this.scatterTemporalRenderer = this.createLazyRenderer(diScatterTemporalResamplingFragment, this.temporalReservoirFramebuffer);
      }
   }

   private void ensureMultiTemporalScatterRenderers() {
      if (this.temporalMultiScatterReprojectionRenderer == null) {
         this.temporalMultiScatterReprojectionRenderer = this.createLazyRenderer(diMultiTemporalReprojectionFragment, this.temporalScatterStageFramebuffer);
      }
      if (this.temporalMultiScatterBinningOffsetsRenderer == null) {
         this.temporalMultiScatterBinningOffsetsRenderer = this.createLazyRenderer(diMultiTemporalBinningOffsetsFragment, this.temporalScatterStageFramebuffer);
      }
      if (this.temporalMultiScatterBinningRenderer == null) {
         this.temporalMultiScatterBinningRenderer = this.createLazyRenderer(diMultiTemporalBinningFragment, this.temporalScatterStageFramebuffer);
      }
      if (this.multiScatterTemporalRenderer == null) {
         this.multiScatterTemporalRenderer = this.createLazyRenderer(diMultiScatterTemporalResamplingFragment, this.temporalReservoirFramebuffer);
      }
   }

   private void ensureIndirectTemporalSplattingRenderers() {
      if (this.indirectTemporalReprojectionRenderer == null) {
         this.indirectTemporalReprojectionRenderer = this.createLazyRenderer(indirectTemporalReprojectionFragment, this.temporalScatterStageFramebuffer);
      }
      if (this.indirectTemporalBinningOffsetsRenderer == null) {
         this.indirectTemporalBinningOffsetsRenderer = this.createLazyRenderer(indirectTemporalBinningOffsetsFragment, this.temporalScatterStageFramebuffer);
      }
      if (this.indirectTemporalBinningRenderer == null) {
         this.indirectTemporalBinningRenderer = this.createLazyRenderer(indirectTemporalBinningFragment, this.temporalScatterStageFramebuffer);
      }
      if (this.indirectScatterTemporalRenderer == null) {
         this.indirectScatterTemporalRenderer = this.createLazyRenderer(indirectScatterTemporalFragment, this.indirectBoilingFramebuffer);
      }
   }

   private void compileRegirComputeShader() {
      if (this.regirComputeProgram == null || this.regirComputeProgram.isCompiled()) {
         return;
      }
      try {
         String presampleSource = this.loadShaderSource("lighttree/regir_presample_tiles.glsl");
         if (presampleSource != null) {
            this.regirComputeProgram.compilePresample(presampleSource);
         } else {
            Photonic.warn("[LightTree] Presample tile shader not found — ReGIR build will use tile buffer only if present");
         }
         String buildSource = this.loadShaderSource("lighttree/regir_build.glsl");
         if (buildSource != null) {
            this.regirComputeProgram.compile(buildSource);
            if (this.regirComputeProgram.isCompiled()) {
               this.worldRegistry.getLightRegistry().setGpuRegirBuildEnabled(!this.isGpuRegirBuildDisabledForIsolation());
            }
         }
      } catch (Exception e) {
         Photonic.error("[LightTree] Failed to compile ReGIR compute shaders", e);
      }
   }

   private boolean isGpuRegirBuildDisabledForIsolation() {
      return Boolean.getBoolean("photonics.disableGpuRegirBuild");
   }

   private String loadShaderSource(String shaderRelativePath) {
      String resourcePath = "assets/photonic/shaders/" + shaderRelativePath;
      Path devEnvPath = Path.of("../src/main/resources/" + resourcePath);
      if (Files.exists(devEnvPath)) {
         try {
            return Files.readString(devEnvPath);
         } catch (Exception e) {
            Photonic.warn("[LightTree] Failed to read dev shader from {}: {}", devEnvPath, e.getMessage());
         }
      }
      try {
         URL jarUrl = IncludeGraph.class.getClassLoader().getResource(resourcePath);
         if (jarUrl != null) {
            return Files.readString(Path.of(jarUrl.toURI()));
         }
      } catch (Exception e) {
         Photonic.warn("[LightTree] Failed to read shader from jar ({}): {}", resourcePath, e.getMessage());
      }
      Photonic.warn("[LightTree] Shader source not found: {}", resourcePath);
      return null;
   }

   @Override
   public void registerCustomTextures(SamplerHolder samplers) {
      if (this.isCurrentPhotonicsFragment(diScatterBackupTemporalResamplingFragment)) {
         this.registerScatterBackupTemporalTextures(samplers);
         return;
      }
      this.addTextureSampler(samplers, "radiosity_position", this::getCurrentGeometryPositionTexture);
      this.addTextureSampler(samplers, "radiosity_normal", this::getCurrentGeometryNormalTexture);
      this.addTextureSampler(samplers, "radiosity_mapped_normal", this::getCurrentMappedNormalTexture);
      this.addTextureSampler(samplers, "radiosity_albedo", this::getCurrentAlbedoTexture);
      this.addTextureSampler(samplers, "radiosity_material", this::getCurrentMaterialTexture);
      this.addTextureSampler(samplers, "radiosity_identity", this::getCurrentIdentityTexture);
      this.addTextureSampler(samplers, "radiosity_proposal_reservoirs", () -> this.directReservoirBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "radiosity_proposal_reservoir_samples", () -> this.directReservoirBuffer.getWriteAttachment("sample"));
      this.addTextureSampler(samplers, "radiosity_proposal_reservoir_meta", () -> this.directReservoirBuffer.getWriteAttachment("meta"));
      this.addTextureSampler(samplers, "radiosity_direct", this::getResolvedDirectTexture);
      this.addTextureSampler(samplers, "radiosity_reservoirs", this::getCurrentDirectReservoirDataTexture);
      this.addTextureSampler(samplers, "radiosity_reservoir_samples", this::getCurrentDirectReservoirSampleTexture);
      this.addTextureSampler(samplers, "radiosity_reservoir_meta", this::getCurrentDirectReservoirMetaTexture);
      this.addTextureSampler(samplers, "radiosity_spatial_reservoirs", this::getCurrentSpatialReservoirDataTexture);
      this.addTextureSampler(samplers, "radiosity_spatial_reservoir_samples", this::getCurrentSpatialReservoirSampleTexture);
      this.addTextureSampler(samplers, "radiosity_spatial_reservoir_meta", this::getCurrentSpatialReservoirMetaTexture);
      this.addTextureSampler(samplers, "direct_initial_debug_input", () -> this.directInitialDebugBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "radiosity_direct_soft", this::getCompatDirectSoftTexture);
      this.addTextureSampler(samplers, "radiosity_handheld", () -> this.lightingBuffer.getWriteAttachment("handheld"));
      this.addTextureSampler(samplers, "radiosity_lighting_variance", () -> this.lightingBuffer.getWriteAttachment("lighting_variance"));
      this.addTextureSampler(samplers, "radiosity_indirect", () -> this.lightingBuffer.getWriteAttachment("indirect"));
      this.addTextureSampler(samplers, "radiosity_indirect_variance", () -> this.lightingBuffer.getWriteAttachment("indirect_variance"));
      this.addTextureSampler(samplers, "radiosity_indirect_reservoir_position", this::getCurrentIndirectReservoirPositionTexture);
      this.addTextureSampler(samplers, "radiosity_indirect_reservoir_normal", this::getCurrentIndirectReservoirNormalTexture);
      this.addTextureSampler(samplers, "radiosity_indirect_reservoir_radiance", this::getCurrentIndirectReservoirRadianceTexture);
      this.addTextureSampler(samplers, "radiosity_indirect_reservoir_meta", this::getCurrentIndirectReservoirMetaTexture);
      this.addTextureSampler(samplers, "radiosity_indirect_initial_position", () -> this.indirectInitialReservoirBuffer.getWriteAttachment("position"));
      this.addTextureSampler(samplers, "radiosity_indirect_initial_normal", () -> this.indirectInitialReservoirBuffer.getWriteAttachment("normal"));
      this.addTextureSampler(samplers, "radiosity_indirect_initial_radiance", () -> this.indirectInitialReservoirBuffer.getWriteAttachment("radiance"));
      this.addTextureSampler(samplers, "radiosity_indirect_initial_meta", () -> this.indirectInitialReservoirBuffer.getWriteAttachment("meta"));
      this.addTextureSampler(samplers, "radiosity_indirect_resolved", this::getResolvedIndirectTexture);
      this.addTextureSampler(samplers, "radiosity_motion", () -> this.motionVectorBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_confidence_input", () -> this.directConfidenceBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "stage_radiosity_position", () -> this.lightingStageBuffer.getWriteAttachment("position"));
      this.addTextureSampler(samplers, "stage_radiosity_normal", () -> this.lightingStageBuffer.getWriteAttachment("normal"));
      this.addTextureSampler(samplers, "stage_radiosity_mapped_normal", () -> this.lightingStageBuffer.getWriteAttachment("mapped_normal"));
      this.addTextureSampler(samplers, "stage_radiosity_albedo", () -> this.lightingStageBuffer.getWriteAttachment("albedo"));
      this.addTextureSampler(samplers, "stage_radiosity_material", () -> this.lightingStageBuffer.getWriteAttachment("material"));
      this.addTextureSampler(samplers, "stage_radiosity_identity", () -> this.lightingStageBuffer.getWriteAttachment("identity"));
      this.addTextureSampler(samplers, "stage_radiosity_direct", () -> this.lightingStageBuffer.getWriteAttachment("direct"));
      this.addTextureSampler(samplers, "stage_radiosity_direct_specular", () -> this.lightingStageBuffer.getWriteAttachment("direct_specular"));
      this.addTextureSampler(samplers, "stage_radiosity_handheld", () -> this.lightingStageBuffer.getWriteAttachment("handheld"));
      this.addTextureSampler(samplers, "stage_radiosity_indirect", () -> this.lightingStageBuffer.getWriteAttachment("indirect"));
      this.addTextureSampler(samplers, "prev_radiosity_position", () -> this.lightingBuffer.getReadAttachment("position"));
      this.addTextureSampler(samplers, "prev_radiosity_normal", () -> this.lightingBuffer.getReadAttachment("normal"));
      this.addTextureSampler(samplers, "prev_radiosity_mapped_normal", () -> this.lightingBuffer.getReadAttachment("mapped_normal"));
      this.addTextureSampler(samplers, "prev_radiosity_albedo", () -> this.lightingBuffer.getReadAttachment("albedo"));
      this.addTextureSampler(samplers, "prev_radiosity_material", () -> this.lightingBuffer.getReadAttachment("material"));
      this.addTextureSampler(samplers, "prev_radiosity_identity", () -> this.lightingBuffer.getReadAttachment("identity"));
      this.addTextureSampler(samplers, "prev_radiosity_direct", this::getPreviousResolvedDirectTexture);
      this.addTextureSampler(samplers, "prev_radiosity_reservoirs", () -> this.directReservoirBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_radiosity_reservoir_samples", () -> this.directReservoirBuffer.getReadAttachment("sample"));
      this.addTextureSampler(samplers, "prev_radiosity_reservoir_meta", () -> this.directReservoirBuffer.getReadAttachment("meta"));
      this.addTextureSampler(samplers, "scatter_reconnection0", () -> this.getCurrentStageReconnectionAttachment("reconnection0"));
      this.addTextureSampler(samplers, "scatter_reconnection1", () -> this.getCurrentStageReconnectionAttachment("reconnection1"));
      this.addTextureSampler(samplers, "scatter_reconnection2", () -> this.getCurrentStageReconnectionAttachment("reconnection2"));
      this.addTextureSampler(samplers, "scatter_reconnection3", () -> this.getCurrentStageReconnectionAttachment("reconnection3"));
      this.addTextureSampler(samplers, "scatter_reconnection4", () -> this.getCurrentStageReconnectionAttachment("reconnection4"));
      this.addTextureSampler(samplers, "prev_scatter_reconnection0", () -> this.scatterReconnectionBuffer.getReadAttachment("reconnection0"));
      this.addTextureSampler(samplers, "prev_scatter_reconnection1", () -> this.scatterReconnectionBuffer.getReadAttachment("reconnection1"));
      this.addTextureSampler(samplers, "prev_scatter_reconnection2", () -> this.scatterReconnectionBuffer.getReadAttachment("reconnection2"));
      this.addTextureSampler(samplers, "prev_scatter_reconnection3", () -> this.scatterReconnectionBuffer.getReadAttachment("reconnection3"));
      this.addTextureSampler(samplers, "prev_scatter_reconnection4", () -> this.scatterReconnectionBuffer.getReadAttachment("reconnection4"));
      // Scatter temporal resampling output: consumed by the current local spatial resampling stage
      this.addTextureSampler(samplers, "temporal_reservoir_data", () -> this.temporalReservoirBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "temporal_reservoir_sample", () -> this.temporalReservoirBuffer.getWriteAttachment("sample"));
      this.addTextureSampler(samplers, "temporal_reservoir_meta", () -> this.temporalReservoirBuffer.getWriteAttachment("meta"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reservoir_data", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_data"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reservoir_sample", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_sample"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reservoir_meta", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_meta"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reconnection0", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection0"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reconnection1", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection1"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reconnection2", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection2"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reconnection3", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection3"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reconnection4", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection4"));
      this.addTextureSampler(samplers, "prev_radiosity_direct_soft", this::getPreviousCompatDirectSoftTexture);
      this.addTextureSampler(samplers, "prev_radiosity_handheld", () -> this.lightingBuffer.getReadAttachment("handheld"));
      this.addTextureSampler(samplers, "prev_radiosity_lighting_variance", () -> this.lightingBuffer.getReadAttachment("lighting_variance"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect", () -> this.lightingBuffer.getReadAttachment("indirect"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect_variance", () -> this.lightingBuffer.getReadAttachment("indirect_variance"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect_reservoir_position", () -> this.indirectReservoirBuffer.getReadAttachment("position"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect_reservoir_normal", () -> this.indirectReservoirBuffer.getReadAttachment("normal"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect_reservoir_radiance", () -> this.indirectReservoirBuffer.getReadAttachment("radiance"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect_reservoir_meta", () -> this.indirectReservoirBuffer.getReadAttachment("meta"));
      this.addTextureSampler(samplers, "prev_radiosity_motion", () -> this.motionVectorBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_direct_confidence_input", () -> this.directConfidenceBuffer.getReadAttachment("data"));
      // NRD RELAX_DiffuseSpecular pipeline samplers (contract §6).
      // Tile classifier (R8, 1/16 resolution)
      this.addTextureSampler(samplers, "nrd_in_tiles", () -> this.nrdTilesFb.getWriteAttachment("data"));
      // Raw radiance+hitDist from sampling stage (NRD-packed by light_tree_sampling_stage.fsh)
      this.addTextureSampler(samplers, "nrd_in_diff_radiance_hitdist", () -> this.lightingStageBuffer.getWriteAttachment("direct"));
      this.addTextureSampler(samplers, "nrd_in_spec_radiance_hitdist", () -> this.lightingStageBuffer.getWriteAttachment("direct_specular"));
      // Transient ping/pong buffers
      this.addTextureSampler(samplers, "nrd_diff_illum_ping", () -> this.nrdDiffIllumPingFb.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_diff_illum_pong", () -> this.nrdDiffIllumPongFb.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_spec_illum_ping", () -> this.nrdSpecIllumPingFb.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_spec_illum_pong", () -> this.nrdSpecIllumPongFb.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_history_length", () -> this.nrdHistoryLengthFb.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_spec_reprojection_confidence", () -> this.nrdSpecReprojectionConfidenceFb.getWriteAttachment("data"));
      // Permanent prev-frame buffers: temporal reads .read (prev frame); atrous smem reads .write (post-anti-firefly)
      this.addTextureSampler(samplers, "nrd_diff_illum_prev", this::getCurrentNrdDiffIllumPrevTexture);
      this.addTextureSampler(samplers, "nrd_diff_illum_responsive_prev", this::getCurrentNrdDiffIllumResponsivePrevTexture);
      this.addTextureSampler(samplers, "nrd_spec_illum_prev", this::getCurrentNrdSpecIllumPrevTexture);
      this.addTextureSampler(samplers, "nrd_spec_illum_responsive_prev", this::getCurrentNrdSpecIllumResponsivePrevTexture);
      this.addTextureSampler(samplers, "nrd_history_length_prev", () -> this.nrdHistoryLengthPrevFb.getReadAttachment("data"));
      this.addTextureSampler(samplers, "nrd_reflection_hit_t_curr", () -> this.nrdReflectionHitTCurrFb.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_reflection_hit_t_prev", () -> this.nrdReflectionHitTPrevFb.getReadAttachment("data"));
      this.addTextureSampler(samplers, "nrd_out_diff_radiance_hitdist", () -> this.nrdOutDiffRadianceHitDistFb.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_out_spec_radiance_hitdist", () -> this.nrdOutSpecRadianceHitDistFb.getWriteAttachment("data"));
      // A-trous ping-pong inputs (Java rebinds per-pass to the correct ping or pong buffer)
      this.addTextureSampler(samplers, "nrd_diff_atrous_input", this::getCurrentDiffAtrousInputTexture);
      this.addTextureSampler(samplers, "nrd_spec_atrous_input", this::getCurrentSpecAtrousInputTexture);
      // NRD history-confidence cascade samplers.
      // ph_nrd_diff_confidence: last frame's final confidence output, sampled by TA next frame.
      // nrd_diff_confidence_gradient: gradient pass output / blur cascade input this frame.
      this.addTextureSampler(samplers, "ph_nrd_diff_confidence", () -> this.nrdConfidenceBlurPingFb.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_diff_confidence_gradient", this::getCurrentConfidenceBlurInputTexture);
      this.addTextureSampler(samplers, "denoised_direct_diffuse", this::getResolvedDirectDiffuseTexture);
      this.addTextureSampler(samplers, "denoised_direct_specular", this::getResolvedSpecularAtrousTexture);
   }

   private void registerScatterBackupTemporalTextures(SamplerHolder samplers) {
      this.addTextureSampler(samplers, "radiosity_position", this::getCurrentGeometryPositionTexture);
      this.addTextureSampler(samplers, "radiosity_normal", this::getCurrentGeometryNormalTexture);
      this.addTextureSampler(samplers, "radiosity_mapped_normal", this::getCurrentMappedNormalTexture);
      this.addTextureSampler(samplers, "radiosity_albedo", this::getCurrentAlbedoTexture);
      this.addTextureSampler(samplers, "radiosity_material", this::getCurrentMaterialTexture);
      this.addTextureSampler(samplers, "radiosity_identity", this::getCurrentIdentityTexture);
      this.addTextureSampler(samplers, "radiosity_proposal_reservoirs", () -> this.directReservoirBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "radiosity_proposal_reservoir_samples", () -> this.directReservoirBuffer.getWriteAttachment("sample"));
      this.addTextureSampler(samplers, "radiosity_proposal_reservoir_meta", () -> this.directReservoirBuffer.getWriteAttachment("meta"));
      this.addTextureSampler(samplers, "scatter_reconnection0", () -> this.getCurrentStageReconnectionAttachment("reconnection0"));
      this.addTextureSampler(samplers, "scatter_reconnection1", () -> this.getCurrentStageReconnectionAttachment("reconnection1"));
      this.addTextureSampler(samplers, "scatter_reconnection2", () -> this.getCurrentStageReconnectionAttachment("reconnection2"));
      this.addTextureSampler(samplers, "scatter_reconnection3", () -> this.getCurrentStageReconnectionAttachment("reconnection3"));
      this.addTextureSampler(samplers, "scatter_reconnection4", () -> this.getCurrentStageReconnectionAttachment("reconnection4"));
      this.addTextureSampler(samplers, "prev_radiosity_position", () -> this.lightingBuffer.getReadAttachment("position"));
      this.addTextureSampler(samplers, "prev_radiosity_normal", () -> this.lightingBuffer.getReadAttachment("normal"));
      this.addTextureSampler(samplers, "prev_radiosity_mapped_normal", () -> this.lightingBuffer.getReadAttachment("mapped_normal"));
      this.addTextureSampler(samplers, "prev_radiosity_albedo", () -> this.lightingBuffer.getReadAttachment("albedo"));
      this.addTextureSampler(samplers, "prev_radiosity_material", () -> this.lightingBuffer.getReadAttachment("material"));
      this.addTextureSampler(samplers, "prev_radiosity_identity", () -> this.lightingBuffer.getReadAttachment("identity"));
      this.addTextureSampler(samplers, "prev_radiosity_reservoirs", () -> this.directReservoirBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_radiosity_reservoir_samples", () -> this.directReservoirBuffer.getReadAttachment("sample"));
      this.addTextureSampler(samplers, "prev_radiosity_reservoir_meta", () -> this.directReservoirBuffer.getReadAttachment("meta"));
      this.addTextureSampler(samplers, "prev_scatter_reconnection0", () -> this.scatterReconnectionBuffer.getReadAttachment("reconnection0"));
      this.addTextureSampler(samplers, "prev_scatter_reconnection1", () -> this.scatterReconnectionBuffer.getReadAttachment("reconnection1"));
      this.addTextureSampler(samplers, "prev_scatter_reconnection2", () -> this.scatterReconnectionBuffer.getReadAttachment("reconnection2"));
      this.addTextureSampler(samplers, "prev_scatter_reconnection3", () -> this.scatterReconnectionBuffer.getReadAttachment("reconnection3"));
      this.addTextureSampler(samplers, "prev_scatter_reconnection4", () -> this.scatterReconnectionBuffer.getReadAttachment("reconnection4"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reservoir_data", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_data"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reservoir_sample", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_sample"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reservoir_meta", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_meta"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reconnection0", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection0"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reconnection1", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection1"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reconnection2", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection2"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reconnection3", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection3"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reconnection4", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection4"));
   }

   @Override
   public void registerCustomUniforms(DynamicUniformHolder uniforms) {
      uniforms.uniform1i("direct_atrous_step_size", this::getCurrentDirectAtrousStepSize, listener -> {});
      uniforms.uniform1i("direct_atrous_is_last_pass", this::getCurrentDirectAtrousIsLastPass, listener -> {});
      // Confidence blur step size: updated per-pass by renderConfidenceCascade().
      uniforms.uniform1i("confidence_blur_step", this::getCurrentConfidenceBlurStep, listener -> {});
      uniforms.uniform1i(UniformUpdateFrequency.PER_FRAME, "ph_restir_active_checkerboard_field", this::getActiveCheckerboardField);
      uniforms.uniform1i(UniformUpdateFrequency.PER_FRAME, "ph_restir_frame_index", this::getRestirFrameIndex);
      uniforms.uniform1i(UniformUpdateFrequency.PER_FRAME, "ph_reservoir_splatting_time_partition_count", this::getReservoirSplattingTimePartitionCount);
      uniforms.uniform1f("ph_direct_sample_budget_scale", this::getDirectSampleBudgetScale, listener -> {});
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_depth_threshold", () -> this.properties.getRestirDepthThreshold());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_normal_threshold", () -> this.properties.getRestirNormalThreshold());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_visibility_max_age", () -> (float) this.properties.getRestirVisibilityMaxAge());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_visibility_max_distance", () -> this.properties.getRestirVisibilityMaxDistance());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_initial_num_local_samples", () -> {
         String propertyOverride = System.getProperty("photonics.restirInitialLocalSamples");
         if (propertyOverride != null && !propertyOverride.isBlank()) {
            try {
               return Float.parseFloat(propertyOverride.trim());
            } catch (NumberFormatException ignored) {
            }
         }

         // Reservoir Splatting SPP is the compile-time PH_LIGHTTREE_INITIAL_SAMPLES path count.
         // Keep runtime local-light candidates at the shader's one-NEE-sample-per-path default
         // unless ReGIR is active and the ReGIR tuning panel requests nested candidates.
         if (this.shouldUseRegirLocalLightSampling()) {
            return Math.max(1.0f, PhotonicsStorage.REGIR_LOCAL_LIGHT_SAMPLES.value);
         }
         return 0.0f;
      });
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_restir_initial_num_environment_samples",
         () -> -1.0f
      );
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_initial_num_brdf_samples", () -> {
         String override = System.getProperty("photonics.restirInitialBrdfSamples");
         if (override != null && !override.isBlank()) {
            try {
               return Float.parseFloat(override.trim());
            } catch (NumberFormatException ignored) {
            }
         }

         return 0.0f;
      });
      // Hidden debug override for isolating proposal-time conservative-visibility artifacts
      // without changing the shipped runtime default.
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_initial_enable_visibility", () -> {
         String override = System.getProperty("photonics.restirInitialEnableVisibility");
         if (override != null && !override.isBlank()) {
            try {
               return Float.parseFloat(override.trim());
            } catch (NumberFormatException ignored) {
            }
         }

         return 1.0f;
      });
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_initial_brdf_cutoff", () -> 0.0001f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_local_light_sampling_mode", () -> {
         String configuredMode = PhotonicsStorage.normalizeRestirLocalLightSamplingMode(PhotonicsStorage.RESTIR_LOCAL_LIGHT_SAMPLING_MODE.value);
         return switch (configuredMode) {
            case "uniform" -> 0.0f;
            case "power_ris" -> 1.0f;
            case "fast_random" -> 3.0f;
            case "regir_ris" -> 2.0f;
            default -> 2.0f;
         };
      });
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_restir_scatter_backup_mis_mode",
         () -> "pairwise".equals(
            PhotonicsStorage.normalizeRestirScatterBackupMisOption(
               PhotonicsStorage.RESTIR_SCATTER_BACKUP_MIS_OPTION.value
            )
         ) ? 1.0f : 0.0f
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_restir_debug_force_target_pdf_one",
         () -> this.getOptionalFloatSystemProperty("photonics.restirDebugForceTargetPdfOne", 0.0f)
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_restir_debug_force_shading_inv_pdf_one",
         () -> this.getOptionalFloatSystemProperty("photonics.restirDebugForceShadingInvPdfOne", 0.0f)
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_restir_debug_force_solid_angle_pdf_one",
         () -> this.getOptionalFloatSystemProperty("photonics.restirDebugForceSolidAnglePdfOne", 0.0f)
      );
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_bias_mode", () -> {
         float override = PhotonicsStorage.RESTIR_SPATIAL_BIAS_MODE.value;
         if (override >= 0) {
            return override;
         }

         String configuredMode = PhotonicsStorage.normalizeRestirSpatialMisMode(PhotonicsStorage.RESTIR_SPATIAL_MIS_MODE.value);
         return switch (configuredMode) {
            case "basic" -> 1.0f;
            default -> 2.0f;
         };
      });
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_discount_naive", () -> this.properties.getRestirSpatialDiscountNaive());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_material_test", () -> this.properties.getRestirSpatialMaterialTest());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_boost_samples", () -> this.properties.getRestirSpatialBoostSamples());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_target_history", () -> this.properties.getRestirSpatialTargetHistory());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_sample_count", () -> {
         float override = PhotonicsStorage.RESTIR_SPATIAL_SAMPLES.value;
         return override >= 0 ? override : (float) this.properties.getRestirSpatialSampleCount();
      });
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_radius", () -> {
         float override = PhotonicsStorage.RESTIR_SPATIAL_RADIUS.value;
         return override >= 0 ? override : this.properties.getRestirSpatialRadius();
      });
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_depth_threshold", () -> this.properties.getRestirSpatialDepthThreshold());
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_spatial_normal_threshold", () -> this.properties.getRestirSpatialNormalThreshold());
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_restir_temporal_scatter_isolation_mode",
         () -> {
            String isolationMode = PhotonicsStorage.normalizeRestirTemporalReuse(
               PhotonicsStorage.RESTIR_TEMPORAL_REUSE.value
            );
            return switch (isolationMode) {
               case "scatter_only" -> 1.0f;
               case "scatter_backup" -> 2.0f;
               case "multi_scatter" -> 3.0f;
               default -> 0.0f;
            };
         }
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_restir_temporal_gather_mode",
         () -> {
            String gatherMode = PhotonicsStorage.normalizeRestirTemporalGatherMode(
               PhotonicsStorage.RESTIR_TEMPORAL_GATHER_MODE.value
            );
            return switch (gatherMode) {
               case "clamped" -> 1.0f;
               case "robust" -> 2.0f;
               default -> 0.0f;
            };
         }
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_restir_temporal_use_confidence_weights",
         () -> this.getOptionalFloatSystemProperty("photonics.restirTemporalUseConfidenceWeights", 1.0f)
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_reservoir_splatting_camera_aperture_radius",
         () -> this.getOptionalFloatSystemProperty("photonics.reservoirSplattingCameraApertureRadius", 0.0f)
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_reservoir_splatting_artificial_frame_time",
         () -> this.getOptionalFloatSystemProperty("photonics.reservoirSplattingArtificialFrameTime", 1.0f / 60.0f)
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_reservoir_splatting_shutter_speed",
         () -> this.getOptionalFloatSystemProperty("photonics.reservoirSplattingShutterSpeed", 1.0f / 24.0f)
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_debug_enable_direct_temporal_reuse",
         () -> this.isDirectTemporalReuseEnabled() ? 1.0f : 0.0f
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_debug_enable_direct_spatial_reuse",
         () -> PhotonicsStorage.DEBUG_ENABLE_DIRECT_SPATIAL_REUSE.value ? 1.0f : 0.0f
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_debug_enable_direct_final_visibility",
         () -> PhotonicsStorage.DEBUG_ENABLE_DIRECT_FINAL_VISIBILITY.value ? 1.0f : 0.0f
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_debug_enable_direct_visibility_transmittance",
         () -> PhotonicsStorage.DEBUG_ENABLE_DIRECT_VISIBILITY_TRANSMITTANCE.value ? 1.0f : 0.0f
      );
      // Match the RTXDI default shading configuration: evaluate and store final
      // visibility on the final shading pass, then reuse that visibility while
      // reservoir age/spatial distance limits remain valid.
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_enable_final_visibility", () -> 1.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_indirect_boiling_filter_strength", () -> PhotonicsStorage.RESTIR_GI_BOILING_FILTER_STRENGTH.value);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_gi_use_boiling_filter", () -> this.shouldRunIndirectBoilingFilter() ? 1.0f : 0.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_gi_temporal_splatting_active", () -> this.indirectTemporalSplattingActiveThisFrame ? 1.0f : 0.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_gi_initial_sample_count", () -> Math.max(1.0f, PhotonicsStorage.RESTIR_GI_INITIAL_SAMPLES.value));
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_gi_temporal_max_splats", () -> Math.max(1.0f, PhotonicsStorage.RESTIR_GI_TEMPORAL_MAX_SPLATS.value));
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_gi_max_ray_distance", () -> Math.max(1.0f, PhotonicsStorage.RESTIR_GI_MAX_RAY_DISTANCE.value));
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_gi_spatial_sample_count", () -> {
         float configuredSamples = PhotonicsStorage.RESTIR_GI_SPATIAL_SAMPLES.value;
         return configuredSamples >= 0.0f ? configuredSamples : 0.0f;
      });
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_gi_spatial_bias_mode", () -> PhotonicsStorage.RESTIR_GI_SPATIAL_BIAS_MODE.value);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_reuse_final_visibility", () -> 1.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_enable_denoiser_packing", () -> 1.0f);
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_debug_view_mode",
         () -> PhotonicsStorage.DEBUG_VIEW_MODE.value
      );
      // NRD RELAX_DiffuseSpecular uniforms (contract §6). All registered here so
      // LightTreeRenderer is the single source of truth for default values.
      // Tuned for Minecraft voxel scenes: short accumulation windows so block
      // placements / redstone-lamp toggles surface in <0.3s, plus aggressive
      // anti-lag (clamping sigma + reset amount) so radiance-only changes
      // (newly-cast shadow with unchanged geometry) decay fast.
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_max_accumulated_frame_num", () -> 32.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_max_fast_accumulated_frame_num", () -> 8.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_depth_threshold", () -> 0.003f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_denoising_range", () -> 500.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_disocclusion_threshold", () -> 0.005f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_disocclusion_threshold_alt", () -> 0.05f);
      // Tighter phi-luminance / lobe / roughness fractions: voxel block faces are
      // planar and quantized, so atrous edge-stopping can be sharper without
      // smearing detail across material boundaries.
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_phi_luminance_diff", () -> 0.4f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_phi_luminance_spec", () -> 0.6f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_lobe_angle_fraction", () -> 0.4f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_roughness_fraction", () -> 0.1f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_spec_lobe_angle_slack", () -> 0.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_history_fix_frame_num", () -> 2.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_history_fix_base_stride", () -> 8.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_history_fix_normal_power", () -> 8.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_history_clamping_color_box_sigma_scale", () -> 2.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_history_acceleration_amount", () -> 0.6f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_history_reset_temporal_sigma_scale", () -> 0.25f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_history_reset_spatial_sigma_scale", () -> 2.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_history_reset_amount", () -> 0.8f);
      // Smaller prepass radii: voxel surfaces have no fine geometric detail to
      // preserve and are pre-blurred by their bilinear filter texture sampling.
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_diff_prepass_blur_radius", () -> 0.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_spec_prepass_blur_radius", () -> 0.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_anti_firefly", () -> 1.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_hitdist_reconstruction", () -> 0.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_reset_history", () -> this.shouldResetNrdHistory() ? 1.0f : 0.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_roughness_edge_stopping_relaxation", () -> 0.3f);
      // Dirty-block mask: cap historyLength near recently-changed blocks so new
      // lighting (toggled lamp, placed block) converges without a global NRD flush.
      uniforms.uniform4fArray(UniformUpdateFrequency.PER_FRAME, "ph_nrd_dirty_blocks", () -> this.dirtyBlockBuffer);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_dirty_block_radius", () -> 24.0f);
      // Cap of 1 = instant reset at the dirty block center. historyLength<3
      // trips nrd_history_fix into wide spatial filtering, masking the raw
      // noisy frame while the temporal signal re-converges over ~3 frames.
      // Linear falloff out to ph_nrd_dirty_block_radius prevents a hard ring.
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_dirty_block_history_cap", () -> 1.0f);
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_nrd_debug_bypass_temporal_accumulation",
         () -> PhotonicsStorage.DEBUG_ENABLE_DIRECT_TEMPORAL_ACCUMULATION.value ? 0.0f : 1.0f
      );
      // History-confidence availability flag.  0.0 = first frame (texture uninitialised);
      // 1.0 = valid confidence texture produced by the cascade last frame.
      // Reset to 0.0 on world reload (shouldResetNrdHistory() fires same frame as reset).
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_nrd_has_history_confidence",
         () -> this.hasHistoryConfidence ? 1.0f : 0.0f
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_scatter_temporal_enabled",
         () -> this.getOptionalFloatSystemProperty("photonics.scatterTemporalEnabled", 1.0f)
      );
      // Area-ReSTIR shift mode and history length uniforms.
      // Shift modes: 0 = DELAYED_RECONNECTION, 1 = ONLY_RECONNECTION, 2 = HYBRID
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_area_restir_temporal_shift_mode",
         () -> this.getOptionalFloatSystemProperty("photonics.areaRestirTemporalShiftMode", 1.0f)
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_area_restir_spatial_shift_mode",
         () -> this.getOptionalFloatSystemProperty("photonics.areaRestirSpatialShiftMode", 1.0f)
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_area_restir_max_history_length",
         () -> this.getOptionalFloatSystemProperty("photonics.areaRestirMaxHistoryLength", 20.0f)
      );
   }

   private float getOptionalFloatSystemProperty(String key, float fallback) {
      String override = System.getProperty(key);
      if (override != null && !override.isBlank()) {
         try {
            return Float.parseFloat(override.trim());
         } catch (NumberFormatException ignored) {
         }
      }
      return fallback;
   }

   private int getActiveCheckerboardField() {
      String checkerboardMode = PhotonicsStorage.normalizeCheckerboardMode(PhotonicsStorage.RESTIR_CHECKERBOARD_MODE.value);
      if ("off".equals(checkerboardMode)) {
         return 0;
      }

      // Match RTXDI ReSTIRDIContext::UpdateCheckerboardField exactly:
      //   Black: odd frameIndex -> 1, even frameIndex -> 2
      //   White: odd frameIndex -> 2, even frameIndex -> 1
      // Checkerboard reservoir lookups interpret previousFrame=true using that same
      // parity shift, so inverting the field assignment makes reuse walk to the
      // wrong checkerboard owner every other frame and shows up as shimmer/swimming.
      boolean oddFrame = (this.renderFrameIndex & 1) != 0;
      return switch (checkerboardMode) {
         case "black" -> oddFrame ? 1 : 2;
         case "white" -> oddFrame ? 2 : 1;
         default -> 0;
      };
   }

   private int getRestirFrameIndex() {
      return this.renderFrameIndex;
   }

   private void swapScatterTemporalHistory() {
      // Match the reference ownership model more closely by publishing the just-finished
      // frame's final reconnection payload at end-of-frame rather than pre-emptively at
      // frame start. The temporal DI output buffer remains single-frame local.
      this.scatterReconnectionBuffer.swap();
   }

   private void updateScatterTemporalResourcesPerFrame() {
      this.ensureTemporalScatterMemoryCapacity();
      this.proposalReconnectionBuffer.updatePerFrame();
      this.temporalReconnectionBuffer.updatePerFrame();
      this.scatterReconnectionBuffer.updatePerFrame();
      this.temporalReservoirBuffer.updatePerFrame();
      this.temporalGatherBuffer.updatePerFrame();
   }

   private void allocateTemporalScatterMemoryManagers() {
      this.temporalGatherFloatingCoordsMemoryManager = this.createTemporalScatterMemoryManager(
         "floatingCoords",
         this.temporalScatterPixelCapacity * 2 * Float.BYTES
      );
      this.temporalGatherShiftedPathsMemoryManager = this.createTemporalScatterMemoryManager(
         "shiftedPaths",
         this.temporalScatterPixelCapacity
            * TEMPORAL_GATHER_SHIFTED_PATH_COUNT
            * TEMPORAL_GATHER_SHIFTED_PATH_STRIDE_BYTES
      );
      int currentCounterBytes = 2 * Integer.BYTES;
      int currentCellBytes = this.temporalScatterPixelCapacity * Integer.BYTES;
      int currentContributorBytes = this.temporalScatterPixelCapacity * 2 * Integer.BYTES;
      int giCurrentRecordBytes = this.temporalScatterPixelCapacity * 4 * Integer.BYTES;
      int multiCounterBytes = this.getReservoirSplattingTimePartitionCount() * 2 * Integer.BYTES;
      int multiCellBytes = this.temporalScatterContributorCapacity * Integer.BYTES;
      int multiContributorBytes = this.temporalScatterContributorCapacity * 2 * Integer.BYTES;

      this.temporalScatterCurrentGlobalCountersMemoryManager = this.createTemporalScatterMemoryManager(
         "ph_reproject_temporal_samples_global_counters",
         currentCounterBytes
      );
      this.temporalScatterCurrentCellCountersMemoryManager = this.createTemporalScatterMemoryManager(
         "ph_reproject_temporal_samples_cell_counters",
         currentCellBytes
      );
      this.giTemporalScatterCurrentRecordsMemoryManager = this.createTemporalScatterMemoryManager(
         "ph_gi_reproject_temporal_samples_records",
         giCurrentRecordBytes
      );
      this.temporalScatterCurrentReservoirIndicesMemoryManager = this.createTemporalScatterMemoryManager(
         "ph_reproject_temporal_samples_reservoir_indices",
         currentContributorBytes
      );
      this.temporalScatterCurrentScatteredReservoirsMemoryManager = this.createTemporalScatterMemoryManager(
         "ph_reproject_temporal_samples_scattered_reservoirs",
         currentContributorBytes
      );
      this.temporalScatterCurrentCellOffsetsMemoryManager = this.createTemporalScatterMemoryManager(
         "ph_scatter_temporal_resampling_cell_offsets",
         currentCellBytes
      );
      this.temporalScatterCurrentSortedReservoirsMemoryManager = this.createTemporalScatterMemoryManager(
         "ph_scatter_temporal_resampling_sorted_reservoirs",
         currentContributorBytes
      );
      this.temporalScatterMultiGlobalCountersMemoryManager = this.createTemporalScatterMemoryManager(
         "ph_multi_reproject_temporal_samples_global_counters",
         multiCounterBytes
      );
      this.temporalScatterMultiCellCountersMemoryManager = this.createTemporalScatterMemoryManager(
         "ph_multi_reproject_temporal_samples_cell_counters",
         multiCellBytes
      );
      this.temporalScatterMultiReservoirIndicesMemoryManager = this.createTemporalScatterMemoryManager(
         "ph_multi_reproject_temporal_samples_reservoir_indices",
         multiContributorBytes
      );
      this.temporalScatterMultiScatteredReservoirsMemoryManager = this.createTemporalScatterMemoryManager(
         "ph_multi_reproject_temporal_samples_scattered_reservoirs",
         multiContributorBytes
      );
      this.temporalScatterMultiCellOffsetsMemoryManager = this.createTemporalScatterMemoryManager(
         "ph_multi_scatter_temporal_resampling_cell_offsets",
         multiCellBytes
      );
      this.temporalScatterMultiSortedReservoirsMemoryManager = this.createTemporalScatterMemoryManager(
         "ph_multi_scatter_temporal_resampling_sorted_reservoirs",
         multiContributorBytes
      );
   }

   private void ensureTemporalScatterMemoryCapacity() {
      int requiredPixelCapacity = this.getTemporalScatterPixelCapacity();
      int requiredContributorCapacity = this.getTemporalScatterContributorCapacity();
      if (requiredPixelCapacity == this.temporalScatterPixelCapacity && requiredContributorCapacity == this.temporalScatterContributorCapacity) {
         return;
      }

      this.temporalScatterPixelCapacity = requiredPixelCapacity;
      this.temporalScatterContributorCapacity = requiredContributorCapacity;
      this.destroyTemporalScatterMemoryManagers();
      this.allocateTemporalScatterMemoryManagers();
      this.invalidateDirectReuseHistory();
   }

   private int getTemporalScatterPixelCapacity() {
      Vector2f resolution = this.getDirectReservoirResolution();
      return Math.max(1, (int)resolution.x) * Math.max(1, (int)resolution.y);
   }

   private int getTemporalScatterContributorCapacity() {
      return this.getTemporalScatterPixelCapacity() * this.getReservoirSplattingTimePartitionCount();
   }

   private int getReservoirSplattingTimePartitionCount() {
      return Math.max(1, Math.round(PhotonicsStorage.RESTIR_TIME_PARTITIONS.value));
   }

   private GlMemoryManager createTemporalScatterMemoryManager(String name, int byteSize) {
      return new GlMemoryManager(at.redi2go.photonic.client.rendering.opengl.objects.GlTarget.SSBO, name, Math.max(byteSize, Integer.BYTES), false);
   }

   private void clearTemporalGatherBuffers() {
      this.clearFloat2Buffer(this.temporalGatherFloatingCoordsMemoryManager);
      GL42.glMemoryBarrier(GL43.GL_SHADER_STORAGE_BARRIER_BIT);
   }

   private void clearCurrentTemporalScatterBuffers() {
      this.clearUintBuffer(this.temporalScatterCurrentGlobalCountersMemoryManager, 0);
      this.clearUintBuffer(this.temporalScatterCurrentCellCountersMemoryManager, 0);
      GL42.glMemoryBarrier(GL43.GL_SHADER_STORAGE_BARRIER_BIT);
   }

   private void clearMultiTemporalScatterBuffers() {
      this.clearUintBuffer(this.temporalScatterMultiGlobalCountersMemoryManager, 0);
      this.clearUintBuffer(this.temporalScatterMultiCellCountersMemoryManager, 0);
      GL42.glMemoryBarrier(GL43.GL_SHADER_STORAGE_BARRIER_BIT);
   }

   private void clearUintBuffer(GlMemoryManager memoryManager, int value) {
      if (memoryManager == null) {
         return;
      }
      java.nio.IntBuffer clearValue = BufferUtils.createIntBuffer(1);
      clearValue.put(value);
      clearValue.flip();
      GL15.glBindBuffer(GL43.GL_SHADER_STORAGE_BUFFER, memoryManager.getId());
      GL43.glClearBufferData(GL43.GL_SHADER_STORAGE_BUFFER, GL30.GL_R32UI, GL30.GL_RED_INTEGER, GL30.GL_UNSIGNED_INT, clearValue);
      GL15.glBindBuffer(GL43.GL_SHADER_STORAGE_BUFFER, 0);
   }

   private void clearFloat4Buffer(GlMemoryManager memoryManager) {
      if (memoryManager == null) {
         return;
      }

      java.nio.FloatBuffer clearValue = BufferUtils.createFloatBuffer(4);
      clearValue.put(0.0f).put(0.0f).put(0.0f).put(0.0f);
      clearValue.flip();
      GL15.glBindBuffer(GL43.GL_SHADER_STORAGE_BUFFER, memoryManager.getId());
      GL43.glClearBufferData(GL43.GL_SHADER_STORAGE_BUFFER, GL30.GL_RGBA32F, GL11.GL_RGBA, GL11.GL_FLOAT, clearValue);
      GL15.glBindBuffer(GL43.GL_SHADER_STORAGE_BUFFER, 0);
   }

   private void clearFloat2Buffer(GlMemoryManager memoryManager) {
      if (memoryManager == null) {
         return;
      }

      java.nio.FloatBuffer clearValue = BufferUtils.createFloatBuffer(2);
      clearValue.put(-1.0f).put(-1.0f);
      clearValue.flip();
      GL15.glBindBuffer(GL43.GL_SHADER_STORAGE_BUFFER, memoryManager.getId());
      GL43.glClearBufferData(GL43.GL_SHADER_STORAGE_BUFFER, GL30.GL_RG32F, GL30.GL_RG, GL11.GL_FLOAT, clearValue);
      GL15.glBindBuffer(GL43.GL_SHADER_STORAGE_BUFFER, 0);
   }

   private void destroyTemporalScatterMemoryManagers() {
      this.temporalGatherFloatingCoordsMemoryManager = this.freeTemporalScatterMemoryManager(this.temporalGatherFloatingCoordsMemoryManager);
      this.temporalGatherShiftedPathsMemoryManager = this.freeTemporalScatterMemoryManager(this.temporalGatherShiftedPathsMemoryManager);
      this.temporalScatterCurrentGlobalCountersMemoryManager = this.freeTemporalScatterMemoryManager(this.temporalScatterCurrentGlobalCountersMemoryManager);
      this.temporalScatterCurrentCellCountersMemoryManager = this.freeTemporalScatterMemoryManager(this.temporalScatterCurrentCellCountersMemoryManager);
      this.giTemporalScatterCurrentRecordsMemoryManager = this.freeTemporalScatterMemoryManager(this.giTemporalScatterCurrentRecordsMemoryManager);
      this.temporalScatterCurrentReservoirIndicesMemoryManager = this.freeTemporalScatterMemoryManager(this.temporalScatterCurrentReservoirIndicesMemoryManager);
      this.temporalScatterCurrentScatteredReservoirsMemoryManager = this.freeTemporalScatterMemoryManager(this.temporalScatterCurrentScatteredReservoirsMemoryManager);
      this.temporalScatterCurrentCellOffsetsMemoryManager = this.freeTemporalScatterMemoryManager(this.temporalScatterCurrentCellOffsetsMemoryManager);
      this.temporalScatterCurrentSortedReservoirsMemoryManager = this.freeTemporalScatterMemoryManager(this.temporalScatterCurrentSortedReservoirsMemoryManager);
      this.temporalScatterMultiGlobalCountersMemoryManager = this.freeTemporalScatterMemoryManager(this.temporalScatterMultiGlobalCountersMemoryManager);
      this.temporalScatterMultiCellCountersMemoryManager = this.freeTemporalScatterMemoryManager(this.temporalScatterMultiCellCountersMemoryManager);
      this.temporalScatterMultiReservoirIndicesMemoryManager = this.freeTemporalScatterMemoryManager(this.temporalScatterMultiReservoirIndicesMemoryManager);
      this.temporalScatterMultiScatteredReservoirsMemoryManager = this.freeTemporalScatterMemoryManager(this.temporalScatterMultiScatteredReservoirsMemoryManager);
      this.temporalScatterMultiCellOffsetsMemoryManager = this.freeTemporalScatterMemoryManager(this.temporalScatterMultiCellOffsetsMemoryManager);
      this.temporalScatterMultiSortedReservoirsMemoryManager = this.freeTemporalScatterMemoryManager(this.temporalScatterMultiSortedReservoirsMemoryManager);
   }

   @Nullable
   private GlMemoryManager freeTemporalScatterMemoryManager(@Nullable GlMemoryManager memoryManager) {
      if (memoryManager != null) {
         memoryManager.free();
      }
      return null;
   }

   private void destroyScatterTemporalResources() {
      this.temporalCollectFramebuffer.destroy();
      this.robustReuseOptimizationFramebuffer.destroy();
      this.temporalScatterStageFramebuffer.destroy();
      this.temporalReservoirFramebuffer.destroy();
      this.proposalReconnectionBuffer.destroy();
      this.temporalReconnectionBuffer.destroy();
      this.scatterReconnectionBuffer.destroy();
      this.temporalReservoirBuffer.destroy();
      this.temporalGatherBuffer.destroy();
      this.destroyTemporalScatterMemoryManagers();
   }

   private void clearCurrentTemporalStageBuffers(Vector4f clearColor) {
      // Reference topology keeps only prev/curr history persistent across frames.
      // Proposal/current-write and intermediate gather targets are frame-local and
      // should not be treated as double-buffered history on resets.
      this.proposalReconnectionBuffer.clear(clearColor);
      this.temporalReconnectionBuffer.clear(clearColor);
      this.temporalReservoirBuffer.clear(clearColor);
      this.temporalGatherBuffer.clear(clearColor);
   }

   private void clearPreviousTemporalHistory(Vector4f clearColor) {
      // Final temporal/spatial reconnection history is the only DI reconnection
      // payload that survives across frames in the current topology.
      this.scatterReconnectionBuffer.clearBothSides(clearColor);
   }

   @Override
   public void render() {
      if (this.proposalStageRenderer == null) {
         return;
      }

      this.renderFrameIndex++;
      this.drainDirtyBlocksIntoRingBuffer();
      this.resolveGpuProfile();
      this.advanceGpuProfileFrame();
      this.ensureCompatDirectSoftCleared();
      boolean resetReservoirSplatting = this.shouldResetReservoirSplattingTemporal(this.ensureReservoirHistoryCleared());
      this.directTemporalReuseActiveThisFrame = this.shouldRunReservoirSplattingTemporalResampling(resetReservoirSplatting);
      this.indirectTemporalSplattingActiveThisFrame = this.shouldRunIndirectTemporalSplatting(resetReservoirSplatting);
      this.lightingBuffer.swap();
      this.compatDirectSoftBuffer.swap();
      this.motionVectorBuffer.swap();
      this.directReservoirBuffer.swap();
      this.directConfidenceBuffer.swap();
      // Swap permanent NRD history buffers so current-frame writes become next-frame reads.
      this.nrdDiffIllumPrevFb.swap();
      this.nrdDiffIllumResponsivePrevFb.swap();
      this.nrdSpecIllumPrevFb.swap();
      this.nrdSpecIllumResponsivePrevFb.swap();
      this.nrdHistoryLengthPrevFb.swap();
      this.nrdReflectionHitTPrevFb.swap();
      this.indirectInitialReservoirBuffer.swap();
      this.indirectReservoirBuffer.swap();
      this.indirectDenoisedBuffer.swap();
      long t0 = System.nanoTime();
      this.renderLightTreeSamplingStageProfiled();
      long t1 = System.nanoTime();
      this.renderDIInitialCandidatesProfiled();
      long t2 = System.nanoTime();
      if (this.isDirectTemporalReuseEnabled()) {
         this.renderDIScatterTemporalProfiled();
      }
      long t3 = System.nanoTime();
      this.renderDISpatialResamplingProfiled();
      long t4 = System.nanoTime();
      // Reference parity:
      // 1) publish the final reconnection payload only when temporal/proposal is
      //    the last reuse stage
      // 2) resolve lighting and promote the authoritative final reservoir via the
      //    monolithic ShadeSamples/ResolveReSTIR pass
      this.renderShadeSamplesProfiled();
      long t5 = System.nanoTime();
      // NRD RELAX_DiffuseSpecular fused pipeline (contract §9, pipeline order §1).
      long t6 = System.nanoTime();
      this.renderProfiled(nrdClassifyTilesRegionIndex, this.nrdClassifyTilesRenderer);
      long t7 = System.nanoTime();
      if (this.shouldRunHitDistReconstruction()) {
         this.renderProfiled(nrdHitDistReconstructionRegionIndex, this.nrdHitDistReconstructionRenderer);
      }
      long t8 = System.nanoTime();
      this.renderProfiled(nrdPrepassRegionIndex, this.nrdPrepassRenderer);
      long t9 = System.nanoTime();
      this.renderProfiled(relaxTemporalAccumulationRegionIndex, this.directTemporalRenderer);
      long t10 = System.nanoTime();
      // Confidence cascade runs AFTER TA so the new noisy input is available.
      // The produced confidence texture is consumed by TA in the NEXT frame.
      // Reference placement: NRD-Sample dispatches ConfidenceBlur after TemporalAccumulation.
      this.renderConfidenceCascade();
      this.renderProfiled(relaxHistoryFixRegionIndex, this.directHistoryFixRenderer);
      long t11 = System.nanoTime();
      this.renderProfiled(relaxHistoryClampingRegionIndex, this.directHistoryClampingRenderer);
      long t12 = System.nanoTime();
      this.renderProfiled(nrdCopyRegionIndex, this.nrdCopyRenderer);
      long t13 = System.nanoTime();
      this.renderProfiled(relaxAntiFireflyRegionIndex, this.directAntiFireflyRenderer);
      long t14 = System.nanoTime();
      this.renderNrdAtrousProfiled();
      long t15 = System.nanoTime();
      long t16 = t15;
      boolean runReservoirSplattingIndirect = this.shouldRunReservoirSplattingIndirectPipeline();
      if (runReservoirSplattingIndirect) {
         this.disabledIndirectOutputsCleared = false;
         this.renderIndirectAccumulationProfiled();
      } else {
         this.clearDisabledIndirectOutputs();
      }
      long t17 = System.nanoTime();
      this.renderProfiled(lightingAccumulationRegionIndex, this.accumulationRenderer);
      long t18 = System.nanoTime();
      if (runReservoirSplattingIndirect && this.shouldRunIndirectDenoise()) {
         this.renderProfiled(indirectDenoiseRegionIndex, this.indirectDenoisingRenderer);
      }
      long t19 = System.nanoTime();
      if (runReservoirSplattingIndirect) {
         this.renderProfiled(indirectCompositeRegionIndex, this.indirectRenderer);
      }
      long t20 = System.nanoTime();
      this.swapScatterTemporalHistory();
      this.recordCpuPassTimes(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t17, t18, t19, t20);
      this.worldRegistry.advanceLightBlendFrame(this.renderFrameIndex);
      this.logRenderProfileIfNeeded(t20 - t0);
   }

   @Override
   public Map<String, TextureObject> getAutomationTextures() {
      return Map.ofEntries(
         Map.entry("direct", this.getResolvedDirectTexture()),
         Map.entry("direct_reservoir", this.directReservoirBuffer.getWriteAttachment("data")),
         Map.entry("direct_reservoir_resolved", this.directReservoirBuffer.getReadAttachment("data")),
         Map.entry("direct_soft", this.getCompatDirectSoftTexture()),
         Map.entry("direct_soft_prev", this.getPreviousCompatDirectSoftTexture()),
         // NRD-pipeline mapped names (contract §8 Task 8).
         Map.entry("nrd_in_diff", this.lightingStageBuffer.getWriteAttachment("direct")),
         Map.entry("nrd_in_spec", this.lightingStageBuffer.getWriteAttachment("direct_specular")),
         Map.entry("tiles", this.nrdTilesFb.getWriteAttachment("data")),
         Map.entry("prepass_diff", this.nrdOutDiffRadianceHitDistFb.getWriteAttachment("data")),
         Map.entry("direct_slow", this.nrdDiffIllumPingFb.getWriteAttachment("data")),
         Map.entry("direct_fast", this.nrdDiffIllumPongFb.getWriteAttachment("data")),
         Map.entry("direct_clamped_slow", this.nrdDiffIllumPrevFb.getWriteAttachment("data")),
         Map.entry("direct_clamped_fast", this.nrdDiffIllumResponsivePrevFb.getWriteAttachment("data")),
         Map.entry("direct_anti_firefly", this.nrdDiffIllumPrevFb.getWriteAttachment("data")),
         Map.entry("direct_denoised", this.nrdOutDiffRadianceHitDistFb.getWriteAttachment("data")),
         Map.entry("direct_atrous", this.getResolvedDiffuseAtrousTexture()),
         Map.entry("direct_raw", this.lightingStageBuffer.getWriteAttachment("direct_combined")),
         Map.entry("direct_raw_diffuse", this.lightingStageBuffer.getWriteAttachment("direct")),
         Map.entry("direct_raw_specular", this.lightingStageBuffer.getWriteAttachment("direct_specular")),
         Map.entry("spec_denoised", this.getResolvedSpecularAtrousTexture()),
         Map.entry("spec_raw", this.lightingStageBuffer.getWriteAttachment("direct_specular")),
         Map.entry("direct_initial_debug", this.directInitialDebugBuffer.getWriteAttachment("data")),
         Map.entry("handheld", this.lightingBuffer.getWriteAttachment("handheld")),
         Map.entry("indirect", this.getResolvedIndirectTexture()),
         Map.entry("indirect_raw", this.lightingBuffer.getWriteAttachment("indirect")),
         Map.entry("indirect_reservoir", this.indirectReservoirBuffer.getWriteAttachment("radiance")),
         Map.entry("lighting", this.nrdDiffIllumPingFb.getWriteAttachment("data")),
         Map.entry("stage_albedo", this.lightingStageBuffer.getWriteAttachment("albedo")),
         Map.entry("stage_direct", this.lightingStageBuffer.getWriteAttachment("direct_combined")),
         Map.entry("stage_direct_diffuse", this.lightingStageBuffer.getWriteAttachment("direct")),
         Map.entry("stage_direct_specular", this.lightingStageBuffer.getWriteAttachment("direct_specular")),
         Map.entry("stage_mapped_normal", this.lightingStageBuffer.getWriteAttachment("mapped_normal")),
         Map.entry("stage_material", this.lightingStageBuffer.getWriteAttachment("material")),
         Map.entry("stage_normal", this.lightingStageBuffer.getWriteAttachment("normal")),
         Map.entry("stage_position", this.lightingStageBuffer.getWriteAttachment("position")),
         Map.entry("stage_indirect", this.lightingBuffer.getWriteAttachment("indirect")),
         Map.entry("motion", this.motionVectorBuffer.getWriteAttachment("data"))
      );
   }

   @Override
   public void recalculateSizes() {
      this.directReservoirBuffer.updatePerFrame();
      this.directSpatialReservoirBuffer.updatePerFrame();
      this.updateScatterTemporalResourcesPerFrame();
      this.directConfidenceBuffer.updatePerFrame();
      this.directInitialDebugBuffer.updatePerFrame();
      this.motionVectorBuffer.updatePerFrame();
      // NRD permanent FBOs
      this.nrdDiffIllumPrevFb.updatePerFrame();
      this.nrdDiffIllumResponsivePrevFb.updatePerFrame();
      this.nrdSpecIllumPrevFb.updatePerFrame();
      this.nrdSpecIllumResponsivePrevFb.updatePerFrame();
      this.nrdHistoryLengthPrevFb.updatePerFrame();
      this.nrdReflectionHitTPrevFb.updatePerFrame();
      // NRD transient FBOs (tile FBO recalculated by updatePerFrame - size computed in ColorFramebuffer via supplier)
      this.nrdTilesFb.updatePerFrame();
      this.nrdDiffIllumPingFb.updatePerFrame();
      this.nrdDiffIllumPongFb.updatePerFrame();
      this.nrdSpecIllumPingFb.updatePerFrame();
      this.nrdSpecIllumPongFb.updatePerFrame();
      this.nrdHistoryLengthFb.updatePerFrame();
      this.nrdSpecReprojectionConfidenceFb.updatePerFrame();
      this.nrdReflectionHitTCurrFb.updatePerFrame();
      this.nrdOutDiffRadianceHitDistFb.updatePerFrame();
      this.nrdOutSpecRadianceHitDistFb.updatePerFrame();
      this.nrdDiffHitDistReconFb.updatePerFrame();
      this.nrdSpecHitDistReconFb.updatePerFrame();
      this.indirectInitialReservoirBuffer.updatePerFrame();
      this.indirectReservoirBuffer.updatePerFrame();
      this.indirectDenoisedBuffer.updatePerFrame();
      this.recalculateRenderer(this.proposalStageRenderer);
      this.recalculateRenderer(this.proposalReservoirRenderer);
      this.recalculateRenderer(this.temporalCollectRenderer);
      this.recalculateRenderer(this.robustReuseOptimizationRenderer);
      this.recalculateRenderer(this.temporalGatherRenderer);
      this.recalculateRenderer(this.temporalScatterReprojectionRenderer);
      this.recalculateRenderer(this.temporalMultiScatterReprojectionRenderer);
      this.recalculateRenderer(this.temporalScatterBinningOffsetsRenderer);
      this.recalculateRenderer(this.temporalMultiScatterBinningOffsetsRenderer);
      this.recalculateRenderer(this.temporalScatterBinningRenderer);
      this.recalculateRenderer(this.temporalMultiScatterBinningRenderer);
      this.recalculateRenderer(this.scatterTemporalRenderer);
      this.recalculateRenderer(this.scatterBackupTemporalRenderer);
      this.recalculateRenderer(this.multiScatterTemporalRenderer);
      this.recalculateRenderer(this.reuseResolveRenderer);
      this.recalculateRenderer(this.nrdClassifyTilesRenderer);
      this.recalculateRenderer(this.nrdHitDistReconstructionRenderer);
      this.recalculateRenderer(this.nrdPrepassRenderer);
      this.recalculateRenderer(this.directTemporalRenderer);
      this.recalculateRenderer(this.directHistoryFixRenderer);
      this.recalculateRenderer(this.directHistoryClampingRenderer);
      this.recalculateRenderer(this.nrdCopyRenderer);
      this.recalculateRenderer(this.directAntiFireflyRenderer);
      this.recalculateRenderer(this.nrdAtrousSmemRenderer);
      this.recalculateRenderer(this.directAtrousRenderer);
      this.recalculateRenderer(this.indirectInitialRenderer);
      this.recalculateRenderer(this.indirectBoilingRenderer);
      this.recalculateRenderer(this.indirectTemporalReprojectionRenderer);
      this.recalculateRenderer(this.indirectTemporalBinningOffsetsRenderer);
      this.recalculateRenderer(this.indirectTemporalBinningRenderer);
      this.recalculateRenderer(this.indirectScatterTemporalRenderer);
      this.recalculateRenderer(this.indirectAccumulationRenderer);
      this.recalculateRenderer(this.indirectAccumulationLightingRenderer);
      this.recalculateRenderer(this.indirectAccumulationReservoirRenderer);
      this.recalculateRenderer(this.indirectDenoisingRenderer);
      this.recalculateRenderer(this.accumulationRenderer);
      this.recalculateRenderer(this.indirectRenderer);
      this.recalculateRenderer(this.shadeSamplesMonolithicRenderer);
      this.recalculateRenderer(this.shadeSamplesReservoirRenderer);
      this.recalculateRenderer(this.shadeSamplesRenderer);
      this.recalculateRenderer(this.shadeSamplesReconnectionRenderer);
   }

   @Override
   public void free() {
      PhotonicsStorage.RESTIR_LOCAL_LIGHT_SAMPLING_MODE.removeObserver(this.localLightSamplingModeObserver);
      PhotonicsStorage.RESTIR_TEMPORAL_REUSE.removeObserver(this.temporalScatterIsolationModeObserver);
      PhotonicsStorage.RESTIR_GI_TEMPORAL_REUSE.removeObserver(this.indirectTemporalReuseObserver);
      this.proposalFramebuffer.destroy();
      this.proposalReservoirFramebuffer.destroy();
      this.reuseResolveFramebuffer.destroy();
      // NRD RELAX_DiffuseSpecular fused routing framebuffers
      this.nrdClassifyTilesFramebuffer.destroy();
      this.nrdHitDistReconstructionFramebuffer.destroy();
      this.nrdPrepassFramebuffer.destroy();
      this.directTemporalFramebuffer.destroy();
      this.directHistoryFixFramebuffer.destroy();
      this.directHistoryClampingFramebuffer.destroy();
      this.nrdCopyFramebuffer.destroy();
      this.directAntiFireflyFramebuffer.destroy();
      this.nrdAtrousSmemFramebuffer.destroy();
      this.directAtrousFramebuffer.destroy();
      this.indirectInitialFramebuffer.destroy();
      this.indirectBoilingFramebuffer.destroy();
      this.indirectAccumulationFramebuffer.destroy();
      this.indirectAccumulationLightingFramebuffer.destroy();
      this.indirectAccumulationReservoirFramebuffer.destroy();
      this.indirectDenoisingFramebuffer.destroy();
      this.positionWriteFramebuffer.destroy();
      this.shadeSamplesMonolithicFramebuffer.destroy();
      this.shadeSamplesFramebuffer.destroy();
      this.shadeSamplesReservoirFramebuffer.destroy();
      this.shadeSamplesReconnectionFramebuffer.destroy();
      this.destroyScatterTemporalResources();
      this.lightingBuffer.destroy();
      this.lightingStageBuffer.destroy();
      this.compatDirectSoftBuffer.destroy();
      this.motionVectorBuffer.destroy();
      this.directReservoirBuffer.destroy();
      this.directSpatialReservoirBuffer.destroy();
      this.directConfidenceBuffer.destroy();
      // NRD permanent (swap-buffered) FBOs
      this.nrdDiffIllumPrevFb.destroy();
      this.nrdDiffIllumResponsivePrevFb.destroy();
      this.nrdSpecIllumPrevFb.destroy();
      this.nrdSpecIllumResponsivePrevFb.destroy();
      this.nrdHistoryLengthPrevFb.destroy();
      this.nrdReflectionHitTPrevFb.destroy();
      // NRD transient FBOs
      this.nrdTilesFb.destroy();
      this.nrdDiffIllumPingFb.destroy();
      this.nrdDiffIllumPongFb.destroy();
      this.nrdSpecIllumPingFb.destroy();
      this.nrdSpecIllumPongFb.destroy();
      this.nrdHistoryLengthFb.destroy();
      this.nrdSpecReprojectionConfidenceFb.destroy();
      this.nrdReflectionHitTCurrFb.destroy();
      this.nrdOutDiffRadianceHitDistFb.destroy();
      this.nrdOutSpecRadianceHitDistFb.destroy();
      this.nrdDiffHitDistReconFb.destroy();
      this.nrdSpecHitDistReconFb.destroy();
      this.indirectInitialReservoirBuffer.destroy();
      this.indirectReservoirBuffer.destroy();
      this.indirectDenoisedBuffer.destroy();
      this.destroyRenderer(this.proposalStageRenderer);
      this.destroyRenderer(this.proposalReservoirRenderer);
      this.destroyRenderer(this.temporalCollectRenderer);
      this.destroyRenderer(this.robustReuseOptimizationRenderer);
      this.destroyRenderer(this.temporalGatherRenderer);
      this.destroyRenderer(this.temporalScatterReprojectionRenderer);
      this.destroyRenderer(this.temporalMultiScatterReprojectionRenderer);
      this.destroyRenderer(this.temporalScatterBinningOffsetsRenderer);
      this.destroyRenderer(this.temporalMultiScatterBinningOffsetsRenderer);
      this.destroyRenderer(this.temporalScatterBinningRenderer);
      this.destroyRenderer(this.temporalMultiScatterBinningRenderer);
      this.destroyRenderer(this.scatterTemporalRenderer);
      this.destroyRenderer(this.scatterBackupTemporalRenderer);
      this.destroyRenderer(this.multiScatterTemporalRenderer);
      this.destroyRenderer(this.reuseResolveRenderer);
      // NRD RELAX_DiffuseSpecular fused pipeline renderers
      this.destroyRenderer(this.nrdClassifyTilesRenderer);
      this.destroyRenderer(this.nrdHitDistReconstructionRenderer);
      this.destroyRenderer(this.nrdPrepassRenderer);
      this.destroyRenderer(this.directTemporalRenderer);
      this.destroyRenderer(this.directHistoryFixRenderer);
      this.destroyRenderer(this.directHistoryClampingRenderer);
      this.destroyRenderer(this.nrdCopyRenderer);
      this.destroyRenderer(this.directAntiFireflyRenderer);
      this.destroyRenderer(this.nrdAtrousSmemRenderer);
      this.destroyRenderer(this.directAtrousRenderer);
      this.destroyRenderer(this.indirectInitialRenderer);
      this.destroyRenderer(this.indirectBoilingRenderer);
      this.destroyRenderer(this.indirectTemporalReprojectionRenderer);
      this.destroyRenderer(this.indirectTemporalBinningOffsetsRenderer);
      this.destroyRenderer(this.indirectTemporalBinningRenderer);
      this.destroyRenderer(this.indirectScatterTemporalRenderer);
      this.destroyRenderer(this.indirectAccumulationRenderer);
      this.destroyRenderer(this.indirectAccumulationLightingRenderer);
      this.destroyRenderer(this.indirectAccumulationReservoirRenderer);
      this.destroyRenderer(this.indirectDenoisingRenderer);
      this.destroyRenderer(this.accumulationRenderer);
      this.destroyRenderer(this.indirectRenderer);
      this.destroyRenderer(this.shadeSamplesMonolithicRenderer);
      this.destroyRenderer(this.shadeSamplesReservoirRenderer);
      this.destroyRenderer(this.shadeSamplesRenderer);
      this.destroyRenderer(this.shadeSamplesReconnectionRenderer);
      this.destroyGpuTimerQuery();
      if (this.regirComputeProgram != null) {
         this.regirComputeProgram.destroy();
      }
   }

   private ColorFramebuffer createDirectSignalFramebuffer(float renderScale, String format) {
      ColorFramebuffer framebuffer = new ColorFramebuffer(renderScale);
      framebuffer.createAttachment("data", format, false);
      return framebuffer;
   }

   private ColorFramebuffer createDirectPackedDebugFramebuffer(float renderScale) {
      ColorFramebuffer framebuffer = new ColorFramebuffer(this::getDirectReservoirResolution, renderScale);
      framebuffer.createAttachment("data", "RGBA16F", false);
      return framebuffer;
   }

   private ColorFramebuffer createTemporalScatterCandidateFramebuffer(float renderScale) {
      ColorFramebuffer framebuffer = new ColorFramebuffer(this::getDirectReservoirResolution, renderScale);
      framebuffer.createAttachment("data", "RGBA32F", false);
      framebuffer.createAttachment("sample", "RGBA32F", false);
      framebuffer.createAttachment("meta", "RGBA32F", false);
      return framebuffer;
   }

   private RoutingFramebuffer createTemporalScatterStageFramebuffer() {
      RoutingFramebuffer framebuffer = this.createDirectPackedRoutingFramebuffer(
         () -> this.directInitialDebugBuffer.getWriteAttachment("data"),
         () -> this.directInitialDebugBuffer.getWriteAttachment("data"),
         () -> this.directInitialDebugBuffer.getWriteAttachment("data")
      );
      framebuffer.setDrawBuffers(new int[] {-1});
      return framebuffer;
   }

   private ColorFramebuffer createReconnectionFramebuffer(float renderScale) {
      ColorFramebuffer framebuffer = new ColorFramebuffer(this::getDirectReservoirResolution, renderScale);
      // DI reconnection payload split across five RGBA32F targets:
      // reconnection0: firstHit.worldPos.xyz, firstHit.viewDepth
      // reconnection1: secondHit.worldPos.xyz, packed lightPdf/subPixelJacobian
      // reconnection2: irradiance.xyz, packed discrete metadata
      // reconnection3: earlyThroughput.xyz, packed lensVertexJacobian/secondaryPathJacobian
      // reconnection4: packed subPixel, packed lensSample, packed firstWi, packed secondWo
      // reservoir transport aux: secondHit.viewDepth, packed face ids
      framebuffer.createAttachment("reconnection0", "RGBA32F", false);
      framebuffer.createAttachment("reconnection1", "RGBA32F", false);
      framebuffer.createAttachment("reconnection2", "RGBA32F", false);
      framebuffer.createAttachment("reconnection3", "RGBA32F", false);
      framebuffer.createAttachment("reconnection4", "RGBA32F", false);
      return framebuffer;
   }

   private ColorFramebuffer createTemporalReservoirFramebuffer(float renderScale) {
      // Same format as directReservoirBuffer - holds the temporal resampling output
      // that feeds into spatial resampling. Single-buffered (produced & consumed same frame).
      ColorFramebuffer framebuffer = new ColorFramebuffer(this::getDirectReservoirResolution, renderScale);
      framebuffer.createAttachment("data", "RGBA32F", false);
      framebuffer.createAttachment("sample", "RGBA32F", false);
      framebuffer.createAttachment("meta", "RGBA32F", false);
      return framebuffer;
   }

   private ColorFramebuffer createTemporalGatherFramebuffer(float renderScale) {
      ColorFramebuffer framebuffer = new ColorFramebuffer(this::getDirectReservoirResolution, renderScale);
      framebuffer.createAttachment("intermediate_data", "RGBA32F", false);
      framebuffer.createAttachment("intermediate_sample", "RGBA32F", false);
      framebuffer.createAttachment("intermediate_meta", "RGBA32F", false);
      framebuffer.createAttachment("intermediate_reconnection0", "RGBA32F", false);
      framebuffer.createAttachment("intermediate_reconnection1", "RGBA32F", false);
      framebuffer.createAttachment("intermediate_reconnection2", "RGBA32F", false);
      framebuffer.createAttachment("intermediate_reconnection3", "RGBA32F", false);
      framebuffer.createAttachment("intermediate_reconnection4", "RGBA32F", false);
      return framebuffer;
   }

   private RoutingFramebuffer createTemporalCollectFramebuffer() {
      return this.createDirectPackedRoutingFramebuffer(
         () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_data"),
         () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_sample"),
         () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_meta"),
         () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection0"),
         () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection1"),
         () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection2"),
         () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection3"),
         () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection4")
      );
   }

   private RoutingFramebuffer createRobustReuseOptimizationFramebuffer() {
      RoutingFramebuffer framebuffer = this.createDirectPackedRoutingFramebuffer(
         () -> this.directInitialDebugBuffer.getWriteAttachment("data")
      );
      framebuffer.setDrawBuffers(new int[] {-1});
      return framebuffer;
   }

   private RoutingFramebuffer createTemporalReservoirRoutingFramebuffer() {
      return this.createDirectPackedRoutingFramebuffer(
         () -> this.temporalReservoirBuffer.getWriteAttachment("data"),
         () -> this.temporalReservoirBuffer.getWriteAttachment("sample"),
         () -> this.temporalReservoirBuffer.getWriteAttachment("meta"),
         () -> this.temporalReconnectionBuffer.getWriteAttachment("reconnection0"),
         () -> this.temporalReconnectionBuffer.getWriteAttachment("reconnection1"),
         () -> this.temporalReconnectionBuffer.getWriteAttachment("reconnection2"),
         () -> this.temporalReconnectionBuffer.getWriteAttachment("reconnection3"),
         () -> this.temporalReconnectionBuffer.getWriteAttachment("reconnection4")
      );
   }

   private ColorFramebuffer createDirectReservoirFramebuffer(float renderScale) {
      ColorFramebuffer framebuffer = new ColorFramebuffer(this::getDirectReservoirResolution, renderScale);
      framebuffer.createAttachment("data", "RGBA32F", false);
      framebuffer.createAttachment("sample", "RGBA32F", false);
      // RGBA32F required: the framebuffer-backed DI reservoir stores M/age/spatial
      // distance/visibility as exact 32-bit float channels, while the light/sample IDs
      // still use uintBitsToFloat transport in the X channels.
      framebuffer.createAttachment("meta", "RGBA32F", false);
      return framebuffer;
   }

   private ColorFramebuffer createIndirectReservoirFramebuffer(float renderScale) {
      ColorFramebuffer framebuffer = new ColorFramebuffer(this::getDirectReservoirResolution, renderScale);
      this.createIndirectReservoirAttachments(framebuffer);
      return framebuffer;
   }

   private Vector2f getDirectReservoirResolution() {
      int fbWidth = MinecraftClient.getInstance().getWindow().getFramebufferWidth();
      int fbHeight = MinecraftClient.getInstance().getWindow().getFramebufferHeight();
      if (this.getActiveCheckerboardField() != 0) {
         // RTXDI checkerboard: reservoir buffer is half-width (ceil) when active.
         // Reference: RTXDI Libraries/Rtxdi/Include/Rtxdi/Utils/ReservoirAddressing.hlsli
         fbWidth = (fbWidth + 1) >> 1;
      }
      return new Vector2f(fbWidth, fbHeight);
   }

   // ---------------------------------------------------------------------------
   // NRD RELAX_DiffuseSpecular framebuffer factory methods (contract §7/§8)
   // ---------------------------------------------------------------------------

   private ColorFramebuffer createNrdTileFramebuffer(float renderScale) {
      // Tile classifier runs at ceil(w/16) x ceil(h/16).  We encode this as a
      // custom resolution supplier so updatePerFrame() recalculates correctly.
      Supplier<Vector2f> tileSizeSupplier = () -> {
         Vector2f base = this.getDirectReservoirResolution();
         return new Vector2f(
            (float) Math.ceil(base.x / 16.0),
            (float) Math.ceil(base.y / 16.0)
         );
      };
      ColorFramebuffer framebuffer = new ColorFramebuffer(tileSizeSupplier, renderScale);
      framebuffer.createAttachment("data", "R8", false);
      return framebuffer;
   }

   private RoutingFramebuffer createNrdClassifyTilesFramebuffer() {
      return this.createRoutingFramebuffer(() -> this.nrdTilesFb.getWriteAttachment("data"));
   }

   private RoutingFramebuffer createNrdHitDistReconstructionFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.nrdDiffHitDistReconFb.getWriteAttachment("data"),
         () -> this.nrdSpecHitDistReconFb.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createNrdPrepassFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.nrdOutDiffRadianceHitDistFb.getWriteAttachment("data"),
         () -> this.nrdOutSpecRadianceHitDistFb.getWriteAttachment("data")
      );
   }

   // Temporal accumulation: 7 outputs per contract §7
   //   loc 0 -> nrdHistoryLengthFb
   //   loc 1 -> nrdDiffIllumPingFb
   //   loc 2 -> nrdSpecIllumPingFb
   //   loc 3 -> nrdDiffIllumPongFb
   //   loc 4 -> nrdSpecIllumPongFb
   //   loc 5 -> nrdReflectionHitTCurrFb
   //   loc 6 -> nrdSpecReprojectionConfidenceFb
   private RoutingFramebuffer createDirectTemporalFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.nrdHistoryLengthFb.getWriteAttachment("data"),
         () -> this.nrdDiffIllumPingFb.getWriteAttachment("data"),
         () -> this.nrdSpecIllumPingFb.getWriteAttachment("data"),
         () -> this.nrdDiffIllumPongFb.getWriteAttachment("data"),
         () -> this.nrdSpecIllumPongFb.getWriteAttachment("data"),
         () -> this.nrdReflectionHitTCurrFb.getWriteAttachment("data"),
         () -> this.nrdSpecReprojectionConfidenceFb.getWriteAttachment("data")
      );
   }

   // History fix: 2 outputs -> pong buffers (loc 0 = diff pong, loc 1 = spec pong)
   private RoutingFramebuffer createDirectHistoryFixFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.nrdDiffIllumPongFb.getWriteAttachment("data"),
         () -> this.nrdSpecIllumPongFb.getWriteAttachment("data")
      );
   }

   // History clamping: 5 outputs -> permanent prev-frame history
   //   loc 0 -> nrdDiffIllumPrevFb.write
   //   loc 1 -> nrdDiffIllumResponsivePrevFb.write
   //   loc 2 -> nrdSpecIllumPrevFb.write
   //   loc 3 -> nrdSpecIllumResponsivePrevFb.write
   //   loc 4 -> nrdHistoryLengthPrevFb.write
   private RoutingFramebuffer createDirectHistoryClampingFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.nrdDiffIllumPrevFb.getWriteAttachment("data"),
         () -> this.nrdDiffIllumResponsivePrevFb.getWriteAttachment("data"),
         () -> this.nrdSpecIllumPrevFb.getWriteAttachment("data"),
         () -> this.nrdSpecIllumResponsivePrevFb.getWriteAttachment("data"),
         () -> this.nrdHistoryLengthPrevFb.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createNrdCopyFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.nrdOutDiffRadianceHitDistFb.getWriteAttachment("data"),
         () -> this.nrdOutSpecRadianceHitDistFb.getWriteAttachment("data")
      );
   }

   // Anti-firefly: 2 outputs -> prev-frame illum write sides (post-clamping in-place update)
   private RoutingFramebuffer createDirectAntiFireflyFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.nrdDiffIllumPrevFb.getWriteAttachment("data"),
         () -> this.nrdSpecIllumPrevFb.getWriteAttachment("data")
      );
   }

   // AtrousSmem: 2 outputs -> pong buffers (first regular atrous pass input)
   private RoutingFramebuffer createNrdAtrousSmemFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.nrdDiffIllumPongFb.getWriteAttachment("data"),
         () -> this.nrdSpecIllumPongFb.getWriteAttachment("data")
      );
   }

   // Regular A-trous: 2 outputs via ping-pong routing helpers
   private RoutingFramebuffer createDirectAtrousFramebuffer() {
      return this.createRoutingFramebuffer(
         this::getCurrentDiffAtrousOutputTexture,
         this::getCurrentSpecAtrousOutputTexture
      );
   }

   private RoutingFramebuffer createIndirectInitialFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.indirectInitialReservoirBuffer.getWriteAttachment("position"),
         () -> this.indirectInitialReservoirBuffer.getWriteAttachment("normal"),
         () -> this.indirectInitialReservoirBuffer.getWriteAttachment("radiance"),
         () -> this.indirectInitialReservoirBuffer.getWriteAttachment("meta")
      );
   }

   private RoutingFramebuffer createIndirectBoilingFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.indirectReservoirBuffer.getWriteAttachment("position"),
         () -> this.indirectReservoirBuffer.getWriteAttachment("normal"),
         () -> this.indirectReservoirBuffer.getWriteAttachment("radiance"),
         () -> this.indirectReservoirBuffer.getWriteAttachment("meta")
      );
   }

   private void createLightingBufferAttachments(ColorFramebuffer framebuffer) {
      // Linear view depth in position.a is still required by direct reuse/shading,
      // NRD reprojection, and previous-frame surface reconstruction.
      framebuffer.createAttachment("position", "RGBA32F", false);
      framebuffer.createAttachment("normal", "RGB16F", false);
      framebuffer.createAttachment("mapped_normal", "RGB16F", false);
      framebuffer.createAttachment("albedo", "RGBA8", false);
      framebuffer.createAttachment("material", "RGBA16F", false);
      framebuffer.createAttachment("identity", "RGBA16F", false);
      framebuffer.createAttachment("direct", "RGBA16F", false);
      framebuffer.createAttachment("direct_specular", "RGBA16F", false);
      framebuffer.createAttachment("lighting", "RGBA32F", false);
      framebuffer.createAttachment("lighting_variance", "RGBA32F", false);
      framebuffer.createAttachment("handheld", "RGBA16F", false);
      framebuffer.createAttachment("indirect", "RGBA16F", false);
      framebuffer.createAttachment("indirect_variance", "RGBA32F", false);
   }

   private void createLightingStageAttachments(ColorFramebuffer framebuffer) {
      // Keep the stage geometry format aligned with lightingBuffer: direct reuse,
      // shading, and denoising all expect linear depth in stage_radiosity_position.a.
      framebuffer.createAttachment("position", "RGBA32F", false);
      framebuffer.createAttachment("normal", "RGB16F", false);
      framebuffer.createAttachment("mapped_normal", "RGB16F", false);
      framebuffer.createAttachment("albedo", "RGBA8", false);
      framebuffer.createAttachment("material", "RGBA16F", false);
      framebuffer.createAttachment("identity", "RGBA16F", false);
      framebuffer.createAttachment("direct", "RGBA16F", false);
      framebuffer.createAttachment("direct_specular", "RGBA16F", false);
      framebuffer.createAttachment("direct_combined", "RGBA16F", false);
      framebuffer.createAttachment("handheld", "RGBA16F", false);
      framebuffer.createAttachment("indirect", "RGBA16F", false);
   }

   private void createIndirectReservoirAttachments(ColorFramebuffer framebuffer) {
      framebuffer.createAttachment("position", "RGBA32F", false);
      // RTXDI packed GI reservoirs store packed normal / misc / radiance as 32-bit values.
      // These attachments are sampled back with floatBitsToUint(...), so 16-bit float formats
      // destroy the packed payload and corrupt M, age, and radiance on load.
      framebuffer.createAttachment("normal", "RGBA32F", false);
      framebuffer.createAttachment("radiance", "RGBA32F", false);
      framebuffer.createAttachment("meta", "RGBA32F", false);
   }



   private RoutingFramebuffer createProposalGeometryFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingStageBuffer.getWriteAttachment("position"),
         () -> this.lightingStageBuffer.getWriteAttachment("normal"),
         () -> this.lightingStageBuffer.getWriteAttachment("mapped_normal"),
         () -> this.lightingStageBuffer.getWriteAttachment("albedo"),
         () -> this.lightingStageBuffer.getWriteAttachment("material"),
         () -> this.lightingStageBuffer.getWriteAttachment("identity"),
         () -> this.motionVectorBuffer.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createProposalReservoirFramebuffer() {
      return this.createDirectPackedRoutingFramebuffer(
         () -> this.directReservoirBuffer.getWriteAttachment("data"),
         () -> this.directReservoirBuffer.getWriteAttachment("sample"),
         () -> this.directReservoirBuffer.getWriteAttachment("meta"),
         () -> this.proposalReconnectionBuffer.getWriteAttachment("reconnection0"),
         () -> this.proposalReconnectionBuffer.getWriteAttachment("reconnection1"),
         () -> this.proposalReconnectionBuffer.getWriteAttachment("reconnection2"),
         () -> this.proposalReconnectionBuffer.getWriteAttachment("reconnection3"),
         () -> this.proposalReconnectionBuffer.getWriteAttachment("reconnection4")
      );
   }

   private RoutingFramebuffer createReuseResolveFramebuffer() {
      // Spatial reuse writes the paired post-temporal reservoir and reconnection state
      // that the local final resolve stages consume directly in the same frame.
      return this.createDirectPackedRoutingFramebuffer(
         () -> this.directSpatialReservoirBuffer.getWriteAttachment("data"),
         () -> this.directSpatialReservoirBuffer.getWriteAttachment("sample"),
         () -> this.directSpatialReservoirBuffer.getWriteAttachment("meta"),
         () -> this.scatterReconnectionBuffer.getWriteAttachment("reconnection0"),
         () -> this.scatterReconnectionBuffer.getWriteAttachment("reconnection1"),
         () -> this.scatterReconnectionBuffer.getWriteAttachment("reconnection2"),
         () -> this.scatterReconnectionBuffer.getWriteAttachment("reconnection3"),
         () -> this.scatterReconnectionBuffer.getWriteAttachment("reconnection4")
      );
   }

   private RoutingFramebuffer createShadeSamplesLightingFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingStageBuffer.getWriteAttachment("direct"),
         () -> this.lightingStageBuffer.getWriteAttachment("direct_specular"),
         () -> this.lightingStageBuffer.getWriteAttachment("direct_combined")
      );
   }

   private RoutingFramebuffer createShadeSamplesReservoirFramebuffer() {
      // Reservoir finalization is the only promotion step from authoritative
      // same-frame post-spatial output into persistent direct history.
      return this.createDirectPackedRoutingFramebuffer(
         () -> this.directReservoirBuffer.getWriteAttachment("data"),
         () -> this.directReservoirBuffer.getWriteAttachment("sample"),
         () -> this.directReservoirBuffer.getWriteAttachment("meta")
      );
   }

   private RoutingFramebuffer createShadeSamplesReconnectionFramebuffer() {
      return this.createDirectPackedRoutingFramebuffer(
         () -> this.scatterReconnectionBuffer.getWriteAttachment("reconnection0"),
         () -> this.scatterReconnectionBuffer.getWriteAttachment("reconnection1"),
         () -> this.scatterReconnectionBuffer.getWriteAttachment("reconnection2"),
         () -> this.scatterReconnectionBuffer.getWriteAttachment("reconnection3"),
         () -> this.scatterReconnectionBuffer.getWriteAttachment("reconnection4")
      );
   }

   private RoutingFramebuffer createIndirectAccumulationFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingBuffer.getWriteAttachment("indirect"),
         () -> this.lightingBuffer.getWriteAttachment("indirect_variance"),
         () -> this.lightingBuffer.getWriteAttachment("handheld"),
         () -> this.indirectReservoirBuffer.getWriteAttachment("position"),
         () -> this.indirectReservoirBuffer.getWriteAttachment("normal"),
         () -> this.indirectReservoirBuffer.getWriteAttachment("radiance"),
         () -> this.indirectReservoirBuffer.getWriteAttachment("meta")
      );
   }

   private RoutingFramebuffer createIndirectAccumulationLightingFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingBuffer.getWriteAttachment("indirect"),
         () -> this.lightingBuffer.getWriteAttachment("indirect_variance"),
         () -> this.lightingBuffer.getWriteAttachment("handheld")
      );
   }

   private RoutingFramebuffer createIndirectAccumulationReservoirFramebuffer() {
      return this.createDirectPackedRoutingFramebuffer(
         () -> this.indirectReservoirBuffer.getWriteAttachment("position"),
         () -> this.indirectReservoirBuffer.getWriteAttachment("normal"),
         () -> this.indirectReservoirBuffer.getWriteAttachment("radiance"),
         () -> this.indirectReservoirBuffer.getWriteAttachment("meta")
      );
   }

   private RoutingFramebuffer createIndirectDenoisingFramebuffer() {
      return this.createRoutingFramebuffer(() -> this.indirectDenoisedBuffer.getWriteAttachment("data"));
   }

   private RoutingFramebuffer createPositionWriteFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingBuffer.getWriteAttachment("position"),
         () -> this.lightingBuffer.getWriteAttachment("normal"),
         () -> this.lightingBuffer.getWriteAttachment("mapped_normal"),
         () -> this.lightingBuffer.getWriteAttachment("albedo"),
         () -> this.lightingBuffer.getWriteAttachment("material"),
         () -> this.lightingBuffer.getWriteAttachment("identity"),
         () -> this.lightingBuffer.getWriteAttachment("direct"),
         () -> this.compatDirectSoftBuffer.getWriteAttachment("direct_soft_compat")
      );
   }

   private RoutingFramebuffer createShadeSamplesMonolithicFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingStageBuffer.getWriteAttachment("direct"),
         () -> this.lightingStageBuffer.getWriteAttachment("direct_specular"),
         () -> this.directReservoirBuffer.getWriteAttachment("data"),
         () -> this.directReservoirBuffer.getWriteAttachment("sample"),
         () -> this.directReservoirBuffer.getWriteAttachment("meta"),
         () -> this.lightingStageBuffer.getWriteAttachment("direct_combined")
      );
   }

   private RoutingFramebuffer createRoutingFramebuffer(Supplier<TextureObject>... attachments) {
      RoutingFramebuffer framebuffer = new RoutingFramebuffer();
      for (Supplier<TextureObject> attachment : attachments) {
         framebuffer.addAttachment(attachment);
      }
      return framebuffer;
   }

   @SafeVarargs
   private final RoutingFramebuffer createDirectPackedRoutingFramebuffer(Supplier<TextureObject>... attachments) {
      return this.createRoutingFramebuffer(this::getDirectPackedViewportWidth, attachments);
   }

   @SafeVarargs
   private final RoutingFramebuffer createRoutingFramebuffer(IntSupplier viewportWidthSupplier, Supplier<TextureObject>... attachments) {
      RoutingFramebuffer framebuffer = new RoutingFramebuffer(viewportWidthSupplier::getAsInt);
      for (Supplier<TextureObject> attachment : attachments) {
         framebuffer.addAttachment(attachment);
      }
      return framebuffer;
   }

   private int getDirectPackedViewportWidth() {
      return Math.max(1, this.directReservoirBuffer.getWriteAttachment("data").getTextureDimensions()[0]);
   }

   private TextureObject getCurrentGeometryPositionTexture() {
      if (this.shouldUseStageGeometry()) {
         return this.lightingStageBuffer.getWriteAttachment("position");
      }
      return this.lightingBuffer.getWriteAttachment("position");
   }

   private TextureObject getCurrentGeometryNormalTexture() {
      if (this.shouldUseStageGeometry()) {
         return this.lightingStageBuffer.getWriteAttachment("normal");
      }
      return this.lightingBuffer.getWriteAttachment("normal");
   }

   private TextureObject getCurrentMappedNormalTexture() {
      if (this.shouldUseStageGeometry()) {
         return this.lightingStageBuffer.getWriteAttachment("mapped_normal");
      }
      return this.lightingBuffer.getWriteAttachment("mapped_normal");
   }

   private TextureObject getCurrentMaterialTexture() {
      if (this.shouldUseStageGeometry()) {
         return this.lightingStageBuffer.getWriteAttachment("material");
      }
      return this.lightingBuffer.getWriteAttachment("material");
   }

   private TextureObject getCurrentIdentityTexture() {
      if (this.shouldUseStageGeometry()) {
         return this.lightingStageBuffer.getWriteAttachment("identity");
      }
      return this.lightingBuffer.getWriteAttachment("identity");
   }

   private TextureObject getCurrentAlbedoTexture() {
      if (this.shouldUseStageGeometry()) {
         return this.lightingStageBuffer.getWriteAttachment("albedo");
      }
      return this.lightingBuffer.getWriteAttachment("albedo");
   }

   private boolean shouldUseStageGeometry() {
      return this.isCurrentPhotonicsFragment(diShadeSamplesFragment)
         || this.isCurrentPhotonicsFragment(diInitialCandidatesFragment)
         || this.isCurrentPhotonicsFragment(diCollectTemporalSamplesFragment)
         || this.isCurrentPhotonicsFragment(diRobustReuseOptimizationFragment)
         || this.isCurrentPhotonicsFragment(diGatherTemporalResamplingFragment)
         || this.isCurrentPhotonicsFragment(diTemporalReprojectionFragment)
         || this.isCurrentPhotonicsFragment(diTemporalBinningOffsetsFragment)
         || this.isCurrentPhotonicsFragment(diTemporalBinningFragment)
         || this.isCurrentPhotonicsFragment(diMultiTemporalReprojectionFragment)
         || this.isCurrentPhotonicsFragment(diMultiTemporalBinningOffsetsFragment)
         || this.isCurrentPhotonicsFragment(diMultiTemporalBinningFragment)
         || this.isCurrentPhotonicsFragment(diShadeSamplesLightingFragment)
         || this.isCurrentPhotonicsFragment(diShadeSamplesReservoirFragment)
         || this.isCurrentPhotonicsFragment(diSpatialResamplingFragment)
         || this.isCurrentPhotonicsFragment(diScatterTemporalResamplingFragment)
         || this.isCurrentPhotonicsFragment(diScatterBackupTemporalResamplingFragment)
         || this.isCurrentPhotonicsFragment(diMultiScatterTemporalResamplingFragment)
         // NRD RELAX fused pipeline passes that read stage geometry (current frame)
         || this.isCurrentPhotonicsFragment(nrdClassifyTilesFragment)
         || this.isCurrentPhotonicsFragment(nrdHitDistReconstructionFragment)
         || this.isCurrentPhotonicsFragment(nrdPrepassFragment)
         || this.isCurrentPhotonicsFragment(relaxTemporalAccumulationFragment)
         || this.isCurrentPhotonicsFragment(relaxHistoryFixFragment)
         || this.isCurrentPhotonicsFragment(relaxHistoryClampingFragment)
         || this.isCurrentPhotonicsFragment(nrdCopyFragment)
         || this.isCurrentPhotonicsFragment(relaxAntiFireflyFragment)
         || this.isCurrentPhotonicsFragment(nrdAtrousSmemFragment)
         || this.isCurrentPhotonicsFragment(relaxAtrousFragment)
         || this.isCurrentPhotonicsFragment(indirectTemporalReprojectionFragment)
         || this.isCurrentPhotonicsFragment(indirectTemporalBinningOffsetsFragment)
         || this.isCurrentPhotonicsFragment(indirectTemporalBinningFragment)
         || this.isCurrentPhotonicsFragment(indirectScatterTemporalFragment)
         || this.isCurrentPhotonicsFragment(indirectAccumulationFragment)
         // GI denoising runs before the accumulation pass copies the current frame
         // guides into lightingBuffer, so it must read the live stage geometry.
         || this.isCurrentPhotonicsFragment(indirectDenoisingFragment);
   }

   // ---------------------------------------------------------------------------
   // NRD RELAX fused A-trous ping-pong routing (contract §1, hard-coded 5-pass cascade)
   // directAtrousIteration: 1 = first regular pass (reads from SMEM output / pong),
   //                        2-4 = subsequent passes.
   // SMEM pass (iter=0) always writes to pong; regular passes ping-pong between
   // pong (iter=1 input) -> ping (iter=1 output) -> pong ... Final pass (iter=4)
   // writes to nrdOutDiff/SpecRadianceHitDistFb.
   // ---------------------------------------------------------------------------

   // nrd_diff_illum_prev / nrd_spec_illum_prev:
   //   temporal accumulation reads PREVIOUS frame's clamped slow (.read).
   //   nrd_copy reads THIS frame's clamping output (.write) and republishes it.
   //   atrous smem reads THIS frame's post-anti-firefly slow (.write).
   //   anti-firefly does not sample this binding (it reads nrd_out_*).
   private boolean shouldUseCurrentNrdIllumPrev() {
      return this.isCurrentPhotonicsFragment(nrdAtrousSmemFragment)
         || this.isCurrentPhotonicsFragment(nrdCopyFragment);
   }

   private TextureObject getCurrentNrdDiffIllumPrevTexture() {
      if (this.shouldUseCurrentNrdIllumPrev()) {
         return this.nrdDiffIllumPrevFb.getWriteAttachment("data");
      }
      return this.nrdDiffIllumPrevFb.getReadAttachment("data");
   }

   private TextureObject getCurrentNrdDiffIllumResponsivePrevTexture() {
      if (this.shouldUseCurrentNrdIllumPrev()) {
         return this.nrdDiffIllumResponsivePrevFb.getWriteAttachment("data");
      }
      return this.nrdDiffIllumResponsivePrevFb.getReadAttachment("data");
   }

   private TextureObject getCurrentNrdSpecIllumPrevTexture() {
      if (this.shouldUseCurrentNrdIllumPrev()) {
         return this.nrdSpecIllumPrevFb.getWriteAttachment("data");
      }
      return this.nrdSpecIllumPrevFb.getReadAttachment("data");
   }

   private TextureObject getCurrentNrdSpecIllumResponsivePrevTexture() {
      if (this.shouldUseCurrentNrdIllumPrev()) {
         return this.nrdSpecIllumResponsivePrevFb.getWriteAttachment("data");
      }
      return this.nrdSpecIllumResponsivePrevFb.getReadAttachment("data");
   }

   // Regular A-trous input: ping/pong based on iteration parity.
   // iteration 1 reads pong (SMEM output), iteration 2 reads ping, etc.
   private TextureObject getCurrentDiffAtrousInputTexture() {
      if ((this.directAtrousIteration & 1) == 1) {
         return this.nrdDiffIllumPongFb.getWriteAttachment("data");
      }
      return this.nrdDiffIllumPingFb.getWriteAttachment("data");
   }

   private TextureObject getCurrentSpecAtrousInputTexture() {
      if ((this.directAtrousIteration & 1) == 1) {
         return this.nrdSpecIllumPongFb.getWriteAttachment("data");
      }
      return this.nrdSpecIllumPingFb.getWriteAttachment("data");
   }

   // Regular A-trous output: opposite of input, except final pass -> nrdOutXxx.
   private TextureObject getCurrentDiffAtrousOutputTexture() {
      if (this.directAtrousIteration == NRD_ATROUS_STRIDES.length - 1) {
         return this.nrdOutDiffRadianceHitDistFb.getWriteAttachment("data");
      }
      if ((this.directAtrousIteration & 1) == 1) {
         return this.nrdDiffIllumPingFb.getWriteAttachment("data");
      }
      return this.nrdDiffIllumPongFb.getWriteAttachment("data");
   }

   private TextureObject getCurrentSpecAtrousOutputTexture() {
      if (this.directAtrousIteration == NRD_ATROUS_STRIDES.length - 1) {
         return this.nrdOutSpecRadianceHitDistFb.getWriteAttachment("data");
      }
      if ((this.directAtrousIteration & 1) == 1) {
         return this.nrdSpecIllumPingFb.getWriteAttachment("data");
      }
      return this.nrdSpecIllumPongFb.getWriteAttachment("data");
   }

   private int getCurrentDirectAtrousStepSize() {
      int iterationIndex = Math.max(0, Math.min(this.directAtrousIteration, NRD_ATROUS_STRIDES.length - 1));
      return NRD_ATROUS_STRIDES[iterationIndex];
   }

   private float getDirectSampleBudgetScale() {
      return 1.0f;
   }

   private int getCurrentDirectAtrousIsLastPass() {
      return this.directAtrousIteration == NRD_ATROUS_STRIDES.length - 1 ? 1 : 0;
   }

   private boolean shouldRunHitDistReconstruction() {
      // Default ph_nrd_hitdist_reconstruction = 0.0, so this is always false unless
      // overridden via uniform. Gated here to avoid the pass when not needed.
      return false;
   }

   private GpuTimerQuery createGpuTimerQuery() {
      return new GpuTimerQuery(gpuProfilerRegionNames);
   }

   private void resolveGpuProfile() {
      this.gpuTimerQuery.resolve();
   }

   private int resolveRegirFrameSeed(String stageProperty, String sharedProperty, String stageName) {
      String override = System.getProperty(stageProperty);
      if (override == null || override.isBlank()) {
         override = System.getProperty(sharedProperty);
      }

      if (override != null && !override.isBlank()) {
         try {
            int parsed = Integer.parseInt(override.trim());
            boolean alreadyLogged = "presample".equals(stageName)
               ? this.loggedRegirPresampleFrameSeedOverride
               : this.loggedRegirBuildFrameSeedOverride;
            if (!alreadyLogged) {
               Photonic.info("[RegirCompute] Using fixed {} frame seed override {}", stageName, parsed);
               if ("presample".equals(stageName)) {
                  this.loggedRegirPresampleFrameSeedOverride = true;
               } else {
                  this.loggedRegirBuildFrameSeedOverride = true;
               }
            }
            return parsed;
         } catch (NumberFormatException ignored) {
         }
      }

      if (PhotonicsStorage.REGIR_FIXED_FRAME_SEED.value) {
         return Math.round(PhotonicsStorage.REGIR_FRAME_SEED.value);
      }

      return this.renderFrameIndex;
   }

   private int resolveRegirPresampleFrameSeed() {
      return this.resolveRegirFrameSeed("photonics.regirPresampleFrameSeed", "photonics.regirFrameSeed", "presample");
   }

   private int resolveRegirBuildFrameSeed() {
      return this.resolveRegirFrameSeed("photonics.regirBuildFrameSeed", "photonics.regirFrameSeed", "build");
   }

   private void dispatchRegirCompute() {
      if (!this.shouldUseRegirLocalLightSampling()) {
         return;
      }
      if (this.isGpuRegirBuildDisabledForIsolation()) {
         return;
      }
      if (this.regirComputeProgram == null || !this.regirComputeProgram.isCompiled()) {
         return;
      }
      LightRegistry lightRegistry = this.worldRegistry.getLightRegistry();
      int lightCount = lightRegistry.lightCount();
      if (lightCount <= 0) {
         this.cachedRegirPdfPowers = null;
         this.cachedRegirPdfLightCount = 0;
         this.cachedRegirSemanticLayoutHash = Long.MIN_VALUE;
         this.hasValidRegirBuild = false;
         return;
      }

      long currentSemanticHash = lightRegistry.getSemanticLayoutHash();
      Vector3f gridCenter = lightRegistry.getRegirGridCenter();
      float cellSize = lightRegistry.getRegirHashCellSizeBlocks();
      int camCellX = (int) Math.floor(gridCenter.x / cellSize);
      int camCellY = (int) Math.floor(gridCenter.y / cellSize);
      int camCellZ = (int) Math.floor(gridCenter.z / cellSize);

      if (this.hasValidRegirBuild
            && currentSemanticHash == this.cachedRegirBuildSemanticHash
            && camCellX == this.cachedRegirBuildCamCellX
            && camCellY == this.cachedRegirBuildCamCellY
            && camCellZ == this.cachedRegirBuildCamCellZ) {
         return;
      }

      // Update PDF mipmap texture whenever the live light layout driving ReGIR changes.
      // Reservoir-splatting relies on flashing/tile coverage recovering dark cells after layout shifts,
      // so we must invalidate on semantic/layout churn, not only power-count changes.
      float[] powers = lightRegistry.getRegirLightPowers();
      long semanticLayoutHash = lightRegistry.getSemanticLayoutHash();
      if (powers.length > 0) {
         this.regirComputeProgram.createPdfTexture(lightCount);
         if (this.shouldRefreshRegirPdfTexture(powers, lightCount, semanticLayoutHash)) {
            this.regirComputeProgram.updatePdfTexture(powers, lightCount);
            this.cachedRegirPdfPowers = powers.clone();
            this.cachedRegirPdfLightCount = lightCount;
            this.cachedRegirSemanticLayoutHash = semanticLayoutHash;
         }
      }

      // Hash-grid ReGIR (paper variant): cells are world-fixed and addressed by
      // hash(quantized_position, normal_bucket). The legacy gridCells/cellSize uniforms
      // are still passed for diagnostic shaders that have not been migrated.
      int gridRes = lightRegistry.getRegirGridResolution();
      lightRegistry.refreshActiveRegirCells(lightRegistry.getRegirGridCenter());
      this.regirComputeProgram.dispatch(
         lightRegistry.getLightsMemoryManager(),
         lightRegistry.getGlobalLightCdfMemoryManager(),
         lightRegistry.getRegirLightIndexMemoryManager(),
         lightRegistry.getRegirCompactLightDataMemoryManager(),
         lightRegistry.getRegirHashChecksumMemoryManager(),
         lightRegistry.getRegirHashKeyMemoryManager(),
         lightRegistry.getRegirGridCenter(),
         new Vector3i(gridRes, gridRes, gridRes),
         lightRegistry.getRegirLightsPerCell(),
         32.0f,
         lightCount,
         this.resolveRegirPresampleFrameSeed(),
         this.resolveRegirBuildFrameSeed(),
         this.getRegirBuildSampleCount(),
         lightRegistry.getRegirSamplingJitter(),
         lightRegistry.getRegirHashTableSize(),
         lightRegistry.getRegirHashCellSizeBlocks(),
         lightRegistry.getRegirHashNormalBuckets(),
         lightRegistry.getRegirBuildRegionCells(),
         this.lightingStageBuffer.getWriteAttachment("position"),
         this.lightingStageBuffer.getWriteAttachment("mapped_normal"),
         lightRegistry.getActiveRegirCellCount(),
         lightRegistry.getActiveRegirCellsBuffer()
      );

      this.cachedRegirBuildSemanticHash = currentSemanticHash;
      this.cachedRegirBuildCamCellX = camCellX;
      this.cachedRegirBuildCamCellY = camCellY;
      this.cachedRegirBuildCamCellZ = camCellZ;
      this.hasValidRegirBuild = true;
   }

   private int getRegirBuildSampleCount() {
      String override = System.getProperty("photonics.regirBuildSamples");
      if (override != null && !override.isBlank()) {
         try {
            return Math.max(1, Integer.parseInt(override.trim()));
         } catch (NumberFormatException ignored) {
         }
      }

      return Math.max(1, Math.round(PhotonicsStorage.REGIR_BUILD_SAMPLES.value));
   }

   private boolean shouldRefreshRegirPdfTexture(float[] powers, int lightCount, long semanticLayoutHash) {
      if (lightCount != this.cachedRegirPdfLightCount
         || this.cachedRegirPdfPowers == null
         || this.cachedRegirPdfPowers.length != powers.length
         || semanticLayoutHash != this.cachedRegirSemanticLayoutHash) {
         return true;
      }

      for (int i = 0; i < powers.length; i++) {
         if (Float.floatToIntBits(this.cachedRegirPdfPowers[i]) != Float.floatToIntBits(powers[i])) {
            return true;
         }
      }

      return false;
   }

   private void renderProfiled(int regionIndex, @Nullable CompositeRenderer renderer) {
      if (renderer == null) {
         return;
      }
      this.beginGpuRegion(regionIndex);
      renderer.renderAll();
      this.endGpuRegion(regionIndex);
   }

   private void renderLightTreeSamplingStageProfiled() {
      this.beginGpuRegion(lightTreeSamplingStageRegionIndex);
      if (this.proposalStageRenderer != null) {
         this.proposalStageRenderer.renderAll();
      }
      GL42.glMemoryBarrier(GL42.GL_FRAMEBUFFER_BARRIER_BIT | GL42.GL_TEXTURE_FETCH_BARRIER_BIT);
      this.dispatchRegirCompute();
      this.endGpuRegion(lightTreeSamplingStageRegionIndex);
   }

   private boolean shouldUseRegirLocalLightSampling() {
      return "regir_ris".equals(
         PhotonicsStorage.normalizeRestirLocalLightSamplingMode(PhotonicsStorage.RESTIR_LOCAL_LIGHT_SAMPLING_MODE.value)
      );
   }

   private void renderDIInitialCandidatesProfiled() {
      this.beginGpuRegion(initialCandidatesRegionIndex);
      if (this.isDirectProposalReservoirEnabled()) {
         if (this.proposalReservoirRenderer != null) {
            this.proposalReservoirRenderer.renderAll();
         }
      } else {
         this.clearProposalReservoirOutputs();
      }
      this.setCurrentDiReconnectionSource(DiReconnectionSource.PROPOSAL);
      this.endGpuRegion(initialCandidatesRegionIndex);
   }

   private void renderDIScatterTemporalProfiled() {
      this.beginGpuRegion(diTemporalResamplingRegionIndex);
      this.setCurrentDiReconnectionSource(DiReconnectionSource.PROPOSAL);
      boolean scatterBackupTemporalBranch = false;
      boolean multiScatterTemporalBranch = false;
      boolean robustTemporalGather = "robust".equals(
         PhotonicsStorage.normalizeRestirTemporalGatherMode(PhotonicsStorage.RESTIR_TEMPORAL_GATHER_MODE.value)
      );
      boolean scatterOnlyTemporalBranch = false;
      boolean gatherTemporalBranch = true;
      boolean gatherTemporalResolveBranch = true;
      boolean wroteTemporalOutput = false;
      if (gatherTemporalBranch && robustTemporalGather) {
         this.clearTemporalGatherBuffers();
      }
      if (scatterOnlyTemporalBranch || scatterBackupTemporalBranch) {
         this.clearCurrentTemporalScatterBuffers();
      }
      if (multiScatterTemporalBranch) {
         this.clearMultiTemporalScatterBuffers();
      }
      if (gatherTemporalBranch) {
         this.ensureTemporalGatherRenderers();
      }
      if (scatterOnlyTemporalBranch || scatterBackupTemporalBranch) {
         this.ensureTemporalScatterRenderers();
      }
      if (multiScatterTemporalBranch) {
         this.ensureMultiTemporalScatterRenderers();
      }
      if (scatterBackupTemporalBranch) {
         this.ensureScatterBackupTemporalRenderer();
      }
      if (gatherTemporalBranch && robustTemporalGather && this.robustReuseOptimizationRenderer != null) {
         this.robustReuseOptimizationRenderer.renderAll();
         GL42.glMemoryBarrier(GL43.GL_SHADER_STORAGE_BARRIER_BIT | GL42.GL_FRAMEBUFFER_BARRIER_BIT);
      }
      if (gatherTemporalBranch && this.temporalCollectRenderer != null) {
         this.temporalCollectRenderer.renderAll();
         GL42.glMemoryBarrier(GL42.GL_FRAMEBUFFER_BARRIER_BIT | GL42.GL_TEXTURE_FETCH_BARRIER_BIT);
      }
      if (gatherTemporalResolveBranch && this.temporalGatherRenderer != null) {
         this.temporalGatherRenderer.renderAll();
         GL42.glMemoryBarrier(GL42.GL_FRAMEBUFFER_BARRIER_BIT | GL42.GL_TEXTURE_FETCH_BARRIER_BIT);
         wroteTemporalOutput = true;
      }
      if (multiScatterTemporalBranch) {
         if (this.temporalMultiScatterReprojectionRenderer != null) {
            this.temporalMultiScatterReprojectionRenderer.renderAll();
            this.barrierTemporalScatterOwnershipWrites();
         }
         if (this.temporalMultiScatterBinningOffsetsRenderer != null) {
            this.temporalMultiScatterBinningOffsetsRenderer.renderAll();
            this.barrierTemporalScatterBinningHalves();
         }
         if (this.temporalMultiScatterBinningRenderer != null) {
            this.temporalMultiScatterBinningRenderer.renderAll();
            this.barrierTemporalScatterResolveInputs();
         }
         if (this.multiScatterTemporalRenderer != null) {
            this.multiScatterTemporalRenderer.renderAll();
            wroteTemporalOutput = true;
         }
      } else if (scatterOnlyTemporalBranch && this.temporalScatterReprojectionRenderer != null) {
         this.temporalScatterReprojectionRenderer.renderAll();
         this.barrierTemporalScatterOwnershipWrites();
      }
      // Reference: SortReprojectedReservoirs.cs.slang runs computeCellOffsets
      // and sortCellData as TWO separate compute dispatches with a pipeline
      // barrier between them (see ReservoirSplatting.cpp:423-465 for the
      // two-phase dispatch). The prefix-sum half MUST complete and its
      // cellOffsets[] writes MUST be globally visible before the sort half
      // reads `cellOffsets[indices.x]`, otherwise the sort reads stale values
      // and writes contributors to wrong cells -- producing flashing tiles.
      if (scatterOnlyTemporalBranch && this.temporalScatterBinningOffsetsRenderer != null) {
         this.temporalScatterBinningOffsetsRenderer.renderAll();
         this.barrierTemporalScatterBinningHalves();
      }
      if (scatterOnlyTemporalBranch && this.temporalScatterBinningRenderer != null) {
         this.temporalScatterBinningRenderer.renderAll();
         this.barrierTemporalScatterResolveInputs();
      }
      if (scatterBackupTemporalBranch && this.scatterBackupTemporalRenderer != null) {
         if (this.temporalScatterReprojectionRenderer != null) {
            this.temporalScatterReprojectionRenderer.renderAll();
            this.barrierTemporalScatterOwnershipWrites();
         }
         if (this.temporalScatterBinningOffsetsRenderer != null) {
            this.temporalScatterBinningOffsetsRenderer.renderAll();
            this.barrierTemporalScatterBinningHalves();
         }
         if (this.temporalScatterBinningRenderer != null) {
            this.temporalScatterBinningRenderer.renderAll();
            this.barrierTemporalScatterResolveInputs();
         }
         this.scatterBackupTemporalRenderer.renderAll();
         wroteTemporalOutput = true;
      } else if (scatterOnlyTemporalBranch && this.scatterTemporalRenderer != null) {
         this.scatterTemporalRenderer.renderAll();
         wroteTemporalOutput = true;
      }
      if (wroteTemporalOutput) {
         GL42.glMemoryBarrier(GL42.GL_FRAMEBUFFER_BARRIER_BIT | GL42.GL_TEXTURE_FETCH_BARRIER_BIT);
      }
      this.endGpuRegion(diTemporalResamplingRegionIndex);
   }

   private void barrierTemporalScatterOwnershipWrites() {
      GL42.glMemoryBarrier(GL43.GL_SHADER_STORAGE_BARRIER_BIT | GL42.GL_FRAMEBUFFER_BARRIER_BIT);
   }

   private void ensureScatterBackupTemporalRenderer() {
      if (this.scatterBackupTemporalRenderer != null || this.compositeRendererCreator == null) {
         return;
      }

      this.setCurrentPhotonicsFragment(diScatterBackupTemporalResamplingFragment);
      try {
         this.scatterBackupTemporalRenderer = this.compositeRendererCreator.apply(
            List.of(new PhotonicsShader(diScatterBackupTemporalResamplingFragment, "common/screen.vsh", this.memoryCollection, this.temporalReservoirFramebuffer))
         );
      } finally {
         this.setCurrentPhotonicsFragment("");
      }
   }

   private void barrierTemporalScatterBinningHalves() {
      // Cross-draw barrier between SortReprojectedReservoirs.cs.slang's
      // computeCellOffsets (prefix sum) and sortCellData (sort) halves.
      // SHADER_STORAGE: cellOffsets[] writes from the offsets pass must be
      // visible to subsequent fragment reads in the sort pass.
      // FRAMEBUFFER: both passes share the temporalScatterStageFramebuffer
      // attachments, so ordering for dummy fragment writes matters too.
      GL42.glMemoryBarrier(GL43.GL_SHADER_STORAGE_BARRIER_BIT | GL42.GL_FRAMEBUFFER_BARRIER_BIT);
   }

   private void barrierTemporalScatterResolveInputs() {
      GL42.glMemoryBarrier(GL43.GL_SHADER_STORAGE_BARRIER_BIT | GL42.GL_TEXTURE_FETCH_BARRIER_BIT | GL42.GL_FRAMEBUFFER_BARRIER_BIT);
   }

   private void drainDirtyBlocksIntoRingBuffer() {
      java.util.List<net.minecraft.util.math.BlockPos> consumed =
         this.worldRegistry.getLightRegistry().consumeDirtyLightBlocks();
      for (net.minecraft.util.math.BlockPos pos : consumed) {
         int slot = this.dirtyBlockWriteHead % dirtyBlockCapacity;
         this.dirtyBlockCentres[slot] = pos.getX() + 0.5f;
         this.dirtyBlockCentresY[slot] = pos.getY() + 0.5f;
         this.dirtyBlockCentresZ[slot] = pos.getZ() + 0.5f;
         this.dirtyBlockFrameSeen[slot] = this.renderFrameIndex;
         this.dirtyBlockWriteHead++;
      }
      // Rebuild the flat shader buffer; expired slots encoded as w=-1.
      for (int i = 0; i < dirtyBlockCapacity; i++) {
         int age = this.renderFrameIndex - this.dirtyBlockFrameSeen[i];
         boolean active = this.dirtyBlockFrameSeen[i] != Integer.MIN_VALUE && age <= dirtyBlockTtl;
         this.dirtyBlockBuffer[i * 4    ] = active ? this.dirtyBlockCentres[i]  : 0.0f;
         this.dirtyBlockBuffer[i * 4 + 1] = active ? this.dirtyBlockCentresY[i] : 0.0f;
         this.dirtyBlockBuffer[i * 4 + 2] = active ? this.dirtyBlockCentresZ[i] : 0.0f;
         this.dirtyBlockBuffer[i * 4 + 3] = active ? (float) age : -1.0f;
      }
   }

   private boolean isDirectTemporalReuseEnabled() {
      return this.directTemporalReuseActiveThisFrame;
   }

   private boolean isDirectTemporalReuseRequested() {
      return PhotonicsStorage.DEBUG_ENABLE_DIRECT_TEMPORAL_REUSE.value;
   }

   private boolean shouldRunReservoirSplattingTemporalResampling(boolean resetReservoirSplatting) {
      return this.isDirectTemporalReuseRequested()
         && !resetReservoirSplatting
         && this.renderFrameIndex > 1;
   }

   private boolean shouldResetNrdHistory() {
      // Regional blends are emitted for ordinary block edits. Resetting RELAX for
      // those local updates drops the whole frame to young-history spatial blur.
      // Only full reloads need the global NRD history reset.
      return !PhotonicsStorage.DEBUG_DISABLE_TEMPORAL_RESET.value
         && this.worldRegistry.fetchLightReload()
         && this.worldRegistry.fetchLightBlendFactor() >= 0.999f;
   }

   // -------------------------------------------------------------------------
   // NRD history-confidence cascade helpers
   // -------------------------------------------------------------------------

   private int getCurrentConfidenceBlurStep() {
      return this.currentConfidenceBlurStep;
   }

   // The gradient pass outputs to nrdConfidenceGradientFb.
   // The first blur pass reads nrdConfidenceGradientFb; subsequent passes ping-pong
   // between nrdConfidenceBlurPingFb and nrdConfidenceBlurPongFb.
   // After 5 passes the final result lives in nrdConfidenceBlurPingFb (write-side)
   // which is bound as ph_nrd_diff_confidence for the next frame's TA.
   //
   // Ping-pong schedule (output of pass i -> input of pass i+1):
   //   pass 0 (gradient): -> gradientFb
   //   pass 1 (step=1):   gradientFb -> pingFb
   //   pass 2 (step=2):   pingFb     -> pongFb
   //   pass 3 (step=4):   pongFb     -> pingFb
   //   pass 4 (step=8):   pingFb     -> pongFb
   //   pass 5 (step=16):  pongFb     -> pingFb   <-- final result in pingFb
   //
   // nrd_diff_confidence_gradient sampler is rebound per-pass via getCurrentConfidenceBlurInputTexture.

   private int confidenceBlurIteration = 0;

   // Returns the texture that the current blur pass should sample as input.
   // Used by the nrd_diff_confidence_gradient sampler binding.
   //
   // Ping-pong schedule: each pass reads the previous pass's output.
   //   Output of pass i (even) -> pingFb
   //   Output of pass i (odd)  -> pongFb
   //   => Input of pass j (even j>0) -> pongFb  (output of pass j-1, which was odd)
   //   => Input of pass j (odd  j>0) -> pingFb  (output of pass j-1, which was even)
   //   => Input of pass 0 -> gradientFb (gradient pass output)
   private TextureObject getCurrentConfidenceBlurInputTexture() {
      if (this.confidenceBlurIteration == 0) {
         return this.nrdConfidenceGradientFb.getWriteAttachment("data");
      }
      // pass j reads: ping if j is odd (prev was even -> wrote ping)
      //                pong if j is even (prev was odd -> wrote pong)
      return ((this.confidenceBlurIteration % 2) == 1)
         ? this.nrdConfidenceBlurPingFb.getWriteAttachment("data")
         : this.nrdConfidenceBlurPongFb.getWriteAttachment("data");
   }

   // Returns the texture that the current blur pass should write to.
   // Used by the nrdConfidenceBlurFramebuffer attachment supplier.
   //   Pass 0 (step=1):  writes ping  (even)
   //   Pass 1 (step=2):  writes pong  (odd)
   //   Pass 2 (step=4):  writes ping  (even)
   //   Pass 3 (step=8):  writes pong  (odd)
   //   Pass 4 (step=16): writes ping  (even) <- final confidence in pingFb
   private TextureObject getCurrentConfidenceBlurOutputTexture() {
      return ((this.confidenceBlurIteration % 2) == 0)
         ? this.nrdConfidenceBlurPingFb.getWriteAttachment("data")
         : this.nrdConfidenceBlurPongFb.getWriteAttachment("data");
   }

   private RoutingFramebuffer createNrdConfidenceGradientFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.nrdConfidenceGradientFb.getWriteAttachment("data")
      );
   }

   // Single dynamic blur framebuffer: attachment supplier evaluates getCurrentConfidenceBlurOutputTexture()
   // at bind-time so each renderAll() call routes to the correct ping or pong buffer.
   private RoutingFramebuffer createNrdConfidenceBlurFramebuffer() {
      return this.createRoutingFramebuffer(
         this::getCurrentConfidenceBlurOutputTexture
      );
   }

   // Dispatch the gradient pass then the 5-pass blur cascade.
   // Must run after RELAXTemporalAccumulation each frame.
   // Reference: NRD-Sample dispatches ConfidenceBlur passes after TemporalAccumulation.
   private void renderConfidenceCascade() {
      if (this.nrdConfidenceGradientRenderer == null || this.nrdConfidenceBlurRenderer == null) {
         return;
      }

      // On world reload, invalidate so TA doesn't sample stale confidence.
      if (this.shouldResetNrdHistory()) {
         this.hasHistoryConfidence = false;
      }

      this.beginGpuRegion(nrdConfidenceCascadeRegionIndex);

      // Pass 0: gradient
      this.nrdConfidenceGradientRenderer.renderAll();
      GL42.glMemoryBarrier(GL42.GL_FRAMEBUFFER_BARRIER_BIT | GL42.GL_TEXTURE_FETCH_BARRIER_BIT);

      // Passes 1-5: blur cascade with step sizes 1, 2, 4, 8, 16.
      // confidenceBlurIteration drives both the input sampler (getCurrentConfidenceBlurInputTexture)
      // and the output framebuffer (getCurrentConfidenceBlurOutputTexture) via supplier lambdas.
      for (int passIndex = 0; passIndex < NRD_CONFIDENCE_BLUR_STEPS.length; passIndex++) {
         this.confidenceBlurIteration = passIndex;
         this.currentConfidenceBlurStep = NRD_CONFIDENCE_BLUR_STEPS[passIndex];
         this.nrdConfidenceBlurRenderer.renderAll();
         GL42.glMemoryBarrier(GL42.GL_FRAMEBUFFER_BARRIER_BIT | GL42.GL_TEXTURE_FETCH_BARRIER_BIT);
      }

      this.endGpuRegion(nrdConfidenceCascadeRegionIndex);

      // After the first complete cascade the confidence texture is valid.
      this.hasHistoryConfidence = true;
   }

   private boolean shouldResetReservoirSplattingTemporal(boolean reservoirHistoryReset) {
      return reservoirHistoryReset
         || (this.worldRegistry.fetchLightReload() && !PhotonicsStorage.DEBUG_DISABLE_TEMPORAL_RESET.value);
   }

   private boolean isDirectSpatialReuseEnabled() {
      return PhotonicsStorage.DEBUG_ENABLE_DIRECT_SPATIAL_REUSE.value;
   }

   private DiReconnectionSource getSpatialResamplingInputReconnectionSource() {
      return this.isDirectTemporalReuseEnabled()
         ? DiReconnectionSource.TEMPORAL
         : DiReconnectionSource.PROPOSAL;
   }

   private DiReconnectionSource getShadingInputReconnectionSource() {
      if (this.isDirectSpatialReuseEnabled()) {
         return DiReconnectionSource.FINAL;
      }

      return this.getSpatialResamplingInputReconnectionSource();
   }

   private void renderDISpatialResamplingProfiled() {
      if (!this.isDirectSpatialReuseEnabled()) {
         return;
      }

      this.setCurrentDiReconnectionSource(this.getSpatialResamplingInputReconnectionSource());
      this.renderProfiled(diSpatialResamplingRegionIndex, this.reuseResolveRenderer);
      GL42.glMemoryBarrier(GL42.GL_FRAMEBUFFER_BARRIER_BIT | GL42.GL_TEXTURE_FETCH_BARRIER_BIT);
      this.setCurrentDiReconnectionSource(DiReconnectionSource.FINAL);
   }

   private void renderIndirectAccumulationProfiled() {
      if (!this.shouldRunReservoirSplattingIndirectPipeline()) {
         return;
      }
      if (this.indirectInitialRenderer == null && this.indirectBoilingRenderer == null && this.indirectAccumulationRenderer == null
            && this.indirectAccumulationLightingRenderer == null && this.indirectAccumulationReservoirRenderer == null) {
         return;
      }
      this.beginGpuRegion(restirGIRegionIndex);
      if (this.indirectInitialRenderer != null) {
         this.indirectInitialRenderer.renderAll();
      }
      if (this.shouldRunIndirectBoilingFilter() && this.indirectBoilingRenderer != null) {
         this.indirectBoilingRenderer.renderAll();
         GL42.glMemoryBarrier(GL42.GL_FRAMEBUFFER_BARRIER_BIT | GL42.GL_TEXTURE_FETCH_BARRIER_BIT);
         this.indirectReservoirBuffer.swap();
      }
      if (this.indirectTemporalSplattingActiveThisFrame) {
         if (this.renderIndirectTemporalSplatting()) {
            this.indirectReservoirBuffer.swap();
         } else {
            this.indirectTemporalSplattingActiveThisFrame = false;
         }
      }
      if (this.indirectAccumulationRenderer != null) {
         this.indirectAccumulationRenderer.renderAll();
      }
      if (this.indirectAccumulationLightingRenderer != null) {
         this.indirectAccumulationLightingRenderer.renderAll();
      }
      if (this.indirectAccumulationReservoirRenderer != null) {
         this.indirectAccumulationReservoirRenderer.renderAll();
      }
      this.endGpuRegion(restirGIRegionIndex);
   }

   private boolean renderIndirectTemporalSplatting() {
      this.ensureIndirectTemporalSplattingRenderers();
      if (this.indirectTemporalReprojectionRenderer == null
         || this.indirectTemporalBinningOffsetsRenderer == null
         || this.indirectTemporalBinningRenderer == null
         || this.indirectScatterTemporalRenderer == null) {
         return false;
      }
      this.clearCurrentTemporalScatterBuffers();
      this.indirectTemporalReprojectionRenderer.renderAll();
      this.barrierTemporalScatterOwnershipWrites();
      this.indirectTemporalBinningOffsetsRenderer.renderAll();
      this.barrierTemporalScatterBinningHalves();
      this.indirectTemporalBinningRenderer.renderAll();
      this.barrierTemporalScatterResolveInputs();
      this.indirectScatterTemporalRenderer.renderAll();
      GL42.glMemoryBarrier(GL42.GL_FRAMEBUFFER_BARRIER_BIT | GL42.GL_TEXTURE_FETCH_BARRIER_BIT);
      return true;
   }

   private boolean shouldRunReservoirSplattingIndirectPipeline() {
      return PhotonicsStorage.DEBUG_ENABLE_INDIRECT_GI.value;
   }

   private boolean shouldRunIndirectBoilingFilter() {
      return this.shouldRunReservoirSplattingIndirectPipeline()
         && PhotonicsStorage.RESTIR_GI_BOILING_FILTER_STRENGTH.value > 0.0f;
   }

   private boolean shouldRunIndirectDenoise() {
      return this.shouldRunReservoirSplattingIndirectPipeline()
         && PhotonicsStorage.DEBUG_ENABLE_INDIRECT_DENOISE.value;
   }

   private boolean shouldRunIndirectTemporalSplatting(boolean resetReservoirSplatting) {
      return this.shouldRunReservoirSplattingIndirectPipeline()
         && PhotonicsStorage.RESTIR_GI_TEMPORAL_REUSE.value
         && !resetReservoirSplatting
         && this.renderFrameIndex > 1;
   }

   private void clearDisabledIndirectOutputs() {
      if (this.disabledIndirectOutputsCleared) {
         return;
      }

      Vector4f clearColor = new Vector4f(0.0f, 0.0f, 0.0f, 0.0f);
      this.indirectInitialReservoirBuffer.clearBothSides(clearColor);
      this.indirectReservoirBuffer.clearBothSides(clearColor);
      this.indirectDenoisedBuffer.clearBothSides(clearColor);
      this.disabledIndirectOutputsCleared = true;
   }

   // Dispatches SMEM pass (iteration index 0) then 4 regular A-trous passes (1-4).
   // directAtrousIteration is used by ping-pong routing helpers and step-size uniforms.
   private void renderNrdAtrousProfiled() {
      if (!this.isDirectAtrousEnabled()) {
         return;
      }
      // SMEM pass: iteration index 0 (strides[0] == 1)
      this.directAtrousIteration = 0;
      long smemStart = System.nanoTime();
      this.renderProfiled(relaxAtrousSmemRegionIndex, this.nrdAtrousSmemRenderer);
      this.lastCpuDirectAtrousIterationNanos[0] = System.nanoTime() - smemStart;
      // Regular A-trous passes: iterations 1-4
      if (this.directAtrousRenderer != null) {
         this.beginGpuRegion(relaxAtrousRegionIndex);
         for (this.directAtrousIteration = 1; this.directAtrousIteration < NRD_ATROUS_STRIDES.length; this.directAtrousIteration++) {
            long iterationStart = System.nanoTime();
            this.directAtrousRenderer.renderAll();
            this.lastCpuDirectAtrousIterationNanos[this.directAtrousIteration] = System.nanoTime() - iterationStart;
         }
         this.endGpuRegion(relaxAtrousRegionIndex);
      }
   }

   private void renderShadeSamplesProfiled() {
      this.setCurrentDiReconnectionSource(this.getShadingInputReconnectionSource());
      if (this.shadeSamplesRenderer == null || this.shadeSamplesReservoirRenderer == null) {
         return;
      }
      this.beginGpuRegion(diShadeSamplesRegionIndex);
      if (this.isDirectShadeSamplesEnabled()) {
         this.promoteShadingReconnectionHistory();
         // Lighting first (full-res FBO), then reservoir promotion (half-res FBO when
         // checkerboard is on). Order matters because the reservoir pass reads the
         // post-spatial reservoir that was finalized within the same frame.
         this.shadeSamplesRenderer.renderAll();
         this.shadeSamplesReservoirRenderer.renderAll();
      } else {
         this.clearShadeSamplesSplitOutputs();
         this.clearFrameFinalReconnectionOutputs();
      }
      this.endGpuRegion(diShadeSamplesRegionIndex);
   }

   private void promoteShadingReconnectionHistory() {
      if (this.getShadingInputReconnectionSource() == DiReconnectionSource.FINAL) {
         return;
      }
      if (this.shadeSamplesReconnectionRenderer == null) {
         return;
      }

      this.shadeSamplesReconnectionRenderer.renderAll();
      GL42.glMemoryBarrier(GL42.GL_FRAMEBUFFER_BARRIER_BIT | GL42.GL_TEXTURE_FETCH_BARRIER_BIT);
   }

   private void clearFrameFinalReconnectionOutputs() {
      this.scatterReconnectionBuffer.clear(new Vector4f(0.0f, 0.0f, 0.0f, 0.0f));
   }

   private void setCurrentDiReconnectionSource(DiReconnectionSource source) {
      this.currentDiReconnectionSource = source;
   }

   private TextureObject getCurrentStageReconnectionAttachment(String name) {
      if (this.currentDiReconnectionSource == DiReconnectionSource.PROPOSAL) {
         return this.proposalReconnectionBuffer.getWriteAttachment(name);
      }
      if (this.currentDiReconnectionSource == DiReconnectionSource.TEMPORAL) {
         return this.temporalReconnectionBuffer.getWriteAttachment(name);
      }
      return this.scatterReconnectionBuffer.getWriteAttachment(name);
   }

   private void beginGpuRegion(int regionIndex) {
      this.gpuTimerQuery.begin(regionIndex);
   }

   private void endGpuRegion(int regionIndex) {
      this.gpuTimerQuery.end(regionIndex);
   }

   private void destroyGpuTimerQuery() {
      this.gpuTimerQuery.destroy();
   }

   // After the 5-pass cascade the final result is always in nrdOutXxxRadianceHitDistFb
   // (the last regular atrous pass writes there regardless of ping-pong parity).
   private TextureObject getResolvedDiffuseAtrousTexture() {
      return this.nrdOutDiffRadianceHitDistFb.getWriteAttachment("data");
   }

   private TextureObject getResolvedSpecularAtrousTexture() {
      return this.nrdOutSpecRadianceHitDistFb.getWriteAttachment("data");
   }

   @Nullable
   private TextureObject getDebugDirectStageTexture() {
      String normalized = PhotonicsStorage.normalizeDirectStageView(PhotonicsStorage.DEBUG_DIRECT_STAGE_VIEW.value);

      return switch (normalized) {
         case "final" -> this.lightingBuffer.getWriteAttachment("direct");
         case "lighting_direct", "lighting_buffer_direct", "direct_buffer" -> this.lightingBuffer.getWriteAttachment("direct");
         case "lighting", "stage_lighting", "lighting_buffer_lighting" -> this.lightingBuffer.getWriteAttachment("lighting");
         case "stage_direct", "direct_raw", "raw" -> this.lightingStageBuffer.getWriteAttachment("direct_combined");
         case "stage_diffuse", "direct_diffuse", "nrd_in_diff" -> this.lightingStageBuffer.getWriteAttachment("direct");
         case "stage_specular", "spec_raw", "direct_specular" -> this.lightingStageBuffer.getWriteAttachment("direct_specular");
         case "stage_indirect", "indirect_raw" -> this.lightingStageBuffer.getWriteAttachment("indirect");
         // NRD fused pipeline intermediate buffers
         case "direct_noisy", "noisy", "temporal", "temporal_raw" -> this.nrdDiffIllumPingFb.getWriteAttachment("data");
         case "direct_responsive", "responsive" -> this.nrdDiffIllumPongFb.getWriteAttachment("data");
         case "direct_slow", "slow" -> this.nrdDiffIllumPingFb.getWriteAttachment("data");
         case "direct_fast", "fast" -> this.nrdDiffIllumPongFb.getWriteAttachment("data");
         case "direct_historyfix", "historyfix" -> this.nrdDiffIllumPongFb.getWriteAttachment("data");
         case "direct_anti_firefly", "anti_firefly" -> this.nrdDiffIllumPrevFb.getWriteAttachment("data");
         case "direct_clamped_slow", "clamped_slow" -> this.nrdDiffIllumPrevFb.getWriteAttachment("data");
         case "direct_clamped_fast", "clamped_fast" -> this.nrdDiffIllumResponsivePrevFb.getWriteAttachment("data");
         case "direct_denoised", "denoised" -> this.nrdOutDiffRadianceHitDistFb.getWriteAttachment("data");
         case "direct_atrous", "atrous" -> this.getResolvedDiffuseAtrousTexture();
         default -> null;
      };
   }

   private TextureObject getResolvedDirectDiffuseTexture() {
      if (!this.isDirectAtrousEnabled()) {
         // When atrous is disabled the anti-firefly output is the final diffuse result.
         return this.nrdDiffIllumPrevFb.getWriteAttachment("data");
      }
      return this.getResolvedDiffuseAtrousTexture();
   }

   private TextureObject getResolvedDirectTexture() {
      TextureObject debugStageTexture = this.getDebugDirectStageTexture();
      if (debugStageTexture != null) {
         return debugStageTexture;
      }
      return this.lightingBuffer.getWriteAttachment("direct");
   }

   private TextureObject getPreviousResolvedDirectTexture() {
      return this.lightingBuffer.getReadAttachment("direct");
   }

   private TextureObject getResolvedIndirectTexture() {
      if (!this.shouldRunIndirectDenoise()) {
         return this.lightingBuffer.getWriteAttachment("indirect");
      }
      return this.indirectDenoisedBuffer.getWriteAttachment("data");
   }

   private TextureObject getCurrentDirectReservoirDataTexture() {
      return this.directReservoirBuffer.getWriteAttachment("data");
   }

   private TextureObject getCurrentDirectReservoirSampleTexture() {
      return this.directReservoirBuffer.getWriteAttachment("sample");
   }

   private TextureObject getCurrentDirectReservoirMetaTexture() {
      return this.directReservoirBuffer.getWriteAttachment("meta");
   }

   private TextureObject getCurrentSpatialReservoirDataTexture() {
      if (!this.isDirectSpatialReuseEnabled()) {
         return this.temporalReservoirBuffer.getWriteAttachment("data");
      }
      return this.directSpatialReservoirBuffer.getWriteAttachment("data");
   }

   private TextureObject getCurrentSpatialReservoirSampleTexture() {
      if (!this.isDirectSpatialReuseEnabled()) {
         return this.temporalReservoirBuffer.getWriteAttachment("sample");
      }
      return this.directSpatialReservoirBuffer.getWriteAttachment("sample");
   }

   private TextureObject getCurrentSpatialReservoirMetaTexture() {
      if (!this.isDirectSpatialReuseEnabled()) {
         return this.temporalReservoirBuffer.getWriteAttachment("meta");
      }
      return this.directSpatialReservoirBuffer.getWriteAttachment("meta");
   }

   private TextureObject getCurrentIndirectReservoirPositionTexture() {
      if (this.shouldReadCurrentIndirectReservoirHistory()) {
         return this.indirectReservoirBuffer.getReadAttachment("position");
      }
      return this.indirectReservoirBuffer.getWriteAttachment("position");
   }

   private TextureObject getCurrentIndirectReservoirNormalTexture() {
      if (this.shouldReadCurrentIndirectReservoirHistory()) {
         return this.indirectReservoirBuffer.getReadAttachment("normal");
      }
      return this.indirectReservoirBuffer.getWriteAttachment("normal");
   }

   private TextureObject getCurrentIndirectReservoirRadianceTexture() {
      if (this.shouldReadCurrentIndirectReservoirHistory()) {
         return this.indirectReservoirBuffer.getReadAttachment("radiance");
      }
      return this.indirectReservoirBuffer.getWriteAttachment("radiance");
   }

   private TextureObject getCurrentIndirectReservoirMetaTexture() {
      if (this.shouldReadCurrentIndirectReservoirHistory()) {
         return this.indirectReservoirBuffer.getReadAttachment("meta");
      }
      return this.indirectReservoirBuffer.getWriteAttachment("meta");
   }

   private boolean shouldReadCurrentIndirectReservoirHistory() {
      return this.isCurrentPhotonicsFragment(indirectAccumulationFragment)
         || this.isCurrentPhotonicsFragment(indirectScatterTemporalFragment);
   }

   private TextureObject getCompatDirectSoftTexture() {
      return this.compatDirectSoftBuffer.getWriteAttachment("direct_soft_compat");
   }

   private TextureObject getPreviousCompatDirectSoftTexture() {
      return this.compatDirectSoftBuffer.getReadAttachment("direct_soft_compat");
   }

   private void recalculateRenderer(@Nullable CompositeRenderer renderer) {
      if (renderer != null) {
         renderer.recalculateSizes();
      }
   }

   private void destroyRenderer(@Nullable CompositeRenderer renderer) {
      if (renderer != null) {
         renderer.destroy();
      }
   }

   private boolean isDirectProposalReservoirEnabled() {
      return PhotonicsStorage.DEBUG_ENABLE_DIRECT_PROPOSAL_RESERVOIR.value;
   }

   private boolean isDirectShadeSamplesEnabled() {
      return PhotonicsStorage.DEBUG_ENABLE_DIRECT_SHADE_SAMPLES.value;
   }

   private boolean isDirectAtrousEnabled() {
      return PhotonicsStorage.DEBUG_ENABLE_DIRECT_ATROUS.value;
   }

   private void clearProposalReservoirOutputs() {
      this.proposalReservoirFramebuffer.clear(new Vector4f(0.0f, 0.0f, 0.0f, 0.0f));
   }

   private void clearShadeSamplesMonolithicOutputs() {
      this.shadeSamplesMonolithicFramebuffer.clear(new Vector4f(0.0f, 0.0f, 0.0f, 0.0f));
   }

   private void clearShadeSamplesLightingOutputs() {
      this.shadeSamplesFramebuffer.clear(new Vector4f(0.0f, 0.0f, 0.0f, 0.0f));
   }

   private void clearShadeSamplesSplitOutputs() {
      Vector4f clearColor = new Vector4f(0.0f, 0.0f, 0.0f, 0.0f);
      this.shadeSamplesFramebuffer.clear(clearColor);
      this.shadeSamplesReservoirFramebuffer.clear(clearColor);
   }

   private void invalidateDirectReuseHistory() {
      this.compatDirectSoftDirty = true;
      this.invalidateReservoirHistory();
   }

   private void invalidateReservoirHistory() {
      this.reservoirHistoryDirty = true;
   }

   private void ensureCompatDirectSoftCleared() {
      if (!this.compatDirectSoftDirty) {
         return;
      }
      this.clearCompatDirectSoftAttachments();
      this.compatDirectSoftDirty = false;
   }

   private boolean ensureReservoirHistoryCleared() {
      if (!this.reservoirHistoryDirty) {
         return false;
      }

      // RTXDI assumes reservoir histories start from EmptyReservoir on a reset.
      // Our ping-pong GL textures are not zero-initialized on both sides, so
      // explicit clears are required before reuse can safely read age/visibility.
      Vector4f clearColor = new Vector4f(0.0f, 0.0f, 0.0f, 0.0f);
      this.directReservoirBuffer.clearBothSides(clearColor);
      this.directSpatialReservoirBuffer.clear(clearColor);
      this.clearCurrentTemporalStageBuffers(clearColor);
      this.clearPreviousTemporalHistory(clearColor);
      this.indirectInitialReservoirBuffer.clearBothSides(clearColor);
      this.indirectReservoirBuffer.clearBothSides(clearColor);
      this.reservoirHistoryDirty = false;
      return true;
   }

   private void clearCompatDirectSoftAttachments() {
      Vector4f clearColor = new Vector4f(0.0f, 0.0f, 0.0f, 0.0f);
      this.compatDirectSoftBuffer.clear(clearColor);
      this.compatDirectSoftBuffer.swap();
      this.compatDirectSoftBuffer.clear(clearColor);
   }

   // Timestamps t0..t19 correspond to the 19 NRD pipeline segments (contract §1):
   // [0] LightTreeSamplingStage [1] InitialCandidates [2] DITemporalResampling
   // [3] DISpatialResampling [4] DIShadeSamples [5] NRDClassifyTiles
   // [6] NRDHitDistReconstruction [7] NRDPrepass [8] RELAXTemporalAccumulation
   // [9] RELAXHistoryFix [10] RELAXHistoryClamping [11] NRDCopy
   // [12] RELAXAntiFirefly [13] RELAXAtrousSmem+Atrous (fused) [14] ReSTIRGI
   // [15] LightingAccumulation [16] IndirectDenoise [17] IndirectComposite
   // render() uses t0..t20 but t16==t15 (no separate Atrous segment in timestamps).
   private void recordCpuPassTimes(long t0, long t1, long t2, long t3, long t4, long t5,
                                    long t6, long t7, long t8, long t9, long t10, long t11,
                                    long t12, long t13, long t14, long t15, long t17, long t18,
                                    long t19, long t20) {
      this.lastCpuLightTreeSamplingStageNanos = t1 - t0;
      this.lastCpuInitialCandidatesNanos = t2 - t1;
      this.lastCpuDITemporalResamplingNanos = t3 - t2;
      this.lastCpuDISpatialResamplingNanos = t4 - t3;
      this.lastCpuDIShadeSamplesNanos = t5 - t4;
      this.lastCpuNRDClassifyTilesNanos = t6 - t5;
      this.lastCpuNRDHitDistReconstructionNanos = t7 - t6;
      this.lastCpuNRDPrepassNanos = t8 - t7;
      this.lastCpuRELAXTemporalAccumulationNanos = t9 - t8;
      this.lastCpuRELAXHistoryFixNanos = t10 - t9;
      this.lastCpuRELAXHistoryClampingNanos = t11 - t10;
      this.lastCpuNRDCopyNanos = t12 - t11;
      this.lastCpuRELAXAntiFireflyNanos = t13 - t12;
      this.lastCpuRELAXAtrousSmemNanos = t14 - t13;
      this.lastCpuRELAXAtrousNanos = t15 - t14;
      this.lastCpuReSTIRGINanos = t17 - t15;
      this.lastCpuLightingAccumulationNanos = t18 - t17;
      this.lastCpuIndirectDenoiseNanos = t19 - t18;
      this.lastCpuIndirectCompositeNanos = t20 - t19;
      // Confidence cascade CPU time is absorbed into TA (t10-t9) as it runs inline.
      // GPU time is accurately tracked via nrdConfidenceCascadeRegionIndex GPU timer query.
      this.lastCpuNRDConfidenceCascadeNanos = 0;
   }

   private void logRenderProfileIfNeeded(long totalCpuNanos) {
      this.profilerFrameCounter++;
      if (this.profilerFrameCounter < profilerLogIntervalFrames) {
         return;
      }
      this.profilerFrameCounter = 0;
      long[] cpuPassNanos = this.getCpuPassNanos();
      long[] gpuPassNanos = this.getGpuPassNanos();
      int worstCpuIndex = this.getWorstPassIndex(cpuPassNanos);
      int worstGpuIndex = this.getWorstPassIndex(gpuPassNanos);
      WorldRegistry worldRegistry = this.worldRegistry;
      LightRegistry lightRegistry = worldRegistry.getLightRegistry();
      long totalGpuNanos = this.sumNanos(gpuPassNanos);
      int fbWidth = MinecraftClient.getInstance().getWindow().getFramebufferWidth();
      int fbHeight = MinecraftClient.getInstance().getWindow().getFramebufferHeight();
      int renderWidth = Math.round(fbWidth * this.renderScale);
      int renderHeight = Math.round(fbHeight * this.renderScale);
      long renderPixels = (long) renderWidth * renderHeight;
      Photonic.info(
         "[Profiler] RTXDI/NRD summary: cpuTotal={}us gpuTotal={}us worstCpu={}={}us worstGpu={}={}us reloadActive={} blendFactor={} blendRegions={} tracedLights={}/{} regirCells={} regirLightSlots={} regirGrid={}^3 viewport={}x{} renderRes={}x{} pixels={} lightTreeSamplingStageNsPerPixel={} stageGeometry={}",
         this.toMicros(totalCpuNanos),
         this.toMicros(totalGpuNanos),
         profilerPassNames[worstCpuIndex],
         this.toMicros(cpuPassNanos[worstCpuIndex]),
         profilerPassNames[worstGpuIndex],
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
      this.logGpuRenderProfile(gpuPassNanos);
   }

   private void logGpuRenderProfile(long[] gpuPassNanos) {
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
      LightRegistry lightRegistry = this.worldRegistry.getLightRegistry();
      int fbWidth = MinecraftClient.getInstance().getWindow().getFramebufferWidth();
      int fbHeight = MinecraftClient.getInstance().getWindow().getFramebufferHeight();
      int renderWidth = Math.round(fbWidth * this.renderScale);
      int renderHeight = Math.round(fbHeight * this.renderScale);
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
      this.logDirectAtrousBreakdown();
   }

   private void logDirectAtrousBreakdown() {
      if (this.lastCpuDirectAtrousIterationNanos.length == 0) {
         return;
      }
      StringBuilder passSummary = new StringBuilder();
      long worstNanos = 0L;
      int worstPass = 0;
      for (int i = 0; i < this.lastCpuDirectAtrousIterationNanos.length; i++) {
         long iterationNanos = this.lastCpuDirectAtrousIterationNanos[i];
         if (i > 0) {
            passSummary.append(' ');
         }
         passSummary.append("pass")
            .append(i)
            .append("(step=")
            .append(NRD_ATROUS_STRIDES[i])
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
         NRD_ATROUS_STRIDES[worstPass],
         this.toMicros(worstNanos)
      );
   }

   private long[] getCpuPassNanos() {
      return new long[]{
         this.lastCpuLightTreeSamplingStageNanos,       // index 0
         this.lastCpuInitialCandidatesNanos,            // index 1
         this.lastCpuDITemporalResamplingNanos,         // index 2
         this.lastCpuDISpatialResamplingNanos,          // index 3
         this.lastCpuDIShadeSamplesNanos,               // index 4
         this.lastCpuNRDClassifyTilesNanos,             // index 5
         this.lastCpuNRDHitDistReconstructionNanos,     // index 6
         this.lastCpuNRDPrepassNanos,                   // index 7
         this.lastCpuRELAXTemporalAccumulationNanos,    // index 8
         this.lastCpuRELAXHistoryFixNanos,              // index 9
         this.lastCpuRELAXHistoryClampingNanos,         // index 10
         this.lastCpuNRDCopyNanos,                      // index 11
         this.lastCpuRELAXAntiFireflyNanos,             // index 12
         this.lastCpuRELAXAtrousSmemNanos,              // index 13
         this.lastCpuRELAXAtrousNanos,                  // index 14
         this.lastCpuReSTIRGINanos,                     // index 15
         this.lastCpuIndirectDenoiseNanos,              // index 16
         this.lastCpuLightingAccumulationNanos,         // index 17
         this.lastCpuIndirectCompositeNanos,            // index 18
         this.lastCpuNRDConfidenceCascadeNanos          // index 19
      };
   }

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

   private void advanceGpuProfileFrame() {
      this.gpuTimerQuery.nextFrame();
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




