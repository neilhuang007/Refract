package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.BakedQuadExt;
import net.minecraft.client.render.model.BakedQuad;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;

@Mixin(BakedQuad.class)
public class BakedQuadMixin implements BakedQuadExt {
   @Unique
   private boolean shouldBeVoxelized = true;

   @Override
   public boolean photonic$shouldBeVoxelized() {
      return this.shouldBeVoxelized;
   }

   @Override
   public void photonic$setShouldBeVoxelized(boolean shouldBeVoxelized) {
      this.shouldBeVoxelized = shouldBeVoxelized;
   }
}
