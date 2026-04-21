package at.redi2go.photonic.client.rendering.world;

import org.joml.Vector4f;

public record TextureData(int blockId, int color) {
   public boolean gt(TextureData other) {
      return VoxelColor.gt(this.color, other.color());
   }

   public TextureData withTint(Vector4f tint) {
      return new TextureData(this.blockId, VoxelColor.fromVector(VoxelColor.toVector(this.color).mul(tint)));
   }
}
