package at.redi2go.photonic.client.rendering.opengl.objects;

import at.redi2go.photonic.client.rendering.util.BufferUtils;
import java.awt.Color;
import java.awt.image.BufferedImage;
import java.nio.ByteBuffer;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.util.Arrays;
import net.irisshaders.iris.gl.texture.InternalTextureFormat;
import org.lwjgl.opengl.GL11;

public abstract class TextureObject implements Destructable {
   protected final int[] dimensions;
   protected final int format;
   protected final InternalTextureFormat internalTextureFormat;
   protected final int target;
   protected int textureUnit;
   protected int textureId;
   protected boolean image;

   public TextureObject(int[] dimensions, int format, int target, int textureId, boolean image) {
      this.dimensions = dimensions;
      this.format = format;
      this.target = target;
      this.textureId = textureId;
      this.image = image;
      InternalTextureFormat fFinal = null;

      for (InternalTextureFormat f : InternalTextureFormat.values()) {
         if (f.getGlFormat() == format) {
            fFinal = f;
         }
      }

      this.internalTextureFormat = fFinal;
   }

   public abstract void bind();

   public abstract void unbind();

   public abstract void clear(int var1);

   public abstract void updatePerFrame();

   public TextureStats readStats() {
      if (this.getTextureDimensions().length > 2 || this.target != 3553) {
         return TextureStats.EMPTY;
      }

      this.bind();
      IntBuffer buffer = BufferUtils.createIntBuffer(1);
      GL11.glGetTexLevelParameteriv(this.target, 0, 4096, buffer);
      int width = buffer.get(0);
      buffer.clear();
      GL11.glGetTexLevelParameteriv(this.target, 0, 4097, buffer);
      int height = buffer.get(0);
      if (width <= 0 || height <= 0) {
         this.unbind();
         return TextureStats.EMPTY;
      }

      TextureStats stats;
      if (this.isFloatingPointTexture()) {
         FloatBuffer pixels = BufferUtils.createFloatBuffer(width * height * 4);
         GL11.glGetTexImage(this.target, 0, GL11.GL_RGBA, GL11.GL_FLOAT, pixels);
         stats = computeFloatStats(pixels, width, height);
      } else {
         ByteBuffer pixels = BufferUtils.createByteBuffer(width * height * 4);
         GL11.glGetTexImage(this.target, 0, 6408, 5121, pixels);
         stats = computeByteStats(pixels, width, height);
      }

      this.unbind();
      return stats;
   }

   public BufferedImage download() {
      if (this.getTextureDimensions().length > 2 || this.target != 3553) {
         return null;
      } else {
         this.bind();
         IntBuffer buffer = BufferUtils.createIntBuffer(1);
         GL11.glGetTexLevelParameteriv(this.target, 0, 4096, buffer);
         int width = buffer.get(0);
         buffer.clear();
         GL11.glGetTexLevelParameteriv(this.target, 0, 4097, buffer);
         int height = buffer.get(0);
         if (width <= 0 || height <= 0) {
            this.unbind();
            return null;
         }
         if (this.isFloatingPointTexture()) {
            FloatBuffer pixels = BufferUtils.createFloatBuffer(width * height * 4);
            GL11.glGetTexImage(this.target, 0, GL11.GL_RGBA, GL11.GL_FLOAT, pixels);
            BufferedImage image = new BufferedImage(width, height, 2);

            for (int x = 0; x < width; x++) {
               for (int y = 0; y < height; y++) {
                  pixels.position((x + y * width) * 4);
                  int r = hdrChannelToByte(pixels.get());
                  int g = hdrChannelToByte(pixels.get());
                  int b = hdrChannelToByte(pixels.get());
                  int a = alphaChannelToByte(pixels.get());
                  image.setRGB(x, y, new Color(r, g, b, a).getRGB());
               }
            }

            this.unbind();
            return image;
         }

         ByteBuffer pixels = BufferUtils.createByteBuffer(width * height * 4);
         GL11.glGetTexImage(this.target, 0, 6408, 5121, pixels);
         BufferedImage image = new BufferedImage(width, height, 2);

         for (int x = 0; x < width; x++) {
            for (int y = 0; y < height; y++) {
               pixels.position((x + y * width) * 4);
               int r = pixels.get() & 255;
               int g = pixels.get() & 255;
               int b = pixels.get() & 255;
               int a = pixels.get() & 255;
               image.setRGB(x, y, new Color(r, g, b, a).getRGB());
            }
         }

         this.unbind();
         return image;
      }
   }

   private boolean isFloatingPointTexture() {
      return this.internalTextureFormat != null && this.internalTextureFormat.name().contains("F");
   }

   private static TextureStats computeFloatStats(FloatBuffer pixels, int width, int height) {
      double maxLuma = 0.0;
      double lumaSum = 0.0;
      double redSum = 0.0;
      double greenSum = 0.0;
      double blueSum = 0.0;
      double alphaSum = 0.0;
      int zeroAlphaPixels = 0;
      int overbrightPixels = 0;
      int pixelCount = Math.max(1, width * height);

      for (int i = 0; i < pixelCount; i++) {
         int base = i * 4;
         double r = Math.max(pixels.get(base), 0.0f);
         double g = Math.max(pixels.get(base + 1), 0.0f);
         double b = Math.max(pixels.get(base + 2), 0.0f);
         double a = Math.clamp(pixels.get(base + 3), 0.0f, 1.0f);
         double luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
         maxLuma = Math.max(maxLuma, luma);
         lumaSum += luma;
         redSum += r;
         greenSum += g;
         blueSum += b;
         alphaSum += a;
         if (a <= 1.0e-6) {
            zeroAlphaPixels++;
         }
         if (luma > 1.0) {
            overbrightPixels++;
         }
      }

      return new TextureStats(
         maxLuma,
         lumaSum / pixelCount,
         redSum / pixelCount,
         greenSum / pixelCount,
         blueSum / pixelCount,
         alphaSum / pixelCount,
         zeroAlphaPixels / (double)pixelCount,
         overbrightPixels / (double)pixelCount
      );
   }

   private static TextureStats computeByteStats(ByteBuffer pixels, int width, int height) {
      double maxLuma = 0.0;
      double lumaSum = 0.0;
      double redSum = 0.0;
      double greenSum = 0.0;
      double blueSum = 0.0;
      double alphaSum = 0.0;
      int zeroAlphaPixels = 0;
      int pixelCount = Math.max(1, width * height);

      for (int i = 0; i < pixelCount; i++) {
         int base = i * 4;
         double r = (pixels.get(base) & 255) / 255.0;
         double g = (pixels.get(base + 1) & 255) / 255.0;
         double b = (pixels.get(base + 2) & 255) / 255.0;
         double a = (pixels.get(base + 3) & 255) / 255.0;
         double luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
         maxLuma = Math.max(maxLuma, luma);
         lumaSum += luma;
         redSum += r;
         greenSum += g;
         blueSum += b;
         alphaSum += a;
         if (a <= 1.0e-6) {
            zeroAlphaPixels++;
         }
      }

      return new TextureStats(
         maxLuma,
         lumaSum / pixelCount,
         redSum / pixelCount,
         greenSum / pixelCount,
         blueSum / pixelCount,
         alphaSum / pixelCount,
         zeroAlphaPixels / (double)pixelCount,
         0.0
      );
   }

   private static int hdrChannelToByte(float linear) {
      float clamped = Math.max(linear, 0.0f);
      float mapped = clamped / (1.0f + clamped);
      float gamma = (float)Math.pow(mapped, 1.0 / 2.2);
      return (int)Math.round(Math.clamp(gamma, 0.0, 1.0) * 255.0);
   }

   private static int alphaChannelToByte(float alpha) {
      return (int)Math.round(Math.clamp(alpha, 0.0, 1.0) * 255.0);
   }

   public int[] getTextureDimensions() {
      if (this.dimensions.length <= 2) {
         return Arrays.copyOf(this.dimensions, this.dimensions.length);
      }
      return Arrays.copyOfRange(this.dimensions, 0, this.dimensions.length - 2);
   }

   public int getChannelCount() {
      return this.dimensions[this.dimensions.length - 2];
   }

   public int getChannelByteCount() {
      return this.dimensions[this.dimensions.length - 1];
   }

   public int getFormat() {
      return this.format;
   }

   public int getTarget() {
      return this.target;
   }

   public int getTextureUnit() {
      return this.textureUnit;
   }

   public void setTextureUnit(int textureUnit) {
      this.textureUnit = textureUnit;
   }

   public int getTextureId() {
      return this.textureId;
   }

   public InternalTextureFormat getInternalTextureFormat() {
      return this.internalTextureFormat;
   }

   public boolean isImage() {
      return this.image;
   }

   public record TextureStats(
      double maxLuma,
      double meanLuma,
      double meanRed,
      double meanGreen,
      double meanBlue,
      double meanAlpha,
      double zeroAlphaFraction,
      double overbrightFraction
   ) {
      public static final TextureStats EMPTY = new TextureStats(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
   }
}
