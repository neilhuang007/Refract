package at.redi2go.photonic.client.config.lights;

import at.redi2go.photonic.client.config.Variable;
import at.redi2go.photonic.client.config.adapter.BlockAdapter;
import at.redi2go.photonic.client.config.lights.block.LightBlock;
import at.redi2go.photonic.client.config.lights.color.LightColor;
import at.redi2go.photonic.client.config.lights.falloff.LightFalloff;
import at.redi2go.photonic.client.config.lights.intensity.LightIntensity;
import at.redi2go.photonic.client.config.lights.orientation.LightOrientation;
import at.redi2go.photonic.client.config.lights.predicate.LightPredicate;
import at.redi2go.photonic.client.config.lights.radius.LightRadius;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import net.minecraft.block.Block;
import net.minecraft.block.pattern.CachedBlockPosition;
import org.jetbrains.annotations.Nullable;

public class LightGroup {
   @Nullable
   LightColor color;
   @Nullable
   LightIntensity intensity;
   @Nullable
   LightRadius radius;
   @Nullable
   LightFalloff falloff;
   @Nullable
   LightOrientation orientation;
   @Nullable
   Boolean isTraced;
   @Nullable
   List<LightBlock> blocks;
   @Nullable
   LinkedHashMap<String, LightGroup> overrides;

   public void recordLights(Variable.Owner owner, LightList lights, Map<Block, Boolean> tracedLightsOverrides, int priority) {
      this.recordLightsImpl(owner, lights, tracedLightsOverrides, null, null, null, null, null, null, priority);
   }

   private void recordLightsImpl(
      Variable.Owner owner, LightList lights, Map<Block, Boolean> tracedLightsOverrides,
      @Nullable LightColor color, @Nullable Float intensity, @Nullable Float radius,
      @Nullable Float falloff, @Nullable LightOrientation orientation, @Nullable Boolean isTraced, int priority
   ) {
      if (this.color != null) color = setOwner(this.color, owner);
      if (this.intensity != null) intensity = setOwner(this.intensity, owner).get();
      if (this.radius != null) radius = setOwner(this.radius, owner).get();
      if (this.falloff != null) falloff = setOwner(this.falloff, owner).get();
      if (this.orientation != null) orientation = this.orientation;
      if (this.isTraced != null) isTraced = this.isTraced;

      if (this.blocks != null) {
         for (LightBlock block : this.blocks) {
            try {
               for (LightPredicate predicate : setOwner(block, owner).listPredicates()) {
                  addBlock(lights, tracedLightsOverrides, predicate, color, intensity, radius, falloff, orientation, isTraced, priority);
               }
            } catch (CommandSyntaxException ignored) {
            }
         }
      }

      if (this.overrides != null) {
         for (LightGroup override : this.overrides.values()) {
            override.recordLightsImpl(owner, lights, tracedLightsOverrides, color, intensity, radius, falloff, orientation, isTraced, priority);
         }
      }
   }

   private static <T> T setOwner(T value, Variable.Owner owner) {
      if (value instanceof Variable<?> variable) {
         variable.setOwner(owner);
      }
      return value;
   }

   private static void addBlock(
      LightList lights, Map<Block, Boolean> tracedLightsOverrides, LightPredicate predicate,
      @Nullable LightColor color, @Nullable Float intensity, @Nullable Float radius,
      @Nullable Float falloff, @Nullable LightOrientation orientation, @Nullable Boolean isTraced, int priority
   ) {
      Block block = predicate.block();
      String blockString = BlockAdapter.toString(block);
      Objects.requireNonNull(color, "no light color for " + blockString);
      Objects.requireNonNull(intensity, "no intensity for " + blockString);
      Objects.requireNonNull(radius, "no radius for " + blockString);
      Objects.requireNonNull(falloff, "no falloff for " + blockString);
      Objects.requireNonNull(isTraced, "no isTraced for " + blockString);
      if (priority != 0) {
         predicate = new PredicateWrapper(predicate.priority() + priority, predicate);
      }
      LightOrientation resolvedOrientation = orientation == null ? LightOrientation.OMNI : orientation;
      lights.add(new BlockLightInfo(predicate, color, intensity, radius, falloff, evaluateIsTraced(isTraced, block, tracedLightsOverrides), isTraced, resolvedOrientation));
   }

   private static boolean evaluateIsTraced(boolean actual, Block block, Map<Block, Boolean> tracedLightsOverrides) {
      Boolean value = tracedLightsOverrides.get(block);
      return value == null ? actual : value;
   }

   private record PredicateWrapper(int priority, LightPredicate actual) implements LightPredicate {
      @Override
      public Block block() {
         return this.actual.block();
      }

      @Override
      public boolean test(CachedBlockPosition block) {
         return this.actual.test(block);
      }
   }
}
