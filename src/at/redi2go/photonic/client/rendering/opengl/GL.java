package at.redi2go.photonic.client.rendering.opengl;

import org.lwjgl.opengl.GL42;
import org.lwjgl.opengl.GL43;
import org.lwjgl.opengl.GLCapabilities;

public class GL {
   private static final int[] versions = new int[]{30, 11, 31};

   public static int pGetInternalFormat(String internalFormat) {
      for (int version : versions) {
         try {
            return pGetConstant(version, internalFormat);
         } catch (RuntimeException var6) {
         }
      }

      throw new RuntimeException(new NoSuchFieldException(internalFormat));
   }

   public static int pGetConstant(int version, String constantName) {
      try {
         return (Integer)Class.forName("org.lwjgl.opengl.GL" + version).getField("GL_" + constantName).get(null);
      } catch (NoSuchFieldException | ClassNotFoundException | IllegalAccessException var3) {
         throw new RuntimeException(var3);
      }
   }

   public static int pGetShaderWriteToCpuBarrierBits() {
      GLCapabilities capabilities = org.lwjgl.opengl.GL.getCapabilities();
      int barriers = GL42.GL_BUFFER_UPDATE_BARRIER_BIT;
      if (capabilities.OpenGL43 || capabilities.GL_ARB_shader_storage_buffer_object) {
         barriers |= GL43.GL_SHADER_STORAGE_BARRIER_BIT;
      }

      return barriers;
   }
}
