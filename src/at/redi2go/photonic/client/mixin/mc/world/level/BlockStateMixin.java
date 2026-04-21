package at.redi2go.photonic.client.mixin.mc.world.level;

import at.redi2go.photonics.api.mc.IProperty;
import at.redi2go.photonics.api.mc.world.level.IBlock;
import at.redi2go.photonics.api.mc.world.level.IBlockState;
import net.minecraft.block.BlockState;
import net.minecraft.state.property.Property;
import org.spongepowered.asm.mixin.Mixin;

@SuppressWarnings("unchecked")
@Mixin(BlockState.class)
public abstract class BlockStateMixin implements IBlockState {
    @Override
    public IBlock block() {
        return (IBlock) ((BlockState) (Object) this).getBlock();
    }

    @Override
    public boolean hasProperty(IProperty<?> property) {
        return ((BlockState) (Object) this).contains((Property<?>) property);
    }

    @Override
    public <T extends Comparable<T>> T getValue(IProperty<T> property) {
        return ((BlockState) (Object) this).get((Property<T>) property);
    }
}
