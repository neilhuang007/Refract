package at.redi2go.photonic.client.mixin.mc.world.level;

import at.redi2go.photonics.api.mc.core.IBlockPos;
import at.redi2go.photonics.api.mc.world.level.IBlockGetter;
import at.redi2go.photonics.api.mc.world.level.IBlockState;
import at.redi2go.photonics.api.mc.world.level.block.IBlockEntity;
import net.minecraft.block.entity.BlockEntity;
import net.minecraft.util.math.BlockPos;
import net.minecraft.world.BlockView;
import org.jetbrains.annotations.Nullable;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;

@Mixin(BlockView.class)
public interface BlockGetterMixin extends IBlockGetter {
    @Shadow
    net.minecraft.block.BlockState getBlockState(BlockPos pos);

    @Override
    default IBlockState getBlockState(IBlockPos pos) {
        return (IBlockState) (Object) getBlockState((BlockPos) (Object) pos);
    }

    @Shadow
    @Nullable
    BlockEntity getBlockEntity(BlockPos pos);

    @Override
    default @Nullable IBlockEntity getBlockEntity(IBlockPos pos) {
        return (IBlockEntity) (Object) getBlockEntity((BlockPos) (Object) pos);
    }
}
