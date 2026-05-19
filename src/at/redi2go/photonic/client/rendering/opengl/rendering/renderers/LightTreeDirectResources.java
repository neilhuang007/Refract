package at.redi2go.photonic.client.rendering.opengl.rendering.renderers;

import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.opengl.rendering.ColorFramebuffer;
import at.redi2go.photonic.client.rendering.opengl.rendering.RoutingFramebuffer;
import java.util.function.IntSupplier;
import java.util.function.Supplier;
import net.irisshaders.iris.pipeline.CompositeRenderer;
import org.jetbrains.annotations.Nullable;

/**
 * ReSTIR DI resources extracted from LightTreeRenderer.
 * Same package; fields are package-private so LightTreeRenderer reads them directly.
 */
final class LightTreeDirectResources {

   // DI ColorFramebuffers — package-private final
   final ColorFramebuffer directInitialDebugBuffer;
   final ColorFramebuffer proposalReconnectionBuffer;
   final ColorFramebuffer temporalReconnectionBuffer;
   final ColorFramebuffer scatterReconnectionBuffer;
   final ColorFramebuffer temporalReservoirBuffer;
   final ColorFramebuffer temporalGatherBuffer;

   // DI RoutingFramebuffers — package-private final
   final RoutingFramebuffer temporalScatterStageFramebuffer;
   final RoutingFramebuffer temporalCollectFramebuffer;
   final RoutingFramebuffer robustReuseOptimizationFramebuffer;
   final RoutingFramebuffer temporalReservoirFramebuffer;
   final RoutingFramebuffer directTemporalFramebuffer;
   final RoutingFramebuffer directHistoryFixFramebuffer;
   final RoutingFramebuffer directHistoryClampingFramebuffer;
   final RoutingFramebuffer directAntiFireflyFramebuffer;
   final RoutingFramebuffer directAtrousFramebuffer;

   // DI CompositeRenderers — non-final, assigned by LightTreeRenderer's shader-compile callback
   @Nullable CompositeRenderer directTemporalRenderer;
   @Nullable CompositeRenderer directHistoryFixRenderer;
   @Nullable CompositeRenderer directHistoryClampingRenderer;
   @Nullable CompositeRenderer directAntiFireflyRenderer;
   @Nullable CompositeRenderer directAtrousRenderer;
   @Nullable CompositeRenderer temporalCollectRenderer;
   @Nullable CompositeRenderer robustReuseOptimizationRenderer;
   @Nullable CompositeRenderer temporalGatherRenderer;
   @Nullable CompositeRenderer temporalScatterReprojectionRenderer;
   @Nullable CompositeRenderer temporalMultiScatterReprojectionRenderer;
   @Nullable CompositeRenderer temporalScatterBinningOffsetsRenderer;
   @Nullable CompositeRenderer temporalMultiScatterBinningOffsetsRenderer;
   @Nullable CompositeRenderer temporalScatterBinningRenderer;
   @Nullable CompositeRenderer temporalMultiScatterBinningRenderer;
   @Nullable CompositeRenderer scatterTemporalRenderer;
   @Nullable CompositeRenderer scatterBackupTemporalRenderer;
   @Nullable CompositeRenderer multiScatterTemporalRenderer;

   /**
    * @param renderScale                supplier for the reservoir resolution size function;
    *                                   passed directly to ColorFramebuffer constructors
    * @param reservoirResolutionSupplier supplier for the direct reservoir resolution Vector2f,
    *                                   forwarded to ColorFramebuffers that use checkerboard sizing
    * @param directPackedViewportWidth  supplier for the checkerboard-aware viewport width,
    *                                   used by direct-packed RoutingFramebuffers
    * @param nrdRes                     the NRD resources holder, needed by the direct-temporal
    *                                   routing framebuffers whose attachments reference NRD FBOs
    * @param diffAtrousOutput           supplier for the current diff atrous output texture,
    *                                   used by directAtrousFramebuffer (ping-pong, frame-local)
    * @param specAtrousOutput           supplier for the current spec atrous output texture,
    *                                   used by directAtrousFramebuffer (ping-pong, frame-local)
    */
   LightTreeDirectResources(
      float renderScale,
      Supplier<org.joml.Vector2f> reservoirResolutionSupplier,
      IntSupplier directPackedViewportWidth,
      LightTreeNrdResources nrdRes,
      Supplier<TextureObject> diffAtrousOutput,
      Supplier<TextureObject> specAtrousOutput
   ) {
      this.directInitialDebugBuffer      = createDirectPackedDebugFramebuffer(renderScale, reservoirResolutionSupplier);
      this.proposalReconnectionBuffer    = createReconnectionFramebuffer(renderScale, reservoirResolutionSupplier);
      this.temporalReconnectionBuffer    = createReconnectionFramebuffer(renderScale, reservoirResolutionSupplier);
      this.scatterReconnectionBuffer     = createReconnectionFramebuffer(renderScale, reservoirResolutionSupplier);
      this.temporalReservoirBuffer       = createTemporalReservoirFramebuffer(renderScale, reservoirResolutionSupplier);
      this.temporalGatherBuffer          = createTemporalGatherFramebuffer(renderScale, reservoirResolutionSupplier);

      // RoutingFramebuffers — constructed after the ColorFramebuffers they reference
      this.temporalScatterStageFramebuffer       = createTemporalScatterStageFramebuffer(directPackedViewportWidth);
      this.temporalCollectFramebuffer            = createTemporalCollectFramebuffer(directPackedViewportWidth);
      this.robustReuseOptimizationFramebuffer    = createRobustReuseOptimizationFramebuffer(directPackedViewportWidth);
      this.temporalReservoirFramebuffer          = createTemporalReservoirRoutingFramebuffer(directPackedViewportWidth);
      this.directTemporalFramebuffer             = createDirectTemporalFramebuffer(nrdRes);
      this.directHistoryFixFramebuffer           = createDirectHistoryFixFramebuffer(nrdRes);
      this.directHistoryClampingFramebuffer      = createDirectHistoryClampingFramebuffer(nrdRes);
      this.directAntiFireflyFramebuffer          = createDirectAntiFireflyFramebuffer(nrdRes);
      this.directAtrousFramebuffer               = createDirectAtrousFramebuffer(diffAtrousOutput, specAtrousOutput);
   }

   /** Call once per frame (replaces the per-field updatePerFrame() calls for moved FBOs). */
   void updatePerFrame() {
      this.directInitialDebugBuffer.updatePerFrame();
      this.proposalReconnectionBuffer.updatePerFrame();
      this.temporalReconnectionBuffer.updatePerFrame();
      this.scatterReconnectionBuffer.updatePerFrame();
      this.temporalReservoirBuffer.updatePerFrame();
      this.temporalGatherBuffer.updatePerFrame();
   }

   /** Destroy all owned framebuffers. Called from LightTreeRenderer.free(). */
   void free() {
      this.directInitialDebugBuffer.destroy();
      this.proposalReconnectionBuffer.destroy();
      this.temporalReconnectionBuffer.destroy();
      this.scatterReconnectionBuffer.destroy();
      this.temporalReservoirBuffer.destroy();
      this.temporalGatherBuffer.destroy();
      this.temporalScatterStageFramebuffer.destroy();
      this.temporalCollectFramebuffer.destroy();
      this.robustReuseOptimizationFramebuffer.destroy();
      this.temporalReservoirFramebuffer.destroy();
      this.directTemporalFramebuffer.destroy();
      this.directHistoryFixFramebuffer.destroy();
      this.directHistoryClampingFramebuffer.destroy();
      this.directAntiFireflyFramebuffer.destroy();
      this.directAtrousFramebuffer.destroy();
   }

   // -------------------------------------------------------------------------
   // Private factory methods — bodies moved from LightTreeRenderer
   // -------------------------------------------------------------------------

   private static ColorFramebuffer createDirectPackedDebugFramebuffer(
      float renderScale,
      Supplier<org.joml.Vector2f> reservoirResolutionSupplier
   ) {
      ColorFramebuffer framebuffer = new ColorFramebuffer(reservoirResolutionSupplier, renderScale);
      framebuffer.createAttachment("data", "RGBA16F", false);
      return framebuffer;
   }

   private static ColorFramebuffer createReconnectionFramebuffer(
      float renderScale,
      Supplier<org.joml.Vector2f> reservoirResolutionSupplier
   ) {
      ColorFramebuffer framebuffer = new ColorFramebuffer(reservoirResolutionSupplier, renderScale);
      // DI reconnection payload split across five RGBA32F targets:
      // reconnection0: firstHit.worldPos.xyz, firstHit.viewDepth
      // reconnection1: secondHit.worldPos.xyz, packed lightPdf/subPixelJacobian
      // reconnection2: irradiance.xyz, packed discrete metadata
      // reconnection3: earlyThroughput.xyz, packed lensVertexJacobian/secondaryPathJacobian
      // reconnection4: packed subPixel, packed lensSample, packed firstWi, packed secondWo
      // reservoir transport aux: secondHit.viewDepth, packed face ids
      framebuffer.createLayeredAttachmentGroup(
         new String[]{"reconnection0", "reconnection1", "reconnection2", "reconnection3", "reconnection4"},
         "RGBA32F", false);
      return framebuffer;
   }

   private static ColorFramebuffer createTemporalReservoirFramebuffer(
      float renderScale,
      Supplier<org.joml.Vector2f> reservoirResolutionSupplier
   ) {
      // Same format as directReservoirBuffer - holds the temporal resampling output
      // that feeds into spatial resampling. Single-buffered (produced & consumed same frame).
      ColorFramebuffer framebuffer = new ColorFramebuffer(reservoirResolutionSupplier, renderScale);
      framebuffer.createAttachment("data", "RGBA32F", false);
      framebuffer.createAttachment("sample", "RGBA32F", false);
      framebuffer.createAttachment("meta", "RGBA32F", false);
      return framebuffer;
   }

   private static ColorFramebuffer createTemporalGatherFramebuffer(
      float renderScale,
      Supplier<org.joml.Vector2f> reservoirResolutionSupplier
   ) {
      ColorFramebuffer framebuffer = new ColorFramebuffer(reservoirResolutionSupplier, renderScale);
      framebuffer.createAttachment("intermediate_data", "RGBA32F", false);
      framebuffer.createAttachment("intermediate_sample", "RGBA32F", false);
      framebuffer.createAttachment("intermediate_meta", "RGBA32F", false);
      framebuffer.createLayeredAttachmentGroup(
         new String[]{"intermediate_reconnection0", "intermediate_reconnection1", "intermediate_reconnection2", "intermediate_reconnection3", "intermediate_reconnection4"},
         "RGBA32F", false);
      return framebuffer;
   }

   private RoutingFramebuffer createTemporalScatterStageFramebuffer(IntSupplier directPackedViewportWidth) {
      RoutingFramebuffer framebuffer = RoutingFramebuffer.create(
         directPackedViewportWidth,
         () -> this.directInitialDebugBuffer.getWriteAttachment("data"),
         () -> this.directInitialDebugBuffer.getWriteAttachment("data"),
         () -> this.directInitialDebugBuffer.getWriteAttachment("data")
      );
      framebuffer.setDrawBuffers(new int[] {-1});
      return framebuffer;
   }

   private RoutingFramebuffer createTemporalCollectFramebuffer(IntSupplier directPackedViewportWidth) {
      return RoutingFramebuffer.create(
         directPackedViewportWidth,
         () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_data"),
         () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_sample"),
         () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_meta"),
         () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection0"),
         () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection1"),
         () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection2"),
         () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection3"),
         () -> this.temporalGatherBuffer.getWriteAttachment("intermediate_reconnection4")
      );
   }

   private RoutingFramebuffer createRobustReuseOptimizationFramebuffer(IntSupplier directPackedViewportWidth) {
      RoutingFramebuffer framebuffer = RoutingFramebuffer.create(
         directPackedViewportWidth,
         () -> this.directInitialDebugBuffer.getWriteAttachment("data")
      );
      framebuffer.setDrawBuffers(new int[] {-1});
      return framebuffer;
   }

   private RoutingFramebuffer createTemporalReservoirRoutingFramebuffer(IntSupplier directPackedViewportWidth) {
      return RoutingFramebuffer.create(
         directPackedViewportWidth,
         () -> this.temporalReservoirBuffer.getWriteAttachment("data"),
         () -> this.temporalReservoirBuffer.getWriteAttachment("sample"),
         () -> this.temporalReservoirBuffer.getWriteAttachment("meta"),
         () -> this.temporalReconnectionBuffer.getWriteAttachment("reconnection0"),
         () -> this.temporalReconnectionBuffer.getWriteAttachment("reconnection1"),
         () -> this.temporalReconnectionBuffer.getWriteAttachment("reconnection2"),
         () -> this.temporalReconnectionBuffer.getWriteAttachment("reconnection3"),
         () -> this.temporalReconnectionBuffer.getWriteAttachment("reconnection4")
      );
   }

   // Temporal accumulation: 7 outputs per contract §7
   //   loc 0 -> nrdRes.historyLengthFb
   //   loc 1 -> nrdRes.diffIllumPingFb
   //   loc 2 -> nrdRes.specIllumPingFb
   //   loc 3 -> nrdRes.diffIllumPongFb
   //   loc 4 -> nrdRes.specIllumPongFb
   //   loc 5 -> nrdRes.reflectionHitTCurrFb
   //   loc 6 -> nrdRes.specReprojectionConfidenceFb
   private static RoutingFramebuffer createDirectTemporalFramebuffer(LightTreeNrdResources nrdRes) {
      return RoutingFramebuffer.create(
         () -> nrdRes.historyLengthFb.getWriteAttachment("data"),
         () -> nrdRes.diffIllumPingFb.getWriteAttachment("data"),
         () -> nrdRes.specIllumPingFb.getWriteAttachment("data"),
         () -> nrdRes.diffIllumPongFb.getWriteAttachment("data"),
         () -> nrdRes.specIllumPongFb.getWriteAttachment("data"),
         () -> nrdRes.reflectionHitTCurrFb.getWriteAttachment("data"),
         () -> nrdRes.specReprojectionConfidenceFb.getWriteAttachment("data")
      );
   }

   // History fix: 2 outputs -> pong buffers (loc 0 = diff pong, loc 1 = spec pong)
   private static RoutingFramebuffer createDirectHistoryFixFramebuffer(LightTreeNrdResources nrdRes) {
      return RoutingFramebuffer.create(
         () -> nrdRes.diffIllumPongFb.getWriteAttachment("data"),
         () -> nrdRes.specIllumPongFb.getWriteAttachment("data")
      );
   }

   // History clamping: 5 outputs -> permanent prev-frame history
   //   loc 0 -> nrdRes.diffIllumPrevFb.write
   //   loc 1 -> nrdRes.diffIllumResponsivePrevFb.write
   //   loc 2 -> nrdRes.specIllumPrevFb.write
   //   loc 3 -> nrdRes.specIllumResponsivePrevFb.write
   //   loc 4 -> nrdRes.historyLengthPrevFb.write
   private static RoutingFramebuffer createDirectHistoryClampingFramebuffer(LightTreeNrdResources nrdRes) {
      return RoutingFramebuffer.create(
         () -> nrdRes.diffIllumPrevFb.getWriteAttachment("data"),
         () -> nrdRes.diffIllumResponsivePrevFb.getWriteAttachment("data"),
         () -> nrdRes.specIllumPrevFb.getWriteAttachment("data"),
         () -> nrdRes.specIllumResponsivePrevFb.getWriteAttachment("data"),
         () -> nrdRes.historyLengthPrevFb.getWriteAttachment("data")
      );
   }

   // Anti-firefly: 2 outputs -> prev-frame illum write sides (post-clamping in-place update)
   private static RoutingFramebuffer createDirectAntiFireflyFramebuffer(LightTreeNrdResources nrdRes) {
      return RoutingFramebuffer.create(
         () -> nrdRes.diffIllumPrevFb.getWriteAttachment("data"),
         () -> nrdRes.specIllumPrevFb.getWriteAttachment("data")
      );
   }

   // Regular A-trous: 2 outputs via ping-pong routing helpers (frame-local suppliers)
   private static RoutingFramebuffer createDirectAtrousFramebuffer(
      Supplier<TextureObject> diffAtrousOutput,
      Supplier<TextureObject> specAtrousOutput
   ) {
      return RoutingFramebuffer.create(diffAtrousOutput, specAtrousOutput);
   }
}
