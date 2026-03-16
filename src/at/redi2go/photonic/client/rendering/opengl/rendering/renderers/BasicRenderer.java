package at.redi2go.photonic.client.rendering.opengl.rendering.renderers;

import at.redi2go.photonic.client.api.PhotonicsProperties;
import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.opengl.rendering.ColorFramebuffer;
import at.redi2go.photonic.client.rendering.opengl.rendering.PhotonicsShader;
import at.redi2go.photonic.client.rendering.world.WorldRegistry;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import net.irisshaders.iris.gl.sampler.SamplerHolder;
import net.irisshaders.iris.gl.uniform.DynamicUniformHolder;
import net.irisshaders.iris.pipeline.CompositeRenderer;
import org.jetbrains.annotations.Nullable;

public class BasicRenderer extends MainRenderer {
   private final ColorFramebuffer lightingBuffer;
   @Nullable
   private CompositeRenderer lightingRenderer;
   private final int[] lightingDrawBuffers;

   public BasicRenderer(WorldRegistry worldRegistry, float renderScale, PhotonicsProperties properties) {
      super(worldRegistry, renderScale);
      this.lightingBuffer = new ColorFramebuffer(renderScale);
      this.lightingBuffer.createAttachment("position", "RGB32F", false);
      this.lightingBuffer.createAttachment("normal", "RGBA16F", false);
      this.lightingBuffer.createAttachment("direct", "RGBA16F", false);
      this.lightingBuffer.createAttachment("direct_soft", "RGBA32F", false);
      this.lightingBuffer.createAttachment("handheld", "RGBA16F", false);

      boolean blockLightEnabled = properties.isBlockLightEnabled().orElse(true);
      boolean handheldLightEnabled = properties.isHandheldLightEnabled().orElse(true);
      if (blockLightEnabled && handheldLightEnabled) {
         this.lightingDrawBuffers = new int[]{0, 1, 2, 3, 4};
      } else if (blockLightEnabled) {
         this.lightingDrawBuffers = new int[]{0, 1, 2, 3};
      } else if (handheldLightEnabled) {
         this.lightingDrawBuffers = new int[]{0, 1, 2, 3, 4};
      } else {
         this.lightingDrawBuffers = new int[]{0, 1};
      }
   }

   @Override
   public void createCompositeRenderer(Function<List<PhotonicsShader>, CompositeRenderer> rendererCreator) {
      this.lightingRenderer = rendererCreator.apply(
         List.of(
            new PhotonicsShader("basic/lighting.fsh", "common/screen.vsh", this.memoryCollection, this.lightingBuffer, this.lightingDrawBuffers),
            new PhotonicsShader("common/indirect.fsh", "common/screen.vsh", this.memoryCollection, null)
         )
      );
   }

   @Override
   public void registerCustomTextures(SamplerHolder samplers) {
      this.addTextureSampler(samplers, "radiosity_position", () -> this.lightingBuffer.getWriteAttachment("position"));
      this.addTextureSampler(samplers, "radiosity_normal", () -> this.lightingBuffer.getWriteAttachment("normal"));
      this.addTextureSampler(samplers, "radiosity_direct", () -> this.lightingBuffer.getWriteAttachment("direct"));
      this.addTextureSampler(samplers, "radiosity_direct_soft", () -> this.lightingBuffer.getWriteAttachment("direct_soft"));
      this.addTextureSampler(samplers, "radiosity_handheld", () -> this.lightingBuffer.getWriteAttachment("handheld"));
      this.addTextureSampler(samplers, "prev_radiosity_position", () -> this.lightingBuffer.getReadAttachment("position"));
      this.addTextureSampler(samplers, "prev_radiosity_normal", () -> this.lightingBuffer.getReadAttachment("normal"));
      this.addTextureSampler(samplers, "prev_radiosity_direct", () -> this.lightingBuffer.getReadAttachment("direct"));
      this.addTextureSampler(samplers, "prev_radiosity_direct_soft", () -> this.lightingBuffer.getReadAttachment("direct_soft"));
      this.addTextureSampler(samplers, "prev_radiosity_handheld", () -> this.lightingBuffer.getReadAttachment("handheld"));
   }

   @Override
   public void registerCustomUniforms(DynamicUniformHolder uniforms) {
   }

   @Override
   public void render() {
      if (this.lightingRenderer != null) {
         this.lightingBuffer.swap();
         this.lightingRenderer.renderAll();
         this.worldRegistry.advanceLightBlendFrame();
      }
   }

   @Override
   public Map<String, TextureObject> getAutomationTextures() {
      return Map.of(
         "direct", this.lightingBuffer.getWriteAttachment("direct"),
         "direct_soft", this.lightingBuffer.getWriteAttachment("direct_soft"),
         "handheld", this.lightingBuffer.getWriteAttachment("handheld")
      );
   }

   @Override
   public void recalculateSizes() {
      if (this.lightingRenderer != null) {
         this.lightingRenderer.recalculateSizes();
      }
   }

   @Override
   public void free() {
      this.lightingBuffer.destroy();
      if (this.lightingRenderer != null) {
         this.lightingRenderer.destroy();
      }
   }
}

