package at.redi2go.photonic.client.rendering.opengl.rendering;

import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.util.BufferUtils;
import java.nio.IntBuffer;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Supplier;
import net.minecraft.client.MinecraftClient;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL20;
import org.lwjgl.opengl.GL30;

public class RoutingFramebuffer extends ColorFramebuffer {
   private final List<Supplier<TextureObject>> attachmentSuppliers = new ArrayList<>();
   private int[] routingDrawBuffers;
   private int previousDrawFramebuffer;

   public RoutingFramebuffer() {
      super(1.0f);
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
      GL30.glBindFramebuffer(GL30.GL_DRAW_FRAMEBUFFER, this.getId());

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

         GL30.glFramebufferTexture2D(
            GL30.GL_DRAW_FRAMEBUFFER,
            GL30.GL_COLOR_ATTACHMENT0 + attachmentIndex,
            attachment.getTarget(),
            attachment.getTextureId(),
            0
         );
         attachmentIndex++;
      }

      GL11.glViewport(0, 0, width, height);

      int[] resolvedDrawBuffers = resolveDrawBuffers(this.routingDrawBuffers, attachmentIndex);
      IntBuffer buffer = BufferUtils.createIntBuffer(resolvedDrawBuffers.length);
      for (int drawBuffer : resolvedDrawBuffers) {
         buffer.put(drawBuffer);
      }

      buffer.position(0);
      buffer.limit(resolvedDrawBuffers.length);
      GL20.glDrawBuffers(buffer);
      int status = GL30.glCheckFramebufferStatus(GL30.GL_DRAW_FRAMEBUFFER);
      if (status != GL30.GL_FRAMEBUFFER_COMPLETE) {
         throw new RuntimeException("Framebuffer in invalid state: " + status);
      }
   }

   @Override
   public void unbind() {
      GL30.glBindFramebuffer(GL30.GL_DRAW_FRAMEBUFFER, this.previousDrawFramebuffer);
      int width = MinecraftClient.getInstance().getWindow().getFramebufferWidth();
      int height = MinecraftClient.getInstance().getWindow().getFramebufferHeight();
      GL11.glViewport(0, 0, width, height);
      this.previousDrawFramebuffer = 0;
   }

   @Override
   public void clear(org.joml.Vector4f clearColor) {
      this.bind();
      GL11.glClearColor(clearColor.x, clearColor.y, clearColor.z, clearColor.w);
      GL11.glClear(GL11.GL_COLOR_BUFFER_BIT | GL11.GL_DEPTH_BUFFER_BIT);
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

   @Override
   public void swap() {
   }
}
