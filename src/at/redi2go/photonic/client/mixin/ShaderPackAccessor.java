package at.redi2go.photonic.client.mixin;

import java.util.function.Function;
import net.irisshaders.iris.shaderpack.ShaderPack;
import net.irisshaders.iris.shaderpack.include.AbsolutePackPath;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

@Mixin(value = ShaderPack.class, remap = false)
public interface ShaderPackAccessor {
   @Accessor
   Function<AbsolutePackPath, String> getSourceProvider();
}
