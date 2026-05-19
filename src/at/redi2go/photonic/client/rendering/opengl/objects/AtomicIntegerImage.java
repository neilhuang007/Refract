package at.redi2go.photonic.client.rendering.opengl.objects;

import java.nio.ByteBuffer;
import java.nio.IntBuffer;
import java.util.function.Supplier;
import org.joml.Vector3f;
import org.lwjgl.BufferUtils;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL12;
import org.lwjgl.opengl.GL15;
import org.lwjgl.opengl.GL30;
import org.lwjgl.opengl.GL42;
import org.lwjgl.opengl.GL44;

public class AtomicIntegerImage extends TextureObject {
   public static final int FORMAT_SIZED = GL30.GL_R32UI;
   public static final int FORMAT = GL30.GL_RED_INTEGER;
   public static final int TYPE = GL11.GL_UNSIGNED_INT;
   private final Supplier<Vector3f> resolutionSupplier;

   public AtomicIntegerImage(Supplier<Vector3f> resolutionSupplier) {
      super(new int[]{0, 0, 0, 1, 4}, GL30.GL_R32UI, GL12.GL_TEXTURE_3D, GL11.glGenTextures(), true);
      this.resolutionSupplier = resolutionSupplier;
      GL11.glBindTexture(GL12.GL_TEXTURE_3D, this.getTextureId());
      GL11.glTexParameteri(GL12.GL_TEXTURE_3D, GL11.GL_TEXTURE_MIN_FILTER, GL11.GL_NEAREST);
      GL11.glTexParameteri(GL12.GL_TEXTURE_3D, GL11.GL_TEXTURE_MAG_FILTER, GL11.GL_NEAREST);
      GL11.glTexParameteri(GL12.GL_TEXTURE_3D, GL11.GL_TEXTURE_WRAP_S, GL12.GL_CLAMP_TO_EDGE);
      GL11.glTexParameteri(GL12.GL_TEXTURE_3D, GL11.GL_TEXTURE_WRAP_T, GL12.GL_CLAMP_TO_EDGE);
      GL11.glTexParameteri(GL12.GL_TEXTURE_3D, GL12.GL_TEXTURE_WRAP_R, GL12.GL_CLAMP_TO_EDGE);
      GL11.glBindTexture(GL12.GL_TEXTURE_3D, 0);
      this.updatePerFrame();
   }

   @Override
   public void updatePerFrame() {
      Vector3f resolution = this.resolutionSupplier.get();
      if (this.dimensions[0] != resolution.x || this.dimensions[1] != resolution.y || this.dimensions[2] != resolution.z) {
         this.dimensions[0] = (int)Math.max(resolution.x, 1.0F);
         this.dimensions[1] = (int)Math.max(resolution.y, 1.0F);
         this.dimensions[2] = (int)Math.max(resolution.z, 1.0F);
         GL11.glBindTexture(GL12.GL_TEXTURE_3D, this.getTextureId());
         GL12.glTexImage3D(GL12.GL_TEXTURE_3D, 0, GL30.GL_R32UI, this.dimensions[0], this.dimensions[1], this.dimensions[2], 0, GL30.GL_RED_INTEGER, GL11.GL_UNSIGNED_INT, (ByteBuffer)null);
         GL11.glBindTexture(GL12.GL_TEXTURE_3D, 0);
      }
   }

   @Override
   public void bind() {
      GL42.glBindImageTexture(this.getTextureUnit(), this.getTextureId(), 0, true, 0, GL15.GL_READ_WRITE, GL30.GL_R32UI);
   }

   @Override
   public void unbind() {
      GL42.glBindImageTexture(this.getTextureUnit(), 0, 0, true, 0, GL15.GL_READ_WRITE, GL30.GL_R32UI);
   }

   @Override
   public void clear(int value) {
      IntBuffer buffer = BufferUtils.createIntBuffer(1);
      buffer.put(value);
      buffer.flip();
      GL44.glClearTexImage(this.getTextureId(), 0, GL30.GL_RED_INTEGER, GL11.GL_UNSIGNED_INT, buffer);
   }

   @Override
   public void free() {
      GL11.glDeleteTextures(this.getTextureId());
   }
}
