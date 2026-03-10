package at.redi2go.photonic.client.rendering.opengl.rendering;

import at.redi2go.photonic.client.GlProgramExt;
import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;
import at.redi2go.photonic.client.rendering.opengl.objects.GLMemoryCollection;
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
import net.caffeinemc.mods.sodium.client.gl.shader.GlProgram;
import net.caffeinemc.mods.sodium.client.render.chunk.shader.ChunkShaderInterface;
import net.irisshaders.iris.pipeline.CompositeRenderer;

public class MainRenderer implements Destructable {
   private final WorldRegistry worldRegistry;
   private final float renderScale;
   private CompositeRenderer compositeRenderer;
   private final GLMemoryCollection memoryCollection;
   private ColorFramebuffer lightingBuffer;
   private final Int2ObjectMap<List<Map.Entry<Integer, GlMemoryManager>>> foundMemories = new Int2ObjectOpenHashMap<>();

   public MainRenderer(WorldRegistry worldRegistry, float renderScale) {
      this.worldRegistry = worldRegistry;
      this.renderScale = renderScale;
      this.memoryCollection = this.buildGlMemoryCollection();
   }

   public void setup() {
      while (!this.worldRegistry.getGlQueue().isEmpty()) {
         Objects.requireNonNull(this.worldRegistry.getGlQueue().poll()).run();
      }

      this.worldRegistry.upload();
   }

   public void finishRender() {
      this.getLightBuffer().swap();
      if (this.compositeRenderer != null) {
         this.compositeRenderer.renderAll();
      }
   }

   public void createCompositeRenderer(Function<List<PhotonicsShader>, CompositeRenderer> rendererCreator) {
      this.compositeRenderer = rendererCreator.apply(
         List.of(
            new PhotonicsShader("ph_lighting.glsl", "ph_screen.glsl", this.memoryCollection, this.getLightBuffer()),
            new PhotonicsShader("ph_indirect.glsl", "ph_screen.glsl", this.memoryCollection, null)
         )
      );
   }

   public void configureVoxelsShaders(GlProgram<ChunkShaderInterface> voxelProgram) {
      PhotonicsShader photonicsShader = new PhotonicsShader("", "", this.memoryCollection, null);
      ((GlProgramExt)voxelProgram).photonic$setPhotonicsShader(photonicsShader);
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

   @Override
   public void free() {
      if (this.compositeRenderer != null) {
         this.compositeRenderer.destroy();
      }
      if (this.lightingBuffer != null) {
         this.lightingBuffer.destroy();
      }
      this.foundMemories.clear();
   }

   private GLMemoryCollection buildGlMemoryCollection() {
      GLMemoryCollection memoryCollection = new GLMemoryCollection();
      memoryCollection.add(this.worldRegistry::getRootMemoryManager);
      memoryCollection.add(this.worldRegistry::getCbMemoryManager);
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getLightsMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getRegistryMemoryManager());
      return memoryCollection;
   }

   public void recalculateSizes() {
      if (this.compositeRenderer != null) {
         this.compositeRenderer.recalculateSizes();
      }
   }

   public ColorFramebuffer getLightBuffer() {
      if (this.lightingBuffer == null) {
         this.lightingBuffer = new ColorFramebuffer(this.renderScale);
         this.lightingBuffer.createAttachment("position", "RGB32F", false);
         this.lightingBuffer.createAttachment("normal", "RGBA16F", false);
         this.lightingBuffer.createAttachment("direct", "RGBA16F", false);
         this.lightingBuffer.createAttachment("direct_soft", "RGBA32F", false);
         this.lightingBuffer.createAttachment("handheld", "RGBA8", false);
         this.lightingBuffer.clear(new org.joml.Vector4f(0, 0, 0, 0));
         this.lightingBuffer.swap();
         this.lightingBuffer.clear(new org.joml.Vector4f(0, 0, 0, 0));
         this.lightingBuffer.swap();
      }
      return this.lightingBuffer;
   }
}
