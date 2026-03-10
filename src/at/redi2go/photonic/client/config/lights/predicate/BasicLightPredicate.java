package at.redi2go.photonic.client.config.lights.predicate;

import java.util.Objects;
import net.minecraft.block.Block;
import net.minecraft.block.pattern.CachedBlockPosition;
import net.minecraft.command.argument.BlockArgumentParser;

public record BasicLightPredicate(Block block, int priority) implements LightPredicate {
   public BasicLightPredicate {
      Objects.requireNonNull(block, "block was null");
   }

   @Override
   public boolean test(CachedBlockPosition block) {
      return block.getBlockState().isOf(this.block);
   }

   public static boolean isBasic(BlockArgumentParser.BlockResult blockResult) {
      return blockResult.properties().isEmpty() && (blockResult.nbt() == null || blockResult.nbt().isEmpty());
   }

   public static boolean isBasic(BlockArgumentParser.TagResult tagResult) {
      return tagResult.vagueProperties().isEmpty() && (tagResult.nbt() == null || tagResult.nbt().isEmpty());
   }
}
