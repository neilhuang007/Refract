package at.redi2go.photonic.client.rendering.opengl;

import at.redi2go.photonic.client.Photonic;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL42;
import org.lwjgl.opengl.GL43;
import org.lwjgl.opengl.GLCapabilities;

public class GL {
   private static final int[] versions = new int[]{30, 11, 31};
   private static int loggedGlErrors = 0;

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

   public static void logGlError(String context) {
      int error = GL11.glGetError();
      if (error == GL11.GL_NO_ERROR) {
         return;
      }

      if (loggedGlErrors < 64) {
         Photonic.warn("[GL] {} failed with {}", context, describeGlError(error));
         loggedGlErrors++;
      }
   }

   private static String describeGlError(int error) {
      return switch (error) {
         case GL11.GL_INVALID_ENUM -> "GL_INVALID_ENUM";
         case GL11.GL_INVALID_VALUE -> "GL_INVALID_VALUE";
         case GL11.GL_INVALID_OPERATION -> "GL_INVALID_OPERATION";
         case GL11.GL_OUT_OF_MEMORY -> "GL_OUT_OF_MEMORY";
         default -> "0x" + Integer.toHexString(error);
      };
   }
}
