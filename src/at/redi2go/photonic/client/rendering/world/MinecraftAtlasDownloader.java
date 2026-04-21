package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.mixin.AbstractTextureAccessor;
import at.redi2go.photonics.api.mc.Id;
import at.redi2go.photonics.core.rendering.world.bakery.texture.AtlasDownloader;
import at.redi2go.photonics.core.rendering.world.bakery.texture.CpuTexture;
import at.redi2go.photonics.core.rendering.world.bakery.texture.Rgba8Texture;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.texture.SpriteAtlasTexture;
import net.minecraft.util.Identifier;
import org.lwjgl.BufferUtils;
import org.lwjgl.opengl.GL11;

import java.nio.ByteBuffer;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public class MinecraftAtlasDownloader implements AtlasDownloader {
   private final Map<Identifier, CpuTexture> textures = new ConcurrentHashMap<>();

   @Override
   public void preloadTexture(Id atlasId) {
      get(atlasId);
   }

   @Override
   public CpuTexture get(Id atlasId) {
      Identifier identifier = (Identifier) (Object) atlasId;
      return textures.computeIfAbsent(identifier, this::loadTexture);
   }

   private CpuTexture loadTexture(Identifier atlasId) {
      SpriteAtlasTexture atlas = MinecraftClient.getInstance().getBakedModelManager().getAtlas(atlasId);
      int textureId = ((AbstractTextureAccessor) atlas).getGlId();
      int previousTexture = GL11.glGetInteger(GL11.GL_TEXTURE_BINDING_2D);
      GL11.glBindTexture(GL11.GL_TEXTURE_2D, textureId);
      int width = GL11.glGetTexLevelParameteri(GL11.GL_TEXTURE_2D, 0, GL11.GL_TEXTURE_WIDTH);
      int height = GL11.glGetTexLevelParameteri(GL11.GL_TEXTURE_2D, 0, GL11.GL_TEXTURE_HEIGHT);
      if (width <= 0 || height <= 0) {
         GL11.glBindTexture(GL11.GL_TEXTURE_2D, previousTexture);
         throw new IllegalStateException("Failed to read atlas texture dimensions for " + atlasId);
      }
      ByteBuffer bytes = BufferUtils.createByteBuffer(width * height * 4);
      GL11.glGetTexImage(GL11.GL_TEXTURE_2D, 0, GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, bytes);
      GL11.glBindTexture(GL11.GL_TEXTURE_2D, previousTexture);
      int[] pixels = new int[width * height];
      for (int i = 0; i < pixels.length; i++) {
         int r = bytes.get(i * 4) & 0xFF;
         int g = bytes.get(i * 4 + 1) & 0xFF;
         int b = bytes.get(i * 4 + 2) & 0xFF;
         int a = bytes.get(i * 4 + 3) & 0xFF;
         pixels[i] = (a << 24) | (b << 16) | (g << 8) | r;
      }
      return new Rgba8Texture(width, height, pixels);
   }

   @Override
   public void close() {
      textures.clear();
   }
}
