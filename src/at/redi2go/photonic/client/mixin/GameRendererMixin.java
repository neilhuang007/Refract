package at.redi2go.photonic.client.mixin;

import java.io.IOException;
import java.util.Map;
import net.minecraft.client.render.VertexFormats;
import net.minecraft.resource.ResourceFactory;
import net.minecraft.client.gl.ShaderProgram;
import net.minecraft.client.render.GameRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(GameRenderer.class)
public class GameRendererMixin {
   @Inject(method = "reloadShaders", at = @At("TAIL"))
   public void loadShaders(ResourceFactory resourceProvider, CallbackInfo ci) {
      try {
         Map<String, ShaderProgram> shaders = ((GameRendererAccessor)this).getShaders();
         ShaderProgram schematic6 = new ShaderProgram(resourceProvider, "schematic6", VertexFormats.POSITION_COLOR_TEXTURE_LIGHT_NORMAL);
         shaders.put("schematic6", schematic6);
         ShaderProgram schematic7 = new ShaderProgram(resourceProvider, "schematic7", VertexFormats.POSITION_COLOR_TEXTURE_LIGHT_NORMAL);
         shaders.put("schematic7", schematic7);
      } catch (IOException var6) {
         throw new RuntimeException(var6);
      }
   }
}
