package at.redi2go.photonic.client.mixin.mc;

import at.redi2go.photonics.api.mc.Id;
import net.minecraft.util.Identifier;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Overwrite;

@Mixin(value = Id.class, remap = false)
public interface IdImpl {
    @Overwrite
    static Id fromNamespaceAndPath(String namespace, String path) {
        return (Id) (Object) Identifier.of(namespace, path);
    }

    @Overwrite
    static Id parse(String string) {
        return (Id) (Object) Identifier.of(string);
    }

    @Overwrite
    static Id withDefaultNamespace(String path) {
        return (Id) (Object) Identifier.ofVanilla(path);
    }
}
