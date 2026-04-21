package at.redi2go.photonic.client.mixin.mc.world.level.block.state;

import at.redi2go.photonics.api.mc.IProperty;
import at.redi2go.photonics.api.mc.world.level.block.state.IStateDefinition;
import net.minecraft.state.StateManager;
import org.jetbrains.annotations.Nullable;
import org.spongepowered.asm.mixin.Mixin;

@Mixin(StateManager.class)
public abstract class StateManagerMixin<K, V> implements IStateDefinition<K, V> {
    @Override
    public @Nullable IProperty<?> getProperty(String string) {
        return (IProperty<?>) ((StateManager<?, ?>) (Object) this).getProperty(string);
    }
}
