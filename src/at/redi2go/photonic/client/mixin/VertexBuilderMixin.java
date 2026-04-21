package at.redi2go.photonic.client.mixin;

import at.redi2go.photonics.core.rendering.world.bakery.VertexBuilder;
import at.redi2go.photonics.core.rendering.world.block.VoxelColor;
import net.minecraft.client.render.VertexConsumer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;

@Mixin(value = VertexBuilder.class, remap = false)
public interface VertexBuilderMixin extends VertexConsumer {
   @Shadow(remap = false)
   VertexBuilder addVertex(float x, float y, float z);

   @Override
   default VertexConsumer vertex(float x, float y, float z) {
      return (VertexConsumer)this.addVertex(x, y, z);
   }

   @Override
   default VertexConsumer color(int red, int green, int blue, int alpha) {
      return this.color(VoxelColor.from(red, green, blue, alpha));
   }

   @Shadow(remap = false)
   VertexBuilder setTint(int argb);

   @Override
   default VertexConsumer color(int argb) {
      return (VertexConsumer)this.setTint(argb);
   }

   @Override
   default VertexConsumer texture(float u, float v) {
      return (VertexConsumer)this.setUv(u, v);
   }

   @Shadow(remap = false)
   VertexBuilder setUv(float u, float v);

   @Override
   default VertexConsumer overlay(int u, int v) {
      return this;
   }

   @Override
   default VertexConsumer light(int u, int v) {
      return this;
   }

   @Override
   default VertexConsumer normal(float x, float y, float z) {
      return this;
   }
}
