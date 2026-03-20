package at.redi2go.photonic.client.rendering.opengl.rendering;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.Test;
import org.lwjgl.opengl.GL30;

class ColorFramebufferDrawBufferMappingTest {
   @Test
   void resolvesSequentialDrawBuffersWhenFramebufferUsesDefaultRouting() {
      assertArrayEquals(
         new int[]{
            GL30.GL_COLOR_ATTACHMENT0,
            GL30.GL_COLOR_ATTACHMENT0 + 1,
            GL30.GL_COLOR_ATTACHMENT0 + 2
         },
         ColorFramebuffer.resolveDrawBuffers(null, 3)
      );
   }

   @Test
   void routesSequentialOutputsToSparseAttachments() {
      assertArrayEquals(
         new int[]{
            GL30.GL_COLOR_ATTACHMENT0 + 2,
            GL30.GL_COLOR_ATTACHMENT0 + 3,
            GL30.GL_COLOR_ATTACHMENT0 + 5,
            GL30.GL_COLOR_ATTACHMENT0 + 6
         },
         ColorFramebuffer.resolveDrawBuffers(new int[]{2, 3, 5, 6}, 8)
      );
   }

   @Test
   void routesSequentialOutputsToExtendedGbuffers() {
      assertArrayEquals(
         new int[]{
            GL30.GL_COLOR_ATTACHMENT0 + 2,
            GL30.GL_COLOR_ATTACHMENT0 + 3,
            GL30.GL_COLOR_ATTACHMENT0 + 4,
            GL30.GL_COLOR_ATTACHMENT0 + 6,
            GL30.GL_COLOR_ATTACHMENT0 + 7,
            GL30.GL_COLOR_ATTACHMENT0 + 8,
            GL30.GL_COLOR_ATTACHMENT0 + 9,
            GL30.GL_COLOR_ATTACHMENT0 + 10,
            GL30.GL_COLOR_ATTACHMENT0 + 11,
            GL30.GL_COLOR_ATTACHMENT0 + 12
         },
         ColorFramebuffer.resolveDrawBuffers(new int[]{2, 3, 4, 6, 7, 8, 9, 10, 11, 12}, 13)
      );
   }

   @Test
   void routesUnboundOutputsToGlNone() {
      assertArrayEquals(
         new int[]{
            GL30.GL_COLOR_ATTACHMENT0,
            GL30.GL_COLOR_ATTACHMENT0 + 1,
            GL30.GL_NONE,
            GL30.GL_NONE,
            GL30.GL_NONE
         },
         ColorFramebuffer.resolveDrawBuffers(new int[]{0, 1, -1, -1, -1}, 2)
      );
   }

   @Test
   void rejectsOutOfRangeDrawBufferIndices() {
      assertThrows(IllegalArgumentException.class, () -> ColorFramebuffer.resolveDrawBuffers(new int[]{7}, 7));
   }
}
