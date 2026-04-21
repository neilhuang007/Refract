package at.redi2go.photonic.client.mixin.mc.core;

import at.redi2go.photonics.api.mc.core.IBlockPos;
import net.minecraft.util.math.BlockPos;
import org.spongepowered.asm.mixin.Mixin;

@Mixin(BlockPos.class)
public abstract class BlockPosMixin implements IBlockPos {
    @Override
    public int x() {
        return ((BlockPos) (Object) this).getX();
    }

    @Override
    public int y() {
        return ((BlockPos) (Object) this).getY();
    }

    @Override
    public int z() {
        return ((BlockPos) (Object) this).getZ();
    }
}
