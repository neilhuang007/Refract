package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.Raytracer;
import com.llamalad7.mixinextras.injector.wrapoperation.Operation;
import com.llamalad7.mixinextras.injector.wrapoperation.WrapOperation;
import net.irisshaders.iris.gl.program.ComputeProgram;
import net.irisshaders.iris.gl.program.Program;
import net.irisshaders.iris.pipeline.FinalPassRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;

@Mixin(value = FinalPassRenderer.class, remap = false)
public class FinalRenderPassMixin {
   @WrapOperation(method = "renderFinalPass", at = @At(value = "INVOKE", target = "Lnet/irisshaders/iris/gl/program/ComputeProgram;use()V"))
   public void useCompute(ComputeProgram instance, Operation<Void> original) {
      Raytracer.bindBuffers(instance.getProgramId());
      original.call(instance);
   }

   @WrapOperation(method = "renderFinalPass", at = @At(value = "INVOKE", target = "Lnet/irisshaders/iris/gl/program/Program;use()V"))
   public void use(Program instance, Operation<Void> original) {
      Raytracer.bindBuffers(instance.getProgramId());
      original.call(instance);
   }
}
