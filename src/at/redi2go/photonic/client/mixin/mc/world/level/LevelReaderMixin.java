package at.redi2go.photonic.client.mixin.mc.world.level;

import at.redi2go.photonics.api.mc.core.IRegistryAccess;
import at.redi2go.photonics.api.mc.world.level.ILevelReader;
import net.minecraft.registry.DynamicRegistryManager;
import net.minecraft.world.WorldView;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;

@Mixin(WorldView.class)
public interface LevelReaderMixin extends ILevelReader {
    @Shadow
    DynamicRegistryManager getRegistryManager();

    @Override
    default IRegistryAccess registryAccess() {
        return (IRegistryAccess) (Object) getRegistryManager();
    }
}
