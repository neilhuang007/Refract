package at.redi2go.photonic.client.rendering.opengl.rendering.renderers;

import at.redi2go.photonic.client.api.PhotonicsProperties;
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

public class OctrayRenderer extends MainRenderer {
   private static final boolean USE_DENOISED_DIRECT_OUTPUT = true;
   private final ColorFramebuffer lightingBuffer;
   private final ColorFramebuffer lightingStageBuffer;
   private final ColorFramebuffer compatDirectSoftBuffer;
   private final RoutingFramebuffer samplingFramebuffer;
   private final RoutingFramebuffer lightingPassFramebuffer;
   private final RoutingFramebuffer accumulationFramebuffer;
   private final RoutingFramebuffer giCopyFramebuffer;
   @Nullable
   private CompositeRenderer lightingRenderer;
   @Nullable
   private CompositeRenderer indirectRenderer;
   @Nullable
   private final ColorFramebuffer denoisingBuffer;
   @Nullable
   private CompositeRenderer denoisingRenderer;
   @Nullable
   private final ColorFramebuffer indirectDenoisingBuffer;
   @Nullable
   private CompositeRenderer indirectDenoisingRenderer;
   private int atrousIteration = 0;
   private final int denoiserPasses;
   private boolean compatDirectSoftDirty = true;

   public OctrayRenderer(WorldRegistry worldRegistry, float renderScale, PhotonicsProperties properties) {
      super(worldRegistry, renderScale);
      this.denoiserPasses = properties.getRestirDenoiserPasses();
      this.lightingBuffer = new ColorFramebuffer(renderScale);
      this.createLightingAttachments(this.lightingBuffer);
      this.lightingStageBuffer = new ColorFramebuffer(renderScale);
      this.createLightingAttachments(this.lightingStageBuffer);
      this.compatDirectSoftBuffer = new ColorFramebuffer(renderScale);
      this.compatDirectSoftBuffer.createAttachment("direct_soft_compat", "RGBA16F", false);
      boolean handheldLightEnabled = properties.isHandheldLightEnabled().orElse(true);
      this.samplingFramebuffer = this.createSamplingFramebuffer();
      this.lightingPassFramebuffer = this.createLightingPassFramebuffer(handheldLightEnabled);
      this.accumulationFramebuffer = this.createAccumulationFramebuffer(handheldLightEnabled);
      this.giCopyFramebuffer = this.createGiCopyFramebuffer();
      if (this.denoiserPasses != 0) {
         this.denoisingBuffer = new ColorFramebuffer(renderScale);
         this.denoisingBuffer.createAttachment("color", "RGB16F", true);
         this.denoisingBuffer.createAttachment("variance", "R16F", true);
         this.indirectDenoisingBuffer = new ColorFramebuffer(renderScale);
         this.indirectDenoisingBuffer.createAttachment("color", "RGB16F", true);
         this.indirectDenoisingBuffer.createAttachment("variance", "R16F", true);
      } else {
         this.denoisingBuffer = null;
         this.indirectDenoisingBuffer = null;
      }
   }

   @Override
   public void createCompositeRenderer(Function<List<PhotonicsShader>, CompositeRenderer> rendererCreator) {
      this.lightingRenderer = rendererCreator.apply(
         List.of(
            new PhotonicsShader("restir/sampling.fsh", "common/screen.vsh", this.memoryCollection, this.samplingFramebuffer),
            new PhotonicsShader("restir/lighting.fsh", "common/screen.vsh", this.memoryCollection, this.lightingPassFramebuffer),
            new PhotonicsShader("restir/accumulation.fsh", "common/screen.vsh", this.memoryCollection, this.accumulationFramebuffer),
            new PhotonicsShader("restir/gi_copy.fsh", "common/screen.vsh", this.memoryCollection, this.giCopyFramebuffer)
         )
      );
      this.indirectRenderer = rendererCreator.apply(
         List.of(new PhotonicsShader("common/indirect.fsh", "common/screen.vsh", this.memoryCollection, null))
      );
      if (this.denoiserPasses != 0) {
         this.denoisingRenderer = rendererCreator.apply(
            List.of(new PhotonicsShader("restir/denoising.fsh", "common/screen.vsh", this.memoryCollection, this.denoisingBuffer, new int[]{0, 1}))
         );
         this.indirectDenoisingRenderer = rendererCreator.apply(
            List.of(new PhotonicsShader("restir/indirect_denoising.fsh", "common/screen.vsh", this.memoryCollection, this.indirectDenoisingBuffer, new int[]{0, 1}))
         );
      }
   }

   @Override
   public void registerCustomTextures(SamplerHolder samplers) {
      this.addTextureSampler(samplers, "radiosity_position", () -> this.lightingBuffer.getWriteAttachment("position"));
      this.addTextureSampler(samplers, "radiosity_normal", () -> this.lightingBuffer.getWriteAttachment("normal"));
      this.addTextureSampler(samplers, "radiosity_direct", this::getResolvedDirectTexture);
      this.addTextureSampler(samplers, "radiosity_direct_soft", this::getCompatDirectSoftTexture);
      this.addTextureSampler(samplers, "radiosity_reservoirs", () -> this.lightingBuffer.getWriteAttachment("reservoirs"));
      this.addTextureSampler(samplers, "radiosity_lighting", () -> this.lightingBuffer.getWriteAttachment("lighting"));
      this.addTextureSampler(samplers, "radiosity_lighting_variance", () -> this.lightingBuffer.getWriteAttachment("lighting_variance"));
      this.addTextureSampler(samplers, "radiosity_handheld", () -> this.lightingBuffer.getWriteAttachment("handheld"));
      this.addTextureSampler(samplers, "radiosity_indirect", () -> this.lightingBuffer.getWriteAttachment("indirect"));
      this.addTextureSampler(samplers, "radiosity_indirect_variance", () -> this.lightingBuffer.getWriteAttachment("indirect_variance"));
      this.addTextureSampler(samplers, "radiosity_indirect_resolved", this::getResolvedIndirectTexture);
      this.addTextureSampler(samplers, "radiosity_gi_reservoir_pos", () -> this.lightingBuffer.getWriteAttachment("gi_reservoir_pos"));
      this.addTextureSampler(samplers, "radiosity_gi_reservoir_normal", () -> this.lightingBuffer.getWriteAttachment("gi_reservoir_normal"));
      this.addTextureSampler(samplers, "radiosity_gi_reservoir_radiance", () -> this.lightingBuffer.getWriteAttachment("gi_reservoir_radiance"));
      this.addTextureSampler(samplers, "radiosity_gi_reservoir_meta", () -> this.lightingBuffer.getWriteAttachment("gi_reservoir_meta"));
      this.addTextureSampler(samplers, "stage_radiosity_reservoirs", () -> this.lightingStageBuffer.getWriteAttachment("reservoirs"));
      this.addTextureSampler(samplers, "stage_radiosity_lighting", () -> this.lightingStageBuffer.getWriteAttachment("lighting"));
      this.addTextureSampler(samplers, "stage_radiosity_handheld", () -> this.lightingStageBuffer.getWriteAttachment("handheld"));
      this.addTextureSampler(samplers, "stage_radiosity_indirect", () -> this.lightingStageBuffer.getWriteAttachment("indirect"));
      this.addTextureSampler(samplers, "stage_radiosity_gi_reservoir_pos", () -> this.lightingStageBuffer.getWriteAttachment("gi_reservoir_pos"));
      this.addTextureSampler(samplers, "stage_radiosity_gi_reservoir_normal", () -> this.lightingStageBuffer.getWriteAttachment("gi_reservoir_normal"));
      this.addTextureSampler(samplers, "stage_radiosity_gi_reservoir_radiance", () -> this.lightingStageBuffer.getWriteAttachment("gi_reservoir_radiance"));
      this.addTextureSampler(samplers, "stage_radiosity_gi_reservoir_meta", () -> this.lightingStageBuffer.getWriteAttachment("gi_reservoir_meta"));
      this.addTextureSampler(samplers, "prev_radiosity_position", () -> this.lightingBuffer.getReadAttachment("position"));
      this.addTextureSampler(samplers, "prev_radiosity_normal", () -> this.lightingBuffer.getReadAttachment("normal"));
      this.addTextureSampler(samplers, "prev_radiosity_direct", this::getPreviousResolvedDirectTexture);
      this.addTextureSampler(samplers, "prev_radiosity_direct_soft", this::getPreviousCompatDirectSoftTexture);
      this.addTextureSampler(samplers, "prev_radiosity_reservoirs", () -> this.lightingBuffer.getReadAttachment("reservoirs"));
      this.addTextureSampler(samplers, "prev_radiosity_lighting", () -> this.lightingBuffer.getReadAttachment("lighting"));
      this.addTextureSampler(samplers, "prev_radiosity_lighting_variance", () -> this.lightingBuffer.getReadAttachment("lighting_variance"));
      this.addTextureSampler(samplers, "prev_radiosity_handheld", () -> this.lightingBuffer.getReadAttachment("handheld"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect", () -> this.lightingBuffer.getReadAttachment("indirect"));
      this.addTextureSampler(samplers, "prev_radiosity_indirect_variance", () -> this.lightingBuffer.getReadAttachment("indirect_variance"));
      this.addTextureSampler(samplers, "prev_radiosity_gi_reservoir_pos", () -> this.lightingBuffer.getReadAttachment("gi_reservoir_pos"));
      this.addTextureSampler(samplers, "prev_radiosity_gi_reservoir_normal", () -> this.lightingBuffer.getReadAttachment("gi_reservoir_normal"));
      this.addTextureSampler(samplers, "prev_radiosity_gi_reservoir_radiance", () -> this.lightingBuffer.getReadAttachment("gi_reservoir_radiance"));
      this.addTextureSampler(samplers, "prev_radiosity_gi_reservoir_meta", () -> this.lightingBuffer.getReadAttachment("gi_reservoir_meta"));
      if (this.denoisingBuffer != null) {
         this.addTextureSampler(samplers, "denoise_color", () -> this.denoisingBuffer.getWriteAttachment("color"));
         this.addTextureSampler(samplers, "denoise_variance", () -> this.denoisingBuffer.getWriteAttachment("variance"));
         this.addTextureSampler(samplers, "prev_denoise_color", () -> this.denoisingBuffer.getReadAttachment("color"));
         this.addTextureSampler(samplers, "prev_denoise_variance", () -> this.denoisingBuffer.getReadAttachment("variance"));
         this.addTextureSampler(samplers, "indirect_denoise_color", () -> this.indirectDenoisingBuffer.getWriteAttachment("color"));
         this.addTextureSampler(samplers, "indirect_denoise_variance", () -> this.indirectDenoisingBuffer.getWriteAttachment("variance"));
         this.addTextureSampler(samplers, "prev_indirect_denoise_color", () -> this.indirectDenoisingBuffer.getReadAttachment("color"));
         this.addTextureSampler(samplers, "prev_indirect_denoise_variance", () -> this.indirectDenoisingBuffer.getReadAttachment("variance"));
      }
   }

   @Override
   public void registerCustomUniforms(DynamicUniformHolder uniforms) {
      if (this.denoiserPasses != 0) {
         uniforms.uniform1i("atrous_iteration", () -> this.atrousIteration, updater -> {
            if (updater != null) {
               updater.run();
            }
         });
      }
   }

   @Override
   public void render() {
      if (this.lightingRenderer != null) {
         this.ensureCompatDirectSoftCleared();
         this.lightingBuffer.swap();
         this.lightingRenderer.renderAll();
         if (this.denoisingRenderer != null && this.denoisingBuffer != null) {
            for (this.atrousIteration = -1; this.atrousIteration < this.denoiserPasses; this.atrousIteration++) {
               this.denoisingBuffer.swap();
               this.denoisingRenderer.renderAll();
            }
         }
         if (this.indirectDenoisingRenderer != null && this.indirectDenoisingBuffer != null) {
            for (this.atrousIteration = -1; this.atrousIteration < this.denoiserPasses; this.atrousIteration++) {
               this.indirectDenoisingBuffer.swap();
               this.indirectDenoisingRenderer.renderAll();
            }
         }
         if (this.indirectRenderer != null) {
            this.indirectRenderer.renderAll();
         }
         this.worldRegistry.advanceLightBlendFrame();
      }
   }

   @Override
   public Map<String, TextureObject> getAutomationTextures() {
      return Map.ofEntries(
         Map.entry("direct", this.getResolvedDirectTexture()),
         Map.entry("direct_soft", this.getCompatDirectSoftTexture()),
         Map.entry("direct_denoised", this.getDenoisedDirectTexture()),
         Map.entry("direct_raw", this.lightingBuffer.getWriteAttachment("direct")),
         Map.entry("handheld", this.lightingBuffer.getWriteAttachment("handheld")),
         Map.entry("indirect", this.getResolvedIndirectTexture()),
         Map.entry("indirect_raw", this.lightingBuffer.getWriteAttachment("indirect")),
         Map.entry("indirect_denoised", this.getResolvedIndirectTexture()),
         Map.entry("stage_indirect", this.lightingStageBuffer.getWriteAttachment("indirect")),
         Map.entry("lighting", this.lightingBuffer.getWriteAttachment("lighting")),
         Map.entry("stage_lighting", this.lightingStageBuffer.getWriteAttachment("lighting"))
      );
   }

   @Override
   public void recalculateSizes() {
      if (this.lightingRenderer != null) {
         this.lightingRenderer.recalculateSizes();
      }
      if (this.denoisingRenderer != null) {
         this.denoisingRenderer.recalculateSizes();
      }
      if (this.indirectDenoisingRenderer != null) {
         this.indirectDenoisingRenderer.recalculateSizes();
      }
      if (this.indirectRenderer != null) {
         this.indirectRenderer.recalculateSizes();
      }
      this.compatDirectSoftDirty = true;
   }

   @Override
   public void free() {
      this.samplingFramebuffer.destroy();
      this.lightingPassFramebuffer.destroy();
      this.accumulationFramebuffer.destroy();
      this.giCopyFramebuffer.destroy();
      this.lightingBuffer.destroy();
      this.lightingStageBuffer.destroy();
      this.compatDirectSoftBuffer.destroy();
      if (this.lightingRenderer != null) {
         this.lightingRenderer.destroy();
      }
      if (this.indirectRenderer != null) {
         this.indirectRenderer.destroy();
      }
      if (this.denoisingBuffer != null) {
         this.denoisingBuffer.destroy();
      }
      if (this.denoisingRenderer != null) {
         this.denoisingRenderer.destroy();
      }
      if (this.indirectDenoisingBuffer != null) {
         this.indirectDenoisingBuffer.destroy();
      }
      if (this.indirectDenoisingRenderer != null) {
         this.indirectDenoisingRenderer.destroy();
      }
   }

   private void createLightingAttachments(ColorFramebuffer framebuffer) {
      framebuffer.createAttachment("position", "RGB32F", false);
      framebuffer.createAttachment("normal", "RGB16F", false);
      framebuffer.createAttachment("reservoirs", "RGBA32F", false);
      framebuffer.createAttachment("lighting", "RGBA32F", false);
      framebuffer.createAttachment("lighting_variance", "RGBA32F", false);
      framebuffer.createAttachment("handheld", "RGBA16F", false);
      framebuffer.createAttachment("indirect", "RGBA16F", false);
      framebuffer.createAttachment("direct", "RGBA16F", false);
      framebuffer.createAttachment("gi_reservoir_pos", "RGBA32F", false);
      framebuffer.createAttachment("gi_reservoir_normal", "RGBA16F", false);
      framebuffer.createAttachment("gi_reservoir_radiance", "RGBA16F", false);
      framebuffer.createAttachment("gi_reservoir_meta", "RGBA32F", false);
      framebuffer.createAttachment("indirect_variance", "RGBA32F", false);
   }

   private RoutingFramebuffer createSamplingFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingBuffer.getWriteAttachment("position"),
         () -> this.lightingBuffer.getWriteAttachment("normal"),
         () -> this.lightingBuffer.getWriteAttachment("reservoirs"),
         () -> this.lightingBuffer.getWriteAttachment("gi_reservoir_pos"),
         () -> this.lightingBuffer.getWriteAttachment("gi_reservoir_normal"),
         () -> this.lightingBuffer.getWriteAttachment("gi_reservoir_radiance"),
         () -> this.lightingBuffer.getWriteAttachment("gi_reservoir_meta")
      );
   }

   private RoutingFramebuffer createLightingPassFramebuffer(boolean handheldLightEnabled) {
      if (handheldLightEnabled) {
         return this.createRoutingFramebuffer(
            () -> this.lightingStageBuffer.getWriteAttachment("reservoirs"),
            () -> this.lightingStageBuffer.getWriteAttachment("lighting"),
            () -> this.lightingStageBuffer.getWriteAttachment("handheld"),
            () -> this.lightingStageBuffer.getWriteAttachment("indirect"),
            () -> this.lightingStageBuffer.getWriteAttachment("gi_reservoir_pos"),
            () -> this.lightingStageBuffer.getWriteAttachment("gi_reservoir_normal"),
            () -> this.lightingStageBuffer.getWriteAttachment("gi_reservoir_radiance"),
            () -> this.lightingStageBuffer.getWriteAttachment("gi_reservoir_meta")
         );
      }

      return this.createRoutingFramebuffer(
         () -> this.lightingStageBuffer.getWriteAttachment("reservoirs"),
         () -> this.lightingStageBuffer.getWriteAttachment("lighting"),
         () -> this.lightingStageBuffer.getWriteAttachment("indirect"),
         () -> this.lightingStageBuffer.getWriteAttachment("gi_reservoir_pos"),
         () -> this.lightingStageBuffer.getWriteAttachment("gi_reservoir_normal"),
         () -> this.lightingStageBuffer.getWriteAttachment("gi_reservoir_radiance"),
         () -> this.lightingStageBuffer.getWriteAttachment("gi_reservoir_meta")
      );
   }

   private RoutingFramebuffer createAccumulationFramebuffer(boolean handheldLightEnabled) {
      if (handheldLightEnabled) {
         return this.createRoutingFramebuffer(
            () -> this.lightingBuffer.getWriteAttachment("reservoirs"),
            () -> this.lightingBuffer.getWriteAttachment("lighting"),
            () -> this.lightingBuffer.getWriteAttachment("lighting_variance"),
            () -> this.lightingBuffer.getWriteAttachment("handheld"),
            () -> this.lightingBuffer.getWriteAttachment("indirect"),
            () -> this.lightingBuffer.getWriteAttachment("direct"),
            () -> this.lightingBuffer.getWriteAttachment("indirect_variance")
         );
      }

      return this.createRoutingFramebuffer(
         () -> this.lightingBuffer.getWriteAttachment("reservoirs"),
         () -> this.lightingBuffer.getWriteAttachment("lighting"),
         () -> this.lightingBuffer.getWriteAttachment("lighting_variance"),
         () -> this.lightingBuffer.getWriteAttachment("indirect"),
         () -> this.lightingBuffer.getWriteAttachment("direct"),
         () -> this.lightingBuffer.getWriteAttachment("indirect_variance")
      );
   }

   private RoutingFramebuffer createGiCopyFramebuffer() {
      return this.createRoutingFramebuffer(
         () -> this.lightingBuffer.getWriteAttachment("gi_reservoir_pos"),
         () -> this.lightingBuffer.getWriteAttachment("gi_reservoir_normal"),
         () -> this.lightingBuffer.getWriteAttachment("gi_reservoir_radiance"),
         () -> this.lightingBuffer.getWriteAttachment("gi_reservoir_meta")
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


   private TextureObject getResolvedDirectTexture() {
      if (USE_DENOISED_DIRECT_OUTPUT && this.denoisingBuffer != null) {
         return this.denoisingBuffer.getWriteAttachment("color");
      }
      return this.lightingBuffer.getWriteAttachment("direct");
   }

   private TextureObject getPreviousResolvedDirectTexture() {
      if (USE_DENOISED_DIRECT_OUTPUT && this.denoisingBuffer != null) {
         return this.denoisingBuffer.getReadAttachment("color");
      }
      return this.lightingBuffer.getReadAttachment("direct");
   }

   private TextureObject getDenoisedDirectTexture() {
      if (this.denoisingBuffer != null) {
         return this.denoisingBuffer.getWriteAttachment("color");
      }
      return this.lightingBuffer.getWriteAttachment("direct");
   }

   private TextureObject getResolvedIndirectTexture() {
      if (this.indirectDenoisingBuffer != null) {
         return this.indirectDenoisingBuffer.getWriteAttachment("color");
      }
      return this.lightingBuffer.getWriteAttachment("indirect");
   }

   private TextureObject getCompatDirectSoftTexture() {
      return this.compatDirectSoftBuffer.getWriteAttachment("direct_soft_compat");
   }

   private TextureObject getPreviousCompatDirectSoftTexture() {
      return this.compatDirectSoftBuffer.getReadAttachment("direct_soft_compat");
   }

   private void ensureCompatDirectSoftCleared() {
      if (!this.compatDirectSoftDirty) {
         return;
      }
      this.clearCompatDirectSoftAttachments();
      this.compatDirectSoftDirty = false;
   }

   private void clearCompatDirectSoftAttachments() {
      Vector4f clearColor = new Vector4f(0.0f, 0.0f, 0.0f, 1.0f);
      this.compatDirectSoftBuffer.clear(clearColor);
      this.compatDirectSoftBuffer.swap();
      this.compatDirectSoftBuffer.clear(clearColor);
      this.compatDirectSoftBuffer.swap();
   }
}

