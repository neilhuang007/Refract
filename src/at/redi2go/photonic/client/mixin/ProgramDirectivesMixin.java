package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.IrisRenderTargetAliases;
import java.util.List;
import java.util.Map;
import net.irisshaders.iris.gl.blending.BufferBlendInformation;
import net.irisshaders.iris.shaderpack.properties.ProgramDirectives;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;
import com.google.common.collect.ImmutableMap;
import com.google.common.collect.ImmutableSet;
import org.spongepowered.asm.mixin.Mixin;

@Mixin(value = ProgramDirectives.class, remap = false)
public class ProgramDirectivesMixin {
   @Inject(method = "getDrawBuffers", at = @At("RETURN"), cancellable = true)
   private void photonic$aliasUnsupportedRenderTargets(CallbackInfoReturnable<int[]> cir) {
      cir.setReturnValue(IrisRenderTargetAliases.alias(cir.getReturnValue()));
   }

   @Inject(method = "getExplicitFlips", at = @At("RETURN"), cancellable = true)
   private void photonic$aliasExplicitFlips(CallbackInfoReturnable<ImmutableMap<Integer, Boolean>> cir) {
      Map<Integer, Boolean> aliased = IrisRenderTargetAliases.alias(cir.getReturnValue());
      if (aliased != cir.getReturnValue()) {
         cir.setReturnValue(ImmutableMap.copyOf(aliased));
      }
   }

   @Inject(method = "getMipmappedBuffers", at = @At("RETURN"), cancellable = true)
   private void photonic$aliasMipmappedBuffers(CallbackInfoReturnable<ImmutableSet<Integer>> cir) {
      cir.setReturnValue(IrisRenderTargetAliases.alias(cir.getReturnValue()));
   }

   @Inject(method = "getBufferBlendOverrides", at = @At("RETURN"), cancellable = true)
   private void photonic$aliasBufferBlendOverrides(CallbackInfoReturnable<List<BufferBlendInformation>> cir) {
      cir.setReturnValue(IrisRenderTargetAliases.aliasBufferBlendOverrides(cir.getReturnValue()));
   }
}
