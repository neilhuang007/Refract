package at.redi2go.photonic.client.mixin;

import java.util.List;
import net.minecraft.resource.ResourceReloader;
import net.minecraft.resource.ReloadableResourceManagerImpl;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

@Mixin(ReloadableResourceManagerImpl.class)
public interface ReloadableResourceManagerAccessor {
   @Accessor("reloaders")
   List<ResourceReloader> getListeners();
}
