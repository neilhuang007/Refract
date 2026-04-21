package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.CompositeRendererExt;
import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.rendering.opengl.rendering.PhotonicsShader;
import com.llamalad7.mixinextras.injector.wrapoperation.Operation;
import com.llamalad7.mixinextras.injector.wrapoperation.WrapOperation;
import com.llamalad7.mixinextras.sugar.Local;
import java.util.List;
import net.irisshaders.iris.gl.program.ComputeProgram;
import net.irisshaders.iris.gl.program.Program;
import net.irisshaders.iris.pipeline.CompositeRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;

@Mixin(value = CompositeRenderer.class, remap = false)
public class CompositeRendererMixin implements CompositeRendererExt {
   @Unique
   private List<PhotonicsShader> photonicsShaders = null;

   @WrapOperation(method = "renderAll", at = @At(value = "INVOKE", target = "Lnet/irisshaders/iris/gl/program/ComputeProgram;use()V"))
   public void useCompute(ComputeProgram instance, Operation<Void> original) {
      Raytracer.bindBuffers(instance.getProgramId());
      original.call(instance);
   }

   @WrapOperation(method = "renderAll", at = @At(value = "INVOKE", target = "Lnet/irisshaders/iris/gl/program/Program;use()V"))
   public void use(Program instance, Operation<Void> original, @Local(ordinal = 0) int photonicsId) {
      if (Raytracer.INSTANCE != null) {
         if (this.photonicsShaders != null && photonicsId >= 0 && photonicsId < this.photonicsShaders.size()) {
            Raytracer.INSTANCE.getMainRenderer().setCurrentPhotonicsFragment(this.photonicsShaders.get(photonicsId).getFragmentName());
         } else {
            Raytracer.INSTANCE.getMainRenderer().setCurrentPhotonicsFragment("");
         }
      }

      Raytracer.bindBuffers(instance.getProgramId());
      original.call(instance);
   }

   @Override
   public List<PhotonicsShader> photonic$getPhotonicsShaders() {
      return this.photonicsShaders;
   }

   @Override
   public void photonic$setPhotonicsShaders(List<PhotonicsShader> photonicsShaders) {
      this.photonicsShaders = photonicsShaders;
   }
}
