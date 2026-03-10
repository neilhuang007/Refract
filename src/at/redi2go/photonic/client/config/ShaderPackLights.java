package at.redi2go.photonic.client.config;

import at.redi2go.photonic.client.config.lights.LightDefines;
import at.redi2go.photonic.client.config.lights.LightGroup;
import at.redi2go.photonic.client.config.lights.LightList;
import at.redi2go.photonic.client.config.lights.LightsProvider;
import at.redi2go.photonic.client.config.lights.block.LightBlock;
import at.redi2go.photonic.client.config.lights.predicate.LightPredicate;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import net.irisshaders.iris.shaderpack.IdMap;
import net.irisshaders.iris.shaderpack.ShaderPack;
import net.irisshaders.iris.shaderpack.materialmap.BlockEntry;
import net.irisshaders.iris.shaderpack.materialmap.TagEntry;
import net.minecraft.block.Block;
import net.minecraft.block.BlockState;
import net.minecraft.block.pattern.CachedBlockPosition;
import net.minecraft.registry.Registries;
import net.minecraft.registry.RegistryKeys;
import net.minecraft.registry.entry.RegistryEntry;
import net.minecraft.registry.tag.TagKey;
import net.minecraft.state.property.Property;
import net.minecraft.util.Identifier;
import org.jetbrains.annotations.Nullable;

public class ShaderPackLights implements LightsProvider, Variable.Owner {
   LightDefines defines = LightDefines.EMPTY;
   LinkedHashMap<String, LightGroup> lights = new LinkedHashMap<>(0);
   private ShaderPack shaderPack;

   public void setShaderPack(ShaderPack pack) {
      this.shaderPack = pack;
      this.defines.setOwner(this);
   }

   @Override
   public void registerLights(LightList lights) {
      for (LightGroup lightGroup : this.lights.values()) {
         lightGroup.recordLights(this, lights, PhotonicsConfig.getTracedOverrides(), 1000);
      }
   }

   @Override
   public void registerChangeListener(Runnable consumer) {
   }

   @Override
   public void clearListeners() {
   }

   @Override
   public int mod() {
      return 0;
   }

   @Override
   @SuppressWarnings("unchecked")
   public <T> Optional<T> getValue(Variable.Type<T> type, String name) {
      if (type == LightBlock.TYPE) {
         try {
            IdMap idMap = this.shaderPack.getIdMap();
            int id = Integer.parseInt(name);
            List<BlockEntry> blocks = idMap.getBlockProperties().getOrDefault(id, null);
            List<TagEntry> tags = idMap.getTagEntries().getOrDefault(id, null);
            return blocks == null && tags == null ? Optional.empty() : Optional.of((T) new ShaderLightBlock(blocks, tags));
         } catch (NumberFormatException e) {
            return Optional.empty();
         }
      } else {
         return this.defines.getValue(type, name);
      }
   }

   public static ShaderPackLights parse(String contents) {
      String[] lines = contents.split("\n");
      int start = 0;
      for (int i = lines.length - 1; i >= 0; i--) {
         String line = lines[i];
         if (!line.isEmpty() && line.charAt(0) == '{') {
            start = i;
            break;
         }
      }
      contents = String.join("\n", Arrays.copyOfRange(lines, start, lines.length));
      contents = contents.replaceAll("`", "\"");
      return PhotonicsConfig.GSON.fromJson(contents, ShaderPackLights.class);
   }

   private record ShaderLightBlock(@Nullable List<BlockEntry> blocks, @Nullable List<TagEntry> tags) implements LightBlock {
      @Override
      public List<LightPredicate> listPredicates() throws CommandSyntaxException {
         ArrayList<LightPredicate> out = new ArrayList<>();
         if (this.blocks != null) {
            for (BlockEntry block : this.blocks) {
               Identifier id = Identifier.of(block.id().getNamespace(), block.id().getName());
               Registries.BLOCK.getOrEmpty(id).ifPresent(resolved -> out.add(new ShaderPredicate(resolved, block.propertyPredicates())));
            }
         }
         if (this.tags != null) {
            for (TagEntry tag : this.tags) {
               Identifier id = Identifier.of(tag.id().getNamespace(), tag.id().getName());
               TagKey<Block> key = TagKey.of(RegistryKeys.BLOCK, id);
               Registries.BLOCK.getEntryList(key).ifPresent(entries -> {
                  for (RegistryEntry<Block> entry : entries) {
                     out.add(new ShaderPredicate(entry.value(), tag.propertyPredicates()));
                  }
               });
            }
         }
         return out;
      }
   }

   private record ShaderPredicate(Block block, Map<String, String> vagueProperties) implements LightPredicate {
      public ShaderPredicate {
         Objects.requireNonNull(block, "block was null");
         Objects.requireNonNull(vagueProperties, "vagueProperties was null");
      }

      @Override
      public int priority() {
         return 0;
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
         return true;
      }
   }
}
