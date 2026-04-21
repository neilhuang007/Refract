package at.redi2go.photonic.client.mixin.mc.core;

import at.redi2go.photonics.api.mc.core.IRegistryAccess;
import net.minecraft.registry.DynamicRegistryManager;
import org.spongepowered.asm.mixin.Mixin;

@Mixin(DynamicRegistryManager.class)
public interface RegistryAccessMixin extends IRegistryAccess {
}
