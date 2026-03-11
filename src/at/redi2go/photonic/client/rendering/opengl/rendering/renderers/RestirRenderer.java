package at.redi2go.photonic.client.rendering.opengl.rendering.renderers;

import at.redi2go.photonic.client.api.PhotonicsProperties;
import at.redi2go.photonic.client.rendering.opengl.rendering.ColorFramebuffer;
import at.redi2go.photonic.client.rendering.opengl.rendering.PhotonicsShader;
import at.redi2go.photonic.client.rendering.world.WorldRegistry;
import java.util.List;
import java.util.function.Function;
import net.irisshaders.iris.gl.sampler.SamplerHolder;
import net.irisshaders.iris.gl.uniform.DynamicUniformHolder;
import net.irisshaders.iris.pipeline.CompositeRenderer;
import org.jetbrains.annotations.Nullable;

public class RestirRenderer extends MainRenderer {
   private final ColorFramebuffer lightingBuffer;
   @Nullable
   private CompositeRenderer lightingRenderer;
   @Nullable
   private final ColorFramebuffer denoisingBuffer;
   @Nullable
   private CompositeRenderer denoisingRenderer;
   private int atrousIteration = 0;
   private final int denoiserPasses;

   public RestirRenderer(WorldRegistry worldRegistry, float renderScale, PhotonicsProperties properties) {
      super(worldRegistry, renderScale);
      this.denoiserPasses = properties.getRestirDenoiserPasses();
      this.lightingBuffer = new ColorFramebuffer(renderScale);
      this.lightingBuffer.createAttachment("position", "RGB32F", false);
      this.lightingBuffer.createAttachment("normal", "RGB16F", false);
      this.lightingBuffer.createAttachment("reservoirs", "RGBA32F", false);
      this.lightingBuffer.createAttachment("lighting", "RGBA32F", false);
      this.lightingBuffer.createAttachment("lighting_variance", "RGBA32F", false);
      this.lightingBuffer.createAttachment("handheld", "RGBA16F", false);
      if (this.denoiserPasses != 0) {
         this.denoisingBuffer = new ColorFramebuffer(renderScale);
         this.denoisingBuffer.createAttachment("color", "RGB16F", true);
         this.denoisingBuffer.createAttachment("variance", "R16F", true);
      } else {
         this.denoisingBuffer = null;
      }
   }

   @Override
   public void createCompositeRenderer(Function<List<PhotonicsShader>, CompositeRenderer> rendererCreator) {
      this.lightingRenderer = rendererCreator.apply(
         List.of(
            new PhotonicsShader("restir/sampling.fsh", "common/screen.vsh", this.memoryCollection, this.lightingBuffer),
            new PhotonicsShader("restir/lighting.fsh", "common/screen.vsh", this.memoryCollection, this.lightingBuffer),
            new PhotonicsShader("restir/accumulation.fsh", "common/screen.vsh", this.memoryCollection, this.lightingBuffer),
            new PhotonicsShader("common/indirect.fsh", "common/screen.vsh", this.memoryCollection, null)
         )
      );
      if (this.denoiserPasses != 0) {
         this.denoisingRenderer = rendererCreator.apply(
            List.of(new PhotonicsShader("restir/denoising.fsh", "common/screen.vsh", this.memoryCollection, this.denoisingBuffer))
         );
      }
   }

   @Override
   public void registerCustomTextures(SamplerHolder samplers) {
      this.addTextureSampler(samplers, "radiosity_position", () -> this.lightingBuffer.getWriteAttachment("position"));
      this.addTextureSampler(samplers, "radiosity_normal", () -> this.lightingBuffer.getWriteAttachment("normal"));
      this.addTextureSampler(samplers, "radiosity_reservoirs", () -> this.lightingBuffer.getWriteAttachment("reservoirs"));
      this.addTextureSampler(samplers, "radiosity_lighting", () -> this.lightingBuffer.getWriteAttachment("lighting"));
      this.addTextureSampler(samplers, "radiosity_lighting_variance", () -> this.lightingBuffer.getWriteAttachment("lighting_variance"));
      this.addTextureSampler(samplers, "radiosity_handheld", () -> this.lightingBuffer.getWriteAttachment("handheld"));
      this.addTextureSampler(samplers, "prev_radiosity_position", () -> this.lightingBuffer.getReadAttachment("position"));
      this.addTextureSampler(samplers, "prev_radiosity_normal", () -> this.lightingBuffer.getReadAttachment("normal"));
      this.addTextureSampler(samplers, "prev_radiosity_reservoirs", () -> this.lightingBuffer.getReadAttachment("reservoirs"));
      this.addTextureSampler(samplers, "prev_radiosity_lighting", () -> this.lightingBuffer.getReadAttachment("lighting"));
      this.addTextureSampler(samplers, "prev_radiosity_lighting_variance", () -> this.lightingBuffer.getReadAttachment("lighting_variance"));
      this.addTextureSampler(samplers, "prev_radiosity_handheld", () -> this.lightingBuffer.getReadAttachment("handheld"));
      if (this.denoisingBuffer != null) {
         this.addTextureSampler(samplers, "denoise_color", () -> this.denoisingBuffer.getWriteAttachment("color"));
         this.addTextureSampler(samplers, "denoise_variance", () -> this.denoisingBuffer.getWriteAttachment("variance"));
         this.addTextureSampler(samplers, "prev_denoise_color", () -> this.denoisingBuffer.getReadAttachment("color"));
         this.addTextureSampler(samplers, "prev_denoise_variance", () -> this.denoisingBuffer.getReadAttachment("variance"));
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
         this.lightingBuffer.swap();
         this.lightingRenderer.renderAll();
         if (this.denoisingRenderer != null && this.denoisingBuffer != null) {
            for (this.atrousIteration = -1; this.atrousIteration < this.denoiserPasses; this.atrousIteration++) {
               this.denoisingBuffer.swap();
               this.denoisingRenderer.renderAll();
            }
         }
      }
   }

   @Override
   public void recalculateSizes() {
      if (this.lightingRenderer != null && this.denoisingRenderer != null) {
         this.lightingRenderer.recalculateSizes();
         this.denoisingRenderer.recalculateSizes();
      }
   }

   @Override
   public void free() {
      this.lightingBuffer.destroy();
      if (this.lightingRenderer != null) {
         this.lightingRenderer.destroy();
      }
      if (this.denoisingBuffer != null) {
         this.denoisingBuffer.destroy();
      }
      if (this.denoisingRenderer != null) {
         this.denoisingRenderer.destroy();
      }
   }
}
