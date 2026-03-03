package at.redi2go.photonic.client;

import at.redi2go.photonic.client.rendering.world.LightBlock;
import java.util.HashSet;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Consumer;
import java.util.function.Function;
import net.minecraft.block.Block;

public final class PhotonicsStorage {
   private static final Map<String, String[]> CONFIG_VALUES = StorageIO.readConfig();

   private static Parameter<Float> floatParam(String key, float defaultValue) {
      return new Parameter<>(key, s -> StorageIO.readFloat(s, defaultValue), StorageIO::writeFloat);
   }

   private static Parameter<Boolean> boolParam(String key, boolean defaultValue) {
      return new Parameter<>(key, s -> StorageIO.readBoolean(s, defaultValue), StorageIO::writeBoolean);
   }

   public static final Parameter<Boolean> DO_MULTITHREADING = boolParam("do_multithreading", false);
   public static final Parameter<Boolean> SHADOW_PIXELATION_ENABLED = boolParam("shadow_pixelation_enabled", true);
   public static final Parameter<Float> SHADOW_PIXELATION_SIZE = floatParam("shadow_pixelation_size", 8.0F);
   public static final Parameter<Boolean> PIXELATED_LIGHTING_DEBUG_LOG = boolParam("pixelated_lighting_debug_log", false);
   public static final Parameter<Boolean> OILIFY_ENABLED = boolParam("oilify_enabled", false);
   public static final Parameter<Float> OILIFY_SIZE = floatParam("oilify_size", 7.0F);
   public static final Parameter<Float> OILIFY_SHARPNESS = floatParam("oilify_sharpness", 1.0F);
   public static final Parameter<Float> OILIFY_SCALE = floatParam("oilify_scale", 1.0F);
   public static final Parameter<Float> OILIFY_TUNING = floatParam("oilify_tuning", 2.0F);
   public static final Parameter<Float> OILIFY_ITERATIONS = floatParam("oilify_iterations", 1.0F);
   public static final Parameter<Float> OILIFY_DEPTH_SCALING = floatParam("oilify_depth_scaling", 0.5F);
   public static final Parameter<Float> OILIFY_STROKE_STRENGTH = floatParam("oilify_stroke_strength", 0.0F);
   public static final PhotonicsStorage.Parameter<Set<Block>> VOLUMETRIC_RENDERED_BLOCKS = new PhotonicsStorage.Parameter<>(
      "volumetric_blocks",
      blocksString -> new HashSet<>(StorageIO.readBlocks(blocksString, Raytracer.DEFAULT_VOLUMETRIC_RENDERED_BLOCKS)),
      StorageIO::writeBlocks
   );
   public static final PhotonicsStorage.Parameter<Set<LightBlock>> TRACED_LIGHT_BLOCKS = new PhotonicsStorage.Parameter<>(
      "traced_light_blocks",
      lightBlocksString -> new HashSet<>(StorageIO.readLightBlocks(lightBlocksString, Raytracer.DEFAULT_LIGHT_BLOCKS)),
      StorageIO::writeLightBlocks
   );

   public static class Parameter<T> {
      private final List<Consumer<T>> observers = new LinkedList<>();
      public final String configKey;
      public final Function<T, String[]> serializer;
      public T value;

      public Parameter(String configKey, Function<String[], T> deserializer, Function<T, String[]> serializer) {
         this.configKey = configKey;
         this.serializer = serializer;
         this.value = deserializer.apply(PhotonicsStorage.CONFIG_VALUES.get(configKey));
      }

      public void modified() {
         this.observers.forEach(observer -> observer.accept(this.value));
         PhotonicsStorage.CONFIG_VALUES.put(this.configKey, this.serializer.apply(this.value));
         StorageIO.writeConfig(PhotonicsStorage.CONFIG_VALUES);
      }

      public void addObserver(Consumer<T> observer) {
         this.observers.add(observer);
      }

      public void removeObserver(Consumer<T> observer) {
         this.observers.remove(observer);
      }
   }
}
