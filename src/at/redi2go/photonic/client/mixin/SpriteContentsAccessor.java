package at.redi2go.photonic.client.mixin;

import net.minecraft.client.texture.SpriteContents;
import net.minecraft.client.texture.NativeImage;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

@Mixin(SpriteContents.class)
public interface SpriteContentsAccessor {
   @Accessor("image")
   NativeImage getImage();
}
