package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.CompositeRendererExt;
import at.redi2go.photonic.client.rendering.opengl.rendering.PhotonicsShader;
import com.llamalad7.mixinextras.sugar.Local;
import java.util.List;
import net.irisshaders.iris.gl.program.Program;
import net.irisshaders.iris.pipeline.CompositeRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;

@Mixin(value = CompositeRenderer.class, remap = false)
public class CompositeRendererMixin implements CompositeRendererExt {
   @Unique
   private List<PhotonicsShader> photonicsShaders = null;

   @Redirect(method = "renderAll", at = @At(value = "INVOKE", target = "Lnet/irisshaders/iris/gl/program/Program;use()V"))
   public void use(Program instance, @Local(ordinal = 0) int i) {
      instance.use();
      if (this.photonicsShaders != null) {
         this.photonicsShaders.get(i).bind(instance.getProgramId());
      }
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
