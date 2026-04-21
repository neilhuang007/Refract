package at.redi2go.photonic.client.mixin.mc;

import at.redi2go.photonics.api.mc.IProperty;
import net.minecraft.state.property.Property;
import org.spongepowered.asm.mixin.Mixin;

import java.util.Optional;

@Mixin(Property.class)
public abstract class PropertyMixin<T extends Comparable<T>> implements IProperty<T> {
    @Override
    public Optional<T> getValue(String name) {
        return ((Property<T>) (Object) this).parse(name);
    }
}
