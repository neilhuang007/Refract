package at.redi2go.photonic.client.rendering.opengl.objects;

import com.mojang.blaze3d.platform.GlStateManager;
import java.nio.ByteBuffer;
import java.util.function.Consumer;
import net.minecraft.client.util.Window;
import net.minecraft.client.MinecraftClient;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL12;
import org.lwjgl.opengl.GL13;
import org.lwjgl.opengl.GL14;
import org.lwjgl.opengl.GL30;

public class CubeMapFramebuffer extends TextureObject {
   private final int fbo;
   private final int depthBuffer;
   private final int size;

   public CubeMapFramebuffer(int size) {
      super(new int[]{1, 1, 4, 1}, GL11.GL_RGBA, GL13.GL_TEXTURE_CUBE_MAP, createCubeMapTexture(size), false);
      this.size = size;
      this.fbo = GL30.glGenFramebuffers();
      this.depthBuffer = GL30.glGenRenderbuffers();
   }

   public void render(Consumer<Integer> consumer) {
      GlStateManager._glBindFramebuffer(GL30.GL_FRAMEBUFFER, this.fbo);
      GL11.glDrawBuffer(GL30.GL_COLOR_ATTACHMENT0);
      GL30.glBindRenderbuffer(GL30.GL_RENDERBUFFER, this.depthBuffer);
      GL30.glRenderbufferStorage(GL30.GL_RENDERBUFFER, GL14.GL_DEPTH_COMPONENT24, this.size, this.size);
      GL30.glFramebufferRenderbuffer(GL30.GL_FRAMEBUFFER, GL30.GL_DEPTH_ATTACHMENT, GL30.GL_RENDERBUFFER, this.depthBuffer);
      GlStateManager._viewport(0, 0, this.size, this.size);

      for (int i = 0; i < 6; i++) {
         GL30.glFramebufferTexture2D(GL30.GL_FRAMEBUFFER, GL30.GL_COLOR_ATTACHMENT0, GL13.GL_TEXTURE_CUBE_MAP_POSITIVE_X + i, this.getTextureId(), 0);
         consumer.accept(i);
      }

      Window window = MinecraftClient.getInstance().getWindow();
      GlStateManager._glBindFramebuffer(GL30.GL_FRAMEBUFFER, 0);
      GlStateManager._viewport(0, 0, window.getFramebufferWidth(), window.getFramebufferHeight());
   }

   private static int createCubeMapTexture(int size) {
      int texID = GlStateManager._genTexture();
      GL11.glBindTexture(GL13.GL_TEXTURE_CUBE_MAP, texID);

      for (int i = 0; i < 6; i++) {
         GL11.glTexImage2D(GL13.GL_TEXTURE_CUBE_MAP_POSITIVE_X + i, 0, GL11.GL_RGBA8, size, size, 0, GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, (ByteBuffer)null);
      }

      GL11.glTexParameteri(GL13.GL_TEXTURE_CUBE_MAP, GL11.GL_TEXTURE_MAG_FILTER, GL11.GL_LINEAR);
      GL11.glTexParameteri(GL13.GL_TEXTURE_CUBE_MAP, GL11.GL_TEXTURE_MIN_FILTER, GL11.GL_LINEAR);
      GL11.glTexParameteri(GL13.GL_TEXTURE_CUBE_MAP, GL11.GL_TEXTURE_WRAP_S, GL12.GL_CLAMP_TO_EDGE);
      GL11.glTexParameteri(GL13.GL_TEXTURE_CUBE_MAP, GL11.GL_TEXTURE_WRAP_T, GL12.GL_CLAMP_TO_EDGE);
      GL11.glTexParameteri(GL13.GL_TEXTURE_CUBE_MAP, GL12.GL_TEXTURE_WRAP_R, GL12.GL_CLAMP_TO_EDGE);
      GL11.glBindTexture(GL13.GL_TEXTURE_CUBE_MAP, 0);
      return texID;
   }

   @Override
   public void bind() {
      GL13.glActiveTexture(GL13.GL_TEXTURE0 + this.getTextureUnit());
      GL11.glBindTexture(GL13.GL_TEXTURE_CUBE_MAP, this.getTextureId());
   }

   @Override
   public void unbind() {
      GL11.glBindTexture(GL13.GL_TEXTURE_CUBE_MAP, 0);
   }

   @Override
   public void clear(int i) {
      throw new UnsupportedOperationException();
   }

   @Override
   public void updatePerFrame() {
   }

   @Override
   public void free() {
      GL30.glDeleteFramebuffers(this.fbo);
      GL30.glDeleteRenderbuffers(this.depthBuffer);
      GlStateManager._deleteTexture(this.textureId);
   }
}
