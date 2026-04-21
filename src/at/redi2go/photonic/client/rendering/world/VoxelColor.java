package at.redi2go.photonic.client.rendering.world;

import org.joml.Vector4f;

public final class VoxelColor {
   private VoxelColor() {
   }

   public static int r(int color) {
      return color & 255;
   }

   public static int g(int color) {
      return color >> 8 & 255;
   }

   public static int b(int color) {
      return color >> 16 & 255;
   }

   public static int a(int color) {
      return color >>> 24;
   }

   public static boolean gt(int left, int right) {
      int alphaCompare = Integer.compareUnsigned(a(left), a(right));
      if (alphaCompare != 0) {
         return alphaCompare > 0;
      }

      int leftLuma = r(left) * 2126 + g(left) * 7152 + b(left) * 722;
      int rightLuma = r(right) * 2126 + g(right) * 7152 + b(right) * 722;
      if (leftLuma != rightLuma) {
         return leftLuma > rightLuma;
      }

      return Integer.compareUnsigned(left & 0x00FFFFFF, right & 0x00FFFFFF) > 0;
   }

   public static Vector4f toVector(int color) {
      return new Vector4f(r(color) / 255.0F, g(color) / 255.0F, b(color) / 255.0F, a(color) / 255.0F);
   }

   public static int fromVector(Vector4f color) {
      int r = clampToByte(color.x);
      int g = clampToByte(color.y);
      int b = clampToByte(color.z);
      int a = clampToByte(color.w);
      return r | g << 8 | b << 16 | a << 24;
   }

   private static int clampToByte(float value) {
      return Math.clamp(Math.round(value * 255.0F), 0, 255);
   }
}
