package at.redi2go.photonic.client.mixin;

import net.minecraft.client.render.model.BakedQuad;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;

@Mixin(BakedQuad.class)
public class BakedQuadMixin {
   @Unique
   private boolean photonic$shouldBeVoxelized = true;
}
