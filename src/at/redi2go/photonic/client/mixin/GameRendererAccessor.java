package at.redi2go.photonic.client.mixin;

import java.util.Map;
import net.minecraft.client.gl.ShaderProgram;
import net.minecraft.client.render.GameRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

@Mixin(GameRenderer.class)
public interface GameRendererAccessor {
   @Accessor
   Map<String, ShaderProgram> getShaders();
}
