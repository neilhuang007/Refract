package at.redi2go.photonic.client.rendering.opengl.rendering;

import at.redi2go.photonic.client.rendering.opengl.GL;
import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.util.BufferUtils;
import java.nio.FloatBuffer;
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
import org.lwjgl.opengl.GL12;
import org.lwjgl.opengl.GL13;
import org.lwjgl.opengl.GL20;
import org.lwjgl.opengl.GL30;
import org.lwjgl.opengl.GL42;
import org.lwjgl.opengl.GL44;
import org.lwjgl.opengl.GL45;

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
   /** Ordered list of (names[], internalFormat, interpolate) for each layered group. Used to recreate on resize. */
   private final List<LayeredGroupSpec> layeredGroupSpecs = new ArrayList<>();

   private record LayeredGroupSpec(String[] names, String internalFormat, boolean interpolate) {}

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

   /**
    * Creates a group of {@code names.length} attachments backed by a single RGBA32F texture array on each
    * side of the double buffer.  All 5 layers share one GL texture id per side.  Binding the attachment for
    * any name in the group returns the shared array texture id; the layer index is encoded in
    * {@link FramebufferAttachment#getArrayLayer()}.
    */
   public void createLayeredAttachmentGroup(String[] names, String internalFormat, boolean interpolate) {
      int layerCount = names.length;
      int readSharedId  = GlStateManager._genTexture();
      int writeSharedId = GlStateManager._genTexture();
      initArrayTexture(readSharedId,  internalFormat, interpolate, this.width, this.height, layerCount);
      initArrayTexture(writeSharedId, internalFormat, interpolate, this.width, this.height, layerCount);
      for (int i = 0; i < layerCount; i++) {
         String name = names[i];
         this.attachmentNames.add(name);
         this.readAttachment.put(name,  new ColorFramebuffer.FramebufferAttachment(this, this.width, this.height, internalFormat, interpolate, i, readSharedId));
         this.writeAttachment.put(name, new ColorFramebuffer.FramebufferAttachment(this, this.width, this.height, internalFormat, interpolate, i, writeSharedId));
      }
      // Record spec so we can recreate array textures on resize.
      this.layeredGroupSpecs.add(new LayeredGroupSpec(names.clone(), internalFormat, interpolate));
      this.swap();
   }

   private static void initArrayTexture(int texId, String internalFormat, boolean interpolate, int w, int h, int layers) {
      if (w <= 0 || h <= 0) return;
      GL11.glBindTexture(GL30.GL_TEXTURE_2D_ARRAY, texId);
      GL45.glTextureStorage3D(texId, 1, GL.pGetInternalFormat(internalFormat), w, h, layers);
      GL.logGlError("ColorFramebuffer.initArrayTexture(format=" + internalFormat + ", size=" + w + "x" + h + "x" + layers + ")");
      int filter = interpolate ? GL11.GL_LINEAR : GL11.GL_NEAREST;
      GL11.glTexParameteri(GL30.GL_TEXTURE_2D_ARRAY, GL11.GL_TEXTURE_MIN_FILTER, filter);
      GL11.glTexParameteri(GL30.GL_TEXTURE_2D_ARRAY, GL11.GL_TEXTURE_MAG_FILTER, filter);
      GL11.glTexParameteri(GL30.GL_TEXTURE_2D_ARRAY, GL11.GL_TEXTURE_WRAP_S, GL12.GL_CLAMP_TO_EDGE);
      GL11.glTexParameteri(GL30.GL_TEXTURE_2D_ARRAY, GL11.GL_TEXTURE_WRAP_T, GL12.GL_CLAMP_TO_EDGE);
      GL11.glBindTexture(GL30.GL_TEXTURE_2D_ARRAY, 0);
   }

   public void bind() {
      this.updatePerFrame();
      this.previousDrawFramebuffer = GL11.glGetInteger(GL30.GL_DRAW_FRAMEBUFFER_BINDING);
      GlStateManager._glBindFramebuffer(GL30.GL_FRAMEBUFFER, this.getId());
      int viewportWidth = this.resolveViewportWidth();
      if (this.viewportSide != -1) {
         int x = this.viewportSide * viewportWidth;
         GlStateManager._viewport(x, 0, viewportWidth, this.height);
      } else {
         GlStateManager._viewport(0, 0, viewportWidth, this.height);
      }

      int i = 0;

      for (String name : this.attachmentNames) {
         ColorFramebuffer.FramebufferAttachment att = name == null ? null : this.writeAttachment.get(name);
         int texture = att == null ? 0 : att.getTextureId();
         if (!Objects.equals(name, "depth")) {
            if (att != null && att.isLayered()) {
               GL30.glFramebufferTextureLayer(GL30.GL_FRAMEBUFFER, GL30.GL_COLOR_ATTACHMENT0 + i, texture, 0, att.getArrayLayer());
               GL.logGlError("ColorFramebuffer.glFramebufferTextureLayer(color name=" + name + ", layer=" + att.getArrayLayer() + ", index=" + i + ")");
            } else {
               GL30.glFramebufferTexture2D(GL30.GL_FRAMEBUFFER, GL30.GL_COLOR_ATTACHMENT0 + i, GL11.GL_TEXTURE_2D, texture, 0);
               GL.logGlError("ColorFramebuffer.glFramebufferTexture2D(color name=" + name + ", index=" + i + ")");
            }
            i++;
         } else {
            GL30.glFramebufferTexture2D(GL30.GL_FRAMEBUFFER, GL30.GL_DEPTH_ATTACHMENT, GL11.GL_TEXTURE_2D, texture, 0);
            GL.logGlError("ColorFramebuffer.glFramebufferTexture2D(depth name=" + name + ")");
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
      GL.logGlError("ColorFramebuffer.glDrawBuffers(count=" + drawBufferCount + ")");
      int status = GL30.glCheckFramebufferStatus(GL30.GL_FRAMEBUFFER);
      if (status != GL30.GL_FRAMEBUFFER_COMPLETE) {
         throw new RuntimeException("Framebuffer in invalid state: " + status);
      }

      if (this.needsClear) {
         this.needsClear = false;
         GlStateManager._clearColor(0f, 0f, 0f, 0f);
         GlStateManager._clear(GL11.GL_COLOR_BUFFER_BIT | GL11.GL_DEPTH_BUFFER_BIT, false);
      }
   }

   public void unbind() {
      GlStateManager._glBindFramebuffer(GL30.GL_FRAMEBUFFER, this.previousDrawFramebuffer);
      int width = MinecraftClient.getInstance().getWindow().getFramebufferWidth();
      int height = MinecraftClient.getInstance().getWindow().getFramebufferHeight();
      GlStateManager._viewport(0, 0, width, height);
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
      this.updatePerFrame();

      for (LayeredGroupSpec spec : this.layeredGroupSpecs) {
         FramebufferAttachment leader = this.writeAttachment.get(spec.names()[0]);
         if (leader != null) {
            leader.clearArray(clearColor);
         }
      }
      for (String name : this.attachmentNames) {
         if (Objects.equals(name, "depth")) {
            continue;
         }
         FramebufferAttachment att = this.writeAttachment.get(name);
         if (att != null && !att.isLayered()) {
            att.clear(clearColor);
         }
      }

      this.needsClear = false;
   }

   public void clearBothSides(Vector4f clearColor) {
      this.clear(clearColor);
      this.swap();
      this.clear(clearColor);
      this.swap();
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
            // Recreate layered group array textures before per-attachment init so that
            // group-leader attachments have a fresh shared texture id ready.
            for (LayeredGroupSpec spec : this.layeredGroupSpecs) {
               reinitLayeredGroup(spec, this.readAttachment, this.width, this.height);
               reinitLayeredGroup(spec, this.writeAttachment, this.width, this.height);
            }
            this.readAttachment.values().forEach(attachment -> attachment.init(this.width, this.height));
            this.writeAttachment.values().forEach(attachment -> attachment.init(this.width, this.height));
            this.needsClear = true;
         }
      }
   }

   private static void reinitLayeredGroup(LayeredGroupSpec spec, Map<String, FramebufferAttachment> side, int w, int h) {
      int layerCount = spec.names().length;
      // Allocate a new shared texture id and propagate it to all layers in this side.
      int newSharedId = GlStateManager._genTexture();
      initArrayTexture(newSharedId, spec.internalFormat(), spec.interpolate(), w, h, layerCount);
      for (String name : spec.names()) {
         FramebufferAttachment att = side.get(name);
         if (att != null) {
            att.setSharedArrayTextureId(newSharedId);
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

      for (LayeredGroupSpec spec : this.layeredGroupSpecs) {
         FramebufferAttachment readLeader = this.readAttachment.get(spec.names()[0]);
         FramebufferAttachment writeLeader = this.writeAttachment.get(spec.names()[0]);
         if (readLeader != null) {
            readLeader.free();
         }
         if (writeLeader != null) {
            writeLeader.free();
         }
      }
      for (FramebufferAttachment att : this.readAttachment.values()) {
         if (!att.isLayered()) {
            att.free();
         }
      }
      for (FramebufferAttachment att : this.writeAttachment.values()) {
         if (!att.isLayered()) {
            att.free();
         }
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
      /** -1 for non-layered; >= 0 for the layer index within the shared array texture. */
      private final int arrayLayer;
      /** The shared array texture id for layered attachments (= textureId for layer 0). */
      private int sharedArrayTextureId;

      private FramebufferAttachment(ColorFramebuffer framebuffer, int width, int height, String internalFormat, boolean interpolate) {
         super(new int[]{width, height}, GL.pGetInternalFormat(internalFormat), GL11.GL_TEXTURE_2D, GlStateManager._genTexture(), false);
         this.framebuffer = framebuffer;
         this.internalFormat = internalFormat;
         this.interpolate = interpolate;
         this.arrayLayer = -1;
         this.sharedArrayTextureId = 0;
         this.init(width, height);
      }

      /** Layered constructor: shares a pre-allocated array texture. Does NOT allocate a new texture. */
      private FramebufferAttachment(ColorFramebuffer framebuffer, int width, int height, String internalFormat, boolean interpolate, int arrayLayer, int sharedArrayTextureId) {
         super(new int[]{width, height}, GL.pGetInternalFormat(internalFormat), GL30.GL_TEXTURE_2D_ARRAY, sharedArrayTextureId, false);
         this.framebuffer = framebuffer;
         this.internalFormat = internalFormat;
         this.interpolate = interpolate;
         this.arrayLayer = arrayLayer;
         this.sharedArrayTextureId = sharedArrayTextureId;
         // No init: the caller already called initArrayTexture for the shared texture.
      }

      public boolean isLayered() {
         return this.arrayLayer >= 0;
      }

      public int getArrayLayer() {
         return this.arrayLayer;
      }

      /** For layered attachments, update the shared texture id (called on resize). */
      private void setSharedArrayTextureId(int newId) {
         // Delete old shared id only from the layer-0 attachment (layer leader).
         if (this.arrayLayer == 0 && this.sharedArrayTextureId != 0) {
            GL11.glDeleteTextures(this.sharedArrayTextureId);
         }
         this.sharedArrayTextureId = newId;
         this.textureId = newId;
      }

      @Override
      public int getTextureId() {
         return this.isLayered() ? this.sharedArrayTextureId : this.textureId;
      }

      private void init(int width, int height) {
         if (this.isLayered()) {
            // Layered attachments are managed via setSharedArrayTextureId; nothing to do here.
            this.dimensions[0] = width;
            this.dimensions[1] = height;
            return;
         }
         if (width > 0 && height > 0) {
            this.dimensions[0] = width;
            this.dimensions[1] = height;
            GlStateManager._deleteTexture(this.textureId);
            this.textureId = GlStateManager._genTexture();
            GlStateManager._bindTexture(this.getTextureId());
            GL42.glTexStorage2D(GL11.GL_TEXTURE_2D, 1, GL.pGetInternalFormat(this.internalFormat), width, height);
            GL.logGlError("ColorFramebuffer.FramebufferAttachment.glTexStorage2D(format=" + this.internalFormat + ", size=" + width + "x" + height + ")");
            int interpolateFlag = this.interpolate ? GL11.GL_LINEAR : GL11.GL_NEAREST;
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MIN_FILTER, interpolateFlag);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MAG_FILTER, interpolateFlag);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_S, GL12.GL_CLAMP_TO_EDGE);
            GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_T, GL12.GL_CLAMP_TO_EDGE);
         }
      }

      @Override
      public void bind() {
         GlStateManager._activeTexture(GL13.GL_TEXTURE0 + this.getTextureUnit());
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

      /** Clear a non-layered attachment. */
      private void clear(Vector4f clearColor) {
         FloatBuffer clearValue = this.buildClearValue(clearColor);
         GL44.glClearTexImage(this.getTextureId(), 0, this.getClearFormat(), GL11.GL_FLOAT, clearValue);
         GL.logGlError("ColorFramebuffer.FramebufferAttachment.glClearTexImage(format=" + this.internalFormat + ")");
      }

      /** Clear the entire array texture backing this layered group (all layers at once). */
      private void clearArray(Vector4f clearColor) {
         FloatBuffer clearValue = this.buildClearValue(clearColor);
         GL44.glClearTexImage(this.sharedArrayTextureId, 0, this.getClearFormat(), GL11.GL_FLOAT, clearValue);
         GL.logGlError("ColorFramebuffer.FramebufferAttachment.glClearTexImage(array, format=" + this.internalFormat + ")");
      }

      private int getClearFormat() {
         return switch (this.internalFormat) {
            case "RG32F" -> GL30.GL_RG;
            default -> GL11.GL_RGBA;
         };
      }

      private FloatBuffer buildClearValue(Vector4f clearColor) {
         if (this.getClearFormat() == GL30.GL_RG) {
            FloatBuffer clearValue = BufferUtils.createFloatBuffer(2);
            clearValue.put(clearColor.x).put(clearColor.y);
            clearValue.flip();
            return clearValue;
         }

         FloatBuffer clearValue = BufferUtils.createFloatBuffer(4);
         clearValue.put(clearColor.x).put(clearColor.y).put(clearColor.z).put(clearColor.w);
         clearValue.flip();
         return clearValue;
      }

      @Override
      public void updatePerFrame() {
         this.framebuffer.updatePerFrame();
      }

      @Override
      public void free() {
         GlStateManager._deleteTexture(this.textureId);
      }
   }
}



