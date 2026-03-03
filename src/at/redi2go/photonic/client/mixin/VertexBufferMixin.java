package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.BlockBuilder;
import net.minecraft.client.gl.GlUniform;
import net.minecraft.client.gl.VertexBuffer;
import net.minecraft.client.gl.ShaderProgram;
import org.joml.Matrix4f;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.At.Shift;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(VertexBuffer.class)
public class VertexBufferMixin {
   @Inject(
      method = "_drawWithShader",
      at = @At(
         value = "INVOKE",
         target = "Lnet/minecraft/client/renderer/ShaderInstance;setDefaultUniforms(Lcom/mojang/blaze3d/vertex/VertexFormat$Mode;Lorg/joml/Matrix4f;Lorg/joml/Matrix4f;Lcom/mojang/blaze3d/platform/Window;)V",
         shift = Shift.AFTER
      )
   )
   public void drawInternal(Matrix4f viewMatrix, Matrix4f projectionMatrix, ShaderProgram program, CallbackInfo ci) {
      GlUniform renderIndex = program.getUniform("RenderIndex");
      if (renderIndex != null) {
         renderIndex.set(BlockBuilder.RENDER_INDEX);
      }
   }
}
