package at.redi2go.photonic.client.mixin.mc.world.level;

import at.redi2go.photonics.api.mc.world.level.IBlockAndTintGetter;
import net.minecraft.world.BlockRenderView;
import org.spongepowered.asm.mixin.Mixin;

@Mixin(BlockRenderView.class)
public interface BlockAndTintGetterMixin extends IBlockAndTintGetter {
}
