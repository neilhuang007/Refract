package at.redi2go.photonic.client.mixin.mc.world.level;

import at.redi2go.photonics.api.mc.Id;
import at.redi2go.photonics.api.mc.world.level.IBlock;
import at.redi2go.photonics.api.mc.world.level.IBlockState;
import at.redi2go.photonics.api.mc.world.level.block.state.IStateDefinition;
import net.minecraft.block.Block;
import net.minecraft.block.BlockState;
import net.minecraft.registry.Registries;
import net.minecraft.state.StateManager;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;

@Mixin(Block.class)
@SuppressWarnings("unchecked")
public abstract class BlockMixin implements IBlock {
    @Shadow
    public abstract StateManager<Block, BlockState> getStateManager();

    @Shadow
    public abstract BlockState getDefaultState();

    @Override
    public Id id() {
        return (Id) (Object) Registries.BLOCK.getId((Block) (Object) this);
    }

    @Override
    public IStateDefinition<IBlock, IBlockState> stateDefinition() {
        return (IStateDefinition<IBlock, IBlockState>) getStateManager();
    }

    @Override
    public IBlockState defaultBlockState() {
        return (IBlockState) (Object) getDefaultState();
    }
}
