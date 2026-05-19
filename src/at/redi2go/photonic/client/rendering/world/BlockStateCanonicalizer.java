package at.redi2go.photonic.client.rendering.world;

import net.minecraft.block.BlockState;
import net.minecraft.state.property.Property;

final class BlockStateCanonicalizer {

   private BlockStateCanonicalizer() {
   }

   @SuppressWarnings({"unchecked", "rawtypes"})
   static BlockState withBooleanProperty(BlockState blockState, Property<?> property, boolean value) {
      Comparable<?> currentValue = blockState.getEntries().get(property);
      if (!(currentValue instanceof Boolean)) {
         return blockState;
      }
      return blockState.with((Property) property, Boolean.valueOf(value));
   }

   @SuppressWarnings({"unchecked", "rawtypes"})
   static BlockState withIntegerProperty(BlockState blockState, Property<?> property, boolean maxValue) {
      Comparable<?> currentValue = blockState.getEntries().get(property);
      if (!(currentValue instanceof Integer)) {
         return blockState;
      }

      Integer selected = null;
      for (Comparable<?> value : property.getValues()) {
         if (value instanceof Integer intValue) {
            if (selected == null || (maxValue ? intValue > selected : intValue < selected)) {
               selected = intValue;
            }
         }
      }
      return selected == null ? blockState : blockState.with((Property) property, selected);
   }

   static boolean isLightActivityProperty(Property<?> property) {
      String name = property.getName();
      return "lit".equals(name) || "powered".equals(name) || "enabled".equals(name);
   }

   static boolean isRtNonLightDynamicBooleanProperty(String propertyName) {
      return "lit".equals(propertyName)
         || "powered".equals(propertyName)
         || "enabled".equals(propertyName)
         || "triggered".equals(propertyName);
   }
}
