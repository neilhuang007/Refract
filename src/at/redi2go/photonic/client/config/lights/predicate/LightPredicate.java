package at.redi2go.photonic.client.config.lights.predicate;

import com.mojang.brigadier.StringReader;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import java.util.List;
import java.util.stream.Collectors;
import net.minecraft.block.Block;
import net.minecraft.block.pattern.CachedBlockPosition;
import net.minecraft.command.argument.BlockArgumentParser;
import net.minecraft.registry.Registries;

public interface LightPredicate extends Comparable<LightPredicate> {
   int NORMAL_PRIORITY = 0;
   int DEFAULT_PRIORITY = Integer.MIN_VALUE;

   Block block();
   int priority();
   boolean test(CachedBlockPosition block);

   default int compareTo(LightPredicate o) {
      return Integer.compare(this.priority(), o.priority());
   }

   static List<LightPredicate> parse(String value, int priority) throws CommandSyntaxException {
      return BlockArgumentParser.blockOrTag(Registries.BLOCK.getReadOnlyWrapper(), new StringReader(value), true)
         .map(
            blockResult -> fromBlockResult(priority, blockResult),
            tagResult -> fromTagResult(priority, tagResult)
         );
   }

   private static List<LightPredicate> fromBlockResult(int priority, BlockArgumentParser.BlockResult blockResult) {
      if (BasicLightPredicate.isBasic(blockResult) && priority == Integer.MIN_VALUE) {
         return List.of(new BasicLightPredicate(blockResult.blockState().getBlock(), priority));
      } else {
         int adjustedPriority = priority == Integer.MIN_VALUE ? 0 : priority;
         return List.of(new LightPredicateImpl(blockResult.blockState(), List.copyOf(blockResult.properties().keySet()), blockResult.nbt(), adjustedPriority));
      }
   }

   private static List<LightPredicate> fromTagResult(int priority, BlockArgumentParser.TagResult tagResult) {
      if (BasicLightPredicate.isBasic(tagResult) && priority == Integer.MIN_VALUE) {
         return tagResult.tag()
            .stream()
            .map(holder -> new BasicLightPredicate(holder.value(), priority))
            .collect(Collectors.toUnmodifiableList());
      } else {
         int adjustedPriority = priority == Integer.MIN_VALUE ? 0 : priority;
         return tagResult.tag()
            .stream()
            .map(holder -> (LightPredicate) new TagLightPredicate(holder.value(), tagResult.nbt(), tagResult.vagueProperties(), adjustedPriority))
            .collect(Collectors.toUnmodifiableList());
      }
   }
}
