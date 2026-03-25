package at.redi2go.photonic.client.mixin;

import it.unimi.dsi.fastutil.ints.Int2ObjectMap;
import net.irisshaders.iris.shaderpack.properties.PackRenderTargetDirectives;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

@Mixin(value = PackRenderTargetDirectives.class, remap = false)
public interface PackRenderTargetDirectivesAccessor {
   @Accessor("renderTargetSettings")
   Int2ObjectMap<PackRenderTargetDirectives.RenderTargetSettings> photonic$getRenderTargetSettings();
}
