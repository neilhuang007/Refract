package at.redi2go.photonic.client.rendering.opengl.rendering.renderers;

import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.opengl.rendering.ColorFramebuffer;
import at.redi2go.photonic.client.rendering.opengl.rendering.RoutingFramebuffer;
import java.util.function.Supplier;
import net.irisshaders.iris.pipeline.CompositeRenderer;
import org.jetbrains.annotations.Nullable;
import org.joml.Vector2f;

/**
 * NRD denoiser resources extracted from LightTreeRenderer.
 * Same package; fields are package-private so LightTreeRenderer reads them directly.
 */
final class LightTreeNrdResources {

   // Shader fragment paths — moved from LightTreeRenderer
   static final String classifyTilesFragment        = "lighttree/nrd_classify_tiles.fsh";
   static final String hitDistReconstructionFragment = "lighttree/nrd_hitdist_reconstruction.fsh";
   static final String prepassFragment              = "lighttree/nrd_prepass.fsh";
   static final String copyFragment                 = "lighttree/nrd_copy.fsh";
   static final String atrousSmemFragment           = "lighttree/nrd_atrous_smem.fsh";
   static final String confidenceGradientFragment   = "lighttree/nrd_confidence_gradient.fsh";
   static final String confidenceBlurFragment       = "lighttree/nrd_confidence_blur.fsh";

   // NRD permanent (swap-buffered) ColorFramebuffers — package-private
   final ColorFramebuffer diffIllumPrevFb;
   final ColorFramebuffer diffIllumResponsivePrevFb;
   final ColorFramebuffer specIllumPrevFb;
   final ColorFramebuffer specIllumResponsivePrevFb;
   final ColorFramebuffer historyLengthPrevFb;
   final ColorFramebuffer reflectionHitTPrevFb;

   // NRD transient (single-buffered) ColorFramebuffers — package-private
   final ColorFramebuffer tilesFb;
   final ColorFramebuffer diffIllumPingFb;
   final ColorFramebuffer diffIllumPongFb;
   final ColorFramebuffer specIllumPingFb;
   final ColorFramebuffer specIllumPongFb;
   final ColorFramebuffer historyLengthFb;
   final ColorFramebuffer specReprojectionConfidenceFb;
   final ColorFramebuffer reflectionHitTCurrFb;
   final ColorFramebuffer outDiffRadianceHitDistFb;
   final ColorFramebuffer outSpecRadianceHitDistFb;
   final ColorFramebuffer diffHitDistReconFb;
   final ColorFramebuffer specHitDistReconFb;

   // Confidence cascade ColorFramebuffers — package-private
   final ColorFramebuffer confidenceGradientFb;
   final ColorFramebuffer confidenceBlurPingFb;
   final ColorFramebuffer confidenceBlurPongFb;

   // NRD RoutingFramebuffers — package-private
   final RoutingFramebuffer classifyTilesFramebuffer;
   final RoutingFramebuffer hitDistReconstructionFramebuffer;
   final RoutingFramebuffer prepassFramebuffer;
   final RoutingFramebuffer copyFramebuffer;
   final RoutingFramebuffer atrousSmemFramebuffer;
   final RoutingFramebuffer confidenceGradientFramebuffer;
   final RoutingFramebuffer confidenceBlurFramebuffer;

   // NRD CompositeRenderers — non-final, assigned by LightTreeRenderer's shader-compile callback
   @Nullable CompositeRenderer classifyTilesRenderer;
   @Nullable CompositeRenderer hitDistReconstructionRenderer;
   @Nullable CompositeRenderer prepassRenderer;
   @Nullable CompositeRenderer copyRenderer;
   @Nullable CompositeRenderer atrousSmemRenderer;
   @Nullable CompositeRenderer confidenceGradientRenderer;
   @Nullable CompositeRenderer confidenceBlurRenderer;

   /**
    * @param renderScale             current render scale
    * @param reservoirResolution     supplier for the reservoir (possibly checkerboard) resolution,
    *                                used by the tile framebuffer size calculation
    * @param confidenceBlurOutput    supplier for the dynamic ping-pong output texture used by
    *                                nrdConfidenceBlurFramebuffer; evaluated at bind-time each pass
    */
   LightTreeNrdResources(
      float renderScale,
      Supplier<Vector2f> reservoirResolution,
      Supplier<TextureObject> confidenceBlurOutput
   ) {
      // Permanent (swap-buffered) FBOs
      this.diffIllumPrevFb          = createSignalFb(renderScale, "RGBA16F");
      this.diffIllumResponsivePrevFb = createSignalFb(renderScale, "RGBA16F");
      this.specIllumPrevFb          = createSignalFb(renderScale, "RGBA16F");
      this.specIllumResponsivePrevFb = createSignalFb(renderScale, "RGBA16F");
      this.historyLengthPrevFb      = createSignalFb(renderScale, "R8");
      this.reflectionHitTPrevFb     = createSignalFb(renderScale, "R16F");

      // Transient FBOs
      this.tilesFb                  = createTileFb(renderScale, reservoirResolution);
      this.diffIllumPingFb          = createSignalFb(renderScale, "RGBA16F");
      this.diffIllumPongFb          = createSignalFb(renderScale, "RGBA16F");
      this.specIllumPingFb          = createSignalFb(renderScale, "RGBA16F");
      this.specIllumPongFb          = createSignalFb(renderScale, "RGBA16F");
      this.historyLengthFb          = createSignalFb(renderScale, "R8");
      this.specReprojectionConfidenceFb = createSignalFb(renderScale, "R8");
      this.reflectionHitTCurrFb     = createSignalFb(renderScale, "R16F");
      this.outDiffRadianceHitDistFb = createSignalFb(renderScale, "RGBA16F");
      this.outSpecRadianceHitDistFb = createSignalFb(renderScale, "RGBA16F");
      this.diffHitDistReconFb       = createSignalFb(renderScale, "RGBA16F");
      this.specHitDistReconFb       = createSignalFb(renderScale, "RGBA16F");

      // Confidence cascade FBOs
      this.confidenceGradientFb     = createSignalFb(renderScale, "RGBA16F");
      this.confidenceBlurPingFb     = createSignalFb(renderScale, "RGBA16F");
      this.confidenceBlurPongFb     = createSignalFb(renderScale, "RGBA16F");

      // RoutingFramebuffers
      this.classifyTilesFramebuffer         = createClassifyTilesFramebuffer();
      this.hitDistReconstructionFramebuffer = createHitDistReconstructionFramebuffer();
      this.prepassFramebuffer               = createOutRadianceHitDistFramebuffer();
      this.copyFramebuffer                  = createOutRadianceHitDistFramebuffer();
      this.atrousSmemFramebuffer            = createAtrousSmemFramebuffer();
      this.confidenceGradientFramebuffer    = createConfidenceGradientFramebuffer();
      this.confidenceBlurFramebuffer        = createConfidenceBlurFramebuffer(confidenceBlurOutput);
   }

   /** Call once per frame (replaces the per-field nrdXxx.updatePerFrame() calls). */
   void updatePerFrame() {
      this.diffIllumPrevFb.updatePerFrame();
      this.diffIllumResponsivePrevFb.updatePerFrame();
      this.specIllumPrevFb.updatePerFrame();
      this.specIllumResponsivePrevFb.updatePerFrame();
      this.historyLengthPrevFb.updatePerFrame();
      this.reflectionHitTPrevFb.updatePerFrame();
      this.tilesFb.updatePerFrame();
      this.diffIllumPingFb.updatePerFrame();
      this.diffIllumPongFb.updatePerFrame();
      this.specIllumPingFb.updatePerFrame();
      this.specIllumPongFb.updatePerFrame();
      this.historyLengthFb.updatePerFrame();
      this.specReprojectionConfidenceFb.updatePerFrame();
      this.reflectionHitTCurrFb.updatePerFrame();
      this.outDiffRadianceHitDistFb.updatePerFrame();
      this.outSpecRadianceHitDistFb.updatePerFrame();
      this.diffHitDistReconFb.updatePerFrame();
      this.specHitDistReconFb.updatePerFrame();
      this.confidenceGradientFb.updatePerFrame();
      this.confidenceBlurPingFb.updatePerFrame();
      this.confidenceBlurPongFb.updatePerFrame();
   }

   void free() {
      this.diffIllumPrevFb.destroy();
      this.diffIllumResponsivePrevFb.destroy();
      this.specIllumPrevFb.destroy();
      this.specIllumResponsivePrevFb.destroy();
      this.historyLengthPrevFb.destroy();
      this.reflectionHitTPrevFb.destroy();
      this.tilesFb.destroy();
      this.diffIllumPingFb.destroy();
      this.diffIllumPongFb.destroy();
      this.specIllumPingFb.destroy();
      this.specIllumPongFb.destroy();
      this.historyLengthFb.destroy();
      this.specReprojectionConfidenceFb.destroy();
      this.reflectionHitTCurrFb.destroy();
      this.outDiffRadianceHitDistFb.destroy();
      this.outSpecRadianceHitDistFb.destroy();
      this.diffHitDistReconFb.destroy();
      this.specHitDistReconFb.destroy();
      this.confidenceGradientFb.destroy();
      this.confidenceBlurPingFb.destroy();
      this.confidenceBlurPongFb.destroy();
      this.classifyTilesFramebuffer.destroy();
      this.hitDistReconstructionFramebuffer.destroy();
      this.prepassFramebuffer.destroy();
      this.copyFramebuffer.destroy();
      this.atrousSmemFramebuffer.destroy();
      this.confidenceGradientFramebuffer.destroy();
      this.confidenceBlurFramebuffer.destroy();
   }

   // -------------------------------------------------------------------------
   // Private factory methods
   // -------------------------------------------------------------------------

   private static ColorFramebuffer createSignalFb(float renderScale, String format) {
      ColorFramebuffer fb = new ColorFramebuffer(renderScale);
      fb.createAttachment("data", format, false);
      return fb;
   }

   private static ColorFramebuffer createTileFb(float renderScale, Supplier<Vector2f> reservoirResolution) {
      // Tile classifier runs at ceil(w/16) x ceil(h/16).
      Supplier<Vector2f> tileSizeSupplier = () -> {
         Vector2f base = reservoirResolution.get();
         return new Vector2f(
            (float) Math.ceil(base.x / 16.0),
            (float) Math.ceil(base.y / 16.0)
         );
      };
      ColorFramebuffer fb = new ColorFramebuffer(tileSizeSupplier, renderScale);
      fb.createAttachment("data", "R8", false);
      return fb;
   }

   private RoutingFramebuffer createClassifyTilesFramebuffer() {
      return RoutingFramebuffer.create(() -> this.tilesFb.getWriteAttachment("data"));
   }

   private RoutingFramebuffer createHitDistReconstructionFramebuffer() {
      return RoutingFramebuffer.create(
         () -> this.diffHitDistReconFb.getWriteAttachment("data"),
         () -> this.specHitDistReconFb.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createOutRadianceHitDistFramebuffer() {
      return RoutingFramebuffer.create(
         () -> this.outDiffRadianceHitDistFb.getWriteAttachment("data"),
         () -> this.outSpecRadianceHitDistFb.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createAtrousSmemFramebuffer() {
      return RoutingFramebuffer.create(
         () -> this.diffIllumPongFb.getWriteAttachment("data"),
         () -> this.specIllumPongFb.getWriteAttachment("data")
      );
   }

   private RoutingFramebuffer createConfidenceGradientFramebuffer() {
      return RoutingFramebuffer.create(() -> this.confidenceGradientFb.getWriteAttachment("data"));
   }

   private static RoutingFramebuffer createConfidenceBlurFramebuffer(Supplier<TextureObject> outputSupplier) {
      return RoutingFramebuffer.create(outputSupplier);
   }
}
