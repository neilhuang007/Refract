package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.Raytracer;
import net.irisshaders.iris.gl.framebuffer.GlFramebuffer;
import net.irisshaders.iris.pipeline.CompositeRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;

@Mixin(value = CompositeRenderer.class, remap = false)
public class CompositeRendererPassMixin {
   @Redirect(method = "renderAll", at = @At(value = "INVOKE", target = "Lnet/irisshaders/iris/gl/framebuffer/GlFramebuffer;bind()V"))
   public void bindFramebuffer(GlFramebuffer instance) {
      if (Raytracer.CURRENT_FRAMEBUFFER != null) {
         Raytracer.CURRENT_FRAMEBUFFER.bind();
      } else {
         instance.bind();
      }
   }
}
