package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.BlockBuilder;
import at.redi2go.photonic.client.Raytracer;
import java.util.List;
import net.caffeinemc.mods.sodium.fabric.model.FabricModelAccess;
import net.minecraft.block.BlockState;
import net.minecraft.client.render.model.BakedModel;
import net.minecraft.client.render.model.BakedQuad;
import net.minecraft.util.math.Direction;
import net.minecraft.util.math.random.Random;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;

@Mixin(FabricModelAccess.class)
public class FabricModelAccessMixin {
   @Redirect(
      method = "getQuads",
      at = @At(
         value = "INVOKE",
         target = "Lnet/minecraft/client/render/model/BakedModel;getQuads(Lnet/minecraft/block/BlockState;Lnet/minecraft/util/math/Direction;Lnet/minecraft/util/math/random/Random;)Ljava/util/List;"
      )
   )
   public List<BakedQuad> getQuads(BakedModel instance, BlockState state, Direction direction, Random random) {
      return !BlockBuilder.IS_BUILDING_BLOCK_BUFFER
         ? instance.getQuads(state, direction, random)
         : instance.getQuads(state, direction, random).stream().filter(Raytracer::getBakedQuadVoxelized).toList();
   }
}
