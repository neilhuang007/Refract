package at.redi2go.photonic.client.mixin.mc.world.level;

import at.redi2go.photonics.api.mc.Id;
import at.redi2go.photonics.api.mc.world.level.IBlock;
import net.minecraft.registry.Registries;
import net.minecraft.util.Identifier;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Overwrite;

import java.util.Optional;

@Mixin(value = IBlock.class, remap = false)
@SuppressWarnings({"unchecked", "rawtypes"})
public interface IBlockImpl {
    @Overwrite
    static Optional<IBlock> fromId(Id id) {
        return Optional.ofNullable(Registries.BLOCK.get((Identifier) (Object) id))
                .map(block -> (IBlock) block);
    }
}
