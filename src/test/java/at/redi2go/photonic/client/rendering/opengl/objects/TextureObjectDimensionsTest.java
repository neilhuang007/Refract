package at.redi2go.photonic.client.rendering.opengl.objects;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;

import org.junit.jupiter.api.Test;

class TextureObjectDimensionsTest {
   @Test
   void keepsExplicit2dDimensionsForFramebufferAttachments() {
      TextureObject texture = new StubTextureObject(new int[]{320, 180});
      assertArrayEquals(new int[]{320, 180}, texture.getTextureDimensions());
   }

   @Test
   void stripsChannelMetadataFromTexturedDimensions() {
      TextureObject texture = new StubTextureObject(new int[]{320, 180, 4, 1});
      assertArrayEquals(new int[]{320, 180}, texture.getTextureDimensions());
   }

   private static final class StubTextureObject extends TextureObject {
      private StubTextureObject(int[] dimensions) {
         super(dimensions, 0, 3553, 0, false);
      }

      @Override
      public void bind() {
      }

      @Override
      public void unbind() {
      }

      @Override
      public void clear(int value) {
      }

      @Override
      public void updatePerFrame() {
      }

      @Override
      public void free() {
      }
   }
}
