package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.BlockElementFaceExt;
import net.minecraft.client.render.model.json.ModelElementFace;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;

@Mixin(ModelElementFace.class)
public class BlockElementFaceMixin implements BlockElementFaceExt {
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
