package at.redi2go.photonic.client.config.lights.predicate;

import java.util.List;
import java.util.Objects;
import net.minecraft.block.Block;
import net.minecraft.block.BlockState;
import net.minecraft.block.entity.BlockEntity;
import net.minecraft.block.pattern.CachedBlockPosition;
import net.minecraft.nbt.NbtCompound;
import net.minecraft.state.property.Property;
import org.jetbrains.annotations.Nullable;

public record LightPredicateImpl(BlockState blockState, List<Property<?>> properties, @Nullable NbtCompound nbt, int priority) implements LightPredicate {
   public LightPredicateImpl {
      Objects.requireNonNull(blockState, "blockState was null");
      Objects.requireNonNull(properties, "properties was null");
   }

   @Override
   public Block block() {
      return this.blockState.getBlock();
   }

   @Override
   public boolean test(CachedBlockPosition block) {
      BlockState state = block.getBlockState();
      if (!state.isOf(this.block())) {
         return false;
      }
      for (Property<?> property : this.properties) {
         if (!this.blockState.get(property).equals(state.get(property))) {
            return false;
         }
      }
      if (this.nbt == null) {
         return true;
      }
      BlockEntity blockEntity = block.getBlockEntity();
      return blockEntity != null && TagLightPredicate.isNbtEqual(this.nbt, blockEntity, block.getWorld());
   }
}
