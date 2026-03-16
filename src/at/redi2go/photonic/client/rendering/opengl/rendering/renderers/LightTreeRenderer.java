package at.redi2go.photonic.client.rendering.opengl.rendering.renderers;

import at.redi2go.photonic.client.api.PhotonicsProperties;
import at.redi2go.photonic.client.rendering.opengl.objects.GLMemoryCollection;
import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.opengl.rendering.ColorFramebuffer;
import at.redi2go.photonic.client.rendering.opengl.rendering.PhotonicsShader;
import at.redi2go.photonic.client.rendering.opengl.rendering.RoutingFramebuffer;
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
   private static final int[] nrdAtrousStepSizes = new int[]{1, 2, 4, 8, 16};

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
   private int nrdAtrousIteration = 0;
   private boolean compatDirectSoftDirty = true;

   public LightTreeRenderer(WorldRegistry worldRegistry, float renderScale, PhotonicsProperties properties) {
      super(worldRegistry, renderScale);
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
      this.addTextureSampler(samplers, "stage_radiosity_direct", () -> this.lightingStageBuffer.getWriteAttachment("direct"));
      this.addTextureSampler(samplers, "stage_radiosity_handheld", () -> this.lightingStageBuffer.getWriteAttachment("handheld"));
      this.addTextureSampler(samplers, "stage_radiosity_indirect", () -> this.lightingStageBuffer.getWriteAttachment("indirect"));
      this.addTextureSampler(samplers, "prev_radiosity_position", () -> this.lightingBuffer.getReadAttachment("position"));
      this.addTextureSampler(samplers, "prev_radiosity_normal", () -> this.lightingBuffer.getReadAttachment("normal"));
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
      this.addTextureSampler(samplers, "nrd_denoised_direct", this::getResolvedDirectTexture);
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
   }

   @Override
   public void render() {
      if (this.samplingRenderer == null) {
         return;
      }

      this.ensureCompatDirectSoftCleared();
      this.lightingBuffer.swap();
      this.compatDirectSoftBuffer.swap();
      this.nrdSlowHistory.swap();
      this.nrdFastHistory.swap();
      this.nrdHistoryLength.swap();
      this.samplingRenderer.renderAll();
      this.nrdTemporalRenderer.renderAll();
      this.nrdHistoryFixRenderer.renderAll();
      this.nrdHistoryClampingRenderer.renderAll();
      this.nrdAntiFireflyRenderer.renderAll();

      for (this.nrdAtrousIteration = 0; this.nrdAtrousIteration < nrdAtrousStepSizes.length; this.nrdAtrousIteration++) {
         this.nrdAtrousRenderer.renderAll();
      }

      this.indirectAccumulationRenderer.renderAll();
      this.indirectDenoisingRenderer.renderAll();
      this.accumulationRenderer.renderAll();
      if (this.indirectRenderer != null) {
         this.indirectRenderer.renderAll();
      }
      this.worldRegistry.advanceLightBlendFrame();
   }

   @Override
   public Map<String, TextureObject> getAutomationTextures() {
      return Map.ofEntries(
         Map.entry("direct", this.getResolvedDirectTexture()),
         Map.entry("direct_soft", this.getCompatDirectSoftTexture()),
         Map.entry("direct_raw", this.lightingStageBuffer.getWriteAttachment("direct")),
         Map.entry("handheld", this.lightingBuffer.getWriteAttachment("handheld")),
         Map.entry("indirect", this.getResolvedIndirectTexture()),
         Map.entry("indirect_raw", this.lightingBuffer.getWriteAttachment("indirect")),
         Map.entry("lighting", this.nrdSlowHistory.getWriteAttachment("data")),
         Map.entry("stage_direct", this.lightingStageBuffer.getWriteAttachment("direct"))
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
   }

   private void createLightingBufferAttachments(ColorFramebuffer framebuffer) {
      framebuffer.createAttachment("position", "RGB32F", false);
      framebuffer.createAttachment("normal", "RGB16F", false);
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
      int iterationIndex = Math.max(0, Math.min(this.nrdAtrousIteration, nrdAtrousStepSizes.length - 1));
      return nrdAtrousStepSizes[iterationIndex];
   }

   private int getCurrentNrdAtrousIsLastPass() {
      return this.nrdAtrousIteration == nrdAtrousStepSizes.length - 1 ? 1 : 0;
   }

   private TextureObject getResolvedDirectTexture() {
      return this.nrdPong.getWriteAttachment("data");
   }

   private TextureObject getPreviousResolvedDirectTexture() {
      return this.lightingBuffer.getReadAttachment("direct");
   }

   private TextureObject getResolvedIndirectTexture() {
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
      this.compatDirectSoftBuffer.swap();
   }
}
