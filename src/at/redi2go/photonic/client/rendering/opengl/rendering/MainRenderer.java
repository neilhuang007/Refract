package at.redi2go.photonic.client.rendering.opengl.rendering;

import at.redi2go.photonic.client.GlProgramExt;
import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.PhotonicsStorage;
import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;
import at.redi2go.photonic.client.rendering.opengl.GL;
import at.redi2go.photonic.client.rendering.opengl.objects.GLMemoryCollection;
import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.world.WorldRegistry;
import at.redi2go.photonic.client.rendering.world.buffer.GlMemoryManager;
import java.nio.FloatBuffer;
import java.util.List;
import java.util.Objects;
import java.util.function.Function;
import net.caffeinemc.mods.sodium.client.gl.shader.GlProgram;
import net.caffeinemc.mods.sodium.client.render.chunk.shader.ChunkShaderInterface;
import net.irisshaders.iris.pipeline.CompositeRenderer;
import org.lwjgl.opengl.GL42;

public class MainRenderer implements Destructable {
   private final WorldRegistry worldRegistry;
   private CompositeRenderer compositeRenderer;
   private final GLMemoryCollection memoryCollection;
   private final ColorFramebuffer lightingBuffer;
   private final GlMemoryManager pixelationDebugBuffer;
   private long lastPixelationDebugLogMs = 0L;
   private int lastPixelationDebugFrame = Integer.MIN_VALUE;

   public MainRenderer(WorldRegistry worldRegistry) {
      this.worldRegistry = worldRegistry;
      this.pixelationDebugBuffer = new GlMemoryManager(GlTarget.SSBO, "debug_pixelation_block", 16 * Float.BYTES, false);
      this.lightingBuffer = new ColorFramebuffer();
      this.lightingBuffer.createAttachment("position", "RGB32F", false);
      this.lightingBuffer.createAttachment("normal", "RGBA16F", false);
      this.lightingBuffer.createAttachment("direct", "RGBA16F", false);
      this.lightingBuffer.createAttachment("direct_soft", "RGBA32F", false);
      this.lightingBuffer.createAttachment("handheld", "RGBA8", false);
      this.memoryCollection = this.buildGlMemoryCollection();
   }

   public void setup() {
      while (!this.worldRegistry.getGlQueue().isEmpty()) {
         Objects.requireNonNull(this.worldRegistry.getGlQueue().poll()).run();
      }

      this.worldRegistry.upload();
   }

   public void finishRender() {
      this.lightingBuffer.swap();
      this.compositeRenderer.renderAll();
      this.logPixelationDebugProbe();
   }

   public void createCompositeRenderer(Function<List<PhotonicsShader>, CompositeRenderer> rendererCreator) {
      this.compositeRenderer = rendererCreator.apply(
         List.of(
            new PhotonicsShader("ph_lighting.glsl", "ph_screen.glsl", this.memoryCollection, this.lightingBuffer),
            new PhotonicsShader("ph_indirect.glsl", "ph_screen.glsl", this.memoryCollection, null)
         )
      );
   }

   public void configureVoxelsShaders(GlProgram<ChunkShaderInterface> voxelProgram) {
      PhotonicsShader photonicsShader = new PhotonicsShader("", "", this.memoryCollection, null);
      ((GlProgramExt)voxelProgram).photonic$setPhotonicsShader(photonicsShader);
   }

   @Override
   public void free() {
      this.compositeRenderer.destroy();
      this.lightingBuffer.destroy();
      this.pixelationDebugBuffer.free();
   }

   private GLMemoryCollection buildGlMemoryCollection() {
      GLMemoryCollection memoryCollection = new GLMemoryCollection();
      memoryCollection.add(this.worldRegistry::getRootMemoryManager);
      memoryCollection.add(this.worldRegistry::getCbMemoryManager);
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getLightsMemoryManager());
      memoryCollection.add(() -> this.worldRegistry.getLightRegistry().getRegistryMemoryManager());
      memoryCollection.add(() -> this.pixelationDebugBuffer);
      return memoryCollection;
   }

   public void recalculateSizes() {
      this.compositeRenderer.recalculateSizes();
   }

   public ColorFramebuffer getLightBuffer() {
      return this.lightingBuffer;
   }

   private void logPixelationDebugProbe() {
      if (!PhotonicsStorage.PIXELATED_LIGHTING_DEBUG_LOG.value) {
         return;
      }

      long now = System.currentTimeMillis();
      if (now - this.lastPixelationDebugLogMs < 1000L) {
         return;
      }
      this.lastPixelationDebugLogMs = now;

      GL42.glMemoryBarrier(GL.pGetShaderWriteToCpuBarrierBits());
      this.pixelationDebugBuffer.download(downloadedBuffer -> {
         FloatBuffer probe = downloadedBuffer.asFloatBuffer();
         if (probe.remaining() < 16) {
            return;
         }

         float baseX = probe.get(0);
         float baseY = probe.get(1);
         float baseZ = probe.get(2);
         int frame = (int)probe.get(3);
         float snapX = probe.get(4);
         float snapY = probe.get(5);
         float snapZ = probe.get(6);
         float snapDist = probe.get(7);
         float texelOffsetX = probe.get(8);
         float texelOffsetY = probe.get(9);
         float centerFactor = probe.get(10);
         float pixelMeta = probe.get(11);
         float yBias = probe.get(12);
         float centerBlend = probe.get(13);
         float centerBranch = probe.get(14);
         float sameCell = probe.get(15);

         if (frame == this.lastPixelationDebugFrame) {
            return;
         }
         this.lastPixelationDebugFrame = frame;

         if (frame < 0) {
            Photonic.info("[PixelationDebug] centerProbe=sky/no-geometry");
            return;
         }

         int axisIndex = Math.max(0, Math.min(2, Math.round(centerFactor)));
         String faceLabel = switch (axisIndex) {
            case 0 -> pixelMeta >= 0.0f ? "+X" : "-X";
            case 1 -> pixelMeta >= 0.0f ? "+Y" : "-Y";
            default -> pixelMeta >= 0.0f ? "+Z" : "-Z";
         };

         Photonic.info(
            "[PixelationDebug] frame={} face={} base=({}, {}, {}) snapped=({}, {}, {}) snapDist={} planeFrac=({}, {}) blockY={} checker={} centerBranch={} sameCell={}",
            frame,
            faceLabel,
            baseX,
            baseY,
            baseZ,
            snapX,
            snapY,
            snapZ,
            snapDist,
            texelOffsetX,
            texelOffsetY,
            yBias,
            centerBlend,
            centerBranch,
            sameCell
         );
      });
   }
}
