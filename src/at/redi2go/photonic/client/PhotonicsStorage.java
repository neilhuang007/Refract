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

   private static Parameter<String> stringParam(String key, String defaultValue) {
      return new Parameter<>(key, s -> StorageIO.readString(s, defaultValue), StorageIO::writeString);
   }

   private static Parameter<Boolean> boolParam(String key, boolean defaultValue) {
      return new Parameter<>(key, s -> StorageIO.readBoolean(s, defaultValue), StorageIO::writeBoolean);
   }

   public static final Parameter<Boolean> DO_MULTITHREADING = boolParam("do_multithreading", true);
   public static final Parameter<Boolean> SHADOW_PIXELATION_ENABLED = boolParam("shadow_pixelation_enabled", true);
   public static final Parameter<Float> SHADOW_PIXELATION_SIZE = floatParam("shadow_pixelation_size", 8.0F);
   public static final Parameter<Boolean> PROFILER_ENABLED = boolParam("profiler_enabled", false);
   public static final Parameter<String> LIGHTING_MODE_OVERRIDE = stringParam("lighting_mode_override", "");
   public static final Parameter<Boolean> USE_OCTRAY_CHUNKS = boolParam("use_octray_chunks", true);
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
      blocksString -> new HashSet<>(StorageIO.readBlocks(blocksString, Set.of())),
      StorageIO::writeBlocks
   );
   public static final PhotonicsStorage.Parameter<Set<LightBlock>> TRACED_LIGHT_BLOCKS = new PhotonicsStorage.Parameter<>(
      "traced_light_blocks",
      lightBlocksString -> new HashSet<>(StorageIO.readLightBlocks(lightBlocksString, Set.of())),
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

   public static void applySystemPropertyOverrides() {
      applyStringSystemPropertyOverride("photonics.lightingMode", LIGHTING_MODE_OVERRIDE.value);
      applyBooleanSystemPropertyOverride("photonics.profilerEnabled", PROFILER_ENABLED);
   }

   private static void applyStringSystemPropertyOverride(String key, String value) {
      String systemValue = System.getProperty(key);
      if (systemValue != null && !systemValue.isBlank()) {
         return;
      }

      if (value == null || value.isBlank()) {
         // Blank local storage means "no local override", not "force clear any
         // externally supplied system property" such as automation/test launch args.
         return;
        } else {
         System.setProperty(key, value);
       }
   }

   private static void applyBooleanSystemPropertyOverride(String key, Parameter<Boolean> parameter) {
      String value = System.getProperty(key);
      if (value == null || value.isBlank()) {
         return;
      }

      parameter.value = Boolean.parseBoolean(value);
   }

   public static String getEffectiveStringOverride(Parameter<String> parameter, String systemPropertyKey) {
      if (parameter.value != null && !parameter.value.isBlank()) {
         return parameter.value;
      }
      String systemValue = System.getProperty(systemPropertyKey);
      return systemValue == null ? "" : systemValue;
   }
}
