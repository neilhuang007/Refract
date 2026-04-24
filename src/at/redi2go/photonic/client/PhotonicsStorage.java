package at.redi2go.photonic.client;

import at.redi2go.photonic.client.rendering.world.LightBlock;
import java.util.HashSet;
import java.util.LinkedList;
import java.util.List;
import java.util.Locale;
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
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_TEMPORAL_REUSE = boolParam("debug_enable_direct_temporal_reuse", true);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_SPATIAL_REUSE = boolParam("debug_enable_direct_spatial_reuse", true);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_SHADE_SAMPLES = boolParam("debug_enable_direct_shade_samples", true);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_FINAL_VISIBILITY = boolParam("debug_enable_direct_final_visibility", true);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_VISIBILITY_TRANSMITTANCE = boolParam("debug_enable_direct_visibility_transmittance", true);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_TEMPORAL_ACCUMULATION = boolParam("debug_enable_direct_temporal_accumulation", true);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_HISTORY_FIX = boolParam("debug_enable_direct_history_fix", true);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_HISTORY_CLAMPING = boolParam("debug_enable_direct_history_clamping", true);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_ANTI_FIREFLY = boolParam("debug_enable_direct_anti_firefly", true);
   public static final Parameter<Boolean> DEBUG_ENABLE_DIRECT_ATROUS = boolParam("debug_enable_direct_atrous", true);
   public static final Parameter<String> RESTIR_CHECKERBOARD_MODE = stringParam("restir_checkerboard_mode", "off");
   public static final Parameter<String> RESTIR_LOCAL_LIGHT_SAMPLING_MODE = stringParam("restir_local_light_sampling_mode", "regir_ris");
   public static final Parameter<String> RESTIR_SPATIAL_MIS_MODE = stringParam("restir_spatial_mis_mode", "pairwise");
   public static final Parameter<String> RESTIR_TEMPORAL_REUSE = stringParam("restir_temporal_reuse", "gather_only");
   public static final Parameter<String> RESTIR_TEMPORAL_GATHER_MODE = stringParam("restir_temporal_gather_mode", "fast");
   public static final Parameter<String> RESTIR_SCATTER_BACKUP_MIS_OPTION = stringParam("restir_scatter_backup_mis_option", "balance");
   // Performance tuning — individual per-parameter overrides.
   // A value of -1 means "use shaderpack default" (auto).  Any positive
   // value overrides the shaderpack setting at runtime.
   public static final Parameter<Float> RENDER_SCALE = floatParam("render_scale", -1.0F);
   public static final Parameter<Float> NRD_ATROUS_PASSES = floatParam("nrd_atrous_passes", -1.0F);
   public static final Parameter<Float> RESTIR_INITIAL_SAMPLES = floatParam("restir_initial_samples", -1.0F);
   public static final Parameter<Float> RESTIR_SPATIAL_SAMPLES = floatParam("restir_spatial_samples", -1.0F);
   public static final Parameter<Float> RESTIR_GI_SPATIAL_SAMPLES = floatParam("restir_gi_spatial_samples", -1.0F);
   public static final Parameter<Float> RESTIR_TIME_PARTITIONS = floatParam("restir_time_partitions", 2.0F);
   public static final Parameter<Float> RESTIR_SPATIAL_RADIUS = floatParam("restir_spatial_radius", -1.0F);
   public static final Parameter<Float> RESTIR_SPATIAL_BIAS_MODE = floatParam("restir_spatial_bias_mode", -1.0F);
   public static final Parameter<Boolean> DEBUG_CONSTANT_ALBEDO = boolParam("debug_constant_albedo", false);
   public static final Parameter<Float> DEBUG_VIEW_MODE = floatParam("debug_view_mode", 0.0F);
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
      applyStringSystemPropertyOverride("photonics.restirLocalLightSamplingMode", RESTIR_LOCAL_LIGHT_SAMPLING_MODE);
      applyStringSystemPropertyOverride("photonics.temporalReuse", RESTIR_TEMPORAL_REUSE);
      applyStringSystemPropertyOverride("photonics.temporalGatherMode", RESTIR_TEMPORAL_GATHER_MODE);
      applyStringSystemPropertyOverride("photonics.scatterBackupMisOption", RESTIR_SCATTER_BACKUP_MIS_OPTION);
   }

   private static void applyBooleanSystemPropertyOverride(String key, Parameter<Boolean> parameter) {
      String value = System.getProperty(key);
      if (value == null || value.isBlank()) {
         return;
      }

      parameter.value = Boolean.parseBoolean(value);
   }

   private static void applyStringSystemPropertyOverride(String key, Parameter<String> parameter) {
      String value = System.getProperty(key);
      if (value == null || value.isBlank()) {
         return;
      }

      parameter.value = value;
   }

   public static String normalizeCheckerboardMode(String checkerboardMode) {
      if (checkerboardMode == null) {
         return "off";
      }

      return switch (checkerboardMode.trim().toLowerCase(Locale.ROOT)) {
         case "black" -> "black";
         case "white" -> "white";
         default -> "off";
      };
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

   public static String normalizeRestirLocalLightSamplingMode(String samplingMode) {
      if (samplingMode == null) {
         return "regir_ris";
      }

      return switch (samplingMode.trim().toLowerCase(Locale.ROOT)) {
         case "", "auto", "default", "-1", "2", "regir", "regir_ris", "regir-ris", "regir ris" -> "regir_ris";
         case "0", "uniform" -> "uniform";
         case "1", "power", "power_ris", "power-ris", "power ris" -> "power_ris";
         case "3", "fast_random", "fast-random", "fast random", "basic_random", "basic-random", "basic random" -> "fast_random";
         default -> "regir_ris";
      };
   }

   public static String normalizeRestirSpatialMisMode(String misMode) {
      if (misMode == null) {
         return "pairwise";
      }

      return switch (misMode.trim().toLowerCase(Locale.ROOT)) {
         case "", "2", "pairwise", "pairwise_mis", "pairwise-mis", "pairwise mis" -> "pairwise";
         case "1", "basic", "basic_mis", "basic-mis", "basic mis" -> "basic";
         default -> "pairwise";
      };
   }

   public static String normalizeRestirTemporalReuse(String temporalReuse) {
      if (temporalReuse == null) {
         return "gather_only";
      }

      return switch (temporalReuse.trim().toLowerCase(Locale.ROOT)) {
         case "", "0", "gather", "gather_only", "gather-only", "off", "legacy" -> "gather_only";
         case "1", "scatter", "scatter_only", "scatter-only", "splat", "splat_only", "splat-only", "ownership_only", "ownership-only", "ownership" -> "scatter_only";
         case "2", "scatter_backup", "scatter-backup", "backup", "backup_gather", "backup-gather" -> "scatter_backup";
         case "3", "multi_scatter", "multi-scatter", "multi", "multi_splat", "multi-splat" -> "multi_scatter";
         case "temporal_off", "temporal-off", "disable_temporal", "full_bypass", "canonical" -> "gather_only";
         default -> "gather_only";
      };
   }

   public static String normalizeRestirScatterBackupMisOption(String misOption) {
      if (misOption == null) {
         return "balance";
      }

      return switch (misOption.trim().toLowerCase(Locale.ROOT)) {
         case "", "0", "balance" -> "balance";
         case "1", "pairwise" -> "pairwise";
         default -> "balance";
      };
   }

   public static String normalizeRestirTemporalGatherMode(String gatherMode) {
      if (gatherMode == null) {
         return "fast";
      }

      return switch (gatherMode.trim().toLowerCase(Locale.ROOT)) {
         case "", "0", "fast" -> "fast";
         case "1", "clamped", "clamp" -> "clamped";
         case "2", "robust", "full_robust", "full-robust" -> "robust";
         default -> "fast";
      };
   }

}
