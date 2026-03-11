package at.redi2go.photonic.client.rendering.opengl.rendering.renderers;

import at.redi2go.photonic.client.api.PhotonicsProperties;
import at.redi2go.photonic.client.rendering.opengl.rendering.PhotonicsShader;
import at.redi2go.photonic.client.rendering.world.WorldRegistry;
import java.util.List;
import java.util.function.Function;
import net.irisshaders.iris.gl.sampler.SamplerHolder;
import net.irisshaders.iris.gl.uniform.DynamicUniformHolder;
import net.irisshaders.iris.pipeline.CompositeRenderer;

public class DisabledRenderer extends MainRenderer {
   public DisabledRenderer(WorldRegistry worldRegistry, float renderScale, PhotonicsProperties properties) {
      super(worldRegistry, renderScale);
   }

   @Override
   public void createCompositeRenderer(Function<List<PhotonicsShader>, CompositeRenderer> rendererCreator) {
   }

   @Override
   public void registerCustomTextures(SamplerHolder samplers) {
   }

   @Override
   public void registerCustomUniforms(DynamicUniformHolder uniforms) {
   }

   @Override
   public void render() {
   }

   @Override
   public void recalculateSizes() {
   }

   @Override
   public void free() {
   }
}
