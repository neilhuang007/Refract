package at.redi2go.photonic.client.rendering.opengl.rendering.renderers;

import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.opengl.rendering.ColorFramebuffer;
import at.redi2go.photonic.client.rendering.opengl.rendering.RoutingFramebuffer;
import java.util.function.IntSupplier;
import java.util.function.Supplier;
import net.irisshaders.iris.pipeline.CompositeRenderer;
import org.jetbrains.annotations.Nullable;
import org.joml.Vector2f;

/**
 * ReSTIR GI / indirect-lighting resources extracted from LightTreeRenderer.
 * Same package; fields are package-private so LightTreeRenderer reads them directly.
 */
final class LightTreeIndirectResources {

   // Indirect ColorFramebuffers — package-private final
   final ColorFramebuffer indirectInitialReservoirBuffer;
   final ColorFramebuffer indirectReservoirBuffer;
   final ColorFramebuffer indirectDenoisedBuffer;

   // Indirect RoutingFramebuffers — package-private final
   final RoutingFramebuffer proposalFramebuffer;
   final RoutingFramebuffer proposalReservoirFramebuffer;
   final RoutingFramebuffer reuseResolveFramebuffer;
   final RoutingFramebuffer indirectInitialFramebuffer;
   final RoutingFramebuffer indirectBoilingFramebuffer;
   final RoutingFramebuffer indirectAccumulationFramebuffer;
   final RoutingFramebuffer indirectAccumulationLightingFramebuffer;
   final RoutingFramebuffer indirectAccumulationReservoirFramebuffer;
   final RoutingFramebuffer indirectDenoisingFramebuffer;
   final RoutingFramebuffer positionWriteFramebuffer;
   final RoutingFramebuffer shadeSamplesMonolithicFramebuffer;
   final RoutingFramebuffer shadeSamplesFramebuffer;
   final RoutingFramebuffer shadeSamplesReservoirFramebuffer;
   final RoutingFramebuffer shadeSamplesReconnectionFramebuffer;

   // Indirect CompositeRenderers — non-final, assigned by LightTreeRenderer's shader-compile callback
   @Nullable CompositeRenderer proposalStageRenderer;
   @Nullable CompositeRenderer proposalReservoirRenderer;
   @Nullable CompositeRenderer reuseResolveRenderer;
   @Nullable CompositeRenderer indirectInitialRenderer;
   @Nullable CompositeRenderer indirectBoilingRenderer;
   @Nullable CompositeRenderer indirectTemporalReprojectionRenderer;
   @Nullable CompositeRenderer indirectTemporalBinningOffsetsRenderer;
   @Nullable CompositeRenderer indirectTemporalBinningRenderer;
   @Nullable CompositeRenderer indirectScatterTemporalRenderer;
   @Nullable CompositeRenderer indirectAccumulationRenderer;
   @Nullable CompositeRenderer indirectAccumulationLightingRenderer;
   @Nullable CompositeRenderer indirectAccumulationReservoirRenderer;
   @Nullable CompositeRenderer indirectDenoisingRenderer;
   @Nullable CompositeRenderer accumulationRenderer;
   @Nullable CompositeRenderer indirectRenderer;
   @Nullable CompositeRenderer shadeSamplesMonolithicRenderer;
   @Nullable CompositeRenderer shadeSamplesReservoirRenderer;
   @Nullable CompositeRenderer shadeSamplesRenderer;
   @Nullable CompositeRenderer shadeSamplesReconnectionRenderer;

   /**
    * @param renderScale                   render scale passed to ColorFramebuffer constructors
    * @param reservoirResolutionSupplier   supplier for the half/full reservoir resolution Vector2f
    * @param directPackedViewportWidth     supplier for the checkerboard-aware packed viewport width
    * @param lightingBuffer                full-res ping-pong geometry/lighting buffer (stays in renderer)
    * @param lightingStageBuffer           geometry stage buffer written by the proposal pass
    * @param motionVectorBuffer            motion vector buffer written by the proposal pass
    * @param directReservoirBuffer         persistent DI reservoir buffer (owned by renderer)
    * @param directSpatialReservoirBuffer  post-spatial DI reservoir buffer (owned by renderer)
    * @param compatDirectSoftBuffer        compat direct-soft buffer (owned by renderer)
    * @param directRes                     direct resources holder; provides reconnection buffers
    */
   LightTreeIndirectResources(
      float renderScale,
      Supplier<Vector2f> reservoirResolutionSupplier,
      IntSupplier directPackedViewportWidth,
      ColorFramebuffer lightingBuffer,
      ColorFramebuffer lightingStageBuffer,
      ColorFramebuffer motionVectorBuffer,
      ColorFramebuffer directReservoirBuffer,
      ColorFramebuffer directSpatialReservoirBuffer,
      ColorFramebuffer compatDirectSoftBuffer,
      LightTreeDirectResources directRes
   ) {
      // ColorFramebuffers — constructed first; routing framebuffers reference them via suppliers
      this.indirectInitialReservoirBuffer = createIndirectReservoirFramebuffer(renderScale, reservoirResolutionSupplier);
      this.indirectReservoirBuffer        = createIndirectReservoirFramebuffer(renderScale, reservoirResolutionSupplier);
      this.indirectDenoisedBuffer         = createIndirectDenoisedFramebuffer(renderScale);

      // RoutingFramebuffers — constructed after the ColorFramebuffers they reference
      this.proposalFramebuffer                    = createProposalGeometryFramebuffer(lightingStageBuffer, motionVectorBuffer);
      this.proposalReservoirFramebuffer           = createProposalReservoirFramebuffer(directPackedViewportWidth, directReservoirBuffer, directRes);
      this.reuseResolveFramebuffer                = createReuseResolveFramebuffer(directPackedViewportWidth, directSpatialReservoirBuffer, directRes);
      this.indirectInitialFramebuffer             = createReservoirFramebuffer(this.indirectInitialReservoirBuffer);
      this.indirectBoilingFramebuffer             = createReservoirFramebuffer(this.indirectReservoirBuffer);
      this.indirectAccumulationFramebuffer        = createIndirectAccumulationFramebuffer(lightingBuffer, this.indirectReservoirBuffer);
      this.indirectAccumulationLightingFramebuffer = createIndirectAccumulationLightingFramebuffer(lightingBuffer);
      this.indirectAccumulationReservoirFramebuffer = createIndirectAccumulationReservoirFramebuffer(directPackedViewportWidth, this.indirectReservoirBuffer);
      this.indirectDenoisingFramebuffer           = createIndirectDenoisingFramebuffer(this.indirectDenoisedBuffer);
      this.positionWriteFramebuffer               = createPositionWriteFramebuffer(lightingBuffer, compatDirectSoftBuffer);
      this.shadeSamplesMonolithicFramebuffer      = createShadeSamplesMonolithicFramebuffer(lightingStageBuffer, directReservoirBuffer);
      this.shadeSamplesFramebuffer                = createShadeSamplesLightingFramebuffer(lightingStageBuffer);
      this.shadeSamplesReservoirFramebuffer       = createShadeSamplesReservoirFramebuffer(directPackedViewportWidth, directReservoirBuffer);
      this.shadeSamplesReconnectionFramebuffer    = createShadeSamplesReconnectionFramebuffer(directPackedViewportWidth, directRes);
   }

   /** Call once per frame (mirrors nrdRes.updatePerFrame() pattern). */
   void updatePerFrame() {
      this.indirectInitialReservoirBuffer.updatePerFrame();
      this.indirectReservoirBuffer.updatePerFrame();
      this.indirectDenoisedBuffer.updatePerFrame();
   }

   /** Destroy all owned framebuffers and renderers. Called from LightTreeRenderer.free(). */
   void free() {
      // ColorFramebuffers
      this.indirectInitialReservoirBuffer.destroy();
      this.indirectReservoirBuffer.destroy();
      this.indirectDenoisedBuffer.destroy();
      // RoutingFramebuffers
      this.proposalFramebuffer.destroy();
      this.proposalReservoirFramebuffer.destroy();
      this.reuseResolveFramebuffer.destroy();
      this.indirectInitialFramebuffer.destroy();
      this.indirectBoilingFramebuffer.destroy();
      this.indirectAccumulationFramebuffer.destroy();
      this.indirectAccumulationLightingFramebuffer.destroy();
      this.indirectAccumulationReservoirFramebuffer.destroy();
      this.indirectDenoisingFramebuffer.destroy();
      this.positionWriteFramebuffer.destroy();
      this.shadeSamplesMonolithicFramebuffer.destroy();
      this.shadeSamplesFramebuffer.destroy();
      this.shadeSamplesReservoirFramebuffer.destroy();
      this.shadeSamplesReconnectionFramebuffer.destroy();
   }

   // -------------------------------------------------------------------------
   // Private factory methods — bodies moved from LightTreeRenderer
   // -------------------------------------------------------------------------

   private static ColorFramebuffer createIndirectReservoirFramebuffer(
      float renderScale,
      Supplier<Vector2f> reservoirResolutionSupplier
   ) {
      ColorFramebuffer framebuffer = new ColorFramebuffer(reservoirResolutionSupplier, renderScale);
      framebuffer.createAttachment("position", "RGBA32F", false);
      // RTXDI packed GI reservoirs store packed normal / misc / radiance as 32-bit values.
      // These attachments are sampled back with floatBitsToUint(...), so 16-bit float formats
      // destroy the packed payload and corrupt M, age, and radiance on load.
      framebuffer.createAttachment("normal", "RGBA32F", false);
      framebuffer.createAttachment("radiance", "RGBA32F", false);
      framebuffer.createAttachment("meta", "RGBA32F", false);
      return framebuffer;
   }

   private static ColorFramebuffer createIndirectDenoisedFramebuffer(float renderScale) {
      ColorFramebuffer framebuffer = new ColorFramebuffer(renderScale);
      framebuffer.createAttachment("data", "RGBA16F", false);
      return framebuffer;
   }

   private static RoutingFramebuffer createProposalGeometryFramebuffer(
      ColorFramebuffer lightingStageBuffer,
      ColorFramebuffer motionVectorBuffer
   ) {
      return RoutingFramebuffer.create(
         () -> lightingStageBuffer.getWriteAttachment("position"),
         () -> lightingStageBuffer.getWriteAttachment("normal"),
         () -> lightingStageBuffer.getWriteAttachment("mapped_normal"),
         () -> lightingStageBuffer.getWriteAttachment("albedo"),
         () -> lightingStageBuffer.getWriteAttachment("material"),
         () -> lightingStageBuffer.getWriteAttachment("identity"),
         () -> motionVectorBuffer.getWriteAttachment("data")
      );
   }

   private static RoutingFramebuffer createProposalReservoirFramebuffer(
      IntSupplier directPackedViewportWidth,
      ColorFramebuffer directReservoirBuffer,
      LightTreeDirectResources directRes
   ) {
      return RoutingFramebuffer.create(
         directPackedViewportWidth,
         () -> directReservoirBuffer.getWriteAttachment("data"),
         () -> directReservoirBuffer.getWriteAttachment("sample"),
         () -> directReservoirBuffer.getWriteAttachment("meta"),
         () -> directRes.proposalReconnectionBuffer.getWriteAttachment("reconnection0"),
         () -> directRes.proposalReconnectionBuffer.getWriteAttachment("reconnection1"),
         () -> directRes.proposalReconnectionBuffer.getWriteAttachment("reconnection2"),
         () -> directRes.proposalReconnectionBuffer.getWriteAttachment("reconnection3"),
         () -> directRes.proposalReconnectionBuffer.getWriteAttachment("reconnection4")
      );
   }

   private static RoutingFramebuffer createReuseResolveFramebuffer(
      IntSupplier directPackedViewportWidth,
      ColorFramebuffer directSpatialReservoirBuffer,
      LightTreeDirectResources directRes
   ) {
      // Spatial reuse writes the paired post-temporal reservoir and reconnection state
      // that the local final resolve stages consume directly in the same frame.
      return RoutingFramebuffer.create(
         directPackedViewportWidth,
         () -> directSpatialReservoirBuffer.getWriteAttachment("data"),
         () -> directSpatialReservoirBuffer.getWriteAttachment("sample"),
         () -> directSpatialReservoirBuffer.getWriteAttachment("meta"),
         () -> directRes.scatterReconnectionBuffer.getWriteAttachment("reconnection0"),
         () -> directRes.scatterReconnectionBuffer.getWriteAttachment("reconnection1"),
         () -> directRes.scatterReconnectionBuffer.getWriteAttachment("reconnection2"),
         () -> directRes.scatterReconnectionBuffer.getWriteAttachment("reconnection3"),
         () -> directRes.scatterReconnectionBuffer.getWriteAttachment("reconnection4")
      );
   }

   // createIndirectInitialFramebuffer and createIndirectBoilingFramebuffer were structurally
   // identical (same 4 attachment names: position/normal/radiance/meta, no draw-buffer override).
   // Collapsed into a single createReservoirFramebuffer helper.
   private static RoutingFramebuffer createReservoirFramebuffer(ColorFramebuffer rb) {
      return RoutingFramebuffer.create(
         () -> rb.getWriteAttachment("position"),
         () -> rb.getWriteAttachment("normal"),
         () -> rb.getWriteAttachment("radiance"),
         () -> rb.getWriteAttachment("meta")
      );
   }

   private static RoutingFramebuffer createIndirectAccumulationFramebuffer(
      ColorFramebuffer lightingBuffer,
      ColorFramebuffer indirectReservoirBuffer
   ) {
      return RoutingFramebuffer.create(
         () -> lightingBuffer.getWriteAttachment("indirect"),
         () -> lightingBuffer.getWriteAttachment("indirect_variance"),
         () -> lightingBuffer.getWriteAttachment("handheld"),
         () -> indirectReservoirBuffer.getWriteAttachment("position"),
         () -> indirectReservoirBuffer.getWriteAttachment("normal"),
         () -> indirectReservoirBuffer.getWriteAttachment("radiance"),
         () -> indirectReservoirBuffer.getWriteAttachment("meta")
      );
   }

   private static RoutingFramebuffer createIndirectAccumulationLightingFramebuffer(ColorFramebuffer lightingBuffer) {
      return RoutingFramebuffer.create(
         () -> lightingBuffer.getWriteAttachment("indirect"),
         () -> lightingBuffer.getWriteAttachment("indirect_variance"),
         () -> lightingBuffer.getWriteAttachment("handheld")
      );
   }

   private static RoutingFramebuffer createIndirectAccumulationReservoirFramebuffer(
      IntSupplier directPackedViewportWidth,
      ColorFramebuffer indirectReservoirBuffer
   ) {
      return RoutingFramebuffer.create(
         directPackedViewportWidth,
         () -> indirectReservoirBuffer.getWriteAttachment("position"),
         () -> indirectReservoirBuffer.getWriteAttachment("normal"),
         () -> indirectReservoirBuffer.getWriteAttachment("radiance"),
         () -> indirectReservoirBuffer.getWriteAttachment("meta")
      );
   }

   private static RoutingFramebuffer createIndirectDenoisingFramebuffer(ColorFramebuffer indirectDenoisedBuffer) {
      return RoutingFramebuffer.create(() -> indirectDenoisedBuffer.getWriteAttachment("data"));
   }

   private static RoutingFramebuffer createPositionWriteFramebuffer(
      ColorFramebuffer lightingBuffer,
      ColorFramebuffer compatDirectSoftBuffer
   ) {
      return RoutingFramebuffer.create(
         () -> lightingBuffer.getWriteAttachment("position"),
         () -> lightingBuffer.getWriteAttachment("normal"),
         () -> lightingBuffer.getWriteAttachment("mapped_normal"),
         () -> lightingBuffer.getWriteAttachment("albedo"),
         () -> lightingBuffer.getWriteAttachment("material"),
         () -> lightingBuffer.getWriteAttachment("identity"),
         () -> lightingBuffer.getWriteAttachment("direct"),
         () -> compatDirectSoftBuffer.getWriteAttachment("direct_soft_compat")
      );
   }

   private static RoutingFramebuffer createShadeSamplesMonolithicFramebuffer(
      ColorFramebuffer lightingStageBuffer,
      ColorFramebuffer directReservoirBuffer
   ) {
      return RoutingFramebuffer.create(
         () -> lightingStageBuffer.getWriteAttachment("direct"),
         () -> lightingStageBuffer.getWriteAttachment("direct_specular"),
         () -> directReservoirBuffer.getWriteAttachment("data"),
         () -> directReservoirBuffer.getWriteAttachment("sample"),
         () -> directReservoirBuffer.getWriteAttachment("meta"),
         () -> lightingStageBuffer.getWriteAttachment("direct_combined")
      );
   }

   private static RoutingFramebuffer createShadeSamplesLightingFramebuffer(ColorFramebuffer lightingStageBuffer) {
      return RoutingFramebuffer.create(
         () -> lightingStageBuffer.getWriteAttachment("direct"),
         () -> lightingStageBuffer.getWriteAttachment("direct_specular"),
         () -> lightingStageBuffer.getWriteAttachment("direct_combined")
      );
   }

   private static RoutingFramebuffer createShadeSamplesReservoirFramebuffer(
      IntSupplier directPackedViewportWidth,
      ColorFramebuffer directReservoirBuffer
   ) {
      // Reservoir finalization is the only promotion step from authoritative
      // same-frame post-spatial output into persistent direct history.
      return RoutingFramebuffer.create(
         directPackedViewportWidth,
         () -> directReservoirBuffer.getWriteAttachment("data"),
         () -> directReservoirBuffer.getWriteAttachment("sample"),
         () -> directReservoirBuffer.getWriteAttachment("meta")
      );
   }

   private static RoutingFramebuffer createShadeSamplesReconnectionFramebuffer(
      IntSupplier directPackedViewportWidth,
      LightTreeDirectResources directRes
   ) {
      return RoutingFramebuffer.create(
         directPackedViewportWidth,
         () -> directRes.scatterReconnectionBuffer.getWriteAttachment("reconnection0"),
         () -> directRes.scatterReconnectionBuffer.getWriteAttachment("reconnection1"),
         () -> directRes.scatterReconnectionBuffer.getWriteAttachment("reconnection2"),
         () -> directRes.scatterReconnectionBuffer.getWriteAttachment("reconnection3"),
         () -> directRes.scatterReconnectionBuffer.getWriteAttachment("reconnection4")
      );
   }
}
