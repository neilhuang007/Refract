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
   private static final String relaxDiffuseTemporalAccumulationFragment = "lighttree/nrd_temporal_accumulation.fsh";
   private static final String relaxDiffuseHistoryFixFragment = "lighttree/nrd_history_fix.fsh";
   private static final String relaxDiffuseAntiFireflyFragment = "lighttree/nrd_anti_firefly.fsh";
   private static final String relaxDiffuseAtrousFragment = "lighttree/nrd_atrous.fsh";
   private static final String relaxDiffuseHistoryClampingFragment = "lighttree/nrd_history_clamping.fsh";
   private static final String relaxSpecularTemporalAccumulationFragment = "lighttree/nrd_spec_temporal_accumulation.fsh";
   private static final String relaxSpecularHistoryFixFragment = "lighttree/nrd_spec_history_fix.fsh";
   private static final String relaxSpecularAntiFireflyFragment = "lighttree/nrd_spec_anti_firefly.fsh";
   private static final String relaxSpecularAtrousFragment = "lighttree/nrd_spec_atrous.fsh";
   private static final String relaxSpecularHistoryClampingFragment = "lighttree/nrd_spec_history_clamping.fsh";
   private static final String indirectBoilingFragment = "lighttree/light_tree_indirect_boiling_filter.fsh";
   private static final String indirectAccumulationFragment = "lighttree/light_tree_indirect_accumulation.fsh";
   private static final String indirectInitialFragment = "lighttree/light_tree_indirect_initial.fsh";
   private static final String indirectDenoisingFragment = "lighttree/light_tree_indirect_denoising.fsh";
   private static final String diShadeSamplesFragment = "lighttree/LightingPasses/DI/ShadeSamples.fsh";
   private static final String diGenerateInitialSamplesFragment = "lighttree/LightingPasses/DI/GenerateInitialSamples.fsh";
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
   private static final String diScatterTemporalResamplingFragment = "lighttree/LightingPasses/DI/ScatterTemporalResolve.fsh";
   private static final int[] proposalReservoirDrawBuffers = new int[]{-1, -1, -1, -1, -1, 0, 1, 2};
   private static final int[] shadeSamplesLightingDrawBuffers = new int[]{0, 1, -1, -1, -1};
   private static final int[] shadeSamplesReservoirDrawBuffers = new int[]{-1, -1, 0, 1, 2};
   private static final int profilerLogIntervalFrames = 60;
   private static final String[] gpuProfilerRegionNames = new String[]{
      "LightTreeSamplingStage", "DIGenerateInitialSamples", "DITemporalResampling", "DISpatialResampling", "DIShadeSamples", "NRDPrepareInputs", "RELAXDiffuseTemporalAccumulation", "RELAXDiffuseHistoryFix", "RELAXDiffuseHistoryClamping", "RELAXDiffuseAntiFirefly", "RELAXDiffuseAtrous", "RELAXSpecularTemporalAccumulation", "RELAXSpecularHistoryFix", "RELAXSpecularHistoryClamping", "RELAXSpecularAntiFirefly", "RELAXSpecularAtrous", "ReSTIRGI", "IndirectDenoise", "LightingAccumulation", "IndirectComposite"
   };
   private static final String[] profilerPassNames = new String[]{
      "LightTreeSamplingStage", "DIGenerateInitialSamples", "DITemporalResampling", "DISpatialResampling", "DIShadeSamples", "NRDPrepareInputs", "RELAXDiffuseTemporalAccumulation", "RELAXDiffuseHistoryFix", "RELAXDiffuseHistoryClamping", "RELAXDiffuseAntiFirefly", "RELAXDiffuseAtrous", "RELAXSpecularTemporalAccumulation", "RELAXSpecularHistoryFix", "RELAXSpecularHistoryClamping", "RELAXSpecularAntiFirefly", "RELAXSpecularAtrous", "ReSTIRGI", "IndirectDenoise", "LightingAccumulation", "IndirectComposite"
   };
   private static final int lightTreeSamplingStageRegionIndex = 0;
   private static final int diGenerateInitialSamplesRegionIndex = 1;
   private static final int diTemporalResamplingRegionIndex = 2;
   private static final int diSpatialResamplingRegionIndex = 3;
   private static final int diShadeSamplesRegionIndex = 4;
   private static final int nrdPrepareInputsRegionIndex = 5;
   private static final int relaxDiffuseTemporalAccumulationRegionIndex = 6;
   private static final int relaxDiffuseHistoryFixRegionIndex = 7;
   private static final int relaxDiffuseHistoryClampingRegionIndex = 8;
   private static final int relaxDiffuseAntiFireflyRegionIndex = 9;
   private static final int relaxDiffuseAtrousRegionIndex = 10;
   private static final int relaxSpecularTemporalAccumulationRegionIndex = 11;
   private static final int relaxSpecularHistoryFixRegionIndex = 12;
   private static final int relaxSpecularHistoryClampingRegionIndex = 13;
   private static final int relaxSpecularAntiFireflyRegionIndex = 14;
  private static final int relaxSpecularAtrousRegionIndex = 15;
  private static final int restirGIRegionIndex = 16;
  private static final int indirectDenoiseRegionIndex = 17;
  private static final int lightingAccumulationRegionIndex = 18;
  private static final int indirectCompositeRegionIndex = 19;
  private boolean loggedRegirPresampleFrameSeedOverride = false;
  private boolean loggedRegirBuildFrameSeedOverride = false;

  private final PhotonicsProperties properties;
  private final ColorFramebuffer lightingBuffer;
  private final ColorFramebuffer lightingStageBuffer;
  private final ColorFramebuffer motionVectorBuffer;
  private final ColorFramebuffer directReservoirBuffer;
  private final ColorFramebuffer directSpatialReservoirBuffer;
  private final ColorFramebuffer directConfidenceBuffer;
  private final ColorFramebuffer directInitialDebugBuffer;
  private final ColorFramebuffer compatDirectSoftBuffer;
  private final ColorFramebuffer directHistoryLengthBuffer;
   private final ColorFramebuffer directNoisyBuffer;
   private final ColorFramebuffer directResponsiveBuffer;
   private final ColorFramebuffer directSlowBuffer;
   private final ColorFramebuffer directFastBuffer;
   private final ColorFramebuffer directAntiFireflyBuffer;
   private final ColorFramebuffer directClampedSlowBuffer;
   private final ColorFramebuffer directClampedFastBuffer;
   private final ColorFramebuffer directDenoisedBuffer;
   private final ColorFramebuffer directAtrousPingBuffer;
   private final ColorFramebuffer specularNoisyBuffer;
   private final ColorFramebuffer specularResponsiveBuffer;
   private final ColorFramebuffer specularSlowBuffer;
   private final ColorFramebuffer specularFastBuffer;
   private final ColorFramebuffer specularAntiFireflyBuffer;
   private final ColorFramebuffer specularClampedSlowBuffer;
   private final ColorFramebuffer specularClampedFastBuffer;
   private final ColorFramebuffer specularDenoisedBuffer;
   private final ColorFramebuffer specularAtrousPingBuffer;
   private final ColorFramebuffer specularHistoryLengthBuffer;
  private final ColorFramebuffer indirectInitialReservoirBuffer;
  private final ColorFramebuffer indirectReservoirBuffer;
  private final ColorFramebuffer indirectDenoisedBuffer;
  // -- Shared DI reconnection payload / temporal scatter history --
  // Persistent resources:
  //   * scatterReconnectionBuffer: shared current-stage + previous-frame reconnection payload
  //   * temporalReservoirBuffer: same-frame temporal DI output consumed by spatial reuse
  //   * temporalGatherBuffer: intermediate gather-side storage for CollectTemporalSamples / GatherTemporalResampling
  private final ColorFramebuffer scatterReconnectionBuffer;
  private final ColorFramebuffer temporalReservoirBuffer;
  private final ColorFramebuffer temporalGatherBuffer;
  private GlMemoryManager[] temporalScatterGlobalCountersMemoryManagers;
  private GlMemoryManager[] temporalScatterCellCountersMemoryManagers;

  private GlMemoryManager[] temporalScatterReservoirIndicesMemoryManagers;
  private GlMemoryManager[] temporalScatterScatteredReservoirsMemoryManagers;
  private GlMemoryManager[] temporalScatterScatteredWeightsMemoryManagers;
  private GlMemoryManager[] temporalScatterCellOffsetsMemoryManagers;
  private GlMemoryManager[] temporalScatterSortedReservoirsMemoryManagers;
  private GlMemoryManager[] temporalScatterSortedWeightsMemoryManagers;
  private final RoutingFramebuffer proposalFramebuffer;
  private final RoutingFramebuffer proposalReservoirFramebuffer;
  private final RoutingFramebuffer reuseResolveFramebuffer;
  private final RoutingFramebuffer directFeatureFramebuffer;
  private final RoutingFramebuffer directTemporalFramebuffer;
  private final RoutingFramebuffer directAntiFireflyFramebuffer;
  private final RoutingFramebuffer directHistoryFixFramebuffer;
  private final RoutingFramebuffer directHistoryClampingFramebuffer;
  private final RoutingFramebuffer directAtrousFramebuffer;
  private final RoutingFramebuffer specTemporalFramebuffer;
  private final RoutingFramebuffer specAntiFireflyFramebuffer;
  private final RoutingFramebuffer specHistoryFixFramebuffer;
  private final RoutingFramebuffer specHistoryClampingFramebuffer;
  private final RoutingFramebuffer specAtrousFramebuffer;
  private final RoutingFramebuffer indirectInitialFramebuffer;
  private final RoutingFramebuffer indirectBoilingFramebuffer;
  private final RoutingFramebuffer indirectAccumulationFramebuffer;
  private final RoutingFramebuffer indirectDenoisingFramebuffer;
  private final RoutingFramebuffer positionWriteFramebuffer;
  private final RoutingFramebuffer shadeSamplesMonolithicFramebuffer;
  private final RoutingFramebuffer shadeSamplesFramebuffer;
  private final RoutingFramebuffer shadeSamplesReservoirFramebuffer;
  private final RoutingFramebuffer temporalScatterStageFramebuffer;
  private final RoutingFramebuffer temporalReservoirFramebuffer;
  @Nullable
  private CompositeRenderer proposalStageRenderer;
  @Nullable
  private CompositeRenderer proposalReservoirRenderer;
  @Nullable
  private CompositeRenderer reuseResolveRenderer;
  @Nullable
  private CompositeRenderer directFeatureRenderer;
  @Nullable
  private CompositeRenderer directTemporalRenderer;
  @Nullable
  private CompositeRenderer directAntiFireflyRenderer;
  @Nullable
  private CompositeRenderer directHistoryFixRenderer;
  @Nullable
  private CompositeRenderer directHistoryClampingRenderer;
  @Nullable
  private CompositeRenderer directAtrousRenderer;
  @Nullable
  private CompositeRenderer specTemporalRenderer;
  @Nullable
  private CompositeRenderer specAntiFireflyRenderer;
  @Nullable
  private CompositeRenderer specHistoryFixRenderer;
  @Nullable
  private CompositeRenderer specHistoryClampingRenderer;
  @Nullable
  private CompositeRenderer specAtrousRenderer;
  @Nullable
  private CompositeRenderer indirectInitialRenderer;
  @Nullable
  private CompositeRenderer indirectBoilingRenderer;
  @Nullable
  private CompositeRenderer indirectAccumulationRenderer;
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
  private final int[] directAtrousStepSizes;
  private final Consumer<String> localLightSamplingModeObserver;
  private final Consumer<String> temporalScatterIsolationModeObserver;
   private static final int RESERVOIR_SPLATTING_TIME_PARTITION_COUNT = 4;
   private int temporalScatterPixelCapacity;
  private int temporalScatterContributorCapacity;
  private int directAtrousIteration = 0;
  private int specAtrousIteration = 0;
  private boolean compatDirectSoftDirty = true;
  private boolean reservoirHistoryDirty = true;
  private int renderFrameIndex = 0;
  private int profilerFrameCounter = 0;
  private long lastCpuLightTreeSamplingStageNanos;
  private long lastCpuDIGenerateInitialSamplesNanos;
  private long lastCpuDITemporalResamplingNanos;
  private long lastCpuDISpatialResamplingNanos;
  private long lastCpuDIShadeSamplesNanos;
  private long lastCpuNRDPrepareInputsNanos;
  private long lastCpuRELAXDiffuseTemporalAccumulationNanos;
  private long lastCpuRELAXDiffuseHistoryFixNanos;
  private long lastCpuRELAXDiffuseHistoryClampingNanos;
  private long lastCpuRELAXDiffuseAntiFireflyNanos;
  private long lastCpuRELAXDiffuseAtrousNanos;
  private long[] lastCpuDirectAtrousIterationNanos;
  private long lastCpuRELAXSpecularTemporalAccumulationNanos;
  private long lastCpuRELAXSpecularHistoryFixNanos;
  private long lastCpuRELAXSpecularHistoryClampingNanos;
  private float[] cachedRegirPdfPowers;
  private int cachedRegirPdfLightCount = -1;
  private long cachedRegirSemanticLayoutHash = Long.MIN_VALUE;
  private long lastCpuRELAXSpecularAntiFireflyNanos;
  private long lastCpuRELAXSpecularAtrousNanos;
  private long lastCpuReSTIRGINanos;
  private long lastCpuIndirectDenoiseNanos;
  private long lastCpuLightingAccumulationNanos;
  private long lastCpuIndirectCompositeNanos;
   public LightTreeRenderer(WorldRegistry worldRegistry, float renderScale, PhotonicsProperties properties) {
      super(worldRegistry, renderScale);
      this.properties = properties;
      this.directAtrousStepSizes = resolveDirectAtrousStepSizes(properties);
      this.lastCpuDirectAtrousIterationNanos = new long[this.directAtrousStepSizes.length];
      this.lightingBuffer = new ColorFramebuffer(renderScale);
      this.createLightingBufferAttachments(this.lightingBuffer);
      this.lightingStageBuffer = new ColorFramebuffer(renderScale);
      this.createLightingStageAttachments(this.lightingStageBuffer);
      this.motionVectorBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directReservoirBuffer = this.createDirectReservoirFramebuffer(renderScale);
      this.directSpatialReservoirBuffer = this.createDirectReservoirFramebuffer(renderScale);
      this.scatterReconnectionBuffer = this.createScatterReconnectionFramebuffer(renderScale);
      this.temporalReservoirBuffer = this.createTemporalReservoirFramebuffer(renderScale);
      this.temporalGatherBuffer = this.createTemporalGatherFramebuffer(renderScale);
      this.temporalScatterPixelCapacity = this.getTemporalScatterPixelCapacity();
      this.temporalScatterContributorCapacity = this.getTemporalScatterContributorCapacity();
      this.allocateTemporalScatterMemoryManagers();
      this.directConfidenceBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directInitialDebugBuffer = this.createDirectPackedDebugFramebuffer(renderScale);
      this.compatDirectSoftBuffer = new ColorFramebuffer(renderScale);
      this.compatDirectSoftBuffer.createAttachment("direct_soft_compat", "RGBA16F", false);
      this.directHistoryLengthBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directNoisyBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directResponsiveBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directSlowBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directFastBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directAntiFireflyBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directClampedSlowBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directClampedFastBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directDenoisedBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directAtrousPingBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularNoisyBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularResponsiveBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularSlowBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularFastBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularAntiFireflyBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularClampedSlowBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularClampedFastBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularDenoisedBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularAtrousPingBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.specularHistoryLengthBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.indirectInitialReservoirBuffer = this.createIndirectReservoirFramebuffer(renderScale);
      this.indirectReservoirBuffer = this.createIndirectReservoirFramebuffer(renderScale);
      this.indirectDenoisedBuffer = new ColorFramebuffer(renderScale);
      this.indirectDenoisedBuffer.createAttachment("data", "RGBA16F", false);
      this.proposalFramebuffer = this.createProposalGeometryFramebuffer();
      this.proposalReservoirFramebuffer = this.createProposalReservoirFramebuffer();
      this.reuseResolveFramebuffer = this.createReuseResolveFramebuffer();
      this.directFeatureFramebuffer = this.createDirectFeatureFramebuffer();
      this.directTemporalFramebuffer = this.createDirectTemporalFramebuffer();
      this.directAntiFireflyFramebuffer = this.createDirectAntiFireflyFramebuffer();
      this.directHistoryFixFramebuffer = this.createDirectHistoryFixFramebuffer();
      this.directHistoryClampingFramebuffer = this.createDirectHistoryClampingFramebuffer();
      this.directAtrousFramebuffer = this.createDirectAtrousFramebuffer();
      this.specTemporalFramebuffer = this.createSpecTemporalFramebuffer();
      this.specAntiFireflyFramebuffer = this.createSpecAntiFireflyFramebuffer();
      this.specHistoryFixFramebuffer = this.createSpecHistoryFixFramebuffer();
      this.specHistoryClampingFramebuffer = this.createSpecHistoryClampingFramebuffer();
      this.specAtrousFramebuffer = this.createSpecAtrousFramebuffer();
      this.indirectInitialFramebuffer = this.createIndirectInitialFramebuffer();
      this.indirectBoilingFramebuffer = this.createIndirectBoilingFramebuffer();
      this.indirectAccumulationFramebuffer = this.createIndirectAccumulationFramebuffer();
      this.indirectDenoisingFramebuffer = this.createIndirectDenoisingFramebuffer();
      this.positionWriteFramebuffer = this.createPositionWriteFramebuffer();
      this.shadeSamplesMonolithicFramebuffer = this.createShadeSamplesMonolithicFramebuffer();
      this.shadeSamplesFramebuffer = this.createShadeSamplesLightingFramebuffer();
      this.shadeSamplesReservoirFramebuffer = this.createShadeSamplesReservoirFramebuffer();
      this.temporalScatterStageFramebuffer = this.createTemporalScatterStageFramebuffer();
      this.temporalReservoirFramebuffer = this.createTemporalReservoirRoutingFramebuffer();
      this.gpuTimerQuery = this.createGpuTimerQuery();
      this.regirComputeProgram = new RegirComputeProgram();
      this.localLightSamplingModeObserver = ignored -> this.invalidateDirectReuseHistory();
      this.temporalScatterIsolationModeObserver = ignored -> this.invalidateDirectReuseHistory();
      PhotonicsStorage.RESTIR_LOCAL_LIGHT_SAMPLING_MODE.addObserver(this.localLightSamplingModeObserver);
      PhotonicsStorage.RESTIR_TEMPORAL_SCATTER_ISOLATION_MODE.addObserver(this.temporalScatterIsolationModeObserver);
   }

   @Override
   protected GLMemoryCollection buildGlMemoryCollection() {
      GLMemoryCollection memoryCollection = super.buildGlMemoryCollection();
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getGlobalLightCdfMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getRegirCellCountMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getRegirLightIndexMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getRegirLightPdfMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getRegirCompactLightDataMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getLightReverseMappingMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getPreviousLightsMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getNeighborOffsetMemoryManager());
      this.addTemporalScatterMemoryManagers(memoryCollection);
      return memoryCollection;
   }

   private void addTemporalScatterMemoryManagers(GLMemoryCollection memoryCollection) {
      this.addTemporalScatterMemoryManagers(memoryCollection, this.temporalScatterGlobalCountersMemoryManagers);
      this.addTemporalScatterMemoryManagers(memoryCollection, this.temporalScatterCellCountersMemoryManagers);
      this.addTemporalScatterMemoryManagers(memoryCollection, this.temporalScatterReservoirIndicesMemoryManagers);
      this.addTemporalScatterMemoryManagers(memoryCollection, this.temporalScatterScatteredReservoirsMemoryManagers);
      this.addTemporalScatterMemoryManagers(memoryCollection, this.temporalScatterScatteredWeightsMemoryManagers);
      this.addTemporalScatterMemoryManagers(memoryCollection, this.temporalScatterCellOffsetsMemoryManagers);
      this.addTemporalScatterMemoryManagers(memoryCollection, this.temporalScatterSortedReservoirsMemoryManagers);
      this.addTemporalScatterMemoryManagers(memoryCollection, this.temporalScatterSortedWeightsMemoryManagers);
   }

   private void addTemporalScatterMemoryManagers(GLMemoryCollection memoryCollection, GlMemoryManager[] managers) {
      if (managers == null) {
         return;
      }

      for (GlMemoryManager manager : managers) {
         memoryCollection.add(() -> manager);
      }
   }

   @Override
   public void createCompositeRenderer(Function<List<PhotonicsShader>, CompositeRenderer> rendererCreator) {
      this.proposalStageRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("lighttree/light_tree_sampling_stage.fsh", "common/screen.vsh", this.memoryCollection, this.proposalFramebuffer))
      );
      this.proposalReservoirRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diGenerateInitialSamplesFragment, "common/screen.vsh", this.memoryCollection, this.proposalReservoirFramebuffer))
      );
      this.reuseResolveRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diSpatialResamplingFragment, "common/screen.vsh", this.memoryCollection, this.reuseResolveFramebuffer))
      );
      this.temporalCollectRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diCollectTemporalSamplesFragment, "common/screen.vsh", this.memoryCollection, this.temporalGatherBuffer))
      );
      this.robustReuseOptimizationRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diRobustReuseOptimizationFragment, "common/screen.vsh", this.memoryCollection, this.temporalGatherBuffer))
      );
      this.temporalGatherRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diGatherTemporalResamplingFragment, "common/screen.vsh", this.memoryCollection, this.temporalReservoirFramebuffer))
      );
      this.temporalScatterReprojectionRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diTemporalReprojectionFragment, "common/screen.vsh", this.memoryCollection, this.temporalScatterStageFramebuffer))
      );
      this.temporalMultiScatterReprojectionRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diMultiTemporalReprojectionFragment, "common/screen.vsh", this.memoryCollection, this.temporalScatterStageFramebuffer))
      );
      this.temporalScatterBinningOffsetsRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diTemporalBinningOffsetsFragment, "common/screen.vsh", this.memoryCollection, this.temporalScatterStageFramebuffer))
      );
      this.temporalMultiScatterBinningOffsetsRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diMultiTemporalBinningOffsetsFragment, "common/screen.vsh", this.memoryCollection, this.temporalScatterStageFramebuffer))
      );
      this.temporalScatterBinningRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diTemporalBinningFragment, "common/screen.vsh", this.memoryCollection, this.temporalScatterStageFramebuffer))
      );
      this.temporalMultiScatterBinningRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diMultiTemporalBinningFragment, "common/screen.vsh", this.memoryCollection, this.temporalScatterStageFramebuffer))
      );
      this.scatterTemporalRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diScatterTemporalResamplingFragment, "common/screen.vsh", this.memoryCollection, this.temporalReservoirFramebuffer))
      );
      this.scatterBackupTemporalRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diScatterBackupTemporalResamplingFragment, "common/screen.vsh", this.memoryCollection, this.temporalReservoirFramebuffer))
      );
      this.multiScatterTemporalRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diMultiScatterTemporalResamplingFragment, "common/screen.vsh", this.memoryCollection, this.temporalReservoirFramebuffer))
      );
      this.directFeatureRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("lighttree/direct_feature_extract.fsh", "common/screen.vsh", this.memoryCollection, this.directFeatureFramebuffer))
      );
      this.directTemporalRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(relaxDiffuseTemporalAccumulationFragment, "common/screen.vsh", this.memoryCollection, this.directTemporalFramebuffer))
      );
      this.directAntiFireflyRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(relaxDiffuseAntiFireflyFragment, "common/screen.vsh", this.memoryCollection, this.directAntiFireflyFramebuffer))
      );
      this.directHistoryFixRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(relaxDiffuseHistoryFixFragment, "common/screen.vsh", this.memoryCollection, this.directHistoryFixFramebuffer))
      );
      this.directHistoryClampingRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(relaxDiffuseHistoryClampingFragment, "common/screen.vsh", this.memoryCollection, this.directHistoryClampingFramebuffer))
      );
      this.directAtrousRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(relaxDiffuseAtrousFragment, "common/screen.vsh", this.memoryCollection, this.directAtrousFramebuffer))
      );
      this.specTemporalRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(relaxSpecularTemporalAccumulationFragment, "common/screen.vsh", this.memoryCollection, this.specTemporalFramebuffer))
      );
      this.specAntiFireflyRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(relaxSpecularAntiFireflyFragment, "common/screen.vsh", this.memoryCollection, this.specAntiFireflyFramebuffer))
      );
      this.specHistoryFixRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(relaxSpecularHistoryFixFragment, "common/screen.vsh", this.memoryCollection, this.specHistoryFixFramebuffer))
      );
      this.specHistoryClampingRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(relaxSpecularHistoryClampingFragment, "common/screen.vsh", this.memoryCollection, this.specHistoryClampingFramebuffer))
      );
      this.specAtrousRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(relaxSpecularAtrousFragment, "common/screen.vsh", this.memoryCollection, this.specAtrousFramebuffer))
      );
      this.indirectInitialRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(indirectInitialFragment, "common/screen.vsh", this.memoryCollection, this.indirectInitialFramebuffer))
      );
      this.indirectBoilingRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(indirectBoilingFragment, "common/screen.vsh", this.memoryCollection, this.indirectBoilingFramebuffer))
      );
      this.indirectAccumulationRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(indirectAccumulationFragment, "common/screen.vsh", this.memoryCollection, this.indirectAccumulationFramebuffer))
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
      this.shadeSamplesMonolithicRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diShadeSamplesFragment, "common/screen.vsh", this.memoryCollection, this.shadeSamplesMonolithicFramebuffer))
      );
      this.shadeSamplesReservoirRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diShadeSamplesReservoirFragment, "common/screen.vsh", this.memoryCollection, this.shadeSamplesReservoirFramebuffer))
      );
      this.shadeSamplesRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(diShadeSamplesLightingFragment, "common/screen.vsh", this.memoryCollection, this.shadeSamplesFramebuffer))
      );
      this.compileRegirComputeShader();
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
      this.addTextureSampler(samplers, "radiosity_spatial_reservoirs", () -> this.directSpatialReservoirBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "radiosity_spatial_reservoir_samples", () -> this.directSpatialReservoirBuffer.getWriteAttachment("sample"));
      this.addTextureSampler(samplers, "radiosity_spatial_reservoir_meta", () -> this.directSpatialReservoirBuffer.getWriteAttachment("meta"));
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
      this.addTextureSampler(samplers, "diffuse_confidence_input", () -> this.directConfidenceBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "spec_confidence_input", () -> this.directConfidenceBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "spec_history_confidence_input", () -> this.specularResponsiveBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "spec_reprojection_confidence_input", () -> this.specularResponsiveBuffer.getWriteAttachment("data"));
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
      // Stage-input shadow copies expose the authoritative current-stage reconnection payload.
      // The historical sampler names remain for compatibility, but the read side is explicitly
      // split from the live write attachments so GenerateInitialSamples, ScatterTemporalResolve,
      // SpatialResampling, and the local final resolve all consume the copied stage input rather than
      // sampling an attachment that is simultaneously bound as a color target.
      this.addTextureSampler(samplers, "scatter_reconnection0", () -> this.scatterReconnectionBuffer.getWriteAttachment("stage_in_reconnection0"));
      this.addTextureSampler(samplers, "scatter_reconnection1", () -> this.scatterReconnectionBuffer.getWriteAttachment("stage_in_reconnection1"));
      this.addTextureSampler(samplers, "prev_scatter_reconnection0", () -> this.scatterReconnectionBuffer.getReadAttachment("reconnection0"));
      this.addTextureSampler(samplers, "prev_scatter_reconnection1", () -> this.scatterReconnectionBuffer.getReadAttachment("reconnection1"));
      // Scatter temporal resampling output: consumed by the current local spatial resampling stage
      this.addTextureSampler(samplers, "temporal_reservoir_data", () -> this.temporalReservoirBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "temporal_reservoir_sample", () -> this.temporalReservoirBuffer.getWriteAttachment("sample"));
      this.addTextureSampler(samplers, "temporal_reservoir_meta", () -> this.temporalReservoirBuffer.getWriteAttachment("meta"));
      this.addTextureSampler(samplers, "temporal_gather_floating_coords", () -> this.temporalGatherBuffer.getWriteAttachment("floating_coords"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reservoir_data", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_data"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reservoir_sample", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_sample"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reservoir_meta", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_meta"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reconnection0", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection0"));
      this.addTextureSampler(samplers, "temporal_gather_intermediate_reconnection1", () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection1"));
      this.addTextureSampler(samplers, "temporal_gather_shifted_path_data0", () -> this.temporalGatherBuffer.getWriteAttachment("shifted_path_data0"));
      this.addTextureSampler(samplers, "temporal_gather_shifted_path_data1", () -> this.temporalGatherBuffer.getWriteAttachment("shifted_path_data1"));
      this.addTextureSampler(samplers, "temporal_gather_shifted_path_data2", () -> this.temporalGatherBuffer.getWriteAttachment("shifted_path_data2"));
      this.addTextureSampler(samplers, "temporal_gather_shifted_path_data3", () -> this.temporalGatherBuffer.getWriteAttachment("shifted_path_data3"));
      this.addTextureSampler(samplers, "temporal_gather_shifted_path_data4", () -> this.temporalGatherBuffer.getWriteAttachment("shifted_path_data4"));
      this.addTextureSampler(samplers, "temporal_gather_shifted_path_data5", () -> this.temporalGatherBuffer.getWriteAttachment("shifted_path_data5"));
      this.addTextureSampler(samplers, "temporal_gather_shifted_path_data6", () -> this.temporalGatherBuffer.getWriteAttachment("shifted_path_data6"));
      this.addTextureSampler(samplers, "temporal_gather_shifted_path_data7", () -> this.temporalGatherBuffer.getWriteAttachment("shifted_path_data7"));
      this.addTextureSampler(samplers, "temporal_gather_shifted_path_data8", () -> this.temporalGatherBuffer.getWriteAttachment("shifted_path_data8"));
      this.addTextureSampler(samplers, "temporal_gather_shifted_path_data9", () -> this.temporalGatherBuffer.getWriteAttachment("shifted_path_data9"));
      this.addTextureSampler(samplers, "temporal_gather_shifted_path_data10", () -> this.temporalGatherBuffer.getWriteAttachment("shifted_path_data10"));
      this.addTextureSampler(samplers, "temporal_gather_shifted_path_data11", () -> this.temporalGatherBuffer.getWriteAttachment("shifted_path_data11"));
      this.addTextureSampler(samplers, "temporal_gather_shifted_path_data12", () -> this.temporalGatherBuffer.getWriteAttachment("shifted_path_data12"));
      this.addTextureSampler(samplers, "temporal_gather_shifted_path_data13", () -> this.temporalGatherBuffer.getWriteAttachment("shifted_path_data13"));
      this.addTextureSampler(samplers, "temporal_gather_shifted_path_data14", () -> this.temporalGatherBuffer.getWriteAttachment("shifted_path_data14"));
      this.addTextureSampler(samplers, "temporal_gather_shifted_path_data15", () -> this.temporalGatherBuffer.getWriteAttachment("shifted_path_data15"));
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
      this.addTextureSampler(samplers, "direct_noisy_input", () -> this.directNoisyBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_responsive_input", () -> this.directResponsiveBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_slow_input", () -> this.directSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_fast_input", () -> this.directFastBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_history_length_input", () -> this.directHistoryLengthBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "prev_direct_noisy_input", () -> this.directNoisyBuffer.getReadAttachment("data"));
      // RELAX temporal accumulation consumes the final slow / fast histories produced by
      // history clamping in the previous frame.
      this.addTextureSampler(samplers, "prev_direct_slow_input", () -> this.directAntiFireflyBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_direct_fast_input", () -> this.directClampedFastBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_direct_history_length_input", () -> this.directHistoryLengthBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "direct_firefly_input", () -> this.directClampedSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_historyfix_input", () -> this.directSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_historyfix_output", () -> this.directClampedSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_diff_slow_input", () -> this.directSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_diff_fast_input", () -> this.directFastBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_diff_noisy_input", () -> this.directNoisyBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_history_length_tex", () -> {
         if (this.shouldUseCurrentDirectHistoryLength()) {
            return this.directHistoryLengthBuffer.getWriteAttachment("data");
         }
         return this.directHistoryLengthBuffer.getReadAttachment("data");
      });
      this.addTextureSampler(samplers, "direct_history_length_tex", () -> {
         if (this.shouldUseCurrentDirectHistoryLength()) {
            return this.directHistoryLengthBuffer.getWriteAttachment("data");
         }
         return this.directHistoryLengthBuffer.getReadAttachment("data");
      });
      this.addTextureSampler(samplers, "direct_history_length_clamp_input", () -> this.directHistoryLengthBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_atrous_input", this::getCurrentDirectAtrousInputTexture);
      this.addTextureSampler(samplers, "spec_noisy_input", () -> this.specularNoisyBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "prev_spec_noisy_input", () -> this.specularNoisyBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "spec_slow_input", () -> this.specularSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "prev_spec_slow_input", () -> this.specularAntiFireflyBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "spec_fast_input", () -> this.specularFastBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "prev_spec_fast_input", () -> this.specularClampedFastBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "spec_history_length_input", () -> {
         if (this.shouldUseCurrentSpecHistoryLength()) {
            return this.specularHistoryLengthBuffer.getWriteAttachment("data");
         }
         return this.specularHistoryLengthBuffer.getReadAttachment("data");
      });
      this.addTextureSampler(samplers, "spec_history_length_clamp_input", () -> this.specularHistoryLengthBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "prev_spec_history_length_input", () -> this.specularHistoryLengthBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "spec_firefly_input", () -> this.specularClampedSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "spec_historyfix_input", () -> this.specularSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "spec_historyfix_output", () -> this.specularClampedSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "spec_clamped_slow_input", () -> this.specularClampedSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "spec_clamped_fast_input", () -> this.specularClampedFastBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "spec_atrous_input", this::getCurrentSpecAtrousInputTexture);
      this.addTextureSampler(samplers, "denoised_direct_diffuse", this::getResolvedDirectDiffuseTexture);
      this.addTextureSampler(samplers, "denoised_direct_specular", this::getResolvedSpecularAtrousTexture);
   }

   @Override
   public void registerCustomUniforms(DynamicUniformHolder uniforms) {
      uniforms.uniform1i("direct_atrous_step_size", this::getCurrentDirectAtrousStepSize, listener -> {});
      uniforms.uniform1i("direct_atrous_is_last_pass", this::getCurrentDirectAtrousIsLastPass, listener -> {});
      uniforms.uniform1i(UniformUpdateFrequency.PER_FRAME, "ph_restir_active_checkerboard_field", this::getActiveCheckerboardField);
      uniforms.uniform1i(UniformUpdateFrequency.PER_FRAME, "ph_restir_frame_index", this::getRestirFrameIndex);
      uniforms.uniform1i(UniformUpdateFrequency.PER_FRAME, "ph_reservoir_splatting_time_partition_count", () -> RESERVOIR_SPLATTING_TIME_PARTITION_COUNT);
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

         float override = PhotonicsStorage.RESTIR_INITIAL_SAMPLES.value;
         return override >= 0 ? override : (float) this.properties.getLightTreeInitialSamples();
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
            case "regir_ris" -> 2.0f;
            default -> 2.0f;
         };
      });
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
            String isolationMode = PhotonicsStorage.normalizeTemporalScatterIsolationMode(
               PhotonicsStorage.RESTIR_TEMPORAL_SCATTER_ISOLATION_MODE.value
            );
            return switch (isolationMode) {
               case "ownership_only" -> 1.0f;
               case "scatter_backup" -> 2.0f;
               case "scatter_only" -> 3.0f;
               case "multi_scatter" -> 4.0f;
               case "temporal_off" -> 5.0f;
               default -> 0.0f;
            };
         }
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_debug_enable_direct_temporal_reuse",
         () -> PhotonicsStorage.DEBUG_ENABLE_DIRECT_TEMPORAL_REUSE.value ? 1.0f : 0.0f
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
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_indirect_enable_final_mis", () -> 1.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_indirect_boiling_filter_strength", () -> 0.2f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_reuse_final_visibility", () -> 1.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_restir_enable_denoiser_packing", () -> 1.0f);
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_debug_enable_direct_temporal_accumulation",
         () -> PhotonicsStorage.DEBUG_ENABLE_DIRECT_TEMPORAL_ACCUMULATION.value ? 1.0f : 0.0f
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_debug_enable_direct_history_fix",
         () -> PhotonicsStorage.DEBUG_ENABLE_DIRECT_HISTORY_FIX.value ? 1.0f : 0.0f
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_debug_enable_direct_history_clamping",
         () -> PhotonicsStorage.DEBUG_ENABLE_DIRECT_HISTORY_CLAMPING.value ? 1.0f : 0.0f
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_debug_enable_direct_anti_firefly",
         () -> PhotonicsStorage.DEBUG_ENABLE_DIRECT_ANTI_FIREFLY.value ? 1.0f : 0.0f
      );
      uniforms.uniform1f(
         UniformUpdateFrequency.PER_FRAME,
         "ph_debug_view_mode",
         () -> PhotonicsStorage.DEBUG_VIEW_MODE.value
      );
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_max_accumulated_frame_num", () -> 30.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_max_fast_accumulated_frame_num", () -> 6.0f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_depth_threshold", () -> 0.003f);
      uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_nrd_denoising_range", () -> 500.0f);
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
      // Previous-frame reconnection data is double-buffered and becomes readable after the
      // frame-start swap. The temporal DI output is intentionally NOT swapped because it is a
      // same-frame producer/consumer resource between the current local scatter temporal stage
      // and spatial reuse.
      this.scatterReconnectionBuffer.swap();
   }

   private void updateScatterTemporalResourcesPerFrame() {
      this.ensureTemporalScatterMemoryCapacity();
      this.scatterReconnectionBuffer.updatePerFrame();
      this.temporalReservoirBuffer.updatePerFrame();
   }

   private void allocateTemporalScatterMemoryManagers() {
      this.temporalScatterGlobalCountersMemoryManagers = this.createTemporalScatterPartitionedMemoryManagers("ph_temporal_scatter_global_counters", () -> 2 * Integer.BYTES);
      this.temporalScatterCellCountersMemoryManagers = this.createTemporalScatterPartitionedMemoryManagers("ph_temporal_scatter_cell_counters", () -> this.temporalScatterPixelCapacity * Integer.BYTES);
      this.temporalScatterReservoirIndicesMemoryManagers = this.createTemporalScatterPartitionedMemoryManagers("ph_temporal_scatter_reservoir_indices", () -> this.temporalScatterPixelCapacity * 2 * Integer.BYTES);
      this.temporalScatterScatteredReservoirsMemoryManagers = this.createTemporalScatterPartitionedMemoryManagers("ph_temporal_scatter_scattered_reservoirs", () -> this.temporalScatterPixelCapacity * 2 * Integer.BYTES);
      this.temporalScatterScatteredWeightsMemoryManagers = this.createTemporalScatterPartitionedMemoryManagers("ph_temporal_scatter_scattered_weights", () -> this.temporalScatterPixelCapacity * Integer.BYTES);
      this.temporalScatterCellOffsetsMemoryManagers = this.createTemporalScatterPartitionedMemoryManagers("ph_temporal_scatter_cell_offsets", () -> this.temporalScatterPixelCapacity * Integer.BYTES);
      this.temporalScatterSortedReservoirsMemoryManagers = this.createTemporalScatterPartitionedMemoryManagers("ph_temporal_scatter_sorted_reservoirs", () -> this.temporalScatterPixelCapacity * 2 * Integer.BYTES);
      this.temporalScatterSortedWeightsMemoryManagers = this.createTemporalScatterPartitionedMemoryManagers("ph_temporal_scatter_sorted_weights", () -> this.temporalScatterPixelCapacity * Integer.BYTES);
   }

   private GlMemoryManager[] createTemporalScatterPartitionedMemoryManagers(String baseName, IntSupplier byteSizeSupplier) {
      GlMemoryManager[] managers = new GlMemoryManager[RESERVOIR_SPLATTING_TIME_PARTITION_COUNT];
      for (int partitionIndex = 0; partitionIndex < RESERVOIR_SPLATTING_TIME_PARTITION_COUNT; partitionIndex++) {
         managers[partitionIndex] = this.createTemporalScatterMemoryManager(baseName + "_partition" + partitionIndex, byteSizeSupplier.getAsInt());
      }
      return managers;
   }

   private void ensureTemporalScatterMemoryCapacity() {
      int requiredPixelCapacity = this.getTemporalScatterPixelCapacity();
      int requiredContributorCapacity = requiredPixelCapacity * 4;
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
      return this.temporalScatterPixelCapacity;
   }

   private boolean isTemporalScatterResolveOnlyBuffer(GlMemoryManager memoryManager) {
      if (memoryManager == null) {
         return false;
      }

      String name = memoryManager.getName();
      return name.startsWith("ph_temporal_scatter_cell_offsets")
         || name.startsWith("ph_temporal_scatter_sorted_reservoirs")
         || name.startsWith("ph_temporal_scatter_sorted_weights");
   }

   private GlMemoryManager createTemporalScatterMemoryManager(String name, int byteSize) {
      return new GlMemoryManager(at.redi2go.photonic.client.rendering.opengl.objects.GlTarget.SSBO, name, Math.max(byteSize, Integer.BYTES), false);
   }

   private void clearTemporalScatterOwnershipBuffers() {
      this.clearUintBuffers(this.temporalScatterGlobalCountersMemoryManagers, 0);
      this.clearUintBuffers(this.temporalScatterCellCountersMemoryManagers, 0);
      this.clearUintBuffers(this.temporalScatterReservoirIndicesMemoryManagers, 0);
      this.clearUintBuffers(this.temporalScatterScatteredReservoirsMemoryManagers, 0);
      this.clearUintBuffers(this.temporalScatterScatteredWeightsMemoryManagers, 0);
      this.clearUintBuffers(this.temporalScatterCellOffsetsMemoryManagers, 0);
      this.clearUintBuffers(this.temporalScatterSortedReservoirsMemoryManagers, 0);
      this.clearUintBuffers(this.temporalScatterSortedWeightsMemoryManagers, 0);
      GL42.glMemoryBarrier(GL43.GL_SHADER_STORAGE_BARRIER_BIT);
   }

   private void clearUintBuffers(GlMemoryManager[] memoryManagers, int value) {
      if (memoryManagers == null) {
         return;
      }

      for (GlMemoryManager memoryManager : memoryManagers) {
         this.clearUintBuffer(memoryManager, value);
      }
   }

   private void clearUintBuffer(GlMemoryManager memoryManager, int value) {
      java.nio.IntBuffer clearValue = BufferUtils.createIntBuffer(1);
      clearValue.put(value);
      clearValue.flip();
      GL15.glBindBuffer(GL43.GL_SHADER_STORAGE_BUFFER, memoryManager.getId());
      GL43.glClearBufferData(GL43.GL_SHADER_STORAGE_BUFFER, GL30.GL_R32UI, GL30.GL_RED_INTEGER, GL30.GL_UNSIGNED_INT, clearValue);
      GL15.glBindBuffer(GL43.GL_SHADER_STORAGE_BUFFER, 0);
   }

   private void destroyTemporalScatterMemoryManagers() {
      this.destroyTemporalScatterMemoryManagers(this.temporalScatterGlobalCountersMemoryManagers);
      this.destroyTemporalScatterMemoryManagers(this.temporalScatterCellCountersMemoryManagers);
      this.destroyTemporalScatterMemoryManagers(this.temporalScatterReservoirIndicesMemoryManagers);
      this.destroyTemporalScatterMemoryManagers(this.temporalScatterScatteredReservoirsMemoryManagers);
      this.destroyTemporalScatterMemoryManagers(this.temporalScatterScatteredWeightsMemoryManagers);
      this.destroyTemporalScatterMemoryManagers(this.temporalScatterCellOffsetsMemoryManagers);
      this.destroyTemporalScatterMemoryManagers(this.temporalScatterSortedReservoirsMemoryManagers);
      this.destroyTemporalScatterMemoryManagers(this.temporalScatterSortedWeightsMemoryManagers);
      this.temporalScatterGlobalCountersMemoryManagers = null;
      this.temporalScatterCellCountersMemoryManagers = null;
      this.temporalScatterReservoirIndicesMemoryManagers = null;
      this.temporalScatterScatteredReservoirsMemoryManagers = null;
      this.temporalScatterScatteredWeightsMemoryManagers = null;
      this.temporalScatterCellOffsetsMemoryManagers = null;
      this.temporalScatterSortedReservoirsMemoryManagers = null;
      this.temporalScatterSortedWeightsMemoryManagers = null;
   }

   private void destroyTemporalScatterMemoryManagers(GlMemoryManager[] memoryManagers) {
      if (memoryManagers == null) {
         return;
      }

      for (GlMemoryManager memoryManager : memoryManagers) {
         if (memoryManager != null) {
            memoryManager.free();
         }
      }
   }

   private void destroyScatterTemporalResources() {
      this.temporalScatterStageFramebuffer.destroy();
      this.temporalReservoirFramebuffer.destroy();
      this.scatterReconnectionBuffer.destroy();
      this.temporalReservoirBuffer.destroy();
      this.temporalGatherBuffer.destroy();
      this.destroyTemporalScatterMemoryManagers();
   }

   private void clearScatterTemporalHistory(Vector4f clearColor) {
      // Reset both the previous/current reconnection history and the same-frame temporal
      // output so later scatter modes can assume empty histories after a camera jump/reload.
      this.scatterReconnectionBuffer.clearBothSides(clearColor);
      this.temporalReservoirBuffer.clearBothSides(clearColor);
      this.temporalGatherBuffer.clearBothSides(clearColor);
   }

   @Override
   public void render() {
      if (this.proposalStageRenderer == null) {
         return;
      }

      this.renderFrameIndex++;
      this.resolveGpuProfile();
      this.advanceGpuProfileFrame();
      this.ensureCompatDirectSoftCleared();
      this.ensureReservoirHistoryCleared();
      this.lightingBuffer.swap();
      this.compatDirectSoftBuffer.swap();
      this.motionVectorBuffer.swap();
      this.directReservoirBuffer.swap();
      this.swapScatterTemporalHistory();
      this.directConfidenceBuffer.swap();
      this.directHistoryLengthBuffer.swap();
      this.directNoisyBuffer.swap();
      this.directResponsiveBuffer.swap();
      this.directSlowBuffer.swap();
      this.directFastBuffer.swap();
      this.directAntiFireflyBuffer.swap();
      this.directClampedSlowBuffer.swap();
      this.directClampedFastBuffer.swap();
      this.directDenoisedBuffer.swap();
      this.directAtrousPingBuffer.swap();
      this.specularNoisyBuffer.swap();
      this.specularResponsiveBuffer.swap();
      this.specularSlowBuffer.swap();
      this.specularFastBuffer.swap();
      this.specularAntiFireflyBuffer.swap();
      this.specularClampedSlowBuffer.swap();
      this.specularClampedFastBuffer.swap();
      this.specularDenoisedBuffer.swap();
      this.specularAtrousPingBuffer.swap();
      this.specularHistoryLengthBuffer.swap();
      this.indirectInitialReservoirBuffer.swap();
      this.indirectReservoirBuffer.swap();
      this.indirectDenoisedBuffer.swap();
      long t0 = System.nanoTime();
      this.renderLightTreeSamplingStageProfiled();
      long t1 = System.nanoTime();
      this.renderDIGenerateInitialSamplesProfiled();
      long t2 = System.nanoTime();
      this.renderDIScatterTemporalProfiled();
      long t3 = System.nanoTime();
      this.renderDISpatialResamplingProfiled();
      long t4 = System.nanoTime();
      // Final shading now runs in two steps:
      // 1) promote post-spatial reservoirs into direct history with final visibility
      // 2) resolve lighting from the promoted authoritative direct reservoir
      this.renderShadeSamplesProfiled();
      long t5 = System.nanoTime();
      this.renderProfiled(nrdPrepareInputsRegionIndex, this.directFeatureRenderer);
      long t6 = System.nanoTime();
      this.renderProfiled(relaxDiffuseTemporalAccumulationRegionIndex, this.directTemporalRenderer);
      long t7 = System.nanoTime();
      this.renderProfiled(relaxDiffuseHistoryFixRegionIndex, this.directHistoryFixRenderer);
      long t8 = System.nanoTime();
      this.renderProfiled(relaxDiffuseHistoryClampingRegionIndex, this.directHistoryClampingRenderer);
      long t9 = System.nanoTime();
      this.renderProfiled(relaxDiffuseAntiFireflyRegionIndex, this.directAntiFireflyRenderer);
      long t10 = System.nanoTime();
      this.renderDirectAtrousProfiled();
      long t11 = System.nanoTime();
      this.renderProfiled(relaxSpecularTemporalAccumulationRegionIndex, this.specTemporalRenderer);
      long t12 = System.nanoTime();
      this.renderProfiled(relaxSpecularHistoryFixRegionIndex, this.specHistoryFixRenderer);
      long t13 = System.nanoTime();
      this.renderProfiled(relaxSpecularHistoryClampingRegionIndex, this.specHistoryClampingRenderer);
      long t14 = System.nanoTime();
      this.renderProfiled(relaxSpecularAntiFireflyRegionIndex, this.specAntiFireflyRenderer);
      long t15 = System.nanoTime();
      this.renderSpecAtrousProfiled();
      long t16 = System.nanoTime();
      this.renderIndirectAccumulationProfiled();
      long t17 = System.nanoTime();
      this.renderProfiled(indirectDenoiseRegionIndex, this.indirectDenoisingRenderer);
      long t18 = System.nanoTime();
      this.renderProfiled(lightingAccumulationRegionIndex, this.accumulationRenderer);
      long t19 = System.nanoTime();
      this.renderProfiled(indirectCompositeRegionIndex, this.indirectRenderer);
      long t20 = System.nanoTime();
      this.recordCpuPassTimes(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20);
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
         Map.entry("direct_noisy", this.directNoisyBuffer.getWriteAttachment("data")),
         Map.entry("direct_responsive", this.directResponsiveBuffer.getWriteAttachment("data")),
         Map.entry("direct_slow", this.directSlowBuffer.getWriteAttachment("data")),
         Map.entry("direct_fast", this.directFastBuffer.getWriteAttachment("data")),
         Map.entry("direct_clamped_slow", this.directClampedSlowBuffer.getWriteAttachment("data")),
         Map.entry("direct_clamped_fast", this.directClampedFastBuffer.getWriteAttachment("data")),
         Map.entry("direct_anti_firefly", this.directAntiFireflyBuffer.getWriteAttachment("data")),
         Map.entry("direct_denoised", this.directDenoisedBuffer.getWriteAttachment("data")),
         Map.entry("direct_atrous", this.getResolvedDiffuseAtrousTexture()),
         Map.entry("direct_raw", this.lightingStageBuffer.getWriteAttachment("direct")),
         Map.entry("spec_denoised", this.getResolvedSpecularAtrousTexture()),
         Map.entry("spec_raw", this.lightingStageBuffer.getWriteAttachment("direct_specular")),
         Map.entry("direct_initial_debug", this.directInitialDebugBuffer.getWriteAttachment("data")),
         Map.entry("handheld", this.lightingBuffer.getWriteAttachment("handheld")),
         Map.entry("indirect", this.getResolvedIndirectTexture()),
         Map.entry("indirect_raw", this.lightingBuffer.getWriteAttachment("indirect")),
         Map.entry("indirect_reservoir", this.indirectReservoirBuffer.getWriteAttachment("radiance")),
         Map.entry("lighting", this.directSlowBuffer.getWriteAttachment("data")),
         Map.entry("stage_albedo", this.lightingStageBuffer.getWriteAttachment("albedo")),
         Map.entry("stage_direct", this.lightingStageBuffer.getWriteAttachment("direct")),
         Map.entry("stage_mapped_normal", this.lightingStageBuffer.getWriteAttachment("mapped_normal")),
         Map.entry("stage_material", this.lightingStageBuffer.getWriteAttachment("material")),
         Map.entry("stage_lighting", this.directResponsiveBuffer.getWriteAttachment("data")),
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
      this.directHistoryLengthBuffer.updatePerFrame();
      this.directNoisyBuffer.updatePerFrame();
      this.directConfidenceBuffer.updatePerFrame();
      this.directInitialDebugBuffer.updatePerFrame();
      this.directResponsiveBuffer.updatePerFrame();
      this.directSlowBuffer.updatePerFrame();
      this.directFastBuffer.updatePerFrame();
      this.directAntiFireflyBuffer.updatePerFrame();
      this.directClampedSlowBuffer.updatePerFrame();
      this.directClampedFastBuffer.updatePerFrame();
      this.directAtrousPingBuffer.updatePerFrame();
      this.specularNoisyBuffer.updatePerFrame();
      this.specularResponsiveBuffer.updatePerFrame();
      this.specularSlowBuffer.updatePerFrame();
      this.specularFastBuffer.updatePerFrame();
      this.specularAntiFireflyBuffer.updatePerFrame();
      this.specularClampedSlowBuffer.updatePerFrame();
      this.specularClampedFastBuffer.updatePerFrame();
      this.specularDenoisedBuffer.updatePerFrame();
      this.specularAtrousPingBuffer.updatePerFrame();
      this.specularHistoryLengthBuffer.updatePerFrame();
      this.motionVectorBuffer.updatePerFrame();
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
      this.recalculateRenderer(this.directTemporalRenderer);
      this.recalculateRenderer(this.directAntiFireflyRenderer);
      this.recalculateRenderer(this.directHistoryFixRenderer);
      this.recalculateRenderer(this.directHistoryClampingRenderer);
      this.recalculateRenderer(this.directAtrousRenderer);
      this.recalculateRenderer(this.specTemporalRenderer);
      this.recalculateRenderer(this.specAntiFireflyRenderer);
      this.recalculateRenderer(this.specHistoryFixRenderer);
      this.recalculateRenderer(this.specHistoryClampingRenderer);
      this.recalculateRenderer(this.specAtrousRenderer);
      this.recalculateRenderer(this.indirectInitialRenderer);
      this.recalculateRenderer(this.indirectBoilingRenderer);
      this.recalculateRenderer(this.indirectAccumulationRenderer);
      this.recalculateRenderer(this.indirectDenoisingRenderer);
      this.recalculateRenderer(this.accumulationRenderer);
      this.recalculateRenderer(this.indirectRenderer);
      this.recalculateRenderer(this.shadeSamplesMonolithicRenderer);
      this.recalculateRenderer(this.shadeSamplesReservoirRenderer);
      this.recalculateRenderer(this.shadeSamplesRenderer);
      this.invalidateDirectReuseHistory();
   }

   @Override
   public void free() {
      PhotonicsStorage.RESTIR_LOCAL_LIGHT_SAMPLING_MODE.removeObserver(this.localLightSamplingModeObserver);
      PhotonicsStorage.RESTIR_TEMPORAL_SCATTER_ISOLATION_MODE.removeObserver(this.temporalScatterIsolationModeObserver);
      this.proposalFramebuffer.destroy();
      this.proposalReservoirFramebuffer.destroy();
      this.reuseResolveFramebuffer.destroy();
      this.directFeatureFramebuffer.destroy();
      this.directTemporalFramebuffer.destroy();
      this.directAntiFireflyFramebuffer.destroy();
      this.directHistoryFixFramebuffer.destroy();
      this.directHistoryClampingFramebuffer.destroy();
      this.directAtrousFramebuffer.destroy();
      this.specTemporalFramebuffer.destroy();
      this.specAntiFireflyFramebuffer.destroy();
      this.specHistoryFixFramebuffer.destroy();
      this.specHistoryClampingFramebuffer.destroy();
      this.specAtrousFramebuffer.destroy();
      this.indirectInitialFramebuffer.destroy();
      this.indirectBoilingFramebuffer.destroy();
      this.indirectAccumulationFramebuffer.destroy();
      this.indirectDenoisingFramebuffer.destroy();
      this.positionWriteFramebuffer.destroy();
      this.shadeSamplesMonolithicFramebuffer.destroy();
      this.shadeSamplesFramebuffer.destroy();
      this.shadeSamplesReservoirFramebuffer.destroy();
      this.destroyScatterTemporalResources();
      this.lightingBuffer.destroy();
      this.lightingStageBuffer.destroy();
      this.compatDirectSoftBuffer.destroy();
      this.motionVectorBuffer.destroy();
      this.directReservoirBuffer.destroy();
      this.directSpatialReservoirBuffer.destroy();
      this.directConfidenceBuffer.destroy();
      this.directHistoryLengthBuffer.destroy();
      this.directNoisyBuffer.destroy();
      this.directResponsiveBuffer.destroy();
      this.directSlowBuffer.destroy();
      this.directFastBuffer.destroy();
      this.directAntiFireflyBuffer.destroy();
      this.directClampedSlowBuffer.destroy();
      this.directClampedFastBuffer.destroy();
      this.directDenoisedBuffer.destroy();
      this.directAtrousPingBuffer.destroy();
      this.specularNoisyBuffer.destroy();
      this.specularResponsiveBuffer.destroy();
      this.specularSlowBuffer.destroy();
      this.specularFastBuffer.destroy();
      this.specularAntiFireflyBuffer.destroy();
      this.specularClampedSlowBuffer.destroy();
      this.specularClampedFastBuffer.destroy();
      this.specularDenoisedBuffer.destroy();
      this.specularAtrousPingBuffer.destroy();
      this.specularHistoryLengthBuffer.destroy();
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
      this.destroyRenderer(this.directTemporalRenderer);
      this.destroyRenderer(this.directAntiFireflyRenderer);
      this.destroyRenderer(this.directHistoryFixRenderer);
      this.destroyRenderer(this.directHistoryClampingRenderer);
      this.destroyRenderer(this.directAtrousRenderer);
      this.destroyRenderer(this.specTemporalRenderer);
      this.destroyRenderer(this.specAntiFireflyRenderer);
      this.destroyRenderer(this.specHistoryFixRenderer);
      this.destroyRenderer(this.specHistoryClampingRenderer);
      this.destroyRenderer(this.specAtrousRenderer);
      this.destroyRenderer(this.indirectInitialRenderer);
      this.destroyRenderer(this.indirectBoilingRenderer);
      this.destroyRenderer(this.indirectAccumulationRenderer);
      this.destroyRenderer(this.indirectDenoisingRenderer);
      this.destroyRenderer(this.accumulationRenderer);
      this.destroyRenderer(this.indirectRenderer);
      this.destroyRenderer(this.shadeSamplesMonolithicRenderer);
      this.destroyRenderer(this.shadeSamplesReservoirRenderer);
      this.destroyRenderer(this.shadeSamplesRenderer);
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

   private ColorFramebuffer createScatterReconnectionFramebuffer(float renderScale) {
      ColorFramebuffer framebuffer = new ColorFramebuffer(this::getDirectReservoirResolution, renderScale);
      // Shared DI reconnection payload split across two finite-float targets:
      // reconnection0: worldPos.xyz, viewDepth
      // reconnection1: packed confidence/lightPdf, packed meta flags, subPixel, packed Jacobians
      framebuffer.createAttachment("reconnection0", "RGBA32F", false);
      framebuffer.createAttachment("reconnection1", "RGBA32F", false);
      // Stage-input shadow copies of reconnection0/1. These are NEVER bound as
      // color attachments during a draw call — they only receive
      // glCopyImageSubData payloads between pipeline stages and are read as
      // current_stage_reconnection0/1 samplers. Decoupling the
      // read-side from the write-side avoids the undefined behaviour of
      // sampling an attachment that is also bound as a draw-framebuffer color
      // output in the same draw call (Stage 4 / Stage 5 feedback loop).
      framebuffer.createAttachment("stage_in_reconnection0", "RGBA32F", false);
      framebuffer.createAttachment("stage_in_reconnection1", "RGBA32F", false);
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
      framebuffer.createAttachment("floating_coords", "RG32F", false);
      framebuffer.createAttachment("intermediate_data", "RGBA32F", false);
      framebuffer.createAttachment("intermediate_sample", "RGBA32F", false);
      framebuffer.createAttachment("intermediate_meta", "RGBA32F", false);
      framebuffer.createAttachment("intermediate_reconnection0", "RGBA32F", false);
      framebuffer.createAttachment("intermediate_reconnection1", "RGBA32F", false);
      framebuffer.createAttachment("shifted_path_data0", "RGBA32F", false);
      framebuffer.createAttachment("shifted_path_data1", "RGBA32F", false);
      framebuffer.createAttachment("shifted_path_data2", "RGBA32F", false);
      framebuffer.createAttachment("shifted_path_data3", "RGBA32F", false);
      framebuffer.createAttachment("shifted_path_data4", "RGBA32F", false);
      framebuffer.createAttachment("shifted_path_data5", "RGBA32F", false);
      framebuffer.createAttachment("shifted_path_data6", "RGBA32F", false);
      framebuffer.createAttachment("shifted_path_data7", "RGBA32F", false);
      framebuffer.createAttachment("shifted_path_data8", "RGBA32F", false);
      framebuffer.createAttachment("shifted_path_data9", "RGBA32F", false);
      framebuffer.createAttachment("shifted_path_data10", "RGBA32F", false);
      framebuffer.createAttachment("shifted_path_data11", "RGBA32F", false);
      framebuffer.createAttachment("shifted_path_data12", "RGBA32F", false);
      framebuffer.createAttachment("shifted_path_data13", "RGBA32F", false);
      framebuffer.createAttachment("shifted_path_data14", "RGBA32F", false);
      framebuffer.createAttachment("shifted_path_data15", "RGBA32F", false);
      return framebuffer;
   }

   private RoutingFramebuffer createTemporalReservoirRoutingFramebuffer() {
      // Outputs 5 textures: 3 reservoir (data/sample/meta) + 2 reconnection payloads.
      // The reconnection writes go to the current-frame scatterReconnectionBuffer
      // (write side), which is ping-ponged next frame into previous-frame history.
      // Strict reference parity would require additional gather-stage storage here
      // (e.g. floating coordinates and intermediate reservoir/reconnection buffers),
      // so the next concrete implementation step must extend the render graph rather
      // than continue audit-only cleanup.
      return this.createDirectPackedRoutingFramebuffer(
         () -> this.temporalReservoirBuffer.getWriteAttachment("data"),
         () -> this.temporalReservoirBuffer.getWriteAttachment("sample"),
         () -> this.temporalReservoirBuffer.getWriteAttachment("meta"),
         () -> this.scatterReconnectionBuffer.getWriteAttachment("reconnection0"),
         () -> this.scatterReconnectionBuffer.getWriteAttachment("reconnection1")
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
      Vector2f framebufferSize = new Vector2f(
         MinecraftClient.getInstance().getWindow().getFramebufferWidth(),
         MinecraftClient.getInstance().getWindow().getFramebufferHeight()
      );
      if (this.getActiveCheckerboardField() == 0) {
         return framebufferSize;
      }
      framebufferSize.x = Math.max(1.0f, (float) Math.ceil(framebufferSize.x * 0.5f));
      return framebufferSize;
   }

   private RoutingFramebuffer createDirectTemporalFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.directNoisyBuffer.getWriteAttachment("data"),
         () -> this.directResponsiveBuffer.getWriteAttachment("data"),
         () -> this.directSlowBuffer.getWriteAttachment("data"),
         () -> this.directFastBuffer.getWriteAttachment("data"),
         () -> this.directHistoryLengthBuffer.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createDirectFeatureFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingStageBuffer.getWriteAttachment("material"),
         () -> this.directConfidenceBuffer.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createDirectAntiFireflyFramebuffer() {
      return this.createRoutingFramebuffer(() -> this.directAntiFireflyBuffer.getWriteAttachment("data"));
   }

   private RoutingFramebuffer createDirectHistoryFixFramebuffer() {
      return this.createRoutingFramebuffer(() -> this.directClampedSlowBuffer.getWriteAttachment("data"));
   }

   private RoutingFramebuffer createDirectHistoryClampingFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.directClampedSlowBuffer.getWriteAttachment("data"),
         () -> this.directClampedFastBuffer.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createDirectAtrousFramebuffer() {
      return this.createRoutingFramebuffer(this::getCurrentDirectAtrousOutputTexture);
   }

   private RoutingFramebuffer createSpecTemporalFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.specularNoisyBuffer.getWriteAttachment("data"),
         () -> this.specularResponsiveBuffer.getWriteAttachment("data"),
         () -> this.specularSlowBuffer.getWriteAttachment("data"),
         () -> this.specularFastBuffer.getWriteAttachment("data"),
         () -> this.specularHistoryLengthBuffer.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createSpecAntiFireflyFramebuffer() {
      return this.createRoutingFramebuffer(() -> this.specularAntiFireflyBuffer.getWriteAttachment("data"));
   }

   private RoutingFramebuffer createSpecHistoryFixFramebuffer() {
      return this.createRoutingFramebuffer(() -> this.specularClampedSlowBuffer.getWriteAttachment("data"));
   }

   private RoutingFramebuffer createSpecHistoryClampingFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.specularClampedSlowBuffer.getWriteAttachment("data"),
         () -> this.specularClampedFastBuffer.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createSpecAtrousFramebuffer() {
      return this.createRoutingFramebuffer(this::getCurrentSpecAtrousOutputTexture);
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
      // Reference parity (InitialCandidates.cs.slang:63-66): initial-candidate stage
      // writes exactly two logical outputs — the packed DI reservoir (data/sample/meta)
      // and the selected reconnection data (reconnection0/reconnection1). No side
      // debug channel. Removing the orphan `direct_initial_debug` binding aligns the
      // FBO attachment count with the 5 fragment outputs in GenerateInitialSamples.fsh.
      return this.createDirectPackedRoutingFramebuffer(
         () -> this.directReservoirBuffer.getWriteAttachment("data"),
         () -> this.directReservoirBuffer.getWriteAttachment("sample"),
         () -> this.directReservoirBuffer.getWriteAttachment("meta"),
         () -> this.scatterReconnectionBuffer.getWriteAttachment("reconnection0"),
         () -> this.scatterReconnectionBuffer.getWriteAttachment("reconnection1")
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
         () -> this.scatterReconnectionBuffer.getWriteAttachment("reconnection1")
      );
   }

   private RoutingFramebuffer createShadeSamplesLightingFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingStageBuffer.getWriteAttachment("direct"),
         () -> this.lightingStageBuffer.getWriteAttachment("direct_specular")
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
         () -> this.directReservoirBuffer.getWriteAttachment("meta")
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
         || this.isCurrentPhotonicsFragment(diGenerateInitialSamplesFragment)
         || this.isCurrentPhotonicsFragment(diCollectTemporalSamplesFragment)
         || this.isCurrentPhotonicsFragment(diTemporalReprojectionFragment)
         || this.isCurrentPhotonicsFragment(diTemporalBinningOffsetsFragment)
         || this.isCurrentPhotonicsFragment(diTemporalBinningFragment)
         || this.isCurrentPhotonicsFragment(diShadeSamplesLightingFragment)
         || this.isCurrentPhotonicsFragment(diShadeSamplesReservoirFragment)
         || this.isCurrentPhotonicsFragment(diSpatialResamplingFragment)
         || this.isCurrentPhotonicsFragment(diScatterTemporalResamplingFragment)
         || this.isCurrentPhotonicsFragment(relaxDiffuseAntiFireflyFragment)
         || this.isCurrentPhotonicsFragment(relaxDiffuseHistoryFixFragment)
         || this.isCurrentPhotonicsFragment(relaxDiffuseHistoryClampingFragment)
         || this.isCurrentPhotonicsFragment(relaxDiffuseAtrousFragment)
         || this.isCurrentPhotonicsFragment(relaxSpecularTemporalAccumulationFragment)
         || this.isCurrentPhotonicsFragment(relaxSpecularAntiFireflyFragment)
         || this.isCurrentPhotonicsFragment(relaxSpecularHistoryFixFragment)
         || this.isCurrentPhotonicsFragment(relaxSpecularHistoryClampingFragment)
         || this.isCurrentPhotonicsFragment(relaxSpecularAtrousFragment)
         || this.isCurrentPhotonicsFragment(indirectAccumulationFragment)
         // GI denoising runs before the accumulation pass copies the current frame
         // guides into lightingBuffer, so it must read the live stage geometry.
         || this.isCurrentPhotonicsFragment(indirectDenoisingFragment);
   }

   private boolean shouldUseCurrentDirectHistoryLength() {
      return this.isCurrentPhotonicsFragment(relaxDiffuseTemporalAccumulationFragment)
         || this.isCurrentPhotonicsFragment(relaxDiffuseHistoryFixFragment)
         || this.isCurrentPhotonicsFragment(relaxDiffuseHistoryClampingFragment)
         || this.isCurrentPhotonicsFragment(relaxDiffuseAtrousFragment);
   }

   private boolean shouldUseCurrentSpecHistoryLength() {
      return this.isCurrentPhotonicsFragment(relaxSpecularTemporalAccumulationFragment)
         || this.isCurrentPhotonicsFragment(relaxSpecularHistoryFixFragment)
         || this.isCurrentPhotonicsFragment(relaxSpecularHistoryClampingFragment)
         || this.isCurrentPhotonicsFragment(relaxSpecularAtrousFragment);
   }

   private TextureObject getCurrentDirectAtrousInputTexture() {
      if (this.directAtrousIteration == 0) {
         return this.directAntiFireflyBuffer.getWriteAttachment("data");
      }
      if ((this.directAtrousIteration & 1) == 1) {
         return this.directAtrousPingBuffer.getWriteAttachment("data");
      }
      return this.directDenoisedBuffer.getWriteAttachment("data");
   }

   private boolean isFinalDirectAtrousIteration() {
      return this.directAtrousIteration == this.directAtrousStepSizes.length - 1;
   }

   private TextureObject getCurrentDirectAtrousOutputTexture() {
      boolean isFinalPass = this.isFinalDirectAtrousIteration();
      boolean readsDenoisedBuffer = this.directAtrousIteration > 0 && (this.directAtrousIteration & 1) == 0;
      if (isFinalPass && readsDenoisedBuffer) {
         return this.directAtrousPingBuffer.getWriteAttachment("data");
      }
      if (isFinalPass) {
         return this.directDenoisedBuffer.getWriteAttachment("data");
      }
      if ((this.directAtrousIteration & 1) == 0) {
         return this.directAtrousPingBuffer.getWriteAttachment("data");
      }
      return this.directDenoisedBuffer.getWriteAttachment("data");
   }

   private TextureObject getCurrentSpecAtrousInputTexture() {
      if (this.specAtrousIteration == 0) {
         return this.specularAntiFireflyBuffer.getWriteAttachment("data");
      }
      if ((this.specAtrousIteration & 1) == 1) {
         return this.specularAtrousPingBuffer.getWriteAttachment("data");
      }
      return this.specularDenoisedBuffer.getWriteAttachment("data");
   }

   private boolean isFinalSpecAtrousIteration() {
      return this.specAtrousIteration == this.directAtrousStepSizes.length - 1;
   }

   private TextureObject getCurrentSpecAtrousOutputTexture() {
      boolean isFinalPass = this.isFinalSpecAtrousIteration();
      boolean readsDenoisedBuffer = this.specAtrousIteration > 0 && (this.specAtrousIteration & 1) == 0;
      if (isFinalPass && readsDenoisedBuffer) {
         return this.specularAtrousPingBuffer.getWriteAttachment("data");
      }
      if (isFinalPass) {
         return this.specularDenoisedBuffer.getWriteAttachment("data");
      }
      if ((this.specAtrousIteration & 1) == 0) {
         return this.specularAtrousPingBuffer.getWriteAttachment("data");
      }
      return this.specularDenoisedBuffer.getWriteAttachment("data");
   }

   private int getCurrentDirectAtrousStepSize() {
      // During specular A-trous, use specAtrousIteration — directAtrousIteration is past-the-end.
      int iteration = this.isCurrentPhotonicsFragment(relaxSpecularAtrousFragment)
         ? this.specAtrousIteration
         : this.directAtrousIteration;
      int iterationIndex = Math.max(0, Math.min(iteration, this.directAtrousStepSizes.length - 1));
      return this.directAtrousStepSizes[iterationIndex];
   }

   private float getDirectSampleBudgetScale() {
      return 1.0f;
   }

   private int getCurrentDirectAtrousIsLastPass() {
      int iteration = this.isCurrentPhotonicsFragment(relaxSpecularAtrousFragment)
         ? this.specAtrousIteration
         : this.directAtrousIteration;
      return iteration == this.directAtrousStepSizes.length - 1 ? 1 : 0;
   }

   private static int[] resolveDirectAtrousStepSizes(PhotonicsProperties properties) {
      int passCount = Math.clamp(properties.getNrdAtrousPasses(), 1, 7);
      return switch (passCount) {
         case 1 -> new int[]{4};
         case 2 -> new int[]{1, 8};
         case 3 -> new int[]{1, 4, 16};
         case 4 -> new int[]{1, 2, 8, 16};
         case 5 -> new int[]{1, 2, 4, 8, 16};
         case 6 -> new int[]{1, 2, 4, 8, 16, 16};
         case 7 -> new int[]{1, 2, 4, 8, 16, 16, 16};
         default -> throw new IllegalStateException("Unexpected direct atrous pass count: " + passCount);
      };
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

      return this.renderFrameIndex;
   }

   private int resolveRegirPresampleFrameSeed() {
      return this.resolveRegirFrameSeed("photonics.regirPresampleFrameSeed", "photonics.regirFrameSeed", "presample");
   }

   private int resolveRegirBuildFrameSeed() {
      return this.resolveRegirFrameSeed("photonics.regirBuildFrameSeed", "photonics.regirFrameSeed", "build");
   }

   private void dispatchRegirCompute() {
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

      // RTXDI defaults: numBuildSamples = 8 (ReGIR.h:141). The FullSample uploads
      // samplingJitter as 2.0 after doubling the user-facing default of 1.0.
      // getRegirLightIndexMemoryManager() is the unified uvec2 ReGIR output buffer,
      // allocated at 8 bytes/slot (cellCount * lightsPerCell * 8) to hold uvec2 entries.
      int gridRes = lightRegistry.getRegirGridResolution();
      this.regirComputeProgram.dispatch(
         lightRegistry.getLightsMemoryManager(),
         lightRegistry.getRegirLightPdfMemoryManager(),
         lightRegistry.getRegirLightIndexMemoryManager(),
         lightRegistry.getRegirCompactLightDataMemoryManager(),
         lightRegistry.getRegirGridCenter(),
         new Vector3i(gridRes, gridRes, gridRes),
         lightRegistry.getRegirLightsPerCell(),
         32.0f,
         lightCount,
         this.resolveRegirPresampleFrameSeed(),
         this.resolveRegirBuildFrameSeed(),
         8,    // numBuildSamples — RTXDI default from ReGIR.h:141
         lightRegistry.getRegirSamplingJitter()
      );
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
      this.dispatchRegirCompute();
      if (this.proposalStageRenderer != null) {
         this.proposalStageRenderer.renderAll();
      }
      this.endGpuRegion(lightTreeSamplingStageRegionIndex);
   }

   private void renderDIGenerateInitialSamplesProfiled() {
      this.beginGpuRegion(diGenerateInitialSamplesRegionIndex);
      if (this.isDirectProposalReservoirEnabled()) {
         if (this.proposalReservoirRenderer != null) {
            this.proposalReservoirRenderer.renderAll();
         }
      } else {
         this.clearProposalReservoirOutputs();
      }
      this.endGpuRegion(diGenerateInitialSamplesRegionIndex);
   }

   private void renderDIScatterTemporalProfiled() {
      this.beginGpuRegion(diTemporalResamplingRegionIndex);
      // Publish Stage 1 (GenerateInitialSamples) reconnection output into the
      // read-side shadow copies so the temporal/scatter stage below can sample
      // `scatter_reconnection0/1` without aliasing the live draw attachments.
      this.publishScatterReconnectionStageInputs();
      this.clearTemporalScatterOwnershipBuffers();
      // Step 2a: CollectTemporalSamples populates the gather-side floating
      // coordinates and intermediate reservoir/reconnection storage before the
      // scatter-side reprojection/sort/resolve chain runs.
      if (this.temporalCollectRenderer != null) {
         this.temporalCollectRenderer.renderAll();
         GL42.glMemoryBarrier(GL42.GL_FRAMEBUFFER_BARRIER_BIT | GL42.GL_TEXTURE_FETCH_BARRIER_BIT);
      }
      String temporalScatterIsolationMode = PhotonicsStorage.normalizeTemporalScatterIsolationMode(
         PhotonicsStorage.RESTIR_TEMPORAL_SCATTER_ISOLATION_MODE.value
      );
      boolean scatterOnlyTemporalBranch = !"temporal_off".equals(temporalScatterIsolationMode)
         && !"ownership_only".equals(temporalScatterIsolationMode)
         && !"multi_scatter".equals(temporalScatterIsolationMode);
      boolean scatterBackupTemporalBranch = "scatter_backup".equals(temporalScatterIsolationMode);
      boolean multiScatterTemporalBranch = "multi_scatter".equals(temporalScatterIsolationMode);
      boolean robustGatherTemporalBranch = "off".equals(temporalScatterIsolationMode)
         || "ownership_only".equals(temporalScatterIsolationMode)
         || scatterBackupTemporalBranch;
      if (robustGatherTemporalBranch && this.robustReuseOptimizationRenderer != null) {
         this.robustReuseOptimizationRenderer.renderAll();
         GL42.glMemoryBarrier(GL42.GL_FRAMEBUFFER_BARRIER_BIT | GL42.GL_TEXTURE_FETCH_BARRIER_BIT);
      }
      if (robustGatherTemporalBranch && this.temporalGatherRenderer != null) {
         this.temporalGatherRenderer.renderAll();
         GL42.glMemoryBarrier(GL42.GL_FRAMEBUFFER_BARRIER_BIT | GL42.GL_TEXTURE_FETCH_BARRIER_BIT);
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
         }
      } else if (scatterOnlyTemporalBranch && this.temporalScatterReprojectionRenderer != null) {
         this.temporalScatterReprojectionRenderer.renderAll();
         this.barrierTemporalScatterOwnershipWrites();
      }
      // Reference: SortReprojectedReservoirs.cs.slang runs computeCellOffsets
      // and sortCellData as TWO separate compute dispatches with a pipeline
      // barrier between them (see ReservoirSplatting.cpp:474-479 for the
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
      } else if (scatterOnlyTemporalBranch && this.scatterTemporalRenderer != null) {
         this.scatterTemporalRenderer.renderAll();
      }
      this.endGpuRegion(diTemporalResamplingRegionIndex);
   }

   private void barrierTemporalScatterOwnershipWrites() {
      GL42.glMemoryBarrier(GL43.GL_SHADER_STORAGE_BARRIER_BIT | GL42.GL_FRAMEBUFFER_BARRIER_BIT);
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

   // Stage-boundary barrier + copy helper for the shared DI reconnection payload.
   //
   // The scatterReconnectionBuffer owns the authoritative write-side attachments
   // `reconnection0/1`, plus read-side shadow copies `stage_in_reconnection0/1`
   // that the legacy `scatter_reconnection0/1` samplers resolve to. Stage 1
   // (GenerateInitialSamples), Stage 2 (ScatterTemporalResolve), Stage 3
   // (SpatialResampling), and Stage 6 (resolve/final shading) all multiplex the
   // same payload attachments across consecutive passes. OpenGL does not allow a
   // fragment stage to sample from an attachment that is simultaneously bound as a
   // draw target, so every consumer stage reads from the copied stage-input side.
   //
   // To decouple reads from writes we:
   //   1. Issue a FRAMEBUFFER + TEXTURE_FETCH barrier so the producing stage's
   //      color writes are committed and available for texture operations.
   //   2. Copy reconnection0 -> stage_in_reconnection0 and
   //      reconnection1 -> stage_in_reconnection1 via glCopyImageSubData.
   //   3. Issue a second TEXTURE_FETCH barrier so the sampler reads in the
   //      consuming stage observe the copied data.
   private void publishScatterReconnectionStageInputs() {
      GL42.glMemoryBarrier(GL42.GL_FRAMEBUFFER_BARRIER_BIT | GL42.GL_TEXTURE_FETCH_BARRIER_BIT);
      this.copyScatterReconnectionAttachment("reconnection0", "stage_in_reconnection0");
      this.copyScatterReconnectionAttachment("reconnection1", "stage_in_reconnection1");
      GL42.glMemoryBarrier(GL42.GL_TEXTURE_FETCH_BARRIER_BIT);
   }

   private void copyScatterReconnectionAttachment(String sourceName, String destName) {
      TextureObject source = this.scatterReconnectionBuffer.getWriteAttachment(sourceName);
      TextureObject dest = this.scatterReconnectionBuffer.getWriteAttachment(destName);
      int[] dims = source.getTextureDimensions();
      int width = dims.length > 0 ? dims[0] : 0;
      int height = dims.length > 1 ? dims[1] : 0;
      if (width <= 0 || height <= 0) {
         return;
      }
      GL43.glCopyImageSubData(
         source.getTextureId(), GL11.GL_TEXTURE_2D, 0, 0, 0, 0,
         dest.getTextureId(), GL11.GL_TEXTURE_2D, 0, 0, 0, 0,
         width, height, 1
      );
   }

   private void renderDISpatialResamplingProfiled() {
      // Publish Stage 4 (ScatterTemporalResolve) reconnection output into the
      // read-side shadow copies so Stage 5 can sample the post-temporal
      // reconnection data without aliasing its own draw attachments.
      this.publishScatterReconnectionStageInputs();
      this.renderProfiled(diSpatialResamplingRegionIndex, this.reuseResolveRenderer);
      // Publish Stage 5 (SpatialResampling) reconnection output so subsequent
      // shading passes (ShadeSamples / ShadeSamplesReservoir) that only read
      // `scatter_reconnection0/1` observe the final post-spatial payload.
      this.publishScatterReconnectionStageInputs();
   }

   private void renderIndirectAccumulationProfiled() {
      if (this.indirectInitialRenderer == null && this.indirectBoilingRenderer == null && this.indirectAccumulationRenderer == null) {
         return;
      }
      this.beginGpuRegion(restirGIRegionIndex);
      if (this.indirectInitialRenderer != null) {
         this.indirectInitialRenderer.renderAll();
      }
      if (this.indirectBoilingRenderer != null) {
         this.indirectBoilingRenderer.renderAll();
         // Spatial GI should read the freshly filtered temporal reservoir and write
         // the frame-final GI reservoir back into the opposite side of the ping-pong buffer.
         this.indirectReservoirBuffer.swap();
      }
      if (this.indirectAccumulationRenderer != null) {
         this.indirectAccumulationRenderer.renderAll();
      }
      this.endGpuRegion(restirGIRegionIndex);
   }

   private void renderDirectAtrousProfiled() {
      if (!this.isDirectAtrousEnabled() || this.directAtrousRenderer == null) {
         return;
      }
      this.beginGpuRegion(relaxDiffuseAtrousRegionIndex);
      for (this.directAtrousIteration = 0; this.directAtrousIteration < this.directAtrousStepSizes.length; this.directAtrousIteration++) {
         long iterationStart = System.nanoTime();
         this.directAtrousRenderer.renderAll();
         this.lastCpuDirectAtrousIterationNanos[this.directAtrousIteration] = System.nanoTime() - iterationStart;
      }
      this.endGpuRegion(relaxDiffuseAtrousRegionIndex);
   }

   private void renderShadeSamplesProfiled() {
      boolean useMonolithic = false;
      if (useMonolithic) {
         if (this.shadeSamplesMonolithicRenderer == null) {
            return;
         }
         this.beginGpuRegion(diShadeSamplesRegionIndex);
         if (this.isDirectShadeSamplesEnabled()) {
            this.shadeSamplesMonolithicRenderer.renderAll();
         } else {
            this.clearShadeSamplesMonolithicOutputs();
         }
         this.endGpuRegion(diShadeSamplesRegionIndex);
         return;
      }

      if (this.shadeSamplesReservoirRenderer == null || this.shadeSamplesRenderer == null) {
         return;
      }
      this.beginGpuRegion(diShadeSamplesRegionIndex);
      if (this.isDirectShadeSamplesEnabled()) {
         this.shadeSamplesReservoirRenderer.renderAll();
         this.shadeSamplesRenderer.renderAll();
      } else {
         this.clearShadeSamplesSplitOutputs();
      }
      this.endGpuRegion(diShadeSamplesRegionIndex);
   }

   private void renderSpecAtrousProfiled() {
      this.beginGpuRegion(relaxSpecularAtrousRegionIndex);
      for (this.specAtrousIteration = 0; this.specAtrousIteration < this.directAtrousStepSizes.length; this.specAtrousIteration++) {
         this.specAtrousRenderer.renderAll();
      }
      this.endGpuRegion(relaxSpecularAtrousRegionIndex);
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

   private boolean directAtrousFinalWroteToPing() {
      // After the A-trous loop, determine which buffer holds the final output.
      // The final iteration index is (length - 1). When that index is > 0 and even,
      // the output texture function routes to atrousPingBuffer (because it reads from
      // denoisedBuffer and must write elsewhere). Otherwise it writes to denoisedBuffer.
      int lastIteration = this.directAtrousStepSizes.length - 1;
      return lastIteration > 0 && (lastIteration & 1) == 0;
   }

   private boolean specAtrousFinalWroteToPing() {
      int lastIteration = this.directAtrousStepSizes.length - 1;
      return lastIteration > 0 && (lastIteration & 1) == 0;
   }

   private TextureObject getResolvedDiffuseAtrousTexture() {
      if (this.directAtrousFinalWroteToPing()) {
         return this.directAtrousPingBuffer.getWriteAttachment("data");
      }
      return this.directDenoisedBuffer.getWriteAttachment("data");
   }

   private TextureObject getResolvedSpecularAtrousTexture() {
      if (this.specAtrousFinalWroteToPing()) {
         return this.specularAtrousPingBuffer.getWriteAttachment("data");
      }
      return this.specularDenoisedBuffer.getWriteAttachment("data");
   }

   @Nullable
   private TextureObject getDebugDirectStageTexture() {
      String normalized = PhotonicsStorage.normalizeDirectStageView(PhotonicsStorage.DEBUG_DIRECT_STAGE_VIEW.value);

      return switch (normalized) {
         case "final" -> this.lightingBuffer.getWriteAttachment("direct");
         case "lighting_direct", "lighting_buffer_direct", "direct_buffer" -> this.lightingBuffer.getWriteAttachment("direct");
         case "lighting", "stage_lighting", "lighting_buffer_lighting" -> this.lightingBuffer.getWriteAttachment("lighting");
         case "stage_direct", "direct_raw", "raw" -> this.lightingStageBuffer.getWriteAttachment("direct");
         case "stage_specular", "spec_raw", "direct_specular" -> this.lightingStageBuffer.getWriteAttachment("direct_specular");
         case "stage_indirect", "indirect_raw" -> this.lightingStageBuffer.getWriteAttachment("indirect");
         case "direct_noisy", "noisy", "temporal", "temporal_raw" -> this.directNoisyBuffer.getWriteAttachment("data");
         case "direct_responsive", "responsive" -> this.directResponsiveBuffer.getWriteAttachment("data");
         case "direct_slow", "slow" -> this.directSlowBuffer.getWriteAttachment("data");
         case "direct_fast", "fast" -> this.directFastBuffer.getWriteAttachment("data");
         case "direct_historyfix", "historyfix" -> this.directClampedSlowBuffer.getWriteAttachment("data");
         case "direct_anti_firefly", "anti_firefly" -> this.directAntiFireflyBuffer.getWriteAttachment("data");
         case "direct_clamped_slow", "clamped_slow" -> this.directClampedSlowBuffer.getWriteAttachment("data");
         case "direct_clamped_fast", "clamped_fast" -> this.directClampedFastBuffer.getWriteAttachment("data");
         case "direct_denoised", "denoised" -> this.directDenoisedBuffer.getWriteAttachment("data");
         case "direct_atrous", "atrous" -> this.getResolvedDiffuseAtrousTexture();
         default -> null;
      };
   }

   private TextureObject getResolvedDirectDiffuseTexture() {
      if (!this.isDirectAtrousEnabled()) {
         return this.directAntiFireflyBuffer.getWriteAttachment("data");
      }
      return this.getResolvedDiffuseAtrousTexture();
   }

   private TextureObject getResolvedDirectTexture() {
      if (PhotonicsStorage.DEBUG_VIEW_MODE.value > 0.5f) {
         return this.lightingStageBuffer.getWriteAttachment("direct");
      }
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

   private TextureObject getCurrentIndirectReservoirPositionTexture() {
      if (this.isCurrentPhotonicsFragment(indirectAccumulationFragment)) {
         return this.indirectReservoirBuffer.getReadAttachment("position");
      }
      return this.indirectReservoirBuffer.getWriteAttachment("position");
   }

   private TextureObject getCurrentIndirectReservoirNormalTexture() {
      if (this.isCurrentPhotonicsFragment(indirectAccumulationFragment)) {
         return this.indirectReservoirBuffer.getReadAttachment("normal");
      }
      return this.indirectReservoirBuffer.getWriteAttachment("normal");
   }

   private TextureObject getCurrentIndirectReservoirRadianceTexture() {
      if (this.isCurrentPhotonicsFragment(indirectAccumulationFragment)) {
         return this.indirectReservoirBuffer.getReadAttachment("radiance");
      }
      return this.indirectReservoirBuffer.getWriteAttachment("radiance");
   }

   private TextureObject getCurrentIndirectReservoirMetaTexture() {
      if (this.isCurrentPhotonicsFragment(indirectAccumulationFragment)) {
         return this.indirectReservoirBuffer.getReadAttachment("meta");
      }
      return this.indirectReservoirBuffer.getWriteAttachment("meta");
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

   private void clearShadeSamplesSplitOutputs() {
      Vector4f clearColor = new Vector4f(0.0f, 0.0f, 0.0f, 0.0f);
      this.shadeSamplesFramebuffer.clear(clearColor);
      this.shadeSamplesReservoirFramebuffer.clear(clearColor);
   }

   private void invalidateDirectReuseHistory() {
      this.compatDirectSoftDirty = true;
      this.reservoirHistoryDirty = true;
   }

   private void ensureCompatDirectSoftCleared() {
      if (!this.compatDirectSoftDirty) {
         return;
      }
      this.clearCompatDirectSoftAttachments();
      this.compatDirectSoftDirty = false;
   }

   private void ensureReservoirHistoryCleared() {
      if (!this.reservoirHistoryDirty) {
         return;
      }

      // RTXDI assumes reservoir histories start from EmptyReservoir on a reset.
      // Our ping-pong GL textures are not zero-initialized on both sides, so
      // explicit clears are required before reuse can safely read age/visibility.
      Vector4f clearColor = new Vector4f(0.0f, 0.0f, 0.0f, 0.0f);
      this.directReservoirBuffer.clearBothSides(clearColor);
      this.directSpatialReservoirBuffer.clear(clearColor);
      this.clearScatterTemporalHistory(clearColor);
      this.indirectInitialReservoirBuffer.clearBothSides(clearColor);
      this.indirectReservoirBuffer.clearBothSides(clearColor);
      this.reservoirHistoryDirty = false;
   }

   private void clearCompatDirectSoftAttachments() {
      Vector4f clearColor = new Vector4f(0.0f, 0.0f, 0.0f, 0.0f);
      this.compatDirectSoftBuffer.clear(clearColor);
      this.compatDirectSoftBuffer.swap();
      this.compatDirectSoftBuffer.clear(clearColor);
   }

   private void recordCpuPassTimes(long t0, long t1, long t2, long t3, long t4, long t5, long t6, long t7, long t8, long t9, long t10, long t11, long t12, long t13, long t14, long t15, long t16, long t17, long t18, long t19, long t20) {
      this.lastCpuLightTreeSamplingStageNanos = t1 - t0;
      this.lastCpuDIGenerateInitialSamplesNanos = t2 - t1;
      this.lastCpuDITemporalResamplingNanos = t3 - t2;
      this.lastCpuDISpatialResamplingNanos = t4 - t3;
      this.lastCpuDIShadeSamplesNanos = t5 - t4;
      this.lastCpuNRDPrepareInputsNanos = t6 - t5;
      this.lastCpuRELAXDiffuseTemporalAccumulationNanos = t7 - t6;
      this.lastCpuRELAXDiffuseHistoryFixNanos = t8 - t7;
      this.lastCpuRELAXDiffuseHistoryClampingNanos = t9 - t8;
      this.lastCpuRELAXDiffuseAntiFireflyNanos = t10 - t9;
      this.lastCpuRELAXDiffuseAtrousNanos = t11 - t10;
      this.lastCpuRELAXSpecularTemporalAccumulationNanos = t12 - t11;
      this.lastCpuRELAXSpecularHistoryFixNanos = t13 - t12;
      this.lastCpuRELAXSpecularHistoryClampingNanos = t14 - t13;
      this.lastCpuRELAXSpecularAntiFireflyNanos = t15 - t14;
      this.lastCpuRELAXSpecularAtrousNanos = t16 - t15;
      this.lastCpuReSTIRGINanos = t17 - t16;
      this.lastCpuIndirectDenoiseNanos = t18 - t17;
      this.lastCpuLightingAccumulationNanos = t19 - t18;
      this.lastCpuIndirectCompositeNanos = t20 - t19;
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
         "[Profiler] RTXDI/NRD CPU passes: LightTreeSamplingStage={}us DIGenerateInitialSamples={}us DITemporalResampling={}us DISpatialResampling={}us DIShadeSamples={}us NRDPrepareInputs={}us RELAXDiffuseTemporalAccumulation={}us RELAXDiffuseHistoryFix={}us RELAXDiffuseHistoryClamping={}us RELAXDiffuseAntiFirefly={}us RELAXDiffuseAtrous={}us RELAXSpecularTemporalAccumulation={}us RELAXSpecularHistoryFix={}us RELAXSpecularHistoryClamping={}us RELAXSpecularAntiFirefly={}us RELAXSpecularAtrous={}us ReSTIRGI={}us IndirectDenoise={}us LightingAccumulation={}us IndirectComposite={}us",
         this.toMicros(cpuPassNanos[lightTreeSamplingStageRegionIndex]),
         this.toMicros(cpuPassNanos[diGenerateInitialSamplesRegionIndex]),
         this.toMicros(cpuPassNanos[diTemporalResamplingRegionIndex]),
         this.toMicros(cpuPassNanos[diSpatialResamplingRegionIndex]),
         this.toMicros(cpuPassNanos[diShadeSamplesRegionIndex]),
         this.toMicros(cpuPassNanos[nrdPrepareInputsRegionIndex]),
         this.toMicros(cpuPassNanos[relaxDiffuseTemporalAccumulationRegionIndex]),
         this.toMicros(cpuPassNanos[relaxDiffuseHistoryFixRegionIndex]),
         this.toMicros(cpuPassNanos[relaxDiffuseHistoryClampingRegionIndex]),
         this.toMicros(cpuPassNanos[relaxDiffuseAntiFireflyRegionIndex]),
         this.toMicros(cpuPassNanos[relaxDiffuseAtrousRegionIndex]),
         this.toMicros(cpuPassNanos[relaxSpecularTemporalAccumulationRegionIndex]),
         this.toMicros(cpuPassNanos[relaxSpecularHistoryFixRegionIndex]),
         this.toMicros(cpuPassNanos[relaxSpecularHistoryClampingRegionIndex]),
         this.toMicros(cpuPassNanos[relaxSpecularAntiFireflyRegionIndex]),
         this.toMicros(cpuPassNanos[relaxSpecularAtrousRegionIndex]),
         this.toMicros(cpuPassNanos[restirGIRegionIndex]),
         this.toMicros(cpuPassNanos[indirectDenoiseRegionIndex]),
         this.toMicros(cpuPassNanos[lightingAccumulationRegionIndex]),
         this.toMicros(cpuPassNanos[indirectCompositeRegionIndex])
      );
      this.logGpuRenderProfile(gpuPassNanos);
   }

   private void logGpuRenderProfile(long[] gpuPassNanos) {
      long diTotal = gpuPassNanos[lightTreeSamplingStageRegionIndex]
         + gpuPassNanos[diGenerateInitialSamplesRegionIndex]
         + gpuPassNanos[diTemporalResamplingRegionIndex]
         + gpuPassNanos[diSpatialResamplingRegionIndex]
         + gpuPassNanos[diShadeSamplesRegionIndex];
      long relaxTotal = gpuPassNanos[nrdPrepareInputsRegionIndex]
         + gpuPassNanos[relaxDiffuseTemporalAccumulationRegionIndex]
         + gpuPassNanos[relaxDiffuseHistoryFixRegionIndex]
         + gpuPassNanos[relaxDiffuseHistoryClampingRegionIndex]
         + gpuPassNanos[relaxDiffuseAntiFireflyRegionIndex]
         + gpuPassNanos[relaxDiffuseAtrousRegionIndex]
         + gpuPassNanos[relaxSpecularTemporalAccumulationRegionIndex]
         + gpuPassNanos[relaxSpecularHistoryFixRegionIndex]
         + gpuPassNanos[relaxSpecularHistoryClampingRegionIndex]
         + gpuPassNanos[relaxSpecularAntiFireflyRegionIndex]
         + gpuPassNanos[relaxSpecularAtrousRegionIndex];
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
         "[Profiler] RTXDI/NRD GPU passes: LightTreeSamplingStage={}us DIGenerateInitialSamples={}us DITemporalResampling={}us DISpatialResampling={}us DIShadeSamples={}us NRDPrepareInputs={}us RELAXDiffuseTemporalAccumulation={}us RELAXDiffuseHistoryFix={}us RELAXDiffuseHistoryClamping={}us RELAXDiffuseAntiFirefly={}us RELAXDiffuseAtrous={}us RELAXSpecularTemporalAccumulation={}us RELAXSpecularHistoryFix={}us RELAXSpecularHistoryClamping={}us RELAXSpecularAntiFirefly={}us RELAXSpecularAtrous={}us ReSTIRGI={}us IndirectDenoise={}us LightingAccumulation={}us IndirectComposite={}us",
         this.toMicros(gpuPassNanos[lightTreeSamplingStageRegionIndex]),
         this.toMicros(gpuPassNanos[diGenerateInitialSamplesRegionIndex]),
         this.toMicros(gpuPassNanos[diTemporalResamplingRegionIndex]),
         this.toMicros(gpuPassNanos[diSpatialResamplingRegionIndex]),
         this.toMicros(gpuPassNanos[diShadeSamplesRegionIndex]),
         this.toMicros(gpuPassNanos[nrdPrepareInputsRegionIndex]),
         this.toMicros(gpuPassNanos[relaxDiffuseTemporalAccumulationRegionIndex]),
         this.toMicros(gpuPassNanos[relaxDiffuseHistoryFixRegionIndex]),
         this.toMicros(gpuPassNanos[relaxDiffuseHistoryClampingRegionIndex]),
         this.toMicros(gpuPassNanos[relaxDiffuseAntiFireflyRegionIndex]),
         this.toMicros(gpuPassNanos[relaxDiffuseAtrousRegionIndex]),
         this.toMicros(gpuPassNanos[relaxSpecularTemporalAccumulationRegionIndex]),
         this.toMicros(gpuPassNanos[relaxSpecularHistoryFixRegionIndex]),
         this.toMicros(gpuPassNanos[relaxSpecularHistoryClampingRegionIndex]),
         this.toMicros(gpuPassNanos[relaxSpecularAntiFireflyRegionIndex]),
         this.toMicros(gpuPassNanos[relaxSpecularAtrousRegionIndex]),
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
            .append(this.directAtrousStepSizes[i])
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
         this.directAtrousStepSizes[worstPass],
         this.toMicros(worstNanos)
      );
   }

   private long[] getCpuPassNanos() {
      return new long[]{
         this.lastCpuLightTreeSamplingStageNanos,
         this.lastCpuDIGenerateInitialSamplesNanos,
         this.lastCpuDITemporalResamplingNanos,
         this.lastCpuDISpatialResamplingNanos,
         this.lastCpuDIShadeSamplesNanos,
         this.lastCpuNRDPrepareInputsNanos,
         this.lastCpuRELAXDiffuseTemporalAccumulationNanos,
         this.lastCpuRELAXDiffuseHistoryFixNanos,
         this.lastCpuRELAXDiffuseHistoryClampingNanos,
         this.lastCpuRELAXDiffuseAntiFireflyNanos,
         this.lastCpuRELAXDiffuseAtrousNanos,
         this.lastCpuRELAXSpecularTemporalAccumulationNanos,
         this.lastCpuRELAXSpecularHistoryFixNanos,
         this.lastCpuRELAXSpecularHistoryClampingNanos,
         this.lastCpuRELAXSpecularAntiFireflyNanos,
         this.lastCpuRELAXSpecularAtrousNanos,
         this.lastCpuReSTIRGINanos,
         this.lastCpuIndirectDenoiseNanos,
         this.lastCpuLightingAccumulationNanos,
         this.lastCpuIndirectCompositeNanos
      };
   }

   private long[] getGpuPassNanos() {
      return new long[]{
         this.gpuTimerQuery.getTimeNanos(lightTreeSamplingStageRegionIndex),
         this.gpuTimerQuery.getTimeNanos(diGenerateInitialSamplesRegionIndex),
         this.gpuTimerQuery.getTimeNanos(diTemporalResamplingRegionIndex),
         this.gpuTimerQuery.getTimeNanos(diSpatialResamplingRegionIndex),
         this.gpuTimerQuery.getTimeNanos(diShadeSamplesRegionIndex),
         this.gpuTimerQuery.getTimeNanos(nrdPrepareInputsRegionIndex),
         this.gpuTimerQuery.getTimeNanos(relaxDiffuseTemporalAccumulationRegionIndex),
         this.gpuTimerQuery.getTimeNanos(relaxDiffuseHistoryFixRegionIndex),
         this.gpuTimerQuery.getTimeNanos(relaxDiffuseHistoryClampingRegionIndex),
         this.gpuTimerQuery.getTimeNanos(relaxDiffuseAntiFireflyRegionIndex),
         this.gpuTimerQuery.getTimeNanos(relaxDiffuseAtrousRegionIndex),
         this.gpuTimerQuery.getTimeNanos(relaxSpecularTemporalAccumulationRegionIndex),
         this.gpuTimerQuery.getTimeNanos(relaxSpecularHistoryFixRegionIndex),
         this.gpuTimerQuery.getTimeNanos(relaxSpecularHistoryClampingRegionIndex),
         this.gpuTimerQuery.getTimeNanos(relaxSpecularAntiFireflyRegionIndex),
         this.gpuTimerQuery.getTimeNanos(relaxSpecularAtrousRegionIndex),
         this.gpuTimerQuery.getTimeNanos(restirGIRegionIndex),
         this.gpuTimerQuery.getTimeNanos(indirectDenoiseRegionIndex),
         this.gpuTimerQuery.getTimeNanos(lightingAccumulationRegionIndex),
         this.gpuTimerQuery.getTimeNanos(indirectCompositeRegionIndex)
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
      return "DIShadeSamples+RELAXDiffuseHistoryFix+RELAXDiffuseHistoryClamping+RELAXDiffuseAtrous+IndirectDenoise";
   }

   private long toMicros(long nanos) {
      return nanos / 1_000L;
   }
}




