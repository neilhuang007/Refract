package at.redi2go.photonic.client.rendering.opengl.rendering.renderers;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.PhotonicsStorage;
import at.redi2go.photonic.client.api.PhotonicsProperties;
import at.redi2go.photonic.client.rendering.opengl.GpuTimerQuery;
import at.redi2go.photonic.client.rendering.opengl.objects.GLMemoryCollection;
import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.opengl.rendering.ColorFramebuffer;
import at.redi2go.photonic.client.rendering.opengl.rendering.PhotonicsShader;
import at.redi2go.photonic.client.rendering.opengl.rendering.RoutingFramebuffer;
import at.redi2go.photonic.client.rendering.world.LightRegistry;
import at.redi2go.photonic.client.rendering.world.WorldRegistry;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.function.Supplier;
import net.irisshaders.iris.gl.sampler.SamplerHolder;
import net.irisshaders.iris.gl.uniform.DynamicUniformHolder;
import net.irisshaders.iris.pipeline.CompositeRenderer;
import org.jetbrains.annotations.Nullable;
import org.joml.Vector4f;

public class LightTreeRenderer extends MainRenderer {
   private static final String directTemporalFragment = "lighttree/nrd_temporal_accumulation.fsh";
   private static final String directHistoryFixFragment = "lighttree/nrd_history_fix.fsh";
   private static final String directAtrousFragment = "lighttree/nrd_atrous.fsh";
   private static final String directHistoryClampingFragment = "lighttree/nrd_history_clamping.fsh";
   private static final String indirectAccumulationFragment = "lighttree/light_tree_indirect_accumulation.fsh";
   private static final String indirectDenoisingFragment = "lighttree/light_tree_indirect_denoising.fsh";
   private static final int profilerLogIntervalFrames = 60;
   private static final String[] gpuProfilerRegionNames = new String[]{
      "proposalSampling", "reuseResolve", "directFeatureExtract", "directTemporal", "directHistoryFix", "directHistoryClamping", "directAtrous", "indirectAccum", "indirectDenoise", "accumulation", "indirect"
   };
   private static final String[] profilerPassNames = new String[]{
      "proposalSampling", "reuseResolve", "directFeatureExtract", "directTemporal", "directHistoryFix", "directHistoryClamping", "directAtrous", "indirectAccum", "indirectDenoise", "accumulation", "indirect"
   };
   private static final int proposalSamplingRegionIndex = 0;
   private static final int reuseResolveRegionIndex = 1;
   private static final int directFeatureRegionIndex = 2;
   private static final int directTemporalRegionIndex = 3;
   private static final int directHistoryFixRegionIndex = 4;
   private static final int directHistoryClampingRegionIndex = 5;
   private static final int directAtrousRegionIndex = 6;
   private static final int indirectAccumRegionIndex = 7;
   private static final int indirectDenoiseRegionIndex = 8;
   private static final int accumulationRegionIndex = 9;
   private static final int indirectRegionIndex = 10;

   private final ColorFramebuffer lightingBuffer;
   private final ColorFramebuffer lightingStageBuffer;
   private final ColorFramebuffer motionVectorBuffer;
   private final ColorFramebuffer directReservoirBuffer;
   private final ColorFramebuffer directConfidenceBuffer;
   private final ColorFramebuffer compatDirectSoftBuffer;
   private final ColorFramebuffer directHistoryLengthBuffer;
   private final ColorFramebuffer directNoisyBuffer;
   private final ColorFramebuffer directResponsiveBuffer;
   private final ColorFramebuffer directSlowBuffer;
   private final ColorFramebuffer directFastBuffer;
   private final ColorFramebuffer directClampedSlowBuffer;
   private final ColorFramebuffer directClampedFastBuffer;
   private final ColorFramebuffer directDenoisedBuffer;
   private final ColorFramebuffer directAtrousPingBuffer;
   private final ColorFramebuffer indirectDenoisedBuffer;
   private final RoutingFramebuffer proposalFramebuffer;
   private final RoutingFramebuffer reuseResolveFramebuffer;
   private final RoutingFramebuffer directFeatureFramebuffer;
   private final RoutingFramebuffer directTemporalFramebuffer;
   private final RoutingFramebuffer directHistoryFixFramebuffer;
   private final RoutingFramebuffer directHistoryClampingFramebuffer;
   private final RoutingFramebuffer directAtrousFramebuffer;
   private final RoutingFramebuffer indirectAccumulationFramebuffer;
   private final RoutingFramebuffer indirectDenoisingFramebuffer;
   private final RoutingFramebuffer positionWriteFramebuffer;
   @Nullable
   private CompositeRenderer proposalRenderer;
   @Nullable
   private CompositeRenderer reuseResolveRenderer;
   @Nullable
   private CompositeRenderer directFeatureRenderer;
   @Nullable
   private CompositeRenderer directTemporalRenderer;
   @Nullable
   private CompositeRenderer directHistoryFixRenderer;
   @Nullable
   private CompositeRenderer directHistoryClampingRenderer;
   @Nullable
   private CompositeRenderer directAtrousRenderer;
   @Nullable
   private CompositeRenderer indirectAccumulationRenderer;
   @Nullable
   private CompositeRenderer indirectDenoisingRenderer;
   @Nullable
   private CompositeRenderer accumulationRenderer;
   @Nullable
   private CompositeRenderer indirectRenderer;
   @Nullable
   private final GpuTimerQuery gpuTimerQuery;
   private final int[] directAtrousStepSizes;
   private int directAtrousIteration = 0;
   private boolean compatDirectSoftDirty = true;
   private int profilerFrameCounter = 0;
   private long lastCpuProposalSamplingNanos;
   private long lastCpuReuseResolveNanos;
   private long lastCpuDirectFeatureNanos;
   private long lastCpuDirectTemporalNanos;
   private long lastCpuDirectHistoryFixNanos;
   private long lastCpuDirectHistoryClampingNanos;
   private long lastCpuDirectAtrousNanos;
   private long lastCpuIndirectAccumNanos;
   private long lastCpuIndirectDenoiseNanos;
   private long lastCpuAccumulationNanos;
   private long lastCpuIndirectNanos;

   public LightTreeRenderer(WorldRegistry worldRegistry, float renderScale, PhotonicsProperties properties) {
      super(worldRegistry, renderScale);
      this.directAtrousStepSizes = resolveDirectAtrousStepSizes(properties);
      this.lightingBuffer = new ColorFramebuffer(renderScale);
      this.createLightingBufferAttachments(this.lightingBuffer);
      this.lightingStageBuffer = new ColorFramebuffer(renderScale);
      this.createLightingStageAttachments(this.lightingStageBuffer);
      this.motionVectorBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directReservoirBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directConfidenceBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.compatDirectSoftBuffer = new ColorFramebuffer(renderScale);
      this.compatDirectSoftBuffer.createAttachment("direct_soft_compat", "RGBA16F", false);
      this.directHistoryLengthBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directNoisyBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directResponsiveBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directSlowBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directFastBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directClampedSlowBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directClampedFastBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directDenoisedBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.directAtrousPingBuffer = this.createDirectSignalFramebuffer(renderScale, "RGBA16F");
      this.indirectDenoisedBuffer = new ColorFramebuffer(renderScale);
      this.indirectDenoisedBuffer.createAttachment("data", "RGBA16F", false);
      this.proposalFramebuffer = this.createProposalFramebuffer();
      this.reuseResolveFramebuffer = this.createReuseResolveFramebuffer();
      this.directFeatureFramebuffer = this.createDirectFeatureFramebuffer();
      this.directTemporalFramebuffer = this.createDirectTemporalFramebuffer();
      this.directHistoryFixFramebuffer = this.createDirectHistoryFixFramebuffer();
      this.directHistoryClampingFramebuffer = this.createDirectHistoryClampingFramebuffer();
      this.directAtrousFramebuffer = this.createDirectAtrousFramebuffer();
      this.indirectAccumulationFramebuffer = this.createIndirectAccumulationFramebuffer();
      this.indirectDenoisingFramebuffer = this.createIndirectDenoisingFramebuffer();
      this.positionWriteFramebuffer = this.createPositionWriteFramebuffer();
      this.gpuTimerQuery = this.createGpuTimerQuery();
   }

   @Override
   protected GLMemoryCollection buildGlMemoryCollection() {
      GLMemoryCollection memoryCollection = super.buildGlMemoryCollection();
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getLightTreeMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getLightTreeIndicesMemoryManager());
      return memoryCollection;
   }

   @Override
   public void createCompositeRenderer(Function<List<PhotonicsShader>, CompositeRenderer> rendererCreator) {
      this.proposalRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("lighttree/light_tree_sampling.fsh", "common/screen.vsh", this.memoryCollection, this.proposalFramebuffer))
      );
      this.reuseResolveRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("lighttree/reuse_resolve.fsh", "common/screen.vsh", this.memoryCollection, this.reuseResolveFramebuffer))
      );
      this.directFeatureRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("lighttree/direct_feature_extract.fsh", "common/screen.vsh", this.memoryCollection, this.directFeatureFramebuffer))
      );
      this.directTemporalRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(directTemporalFragment, "common/screen.vsh", this.memoryCollection, this.directTemporalFramebuffer))
      );
      this.directHistoryFixRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(directHistoryFixFragment, "common/screen.vsh", this.memoryCollection, this.directHistoryFixFramebuffer))
      );
      this.directHistoryClampingRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(directHistoryClampingFragment, "common/screen.vsh", this.memoryCollection, this.directHistoryClampingFramebuffer))
      );
      this.directAtrousRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(directAtrousFragment, "common/screen.vsh", this.memoryCollection, this.directAtrousFramebuffer))
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
   }

   @Override
   public void registerCustomTextures(SamplerHolder samplers) {
      this.addTextureSampler(samplers, "radiosity_position", this::getCurrentGeometryPositionTexture);
      this.addTextureSampler(samplers, "radiosity_normal", this::getCurrentGeometryNormalTexture);
      this.addTextureSampler(samplers, "radiosity_mapped_normal", this::getCurrentMappedNormalTexture);
      this.addTextureSampler(samplers, "radiosity_material", this::getCurrentMaterialTexture);
      this.addTextureSampler(samplers, "radiosity_direct", this::getResolvedDirectTexture);
      this.addTextureSampler(samplers, "radiosity_reservoirs", () -> this.directReservoirBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "radiosity_direct_soft", this::getCompatDirectSoftTexture);
      this.addTextureSampler(samplers, "radiosity_handheld", () -> this.lightingBuffer.getWriteAttachment("handheld"));
      this.addTextureSampler(samplers, "radiosity_indirect", () -> this.lightingBuffer.getWriteAttachment("indirect"));
      this.addTextureSampler(samplers, "radiosity_indirect_variance", () -> this.lightingBuffer.getWriteAttachment("indirect_variance"));
      this.addTextureSampler(samplers, "radiosity_indirect_resolved", this::getResolvedIndirectTexture);
      this.addTextureSampler(samplers, "radiosity_motion", () -> this.motionVectorBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_confidence_input", () -> this.directConfidenceBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "stage_radiosity_position", () -> this.lightingStageBuffer.getWriteAttachment("position"));
      this.addTextureSampler(samplers, "stage_radiosity_normal", () -> this.lightingStageBuffer.getWriteAttachment("normal"));
      this.addTextureSampler(samplers, "stage_radiosity_mapped_normal", () -> this.lightingStageBuffer.getWriteAttachment("mapped_normal"));
      this.addTextureSampler(samplers, "stage_radiosity_material", () -> this.lightingStageBuffer.getWriteAttachment("material"));
      this.addTextureSampler(samplers, "stage_radiosity_direct", () -> this.lightingStageBuffer.getWriteAttachment("direct"));
      this.addTextureSampler(samplers, "stage_radiosity_handheld", () -> this.lightingStageBuffer.getWriteAttachment("handheld"));
      this.addTextureSampler(samplers, "stage_radiosity_indirect", () -> this.lightingStageBuffer.getWriteAttachment("indirect"));
      this.addTextureSampler(samplers, "prev_radiosity_position", () -> this.lightingBuffer.getReadAttachment("position"));
      this.addTextureSampler(samplers, "prev_radiosity_normal", () -> this.lightingBuffer.getReadAttachment("normal"));
      this.addTextureSampler(samplers, "prev_radiosity_mapped_normal", () -> this.lightingBuffer.getReadAttachment("mapped_normal"));
      this.addTextureSampler(samplers, "prev_radiosity_material", () -> this.lightingBuffer.getReadAttachment("material"));
      this.addTextureSampler(samplers, "prev_radiosity_direct", this::getPreviousResolvedDirectTexture);
      this.addTextureSampler(samplers, "prev_radiosity_reservoirs", () -> this.directReservoirBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_radiosity_direct_soft", this::getPreviousCompatDirectSoftTexture);
      this.addTextureSampler(samplers, "prev_radiosity_handheld", () -> this.lightingBuffer.getReadAttachment("handheld"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect", () -> this.lightingBuffer.getReadAttachment("indirect"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect_variance", () -> this.lightingBuffer.getReadAttachment("indirect_variance"));
      this.addTextureSampler(samplers, "prev_radiosity_motion", () -> this.motionVectorBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_direct_confidence_input", () -> this.directConfidenceBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "direct_noisy_input", () -> this.directNoisyBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_responsive_input", () -> this.directResponsiveBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_slow_input", () -> this.directSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_fast_input", () -> this.directFastBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "direct_history_length_input", () -> this.directHistoryLengthBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "prev_direct_noisy_input", () -> this.directNoisyBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_direct_responsive_input", () -> this.directResponsiveBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_direct_slow_input", () -> this.directSlowBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_direct_fast_input", () -> this.directFastBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_direct_history_length_input", () -> this.directHistoryLengthBuffer.getReadAttachment("data"));
      this.addTextureSampler(samplers, "direct_historyfix_input", () -> this.directResponsiveBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_diff_slow_input", () -> this.directSlowBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_diff_fast_input", () -> this.directFastBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_diff_noisy_input", () -> this.directNoisyBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_history_length_tex", () -> {
         if (this.isCurrentPhotonicsFragment(directTemporalFragment)) {
            return this.directHistoryLengthBuffer.getWriteAttachment("data");
         }
         return this.directHistoryLengthBuffer.getReadAttachment("data");
      });
      this.addTextureSampler(samplers, "direct_history_length_tex", () -> {
         if (this.isCurrentPhotonicsFragment(directTemporalFragment)) {
            return this.directHistoryLengthBuffer.getWriteAttachment("data");
         }
         return this.directHistoryLengthBuffer.getReadAttachment("data");
      });
      this.addTextureSampler(samplers, "direct_atrous_input", this::getCurrentDirectAtrousInputTexture);
   }

   @Override
   public void registerCustomUniforms(DynamicUniformHolder uniforms) {
      uniforms.uniform1i("ph_light_tree_node_count", () -> this.worldRegistry.getLightRegistry().getLightTreeNodeCount(), updater -> {
         if (updater != null) {
            updater.run();
         }
      });
      uniforms.uniform1i("direct_atrous_step_size", this::getCurrentDirectAtrousStepSize, updater -> {
         if (updater != null) {
            updater.run();
         }
      });
      uniforms.uniform1i("direct_atrous_is_last_pass", this::getCurrentDirectAtrousIsLastPass, updater -> {
         if (updater != null) {
            updater.run();
         }
      });
      uniforms.uniform1f("ph_direct_sample_budget_scale", this::getDirectSampleBudgetScale, updater -> {
         if (updater != null) {
            updater.run();
         }
      });
   }

   @Override
   public void render() {
      if (this.proposalRenderer == null) {
         return;
      }

      this.resolveGpuProfile();
      this.advanceGpuProfileFrame();
      this.ensureCompatDirectSoftCleared();
      this.lightingBuffer.swap();
      this.compatDirectSoftBuffer.swap();
      this.motionVectorBuffer.swap();
      this.directReservoirBuffer.swap();
      this.directConfidenceBuffer.swap();
      this.directHistoryLengthBuffer.swap();
      this.directNoisyBuffer.swap();
      this.directResponsiveBuffer.swap();
      this.directSlowBuffer.swap();
      this.directFastBuffer.swap();
      this.directClampedSlowBuffer.swap();
      this.directClampedFastBuffer.swap();
      this.directDenoisedBuffer.swap();
      this.directAtrousPingBuffer.swap();
      long t0 = System.nanoTime();
      this.renderProfiled(proposalSamplingRegionIndex, this.proposalRenderer);
      long t1 = System.nanoTime();
      this.renderProfiled(reuseResolveRegionIndex, this.reuseResolveRenderer);
      long t2 = System.nanoTime();
      this.renderProfiled(directFeatureRegionIndex, this.directFeatureRenderer);
      long t3 = System.nanoTime();
      this.renderProfiled(directTemporalRegionIndex, this.directTemporalRenderer);
      long t4 = System.nanoTime();
      this.renderProfiled(directHistoryFixRegionIndex, this.directHistoryFixRenderer);
      long t5 = System.nanoTime();
      this.renderProfiled(directHistoryClampingRegionIndex, this.directHistoryClampingRenderer);
      long t6 = System.nanoTime();
      this.renderDirectAtrousProfiled();
      long t7 = System.nanoTime();
      this.renderProfiled(indirectAccumRegionIndex, this.indirectAccumulationRenderer);
      long t8 = System.nanoTime();
      this.renderProfiled(indirectDenoiseRegionIndex, this.indirectDenoisingRenderer);
      long t9 = System.nanoTime();
      this.renderProfiled(accumulationRegionIndex, this.accumulationRenderer);
      long t10 = System.nanoTime();
      this.renderProfiled(indirectRegionIndex, this.indirectRenderer);
      long t11 = System.nanoTime();
      this.recordCpuPassTimes(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11);
      this.worldRegistry.advanceLightBlendFrame();
      this.logRenderProfileIfNeeded(t11 - t0);
   }

   @Override
   public Map<String, TextureObject> getAutomationTextures() {
      return Map.ofEntries(
         Map.entry("direct", this.getResolvedDirectTexture()),
         Map.entry("direct_reservoir", this.directReservoirBuffer.getWriteAttachment("data")),
         Map.entry("direct_soft", this.getCompatDirectSoftTexture()),
         Map.entry("direct_denoised", this.directDenoisedBuffer.getWriteAttachment("data")),
         Map.entry("direct_raw", this.lightingStageBuffer.getWriteAttachment("direct")),
         Map.entry("handheld", this.lightingBuffer.getWriteAttachment("handheld")),
         Map.entry("indirect", this.getResolvedIndirectTexture()),
         Map.entry("indirect_raw", this.lightingBuffer.getWriteAttachment("indirect")),
         Map.entry("lighting", this.directSlowBuffer.getWriteAttachment("data")),
         Map.entry("stage_direct", this.lightingStageBuffer.getWriteAttachment("direct")),
         Map.entry("stage_lighting", this.directResponsiveBuffer.getWriteAttachment("data")),
         Map.entry("stage_indirect", this.lightingStageBuffer.getWriteAttachment("indirect")),
         Map.entry("motion", this.motionVectorBuffer.getWriteAttachment("data"))
      );
   }

   @Override
   public void recalculateSizes() {
      this.directReservoirBuffer.updatePerFrame();
      this.directHistoryLengthBuffer.updatePerFrame();
      this.directNoisyBuffer.updatePerFrame();
      this.directConfidenceBuffer.updatePerFrame();
      this.directResponsiveBuffer.updatePerFrame();
      this.directSlowBuffer.updatePerFrame();
      this.directFastBuffer.updatePerFrame();
      this.directClampedSlowBuffer.updatePerFrame();
      this.directClampedFastBuffer.updatePerFrame();
      this.directAtrousPingBuffer.updatePerFrame();
      this.motionVectorBuffer.updatePerFrame();
      this.indirectDenoisedBuffer.updatePerFrame();
      this.recalculateRenderer(this.proposalRenderer);
      this.recalculateRenderer(this.reuseResolveRenderer);
      this.recalculateRenderer(this.directFeatureRenderer);
      this.recalculateRenderer(this.directTemporalRenderer);
      this.recalculateRenderer(this.directHistoryFixRenderer);
      this.recalculateRenderer(this.directHistoryClampingRenderer);
      this.recalculateRenderer(this.directAtrousRenderer);
      this.recalculateRenderer(this.indirectAccumulationRenderer);
      this.recalculateRenderer(this.indirectDenoisingRenderer);
      this.recalculateRenderer(this.accumulationRenderer);
      this.recalculateRenderer(this.indirectRenderer);
      this.compatDirectSoftDirty = true;
   }

   @Override
   public void free() {
      this.proposalFramebuffer.destroy();
      this.reuseResolveFramebuffer.destroy();
      this.directFeatureFramebuffer.destroy();
      this.directTemporalFramebuffer.destroy();
      this.directHistoryFixFramebuffer.destroy();
      this.directHistoryClampingFramebuffer.destroy();
      this.directAtrousFramebuffer.destroy();
      this.indirectAccumulationFramebuffer.destroy();
      this.indirectDenoisingFramebuffer.destroy();
      this.positionWriteFramebuffer.destroy();
      this.lightingBuffer.destroy();
      this.lightingStageBuffer.destroy();
      this.compatDirectSoftBuffer.destroy();
      this.motionVectorBuffer.destroy();
      this.directReservoirBuffer.destroy();
      this.directConfidenceBuffer.destroy();
      this.directHistoryLengthBuffer.destroy();
      this.directNoisyBuffer.destroy();
      this.directResponsiveBuffer.destroy();
      this.directSlowBuffer.destroy();
      this.directFastBuffer.destroy();
      this.directClampedSlowBuffer.destroy();
      this.directClampedFastBuffer.destroy();
      this.directDenoisedBuffer.destroy();
      this.directAtrousPingBuffer.destroy();
      this.indirectDenoisedBuffer.destroy();
      this.destroyRenderer(this.proposalRenderer);
      this.destroyRenderer(this.reuseResolveRenderer);
      this.destroyRenderer(this.directFeatureRenderer);
      this.destroyRenderer(this.directTemporalRenderer);
      this.destroyRenderer(this.directHistoryFixRenderer);
      this.destroyRenderer(this.directHistoryClampingRenderer);
      this.destroyRenderer(this.directAtrousRenderer);
      this.destroyRenderer(this.indirectAccumulationRenderer);
      this.destroyRenderer(this.indirectDenoisingRenderer);
      this.destroyRenderer(this.accumulationRenderer);
      this.destroyRenderer(this.indirectRenderer);
      this.destroyGpuTimerQuery();
   }

   private ColorFramebuffer createDirectSignalFramebuffer(float renderScale, String format) {
      ColorFramebuffer framebuffer = new ColorFramebuffer(renderScale);
      framebuffer.createAttachment("data", format, false);
      return framebuffer;
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
         () -> this.motionVectorBuffer.getWriteAttachment("data"),
         () -> this.directConfidenceBuffer.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createDirectHistoryFixFramebuffer() {
      return this.createRoutingFramebuffer(() -> this.directResponsiveBuffer.getWriteAttachment("data"));
   }

   private RoutingFramebuffer createDirectHistoryClampingFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.directClampedSlowBuffer.getWriteAttachment("data"),
         () -> this.directClampedFastBuffer.getWriteAttachment("data"),
         () -> this.directHistoryLengthBuffer.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createDirectAtrousFramebuffer() {
      return this.createRoutingFramebuffer(this::getCurrentDirectAtrousOutputTexture);
   }

   private void createLightingBufferAttachments(ColorFramebuffer framebuffer) {
      framebuffer.createAttachment("position", "RGB32F", false);
      framebuffer.createAttachment("normal", "RGB16F", false);
      framebuffer.createAttachment("mapped_normal", "RGB16F", false);
      framebuffer.createAttachment("material", "RGBA16F", false);
      framebuffer.createAttachment("direct", "RGBA16F", false);
      framebuffer.createAttachment("lighting", "RGBA32F", false);
      framebuffer.createAttachment("lighting_variance", "RGBA32F", false);
      framebuffer.createAttachment("handheld", "RGBA16F", false);
      framebuffer.createAttachment("indirect", "RGBA16F", false);
      framebuffer.createAttachment("indirect_variance", "RGBA32F", false);
   }

   private void createLightingStageAttachments(ColorFramebuffer framebuffer) {
      framebuffer.createAttachment("position", "RGB32F", false);
      framebuffer.createAttachment("normal", "RGB16F", false);
      framebuffer.createAttachment("mapped_normal", "RGB16F", false);
      framebuffer.createAttachment("material", "RGBA16F", false);
      framebuffer.createAttachment("direct", "RGBA16F", false);
      framebuffer.createAttachment("handheld", "RGBA16F", false);
      framebuffer.createAttachment("indirect", "RGBA16F", false);
   }

   private RoutingFramebuffer createProposalFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingStageBuffer.getWriteAttachment("position"),
         () -> this.lightingStageBuffer.getWriteAttachment("normal"),
         () -> this.lightingStageBuffer.getWriteAttachment("mapped_normal"),
         () -> this.directReservoirBuffer.getWriteAttachment("data"),
         () -> this.lightingStageBuffer.getWriteAttachment("handheld"),
         () -> this.lightingStageBuffer.getWriteAttachment("indirect")
      );
   }

   private RoutingFramebuffer createReuseResolveFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.directReservoirBuffer.getWriteAttachment("data"),
         () -> this.lightingStageBuffer.getWriteAttachment("direct")
      );
   }

   private RoutingFramebuffer createIndirectAccumulationFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingBuffer.getWriteAttachment("indirect"),
         () -> this.lightingBuffer.getWriteAttachment("indirect_variance"),
         () -> this.lightingBuffer.getWriteAttachment("handheld")
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
         () -> this.lightingBuffer.getWriteAttachment("material"),
         () -> this.lightingBuffer.getWriteAttachment("direct"),
         () -> this.compatDirectSoftBuffer.getWriteAttachment("direct_soft_compat")
      );
   }

   @SafeVarargs
   private final RoutingFramebuffer createRoutingFramebuffer(Supplier<TextureObject>... attachments) {
      RoutingFramebuffer framebuffer = new RoutingFramebuffer();
      for (Supplier<TextureObject> attachment : attachments) {
         framebuffer.addAttachment(attachment);
      }
      return framebuffer;
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

   private boolean shouldUseStageGeometry() {
      return this.isCurrentPhotonicsFragment(directHistoryFixFragment) || this.isCurrentPhotonicsFragment(directHistoryClampingFragment) || this.isCurrentPhotonicsFragment(directAtrousFragment);
   }

   private TextureObject getCurrentDirectAtrousInputTexture() {
      if (this.directAtrousIteration == 0) {
         return this.directClampedSlowBuffer.getWriteAttachment("data");
      }
      if ((this.directAtrousIteration & 1) == 1) {
         return this.directAtrousPingBuffer.getWriteAttachment("data");
      }
      return this.directDenoisedBuffer.getWriteAttachment("data");
   }

   private TextureObject getCurrentDirectAtrousOutputTexture() {
      if (this.directAtrousIteration == this.directAtrousStepSizes.length - 1) {
         return this.directDenoisedBuffer.getWriteAttachment("data");
      }
      if ((this.directAtrousIteration & 1) == 0) {
         return this.directAtrousPingBuffer.getWriteAttachment("data");
      }
      return this.directDenoisedBuffer.getWriteAttachment("data");
   }

   private int getCurrentDirectAtrousStepSize() {
      int iterationIndex = Math.max(0, Math.min(this.directAtrousIteration, this.directAtrousStepSizes.length - 1));
      return this.directAtrousStepSizes[iterationIndex];
   }

   private float getDirectSampleBudgetScale() {
      float blendFactor = this.worldRegistry.fetchLightBlendFactor();
      boolean lightReload = this.worldRegistry.fetchLightReload();
      boolean hasActiveBlend = this.worldRegistry.hasActiveLightBlend();
      int blendRegions = this.worldRegistry.getLightBlendRegionCount();
      LightRegistry lightRegistry = this.worldRegistry.getLightRegistry();
      float lightCoverage = 0.0f;
      if (lightRegistry.totalLights() > 0) {
         lightCoverage = Math.min(1.0f, (float) lightRegistry.lightCount() / (float) lightRegistry.totalLights());
      }

      float warmupScale = 0.25f + 0.75f * blendFactor;
      if (!lightReload && blendRegions == 0) {
         warmupScale = Math.max(warmupScale, 0.85f);
      }
      if (!lightReload && hasActiveBlend) {
         warmupScale = Math.min(warmupScale, 0.55f);
      }
      float residencyScale = 0.35f + 0.65f * lightCoverage;
      return Math.max(0.2f, Math.min(1.0f, warmupScale * residencyScale));
   }

   private int getCurrentDirectAtrousIsLastPass() {
      return this.directAtrousIteration == this.directAtrousStepSizes.length - 1 ? 1 : 0;
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

   @Nullable
   private GpuTimerQuery createGpuTimerQuery() {
      if (!PhotonicsStorage.PROFILER_ENABLED.value) {
         return null;
      }
      return new GpuTimerQuery(gpuProfilerRegionNames);
   }

   private void resolveGpuProfile() {
      if (this.gpuTimerQuery == null) {
         return;
      }
      this.gpuTimerQuery.resolve();
   }

   private void renderProfiled(int regionIndex, @Nullable CompositeRenderer renderer) {
      if (renderer == null) {
         return;
      }
      this.beginGpuRegion(regionIndex);
      renderer.renderAll();
      this.endGpuRegion(regionIndex);
   }

   private void renderDirectAtrousProfiled() {
      this.beginGpuRegion(directAtrousRegionIndex);
      for (this.directAtrousIteration = 0; this.directAtrousIteration < this.directAtrousStepSizes.length; this.directAtrousIteration++) {
         this.directAtrousRenderer.renderAll();
      }
      this.endGpuRegion(directAtrousRegionIndex);
   }

   private void beginGpuRegion(int regionIndex) {
      if (this.gpuTimerQuery == null) {
         return;
      }
      this.gpuTimerQuery.begin(regionIndex);
   }

   private void endGpuRegion(int regionIndex) {
      if (this.gpuTimerQuery == null) {
         return;
      }
      this.gpuTimerQuery.end(regionIndex);
   }

   private void destroyGpuTimerQuery() {
      if (this.gpuTimerQuery == null) {
         return;
      }
      this.gpuTimerQuery.destroy();
   }

   private TextureObject getResolvedDirectTexture() {
      if (PhotonicsStorage.DEBUG_DISABLE_DENOISER.value) {
         return this.lightingStageBuffer.getWriteAttachment("direct");
      }
      return this.directDenoisedBuffer.getWriteAttachment("data");
   }

   private TextureObject getPreviousResolvedDirectTexture() {
      if (PhotonicsStorage.DEBUG_DISABLE_DENOISER.value) {
         return this.lightingBuffer.getReadAttachment("direct");
      }
      return this.directDenoisedBuffer.getReadAttachment("data");
   }

   private TextureObject getResolvedIndirectTexture() {
      if (PhotonicsStorage.DEBUG_DISABLE_DENOISER.value) {
         return this.lightingBuffer.getWriteAttachment("indirect");
      }
      return this.indirectDenoisedBuffer.getWriteAttachment("data");
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

   private void ensureCompatDirectSoftCleared() {
      if (!this.compatDirectSoftDirty) {
         return;
      }
      this.clearCompatDirectSoftAttachments();
      this.compatDirectSoftDirty = false;
   }

   private void clearCompatDirectSoftAttachments() {
      Vector4f clearColor = new Vector4f(0.0f, 0.0f, 0.0f, 0.0f);
      this.compatDirectSoftBuffer.clear(clearColor);
      this.compatDirectSoftBuffer.swap();
      this.compatDirectSoftBuffer.clear(clearColor);
   }

   private void recordCpuPassTimes(long t0, long t1, long t2, long t3, long t4, long t5, long t6, long t7, long t8, long t9, long t10, long t11) {
      this.lastCpuProposalSamplingNanos = t1 - t0;
      this.lastCpuReuseResolveNanos = t2 - t1;
      this.lastCpuDirectFeatureNanos = t3 - t2;
      this.lastCpuDirectTemporalNanos = t4 - t3;
      this.lastCpuDirectHistoryFixNanos = t5 - t4;
      this.lastCpuDirectHistoryClampingNanos = t6 - t5;
      this.lastCpuDirectAtrousNanos = t7 - t6;
      this.lastCpuIndirectAccumNanos = t8 - t7;
      this.lastCpuIndirectDenoiseNanos = t9 - t8;
      this.lastCpuAccumulationNanos = t10 - t9;
      this.lastCpuIndirectNanos = t11 - t10;
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
      LightRegistry.LightTreeDiagnostics diagnostics = lightRegistry.getLightTreeDiagnostics();
      long totalGpuNanos = this.sumNanos(gpuPassNanos);
      Photonic.info(
         "[Profiler] LightTree summary: cpuTotal={}ms gpuTotal={}ms worstCpu={}={}ms worstGpu={}={}ms reloadActive={} blendFactor={} blendRegions={} tracedLights={}/{} treeNodes={} diagnostics={} stageGeometry={}",
         this.toMillis(totalCpuNanos),
         this.toMillis(totalGpuNanos),
         profilerPassNames[worstCpuIndex],
         this.toMillis(cpuPassNanos[worstCpuIndex]),
         profilerPassNames[worstGpuIndex],
         this.toMillis(gpuPassNanos[worstGpuIndex]),
         worldRegistry.fetchLightReload(),
         this.formatBlendFactor(worldRegistry.fetchLightBlendFactor()),
         worldRegistry.getLightBlendRegionCount(),
         lightRegistry.lightCount(),
         lightRegistry.totalLights(),
         lightRegistry.getLightTreeNodeCount(),
         diagnostics.describe(),
         this.describeStageGeometryUsage()
      );
      Photonic.info(
         "[Profiler] LightTree CPU passes: proposalSampling={}ms reuseResolve={}ms directFeatureExtract={}ms directTemporal={}ms directHistoryFix={}ms directHistoryClamping={}ms directAtrous={}ms indirectAccum={}ms indirectDenoise={}ms accumulation={}ms indirect={}ms",
         this.toMillis(cpuPassNanos[proposalSamplingRegionIndex]),
         this.toMillis(cpuPassNanos[reuseResolveRegionIndex]),
         this.toMillis(cpuPassNanos[directFeatureRegionIndex]),
         this.toMillis(cpuPassNanos[directTemporalRegionIndex]),
         this.toMillis(cpuPassNanos[directHistoryFixRegionIndex]),
         this.toMillis(cpuPassNanos[directHistoryClampingRegionIndex]),
         this.toMillis(cpuPassNanos[directAtrousRegionIndex]),
         this.toMillis(cpuPassNanos[indirectAccumRegionIndex]),
         this.toMillis(cpuPassNanos[indirectDenoiseRegionIndex]),
         this.toMillis(cpuPassNanos[accumulationRegionIndex]),
         this.toMillis(cpuPassNanos[indirectRegionIndex])
      );
      this.logGpuRenderProfile(gpuPassNanos);
   }

   private void logGpuRenderProfile(long[] gpuPassNanos) {
      if (this.gpuTimerQuery == null) {
         return;
      }
      long denoiseTotal = gpuPassNanos[directFeatureRegionIndex]
         + gpuPassNanos[directTemporalRegionIndex]
         + gpuPassNanos[directHistoryFixRegionIndex]
         + gpuPassNanos[directHistoryClampingRegionIndex]
         + gpuPassNanos[directAtrousRegionIndex];
      long directTotal = gpuPassNanos[proposalSamplingRegionIndex] + gpuPassNanos[reuseResolveRegionIndex] + gpuPassNanos[accumulationRegionIndex];
      long indirectTotal = gpuPassNanos[indirectAccumRegionIndex]
         + gpuPassNanos[indirectDenoiseRegionIndex]
         + gpuPassNanos[indirectRegionIndex];
      Photonic.info(
         "[Profiler] LightTree GPU passes: proposalSampling={}ms reuseResolve={}ms directFeatureExtract={}ms directTemporal={}ms directHistoryFix={}ms directHistoryClamping={}ms directAtrous={}ms indirectAccum={}ms indirectDenoise={}ms accumulation={}ms indirect={}ms",
         this.toMillis(gpuPassNanos[proposalSamplingRegionIndex]),
         this.toMillis(gpuPassNanos[reuseResolveRegionIndex]),
         this.toMillis(gpuPassNanos[directFeatureRegionIndex]),
         this.toMillis(gpuPassNanos[directTemporalRegionIndex]),
         this.toMillis(gpuPassNanos[directHistoryFixRegionIndex]),
         this.toMillis(gpuPassNanos[directHistoryClampingRegionIndex]),
         this.toMillis(gpuPassNanos[directAtrousRegionIndex]),
         this.toMillis(gpuPassNanos[indirectAccumRegionIndex]),
         this.toMillis(gpuPassNanos[indirectDenoiseRegionIndex]),
         this.toMillis(gpuPassNanos[accumulationRegionIndex]),
         this.toMillis(gpuPassNanos[indirectRegionIndex])
      );
      Photonic.info(
         "[Profiler] LightTree GPU buckets: direct={}ms denoise={}ms indirect={}ms directShare={} denoiseShare={} indirectShare={}",
         this.toMillis(directTotal),
         this.toMillis(denoiseTotal),
         this.toMillis(indirectTotal),
         this.formatShare(directTotal, gpuPassNanos),
         this.formatShare(denoiseTotal, gpuPassNanos),
         this.formatShare(indirectTotal, gpuPassNanos)
      );
   }

   private long[] getCpuPassNanos() {
      return new long[]{
         this.lastCpuProposalSamplingNanos,
         this.lastCpuReuseResolveNanos,
         this.lastCpuDirectFeatureNanos,
         this.lastCpuDirectTemporalNanos,
         this.lastCpuDirectHistoryFixNanos,
         this.lastCpuDirectHistoryClampingNanos,
         this.lastCpuDirectAtrousNanos,
         this.lastCpuIndirectAccumNanos,
         this.lastCpuIndirectDenoiseNanos,
         this.lastCpuAccumulationNanos,
         this.lastCpuIndirectNanos
      };
   }

   private long[] getGpuPassNanos() {
      if (this.gpuTimerQuery == null) {
         return new long[profilerPassNames.length];
      }
      return new long[]{
         this.gpuTimerQuery.getTimeNanos(proposalSamplingRegionIndex),
         this.gpuTimerQuery.getTimeNanos(reuseResolveRegionIndex),
         this.gpuTimerQuery.getTimeNanos(directFeatureRegionIndex),
         this.gpuTimerQuery.getTimeNanos(directTemporalRegionIndex),
         this.gpuTimerQuery.getTimeNanos(directHistoryFixRegionIndex),
         this.gpuTimerQuery.getTimeNanos(directHistoryClampingRegionIndex),
         this.gpuTimerQuery.getTimeNanos(directAtrousRegionIndex),
         this.gpuTimerQuery.getTimeNanos(indirectAccumRegionIndex),
         this.gpuTimerQuery.getTimeNanos(indirectDenoiseRegionIndex),
         this.gpuTimerQuery.getTimeNanos(accumulationRegionIndex),
         this.gpuTimerQuery.getTimeNanos(indirectRegionIndex)
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
      if (this.gpuTimerQuery != null) {
         this.gpuTimerQuery.nextFrame();
      }
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
      return "historyFix+historyClamping+atrous";
   }

   private long toMillis(long nanos) {
      return nanos / 1_000_000L;
   }
}




