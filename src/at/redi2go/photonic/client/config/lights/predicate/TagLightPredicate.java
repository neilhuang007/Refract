package at.redi2go.photonic.client.config.lights.predicate;

import java.util.Map;
import java.util.Objects;
import net.minecraft.block.Block;
import net.minecraft.block.BlockState;
import net.minecraft.block.entity.BlockEntity;
import net.minecraft.block.pattern.CachedBlockPosition;
import net.minecraft.nbt.NbtCompound;
import net.minecraft.nbt.NbtHelper;
import net.minecraft.state.property.Property;
import net.minecraft.world.WorldView;
import org.jetbrains.annotations.Nullable;

public record TagLightPredicate(Block block, @Nullable NbtCompound nbt, Map<String, String> vagueProperties, int priority) implements LightPredicate {
   public TagLightPredicate {
      Objects.requireNonNull(block, "block was null");
      Objects.requireNonNull(vagueProperties, "vagueProperties was null");
   }

   @Override
   public boolean test(CachedBlockPosition block) {
      BlockState state = block.getBlockState();
      if (!state.isOf(this.block())) {
         return false;
      }
      for (Map.Entry<String, String> entry : this.vagueProperties.entrySet()) {
         Property<?> property = this.block().getStateManager().getProperty(entry.getKey());
         if (property == null) {
            return false;
         }
         Comparable<?> value = property.parse(entry.getValue()).orElse(null);
         if (value == null) {
            return false;
         }
         if (!value.equals(state.get(property))) {
            return false;
         }
      }
      if (this.nbt == null) {
         return true;
      }
      BlockEntity blockEntity = block.getBlockEntity();
      return blockEntity != null && isNbtEqual(this.nbt, blockEntity, block.getWorld());
   }

   static boolean isNbtEqual(NbtCompound nbt, BlockEntity blockEntity, WorldView level) {
      return NbtHelper.matches(nbt, blockEntity.createNbtWithIdentifyingData(level.getRegistryManager()), true);
   }
}
