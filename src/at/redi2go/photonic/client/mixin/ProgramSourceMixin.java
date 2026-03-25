package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.IrisRenderTargetAliases;
import java.util.Set;
import net.irisshaders.iris.shaderpack.programs.ProgramSource;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;

@Mixin(value = ProgramSource.class, remap = false)
public class ProgramSourceMixin {
   @Redirect(
      method = "<init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Lnet/irisshaders/iris/shaderpack/programs/ProgramSet;Lnet/irisshaders/iris/shaderpack/properties/ShaderProperties;Lnet/irisshaders/iris/gl/blending/BlendModeOverride;)V",
      at = @At(
         value = "FIELD",
         target = "Lnet/irisshaders/iris/shaderpack/properties/PackRenderTargetDirectives;BASELINE_SUPPORTED_RENDER_TARGETS:Ljava/util/Set;"
      )
   )
   private static Set<Integer> photonic$extendSupportedRenderTargets() {
      return IrisRenderTargetAliases.supportedRenderTargets();
   }
}
