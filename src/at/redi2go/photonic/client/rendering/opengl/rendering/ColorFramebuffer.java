package at.redi2go.photonic.client.rendering.opengl.rendering;

import at.redi2go.photonic.client.rendering.opengl.GL;
import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.util.BufferUtils;
import com.mojang.blaze3d.platform.GlStateManager;
import java.nio.IntBuffer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.function.Supplier;
import net.irisshaders.iris.gl.framebuffer.GlFramebuffer;
import net.irisshaders.iris.uniforms.SystemTimeUniforms;
import net.minecraft.client.MinecraftClient;
import org.joml.Vector2f;
import org.joml.Vector4f;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL20;
import org.lwjgl.opengl.GL30;
import org.lwjgl.opengl.GL42;

public class ColorFramebuffer extends GlFramebuffer {
   private final Supplier<Vector2f> resolutionSupplier;
   private final float scale;
   private int width;
   private int height;
   private int realWidth;
   private int realHeight;
   private int previousDrawFramebuffer;
   private int[] drawBuffers;
   private int viewportSide = -1;
   private int viewportWidth = -1;
   private int lastFrameUpdate = -1;
   private boolean needsClear = false;
   private final List<String> attachmentNames = new ArrayList<>();
   private Map<String, ColorFramebuffer.FramebufferAttachment> readAttachment = new HashMap<>();
   private Map<String, ColorFramebuffer.FramebufferAttachment> writeAttachment = new HashMap<>();

   public ColorFramebuffer(float scale) {
      this(() -> new Vector2f(MinecraftClient.getInstance().getWindow().getFramebufferWidth(), MinecraftClient.getInstance().getWindow().getFramebufferHeight()), scale);
   }

   public ColorFramebuffer(Supplier<Vector2f> resolutionSupplier, float scale) {
      this.resolutionSupplier = resolutionSupplier;
      this.scale = scale;
   }

   public void createAttachment(String name, String internalFormat, boolean interpolate) {
      this.attachmentNames.add(name);
      this.readAttachment.put(name, new ColorFramebuffer.FramebufferAttachment(this, this.width, this.height, internalFormat, interpolate));
      this.writeAttachment.put(name, new ColorFramebuffer.FramebufferAttachment(this, this.width, this.height, internalFormat, interpolate));
      this.swap();
   }

   public void bind() {
      this.updatePerFrame();
      this.previousDrawFramebuffer = GL11.glGetInteger(GL30.GL_DRAW_FRAMEBUFFER_BINDING);
      GL30.glBindFramebuffer(36160, this.getId());
      int viewportWidth = this.resolveViewportWidth();
      if (this.viewportSide != -1) {
         int x = this.viewportSide * viewportWidth;
         GL11.glViewport(x, 0, viewportWidth, this.height);
      } else {
         GL11.glViewport(0, 0, viewportWidth, this.height);
      }

      int i = 0;

      for (String name : this.attachmentNames) {
         int texture = name == null ? 0 : this.writeAttachment.get(name).getTextureId();
         if (!Objects.equals(name, "depth")) {
            GL30.glFramebufferTexture2D(36160, 36064 + i, 3553, texture, 0);
            i++;
         } else {
            GL30.glFramebufferTexture2D(36160, 36096, 3553, texture, 0);
         }
      }

      int[] resolvedDrawBuffers = resolveDrawBuffers(this.drawBuffers, i);
      IntBuffer buffer = BufferUtils.createIntBuffer(resolvedDrawBuffers.length);
      for (int drawBuffer : resolvedDrawBuffers) {
         buffer.put(drawBuffer);
      }

      int drawBufferCount = resolvedDrawBuffers.length;
      buffer.position(0);
      buffer.limit(drawBufferCount);
      GL20.glDrawBuffers(buffer);
      int status = GL30.glCheckFramebufferStatus(36160);
      if (status != 36053) {
         throw new RuntimeException("Framebuffer in invalid state: " + status);
      }

      if (this.needsClear) {
         this.needsClear = false;
         GL11.glClearColor(0, 0, 0, 0);
         GL11.glClear(16640);
      }
   }

   public void unbind() {
      GL30.glBindFramebuffer(36160, this.previousDrawFramebuffer);
      int width = MinecraftClient.getInstance().getWindow().getFramebufferWidth();
      int height = MinecraftClient.getInstance().getWindow().getFramebufferHeight();
      GL11.glViewport(0, 0, width, height);
      this.previousDrawFramebuffer = 0;
   }

   public void swap() {
      Map<String, ColorFramebuffer.FramebufferAttachment> tmp = this.readAttachment;
      this.readAttachment = this.writeAttachment;
      this.writeAttachment = tmp;
   }

   public void setDrawBuffers(int[] drawBuffers) {
      this.drawBuffers = drawBuffers == null ? null : drawBuffers.clone();
   }

   public void clear(Vector4f clearColor) {
      this.bind();
      GL11.glClearColor(clearColor.x, clearColor.y, clearColor.z, clearColor.w);
      GL11.glClear(16640);
      this.unbind();
   }

   public ColorFramebuffer.FramebufferAttachment getReadAttachment(String name) {
      ColorFramebuffer.FramebufferAttachment attachment = this.readAttachment.get(name);
      if (attachment == null) {
         throw new NullPointerException("Cannot find attachment " + name);
      } else {
         return attachment;
      }
   }

   public ColorFramebuffer.FramebufferAttachment getWriteAttachment(String name) {
      ColorFramebuffer.FramebufferAttachment attachment = this.writeAttachment.get(name);
      if (attachment == null) {
         throw new NullPointerException("Cannot find attachment " + name);
      } else {
         return attachment;
      }
   }

   public void updatePerFrame() {
      int counter = SystemTimeUniforms.COUNTER.getAsInt();
      if (counter != this.lastFrameUpdate) {
         this.lastFrameUpdate = counter;
         Vector2f resolution = this.resolutionSupplier.get();
         int rawW = (int) resolution.x;
         int rawH = (int) resolution.y;
         if (this.realWidth != rawW || this.realHeight != rawH) {
            this.realWidth = rawW;
            this.realHeight = rawH;
            this.width = (int) Math.max(rawW * this.scale, 1.0F);
            this.height = (int) Math.max(rawH * this.scale, 1.0F);
            this.readAttachment.values().forEach(attachment -> attachment.init(this.width, this.height));
            this.writeAttachment.values().forEach(attachment -> attachment.init(this.width, this.height));
            this.needsClear = true;
         }
      }
   }

   public int getWidth() {
      return this.width;
   }

   public int getHeight() {
      return this.height;
   }

   static int[] resolveDrawBuffers(int[] drawBuffers, int colorAttachmentCount) {
      if (drawBuffers == null) {
         int[] resolved = new int[colorAttachmentCount];
         for (int drawBuffer = 0; drawBuffer < colorAttachmentCount; drawBuffer++) {
            resolved[drawBuffer] = GL30.GL_COLOR_ATTACHMENT0 + drawBuffer;
         }
         return resolved;
      }

      for (int drawBuffer : drawBuffers) {
         if (drawBuffer < -1 || drawBuffer >= colorAttachmentCount) {
            throw new IllegalArgumentException(
               "Draw buffer " + drawBuffer + " is outside the color attachment range -1.." + Math.max(colorAttachmentCount - 1, 0)
            );
         }
      }

      int[] resolved = new int[drawBuffers.length];
      for (int i = 0; i < drawBuffers.length; i++) {
         resolved[i] = drawBuffers[i] < 0 ? GL11.GL_NONE : GL30.GL_COLOR_ATTACHMENT0 + drawBuffers[i];
      }
      return resolved;
   }

   public int getViewportSide() {
      return this.viewportSide;
   }

   public void setViewportSide(int viewportSide) {
      this.viewportSide = viewportSide;
   }

   public void setViewportWidth(int viewportWidth) {
      this.viewportWidth = viewportWidth;
   }

   private int resolveViewportWidth() {
      if (this.viewportSide == -1) {
         return this.width;
      }
      if (this.viewportWidth > 0) {
         return this.viewportWidth;
      }
      return Math.max(1, this.width / 2);
   }

   protected void destroyInternal() {
      super.destroyInternal();

      for (ColorFramebuffer.FramebufferAttachment attachment : this.readAttachment.values()) {
         attachment.free();
      }

      for (ColorFramebuffer.FramebufferAttachment attachment : this.writeAttachment.values()) {
         attachment.free();
      }
   }

   public void addDepthAttachment(int texture) {
      throw new UnsupportedOperationException();
   }

   public void addColorAttachment(int index, int texture) {
      throw new UnsupportedOperationException();
   }

   public void noDrawBuffers() {
      throw new UnsupportedOperationException();
   }

   public void drawBuffers(int[] buffers) {
      throw new UnsupportedOperationException();
   }

   public void readBuffer(int buffer) {
      throw new UnsupportedOperationException();
   }

   public int getColorAttachment(int index) {
      throw new UnsupportedOperationException();
   }

   public boolean hasDepthAttachment() {
      throw new UnsupportedOperationException();
   }

   public void bindAsReadBuffer() {
      throw new UnsupportedOperationException();
   }

   public void bindAsDrawBuffer() {
      throw new UnsupportedOperationException();
   }

   public static class FramebufferAttachment extends TextureObject {
      private final ColorFramebuffer framebuffer;
      private final String internalFormat;
      private final boolean interpolate;

      private FramebufferAttachment(ColorFramebuffer framebuffer, int width, int height, String internalFormat, boolean interpolate) {
         super(new int[]{width, height}, GL.pGetInternalFormat(internalFormat), 3553, GL11.glGenTextures(), false);
         this.framebuffer = framebuffer;
         this.internalFormat = internalFormat;
         this.interpolate = interpolate;
         this.init(width, height);
      }

      private void init(int width, int height) {
         if (width > 0 && height > 0) {
            this.dimensions[0] = width;
            this.dimensions[1] = height;
            GL11.glDeleteTextures(this.textureId);
            this.textureId = GL11.glGenTextures();
            GL11.glBindTexture(3553, this.getTextureId());
            GL42.glTexStorage2D(3553, 1, GL.pGetInternalFormat(this.internalFormat), width, height);
            int interpolateFlag = this.interpolate ? 9729 : 9728;
            GL11.glTexParameteri(3553, 10241, interpolateFlag);
            GL11.glTexParameteri(3553, 10240, interpolateFlag);
            GL11.glTexParameteri(3553, 10242, 33071);
            GL11.glTexParameteri(3553, 10243, 33071);
         }
      }

      @Override
      public void bind() {
         GlStateManager._activeTexture(33984 + this.getTextureUnit());
         GlStateManager._bindTexture(this.getTextureId());
      }

      @Override
      public void unbind() {
         GlStateManager._bindTexture(0);
      }

      @Override
      public void clear(int value) {
         throw new UnsupportedOperationException();
      }

      @Override
      public void updatePerFrame() {
         this.framebuffer.updatePerFrame();
      }

      @Override
      public void free() {
         GL11.glDeleteTextures(this.textureId);
      }
   }
}



