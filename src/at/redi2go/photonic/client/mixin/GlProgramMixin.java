package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.GlProgramExt;
import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.rendering.opengl.rendering.PhotonicsShader;
import net.caffeinemc.mods.sodium.client.gl.shader.GlProgram;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(GlProgram.class)
public class GlProgramMixin implements GlProgramExt {
   @Unique
   private PhotonicsShader photonicsShader = null;

   @Inject(method = "bind", at = @At("TAIL"), remap = false)
   public void applyTail(CallbackInfo ci) {
      int programId = ((GlProgram)(Object)this).handle();
      Raytracer.bindBuffers(programId);
      if (this.photonicsShader != null) {
         this.photonicsShader.bindFramebuffer();
      }
   }

   @Override
   public PhotonicsShader photonic$getPhotonicsShader() {
      return this.photonicsShader;
   }

   @Override
   public void photonic$setPhotonicsShader(PhotonicsShader photonicsShader) {
      this.photonicsShader = photonicsShader;
   }
}
