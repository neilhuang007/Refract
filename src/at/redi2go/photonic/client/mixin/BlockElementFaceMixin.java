package at.redi2go.photonic.client.mixin;

import net.minecraft.client.render.model.json.ModelElementFace;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;

@Mixin(ModelElementFace.class)
public class BlockElementFaceMixin {
   @Unique
   private boolean photonic$shouldBeVoxelized = true;
}
