package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.config.PhotonicsConfig;
import at.redi2go.photonic.client.rendering.world.PBlock;
import net.caffeinemc.mods.sodium.client.render.chunk.compile.pipeline.BlockOcclusionCache;
import net.minecraft.world.BlockView;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Direction;
import net.minecraft.block.BlockState;
import net.minecraft.util.math.BlockPos.Mutable;
import org.spongepowered.asm.mixin.Final;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(value = BlockOcclusionCache.class, remap = false)
public class BlockOcclusionCacheMixin {
   @Shadow
   @Final
   private Mutable cachedPositionObject;

   @Inject(method = "shouldDrawSide", at = @At("HEAD"), cancellable = true)
   public void shouldDrawSide(BlockState selfBlockState, BlockView view, BlockPos selfPos, Direction facing, CallbackInfoReturnable<Boolean> cir) {
      Mutable neighborPos = this.cachedPositionObject;
      neighborPos.set(selfPos, facing);
      BlockState neighborBlockState = view.getBlockState(neighborPos);
      if (PhotonicsConfig.isVoxelized(neighborBlockState.getBlock())) {
         PBlock block = Raytracer.INSTANCE != null ? Raytracer.INSTANCE.getBlockRegistry().getBlock(neighborBlockState) : null;
         if (block != null && !block.canOcclude) {
            cir.setReturnValue(true);
            cir.cancel();
         }
      }
   }
}
