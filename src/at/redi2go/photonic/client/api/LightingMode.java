package at.redi2go.photonic.client.api;

import at.redi2go.photonic.client.rendering.opengl.rendering.renderers.BasicRenderer;
import at.redi2go.photonic.client.rendering.opengl.rendering.renderers.DisabledRenderer;
import at.redi2go.photonic.client.rendering.opengl.rendering.renderers.LightTreeRenderer;
import at.redi2go.photonic.client.rendering.opengl.rendering.renderers.RestirRenderer;
import at.redi2go.photonic.client.rendering.opengl.rendering.renderers.MainRenderer;
import at.redi2go.photonic.client.rendering.world.WorldRegistry;

public enum LightingMode {
   OFF(DisabledRenderer::new),
   BASIC(BasicRenderer::new),
   LIGHT_TREE(LightTreeRenderer::new),
   RESTIR(RestirRenderer::new);

   @FunctionalInterface
   public interface RendererFactory {
      MainRenderer create(WorldRegistry worldRegistry, float renderScale, PhotonicsProperties properties);
   }

   private final RendererFactory rendererFactory;

   LightingMode(RendererFactory factory) {
      this.rendererFactory = factory;
   }

   public MainRenderer createMainRenderer(WorldRegistry worldRegistry, float renderScale, PhotonicsProperties properties) {
      return this.rendererFactory.create(worldRegistry, renderScale, properties);
   }
}
