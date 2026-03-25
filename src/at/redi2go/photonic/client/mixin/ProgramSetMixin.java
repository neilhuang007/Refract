package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.IrisRenderTargetAliases;
import java.util.Set;
import net.irisshaders.iris.shaderpack.programs.ProgramSet;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;

@Mixin(value = ProgramSet.class, remap = false)
public class ProgramSetMixin {
   @Redirect(
      method = "<init>",
      at = @At(
         value = "FIELD",
         target = "Lnet/irisshaders/iris/shaderpack/properties/PackRenderTargetDirectives;BASELINE_SUPPORTED_RENDER_TARGETS:Ljava/util/Set;"
      )
   )
   private static Set<Integer> photonic$extendSupportedRenderTargets() {
      return IrisRenderTargetAliases.supportedRenderTargets();
   }
}
