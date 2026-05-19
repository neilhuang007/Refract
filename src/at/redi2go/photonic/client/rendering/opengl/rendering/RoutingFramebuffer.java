package at.redi2go.photonic.client.rendering.opengl.rendering;

import at.redi2go.photonic.client.rendering.opengl.GL;
import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.util.BufferUtils;
import com.mojang.blaze3d.platform.GlStateManager;
import java.nio.IntBuffer;
import java.util.ArrayList;
import java.util.List;
import java.util.function.IntSupplier;
import java.util.function.Supplier;
import net.minecraft.client.MinecraftClient;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL20;
import org.lwjgl.opengl.GL30;

public class RoutingFramebuffer extends ColorFramebuffer {
   private final List<Supplier<TextureObject>> attachmentSuppliers = new ArrayList<>();
   private final Supplier<Integer> viewportWidthSupplier;
   private int[] routingDrawBuffers;
   private int previousDrawFramebuffer;

   public RoutingFramebuffer() {
      this(null);
   }

   public RoutingFramebuffer(Supplier<Integer> viewportWidthSupplier) {
      super(1.0f);
      this.viewportWidthSupplier = viewportWidthSupplier;
   }

   public void addAttachment(Supplier<TextureObject> attachmentSupplier) {
      this.attachmentSuppliers.add(attachmentSupplier);
   }

   @Override
   public void setDrawBuffers(int[] drawBuffers) {
      this.routingDrawBuffers = drawBuffers == null ? null : drawBuffers.clone();
   }

   @Override
   public void bind() {
      this.previousDrawFramebuffer = GL11.glGetInteger(GL30.GL_DRAW_FRAMEBUFFER_BINDING);
      GlStateManager._glBindFramebuffer(GL30.GL_DRAW_FRAMEBUFFER, this.getId());

      int width = 0;
      int height = 0;
      int attachmentIndex = 0;
      for (Supplier<TextureObject> attachmentSupplier : this.attachmentSuppliers) {
         TextureObject attachment = attachmentSupplier.get();
         if (attachment == null) {
            throw new NullPointerException("Routing framebuffer attachment supplier returned null");
         }

         attachment.updatePerFrame();
         if (attachmentIndex == 0) {
            int[] dimensions = attachment.getTextureDimensions();
            if (dimensions.length >= 2) {
               width = dimensions[0];
               height = dimensions[1];
            }
         }

         if (attachment instanceof ColorFramebuffer.FramebufferAttachment fba && fba.isLayered()) {
            GL30.glFramebufferTextureLayer(
               GL30.GL_DRAW_FRAMEBUFFER,
               GL30.GL_COLOR_ATTACHMENT0 + attachmentIndex,
               attachment.getTextureId(),
               0,
               fba.getArrayLayer()
            );
            GL.logGlError("RoutingFramebuffer.glFramebufferTextureLayer(index=" + attachmentIndex + ", layer=" + fba.getArrayLayer() + ")");
         } else {
            GL30.glFramebufferTexture2D(
               GL30.GL_DRAW_FRAMEBUFFER,
               GL30.GL_COLOR_ATTACHMENT0 + attachmentIndex,
               attachment.getTarget(),
               attachment.getTextureId(),
               0
            );
            GL.logGlError("RoutingFramebuffer.glFramebufferTexture2D(index=" + attachmentIndex + ", target=" + attachment.getTarget() + ")");
         }
         attachmentIndex++;
      }

      int viewportWidth = this.resolveViewportWidth(width);
      GlStateManager._viewport(0, 0, viewportWidth, height);
      int[] resolvedDrawBuffers = ColorFramebuffer.resolveDrawBuffers(this.routingDrawBuffers, attachmentIndex);
      IntBuffer buffer = BufferUtils.createIntBuffer(resolvedDrawBuffers.length);
      for (int drawBuffer : resolvedDrawBuffers) {
         buffer.put(drawBuffer);
      }

      buffer.position(0);
      buffer.limit(resolvedDrawBuffers.length);
      GL20.glDrawBuffers(buffer);
      GL.logGlError("RoutingFramebuffer.glDrawBuffers(count=" + resolvedDrawBuffers.length + ")");
      int status = GL30.glCheckFramebufferStatus(GL30.GL_DRAW_FRAMEBUFFER);
      if (status != GL30.GL_FRAMEBUFFER_COMPLETE) {
         throw new RuntimeException("Framebuffer in invalid state: " + status);
      }
   }

   @Override
   public void unbind() {
      GlStateManager._glBindFramebuffer(GL30.GL_DRAW_FRAMEBUFFER, this.previousDrawFramebuffer);
      int width = MinecraftClient.getInstance().getWindow().getFramebufferWidth();
      int height = MinecraftClient.getInstance().getWindow().getFramebufferHeight();
      GlStateManager._viewport(0, 0, width, height);
      this.previousDrawFramebuffer = 0;
   }

   @Override
   public void clear(org.joml.Vector4f clearColor) {
      this.bind();
      GlStateManager._clearColor(clearColor.x, clearColor.y, clearColor.z, clearColor.w);
      GlStateManager._clear(GL11.GL_COLOR_BUFFER_BIT | GL11.GL_DEPTH_BUFFER_BIT, false);
      this.unbind();
   }

   @Override
   public void updatePerFrame() {
      for (Supplier<TextureObject> attachmentSupplier : this.attachmentSuppliers) {
         TextureObject attachment = attachmentSupplier.get();
         if (attachment != null) {
            attachment.updatePerFrame();
         }
      }
   }

   private int resolveViewportWidth(int fallbackWidth) {
      if (this.viewportWidthSupplier == null) {
         return fallbackWidth;
      }
      Integer viewportWidth = this.viewportWidthSupplier.get();
      if (viewportWidth == null || viewportWidth <= 0) {
         return fallbackWidth;
      }
      return Math.min(viewportWidth, fallbackWidth);
   }

   @Override
   public void swap() {
   }

   // -------------------------------------------------------------------------
   // Canonical static factory helpers — shared by all LightTree resource classes
   // -------------------------------------------------------------------------

   /**
    * Creates a {@link RoutingFramebuffer} with a fixed viewport width override.
    * Used for checkerboard/direct-packed passes whose viewport width differs from
    * the framebuffer texture width.
    *
    * @param viewportWidth supplier for the overridden viewport width (e.g. directPackedViewportWidth)
    * @param attachments   zero or more lazy attachment suppliers, added in order
    */
   @SafeVarargs
   public static RoutingFramebuffer create(
      IntSupplier viewportWidth,
      Supplier<TextureObject>... attachments
   ) {
      RoutingFramebuffer fb = new RoutingFramebuffer(viewportWidth::getAsInt);
      for (Supplier<TextureObject> attachment : attachments) {
         fb.addAttachment(attachment);
      }
      return fb;
   }

   /**
    * Creates a plain {@link RoutingFramebuffer} whose viewport width is derived
    * from the first attachment at bind time (no fixed-width override).
    *
    * @param attachments zero or more lazy attachment suppliers, added in order
    */
   @SafeVarargs
   public static RoutingFramebuffer create(Supplier<TextureObject>... attachments) {
      RoutingFramebuffer fb = new RoutingFramebuffer();
      for (Supplier<TextureObject> attachment : attachments) {
         fb.addAttachment(attachment);
      }
      return fb;
   }
}
