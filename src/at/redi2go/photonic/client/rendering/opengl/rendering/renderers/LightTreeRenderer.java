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
   private static final String nrdHistoryFixFragment = "lighttree/nrd_history_fix.fsh";
   private static final String nrdAtrousFragment = "lighttree/nrd_atrous.fsh";
   private static final String indirectAccumulationFragment = "lighttree/light_tree_indirect_accumulation.fsh";
   private static final String indirectDenoisingFragment = "lighttree/light_tree_indirect_denoising.fsh";
   private static final int profilerLogIntervalFrames = 60;
   private static final String[] gpuProfilerRegionNames = new String[]{
      "sampling", "nrdTemporal", "historyFix", "clamping", "antiFirefly", "atrous", "indirectAccum", "indirectDenoise", "accumulation", "indirect"
   };
   private static final String[] profilerPassNames = new String[]{
      "sampling", "nrdTemporal", "historyFix", "clamping", "antiFirefly", "atrous", "indirectAccum", "indirectDenoise", "accumulation", "indirect"
   };
   private static final int samplingRegionIndex = 0;
   private static final int nrdTemporalRegionIndex = 1;
   private static final int historyFixRegionIndex = 2;
   private static final int clampingRegionIndex = 3;
   private static final int antiFireflyRegionIndex = 4;
   private static final int atrousRegionIndex = 5;
   private static final int indirectAccumRegionIndex = 6;
   private static final int indirectDenoiseRegionIndex = 7;
   private static final int accumulationRegionIndex = 8;
   private static final int indirectRegionIndex = 9;

   private final ColorFramebuffer lightingBuffer;
   private final ColorFramebuffer lightingStageBuffer;
   private final ColorFramebuffer compatDirectSoftBuffer;
   private final ColorFramebuffer nrdSlowHistory;
   private final ColorFramebuffer nrdFastHistory;
   private final ColorFramebuffer nrdHistoryLength;
   private final ColorFramebuffer nrdPing;
   private final ColorFramebuffer nrdPong;
   private final ColorFramebuffer nrdHistoryFixBuffer;
   private final ColorFramebuffer indirectDenoisedBuffer;
   private final RoutingFramebuffer samplingFramebuffer;
   private final RoutingFramebuffer nrdTemporalFramebuffer;
   private final RoutingFramebuffer nrdHistoryFixFramebuffer;
   private final RoutingFramebuffer nrdHistoryClampingFramebuffer;
   private final RoutingFramebuffer nrdAntiFireflyFramebuffer;
   private final RoutingFramebuffer nrdAtrousFramebuffer;
   private final RoutingFramebuffer indirectAccumulationFramebuffer;
   private final RoutingFramebuffer indirectDenoisingFramebuffer;
   private final RoutingFramebuffer positionWriteFramebuffer;
   @Nullable
   private CompositeRenderer samplingRenderer;
   @Nullable
   private CompositeRenderer nrdTemporalRenderer;
   @Nullable
   private CompositeRenderer nrdHistoryFixRenderer;
   @Nullable
   private CompositeRenderer nrdHistoryClampingRenderer;
   @Nullable
   private CompositeRenderer nrdAntiFireflyRenderer;
   @Nullable
   private CompositeRenderer nrdAtrousRenderer;
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
   private final int[] nrdAtrousStepSizes;
   private int nrdAtrousIteration = 0;
   private boolean compatDirectSoftDirty = true;
   private int profilerFrameCounter = 0;
   private long lastCpuSamplingNanos;
   private long lastCpuNrdTemporalNanos;
   private long lastCpuHistoryFixNanos;
   private long lastCpuClampingNanos;
   private long lastCpuAntiFireflyNanos;
   private long lastCpuAtrousNanos;
   private long lastCpuIndirectAccumNanos;
   private long lastCpuIndirectDenoiseNanos;
   private long lastCpuAccumulationNanos;
   private long lastCpuIndirectNanos;

   public LightTreeRenderer(WorldRegistry worldRegistry, float renderScale, PhotonicsProperties properties) {
      super(worldRegistry, renderScale);
      this.nrdAtrousStepSizes = resolveNrdAtrousStepSizes(properties);
      this.lightingBuffer = new ColorFramebuffer(renderScale);
      this.createLightingBufferAttachments(this.lightingBuffer);
      this.lightingStageBuffer = new ColorFramebuffer(renderScale);
      this.createLightingStageAttachments(this.lightingStageBuffer);
      this.compatDirectSoftBuffer = new ColorFramebuffer(renderScale);
      this.compatDirectSoftBuffer.createAttachment("direct_soft_compat", "RGBA16F", false);
      this.nrdSlowHistory = this.createNrdHistoryFramebuffer(renderScale, "RGBA16F");
      this.nrdFastHistory = this.createNrdHistoryFramebuffer(renderScale, "RGBA16F");
      this.nrdHistoryLength = this.createNrdHistoryFramebuffer(renderScale, "R16F");
      this.nrdPing = this.createNrdHistoryFramebuffer(renderScale, "RGBA16F");
      this.nrdPong = this.createNrdHistoryFramebuffer(renderScale, "RGBA16F");
      this.nrdHistoryFixBuffer = new ColorFramebuffer(renderScale);
      this.nrdHistoryFixBuffer.createAttachment("data", "RGBA16F", false);
      this.indirectDenoisedBuffer = new ColorFramebuffer(renderScale);
      this.indirectDenoisedBuffer.createAttachment("data", "RGBA16F", false);
      this.samplingFramebuffer = this.createSamplingFramebuffer();
      this.nrdTemporalFramebuffer = this.createNrdTemporalFramebuffer();
      this.nrdHistoryFixFramebuffer = this.createNrdHistoryFixFramebuffer();
      this.nrdHistoryClampingFramebuffer = this.createNrdHistoryClampingFramebuffer();
      this.nrdAntiFireflyFramebuffer = this.createNrdAntiFireflyFramebuffer();
      this.nrdAtrousFramebuffer = this.createNrdAtrousFramebuffer();
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
      this.samplingRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("lighttree/light_tree_sampling.fsh", "common/screen.vsh", this.memoryCollection, this.samplingFramebuffer))
      );
      this.nrdTemporalRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("lighttree/nrd_temporal_accumulation.fsh", "common/screen.vsh", this.memoryCollection, this.nrdTemporalFramebuffer))
      );
      this.nrdHistoryFixRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(nrdHistoryFixFragment, "common/screen.vsh", this.memoryCollection, this.nrdHistoryFixFramebuffer))
      );
      this.nrdHistoryClampingRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("lighttree/nrd_history_clamping.fsh", "common/screen.vsh", this.memoryCollection, this.nrdHistoryClampingFramebuffer))
      );
      this.nrdAntiFireflyRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("lighttree/nrd_anti_firefly.fsh", "common/screen.vsh", this.memoryCollection, this.nrdAntiFireflyFramebuffer))
      );
      this.nrdAtrousRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader(nrdAtrousFragment, "common/screen.vsh", this.memoryCollection, this.nrdAtrousFramebuffer))
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
      this.addTextureSampler(samplers, "radiosity_direct", this::getResolvedDirectTexture);
      this.addTextureSampler(samplers, "radiosity_direct_soft", this::getCompatDirectSoftTexture);
      this.addTextureSampler(samplers, "radiosity_lighting", () -> this.nrdSlowHistory.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "radiosity_lighting_variance", () -> this.nrdFastHistory.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "radiosity_handheld", () -> this.lightingBuffer.getWriteAttachment("handheld"));
      this.addTextureSampler(samplers, "radiosity_indirect", () -> this.lightingBuffer.getWriteAttachment("indirect"));
      this.addTextureSampler(samplers, "radiosity_indirect_variance", () -> this.lightingBuffer.getWriteAttachment("indirect_variance"));
      this.addTextureSampler(samplers, "radiosity_indirect_resolved", this::getResolvedIndirectTexture);
      this.addTextureSampler(samplers, "stage_radiosity_position", () -> this.lightingStageBuffer.getWriteAttachment("position"));
      this.addTextureSampler(samplers, "stage_radiosity_normal", () -> this.lightingStageBuffer.getWriteAttachment("normal"));
      this.addTextureSampler(samplers, "stage_radiosity_mapped_normal", () -> this.lightingStageBuffer.getWriteAttachment("mapped_normal"));
      this.addTextureSampler(samplers, "stage_radiosity_direct", () -> this.lightingStageBuffer.getWriteAttachment("direct"));
      this.addTextureSampler(samplers, "stage_radiosity_handheld", () -> this.lightingStageBuffer.getWriteAttachment("handheld"));
      this.addTextureSampler(samplers, "stage_radiosity_indirect", () -> this.lightingStageBuffer.getWriteAttachment("indirect"));
      this.addTextureSampler(samplers, "prev_radiosity_position", () -> this.lightingBuffer.getReadAttachment("position"));
      this.addTextureSampler(samplers, "prev_radiosity_normal", () -> this.lightingBuffer.getReadAttachment("normal"));
      this.addTextureSampler(samplers, "prev_radiosity_mapped_normal", () -> this.lightingBuffer.getReadAttachment("mapped_normal"));
      this.addTextureSampler(samplers, "prev_radiosity_direct", this::getPreviousResolvedDirectTexture);
      this.addTextureSampler(samplers, "prev_radiosity_direct_soft", this::getPreviousCompatDirectSoftTexture);
      this.addTextureSampler(samplers, "prev_radiosity_lighting", () -> this.nrdSlowHistory.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_radiosity_lighting_variance", () -> this.nrdFastHistory.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_radiosity_handheld", () -> this.lightingBuffer.getReadAttachment("handheld"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect", () -> this.lightingBuffer.getReadAttachment("indirect"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect_variance", () -> this.lightingBuffer.getReadAttachment("indirect_variance"));
      this.addTextureSampler(samplers, "prev_nrd_diff_slow", () -> this.nrdSlowHistory.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_nrd_diff_fast", () -> this.nrdFastHistory.getReadAttachment("data"));
      this.addTextureSampler(samplers, "prev_nrd_history_length", () -> this.nrdHistoryLength.getReadAttachment("data"));
      this.addTextureSampler(samplers, "nrd_diff_input", () -> this.nrdPing.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_history_length_tex", () -> this.nrdHistoryLength.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_diff_slow_input", () -> this.nrdHistoryFixBuffer.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_diff_fast_input", () -> this.nrdPong.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_diff_noisy_input", () -> this.lightingStageBuffer.getWriteAttachment("direct"));
      this.addTextureSampler(samplers, "nrd_anti_firefly_input", () -> this.nrdSlowHistory.getWriteAttachment("data"));
      this.addTextureSampler(samplers, "nrd_diff_variance_input", this::getCurrentNrdAtrousInputTexture);
   }

   @Override
   public void registerCustomUniforms(DynamicUniformHolder uniforms) {
      uniforms.uniform1i("ph_light_tree_node_count", () -> this.worldRegistry.getLightRegistry().getLightTreeNodeCount(), updater -> {
         if (updater != null) {
            updater.run();
         }
      });
      uniforms.uniform1i("nrd_atrous_step_size", this::getCurrentNrdAtrousStepSize, updater -> {
         if (updater != null) {
            updater.run();
         }
      });
      uniforms.uniform1i("nrd_atrous_is_last_pass", this::getCurrentNrdAtrousIsLastPass, updater -> {
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
      if (this.samplingRenderer == null) {
         return;
      }

      this.resolveGpuProfile();
      this.advanceGpuProfileFrame();
      this.ensureCompatDirectSoftCleared();
      this.lightingBuffer.swap();
      this.compatDirectSoftBuffer.swap();
      this.nrdSlowHistory.swap();
      this.nrdFastHistory.swap();
      this.nrdHistoryLength.swap();
      long t0 = System.nanoTime();
      this.renderProfiled(samplingRegionIndex, this.samplingRenderer);
      long t1 = System.nanoTime();
      this.renderProfiled(nrdTemporalRegionIndex, this.nrdTemporalRenderer);
      long t2 = System.nanoTime();
      this.renderProfiled(historyFixRegionIndex, this.nrdHistoryFixRenderer);
      long t3 = System.nanoTime();
      this.renderProfiled(clampingRegionIndex, this.nrdHistoryClampingRenderer);
      long t4 = System.nanoTime();
      this.renderProfiled(antiFireflyRegionIndex, this.nrdAntiFireflyRenderer);
      long t5 = System.nanoTime();
      this.renderAtrousProfiled();
      long t6 = System.nanoTime();
      this.renderProfiled(indirectAccumRegionIndex, this.indirectAccumulationRenderer);
      long t7 = System.nanoTime();
      this.renderProfiled(indirectDenoiseRegionIndex, this.indirectDenoisingRenderer);
      long t8 = System.nanoTime();
      this.renderProfiled(accumulationRegionIndex, this.accumulationRenderer);
      long t9 = System.nanoTime();
      this.renderProfiled(indirectRegionIndex, this.indirectRenderer);
      long t10 = System.nanoTime();
      this.recordCpuPassTimes(t0, t1, t2, t3, t4, t5, t6, t7, t8, t9, t10);
      this.worldRegistry.advanceLightBlendFrame();
      this.logRenderProfileIfNeeded(t10 - t0);
   }

   @Override
   public Map<String, TextureObject> getAutomationTextures() {
      return Map.ofEntries(
         Map.entry("direct", this.getResolvedDirectTexture()),
         Map.entry("direct_soft", this.getCompatDirectSoftTexture()),
         Map.entry("direct_denoised", this.getResolvedDirectTexture()),
         Map.entry("direct_raw", this.lightingStageBuffer.getWriteAttachment("direct")),
         Map.entry("handheld", this.lightingBuffer.getWriteAttachment("handheld")),
         Map.entry("indirect", this.getResolvedIndirectTexture()),
         Map.entry("indirect_raw", this.lightingBuffer.getWriteAttachment("indirect")),
         Map.entry("lighting", this.nrdSlowHistory.getWriteAttachment("data")),
         Map.entry("stage_direct", this.lightingStageBuffer.getWriteAttachment("direct")),
         Map.entry("stage_lighting", this.lightingStageBuffer.getWriteAttachment("direct")),
         Map.entry("stage_indirect", this.lightingStageBuffer.getWriteAttachment("indirect"))
      );
   }

   @Override
   public void recalculateSizes() {
      this.nrdHistoryFixBuffer.updatePerFrame();
      this.indirectDenoisedBuffer.updatePerFrame();
      this.recalculateRenderer(this.samplingRenderer);
      this.recalculateRenderer(this.nrdTemporalRenderer);
      this.recalculateRenderer(this.nrdHistoryFixRenderer);
      this.recalculateRenderer(this.nrdHistoryClampingRenderer);
      this.recalculateRenderer(this.nrdAntiFireflyRenderer);
      this.recalculateRenderer(this.nrdAtrousRenderer);
      this.recalculateRenderer(this.indirectAccumulationRenderer);
      this.recalculateRenderer(this.indirectDenoisingRenderer);
      this.recalculateRenderer(this.accumulationRenderer);
      this.recalculateRenderer(this.indirectRenderer);
      this.compatDirectSoftDirty = true;
   }

   @Override
   public void free() {
      this.samplingFramebuffer.destroy();
      this.nrdTemporalFramebuffer.destroy();
      this.nrdHistoryFixFramebuffer.destroy();
      this.nrdHistoryClampingFramebuffer.destroy();
      this.nrdAntiFireflyFramebuffer.destroy();
      this.nrdAtrousFramebuffer.destroy();
      this.indirectAccumulationFramebuffer.destroy();
      this.indirectDenoisingFramebuffer.destroy();
      this.positionWriteFramebuffer.destroy();
      this.lightingBuffer.destroy();
      this.lightingStageBuffer.destroy();
      this.compatDirectSoftBuffer.destroy();
      this.nrdSlowHistory.destroy();
      this.nrdFastHistory.destroy();
      this.nrdHistoryLength.destroy();
      this.nrdPing.destroy();
      this.nrdPong.destroy();
      this.nrdHistoryFixBuffer.destroy();
      this.indirectDenoisedBuffer.destroy();
      this.destroyRenderer(this.samplingRenderer);
      this.destroyRenderer(this.nrdTemporalRenderer);
      this.destroyRenderer(this.nrdHistoryFixRenderer);
      this.destroyRenderer(this.nrdHistoryClampingRenderer);
      this.destroyRenderer(this.nrdAntiFireflyRenderer);
      this.destroyRenderer(this.nrdAtrousRenderer);
      this.destroyRenderer(this.indirectAccumulationRenderer);
      this.destroyRenderer(this.indirectDenoisingRenderer);
      this.destroyRenderer(this.accumulationRenderer);
      this.destroyRenderer(this.indirectRenderer);
      this.destroyGpuTimerQuery();
   }

   private void createLightingBufferAttachments(ColorFramebuffer framebuffer) {
      framebuffer.createAttachment("position", "RGB32F", false);
      framebuffer.createAttachment("normal", "RGB16F", false);
      framebuffer.createAttachment("mapped_normal", "RGB16F", false);
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
      framebuffer.createAttachment("direct", "RGBA16F", false);
      framebuffer.createAttachment("handheld", "RGBA16F", false);
      framebuffer.createAttachment("indirect", "RGBA16F", false);
   }

   private ColorFramebuffer createNrdHistoryFramebuffer(float renderScale, String format) {
      ColorFramebuffer framebuffer = new ColorFramebuffer(renderScale);
      framebuffer.createAttachment("data", format, false);
      return framebuffer;
   }

   private RoutingFramebuffer createSamplingFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingStageBuffer.getWriteAttachment("position"),
         () -> this.lightingStageBuffer.getWriteAttachment("normal"),
         () -> this.lightingStageBuffer.getWriteAttachment("mapped_normal"),
         () -> this.lightingStageBuffer.getWriteAttachment("direct"),
         () -> this.lightingStageBuffer.getWriteAttachment("handheld"),
         () -> this.lightingStageBuffer.getWriteAttachment("indirect")
      );
   }

   private RoutingFramebuffer createNrdTemporalFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.nrdPing.getWriteAttachment("data"),
         () -> this.nrdPong.getWriteAttachment("data"),
         () -> this.nrdHistoryLength.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createNrdHistoryFixFramebuffer() {
      return this.createRoutingFramebuffer(() -> this.nrdHistoryFixBuffer.getWriteAttachment("data"));
   }

   private RoutingFramebuffer createNrdHistoryClampingFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.nrdSlowHistory.getWriteAttachment("data"),
         () -> this.nrdFastHistory.getWriteAttachment("data"),
         () -> this.nrdHistoryLength.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createNrdAntiFireflyFramebuffer() {
      return this.createRoutingFramebuffer(() -> this.nrdPing.getWriteAttachment("data"));
   }

   private RoutingFramebuffer createNrdAtrousFramebuffer() {
      return this.createRoutingFramebuffer(this::getCurrentNrdAtrousOutputTexture);
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

   private boolean shouldUseStageGeometry() {
      return this.isCurrentPhotonicsFragment(nrdHistoryFixFragment) || this.isCurrentPhotonicsFragment(nrdAtrousFragment);
   }

   private TextureObject getCurrentNrdAtrousInputTexture() {
      if ((this.nrdAtrousIteration & 1) == 0) {
         return this.nrdPing.getWriteAttachment("data");
      }
      return this.nrdPong.getWriteAttachment("data");
   }

   private TextureObject getCurrentNrdAtrousOutputTexture() {
      if ((this.nrdAtrousIteration & 1) == 0) {
         return this.nrdPong.getWriteAttachment("data");
      }
      return this.nrdPing.getWriteAttachment("data");
   }

   private int getCurrentNrdAtrousStepSize() {
      int iterationIndex = Math.max(0, Math.min(this.nrdAtrousIteration, this.nrdAtrousStepSizes.length - 1));
      return this.nrdAtrousStepSizes[iterationIndex];
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

   private int getCurrentNrdAtrousIsLastPass() {
      return this.nrdAtrousIteration == this.nrdAtrousStepSizes.length - 1 ? 1 : 0;
   }

   private static int[] resolveNrdAtrousStepSizes(PhotonicsProperties properties) {
      int passCount = Math.clamp(properties.getNrdAtrousPasses(), 1, 7);
      return switch (passCount) {
         case 1 -> new int[]{4};
         case 2 -> new int[]{1, 8};
         case 3 -> new int[]{1, 4, 16};
         case 4 -> new int[]{1, 2, 8, 16};
         case 5 -> new int[]{1, 2, 4, 8, 16};
         case 6 -> new int[]{1, 2, 4, 8, 16, 16};
         case 7 -> new int[]{1, 2, 4, 8, 16, 16, 16};
         default -> throw new IllegalStateException("Unexpected NRD atrous pass count: " + passCount);
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

   private void renderAtrousProfiled() {
      this.beginGpuRegion(atrousRegionIndex);
      for (this.nrdAtrousIteration = 0; this.nrdAtrousIteration < this.nrdAtrousStepSizes.length; this.nrdAtrousIteration++) {
         this.nrdAtrousRenderer.renderAll();
      }
      this.endGpuRegion(atrousRegionIndex);
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
      return this.nrdPong.getWriteAttachment("data");
   }

   private TextureObject getPreviousResolvedDirectTexture() {
      return this.lightingBuffer.getReadAttachment("direct");
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

   private void recordCpuPassTimes(long t0, long t1, long t2, long t3, long t4, long t5, long t6, long t7, long t8, long t9, long t10) {
      this.lastCpuSamplingNanos = t1 - t0;
      this.lastCpuNrdTemporalNanos = t2 - t1;
      this.lastCpuHistoryFixNanos = t3 - t2;
      this.lastCpuClampingNanos = t4 - t3;
      this.lastCpuAntiFireflyNanos = t5 - t4;
      this.lastCpuAtrousNanos = t6 - t5;
      this.lastCpuIndirectAccumNanos = t7 - t6;
      this.lastCpuIndirectDenoiseNanos = t8 - t7;
      this.lastCpuAccumulationNanos = t9 - t8;
      this.lastCpuIndirectNanos = t10 - t9;
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
      Photonic.info(
         "[Profiler] LightTree summary: cpuTotal={}ms gpuTotal={}ms worstCpu={}={}ms worstGpu={}={}ms reloadActive={} blendFactor={} blendRegions={} tracedLights={}/{} treeNodes={} stageGeometry={}",
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
         this.describeStageGeometryUsage()
      );
      Photonic.info(
         "[Profiler] LightTree CPU passes: sampling={}ms nrdTemporal={}ms historyFix={}ms clamping={}ms antiFirefly={}ms atrous={}ms indirectAccum={}ms indirectDenoise={}ms accumulation={}ms indirect={}ms",
         this.toMillis(cpuPassNanos[samplingRegionIndex]),
         this.toMillis(cpuPassNanos[nrdTemporalRegionIndex]),
         this.toMillis(cpuPassNanos[historyFixRegionIndex]),
         this.toMillis(cpuPassNanos[clampingRegionIndex]),
         this.toMillis(cpuPassNanos[antiFireflyRegionIndex]),
         this.toMillis(cpuPassNanos[atrousRegionIndex]),
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
      long denoiseTotal = gpuPassNanos[nrdTemporalRegionIndex]
         + gpuPassNanos[historyFixRegionIndex]
         + gpuPassNanos[clampingRegionIndex]
         + gpuPassNanos[antiFireflyRegionIndex]
         + gpuPassNanos[atrousRegionIndex];
      long directTotal = gpuPassNanos[samplingRegionIndex] + gpuPassNanos[accumulationRegionIndex];
      long indirectTotal = gpuPassNanos[indirectAccumRegionIndex]
         + gpuPassNanos[indirectDenoiseRegionIndex]
         + gpuPassNanos[indirectRegionIndex];
      Photonic.info(
         "[Profiler] LightTree GPU passes: sampling={}ms nrdTemporal={}ms historyFix={}ms clamping={}ms antiFirefly={}ms atrous={}ms indirectAccum={}ms indirectDenoise={}ms accumulation={}ms indirect={}ms",
         this.toMillis(gpuPassNanos[samplingRegionIndex]),
         this.toMillis(gpuPassNanos[nrdTemporalRegionIndex]),
         this.toMillis(gpuPassNanos[historyFixRegionIndex]),
         this.toMillis(gpuPassNanos[clampingRegionIndex]),
         this.toMillis(gpuPassNanos[antiFireflyRegionIndex]),
         this.toMillis(gpuPassNanos[atrousRegionIndex]),
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
         this.lastCpuSamplingNanos,
         this.lastCpuNrdTemporalNanos,
         this.lastCpuHistoryFixNanos,
         this.lastCpuClampingNanos,
         this.lastCpuAntiFireflyNanos,
         this.lastCpuAtrousNanos,
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
         this.gpuTimerQuery.getTimeNanos(samplingRegionIndex),
         this.gpuTimerQuery.getTimeNanos(nrdTemporalRegionIndex),
         this.gpuTimerQuery.getTimeNanos(historyFixRegionIndex),
         this.gpuTimerQuery.getTimeNanos(clampingRegionIndex),
         this.gpuTimerQuery.getTimeNanos(antiFireflyRegionIndex),
         this.gpuTimerQuery.getTimeNanos(atrousRegionIndex),
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
      return "historyFix+atrous";
   }

   private long toMillis(long nanos) {
      return nanos / 1_000_000L;
   }
}



