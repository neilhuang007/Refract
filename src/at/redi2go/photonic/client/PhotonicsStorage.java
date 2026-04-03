package at.redi2go.photonic.client;

import at.redi2go.photonic.client.rendering.world.LightBlock;
import java.util.HashSet;
import java.util.LinkedList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
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
   public static final Parameter<Boolean> DEBUG_SHOW_DIRECT = boolParam("debug_show_direct", true);
   public static final Parameter<Boolean> DEBUG_SHOW_INDIRECT = boolParam("debug_show_indirect", true);
   public static final Parameter<Boolean> DEBUG_SHOW_HANDHELD = boolParam("debug_show_handheld", true);
   public static final Parameter<Boolean> DEBUG_SHOW_SCENE = boolParam("debug_show_scene", true);
   public static final Parameter<Boolean> DEBUG_DISABLE_SHADOW_RAYS = boolParam("debug_disable_shadow_rays", false);
   public static final Parameter<Boolean> DEBUG_LOCK_TRAVERSAL_RNG = boolParam("debug_lock_traversal_rng", false);
   public static final Parameter<Boolean> DEBUG_DISABLE_TEMPORAL_RESET = boolParam("debug_disable_temporal_reset", false);
   public static final Parameter<Boolean> DEBUG_DISABLE_TAA_JITTER = boolParam("debug_disable_taa_jitter", false);
   public static final Parameter<Boolean> DEBUG_FREEZE_RNG = boolParam("debug_freeze_rng", false);
   public static final Parameter<String> DEBUG_DIRECT_STAGE_VIEW = stringParam("debug_direct_stage_view", "final");
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_PROPOSAL_RESERVOIR = boolParam("debug_enable_direct_proposal_reservoir", true);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_TEMPORAL_REUSE = boolParam("debug_enable_direct_temporal_reuse", false);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_SPATIAL_REUSE = boolParam("debug_enable_direct_spatial_reuse", false);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_SHADE_SAMPLES = boolParam("debug_enable_direct_shade_samples", true);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_FINAL_VISIBILITY = boolParam("debug_enable_direct_final_visibility", true);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_VISIBILITY_TRANSMITTANCE = boolParam("debug_enable_direct_visibility_transmittance", true);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_TEMPORAL_ACCUMULATION = boolParam("debug_enable_direct_temporal_accumulation", true);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_HISTORY_FIX = boolParam("debug_enable_direct_history_fix", true);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_HISTORY_CLAMPING = boolParam("debug_enable_direct_history_clamping", true);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_ANTI_FIREFLY = boolParam("debug_enable_direct_anti_firefly", true);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_ATROUS = boolParam("debug_enable_direct_atrous", true);
   public static final Parameter<String> RESTIR_CHECKERBOARD_MODE = stringParam("restir_checkerboard_mode", "off");
   // Performance tuning — Quality profile and per-parameter overrides.
   // A value of -1 means "use shaderpack default" (auto).  Any positive
   // value overrides the shaderpack setting at runtime.
   public static final Parameter<String> QUALITY_PROFILE = stringParam("quality_profile", "custom");
   public static final Parameter<Float> RENDER_SCALE = floatParam("render_scale", -1.0F);
   public static final Parameter<Float> NRD_ATROUS_PASSES = floatParam("nrd_atrous_passes", -1.0F);
   public static final Parameter<Float> RESTIR_INITIAL_SAMPLES = floatParam("restir_initial_samples", -1.0F);
   public static final Parameter<Float> RESTIR_SPATIAL_SAMPLES = floatParam("restir_spatial_samples", -1.0F);
   public static final Parameter<Float> RESTIR_GI_SPATIAL_SAMPLES = floatParam("restir_gi_spatial_samples", -1.0F);
   public static final Parameter<Float> RESTIR_SPATIAL_RADIUS = floatParam("restir_spatial_radius", -1.0F);
   public static final Parameter<Float> RESTIR_SPATIAL_BIAS_MODE = floatParam("restir_spatial_bias_mode", -1.0F);
   public static final Parameter<Boolean> DEBUG_CONSTANT_ALBEDO = boolParam("debug_constant_albedo", false);
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

   static {
      if (normalizeLoadedQualityProfile()) {
         StorageIO.writeConfig(CONFIG_VALUES);
      }
   }

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
      applyBooleanSystemPropertyOverride("photonics.profilerEnabled", PROFILER_ENABLED);
      applyBooleanSystemPropertyOverride("photonics.debugEnableDirectProposalReservoir", DEBUG_ENABLE_DIRECT_PROPOSAL_RESERVOIR);
      applyBooleanSystemPropertyOverride("photonics.debugEnableDirectTemporalReuse", DEBUG_ENABLE_DIRECT_TEMPORAL_REUSE);
      applyBooleanSystemPropertyOverride("photonics.debugEnableDirectSpatialReuse", DEBUG_ENABLE_DIRECT_SPATIAL_REUSE);
      applyBooleanSystemPropertyOverride("photonics.debugEnableDirectShadeSamples", DEBUG_ENABLE_DIRECT_SHADE_SAMPLES);
      applyBooleanSystemPropertyOverride("photonics.debugEnableDirectFinalVisibility", DEBUG_ENABLE_DIRECT_FINAL_VISIBILITY);
      applyBooleanSystemPropertyOverride("photonics.debugEnableDirectVisibilityTransmittance", DEBUG_ENABLE_DIRECT_VISIBILITY_TRANSMITTANCE);
      applyBooleanSystemPropertyOverride("photonics.debugEnableDirectTemporalAccumulation", DEBUG_ENABLE_DIRECT_TEMPORAL_ACCUMULATION);
      applyBooleanSystemPropertyOverride("photonics.debugEnableDirectHistoryFix", DEBUG_ENABLE_DIRECT_HISTORY_FIX);
      applyBooleanSystemPropertyOverride("photonics.debugEnableDirectHistoryClamping", DEBUG_ENABLE_DIRECT_HISTORY_CLAMPING);
      applyBooleanSystemPropertyOverride("photonics.debugEnableDirectAntiFirefly", DEBUG_ENABLE_DIRECT_ANTI_FIREFLY);
      applyBooleanSystemPropertyOverride("photonics.debugEnableDirectAtrous", DEBUG_ENABLE_DIRECT_ATROUS);
   }

   private static void applyBooleanSystemPropertyOverride(String key, Parameter<Boolean> parameter) {
      String value = System.getProperty(key);
      if (value == null || value.isBlank()) {
         return;
      }

      parameter.value = Boolean.parseBoolean(value);
   }

   public static String normalizeDirectStageView(String stageView) {
      if (stageView == null) {
         return "final";
      }

      return switch (stageView.trim().toLowerCase(Locale.ROOT)) {
         case "", "none", "resolved", "final" -> "final";
         case "stage_direct", "direct_raw", "raw", "rt", "rt_raw" -> "stage_direct";
         case "direct_noisy", "noisy", "temporal", "temporal_raw" -> "direct_noisy";
         case "direct_responsive", "responsive" -> "direct_responsive";
         case "direct_slow", "slow" -> "direct_slow";
         case "direct_fast", "fast" -> "direct_fast";
         case "direct_historyfix", "historyfix", "history_fix" -> "direct_historyfix";
         case "direct_clamped_fast", "clamped_fast" -> "direct_clamped_fast";
         case "direct_anti_firefly", "anti_firefly", "firefly" -> "direct_anti_firefly";
         case "direct_denoised", "denoised" -> "direct_denoised";
         case "direct_atrous", "atrous" -> "direct_atrous";
         default -> "final";
      };
   }

   public static boolean isFinalDirectStageView(String stageView) {
      return "final".equals(normalizeDirectStageView(stageView));
   }

   private static boolean normalizeLoadedQualityProfile() {
      String profile = QUALITY_PROFILE.value == null ? "custom" : QUALITY_PROFILE.value.trim().toLowerCase(Locale.ROOT);
      boolean changed = false;

      switch (profile) {
         case "low" -> {
            changed |= setLoadedParam(RESTIR_INITIAL_SAMPLES, 4.0F);
            changed |= setLoadedParam(RESTIR_SPATIAL_SAMPLES, 1.0F);
            changed |= setLoadedParam(RESTIR_SPATIAL_RADIUS, 32.0F);
            changed |= setLoadedParam(RESTIR_SPATIAL_BIAS_MODE, 0.0F);
         }
         case "medium" -> {
            changed |= setLoadedParam(RESTIR_INITIAL_SAMPLES, 8.0F);
            changed |= setLoadedParam(RESTIR_SPATIAL_SAMPLES, 1.0F);
            changed |= setLoadedParam(RESTIR_SPATIAL_RADIUS, 32.0F);
            changed |= setLoadedParam(RESTIR_SPATIAL_BIAS_MODE, 1.0F);
         }
         case "high" -> {
            changed |= setLoadedParam(RESTIR_INITIAL_SAMPLES, 8.0F);
            changed |= setLoadedParam(RESTIR_SPATIAL_SAMPLES, 1.0F);
            changed |= setLoadedParam(RESTIR_SPATIAL_RADIUS, 32.0F);
            changed |= setLoadedParam(RESTIR_SPATIAL_BIAS_MODE, 3.0F);
         }
         case "ultra" -> {
            changed |= setLoadedParam(RESTIR_INITIAL_SAMPLES, 16.0F);
            changed |= setLoadedParam(RESTIR_SPATIAL_SAMPLES, 4.0F);
            changed |= setLoadedParam(RESTIR_SPATIAL_RADIUS, 32.0F);
            changed |= setLoadedParam(RESTIR_SPATIAL_BIAS_MODE, 3.0F);
         }
         default -> {
            if (RESTIR_SPATIAL_BIAS_MODE.value != null && Math.abs(RESTIR_SPATIAL_BIAS_MODE.value - 2.0F) < 0.25F) {
               changed |= setLoadedParam(RESTIR_SPATIAL_BIAS_MODE, 1.0F);
            }
         }
      }

      return changed;
   }

   private static <T> boolean setLoadedParam(Parameter<T> parameter, T value) {
      if (Objects.equals(parameter.value, value)) {
         return false;
      }

      parameter.value = value;
      CONFIG_VALUES.put(parameter.configKey, parameter.serializer.apply(value));
      return true;
   }

}
