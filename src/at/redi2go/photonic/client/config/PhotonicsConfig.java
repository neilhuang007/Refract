package at.redi2go.photonic.client.config;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.config.adapter.BlockAdapter;
import at.redi2go.photonic.client.config.lights.LightDefines;
import at.redi2go.photonic.client.config.lights.LightGroup;
import at.redi2go.photonic.client.config.lights.LightList;
import at.redi2go.photonic.client.config.lights.LightsProvider;
import at.redi2go.photonic.client.config.lights.block.LightBlock;
import at.redi2go.photonic.client.config.lights.color.LightColor;
import at.redi2go.photonic.client.config.lights.falloff.LightFalloff;
import at.redi2go.photonic.client.config.lights.intensity.LightIntensity;
import at.redi2go.photonic.client.config.lights.radius.LightRadius;
import com.google.common.collect.Sets;
import com.google.gson.FieldNamingPolicy;
import com.google.gson.Gson;
import com.google.gson.GsonBuilder;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.StandardOpenOption;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.function.Consumer;
import java.util.function.Function;
import net.minecraft.block.Block;

public class PhotonicsConfig {
   public boolean multiThreadingEnabled = true;
   public LightDefines defines = LightDefines.EMPTY;
   public LinkedHashMap<String, LightGroup> lights;
   public Map<Block, Boolean> raytraced_lights;
   public Set<Block> voxelizedBlocks;
   private static LightList lightList = new LightList();
   private static final Set<LightsProvider> LIGHTS_PROVIDERS = Sets.newHashSet(new LightsProvider() {
      @Override
      public void registerLights(LightList lights) {
         for (LightGroup lightGroup : PhotonicsConfig.INSTANCE.lights.values()) {
            lightGroup.recordLights(PhotonicsConfigOwner.INSTANCE, PhotonicsConfig.lightList, PhotonicsConfig.INSTANCE.raytraced_lights, 0);
         }
      }

      @Override
      public void registerChangeListener(Runnable consumer) {
         throw new UnsupportedOperationException("registerChangeListener");
      }

      @Override
      public void clearListeners() {
         throw new UnsupportedOperationException("clearListeners");
      }
   });
   public static final Gson GSON = new GsonBuilder()
      .registerTypeAdapter(LightColor.class, new LightColor.Adapter())
      .registerTypeAdapter(LightIntensity.class, new LightIntensity.Adapter())
      .registerTypeAdapter(LightRadius.class, new LightRadius.Adapter())
      .registerTypeAdapter(LightFalloff.class, new LightFalloff.Adapter())
      .registerTypeAdapter(LightBlock.class, new LightBlock.Adapter())
      .registerTypeAdapter(Block.class, new BlockAdapter())
      .setFieldNamingPolicy(FieldNamingPolicy.LOWER_CASE_WITH_UNDERSCORES)
      .excludeFieldsWithModifiers(2, 8)
      .enableComplexMapKeySerialization()
      .disableHtmlEscaping()
      .setPrettyPrinting()
      .setLenient()
      .create();
   private static final LinkedHashMap<String, LightGroup> EMPTY_LIGHTS = new LinkedHashMap<>(0);
   public static PhotonicsConfig INSTANCE = new PhotonicsConfig();
   private static final Set<PhotonicsConfig.Observer<?>> OBSERVERS = new LinkedHashSet<>();
   static int mod = 0;

   public PhotonicsConfig() {
      this.lights = EMPTY_LIGHTS;
      this.raytraced_lights = Map.of();
      this.voxelizedBlocks = Set.of();
   }

   public static PhotonicsConfig getInstance() {
      return INSTANCE;
   }

   public static boolean isMultiThreadingEnabled() {
      return INSTANCE.multiThreadingEnabled;
   }

   public static void setMultiThreadingEnabled(boolean enabled) {
      INSTANCE.multiThreadingEnabled = enabled;
   }

   public static LightList getLightList() {
      return lightList;
   }

   public static Set<Block> getVoxelizedBlocks() {
      return INSTANCE.voxelizedBlocks;
   }

   public static boolean isVoxelized(Block block) {
      return getVoxelizedBlocks().contains(block);
   }

   public static void setVoxelized(Block block, boolean enabled) {
      if (enabled) {
         getVoxelizedBlocks().add(block);
      } else {
         getVoxelizedBlocks().remove(block);
      }
   }

   public static Map<Block, Boolean> getTracedOverrides() {
      return INSTANCE.raytraced_lights;
   }

   public static synchronized void registerLightProvider(LightsProvider provider) {
      LIGHTS_PROVIDERS.add(provider);
      provider.registerChangeListener(PhotonicsConfig::onChangedSafe);
      onChanged();
   }

   public static synchronized void removeLightProvider(LightsProvider provider) {
      if (LIGHTS_PROVIDERS.remove(provider)) {
         provider.clearListeners();
         onChanged();
      }
   }

   public static synchronized <T> PhotonicsConfig.Observer<T> observe(Function<PhotonicsConfig, T> supplier, Consumer<T> consumer) {
      PhotonicsConfig.Observer<T> observer = new PhotonicsConfig.Observer<>(supplier, consumer);
      OBSERVERS.add(observer);
      return observer;
   }

   private static synchronized void removeObserver(PhotonicsConfig.Observer<?> observer) {
      OBSERVERS.remove(observer);
   }

   public static synchronized void prepareModify() {
      try {
         INSTANCE = GSON.fromJson(GSON.toJson(INSTANCE), PhotonicsConfig.class);
      } catch (Exception e) {
         Photonic.error("Could not copy config", e);
      }
   }

   public static synchronized void reloadConfig() {
      mod++;
      if (Files.notExists(Photonic.CONFIG_PATH)) {
         try {
            copyDefaultConfig();
         } catch (Exception e) {
            Photonic.error("Could not create default config", e);
            throw e;
         }
      }

      Photonic.info("Reloading config");

      try (BufferedReader reader = Files.newBufferedReader(Photonic.CONFIG_PATH)) {
         PhotonicsConfig loadedConfig = GSON.fromJson(reader, PhotonicsConfig.class);
         INSTANCE = loadedConfig == null ? new PhotonicsConfig() : loadedConfig;
         INSTANCE = normalizeConfig(INSTANCE);
         onChanged();
      } catch (Exception e) {
         Photonic.error("Could not reload config", e);
      }
   }

   public static synchronized void save() {
      mod++;
      PhotonicsConfigWatchThread.beginSave();

      try (BufferedWriter writer = Files.newBufferedWriter(Photonic.CONFIG_PATH)) {
         GSON.toJson(INSTANCE, writer);
      } catch (IOException e) {
         PhotonicsConfigWatchThread.reset();
         throw new RuntimeException(e);
      }

      PhotonicsConfigWatchThread.endSave();
   }

   private static synchronized void copyDefaultConfig() {
      try (InputStream input = Objects.requireNonNull(
         Photonic.class.getClassLoader().getResourceAsStream(Photonic.DEFAULT_CONFIG_PATH),
         "Missing default config resource: " + Photonic.DEFAULT_CONFIG_PATH
      )) {
         Files.createDirectories(Photonic.CONFIG_PATH.getParent());
         try (OutputStream writer = Files.newOutputStream(Photonic.CONFIG_PATH, StandardOpenOption.CREATE_NEW)) {
            input.transferTo(writer);
         }
      } catch (IOException e) {
         throw new RuntimeException(e);
      } catch (NullPointerException e) {
         throw new RuntimeException(e);
      }
   }

   private static synchronized void onChangedSafe() {
      try {
         onChanged();
      } catch (Exception e) {
         throw new RuntimeException(e);
      }
   }

   public static synchronized void onChanged() {
      PhotonicsConfig config = INSTANCE;
      config.defines.setOwner(PhotonicsConfigOwner.INSTANCE);
      lightList = new LightList();

      for (LightsProvider provider : LIGHTS_PROVIDERS) {
         try {
            provider.registerLights(lightList);
         } catch (Exception e) {
            Photonic.warn("Could not register lights provider", e);
         }
      }

      lightList.sort();

      for (PhotonicsConfig.Observer<?> observer : OBSERVERS) {
         observer.reload(config);
      }
   }

   private static PhotonicsConfig normalizeConfig(PhotonicsConfig config) {
      config.defines = config.defines == null ? new LightDefines() : config.defines;
      config.lights = config.lights == null ? new LinkedHashMap<>() : config.lights;
      config.raytraced_lights = config.raytraced_lights == null ? Map.of() : config.raytraced_lights;
      config.voxelizedBlocks = config.voxelizedBlocks == null ? Set.of() : config.voxelizedBlocks;
      return config;
   }

   public static class Observer<T> implements PhListener {
      private static final Object NO_VALUE = new Object();
      private final Function<PhotonicsConfig, T> supplier;
      private final Consumer<T> consumer;
      private Object previousValue = NO_VALUE;

      Observer(Function<PhotonicsConfig, T> supplier, Consumer<T> consumer) {
         this.supplier = supplier;
         this.consumer = consumer;
      }

      void reload(PhotonicsConfig config) {
         T newValue = this.supplier.apply(config);
         if (this.previousValue != newValue) {
            this.previousValue = newValue;
            this.consumer.accept(newValue);
         }
      }

      @Override
      public void unregister() {
         PhotonicsConfig.removeObserver(this);
      }
   }
}
