package at.redi2go.photonic.client.mixin.mc.core;

import at.redi2go.photonics.api.mc.core.IBlockPos;
import net.minecraft.util.math.BlockPos;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Overwrite;

@Mixin(value = IBlockPos.class, remap = false)
public interface IBlockPosStaticsMixin {
    @Overwrite
    static IBlockPos zero() {
        return (IBlockPos) (Object) BlockPos.ORIGIN;
    }

    @Overwrite
    static IBlockPos of(int x, int y, int z) {
        return (IBlockPos) (Object) new BlockPos(x, y, z);
    }
}
