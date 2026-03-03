package at.redi2go.photonic.client.mixin;

import com.llamalad7.mixinextras.sugar.Local;
import net.irisshaders.iris.pipeline.programs.SodiumShader;
import net.irisshaders.iris.pipeline.programs.SodiumPrograms.Pass;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.ModifyVariable;

@Mixin(value = SodiumShader.class, remap = false)
public class SodiumShaderMixin {
   @ModifyVariable(method = "<init>", at = @At("STORE"), ordinal = 1)
   public boolean isShadowPassAssignment(boolean value, @Local(argsOnly = true) Pass pass) {
      return value || pass == Pass.valueOf("SHADOW_VOXELS");
   }
}
