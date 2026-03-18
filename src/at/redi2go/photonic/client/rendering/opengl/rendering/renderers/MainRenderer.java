package at.redi2go.photonic.client.rendering.opengl.rendering.renderers;

import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;
import at.redi2go.photonic.client.rendering.opengl.objects.GLMemoryCollection;
import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.opengl.rendering.PhotonicsShader;
import at.redi2go.photonic.client.rendering.world.WorldRegistry;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import it.unimi.dsi.fastutil.ints.Int2ObjectMap;
import it.unimi.dsi.fastutil.ints.Int2ObjectOpenHashMap;
import it.unimi.dsi.fastutil.ints.IntSet;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.function.Function;
import java.util.function.Supplier;
import net.irisshaders.iris.gl.sampler.SamplerHolder;
import net.irisshaders.iris.gl.uniform.DynamicUniformHolder;
import net.irisshaders.iris.pipeline.CompositeRenderer;

public abstract class MainRenderer implements Destructable {
   protected final WorldRegistry worldRegistry;
   protected final float renderScale;
   protected final GLMemoryCollection memoryCollection;
   protected final Int2ObjectMap<List<Map.Entry<Integer, GlMemoryManager>>> foundMemories;
   private String currentPhotonicsFragment = "";

   public MainRenderer(WorldRegistry worldRegistry, float renderScale) {
      this.worldRegistry = worldRegistry;
      this.renderScale = renderScale;
      this.memoryCollection = this.buildGlMemoryCollection();
      this.foundMemories = new Int2ObjectOpenHashMap<>();
   }

   public abstract void createCompositeRenderer(Function<List<PhotonicsShader>, CompositeRenderer> rendererCreator);

   protected void addTextureSampler(SamplerHolder samplers, String name, Supplier<TextureObject> textureObjectSupplier) {
      samplers.addDynamicSampler(() -> {
         TextureObject textureObject = textureObjectSupplier.get();
         textureObject.updatePerFrame();
         return textureObject.getTextureId();
      }, new String[]{name});
   }

   public abstract void registerCustomTextures(SamplerHolder samplers);

   public abstract void registerCustomUniforms(DynamicUniformHolder uniforms);

   public abstract void render();

   public void setCurrentPhotonicsFragment(String fragmentName) {
      this.currentPhotonicsFragment = fragmentName == null ? "" : fragmentName;
   }

   protected boolean isCurrentPhotonicsFragment(String fragmentName) {
      return fragmentName.equals(this.currentPhotonicsFragment);
   }

   public Map<String, TextureObject> getAutomationTextures() {
      return Map.of();
   }

   public abstract void recalculateSizes();

   public void setup() {
      while (!this.worldRegistry.getGlQueue().isEmpty()) {
         Objects.requireNonNull(this.worldRegistry.getGlQueue().poll()).run();
      }
      this.worldRegistry.upload();
   }

   public void bindProgramBuffers(int shaderId, IntSet usedBuffers) {
      List<Map.Entry<Integer, GlMemoryManager>> cached = this.foundMemories.get(shaderId);
      if (cached == null) {
         cached = new ArrayList<>();
         int bindingPointIndex = 16;
         for (Supplier<GlMemoryManager> glMemoryManagerSupplier : this.memoryCollection) {
            GlMemoryManager glMemoryManager = glMemoryManagerSupplier.get();
            int blockIndex = glMemoryManager.findInProgram(shaderId);
            if (blockIndex >= 0) {
               while (usedBuffers.contains(--bindingPointIndex)) {
               }
               cached.add(Map.entry(blockIndex, glMemoryManager));
               glMemoryManager.bind(shaderId, blockIndex, bindingPointIndex);
            }
         }
         this.foundMemories.put(shaderId, cached);
      } else {
         int bindingPointIndex = 16;
         for (Map.Entry<Integer, GlMemoryManager> entry : cached) {
            int blockIndex = entry.getKey();
            GlMemoryManager glMemoryManager = entry.getValue();
            while (usedBuffers.contains(--bindingPointIndex)) {
            }
            glMemoryManager.bind(shaderId, blockIndex, bindingPointIndex);
         }
      }
   }

   protected GLMemoryCollection buildGlMemoryCollection() {
      GLMemoryCollection memoryCollection = new GLMemoryCollection();
      memoryCollection.add(this.worldRegistry::getRootMemoryManager);
      memoryCollection.add(this.worldRegistry::getCbMemoryManager);
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getLightsMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getLightMappingMemoryManager());
      return memoryCollection;
   }
}
