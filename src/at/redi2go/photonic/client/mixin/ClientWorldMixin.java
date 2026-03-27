package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.Raytracer;
import net.minecraft.block.BlockState;
import net.minecraft.client.world.ClientWorld;
import net.minecraft.util.math.BlockPos;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(ClientWorld.class)
public class ClientWorldMixin {
   @Inject(method = "handleBlockUpdate", at = @At("TAIL"))
   private void photonic$queueRtBlockUpdate(BlockPos pos, BlockState state, int flags, CallbackInfo ci) {
      if (Raytracer.isDisabled()) {
         return;
      }

      Raytracer.INSTANCE.getWorldRegistry().queueBlockUpdate(pos);
   }
}
