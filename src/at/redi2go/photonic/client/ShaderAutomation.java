package at.redi2go.photonic.client;

import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.util.BufferUtils;
import at.redi2go.photonic.client.rendering.opengl.rendering.renderers.MainRenderer;
import at.redi2go.photonic.client.rendering.world.LightRegistry;
import at.redi2go.photonic.client.rendering.world.WorldRegistry;
import at.redi2go.photonic.client.ShaderAutomationImageUtils;
import at.redi2go.photonic.client.ShaderAutomationValidators;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.atomic.AtomicBoolean;
import javax.imageio.ImageIO;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientLifecycleEvents;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.irisshaders.iris.Iris;
import net.irisshaders.iris.uniforms.SystemTimeUniforms;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.Screen;
import org.joml.Vector3f;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL30;

public final class ShaderAutomation {
   private static final int MAX_REPEAT_DIAGNOSTICS = 5;
   private static final int RTXDI_PACKED_DI_RESERVOIR_M_SHIFT = 18;
   private static final int RTXDI_PACKED_DI_RESERVOIR_MAX_M_UINT = 0x3fff;
   private static final int RTXDI_PACKED_DI_RESERVOIR_DISTANCE_CHANNEL_BITS = 8;
   private static final int RTXDI_PACKED_DI_RESERVOIR_DISTANCE_X_SHIFT = 0;
   private static final int RTXDI_PACKED_DI_RESERVOIR_DISTANCE_Y_SHIFT = 8;
   private static final int RTXDI_PACKED_DI_RESERVOIR_AGE_SHIFT = 16;
   private static final int RTXDI_PACKED_DI_RESERVOIR_MAX_AGE = 0xff;
   private static final int RTXDI_PACKED_DI_RESERVOIR_MAX_DISTANCE = (1 << (RTXDI_PACKED_DI_RESERVOIR_DISTANCE_CHANNEL_BITS - 1)) - 1;
   private static final int RTXDI_TILE_SIZE_IN_PIXELS = 16;
   private static final float REGIR_CELL_SIZE = 32.0f;
   private static final double FIREFLY_LUMA_THRESHOLD = 16.0;
   private static final double SEVERE_FIREFLY_LUMA_THRESHOLD = 64.0;
   private static final double WHOLE_LIGHT_FLASH_DIRECT_DROP_THRESHOLD = 0.35;
   private static final double WHOLE_LIGHT_FLASH_VALID_FRACTION_DROP_THRESHOLD = 0.20;
   private static final double WHOLE_LIGHT_FLASH_LIGHT_COUNT_DROP_THRESHOLD = 0.10;
   private static final double WHOLE_LIGHT_FLASH_BLEND_FACTOR_JUMP_THRESHOLD = 0.05;
   private static final float FP16_SATURATION_CHANNEL_THRESHOLD = 65500.0f;
   private static final AtomicBoolean FATAL_SHADER_FAILURE_SCHEDULED = new AtomicBoolean(false);
   private static final ShaderAutomation INSTANCE = Photonic.automationEnabled() ? new ShaderAutomation() : null;
   private final String worldName;
   private final boolean autoStartWorld;
   private final int startDelayTicks;
   private final int timeoutTicks;
   private final String expectedShaderPack;
   private final String expectedPatchIdPrefix;
   private final Path reportFile;
   private final Path captureDir;
   private final int captureEveryN;
   private final int captureEveryActiveTicks;
   private final int captureTarget;
   private final int minLitCaptures;
   private final int minActiveTicksBeforeSuccess;
   private final int minActiveTicksAfterSignal;
   private final boolean requireDirectSignal;
   private final boolean autoStop;
   private final boolean releaseMouse;
   private final boolean fullscreen;
   private final int motionRepeatSettleTicks;
   private final double maxMotionRepeatDirectDeltaAvg;
   private final double maxMotionRepeatDirectDeltaMax;
   private final double maxMotionRepeatIndirectDeltaAvg;
   private final double maxMotionRepeatIndirectDeltaMax;
   private final double maxDirectTemporalDeltaAvg;
   private final double maxDirectTemporalDeltaMax;
   private final double maxIndirectTemporalDeltaAvg;
   private final double maxIndirectTemporalDeltaMax;
   private final double maxIndirectLinearOverbrightFraction;
   private final double maxIndirectLinearSevereFireflyFraction;
   private final double maxIndirectRawLinearOverbrightFraction;
   private final int stableSceneSettleTicks;
   private final int stableSceneBlendRegionThreshold;
   private final double stableSceneBlendFactorThreshold;
   private final ShaderAutomationWorldController worldController;
   private final ShaderAutomationCameraController cameraController;
   private final ShaderAutomationFrameMetrics metrics = new ShaderAutomationFrameMetrics();
   private int ticksElapsed = 0;
   private int activeTicks = 0;
   private int renderedFrames = 0;
   private long fpsCounterStartTime = 0;
   private int fpsFrameCount = 0;
   private float currentFps = 0;
   private float minFps = Float.MAX_VALUE;
   private float maxFps = 0;
   private float avgFpsSum = 0;
   private int avgFpsCount = 0;
   private int capturesTaken = 0;
   private int litCapturesTaken = 0;
   private int lastCapturedActiveTick = Integer.MIN_VALUE;
   private int firstLightingSignalActiveTick = -1;
   private int latestTracedLightCount = 0;
   private int latestTotalLightCount = 0;
   private int maxTracedLightCount = 0;
   private int maxTotalLightCount = 0;
   private int latestLightBlendRegionCount = 0;
   private int lightSelectionCappedCaptures = 0;
   private int globalLightReloadCaptures = 0;
   private int pendingBurstCaptures = 0;
   private int stableSceneTicks = 0;
   private double latestLightBlendFactor = 0.0;
   private boolean latestLightSelectionCapped = false;
   private boolean latestGlobalLightReload = false;
   private boolean latestWorldBuildWorkPending = false;
   private long latestResetRequestsTotal = 0L;
   private long latestResetRequestsWorldOffset = 0L;
   private long latestResetRequestsTopology = 0L;
   private long latestResetRequestsOther = 0L;
   private long latestBlendFullActivations = 0L;
   private long latestBlendRegionActivations = 0L;
   private long latestBlendCompletions = 0L;
   private long latestFramesGlobalReloadActive = 0L;
   private long latestFramesBlendActive = 0L;
   private long latestFramesPendingWork = 0L;
   private long latestCompileFramesLightWorkNeeded = 0L;
   private long latestCompileFramesLightCompiled = 0L;
   private long latestCompileFramesWorldOffsetChanged = 0L;
   private long latestCompileFramesChunkTopologyChanged = 0L;
   private long latestCompileFramesChunkContentChanged = 0L;
   private long latestCompileFramesTracedLightDirty = 0L;
   private long latestPendingBlendMutationEvents = 0L;
   private int latestMaxPendingBlendRegions = 0;
   private long latestMaxPendingBlendVolume = 0L;
   private long observedResetRequestsTotal = -1L;
   private long observedBlendFullActivations = -1L;
   private long observedBlendRegionActivations = -1L;
   private long observedBlendCompletions = -1L;
   private boolean observedMotionRepeatHistoryActivity = false;
   private int motionRepeatHistoryEpoch = 0;
   private int lastMotionRepeatHistoryInvalidationActiveTick = Integer.MIN_VALUE;
   private int cameraMotionStopActiveTick = -1;
   private boolean raytracerActive = false;
   private boolean directSignalDetected = false;
   private boolean lightingSignalDetected = false;
   private boolean finished = false;
   private boolean fullScreenshotSaved = false;
   private boolean reportInitialized = false;
   private boolean fullscreenApplied = false;
   private boolean recoveringFromScreen = false;
   private String failureReason = "";
   private String shaderPackName = "";
   private boolean expectedShaderPackMatched = false;
   private String patchId = "";
   private int pendingFinalCaptureIndex = Integer.MIN_VALUE;
   private int latestFinalCaptureIndex = Integer.MIN_VALUE;
   private double finalFrameMaxLuma = 0.0;
   private double latestFinalMeanLuma = 0.0;
   private double latestFinalMeanRed = 0.0;
   private double latestFinalMeanGreen = 0.0;
   private double latestFinalMeanBlue = 0.0;
   private boolean finalSignalDetected = false;

   public static void initialize() {
      if (INSTANCE == null) {
         return;
      }

      ClientTickEvents.END_CLIENT_TICK.register(INSTANCE::onEndTick);
      ClientLifecycleEvents.CLIENT_STOPPING.register(INSTANCE::onClientStopping);
   }

   private ShaderAutomation() {
      this.worldName = System.getProperty("photonics.automation.worldName", "");
      this.autoStartWorld = Boolean.parseBoolean(System.getProperty("photonics.automation.autoStartWorld", "false"));
      this.startDelayTicks = Math.max(0, Integer.getInteger("photonics.automation.startDelayTicks", 0));
      this.timeoutTicks = Math.max(1, Integer.getInteger("photonics.automation.timeoutTicks", 1200));
      this.expectedShaderPack = System.getProperty("photonics.automation.expectedShaderPack", "");
      this.expectedPatchIdPrefix = System.getProperty("photonics.automation.expectedPatchIdPrefix", "");
      this.reportFile = Path.of(System.getProperty("photonics.automation.reportFile", "run/automation/shader-report.properties"));
      this.captureDir = Path.of(System.getProperty("photonics.automation.captureDir", "run/automation/captures"));
      this.captureEveryN = Math.max(1, Integer.getInteger("photonics.automation.captureEveryN", 60));
      this.captureEveryActiveTicks = Math.max(0, Integer.getInteger("photonics.automation.captureEveryActiveTicks", 0));
      this.captureTarget = Math.max(1, Integer.getInteger("photonics.automation.captureCount", 1));
      this.minLitCaptures = Math.max(1, Integer.getInteger("photonics.automation.minLitCaptures", Math.max(this.captureTarget, 4)));
      this.minActiveTicksBeforeSuccess = Math.max(this.startDelayTicks, Integer.getInteger("photonics.automation.minActiveTicksBeforeSuccess", Math.max(this.startDelayTicks + 240, this.captureEveryN * Math.max(this.captureTarget, 4) / 2)));
      this.minActiveTicksAfterSignal = Math.max(0, Integer.getInteger("photonics.automation.minActiveTicksAfterSignal", Math.max(this.captureEveryN * 2, 120)));
      this.requireDirectSignal = Boolean.parseBoolean(System.getProperty("photonics.automation.requireDirectSignal", "true"));
      this.autoStop = Boolean.parseBoolean(System.getProperty("photonics.automation.autoStop", "false"));
      this.releaseMouse = Boolean.parseBoolean(System.getProperty("photonics.automation.releaseMouse", "true"));
      this.fullscreen = Boolean.parseBoolean(System.getProperty("photonics.automation.fullscreen", "false"));
      String cameraMotionMode = System.getProperty("photonics.automation.cameraMotion", "none").trim().toLowerCase(Locale.ROOT);
      int cameraMotionStartActiveTick = Math.max(0, Integer.getInteger("photonics.automation.cameraMotionStartActiveTick", this.startDelayTicks + Math.max(this.captureEveryActiveTicks, 30)));
      int cameraMotionPeriodTicks = Math.max(0, Integer.getInteger("photonics.automation.cameraMotionPeriodTicks", 120));
      float cameraYawAmplitudeDegrees = Math.max(0.0f, Float.parseFloat(System.getProperty("photonics.automation.cameraYawAmplitudeDegrees", "0.0")));
      float cameraPitchAmplitudeDegrees = Math.max(0.0f, Float.parseFloat(System.getProperty("photonics.automation.cameraPitchAmplitudeDegrees", "0.0")));
      this.motionRepeatSettleTicks = Math.max(this.captureEveryActiveTicks * 2, 60);
      this.maxMotionRepeatDirectDeltaAvg = Double.parseDouble(System.getProperty("photonics.automation.maxMotionRepeatDirectDeltaAvg", "-1"));
      this.maxMotionRepeatDirectDeltaMax = Double.parseDouble(System.getProperty("photonics.automation.maxMotionRepeatDirectDeltaMax", "-1"));
      this.maxMotionRepeatIndirectDeltaAvg = Double.parseDouble(System.getProperty("photonics.automation.maxMotionRepeatIndirectDeltaAvg", "-1"));
      this.maxMotionRepeatIndirectDeltaMax = Double.parseDouble(System.getProperty("photonics.automation.maxMotionRepeatIndirectDeltaMax", "-1"));
      this.maxDirectTemporalDeltaAvg = Double.parseDouble(System.getProperty("photonics.automation.maxDirectTemporalDeltaAvg", "-1"));
      this.maxDirectTemporalDeltaMax = Double.parseDouble(System.getProperty("photonics.automation.maxDirectTemporalDeltaMax", "-1"));
      this.maxIndirectTemporalDeltaAvg = Double.parseDouble(System.getProperty("photonics.automation.maxIndirectTemporalDeltaAvg", "-1"));
      this.maxIndirectTemporalDeltaMax = Double.parseDouble(System.getProperty("photonics.automation.maxIndirectTemporalDeltaMax", "-1"));
      this.maxIndirectLinearOverbrightFraction = Double.parseDouble(System.getProperty("photonics.automation.maxIndirectLinearOverbrightFraction", "-1"));
      this.maxIndirectLinearSevereFireflyFraction = Double.parseDouble(System.getProperty("photonics.automation.maxIndirectLinearSevereFireflyFraction", "-1"));
      this.maxIndirectRawLinearOverbrightFraction = Double.parseDouble(System.getProperty("photonics.automation.maxIndirectRawLinearOverbrightFraction", "-1"));
      int worldPrepActiveTick = Math.max(1, Integer.getInteger("photonics.automation.worldPrepActiveTick", 1));
      this.stableSceneSettleTicks = Math.max(0, Integer.getInteger("photonics.automation.stableSceneSettleTicks", Math.max(this.captureEveryActiveTicks * 2, 120)));
      this.stableSceneBlendRegionThreshold = Math.max(0, Integer.getInteger("photonics.automation.stableSceneBlendRegionThreshold", 0));
      this.stableSceneBlendFactorThreshold = Math.max(0.0, Double.parseDouble(System.getProperty("photonics.automation.stableSceneBlendFactorThreshold", "0.0")));
      long[] timeOfDaySequence = ShaderAutomationValidators.parseLongSequence(System.getProperty("photonics.automation.timeOfDaySequence", ""));
      int timeOfDayStartActiveTick = Math.max(0, Integer.getInteger("photonics.automation.timeOfDayStartActiveTick", cameraMotionStartActiveTick + cameraMotionPeriodTicks));
      int timeOfDayStepTicks = Math.max(1, Integer.getInteger("photonics.automation.timeOfDayStepTicks", Math.max(this.captureEveryActiveTicks, 30)));
      int blockToggleStartActiveTick = Math.max(0, Integer.getInteger("photonics.automation.blockToggleStartActiveTick", timeOfDayStartActiveTick + timeOfDayStepTicks * Math.max(timeOfDaySequence.length, 1)));
      int blockTogglePeriodTicks = Math.max(1, Integer.getInteger("photonics.automation.blockTogglePeriodTicks", Math.max(this.captureEveryActiveTicks, 30)));
      int blockToggleCount = Math.max(0, Integer.getInteger("photonics.automation.blockToggleCount", 0));
      this.worldController = new ShaderAutomationWorldController(
         timeOfDaySequence,
         timeOfDayStartActiveTick,
         timeOfDayStepTicks,
         blockToggleStartActiveTick,
         blockTogglePeriodTicks,
         blockToggleCount,
         worldPrepActiveTick,
         this::queueBurstCaptures
      );
      this.cameraController = new ShaderAutomationCameraController(
         cameraMotionMode,
         cameraMotionStartActiveTick,
         cameraMotionPeriodTicks,
         cameraYawAmplitudeDegrees,
         cameraPitchAmplitudeDegrees,
         this::stableSceneSatisfied
      );
   }

   public static void afterPhotonicsRender() {
      if (INSTANCE != null) {
         INSTANCE.captureFrame();
      }
   }

   public static void afterFinalComposite() {
      if (INSTANCE != null) {
         INSTANCE.captureFinalFrame();
      }
   }

   public static boolean suppressWorldMutationIngress() {
      return INSTANCE != null && INSTANCE.shouldSuppressWorldMutationIngress();
   }



   static int decodePackedReservoirM(float packedVisibilityAndM) {
      int packed = Float.floatToRawIntBits(packedVisibilityAndM);
      return (packed >>> RTXDI_PACKED_DI_RESERVOIR_M_SHIFT) & RTXDI_PACKED_DI_RESERVOIR_MAX_M_UINT;
   }

   private static FireflyStats computeFireflyStats(TextureObject texture) {
      if (texture == null) {
         return FireflyStats.EMPTY;
      }

      texture.updatePerFrame();
      return computeFireflyStats(texture.downloadFloatData());
   }

   static FireflyStats computeFireflyStats(float[] pixels) {
      if (pixels == null || pixels.length < 4) {
         return FireflyStats.EMPTY;
      }

      int pixelCount = pixels.length / 4;
      int fireflyPixels = 0;
      int severeFireflyPixels = 0;
      int saturatedPixels = 0;
      int nonFinitePixels = 0;
      double totalLuma = 0.0;
      double fireflyLuma = 0.0;
      for (int i = 0; i < pixelCount; i++) {
         int base = i * 4;
         float r = pixels[base];
         float g = pixels[base + 1];
         float b = pixels[base + 2];
         if (!Float.isFinite(r) || !Float.isFinite(g) || !Float.isFinite(b)) {
            nonFinitePixels++;
            continue;
         }

         double clampedR = Math.max(r, 0.0f);
         double clampedG = Math.max(g, 0.0f);
         double clampedB = Math.max(b, 0.0f);
         double luma = 0.2126 * clampedR + 0.7152 * clampedG + 0.0722 * clampedB;
         totalLuma += luma;
         if (luma >= FIREFLY_LUMA_THRESHOLD) {
            fireflyPixels++;
            fireflyLuma += luma;
         }
         if (luma >= SEVERE_FIREFLY_LUMA_THRESHOLD) {
            severeFireflyPixels++;
         }
         if (r >= FP16_SATURATION_CHANNEL_THRESHOLD
            || g >= FP16_SATURATION_CHANNEL_THRESHOLD
            || b >= FP16_SATURATION_CHANNEL_THRESHOLD) {
            saturatedPixels++;
         }
      }

      double pixelCountDouble = Math.max(1, pixelCount);
      return new FireflyStats(
         fireflyPixels / pixelCountDouble,
         severeFireflyPixels / pixelCountDouble,
         totalLuma <= 1.0e-12 ? 0.0 : fireflyLuma / totalLuma,
         saturatedPixels / pixelCountDouble,
         nonFinitePixels / pixelCountDouble
      );
   }

   private static ReservoirSampleDebugStats computeReservoirSampleDebugStats(TextureObject texture) {
      if (texture == null) {
         return ReservoirSampleDebugStats.EMPTY;
      }

      texture.updatePerFrame();
      float[] pixels = texture.downloadFloatData();
      if (pixels == null || pixels.length < 4) {
         return ReservoirSampleDebugStats.EMPTY;
      }

      int pixelCount = pixels.length / 4;
      int nonZeroCount = 0;
      double uSum = 0.0;
      double vSum = 0.0;
      for (int i = 0; i < pixelCount; i++) {
         int packedUv = Float.floatToRawIntBits(pixels[i * 4]);
         if (packedUv == 0) {
            continue;
         }

         nonZeroCount++;
         uSum += (packedUv & 0xffff) / 65535.0;
         vSum += ((packedUv >>> 16) & 0xffff) / 65535.0;
      }

      double denominator = Math.max(1, nonZeroCount);
      return new ReservoirSampleDebugStats(
         nonZeroCount / (double)Math.max(1, pixelCount),
         uSum / denominator,
         vSum / denominator
      );
   }

   private static ReservoirMetaDebugStats computeReservoirMetaDebugStats(TextureObject texture) {
      if (texture == null) {
         return ReservoirMetaDebugStats.EMPTY;
      }

      texture.updatePerFrame();
      float[] pixels = texture.downloadFloatData();
      if (pixels == null || pixels.length < 4) {
         return ReservoirMetaDebugStats.EMPTY;
      }

      int pixelCount = pixels.length / 4;
      int nonZeroCount = 0;
      double ageSum = 0.0;
      double absDistanceXSum = 0.0;
      double absDistanceYSum = 0.0;
      for (int i = 0; i < pixelCount; i++) {
         int packedMeta = Float.floatToRawIntBits(pixels[i * 4 + 3]);
         if (packedMeta == 0) {
            continue;
         }

         nonZeroCount++;
         ageSum += decodePackedReservoirAge(packedMeta);
         absDistanceXSum += Math.abs(decodePackedReservoirDistance(packedMeta, RTXDI_PACKED_DI_RESERVOIR_DISTANCE_X_SHIFT));
         absDistanceYSum += Math.abs(decodePackedReservoirDistance(packedMeta, RTXDI_PACKED_DI_RESERVOIR_DISTANCE_Y_SHIFT));
      }

      double denominator = Math.max(1, nonZeroCount);
      return new ReservoirMetaDebugStats(
         nonZeroCount / (double)Math.max(1, pixelCount),
         ageSum / denominator,
         absDistanceXSum / denominator,
         absDistanceYSum / denominator
      );
   }

   private static int decodePackedReservoirAge(int packedMeta) {
      return (packedMeta >>> RTXDI_PACKED_DI_RESERVOIR_AGE_SHIFT) & RTXDI_PACKED_DI_RESERVOIR_MAX_AGE;
   }

   private static int decodePackedReservoirDistance(int packedMeta, int shift) {
      int leftShift = 32 - shift - RTXDI_PACKED_DI_RESERVOIR_DISTANCE_CHANNEL_BITS;
      int signExtendShift = 32 - RTXDI_PACKED_DI_RESERVOIR_DISTANCE_CHANNEL_BITS;
      return (packedMeta << leftShift) >> signExtendShift;
   }

   private static PositionDebugStats computePositionDebugStats(TextureObject texture) {
      if (texture == null) {
         return PositionDebugStats.EMPTY;
      }

      texture.updatePerFrame();
      float[] pixels = texture.downloadFloatData();
      if (pixels == null || pixels.length < 4) {
         return PositionDebugStats.EMPTY;
      }

      int pixelCount = pixels.length / 4;
      double sumX = 0.0;
      double sumY = 0.0;
      double sumZ = 0.0;
      double minX = Double.POSITIVE_INFINITY;
      double minY = Double.POSITIVE_INFINITY;
      double minZ = Double.POSITIVE_INFINITY;
      double maxX = Double.NEGATIVE_INFINITY;
      double maxY = Double.NEGATIVE_INFINITY;
      double maxZ = Double.NEGATIVE_INFINITY;
      for (int i = 0; i < pixelCount; i++) {
         int base = i * 4;
         float x = pixels[base];
         float y = pixels[base + 1];
         float z = pixels[base + 2];
         sumX += x;
         sumY += y;
         sumZ += z;
         minX = Math.min(minX, x);
         minY = Math.min(minY, y);
         minZ = Math.min(minZ, z);
         maxX = Math.max(maxX, x);
         maxY = Math.max(maxY, y);
         maxZ = Math.max(maxZ, z);
      }

      return new PositionDebugStats(
         sumX / pixelCount,
         sumY / pixelCount,
         sumZ / pixelCount,
         minX,
         minY,
         minZ,
         maxX,
         maxY,
         maxZ
      );
   }

   private static RowJumpStats computeHdrLumaRowJumpStats(TextureObject texture) {
      if (texture == null) {
         return RowJumpStats.EMPTY;
      }

      texture.updatePerFrame();
      int[] dimensions = texture.getTextureDimensions();
      if (dimensions.length < 2 || dimensions[0] <= 0 || dimensions[1] <= 1) {
         return RowJumpStats.EMPTY;
      }

      return computeHdrLumaRowJumpStats(texture.downloadFloatData(), dimensions[0], dimensions[1]);
   }

   private static RowJumpStats computeHdrLumaRowJumpStats(float[] pixels, int width, int height) {
      if (pixels == null || width <= 0 || height <= 1) {
         return RowJumpStats.EMPTY;
      }

      double[] rowMeans = new double[height];
      for (int y = 0; y < height; y++) {
         double lumaSum = 0.0;
         int validCount = 0;
         for (int x = 0; x < width; x++) {
            int base = (x + y * width) * 4;
            float r = pixels[base];
            float g = pixels[base + 1];
            float b = pixels[base + 2];
            if (!Float.isFinite(r) || !Float.isFinite(g) || !Float.isFinite(b)) {
               continue;
            }

            lumaSum += 0.2126 * Math.max(r, 0.0f) + 0.7152 * Math.max(g, 0.0f) + 0.0722 * Math.max(b, 0.0f);
            validCount++;
         }
         rowMeans[y] = validCount == 0 ? 0.0 : lumaSum / validCount;
      }

      return computeRowJumpStats(rowMeans);
   }

   private static ReservoirRowJumpStats computeReservoirRowJumpStats(TextureObject texture) {
      if (texture == null) {
         return ReservoirRowJumpStats.EMPTY;
      }

      texture.updatePerFrame();
      int[] dimensions = texture.getTextureDimensions();
      if (dimensions.length < 2 || dimensions[0] <= 0 || dimensions[1] <= 1) {
         return ReservoirRowJumpStats.EMPTY;
      }

      float[] pixels = texture.downloadFloatData();
      if (pixels == null) {
         return ReservoirRowJumpStats.EMPTY;
      }

      int width = dimensions[0];
      int height = dimensions[1];
      double[] validFractionRows = new double[height];
      double[] weightRows = new double[height];
      double[] targetPdfRows = new double[height];
      double[] weightTimesTargetPdfRows = new double[height];
      double[] reservoirMRows = new double[height];
      for (int y = 0; y < height; y++) {
         int strictValidCount = 0;
         double weightSum = 0.0;
         double targetPdfSum = 0.0;
         double weightTimesTargetPdfSum = 0.0;
         double reservoirMSum = 0.0;
         for (int x = 0; x < width; x++) {
            int base = (x + y * width) * 4;
            int lightData = Float.floatToRawIntBits(pixels[base]);
            float weight = pixels[base + 1];
            float targetPdf = pixels[base + 2];
            int reservoirM = decodePackedReservoirM(pixels[base + 3]);
            if (lightData != 0 && weight > 0.0f && reservoirM > 0) {
               strictValidCount++;
            }
            if (Float.isFinite(weight)) {
               weightSum += Math.max(weight, 0.0f);
            }
            if (Float.isFinite(targetPdf)) {
               targetPdfSum += Math.max(targetPdf, 0.0f);
            }
            if (Float.isFinite(weight) && Float.isFinite(targetPdf)) {
               weightTimesTargetPdfSum += Math.max(weight, 0.0f) * Math.max(targetPdf, 0.0f);
            }
            reservoirMSum += reservoirM;
         }
         validFractionRows[y] = strictValidCount / (double) Math.max(1, width);
         weightRows[y] = weightSum / Math.max(1, width);
         targetPdfRows[y] = targetPdfSum / Math.max(1, width);
         weightTimesTargetPdfRows[y] = weightTimesTargetPdfSum / Math.max(1, width);
         reservoirMRows[y] = reservoirMSum / Math.max(1, width);
      }

      return new ReservoirRowJumpStats(
         computeRowJumpStats(validFractionRows),
         computeRowJumpStats(weightRows),
         computeRowJumpStats(targetPdfRows),
         computeRowJumpStats(weightTimesTargetPdfRows),
         computeRowJumpStats(reservoirMRows)
      );
   }

   private static RowJumpStats computeStageLinearDepthRowJumpStats(TextureObject texture, Vector3f cameraPosition) {
      if (texture == null || cameraPosition == null) {
         return RowJumpStats.EMPTY;
      }

      texture.updatePerFrame();
      int[] dimensions = texture.getTextureDimensions();
      if (dimensions.length < 2 || dimensions[0] <= 0 || dimensions[1] <= 1) {
         return RowJumpStats.EMPTY;
      }

      float[] pixels = texture.downloadFloatData();
      if (pixels == null) {
         return RowJumpStats.EMPTY;
      }

      int width = dimensions[0];
      int height = dimensions[1];
      double[] depthRows = new double[height];
      for (int y = 0; y < height; y++) {
         double depthSum = 0.0;
         int validCount = 0;
         for (int x = 0; x < width; x++) {
            int base = (x + y * width) * 4;
            float px = pixels[base];
            float py = pixels[base + 1];
            float pz = pixels[base + 2];
            if (!Float.isFinite(px) || !Float.isFinite(py) || !Float.isFinite(pz)) {
               continue;
            }
            if (Math.abs(px) < 1.0e-6f && Math.abs(py) < 1.0e-6f && Math.abs(pz) < 1.0e-6f) {
               continue;
            }

            double dx = px - cameraPosition.x;
            double dy = py - cameraPosition.y;
            double dz = pz - cameraPosition.z;
            depthSum += Math.sqrt(dx * dx + dy * dy + dz * dz);
            validCount++;
         }
         depthRows[y] = validCount == 0 ? 0.0 : depthSum / validCount;
      }

      return computeRowJumpStats(depthRows);
   }

   private static RowJumpStats computeReGIRCellZRowJumpStats(
      TextureObject texture,
      Vector3f gridCenter,
      int gridResolution,
      float cellSize
   ) {
      if (texture == null || gridCenter == null || gridResolution <= 0 || cellSize <= 0.0f) {
         return RowJumpStats.EMPTY;
      }

      texture.updatePerFrame();
      int[] dimensions = texture.getTextureDimensions();
      if (dimensions.length < 2 || dimensions[0] <= 0 || dimensions[1] <= 1) {
         return RowJumpStats.EMPTY;
      }

      float[] pixels = texture.downloadFloatData();
      if (pixels == null) {
         return RowJumpStats.EMPTY;
      }

      float gridOriginZ = gridCenter.z - gridResolution * cellSize * 0.5f;
      double[] cellZRows = new double[dimensions[1]];
      for (int y = 0; y < dimensions[1]; y++) {
         double cellZSum = 0.0;
         int validCount = 0;
         for (int x = 0; x < dimensions[0]; x++) {
            int base = (x + y * dimensions[0]) * 4;
            float pz = pixels[base + 2];
            if (!Float.isFinite(pz) || Math.abs(pz) < 1.0e-6f) {
               continue;
            }

            float cellZ = (float) Math.floor((pz - gridOriginZ) / cellSize);
            cellZSum += cellZ;
            validCount++;
         }
         cellZRows[y] = validCount == 0 ? 0.0 : cellZSum / validCount;
      }

      return computeRowJumpStats(cellZRows);
   }

   private static ReGIRCoverageRowJumpStats computeReGIRCoverageRowJumpStats(
      TextureObject texture,
      Vector3f gridCenter,
      int gridResolution,
      float cellSize,
      float samplingJitter
   ) {
      if (texture == null || gridCenter == null || gridResolution <= 0 || cellSize <= 0.0f) {
         return ReGIRCoverageRowJumpStats.EMPTY;
      }

      texture.updatePerFrame();
      int[] dimensions = texture.getTextureDimensions();
      if (dimensions.length < 2 || dimensions[0] <= 0 || dimensions[1] <= 1) {
         return ReGIRCoverageRowJumpStats.EMPTY;
      }

      float[] pixels = texture.downloadFloatData();
      if (pixels == null) {
         return ReGIRCoverageRowJumpStats.EMPTY;
      }

      float nominalHalfExtent = gridResolution * cellSize * 0.5f;
      float jitterMargin = samplingJitter * cellSize * 0.5f;
      double[] nominalCoverageRows = new double[dimensions[1]];
      double[] expandedCoverageRows = new double[dimensions[1]];

      for (int y = 0; y < dimensions[1]; y++) {
         int nominalInsideCount = 0;
         int expandedInsideCount = 0;
         int validCount = 0;
         for (int x = 0; x < dimensions[0]; x++) {
            int base = (x + y * dimensions[0]) * 4;
            float px = pixels[base];
            float py = pixels[base + 1];
            float pz = pixels[base + 2];
            if (!Float.isFinite(px) || !Float.isFinite(py) || !Float.isFinite(pz)) {
               continue;
            }
            if (Math.abs(px) < 1.0e-6f && Math.abs(py) < 1.0e-6f && Math.abs(pz) < 1.0e-6f) {
               continue;
            }

            validCount++;
            if (isInsideAxisAlignedCube(px, py, pz, gridCenter, nominalHalfExtent)) {
               nominalInsideCount++;
            }
            if (isInsideAxisAlignedCube(px, py, pz, gridCenter, nominalHalfExtent + jitterMargin)) {
               expandedInsideCount++;
            }
         }

         nominalCoverageRows[y] = validCount == 0 ? 0.0 : nominalInsideCount / (double) validCount;
         expandedCoverageRows[y] = validCount == 0 ? 0.0 : expandedInsideCount / (double) validCount;
      }

      return new ReGIRCoverageRowJumpStats(
         computeRowJumpStats(nominalCoverageRows),
         computeRowJumpStats(expandedCoverageRows)
      );
   }

   private static boolean isInsideAxisAlignedCube(float x, float y, float z, Vector3f center, float halfExtent) {
      return x >= center.x - halfExtent && x < center.x + halfExtent
         && y >= center.y - halfExtent && y < center.y + halfExtent
         && z >= center.z - halfExtent && z < center.z + halfExtent;
   }

   static RowJumpStats computeRowJumpStats(double[] rowMeans) {
      if (rowMeans == null || rowMeans.length <= 1) {
         return RowJumpStats.EMPTY;
      }

      int bestRow = 0;
      double bestDelta = 0.0;
      double bestPrevious = rowMeans[0];
      double bestNext = rowMeans[1];
      for (int row = 0; row < rowMeans.length - 1; row++) {
         double previous = rowMeans[row];
         double next = rowMeans[row + 1];
         double delta = Math.abs(next - previous);
         if (delta > bestDelta) {
            bestRow = row;
            bestDelta = delta;
            bestPrevious = previous;
            bestNext = next;
         }
      }

      return new RowJumpStats(bestRow, rowMeans.length - 1 - bestRow, bestDelta, bestPrevious, bestNext);
   }


   private void onEndTick(MinecraftClient client) {
      if (this.finished) {
         return;
      }

      this.ticksElapsed++;
      this.refreshRuntimeState();
      if (!reportInitialized) {
         this.reportInitialized = true;
         this.writeReport(false);
      }

      if (client.world != null) {
         this.releaseAutomationMouse(client);
         this.applyFullscreen(client);
         this.ensureGameplayScreen(client);
      }

      if (client.world != null && this.raytracerActive) {
         this.activeTicks++;
         if (this.cameraController.isEnabled()) {
            this.cameraController.applyCameraMotion(this.activeTicks, client);
         }
         this.worldController.applyWorldAutomation(this.activeTicks, client);
         this.updatePostMotionWindow();
      }
      if (this.ticksElapsed >= this.timeoutTicks) {
         String reason = this.buildSuccess()
            ? ""
            : "Automation timed out after " + this.ticksElapsed + " ticks: " + this.defaultFailureReason();
         this.finish(reason);
      }
   }

   private void onClientStopping(MinecraftClient client) {
      if (this.finished) {
         return;
      }

      String fatalShaderFailureMessage = this.readFatalShaderFailureMessage();
      if (fatalShaderFailureMessage != null) {
         Photonic.warn("[Automation] {}", fatalShaderFailureMessage);
         this.finish(fatalShaderFailureMessage);
         return;
      }

      this.finish(this.buildSuccess() ? "" : "Client stopped before automation completed");
   }

   private void captureFrame() {
      if (this.finished) {
         return;
      }

      MinecraftClient client = MinecraftClient.getInstance();
      if (client.world == null || Raytracer.INSTANCE == null || Raytracer.isDisabled()) {
         return;
      }

      this.refreshRuntimeState();
      if (this.activeTicks < this.startDelayTicks) {
         return;
      }

      this.renderedFrames++;
      this.recordFps();
      if (this.buildSuccess()) {
         this.finish("");
         return;
      }
      if (!this.shouldCaptureThisFrame()) {
         return;
      }

      try {
         MainRenderer mainRenderer = Raytracer.INSTANCE.getMainRenderer();
         Map<String, TextureObject> textures = mainRenderer.getAutomationTextures();
         if (textures.isEmpty()) {
            this.finish("Renderer exposed no automation textures for shader automation");
            return;
         }

         Files.createDirectories(this.captureDir);
         int captureIndex = this.capturesTaken + 1;
         TextureObject directTexture = textures.get("direct");
         TextureObject directReservoirTexture = textures.get("direct_reservoir");
         TextureObject directResolvedReservoirTexture = textures.get("direct_reservoir_resolved");
         TextureObject directSoftTexture = textures.get("direct_soft");
         TextureObject directSoftPreviousTexture = textures.get("direct_soft_prev");
         TextureObject directNoisyTexture = textures.get("direct_noisy");
         TextureObject directResponsiveTexture = textures.get("direct_responsive");
         TextureObject directSlowTexture = textures.get("direct_slow");
         TextureObject directFastTexture = textures.get("direct_fast");
         TextureObject directClampedSlowTexture = textures.get("direct_clamped_slow");
         TextureObject directClampedFastTexture = textures.get("direct_clamped_fast");
         TextureObject directAntiFireflyTexture = textures.get("direct_anti_firefly");
         TextureObject directDenoisedTexture = textures.get("direct_denoised");
         TextureObject directAtrousTexture = textures.get("direct_atrous");
         TextureObject directRawTexture = textures.get("direct_raw");
         TextureObject prepassDiffTexture = textures.get("prepass_diff");
         TextureObject tilesTexture = textures.get("tiles");
         TextureObject specDenoisedTexture = textures.get("spec_denoised");
         TextureObject specRawTexture = textures.get("spec_raw");
         TextureObject directInitialDebugTexture = textures.get("direct_initial_debug");
         TextureObject lightingTexture = textures.get("lighting");
         TextureObject stageAlbedoTexture = textures.get("stage_albedo");
         TextureObject stageLightingTexture = textures.get("stage_lighting");
         TextureObject stageMappedNormalTexture = textures.get("stage_mapped_normal");
         TextureObject stageMaterialTexture = textures.get("stage_material");
         TextureObject stageNormalTexture = textures.get("stage_normal");
         TextureObject stagePositionTexture = textures.get("stage_position");
         TextureObject stageIndirectTexture = textures.get("stage_indirect");
         TextureObject handheldTexture = textures.get("handheld");
         TextureObject indirectRawTexture = textures.get("indirect_raw");
         TextureObject indirectTexture = textures.get("indirect");
         BufferedImage directImage = this.captureTexture("direct", directTexture, captureIndex);
         this.captureTexture("direct_reservoir", directReservoirTexture, captureIndex);
         this.captureTexture("direct_reservoir_resolved", directResolvedReservoirTexture, captureIndex);
         BufferedImage directSoftImage = this.captureTexture("direct_soft", directSoftTexture, captureIndex);
         this.captureTexture("direct_soft_prev", directSoftPreviousTexture, captureIndex);
         this.captureTexture("direct_noisy", directNoisyTexture, captureIndex);
         this.captureTexture("direct_responsive", directResponsiveTexture, captureIndex);
         this.captureTexture("direct_slow", directSlowTexture, captureIndex);
         this.captureTexture("direct_fast", directFastTexture, captureIndex);
         this.captureTexture("direct_clamped_slow", directClampedSlowTexture, captureIndex);
         this.captureTexture("direct_clamped_fast", directClampedFastTexture, captureIndex);
         this.captureTexture("direct_anti_firefly", directAntiFireflyTexture, captureIndex);
         BufferedImage directDenoisedImage = this.captureTexture("direct_denoised", directDenoisedTexture, captureIndex);
         BufferedImage directAtrousImage = this.captureTexture("direct_atrous", directAtrousTexture, captureIndex);
         BufferedImage directValidationImage = directAtrousImage != null ? directAtrousImage : directDenoisedImage;
         BufferedImage directTemporalAndRepeatImage = directValidationImage != null ? directValidationImage : directImage;
         BufferedImage directRawImage = this.captureTexture("direct_raw", directRawTexture, captureIndex);
         this.captureTexture("prepass_diff", prepassDiffTexture, captureIndex);
         this.captureTexture("tiles", tilesTexture, captureIndex);
         this.captureTexture("spec_denoised", specDenoisedTexture, captureIndex);
         this.captureTexture("spec_raw", specRawTexture, captureIndex);
         this.captureTexture("direct_initial_debug", directInitialDebugTexture, captureIndex);
         BufferedImage lightingImage = this.captureTexture("lighting", lightingTexture, captureIndex);
         this.captureTexture("stage_albedo", stageAlbedoTexture, captureIndex);
         BufferedImage stageLightingImage = this.captureTexture("stage_lighting", stageLightingTexture, captureIndex);
         this.captureTexture("stage_mapped_normal", stageMappedNormalTexture, captureIndex);
         this.captureTexture("stage_material", stageMaterialTexture, captureIndex);
         this.captureTexture("stage_normal", stageNormalTexture, captureIndex);
         this.captureTexture("stage_position", stagePositionTexture, captureIndex);
         BufferedImage stageIndirectImage = this.captureTexture("stage_indirect", stageIndirectTexture, captureIndex);
         BufferedImage handheldImage = this.captureTexture("handheld", handheldTexture, captureIndex);
         BufferedImage indirectRawImage = this.captureTexture("indirect_raw", indirectRawTexture, captureIndex);
         BufferedImage indirectImage = this.captureTexture("indirect", indirectTexture, captureIndex);
         TextureObject.TextureStats specRawLinearStats =
            specRawTexture == null ? TextureObject.TextureStats.EMPTY : specRawTexture.readStats();
         TextureObject.TextureStats specDenoisedLinearStats =
            specDenoisedTexture == null ? TextureObject.TextureStats.EMPTY : specDenoisedTexture.readStats();
         TextureObject.TextureStats directRawLinearStats =
            directRawTexture == null ? TextureObject.TextureStats.EMPTY : directRawTexture.readStats();
         TextureObject.TextureStats directDenoisedLinearStats =
            directDenoisedTexture == null ? TextureObject.TextureStats.EMPTY : directDenoisedTexture.readStats();
         TextureObject.TextureStats directSoftLinearStats =
            directSoftTexture == null ? TextureObject.TextureStats.EMPTY : directSoftTexture.readStats();
         TextureObject.TextureStats directSoftPreviousLinearStats =
            directSoftPreviousTexture == null ? TextureObject.TextureStats.EMPTY : directSoftPreviousTexture.readStats();
         TextureObject.TextureStats indirectRawLinearStats =
            indirectRawTexture == null ? TextureObject.TextureStats.EMPTY : indirectRawTexture.readStats();
         TextureObject.TextureStats indirectLinearStats =
            indirectTexture == null ? TextureObject.TextureStats.EMPTY : indirectTexture.readStats();
         TextureObject.TextureStats stageIndirectLinearStats =
            stageIndirectTexture == null ? TextureObject.TextureStats.EMPTY : stageIndirectTexture.readStats();
         FireflyStats directRawFireflyStats = computeFireflyStats(directRawTexture);
         FireflyStats directDenoisedFireflyStats = computeFireflyStats(directDenoisedTexture);
         FireflyStats specRawFireflyStats = computeFireflyStats(specRawTexture);
         FireflyStats specDenoisedFireflyStats = computeFireflyStats(specDenoisedTexture);
         FireflyStats indirectRawFireflyStats = computeFireflyStats(indirectRawTexture);
         FireflyStats indirectFireflyStats = computeFireflyStats(indirectTexture);
         WorldRegistry worldRegistry = Raytracer.INSTANCE.getWorldRegistry();
         LightRegistry lightRegistry = worldRegistry.getLightRegistry();
         ShaderAutomationGpuDebugExtractor.ReservoirDebugStats proposalReservoirStats = ShaderAutomationGpuDebugExtractor.computeReservoirDebugStats(directReservoirTexture);
         ShaderAutomationGpuDebugExtractor.InitialSamplingDebugStats initialSamplingDebugStats = ShaderAutomationGpuDebugExtractor.computeInitialSamplingDebugStats(directInitialDebugTexture);
         ShaderAutomationGpuDebugExtractor.ReservoirDebugStats resolvedReservoirStats = ShaderAutomationGpuDebugExtractor.computeReservoirDebugStats(directResolvedReservoirTexture);
         PositionDebugStats stagePositionStats = computePositionDebugStats(stagePositionTexture);
         RowJumpStats directRawRowJump = computeHdrLumaRowJumpStats(directRawTexture);
         ReservoirRowJumpStats proposalReservoirRowJumps = computeReservoirRowJumpStats(directReservoirTexture);
         ReservoirRowJumpStats resolvedReservoirRowJumps = computeReservoirRowJumpStats(directResolvedReservoirTexture);
         RowJumpStats stageLinearDepthRowJump = computeStageLinearDepthRowJumpStats(stagePositionTexture, lightRegistry.getRegirGridCenter());
         RowJumpStats regirCellZRowJump = computeReGIRCellZRowJumpStats(
            stagePositionTexture,
            lightRegistry.getRegirGridCenter(),
            lightRegistry.getRegirGridResolution(),
            32.0f
         );
         ReGIRCoverageRowJumpStats regirCoverageRowJumps = computeReGIRCoverageRowJumpStats(
            stagePositionTexture,
            lightRegistry.getRegirGridCenter(),
            lightRegistry.getRegirGridResolution(),
            32.0f,
            lightRegistry.getRegirLookupJitter()
         );
         int frameIndex = SystemTimeUniforms.COUNTER.getAsInt();
         ShaderAutomationGpuDebugExtractor.ReGIRPixelCorrelationStats regirPixelCorrelationStats = ShaderAutomationGpuDebugExtractor.computeReGIRPixelCorrelationStats(
            directResolvedReservoirTexture,
            stagePositionTexture,
            lightRegistry,
            frameIndex
         );
         double[] directStats = ShaderAutomationImageUtils.computeImageStats(directImage);
         double[] directSoftStats = ShaderAutomationImageUtils.computeImageStats(directSoftImage);
         double[] directDenoisedStats = ShaderAutomationImageUtils.computeImageStats(directDenoisedImage);
         double[] directRawStats = ShaderAutomationImageUtils.computeImageStats(directRawImage);
         double[] lightingStats = ShaderAutomationImageUtils.computeImageStats(lightingImage);
         double[] stageLightingStats = ShaderAutomationImageUtils.computeImageStats(stageLightingImage);
         double[] stageIndirectStats = ShaderAutomationImageUtils.computeImageStats(stageIndirectImage);
         double[] handheldStats = ShaderAutomationImageUtils.computeImageStats(handheldImage);
         double[] indirectRawStats = ShaderAutomationImageUtils.computeImageStats(indirectRawImage);
         double[] indirectStats = ShaderAutomationImageUtils.computeImageStats(indirectImage);
         double[] directAlphaStats = ShaderAutomationImageUtils.computeImageAlphaStats(directImage);
         double[] stageIndirectAlphaStats = ShaderAutomationImageUtils.computeImageAlphaStats(stageIndirectImage);
         double[] indirectAlphaStats = ShaderAutomationImageUtils.computeImageAlphaStats(indirectImage);
         double directLuma = directStats[0];
         double directSoftLuma = directSoftStats[0];
         double directDenoisedLuma = directDenoisedStats[0];
         double directRawLuma = directRawStats[0];
         double lightingLuma = lightingStats[0];
         double stageLightingLuma = stageLightingStats[0];
         double stageIndirectLuma = stageIndirectStats[0];
         double handheldLuma = handheldStats[0];
         double indirectRawLuma = indirectRawStats[0];
         double indirectLuma = indirectStats[0];
         this.metrics.directMaxLuma = Math.max(this.metrics.directMaxLuma, directLuma);
         this.metrics.directSoftMaxLuma = Math.max(this.metrics.directSoftMaxLuma, directSoftLuma);
         this.metrics.directDenoisedMaxLuma = Math.max(this.metrics.directDenoisedMaxLuma, directDenoisedLuma);
         this.metrics.directRawMaxLuma = Math.max(this.metrics.directRawMaxLuma, directRawLuma);
         this.metrics.lightingBufferMaxLuma = Math.max(this.metrics.lightingBufferMaxLuma, lightingLuma);
         this.metrics.stageLightingMaxLuma = Math.max(this.metrics.stageLightingMaxLuma, stageLightingLuma);
         this.metrics.stageIndirectMaxLuma = Math.max(this.metrics.stageIndirectMaxLuma, stageIndirectLuma);
         this.metrics.handheldMaxLuma = Math.max(this.metrics.handheldMaxLuma, handheldLuma);
         this.metrics.indirectRawMaxLuma = Math.max(this.metrics.indirectRawMaxLuma, indirectRawLuma);
         this.metrics.indirectMaxLuma = Math.max(this.metrics.indirectMaxLuma, indirectLuma);
         this.metrics.latestDirectMeanLuma = directStats[1];
         this.metrics.latestDirectDenoisedMeanLuma = directDenoisedStats[1];
         this.metrics.latestDirectRawMeanLuma = directRawStats[1];
         this.metrics.latestDirectRawLinearMeanLuma = directRawLinearStats.meanLuma();
         this.metrics.latestDirectRawLinearMaxLuma = directRawLinearStats.maxLuma();
         this.metrics.latestDirectRawLinearOverbrightFraction = directRawLinearStats.overbrightFraction();
         this.metrics.latestDirectRawLinearFireflyFraction = directRawFireflyStats.fireflyFraction();
         this.metrics.latestDirectRawLinearSevereFireflyFraction = directRawFireflyStats.severeFireflyFraction();
         this.metrics.latestDirectRawLinearFireflyLumaShare = directRawFireflyStats.fireflyLumaShare();
         this.metrics.latestDirectRawLinearSaturatedPixelFraction = directRawFireflyStats.saturatedPixelFraction();
         this.metrics.latestDirectRawLinearNonFiniteFraction = directRawFireflyStats.nonFiniteFraction();
         this.metrics.latestDirectDenoisedLinearMeanLuma = directDenoisedLinearStats.meanLuma();
         this.metrics.latestDirectDenoisedLinearMaxLuma = directDenoisedLinearStats.maxLuma();
         this.metrics.latestDirectDenoisedLinearOverbrightFraction = directDenoisedLinearStats.overbrightFraction();
         this.metrics.latestDirectDenoisedLinearFireflyFraction = directDenoisedFireflyStats.fireflyFraction();
         this.metrics.latestDirectDenoisedLinearSevereFireflyFraction = directDenoisedFireflyStats.severeFireflyFraction();
         this.metrics.latestDirectDenoisedLinearFireflyLumaShare = directDenoisedFireflyStats.fireflyLumaShare();
         this.metrics.latestDirectDenoisedLinearSaturatedPixelFraction = directDenoisedFireflyStats.saturatedPixelFraction();
         this.metrics.latestDirectDenoisedLinearNonFiniteFraction = directDenoisedFireflyStats.nonFiniteFraction();
         this.metrics.latestLightingMeanLuma = lightingStats[1];
         this.metrics.latestStageLightingMeanLuma = stageLightingStats[1];
         this.metrics.latestStageIndirectMeanLuma = stageIndirectStats[1];
         this.metrics.latestIndirectRawMeanLuma = indirectRawStats[1];
         this.metrics.latestIndirectMeanLuma = indirectStats[1];
         this.metrics.latestSpecRawLinearMeanLuma = specRawLinearStats.meanLuma();
         this.metrics.latestSpecRawLinearMaxLuma = specRawLinearStats.maxLuma();
         this.metrics.latestSpecRawLinearOverbrightFraction = specRawLinearStats.overbrightFraction();
         this.metrics.latestSpecRawLinearFireflyFraction = specRawFireflyStats.fireflyFraction();
         this.metrics.latestSpecRawLinearSevereFireflyFraction = specRawFireflyStats.severeFireflyFraction();
         this.metrics.latestSpecRawLinearFireflyLumaShare = specRawFireflyStats.fireflyLumaShare();
         this.metrics.latestSpecRawLinearSaturatedPixelFraction = specRawFireflyStats.saturatedPixelFraction();
         this.metrics.latestSpecRawLinearNonFiniteFraction = specRawFireflyStats.nonFiniteFraction();
         this.metrics.latestSpecDenoisedLinearMeanLuma = specDenoisedLinearStats.meanLuma();
         this.metrics.latestSpecDenoisedLinearMaxLuma = specDenoisedLinearStats.maxLuma();
         this.metrics.latestSpecDenoisedLinearOverbrightFraction = specDenoisedLinearStats.overbrightFraction();
         this.metrics.latestSpecDenoisedLinearFireflyFraction = specDenoisedFireflyStats.fireflyFraction();
         this.metrics.latestSpecDenoisedLinearSevereFireflyFraction = specDenoisedFireflyStats.severeFireflyFraction();
         this.metrics.latestSpecDenoisedLinearFireflyLumaShare = specDenoisedFireflyStats.fireflyLumaShare();
         this.metrics.latestSpecDenoisedLinearSaturatedPixelFraction = specDenoisedFireflyStats.saturatedPixelFraction();
         this.metrics.latestSpecDenoisedLinearNonFiniteFraction = specDenoisedFireflyStats.nonFiniteFraction();
         this.metrics.latestIndirectRawLinearMeanLuma = indirectRawLinearStats.meanLuma();
         this.metrics.latestIndirectRawLinearMaxLuma = indirectRawLinearStats.maxLuma();
         this.metrics.latestIndirectRawLinearOverbrightFraction = indirectRawLinearStats.overbrightFraction();
         this.metrics.latestIndirectRawLinearFireflyFraction = indirectRawFireflyStats.fireflyFraction();
         this.metrics.latestIndirectRawLinearSevereFireflyFraction = indirectRawFireflyStats.severeFireflyFraction();
         this.metrics.latestIndirectRawLinearFireflyLumaShare = indirectRawFireflyStats.fireflyLumaShare();
         this.metrics.latestIndirectRawLinearSaturatedPixelFraction = indirectRawFireflyStats.saturatedPixelFraction();
         this.metrics.latestIndirectRawLinearNonFiniteFraction = indirectRawFireflyStats.nonFiniteFraction();
         this.metrics.latestIndirectLinearMeanLuma = indirectLinearStats.meanLuma();
         this.metrics.latestIndirectLinearMaxLuma = indirectLinearStats.maxLuma();
         this.metrics.latestIndirectLinearOverbrightFraction = indirectLinearStats.overbrightFraction();
         this.metrics.latestIndirectLinearFireflyFraction = indirectFireflyStats.fireflyFraction();
         this.metrics.latestIndirectLinearSevereFireflyFraction = indirectFireflyStats.severeFireflyFraction();
         this.metrics.latestIndirectLinearFireflyLumaShare = indirectFireflyStats.fireflyLumaShare();
         this.metrics.latestIndirectLinearSaturatedPixelFraction = indirectFireflyStats.saturatedPixelFraction();
         this.metrics.latestIndirectLinearNonFiniteFraction = indirectFireflyStats.nonFiniteFraction();
         this.metrics.latestStageIndirectLinearMeanLuma = stageIndirectLinearStats.meanLuma();
         this.metrics.latestStageIndirectLinearMaxLuma = stageIndirectLinearStats.maxLuma();
         this.metrics.latestStageIndirectLinearOverbrightFraction = stageIndirectLinearStats.overbrightFraction();
         this.metrics.latestDirectMeanRed = directStats[2];
         this.metrics.latestDirectMeanGreen = directStats[3];
         this.metrics.latestDirectMeanBlue = directStats[4];
         this.metrics.latestDirectMeanAlpha = directAlphaStats[0];
         this.metrics.latestDirectZeroAlphaFraction = directAlphaStats[3];
         this.metrics.latestDirectAlphaDelta = ShaderAutomationImageUtils.computeAlphaDelta(this.metrics.previousDirectImage, directImage);
         if (this.metrics.previousDirectImage != null) {
            this.metrics.directAlphaDeltaSum += this.metrics.latestDirectAlphaDelta;
            this.metrics.directAlphaDeltaMax = Math.max(this.metrics.directAlphaDeltaMax, this.metrics.latestDirectAlphaDelta);
            this.metrics.directAlphaDeltaSamples++;
         }
         this.metrics.latestDirectBrightnessVariance = ShaderAutomationImageUtils.computeImageBrightnessVariance(directImage);
         this.metrics.latestDirectBrightnessStdDev = Math.sqrt(this.metrics.latestDirectBrightnessVariance);
         this.metrics.directBrightnessVarianceSum += this.metrics.latestDirectBrightnessVariance;
         this.metrics.directBrightnessVarianceMax = Math.max(this.metrics.directBrightnessVarianceMax, this.metrics.latestDirectBrightnessVariance);
         this.metrics.directBrightnessVarianceSamples++;
         this.metrics.latestHandheldBrightnessVariance = ShaderAutomationImageUtils.computeImageBrightnessVariance(handheldImage);
         this.metrics.latestHandheldBrightnessStdDev = Math.sqrt(this.metrics.latestHandheldBrightnessVariance);
         this.metrics.handheldBrightnessVarianceSum += this.metrics.latestHandheldBrightnessVariance;
         this.metrics.handheldBrightnessVarianceMax = Math.max(this.metrics.handheldBrightnessVarianceMax, this.metrics.latestHandheldBrightnessVariance);
         this.metrics.handheldBrightnessVarianceSamples++;
         this.metrics.latestLightingMeanRed = lightingStats[2];
         this.metrics.latestLightingMeanGreen = lightingStats[3];
         this.metrics.latestLightingMeanBlue = lightingStats[4];
         this.metrics.latestStageLightingMeanRed = stageLightingStats[2];
         this.metrics.latestStageLightingMeanGreen = stageLightingStats[3];
         this.metrics.latestStageLightingMeanBlue = stageLightingStats[4];
         this.metrics.latestStageIndirectMeanRed = stageIndirectStats[2];
         this.metrics.latestStageIndirectMeanGreen = stageIndirectStats[3];
         this.metrics.latestStageIndirectMeanBlue = stageIndirectStats[4];
         this.metrics.latestIndirectMeanRed = indirectStats[2];
         this.metrics.latestIndirectMeanGreen = indirectStats[3];
         this.metrics.latestIndirectMeanBlue = indirectStats[4];
         this.metrics.latestStageIndirectMeanAlpha = stageIndirectAlphaStats[0];
         this.metrics.latestStageIndirectZeroAlphaFraction = stageIndirectAlphaStats[3];
         this.metrics.latestIndirectMeanAlpha = indirectAlphaStats[0];
         this.metrics.latestIndirectZeroAlphaFraction = indirectAlphaStats[3];
         this.metrics.updateDirectSoftSignalState(directSoftLuma, captureIndex, this.activeTicks, this.metrics.directMaxLuma, this.metrics.directRawMaxLuma, this.metrics.handheldMaxLuma);
         this.metrics.recordTemporalDelta(directTemporalAndRepeatImage, false, false);
         this.metrics.recordTemporalDelta(directSoftImage, true, false);
         this.metrics.recordTemporalDelta(indirectImage, false, true);
         this.latestTracedLightCount = lightRegistry.lightCount();
         this.latestTotalLightCount = lightRegistry.totalLights();
         this.maxTracedLightCount = Math.max(this.maxTracedLightCount, this.latestTracedLightCount);
         this.maxTotalLightCount = Math.max(this.maxTotalLightCount, this.latestTotalLightCount);
         this.latestLightSelectionCapped = this.latestTotalLightCount > this.latestTracedLightCount;
         this.latestLightBlendFactor = worldRegistry.fetchLightBlendFactor();
         this.latestLightBlendRegionCount = worldRegistry.getLightBlendRegionCount();
         this.latestGlobalLightReload = worldRegistry.fetchLightReload();
         if (this.latestLightSelectionCapped) {
            this.lightSelectionCappedCaptures++;
         }
         if (this.latestGlobalLightReload) {
            this.globalLightReloadCaptures++;
         }
         this.metrics.updatePostMotionDropMetrics(this.cameraMotionStopActiveTick, this.activeTicks);
         this.metrics.latestDirectDenoiserGain = ShaderAutomationImageUtils.computeRelativeImprovement(directRawStats[1], directDenoisedStats[1]);
         this.metrics.latestSpecDenoiserGain = ShaderAutomationImageUtils.computeRelativeImprovement(this.metrics.latestSpecRawLinearMeanLuma, this.metrics.latestSpecDenoisedLinearMeanLuma);
         this.metrics.latestIndirectResolveGain = ShaderAutomationImageUtils.computeRelativeImprovement(stageIndirectStats[1], indirectStats[1]);
         this.metrics.directDenoiserGainSum += this.metrics.latestDirectDenoiserGain;
         this.metrics.directDenoiserGainMax = Math.max(this.metrics.directDenoiserGainMax, this.metrics.latestDirectDenoiserGain);
         this.metrics.directDenoiserGainSamples++;
         this.metrics.specDenoiserGainSum += this.metrics.latestSpecDenoiserGain;
         this.metrics.specDenoiserGainMax = Math.max(this.metrics.specDenoiserGainMax, this.metrics.latestSpecDenoiserGain);
         this.metrics.specDenoiserGainSamples++;
         this.metrics.indirectResolveGainSum += this.metrics.latestIndirectResolveGain;
         this.metrics.indirectResolveGainMax = Math.max(this.metrics.indirectResolveGainMax, this.metrics.latestIndirectResolveGain);
         this.metrics.indirectResolveGainSamples++;
         this.metrics.recordMotionRepeatDelta(directTemporalAndRepeatImage, true, captureIndex, this.activeTicks, this.motionRepeatSettleTicks, this.ticksSinceLastAutomationCommand(), this.isMotionRepeatHistorySettled(), this.cameraController.getCameraMotionStartActiveTick(), this.cameraController.getCameraMotionPeriodTicks(), this.worldController.getTimeOfDayCommandsIssued(), this.worldController.getBlockToggleCommandsIssued(), this.motionRepeatHistoryEpoch());
         this.metrics.recordMotionRepeatDelta(indirectImage, false, captureIndex, this.activeTicks, this.motionRepeatSettleTicks, this.ticksSinceLastAutomationCommand(), this.isMotionRepeatHistorySettled(), this.cameraController.getCameraMotionStartActiveTick(), this.cameraController.getCameraMotionPeriodTicks(), this.worldController.getTimeOfDayCommandsIssued(), this.worldController.getBlockToggleCommandsIssued(), this.motionRepeatHistoryEpoch());
         this.metrics.updateWholeLightFlashDiagnostics(captureIndex, resolvedReservoirStats, this.latestTracedLightCount, this.latestTotalLightCount, this.latestLightBlendFactor, WHOLE_LIGHT_FLASH_DIRECT_DROP_THRESHOLD, WHOLE_LIGHT_FLASH_VALID_FRACTION_DROP_THRESHOLD, WHOLE_LIGHT_FLASH_LIGHT_COUNT_DROP_THRESHOLD, WHOLE_LIGHT_FLASH_BLEND_FACTOR_JUMP_THRESHOLD);
         this.capturesTaken = captureIndex;
         this.pendingFinalCaptureIndex = captureIndex;
         boolean directThisCapture = directLuma > 0.0 || directSoftLuma > 0.0 || directRawLuma > 0.0 || handheldLuma > 0.0;
         boolean litThisCapture = directThisCapture || indirectLuma > 0.0 || lightingLuma > 0.0 || stageLightingLuma > 0.0;
         boolean successSignalThisCapture = this.requireDirectSignal ? directThisCapture : litThisCapture;
         if (successSignalThisCapture) {
            this.litCapturesTaken++;
            if (this.firstLightingSignalActiveTick < 0) {
               this.firstLightingSignalActiveTick = this.activeTicks;
               Photonic.info("[Automation] first lighting signal at activeTicks={} renderedFrames={} capture={}", this.activeTicks, this.renderedFrames, this.capturesTaken);
            }
         }
         this.directSignalDetected = this.metrics.directMaxLuma > 0.0 || this.metrics.directSoftMaxLuma > 0.0 || this.metrics.directRawMaxLuma > 0.0 || this.metrics.handheldMaxLuma > 0.0;
         this.lightingSignalDetected = this.metrics.directMaxLuma > 0.0 || this.metrics.directSoftMaxLuma > 0.0 || this.metrics.handheldMaxLuma > 0.0 || this.metrics.indirectMaxLuma > 0.0;
         Photonic.info("[Automation] capture={} signal={} directSignal={} directSoftSignal={} litCaptures={}/{} activeTicks={} renderedFrames={} lights={}/{} capped={} blendFactor={} blendRegions={} globalReload={} luma(direct={}, soft={}, denoised={}, rawDirect={}, lighting={}, stageLighting={}, stageIndirect={}, handheld={}, rawIndirect={}, indirect={}) mean(direct={}, denoised={}, rawDirect={}, lighting={}, stageLighting={}, stageIndirect={}, rawIndirect={}, indirect={}) variance(direct={}, handheld={}) stddev(direct={}, handheld={}) directAlpha(mean={}, zeroFrac={}) linearIndirect(rawMean={}, rawMax={}, rawOverbright={}, stageMean={}, stageMax={}, stageOverbright={}) meanRgb(direct=({}, {}, {}), lighting=({}, {}, {}), stageLighting=({}, {}, {}), stageIndirect=({}, {}, {}), indirect=({}, {}, {})) indirectAlpha(mainMean={}, mainZeroFrac={}, stageMean={}, stageZeroFrac={}) temporalDelta(directAvg={}, directMax={}, directPixelMaxLatest={}, directPixelMaxAvg={}, softAvg={}, softMax={}, indirectAvg={}, indirectMax={})",
            this.capturesTaken,
            successSignalThisCapture,
            directThisCapture,
            this.metrics.directSoftSignalDetected,
            this.litCapturesTaken,
            this.minLitCaptures,
            this.activeTicks,
            this.renderedFrames,
            this.latestTracedLightCount,
            this.latestTotalLightCount,
            this.latestLightSelectionCapped,
            String.format(Locale.ROOT, "%.3f", this.latestLightBlendFactor),
            this.latestLightBlendRegionCount,
            this.latestGlobalLightReload,
            String.format(Locale.ROOT, "%.4f", directLuma),
            String.format(Locale.ROOT, "%.4f", directSoftLuma),
            String.format(Locale.ROOT, "%.4f", directDenoisedLuma),
            String.format(Locale.ROOT, "%.4f", directRawLuma),
            String.format(Locale.ROOT, "%.4f", lightingLuma),
            String.format(Locale.ROOT, "%.4f", stageLightingLuma),
            String.format(Locale.ROOT, "%.4f", stageIndirectLuma),
            String.format(Locale.ROOT, "%.4f", handheldLuma),
            String.format(Locale.ROOT, "%.4f", indirectRawLuma),
            String.format(Locale.ROOT, "%.4f", indirectLuma),
            String.format(Locale.ROOT, "%.5f", directStats[1]),
            String.format(Locale.ROOT, "%.5f", directDenoisedStats[1]),
            String.format(Locale.ROOT, "%.5f", directRawStats[1]),
            String.format(Locale.ROOT, "%.5f", lightingStats[1]),
            String.format(Locale.ROOT, "%.5f", stageLightingStats[1]),
            String.format(Locale.ROOT, "%.5f", stageIndirectStats[1]),
            String.format(Locale.ROOT, "%.5f", indirectRawStats[1]),
            String.format(Locale.ROOT, "%.5f", indirectStats[1]),
            String.format(Locale.ROOT, "%.6f", this.metrics.latestDirectBrightnessVariance),
            String.format(Locale.ROOT, "%.6f", this.metrics.latestHandheldBrightnessVariance),
            String.format(Locale.ROOT, "%.6f", this.metrics.latestDirectBrightnessStdDev),
            String.format(Locale.ROOT, "%.6f", this.metrics.latestHandheldBrightnessStdDev),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectMeanAlpha),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectZeroAlphaFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectRawLinearMeanLuma),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectRawLinearMaxLuma),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectRawLinearOverbrightFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestStageIndirectLinearMeanLuma),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestStageIndirectLinearMaxLuma),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestStageIndirectLinearOverbrightFraction),
            String.format(Locale.ROOT, "%.5f", directStats[2]),
            String.format(Locale.ROOT, "%.5f", directStats[3]),
            String.format(Locale.ROOT, "%.5f", directStats[4]),
            String.format(Locale.ROOT, "%.5f", lightingStats[2]),
            String.format(Locale.ROOT, "%.5f", lightingStats[3]),
            String.format(Locale.ROOT, "%.5f", lightingStats[4]),
            String.format(Locale.ROOT, "%.5f", stageLightingStats[2]),
            String.format(Locale.ROOT, "%.5f", stageLightingStats[3]),
            String.format(Locale.ROOT, "%.5f", stageLightingStats[4]),
            String.format(Locale.ROOT, "%.5f", stageIndirectStats[2]),
            String.format(Locale.ROOT, "%.5f", stageIndirectStats[3]),
            String.format(Locale.ROOT, "%.5f", stageIndirectStats[4]),
            String.format(Locale.ROOT, "%.5f", indirectStats[2]),
            String.format(Locale.ROOT, "%.5f", indirectStats[3]),
            String.format(Locale.ROOT, "%.5f", indirectStats[4]),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectMeanAlpha),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectZeroAlphaFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestStageIndirectMeanAlpha),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestStageIndirectZeroAlphaFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.averageTemporalDelta(false, false)),
            String.format(Locale.ROOT, "%.5f", this.metrics.directTemporalDeltaMax),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectTemporalMaxPixelDelta),
            String.format(Locale.ROOT, "%.5f", this.metrics.averageDirectTemporalMaxPixelDelta()),
            String.format(Locale.ROOT, "%.5f", this.metrics.averageTemporalDelta(true, false)),
            String.format(Locale.ROOT, "%.5f", this.metrics.directSoftTemporalDeltaMax),
            String.format(Locale.ROOT, "%.5f", this.metrics.averageTemporalDelta(false, true)),
            String.format(Locale.ROOT, "%.5f", this.metrics.indirectTemporalDeltaMax));
         Photonic.info(
            "[Automation] reservoir capture={} proposal(lightValid={}, strict={}, meanWeight={}, meanM={}) resolved(lightValid={}, strict={}, meanWeight={}, meanM={}) stagePosition(mean=({}, {}, {}), min=({}, {}, {}), max=({}, {}, {}))",
            this.capturesTaken,
            String.format(Locale.ROOT, "%.5f", proposalReservoirStats.lightValidFraction()),
            String.format(Locale.ROOT, "%.5f", proposalReservoirStats.strictValidFraction()),
            String.format(Locale.ROOT, "%.5f", proposalReservoirStats.meanWeight()),
            String.format(Locale.ROOT, "%.2f", proposalReservoirStats.meanM()),
            String.format(Locale.ROOT, "%.5f", resolvedReservoirStats.lightValidFraction()),
            String.format(Locale.ROOT, "%.5f", resolvedReservoirStats.strictValidFraction()),
            String.format(Locale.ROOT, "%.5f", resolvedReservoirStats.meanWeight()),
            String.format(Locale.ROOT, "%.2f", resolvedReservoirStats.meanM()),
            String.format(Locale.ROOT, "%.3f", stagePositionStats.meanX()),
            String.format(Locale.ROOT, "%.3f", stagePositionStats.meanY()),
            String.format(Locale.ROOT, "%.3f", stagePositionStats.meanZ()),
            String.format(Locale.ROOT, "%.3f", stagePositionStats.minX()),
            String.format(Locale.ROOT, "%.3f", stagePositionStats.minY()),
            String.format(Locale.ROOT, "%.3f", stagePositionStats.minZ()),
            String.format(Locale.ROOT, "%.3f", stagePositionStats.maxX()),
            String.format(Locale.ROOT, "%.3f", stagePositionStats.maxY()),
            String.format(Locale.ROOT, "%.3f", stagePositionStats.maxZ())
         );
         Photonic.info(
            "[Automation] capture-path capture={} directSoft(currentMax={}, currentMean={}, currentAlpha={}, currentZeroAlpha={}, previousMax={}, previousMean={}, previousAlpha={}, previousZeroAlpha={})",
            this.capturesTaken,
            String.format(Locale.ROOT, "%.5f", directSoftLinearStats.maxLuma()),
            String.format(Locale.ROOT, "%.5f", directSoftLinearStats.meanLuma()),
            String.format(Locale.ROOT, "%.5f", directSoftLinearStats.meanAlpha()),
            String.format(Locale.ROOT, "%.5f", directSoftLinearStats.zeroAlphaFraction()),
            String.format(Locale.ROOT, "%.5f", directSoftPreviousLinearStats.maxLuma()),
            String.format(Locale.ROOT, "%.5f", directSoftPreviousLinearStats.meanLuma()),
            String.format(Locale.ROOT, "%.5f", directSoftPreviousLinearStats.meanAlpha()),
            String.format(Locale.ROOT, "%.5f", directSoftPreviousLinearStats.zeroAlphaFraction())
         );
         Photonic.info(
            "[Automation] initial-sampling capture={} reasons(invalidSurface={}, noLights={}, noLocalSamples={}, invalidLightSelection={}, invalidLightSample={}, zeroRadiance={}, zeroSourcePdf={}, zeroTargetPdf={}, nonFiniteSourcePdf={}, nonFiniteTargetPdf={}, success={}) debug(meanPositiveCandidateFraction={}, proposalValidFraction={}, meanProposalWeight={}) row(successBoundaryRowFromBottom={} successBoundaryRowFromTop={} successDelta={} zeroTargetBoundaryRowFromBottom={} zeroTargetBoundaryRowFromTop={} zeroTargetDelta={} proposalValidBoundaryRowFromBottom={} proposalValidBoundaryRowFromTop={} proposalValidDelta={} proposalWeightBoundaryRowFromBottom={} proposalWeightBoundaryRowFromTop={} proposalWeightDelta={})",
            this.capturesTaken,
            String.format(Locale.ROOT, "%.5f", initialSamplingDebugStats.invalidSurfaceFraction()),
            String.format(Locale.ROOT, "%.5f", initialSamplingDebugStats.noLightsFraction()),
            String.format(Locale.ROOT, "%.5f", initialSamplingDebugStats.noLocalSamplesFraction()),
            String.format(Locale.ROOT, "%.5f", initialSamplingDebugStats.invalidLightSelectionFraction()),
            String.format(Locale.ROOT, "%.5f", initialSamplingDebugStats.invalidLightSampleFraction()),
            String.format(Locale.ROOT, "%.5f", initialSamplingDebugStats.zeroRadianceFraction()),
            String.format(Locale.ROOT, "%.5f", initialSamplingDebugStats.zeroSourcePdfFraction()),
            String.format(Locale.ROOT, "%.5f", initialSamplingDebugStats.zeroTargetPdfFraction()),
            String.format(Locale.ROOT, "%.5f", initialSamplingDebugStats.nonFiniteSourcePdfFraction()),
            String.format(Locale.ROOT, "%.5f", initialSamplingDebugStats.nonFiniteTargetPdfFraction()),
            String.format(Locale.ROOT, "%.5f", initialSamplingDebugStats.successFraction()),
            String.format(Locale.ROOT, "%.5f", initialSamplingDebugStats.meanPositiveCandidateFraction()),
            String.format(Locale.ROOT, "%.5f", initialSamplingDebugStats.proposalValidFraction()),
            String.format(Locale.ROOT, "%.5f", initialSamplingDebugStats.meanProposalWeight()),
            initialSamplingDebugStats.successRowJump().rowFromBottom(),
            initialSamplingDebugStats.successRowJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", initialSamplingDebugStats.successRowJump().delta()),
            initialSamplingDebugStats.zeroTargetRowJump().rowFromBottom(),
            initialSamplingDebugStats.zeroTargetRowJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", initialSamplingDebugStats.zeroTargetRowJump().delta()),
            initialSamplingDebugStats.proposalValidRowJump().rowFromBottom(),
            initialSamplingDebugStats.proposalValidRowJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", initialSamplingDebugStats.proposalValidRowJump().delta()),
            initialSamplingDebugStats.proposalWeightRowJump().rowFromBottom(),
            initialSamplingDebugStats.proposalWeightRowJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", initialSamplingDebugStats.proposalWeightRowJump().delta())
         );
         Photonic.info(
            "[Automation] row-debug capture={} directRawLuma(boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) proposalValid(boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) proposalWeight(boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) proposalTargetPdf(boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) proposalWeightTimesPdf(boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) proposalM(boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) resolvedValid(boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) resolvedWeight(boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) resolvedTargetPdf(boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) resolvedWeightTimesPdf(boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) resolvedM(boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) stageLinearDepth(boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) regirCellZ(boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) regirCoverage(boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) regirCoverageWithJitter(boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={})",
            this.capturesTaken,
            directRawRowJump.rowFromBottom(),
            directRawRowJump.rowFromTop(),
            String.format(Locale.ROOT, "%.6f", directRawRowJump.delta()),
            String.format(Locale.ROOT, "%.6f", directRawRowJump.previousMean()),
            String.format(Locale.ROOT, "%.6f", directRawRowJump.nextMean()),
            proposalReservoirRowJumps.validFractionJump().rowFromBottom(),
            proposalReservoirRowJumps.validFractionJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", proposalReservoirRowJumps.validFractionJump().delta()),
            String.format(Locale.ROOT, "%.6f", proposalReservoirRowJumps.validFractionJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", proposalReservoirRowJumps.validFractionJump().nextMean()),
            proposalReservoirRowJumps.weightJump().rowFromBottom(),
            proposalReservoirRowJumps.weightJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", proposalReservoirRowJumps.weightJump().delta()),
            String.format(Locale.ROOT, "%.6f", proposalReservoirRowJumps.weightJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", proposalReservoirRowJumps.weightJump().nextMean()),
            proposalReservoirRowJumps.targetPdfJump().rowFromBottom(),
            proposalReservoirRowJumps.targetPdfJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", proposalReservoirRowJumps.targetPdfJump().delta()),
            String.format(Locale.ROOT, "%.6f", proposalReservoirRowJumps.targetPdfJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", proposalReservoirRowJumps.targetPdfJump().nextMean()),
            proposalReservoirRowJumps.weightTimesTargetPdfJump().rowFromBottom(),
            proposalReservoirRowJumps.weightTimesTargetPdfJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", proposalReservoirRowJumps.weightTimesTargetPdfJump().delta()),
            String.format(Locale.ROOT, "%.6f", proposalReservoirRowJumps.weightTimesTargetPdfJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", proposalReservoirRowJumps.weightTimesTargetPdfJump().nextMean()),
            proposalReservoirRowJumps.meanMJump().rowFromBottom(),
            proposalReservoirRowJumps.meanMJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", proposalReservoirRowJumps.meanMJump().delta()),
            String.format(Locale.ROOT, "%.6f", proposalReservoirRowJumps.meanMJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", proposalReservoirRowJumps.meanMJump().nextMean()),
            resolvedReservoirRowJumps.validFractionJump().rowFromBottom(),
            resolvedReservoirRowJumps.validFractionJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", resolvedReservoirRowJumps.validFractionJump().delta()),
            String.format(Locale.ROOT, "%.6f", resolvedReservoirRowJumps.validFractionJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", resolvedReservoirRowJumps.validFractionJump().nextMean()),
            resolvedReservoirRowJumps.weightJump().rowFromBottom(),
            resolvedReservoirRowJumps.weightJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", resolvedReservoirRowJumps.weightJump().delta()),
            String.format(Locale.ROOT, "%.6f", resolvedReservoirRowJumps.weightJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", resolvedReservoirRowJumps.weightJump().nextMean()),
            resolvedReservoirRowJumps.targetPdfJump().rowFromBottom(),
            resolvedReservoirRowJumps.targetPdfJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", resolvedReservoirRowJumps.targetPdfJump().delta()),
            String.format(Locale.ROOT, "%.6f", resolvedReservoirRowJumps.targetPdfJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", resolvedReservoirRowJumps.targetPdfJump().nextMean()),
            resolvedReservoirRowJumps.weightTimesTargetPdfJump().rowFromBottom(),
            resolvedReservoirRowJumps.weightTimesTargetPdfJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", resolvedReservoirRowJumps.weightTimesTargetPdfJump().delta()),
            String.format(Locale.ROOT, "%.6f", resolvedReservoirRowJumps.weightTimesTargetPdfJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", resolvedReservoirRowJumps.weightTimesTargetPdfJump().nextMean()),
            resolvedReservoirRowJumps.meanMJump().rowFromBottom(),
            resolvedReservoirRowJumps.meanMJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", resolvedReservoirRowJumps.meanMJump().delta()),
            String.format(Locale.ROOT, "%.6f", resolvedReservoirRowJumps.meanMJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", resolvedReservoirRowJumps.meanMJump().nextMean()),
            stageLinearDepthRowJump.rowFromBottom(),
            stageLinearDepthRowJump.rowFromTop(),
            String.format(Locale.ROOT, "%.6f", stageLinearDepthRowJump.delta()),
            String.format(Locale.ROOT, "%.6f", stageLinearDepthRowJump.previousMean()),
            String.format(Locale.ROOT, "%.6f", stageLinearDepthRowJump.nextMean()),
            regirCellZRowJump.rowFromBottom(),
            regirCellZRowJump.rowFromTop(),
            String.format(Locale.ROOT, "%.6f", regirCellZRowJump.delta()),
            String.format(Locale.ROOT, "%.6f", regirCellZRowJump.previousMean()),
            String.format(Locale.ROOT, "%.6f", regirCellZRowJump.nextMean()),
            regirCoverageRowJumps.nominalCoverageJump().rowFromBottom(),
            regirCoverageRowJumps.nominalCoverageJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", regirCoverageRowJumps.nominalCoverageJump().delta()),
            String.format(Locale.ROOT, "%.6f", regirCoverageRowJumps.nominalCoverageJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", regirCoverageRowJumps.nominalCoverageJump().nextMean()),
            regirCoverageRowJumps.expandedCoverageJump().rowFromBottom(),
            regirCoverageRowJumps.expandedCoverageJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", regirCoverageRowJumps.expandedCoverageJump().delta()),
            String.format(Locale.ROOT, "%.6f", regirCoverageRowJumps.expandedCoverageJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", regirCoverageRowJumps.expandedCoverageJump().nextMean())
         );
         Photonic.info(
            "[Automation] regir-pixel capture={} visible={} strictValidVisible={} exactOutsideGrid={} invalidOutsideGrid={} validOutsideGrid={} invalidZeroSlot={} validZeroSlot={} cellValidSlots(invalidMean={}, validMean={}, boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) cellMeanWeight(invalidMean={}, validMean={}, boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) outsideGrid(boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) jitteredCellChanged(fraction={}, boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) jitteredCellMeanWeightDelta(mean={}, boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={}) jitteredOutsideGridDelta(fraction={}, boundaryRowFromBottom={} boundaryRowFromTop={} delta={} prev={} next={})",
            this.capturesTaken,
            String.format(Locale.ROOT, "%.5f", regirPixelCorrelationStats.visiblePixelFraction()),
            String.format(Locale.ROOT, "%.5f", regirPixelCorrelationStats.strictValidVisibleFraction()),
            String.format(Locale.ROOT, "%.5f", regirPixelCorrelationStats.exactOutsideGridFraction()),
            String.format(Locale.ROOT, "%.5f", regirPixelCorrelationStats.strictInvalidOutsideGridFraction()),
            String.format(Locale.ROOT, "%.5f", regirPixelCorrelationStats.strictValidOutsideGridFraction()),
            String.format(Locale.ROOT, "%.5f", regirPixelCorrelationStats.strictInvalidZeroSlotFraction()),
            String.format(Locale.ROOT, "%.5f", regirPixelCorrelationStats.strictValidZeroSlotFraction()),
            String.format(Locale.ROOT, "%.4f", regirPixelCorrelationStats.strictInvalidMeanCellValidSlots()),
            String.format(Locale.ROOT, "%.4f", regirPixelCorrelationStats.strictValidMeanCellValidSlots()),
            regirPixelCorrelationStats.cellValidSlotsJump().rowFromBottom(),
            regirPixelCorrelationStats.cellValidSlotsJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.cellValidSlotsJump().delta()),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.cellValidSlotsJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.cellValidSlotsJump().nextMean()),
            String.format(Locale.ROOT, "%.4f", regirPixelCorrelationStats.strictInvalidMeanCellWeight()),
            String.format(Locale.ROOT, "%.4f", regirPixelCorrelationStats.strictValidMeanCellWeight()),
            regirPixelCorrelationStats.cellMeanWeightJump().rowFromBottom(),
            regirPixelCorrelationStats.cellMeanWeightJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.cellMeanWeightJump().delta()),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.cellMeanWeightJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.cellMeanWeightJump().nextMean()),
            regirPixelCorrelationStats.outsideGridJump().rowFromBottom(),
            regirPixelCorrelationStats.outsideGridJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.outsideGridJump().delta()),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.outsideGridJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.outsideGridJump().nextMean()),
            String.format(Locale.ROOT, "%.5f", regirPixelCorrelationStats.jitteredCellChangedFraction()),
            regirPixelCorrelationStats.jitteredCellChangedJump().rowFromBottom(),
            regirPixelCorrelationStats.jitteredCellChangedJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.jitteredCellChangedJump().delta()),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.jitteredCellChangedJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.jitteredCellChangedJump().nextMean()),
            String.format(Locale.ROOT, "%.5f", regirPixelCorrelationStats.jitteredMeanCellWeightDelta()),
            regirPixelCorrelationStats.jitteredCellMeanWeightDeltaJump().rowFromBottom(),
            regirPixelCorrelationStats.jitteredCellMeanWeightDeltaJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.jitteredCellMeanWeightDeltaJump().delta()),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.jitteredCellMeanWeightDeltaJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.jitteredCellMeanWeightDeltaJump().nextMean()),
            String.format(Locale.ROOT, "%.5f", regirPixelCorrelationStats.jitteredOutsideGridDeltaFraction()),
            regirPixelCorrelationStats.jitteredOutsideGridDeltaJump().rowFromBottom(),
            regirPixelCorrelationStats.jitteredOutsideGridDeltaJump().rowFromTop(),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.jitteredOutsideGridDeltaJump().delta()),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.jitteredOutsideGridDeltaJump().previousMean()),
            String.format(Locale.ROOT, "%.6f", regirPixelCorrelationStats.jitteredOutsideGridDeltaJump().nextMean())
         );
         Photonic.info("[Automation] fireflies capture={} directRaw(mean={}, max={}, overbright={}, hot16={}, hot64={}, hotShare={}, saturated={}, nonFinite={}) directDenoised(mean={}, max={}, overbright={}, hot16={}, hot64={}, hotShare={}, saturated={}, nonFinite={}) specRaw(mean={}, max={}, overbright={}, hot16={}, hot64={}, hotShare={}, saturated={}, nonFinite={}) specDenoised(mean={}, max={}, overbright={}, hot16={}, hot64={}, hotShare={}, saturated={}, nonFinite={}) indirectRaw(mean={}, max={}, overbright={}, hot16={}, hot64={}, hotShare={}, saturated={}, nonFinite={}) indirect(mean={}, max={}, overbright={}, hot16={}, hot64={}, hotShare={}, saturated={}, nonFinite={})",
            this.capturesTaken,
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectRawLinearMeanLuma),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectRawLinearMaxLuma),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectRawLinearOverbrightFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectRawLinearFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectRawLinearSevereFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectRawLinearFireflyLumaShare),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectRawLinearSaturatedPixelFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectRawLinearNonFiniteFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectDenoisedLinearMeanLuma),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectDenoisedLinearMaxLuma),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectDenoisedLinearOverbrightFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectDenoisedLinearFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectDenoisedLinearSevereFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectDenoisedLinearFireflyLumaShare),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectDenoisedLinearSaturatedPixelFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectDenoisedLinearNonFiniteFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestSpecRawLinearMeanLuma),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestSpecRawLinearMaxLuma),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestSpecRawLinearOverbrightFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestSpecRawLinearFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestSpecRawLinearSevereFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestSpecRawLinearFireflyLumaShare),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestSpecRawLinearSaturatedPixelFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestSpecRawLinearNonFiniteFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestSpecDenoisedLinearMeanLuma),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestSpecDenoisedLinearMaxLuma),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestSpecDenoisedLinearOverbrightFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestSpecDenoisedLinearFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestSpecDenoisedLinearSevereFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestSpecDenoisedLinearFireflyLumaShare),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestSpecDenoisedLinearSaturatedPixelFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestSpecDenoisedLinearNonFiniteFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectRawLinearMeanLuma),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectRawLinearMaxLuma),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectRawLinearOverbrightFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectRawLinearFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectRawLinearSevereFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectRawLinearFireflyLumaShare),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectRawLinearSaturatedPixelFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectRawLinearNonFiniteFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectLinearMeanLuma),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectLinearMaxLuma),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectLinearOverbrightFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectLinearFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectLinearSevereFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectLinearFireflyLumaShare),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectLinearSaturatedPixelFraction),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectLinearNonFiniteFraction)
         );
         Photonic.info("[Automation] denoise gain capture={} direct(latest={}, avg={}, max={}) spec(latest={}, avg={}, max={}) indirect(latest={}, avg={}, max={})",
            this.capturesTaken,
            String.format(Locale.ROOT, "%.5f", this.metrics.latestDirectDenoiserGain),
            String.format(Locale.ROOT, "%.5f", this.metrics.directDenoiserGainSamples == 0 ? 0.0 : this.metrics.directDenoiserGainSum / this.metrics.directDenoiserGainSamples),
            String.format(Locale.ROOT, "%.5f", this.metrics.directDenoiserGainMax),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestSpecDenoiserGain),
            String.format(Locale.ROOT, "%.5f", this.metrics.specDenoiserGainSamples == 0 ? 0.0 : this.metrics.specDenoiserGainSum / this.metrics.specDenoiserGainSamples),
            String.format(Locale.ROOT, "%.5f", this.metrics.specDenoiserGainMax),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestIndirectResolveGain),
            String.format(Locale.ROOT, "%.5f", this.metrics.indirectResolveGainSamples == 0 ? 0.0 : this.metrics.indirectResolveGainSum / this.metrics.indirectResolveGainSamples),
            String.format(Locale.ROOT, "%.5f", this.metrics.indirectResolveGainMax));
         Photonic.info("[Automation] post-motion drop capture={} samples={} direct(stop={}, latestDrop={}, avg={}, max={}) rawDirect(stop={}, latestDrop={}, avg={}, max={}) indirect(stop={}, latestDrop={}, avg={}, max={}) stageIndirect(stop={}, latestDrop={}, avg={}, max={})",
            this.capturesTaken,
            this.metrics.postMotionDropSamples,
            String.format(Locale.ROOT, "%.5f", this.metrics.postMotionDirectMeanAtStop),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestPostMotionDirectDrop),
            String.format(Locale.ROOT, "%.5f", this.metrics.postMotionDropSamples == 0 ? 0.0 : this.metrics.postMotionDirectDropSum / this.metrics.postMotionDropSamples),
            String.format(Locale.ROOT, "%.5f", this.metrics.postMotionDirectDropMax),
            String.format(Locale.ROOT, "%.5f", this.metrics.postMotionRawDirectMeanAtStop),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestPostMotionRawDirectDrop),
            String.format(Locale.ROOT, "%.5f", this.metrics.postMotionDropSamples == 0 ? 0.0 : this.metrics.postMotionRawDirectDropSum / this.metrics.postMotionDropSamples),
            String.format(Locale.ROOT, "%.5f", this.metrics.postMotionRawDirectDropMax),
            String.format(Locale.ROOT, "%.5f", this.metrics.postMotionIndirectMeanAtStop),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestPostMotionIndirectDrop),
            String.format(Locale.ROOT, "%.5f", this.metrics.postMotionDropSamples == 0 ? 0.0 : this.metrics.postMotionIndirectDropSum / this.metrics.postMotionDropSamples),
            String.format(Locale.ROOT, "%.5f", this.metrics.postMotionIndirectDropMax),
            String.format(Locale.ROOT, "%.5f", this.metrics.postMotionStageIndirectMeanAtStop),
            String.format(Locale.ROOT, "%.5f", this.metrics.latestPostMotionStageIndirectDrop),
            String.format(Locale.ROOT, "%.5f", this.metrics.postMotionDropSamples == 0 ? 0.0 : this.metrics.postMotionStageIndirectDropSum / this.metrics.postMotionDropSamples),
            String.format(Locale.ROOT, "%.5f", this.metrics.postMotionStageIndirectDropMax));
         if (this.isCameraMotionEnabled()) {
            Photonic.info("[Automation] motion mode={} ticks={} yawOffsetRange=[{}, {}] pitchOffsetRange=[{}, {}] repeatDelta(directAvg={}, directMax={}, indirectAvg={}, indirectMax={}, phaseSamples={}/{})",
               this.cameraController.getCameraMotionMode(),
               this.cameraController.getCameraMotionAppliedTicks(),
               String.format(Locale.ROOT, "%.2f", this.cameraController.getMotionYawOffsetMin()),
               String.format(Locale.ROOT, "%.2f", this.cameraController.getMotionYawOffsetMax()),
               String.format(Locale.ROOT, "%.2f", this.cameraController.getMotionPitchOffsetMin()),
               String.format(Locale.ROOT, "%.2f", this.cameraController.getMotionPitchOffsetMax()),
               String.format(Locale.ROOT, "%.5f", this.metrics.averageMotionRepeatDelta(true)),
               String.format(Locale.ROOT, "%.5f", this.metrics.motionRepeatDirectDeltaMax),
               String.format(Locale.ROOT, "%.5f", this.metrics.averageMotionRepeatDelta(false)),
               String.format(Locale.ROOT, "%.5f", this.metrics.motionRepeatIndirectDeltaMax),
               this.metrics.motionRepeatDirectDeltaSamples,
               this.metrics.motionRepeatIndirectDeltaSamples);
         }
         this.writeReport(false);
         if (this.buildSuccess()) {
            this.finish("");
         }
      } catch (Exception e) {
         this.finish("Automation capture failed: " + e.getClass().getSimpleName() + (e.getMessage() == null ? "" : " - " + e.getMessage()));
      }
   }

   private void captureFinalFrame() {
      if (this.finished || this.pendingFinalCaptureIndex <= 0 || this.pendingFinalCaptureIndex == this.latestFinalCaptureIndex) {
         return;
      }

      MinecraftClient client = MinecraftClient.getInstance();
      if (client.world == null) {
         return;
      }

      try {
         Files.createDirectories(this.captureDir);
         BufferedImage image = this.captureCurrentFramebuffer(client);
         if (image == null) {
            return;
         }

         int captureIndex = this.pendingFinalCaptureIndex;
         String filename = "final-" + String.format(Locale.ROOT, "%03d", captureIndex) + ".png";
         ImageIO.write(image, "PNG", this.captureDir.resolve(filename).toFile());

         double[] finalStats = ShaderAutomationImageUtils.computeImageStats(image);
         this.finalFrameMaxLuma = Math.max(this.finalFrameMaxLuma, finalStats[0]);
         this.latestFinalMeanLuma = finalStats[1];
         this.latestFinalMeanRed = finalStats[2];
         this.latestFinalMeanGreen = finalStats[3];
         this.latestFinalMeanBlue = finalStats[4];
         this.finalSignalDetected = this.finalFrameMaxLuma > 0.0;
         this.latestFinalCaptureIndex = captureIndex;
         this.writeReport(false);
         Photonic.info(
            "[Automation] final capture={} luma(max={}, mean={}) meanRgb=({}, {}, {})",
            captureIndex,
            String.format(Locale.ROOT, "%.4f", finalStats[0]),
            String.format(Locale.ROOT, "%.5f", finalStats[1]),
            String.format(Locale.ROOT, "%.5f", finalStats[2]),
            String.format(Locale.ROOT, "%.5f", finalStats[3]),
            String.format(Locale.ROOT, "%.5f", finalStats[4]));
      } catch (Exception e) {
         this.finish("Automation final-frame capture failed: " + e.getClass().getSimpleName() + (e.getMessage() == null ? "" : " - " + e.getMessage()));
      }
   }

   private BufferedImage captureCurrentFramebuffer(MinecraftClient client) {
      int width = client.getWindow().getFramebufferWidth();
      int height = client.getWindow().getFramebufferHeight();
      if (width <= 0 || height <= 0) {
         return null;
      }

      int originalReadFramebuffer = GL11.glGetInteger(GL30.GL_READ_FRAMEBUFFER_BINDING);
      int originalDrawFramebuffer = GL11.glGetInteger(GL30.GL_DRAW_FRAMEBUFFER_BINDING);
      int originalReadBuffer = GL11.glGetInteger(GL11.GL_READ_BUFFER);
      int effectiveReadFramebuffer = originalReadFramebuffer;
      if (effectiveReadFramebuffer == 0 && originalDrawFramebuffer != 0) {
         GL30.glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER, originalDrawFramebuffer);
         effectiveReadFramebuffer = originalDrawFramebuffer;
      }

      GL11.glReadBuffer(effectiveReadFramebuffer == 0 ? GL11.GL_BACK : GL30.GL_COLOR_ATTACHMENT0);
      GL11.glPixelStorei(GL11.GL_PACK_ALIGNMENT, 1);
      ByteBuffer pixels = BufferUtils.createByteBuffer(width * height * 4);
      GL11.glReadPixels(0, 0, width, height, GL11.GL_RGBA, GL11.GL_UNSIGNED_BYTE, pixels);

      BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
      for (int y = 0; y < height; y++) {
         int srcY = height - 1 - y;
         for (int x = 0; x < width; x++) {
            int base = (x + srcY * width) * 4;
            int r = pixels.get(base) & 255;
            int g = pixels.get(base + 1) & 255;
            int b = pixels.get(base + 2) & 255;
            int a = pixels.get(base + 3) & 255;
            image.setRGB(x, y, (a << 24) | (r << 16) | (g << 8) | b);
         }
      }

      GL11.glReadBuffer(originalReadBuffer);
      if (originalReadFramebuffer != effectiveReadFramebuffer) {
         GL30.glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER, originalReadFramebuffer);
      }
      return image;
   }

   private BufferedImage captureTexture(String name, TextureObject texture, int captureIndex) throws IOException {
      if (texture == null) {
         return null;
      }

      texture.updatePerFrame();
      BufferedImage image;
      if (name.contains("_reservoir_sample")) {
         image = captureReservoirSampleTexture(texture);
      } else if (name.contains("_reservoir_meta")) {
         image = captureReservoirMetaTexture(texture);
      } else {
         image = texture.download();
      }
      if (image == null) {
         Photonic.info("[Automation] capture={} skipped texture='{}' because it is unavailable or zero-sized", captureIndex, name);
         return null;
      }

      String filename = name + "-" + String.format(Locale.ROOT, "%03d", captureIndex) + ".png";
      ImageIO.write(image, "PNG", this.captureDir.resolve(filename).toFile());
      return image;
   }

   private static BufferedImage captureReservoirSampleTexture(TextureObject texture) {
      float[] pixels = texture.downloadFloatData();
      int[] dimensions = texture.getTextureDimensions();
      if (pixels == null || dimensions.length < 2 || dimensions[0] <= 0 || dimensions[1] <= 0) {
         return null;
      }

      int width = dimensions[0];
      int height = dimensions[1];
      BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
      for (int y = 0; y < height; y++) {
         for (int x = 0; x < width; x++) {
            int packedUv = Float.floatToRawIntBits(pixels[(x + y * width) * 4]);
            int r = (packedUv & 0xffff) >>> 8;
            int g = ((packedUv >>> 16) & 0xffff) >>> 8;
            int b = packedUv == 0 ? 0 : 255;
            image.setRGB(x, y, (255 << 24) | (r << 16) | (g << 8) | b);
         }
      }
      return image;
   }

   private static BufferedImage captureReservoirMetaTexture(TextureObject texture) {
      float[] pixels = texture.downloadFloatData();
      int[] dimensions = texture.getTextureDimensions();
      if (pixels == null || dimensions.length < 2 || dimensions[0] <= 0 || dimensions[1] <= 0) {
         return null;
      }

      int width = dimensions[0];
      int height = dimensions[1];
      BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
      for (int y = 0; y < height; y++) {
         for (int x = 0; x < width; x++) {
            int packedMeta = Float.floatToRawIntBits(pixels[(x + y * width) * 4 + 3]);
            int spatialDistanceX = decodePackedReservoirDistance(packedMeta, RTXDI_PACKED_DI_RESERVOIR_DISTANCE_X_SHIFT);
            int spatialDistanceY = decodePackedReservoirDistance(packedMeta, RTXDI_PACKED_DI_RESERVOIR_DISTANCE_Y_SHIFT);
            int age = decodePackedReservoirAge(packedMeta);
            int r = packSignedReservoirDistanceChannel(spatialDistanceX);
            int g = packSignedReservoirDistanceChannel(spatialDistanceY);
            int b = Math.clamp((int)Math.round(age * 255.0 / Math.max(1, RTXDI_PACKED_DI_RESERVOIR_MAX_AGE)), 0, 255);
            image.setRGB(x, y, (255 << 24) | (r << 16) | (g << 8) | b);
         }
      }
      return image;
   }

   private static int packSignedReservoirDistanceChannel(int value) {
      double normalized = (value + RTXDI_PACKED_DI_RESERVOIR_MAX_DISTANCE)
         / (double)Math.max(1, RTXDI_PACKED_DI_RESERVOIR_MAX_DISTANCE * 2);
      return Math.clamp((int)Math.round(normalized * 255.0), 0, 255);
   }

   private void updatePostMotionWindow() {
      if (!this.isCameraMotionEnabled() || this.cameraController.getCameraMotionAppliedTicks() <= 0) {
         return;
      }

      if (this.cameraMotionStopActiveTick >= 0) {
         return;
      }

      long[] timeOfDaySequence = this.worldController.getTimeOfDaySequence();
      int blockToggleCount = this.worldController.getBlockToggleCount();
      if (timeOfDaySequence.length == 0 && blockToggleCount == 0) {
         return;
      }

      int motionEndTick = timeOfDaySequence.length > 0
         ? this.worldController.getTimeOfDayStartActiveTick()
         : this.worldController.getBlockToggleStartActiveTick();
      if (motionEndTick > 0 && this.activeTicks >= motionEndTick) {
         this.cameraMotionStopActiveTick = motionEndTick;
      }
   }

   private int ticksSinceLastAutomationCommand() {
      return this.worldController.ticksSinceLastCommand(this.activeTicks);
   }

   private int ticksSinceLastMotionRepeatHistoryInvalidation() {
      return this.lastMotionRepeatHistoryInvalidationActiveTick == Integer.MIN_VALUE
         ? Integer.MAX_VALUE
         : Math.max(0, this.activeTicks - this.lastMotionRepeatHistoryInvalidationActiveTick);
   }

   private void observeMotionRepeatHistoryActivity() {
      boolean resetRequestsChanged = this.observedResetRequestsTotal >= 0L && this.latestResetRequestsTotal != this.observedResetRequestsTotal;
      boolean blendActivationsChanged = this.observedBlendFullActivations >= 0L && this.latestBlendFullActivations != this.observedBlendFullActivations;
      boolean regionActivationsChanged = this.observedBlendRegionActivations >= 0L && this.latestBlendRegionActivations != this.observedBlendRegionActivations;
      boolean blendCompletionsChanged = this.observedBlendCompletions >= 0L && this.latestBlendCompletions != this.observedBlendCompletions;
      if (resetRequestsChanged || blendActivationsChanged || regionActivationsChanged || blendCompletionsChanged) {
         this.observedMotionRepeatHistoryActivity = true;
         this.motionRepeatHistoryEpoch++;
         this.lastMotionRepeatHistoryInvalidationActiveTick = this.activeTicks;
      }
      this.observedResetRequestsTotal = this.latestResetRequestsTotal;
      this.observedBlendFullActivations = this.latestBlendFullActivations;
      this.observedBlendRegionActivations = this.latestBlendRegionActivations;
      this.observedBlendCompletions = this.latestBlendCompletions;
   }

   private int motionRepeatSettleTicksRequired() {
      if (!this.observedMotionRepeatHistoryActivity) {
         return this.motionRepeatSettleTicks;
      }
      return Math.max(this.motionRepeatSettleTicks, this.stableSceneSettleTicks);
   }

   private boolean isMotionRepeatHistorySettled() {
      return !this.latestGlobalLightReload
         && !this.latestWorldBuildWorkPending
         && ticksSinceLastMotionRepeatHistoryInvalidation() >= this.motionRepeatSettleTicksRequired();
   }

   private int motionRepeatHistoryEpoch() {
      return this.observedMotionRepeatHistoryActivity ? this.motionRepeatHistoryEpoch : 0;
   }

   private void refreshRuntimeState() {
      this.patchId = this.currentPatchId();
      this.expectedShaderPackMatched = ShaderAutomationValidators.matchesExpectedShaderPack(this.expectedShaderPack, Iris.getCurrentPackName());
      this.raytracerActive = Raytracer.INSTANCE != null && !Raytracer.isDisabled();
      if (!this.raytracerActive) {
         this.stableSceneTicks = 0;
         return;
      }

      WorldRegistry worldRegistry = Raytracer.INSTANCE.getWorldRegistry();
      if (worldRegistry == null) {
         this.stableSceneTicks = 0;
         return;
      }

      this.latestLightBlendFactor = worldRegistry.fetchLightBlendFactor();
      this.latestLightBlendRegionCount = worldRegistry.getLightBlendRegionCount();
      this.latestGlobalLightReload = worldRegistry.fetchLightReload();
      this.latestWorldBuildWorkPending = worldRegistry.hasPendingWork();
      this.latestResetRequestsTotal = worldRegistry.getAutomationResetRequestsTotal();
      this.latestResetRequestsWorldOffset = worldRegistry.getAutomationResetRequestsWorldOffset();
      this.latestResetRequestsTopology = worldRegistry.getAutomationResetRequestsTopology();
      this.latestResetRequestsOther = worldRegistry.getAutomationResetRequestsOther();
      this.latestBlendFullActivations = worldRegistry.getAutomationBlendFullActivations();
      this.latestBlendRegionActivations = worldRegistry.getAutomationBlendRegionActivations();
      this.latestBlendCompletions = worldRegistry.getAutomationBlendCompletions();
      this.latestFramesGlobalReloadActive = worldRegistry.getAutomationFramesGlobalReloadActive();
      this.latestFramesBlendActive = worldRegistry.getAutomationFramesBlendActive();
      this.latestFramesPendingWork = worldRegistry.getAutomationFramesPendingWork();
      this.latestCompileFramesLightWorkNeeded = worldRegistry.getAutomationCompileFramesLightWorkNeeded();
      this.latestCompileFramesLightCompiled = worldRegistry.getAutomationCompileFramesLightCompiled();
      this.latestCompileFramesWorldOffsetChanged = worldRegistry.getAutomationCompileFramesWorldOffsetChanged();
      this.latestCompileFramesChunkTopologyChanged = worldRegistry.getAutomationCompileFramesChunkTopologyChanged();
      this.latestCompileFramesChunkContentChanged = worldRegistry.getAutomationCompileFramesChunkContentChanged();
      this.latestCompileFramesTracedLightDirty = worldRegistry.getAutomationCompileFramesTracedLightDirty();
      this.latestPendingBlendMutationEvents = worldRegistry.getAutomationPendingBlendMutationEvents();
      this.latestMaxPendingBlendRegions = worldRegistry.getAutomationMaxPendingBlendRegions();
      this.latestMaxPendingBlendVolume = worldRegistry.getAutomationMaxPendingBlendVolume();
      this.observeMotionRepeatHistoryActivity();
      LightRegistry lightRegistry = worldRegistry.getLightRegistry();
      if (lightRegistry != null) {
         this.latestTracedLightCount = lightRegistry.lightCount();
         this.latestTotalLightCount = lightRegistry.totalLights();
         this.latestLightSelectionCapped = this.latestTotalLightCount > this.latestTracedLightCount;
      } else {
         this.latestTracedLightCount = 0;
         this.latestTotalLightCount = 0;
         this.latestLightSelectionCapped = false;
      }

      if (this.isStableSceneNow()) {
         this.stableSceneTicks++;
      } else {
         this.stableSceneTicks = 0;
      }
      this.detectFatalShaderFailure();
   }

   private void detectFatalShaderFailure() {
      if (this.finished) {
         return;
      }

      MinecraftClient client = MinecraftClient.getInstance();
      if (client == null) {
         return;
      }

      String failureMessage = this.readFatalShaderFailureMessage();
      if (failureMessage != null) {
         Photonic.warn("[Automation] {}", failureMessage);
         this.finish(failureMessage);
         this.scheduleFatalShutdown(client);
      }
   }

   private String readFatalShaderFailureMessage() {
      Path latestLog = Path.of("run/logs/latest.log");
      if (!Files.exists(latestLog)) {
         return null;
      }

      try {
         String logContent = Files.readString(latestLog);
         if (!logContent.contains("Failed to create shader rendering pipeline")
            && !logContent.contains("The shaderpack failed to load! Please report the error to the shader developer.")) {
            return null;
         }

         String compileReason = photonics$extractShaderCompileReason(logContent);
         return compileReason == null
            ? "Fatal shader compilation failure detected in latest.log"
            : "Fatal shader compilation failure: " + compileReason;
      } catch (IOException ignored) {
         return null;
      }
   }

   private static String photonics$extractShaderCompileReason(String logContent) {
      String[] lines = logContent.split("\\R");
      for (int i = lines.length - 1; i >= 0; i--) {
         String line = lines[i].trim();
         if (line.contains("ShaderCompileException")) {
            return line;
         }
      }

      for (int i = lines.length - 1; i >= 0; i--) {
         String line = lines[i].trim();
         if (line.contains("ERROR") && line.toLowerCase(Locale.ROOT).contains("shader")) {
            return line;
         }
      }

      return null;
   }

   private void scheduleFatalShutdown(MinecraftClient client) {
      if (client == null || !FATAL_SHADER_FAILURE_SCHEDULED.compareAndSet(false, true)) {
         return;
      }

      client.execute(client::scheduleStop);

      Thread shutdownThread = new Thread(() -> {
         try {
            Thread.sleep(250L);
         } catch (InterruptedException ignored) {
            Thread.currentThread().interrupt();
         }

         MinecraftClient liveClient = MinecraftClient.getInstance();
         if (liveClient != null) {
            liveClient.scheduleStop();
         }
      }, "Photonics-Automation-FatalShaderStop");
      shutdownThread.setDaemon(true);
      shutdownThread.start();
   }

   private void releaseAutomationMouse(MinecraftClient client) {
      if (this.releaseMouse && client.mouse != null) {
         client.mouse.unlockCursor();
      }
   }

   private void applyFullscreen(MinecraftClient client) {
      if (!this.fullscreen || this.fullscreenApplied) {
         return;
      }
      if (client.getWindow().isFullscreen()) {
         this.fullscreenApplied = true;
         return;
      }

      client.getWindow().toggleFullscreen();
      this.fullscreenApplied = client.getWindow().isFullscreen();
   }

   private void ensureGameplayScreen(MinecraftClient client) {
      Screen screen = client.currentScreen;
      if (screen == null) {
         this.recoveringFromScreen = false;
         return;
      }
      if (client.player == null || client.isPaused()) {
         if (!this.recoveringFromScreen) {
            Photonic.info("[Automation] clearing paused screen {}", screen.getClass().getSimpleName());
         }
         this.recoveringFromScreen = true;
         client.setScreen(null);
         return;
      }
      String screenName = screen.getClass().getName();
      if (!screenName.startsWith("net.minecraft.client.gui.screen.ChatScreen")) {
         if (!this.recoveringFromScreen) {
            Photonic.info("[Automation] clearing gameplay screen {}", screen.getClass().getSimpleName());
         }
         this.recoveringFromScreen = true;
         client.setScreen(null);
         return;
      }
      this.recoveringFromScreen = false;
   }

   private void recordFps() {
      long now = System.nanoTime();
      if (this.fpsCounterStartTime == 0L) {
         this.fpsCounterStartTime = now;
      }

      this.fpsFrameCount++;
      long elapsedNanos = now - this.fpsCounterStartTime;
      boolean shouldLogFps = this.fpsFrameCount >= 60 || elapsedNanos >= 1_000_000_000L;
      if (!shouldLogFps || elapsedNanos <= 0L) {
         return;
      }

      float elapsedSeconds = elapsedNanos / 1_000_000_000.0f;
      this.currentFps = this.fpsFrameCount / elapsedSeconds;
      this.minFps = Math.min(this.minFps, this.currentFps);
      this.maxFps = Math.max(this.maxFps, this.currentFps);
      this.avgFpsSum += this.currentFps;
      this.avgFpsCount++;
      Photonic.info(
         "[Profiler] FPS: current={} avg={} min={} max={}",
         formatFps(this.currentFps),
         formatFps(this.averageFps()),
         formatFps(this.minFps),
         formatFps(this.maxFps));
      this.fpsCounterStartTime = now;
      this.fpsFrameCount = 0;
   }

   private float averageFps() {
      return this.avgFpsCount == 0 ? 0.0f : this.avgFpsSum / this.avgFpsCount;
   }

   private static String formatFps(float fps) {
      return String.format(Locale.ROOT, "%.2f", fps);
   }

   private void queueBurstCaptures(int burstCaptureCount) {
      this.pendingBurstCaptures = Math.max(this.pendingBurstCaptures, burstCaptureCount);
   }

   private String currentPatchId() {
      String patchState = Raytracer.getAppliedPatch() == null ? "native" : "patched";
      return "REGIR_RESTIR:" + patchState;
   }

   private void finish(String failureReason) {
      if (this.finished) {
         return;
      }

      if (!failureReason.isBlank()) {
         this.failureReason = failureReason;
      }
      this.refreshRuntimeState();
      this.finished = true;
      Photonic.info("[Automation] finish success={} reason='{}' activeTicks={} renderedFrames={} captures={}/{} litCaptures={}/{} directSignal={} ticksSinceSignal={} thresholds(active>={} afterSignal>={}) fps(current={} avg={} min={} max={})",
         this.failureReason.isBlank() && this.buildSuccess(),
         this.failureReason.isBlank() ? "success" : this.failureReason,
         this.activeTicks,
         this.renderedFrames,
         this.capturesTaken,
         this.captureTarget,
         this.litCapturesTaken,
         this.minLitCaptures,
         this.directSignalDetected,
         ShaderAutomationValidators.activeTicksSinceFirstSignal(this.activeTicks, this.firstLightingSignalActiveTick),
         this.minActiveTicksBeforeSuccess,
         this.minActiveTicksAfterSignal,
         formatFps(this.currentFps),
         formatFps(this.averageFps()),
         formatFps(this.minFps == Float.MAX_VALUE ? 0.0f : this.minFps),
         formatFps(this.maxFps));
      this.writeReport(true);
      if (this.autoStop) {
         MinecraftClient.getInstance().scheduleStop();
      }
   }

   private void writeReport(boolean finalWrite) {
      try {
         if (this.reportFile.getParent() != null) {
            Files.createDirectories(this.reportFile.getParent());
         }

         Properties props = new Properties();
         boolean success = finalWrite && this.buildSuccess();
         String finalFailureReason = this.failureReason;
         if (finalWrite && !success && finalFailureReason.isBlank()) {
            finalFailureReason = this.defaultFailureReason();
         }
         if (!finalWrite && finalFailureReason.isBlank()) {
            finalFailureReason = "Automation still running";
         }

         props.setProperty("worldName", this.worldName);
         props.setProperty("autoStartWorld", Boolean.toString(this.autoStartWorld));
         props.setProperty("ticksElapsed", Integer.toString(this.ticksElapsed));
         props.setProperty("activeTicks", Integer.toString(this.activeTicks));
         props.setProperty("renderedFrames", Integer.toString(this.renderedFrames));
         props.setProperty("fullscreen", Boolean.toString(this.fullscreen));
         props.setProperty("fullscreenApplied", Boolean.toString(this.fullscreenApplied));
         props.setProperty("currentFps", Float.toString(this.currentFps));
         props.setProperty("minFps", Float.toString(this.minFps == Float.MAX_VALUE ? 0.0f : this.minFps));
         props.setProperty("maxFps", Float.toString(this.maxFps));
         props.setProperty("avgFps", Float.toString(this.averageFps()));
         props.setProperty("capturesTaken", Integer.toString(this.capturesTaken));
         props.setProperty("litCapturesTaken", Integer.toString(this.litCapturesTaken));
         props.setProperty("captureTarget", Integer.toString(this.captureTarget));
         props.setProperty("minLitCaptures", Integer.toString(this.minLitCaptures));
         props.setProperty("minActiveTicksBeforeSuccess", Integer.toString(this.minActiveTicksBeforeSuccess));
         props.setProperty("minActiveTicksAfterSignal", Integer.toString(this.minActiveTicksAfterSignal));
         props.setProperty("captureEveryActiveTicks", Integer.toString(this.captureEveryActiveTicks));
         props.setProperty("releaseMouse", Boolean.toString(this.releaseMouse));
         props.setProperty("requireDirectSignal", Boolean.toString(this.requireDirectSignal));
         props.setProperty("firstLightingSignalActiveTick", Integer.toString(this.firstLightingSignalActiveTick));
         props.setProperty("activeTicksSinceFirstSignal", Integer.toString(ShaderAutomationValidators.activeTicksSinceFirstSignal(this.activeTicks, this.firstLightingSignalActiveTick)));
         props.setProperty("cameraMotionMode", this.cameraController.getCameraMotionMode());
         props.setProperty("cameraMotionStartActiveTick", Integer.toString(this.cameraController.getCameraMotionStartActiveTick()));
         props.setProperty("cameraMotionPeriodTicks", Integer.toString(this.cameraController.getCameraMotionPeriodTicks()));
         props.setProperty("cameraYawAmplitudeDegrees", Float.toString(this.cameraController.getCameraYawAmplitudeDegrees()));
         props.setProperty("cameraPitchAmplitudeDegrees", Float.toString(this.cameraController.getCameraPitchAmplitudeDegrees()));
         props.setProperty("cameraMotionAppliedTicks", Integer.toString(this.cameraController.getCameraMotionAppliedTicks()));
         props.setProperty("cameraMotionStopActiveTick", Integer.toString(this.cameraMotionStopActiveTick));
         props.setProperty("motionRepeatSettleTicks", Integer.toString(this.motionRepeatSettleTicks));
         props.setProperty("worldPrepActiveTick", Integer.toString(this.worldController.getWorldPrepActiveTick()));
         props.setProperty("worldAutomationPrepared", Boolean.toString(this.worldController.isWorldAutomationPrepared()));
         props.setProperty("stableSceneSettleTicks", Integer.toString(this.stableSceneSettleTicks));
         props.setProperty("stableSceneTicks", Integer.toString(this.stableSceneTicks));
         props.setProperty("stableSceneSatisfied", Boolean.toString(this.stableSceneSatisfied()));
         props.setProperty("stableSceneBlendRegionThreshold", Integer.toString(this.stableSceneBlendRegionThreshold));
         props.setProperty("stableSceneBlendFactorThreshold", Double.toString(this.stableSceneBlendFactorThreshold));
         props.setProperty("timeOfDaySequenceLength", Integer.toString(this.worldController.getTimeOfDaySequence().length));
         props.setProperty("timeOfDayStartActiveTick", Integer.toString(this.worldController.getTimeOfDayStartActiveTick()));
         props.setProperty("timeOfDayStepTicks", Integer.toString(this.worldController.getTimeOfDayStepTicks()));
         props.setProperty("timeOfDayCommandsIssued", Integer.toString(this.worldController.getTimeOfDayCommandsIssued()));
         props.setProperty("blockToggleStartActiveTick", Integer.toString(this.worldController.getBlockToggleStartActiveTick()));
         props.setProperty("blockTogglePeriodTicks", Integer.toString(this.worldController.getBlockTogglePeriodTicks()));
         props.setProperty("blockToggleCount", Integer.toString(this.worldController.getBlockToggleCount()));
         props.setProperty("blockToggleCommandsIssued", Integer.toString(this.worldController.getBlockToggleCommandsIssued()));
         props.setProperty("motionYawOffsetMin", Float.toString(this.cameraController.getMotionYawOffsetMin()));
         props.setProperty("motionYawOffsetMax", Float.toString(this.cameraController.getMotionYawOffsetMax()));
         props.setProperty("motionPitchOffsetMin", Float.toString(this.cameraController.getMotionPitchOffsetMin()));
         props.setProperty("motionPitchOffsetMax", Float.toString(this.cameraController.getMotionPitchOffsetMax()));
         props.setProperty("success", Boolean.toString(success));
         props.setProperty("failureReason", finalFailureReason);
         props.setProperty("shaderPackName", this.shaderPackName);
         props.setProperty("expectedShaderPack", this.expectedShaderPack);
         props.setProperty("expectedShaderPackMatched", Boolean.toString(this.expectedShaderPackMatched));
         props.setProperty("expectedPatchIdPrefix", this.expectedPatchIdPrefix);
         props.setProperty("patchIdMatches", Boolean.toString(this.patchIdMatches()));
         props.setProperty("raytracerActive", Boolean.toString(this.raytracerActive));
         props.setProperty("directSignalDetected", Boolean.toString(this.directSignalDetected));
         props.setProperty("lightingSignalDetected", Boolean.toString(this.lightingSignalDetected));
         props.setProperty("directMaxLuma", Double.toString(this.metrics.directMaxLuma));
         props.setProperty("directSoftMaxLuma", Double.toString(this.metrics.directSoftMaxLuma));
         props.setProperty("directDenoisedMaxLuma", Double.toString(this.metrics.directDenoisedMaxLuma));
         props.setProperty("directRawMaxLuma", Double.toString(this.metrics.directRawMaxLuma));
         props.setProperty("lightingBufferMaxLuma", Double.toString(this.metrics.lightingBufferMaxLuma));
         props.setProperty("stageLightingMaxLuma", Double.toString(this.metrics.stageLightingMaxLuma));
         props.setProperty("stageIndirectMaxLuma", Double.toString(this.metrics.stageIndirectMaxLuma));
         props.setProperty("handheldMaxLuma", Double.toString(this.metrics.handheldMaxLuma));
         props.setProperty("indirectRawMaxLuma", Double.toString(this.metrics.indirectRawMaxLuma));
         props.setProperty("indirectMaxLuma", Double.toString(this.metrics.indirectMaxLuma));
         props.setProperty("finalCaptureIndex", Integer.toString(this.latestFinalCaptureIndex));
         props.setProperty("finalFrameMaxLuma", Double.toString(this.finalFrameMaxLuma));
         props.setProperty("latestFinalMeanLuma", Double.toString(this.latestFinalMeanLuma));
         props.setProperty("latestFinalMeanRed", Double.toString(this.latestFinalMeanRed));
         props.setProperty("latestFinalMeanGreen", Double.toString(this.latestFinalMeanGreen));
         props.setProperty("latestFinalMeanBlue", Double.toString(this.latestFinalMeanBlue));
         props.setProperty("finalSignalDetected", Boolean.toString(this.finalSignalDetected));
         props.setProperty("latestDirectMeanLuma", Double.toString(this.metrics.latestDirectMeanLuma));
         props.setProperty("latestDirectDenoisedMeanLuma", Double.toString(this.metrics.latestDirectDenoisedMeanLuma));
         props.setProperty("latestDirectRawMeanLuma", Double.toString(this.metrics.latestDirectRawMeanLuma));
         props.setProperty("latestDirectRawLinearMeanLuma", Double.toString(this.metrics.latestDirectRawLinearMeanLuma));
         props.setProperty("latestDirectRawLinearMaxLuma", Double.toString(this.metrics.latestDirectRawLinearMaxLuma));
         props.setProperty("latestDirectRawLinearOverbrightFraction", Double.toString(this.metrics.latestDirectRawLinearOverbrightFraction));
         props.setProperty("latestDirectRawLinearFireflyFraction", Double.toString(this.metrics.latestDirectRawLinearFireflyFraction));
         props.setProperty("latestDirectRawLinearSevereFireflyFraction", Double.toString(this.metrics.latestDirectRawLinearSevereFireflyFraction));
         props.setProperty("latestDirectRawLinearFireflyLumaShare", Double.toString(this.metrics.latestDirectRawLinearFireflyLumaShare));
         props.setProperty("latestDirectRawLinearSaturatedPixelFraction", Double.toString(this.metrics.latestDirectRawLinearSaturatedPixelFraction));
         props.setProperty("latestDirectRawLinearNonFiniteFraction", Double.toString(this.metrics.latestDirectRawLinearNonFiniteFraction));
         props.setProperty("latestDirectDenoisedLinearMeanLuma", Double.toString(this.metrics.latestDirectDenoisedLinearMeanLuma));
         props.setProperty("latestDirectDenoisedLinearMaxLuma", Double.toString(this.metrics.latestDirectDenoisedLinearMaxLuma));
         props.setProperty("latestDirectDenoisedLinearOverbrightFraction", Double.toString(this.metrics.latestDirectDenoisedLinearOverbrightFraction));
         props.setProperty("latestDirectDenoisedLinearFireflyFraction", Double.toString(this.metrics.latestDirectDenoisedLinearFireflyFraction));
         props.setProperty("latestDirectDenoisedLinearSevereFireflyFraction", Double.toString(this.metrics.latestDirectDenoisedLinearSevereFireflyFraction));
         props.setProperty("latestDirectDenoisedLinearFireflyLumaShare", Double.toString(this.metrics.latestDirectDenoisedLinearFireflyLumaShare));
         props.setProperty("latestDirectDenoisedLinearSaturatedPixelFraction", Double.toString(this.metrics.latestDirectDenoisedLinearSaturatedPixelFraction));
         props.setProperty("latestDirectDenoisedLinearNonFiniteFraction", Double.toString(this.metrics.latestDirectDenoisedLinearNonFiniteFraction));
         props.setProperty("latestLightingMeanLuma", Double.toString(this.metrics.latestLightingMeanLuma));
         props.setProperty("latestStageLightingMeanLuma", Double.toString(this.metrics.latestStageLightingMeanLuma));
         props.setProperty("latestStageIndirectMeanLuma", Double.toString(this.metrics.latestStageIndirectMeanLuma));
         props.setProperty("latestIndirectRawMeanLuma", Double.toString(this.metrics.latestIndirectRawMeanLuma));
         props.setProperty("latestIndirectMeanLuma", Double.toString(this.metrics.latestIndirectMeanLuma));
         props.setProperty("latestSpecRawLinearMeanLuma", Double.toString(this.metrics.latestSpecRawLinearMeanLuma));
         props.setProperty("latestSpecRawLinearMaxLuma", Double.toString(this.metrics.latestSpecRawLinearMaxLuma));
         props.setProperty("latestSpecRawLinearOverbrightFraction", Double.toString(this.metrics.latestSpecRawLinearOverbrightFraction));
         props.setProperty("latestSpecRawLinearFireflyFraction", Double.toString(this.metrics.latestSpecRawLinearFireflyFraction));
         props.setProperty("latestSpecRawLinearSevereFireflyFraction", Double.toString(this.metrics.latestSpecRawLinearSevereFireflyFraction));
         props.setProperty("latestSpecRawLinearFireflyLumaShare", Double.toString(this.metrics.latestSpecRawLinearFireflyLumaShare));
         props.setProperty("latestSpecRawLinearSaturatedPixelFraction", Double.toString(this.metrics.latestSpecRawLinearSaturatedPixelFraction));
         props.setProperty("latestSpecRawLinearNonFiniteFraction", Double.toString(this.metrics.latestSpecRawLinearNonFiniteFraction));
         props.setProperty("latestSpecDenoisedLinearMeanLuma", Double.toString(this.metrics.latestSpecDenoisedLinearMeanLuma));
         props.setProperty("latestSpecDenoisedLinearMaxLuma", Double.toString(this.metrics.latestSpecDenoisedLinearMaxLuma));
         props.setProperty("latestSpecDenoisedLinearOverbrightFraction", Double.toString(this.metrics.latestSpecDenoisedLinearOverbrightFraction));
         props.setProperty("latestSpecDenoisedLinearFireflyFraction", Double.toString(this.metrics.latestSpecDenoisedLinearFireflyFraction));
         props.setProperty("latestSpecDenoisedLinearSevereFireflyFraction", Double.toString(this.metrics.latestSpecDenoisedLinearSevereFireflyFraction));
         props.setProperty("latestSpecDenoisedLinearFireflyLumaShare", Double.toString(this.metrics.latestSpecDenoisedLinearFireflyLumaShare));
         props.setProperty("latestSpecDenoisedLinearSaturatedPixelFraction", Double.toString(this.metrics.latestSpecDenoisedLinearSaturatedPixelFraction));
         props.setProperty("latestSpecDenoisedLinearNonFiniteFraction", Double.toString(this.metrics.latestSpecDenoisedLinearNonFiniteFraction));
         props.setProperty("latestIndirectRawLinearMeanLuma", Double.toString(this.metrics.latestIndirectRawLinearMeanLuma));
         props.setProperty("latestIndirectRawLinearMaxLuma", Double.toString(this.metrics.latestIndirectRawLinearMaxLuma));
         props.setProperty("latestIndirectRawLinearOverbrightFraction", Double.toString(this.metrics.latestIndirectRawLinearOverbrightFraction));
         props.setProperty("latestIndirectRawLinearFireflyFraction", Double.toString(this.metrics.latestIndirectRawLinearFireflyFraction));
         props.setProperty("latestIndirectRawLinearSevereFireflyFraction", Double.toString(this.metrics.latestIndirectRawLinearSevereFireflyFraction));
         props.setProperty("latestIndirectRawLinearFireflyLumaShare", Double.toString(this.metrics.latestIndirectRawLinearFireflyLumaShare));
         props.setProperty("latestIndirectRawLinearSaturatedPixelFraction", Double.toString(this.metrics.latestIndirectRawLinearSaturatedPixelFraction));
         props.setProperty("latestIndirectRawLinearNonFiniteFraction", Double.toString(this.metrics.latestIndirectRawLinearNonFiniteFraction));
         props.setProperty("latestIndirectLinearMeanLuma", Double.toString(this.metrics.latestIndirectLinearMeanLuma));
         props.setProperty("latestIndirectLinearMaxLuma", Double.toString(this.metrics.latestIndirectLinearMaxLuma));
         props.setProperty("latestIndirectLinearOverbrightFraction", Double.toString(this.metrics.latestIndirectLinearOverbrightFraction));
         props.setProperty("latestIndirectLinearFireflyFraction", Double.toString(this.metrics.latestIndirectLinearFireflyFraction));
         props.setProperty("latestIndirectLinearSevereFireflyFraction", Double.toString(this.metrics.latestIndirectLinearSevereFireflyFraction));
         props.setProperty("latestIndirectLinearFireflyLumaShare", Double.toString(this.metrics.latestIndirectLinearFireflyLumaShare));
         props.setProperty("latestIndirectLinearSaturatedPixelFraction", Double.toString(this.metrics.latestIndirectLinearSaturatedPixelFraction));
         props.setProperty("latestIndirectLinearNonFiniteFraction", Double.toString(this.metrics.latestIndirectLinearNonFiniteFraction));
         props.setProperty("latestStageIndirectLinearMeanLuma", Double.toString(this.metrics.latestStageIndirectLinearMeanLuma));
         props.setProperty("latestStageIndirectLinearMaxLuma", Double.toString(this.metrics.latestStageIndirectLinearMaxLuma));
         props.setProperty("latestStageIndirectLinearOverbrightFraction", Double.toString(this.metrics.latestStageIndirectLinearOverbrightFraction));
         props.setProperty("latestDirectMeanRed", Double.toString(this.metrics.latestDirectMeanRed));
         props.setProperty("latestDirectMeanGreen", Double.toString(this.metrics.latestDirectMeanGreen));
         props.setProperty("latestDirectMeanBlue", Double.toString(this.metrics.latestDirectMeanBlue));
         props.setProperty("latestDirectMeanAlpha", Double.toString(this.metrics.latestDirectMeanAlpha));
         props.setProperty("latestDirectZeroAlphaFraction", Double.toString(this.metrics.latestDirectZeroAlphaFraction));
         props.setProperty("latestDirectAlphaDelta", Double.toString(this.metrics.latestDirectAlphaDelta));
         props.setProperty("directAlphaDeltaAvg", Double.toString(this.metrics.averageDirectAlphaDelta()));
         props.setProperty("directAlphaDeltaMax", Double.toString(this.metrics.directAlphaDeltaMax));
         props.setProperty("latestDirectBrightnessVariance", Double.toString(this.metrics.latestDirectBrightnessVariance));
         props.setProperty("latestDirectBrightnessStdDev", Double.toString(this.metrics.latestDirectBrightnessStdDev));
         props.setProperty("directBrightnessVarianceAvg", Double.toString(this.metrics.averageDirectBrightnessVariance()));
         props.setProperty("directBrightnessVarianceMax", Double.toString(this.metrics.directBrightnessVarianceMax));
         props.setProperty("latestHandheldBrightnessVariance", Double.toString(this.metrics.latestHandheldBrightnessVariance));
         props.setProperty("latestHandheldBrightnessStdDev", Double.toString(this.metrics.latestHandheldBrightnessStdDev));
         props.setProperty("handheldBrightnessVarianceAvg", Double.toString(this.metrics.averageHandheldBrightnessVariance()));
         props.setProperty("handheldBrightnessVarianceMax", Double.toString(this.metrics.handheldBrightnessVarianceMax));
         props.setProperty("latestLightingMeanRed", Double.toString(this.metrics.latestLightingMeanRed));
         props.setProperty("latestLightingMeanGreen", Double.toString(this.metrics.latestLightingMeanGreen));
         props.setProperty("latestLightingMeanBlue", Double.toString(this.metrics.latestLightingMeanBlue));
         props.setProperty("latestStageLightingMeanRed", Double.toString(this.metrics.latestStageLightingMeanRed));
         props.setProperty("latestStageLightingMeanGreen", Double.toString(this.metrics.latestStageLightingMeanGreen));
         props.setProperty("latestStageLightingMeanBlue", Double.toString(this.metrics.latestStageLightingMeanBlue));
         props.setProperty("latestStageIndirectMeanRed", Double.toString(this.metrics.latestStageIndirectMeanRed));
         props.setProperty("latestStageIndirectMeanGreen", Double.toString(this.metrics.latestStageIndirectMeanGreen));
         props.setProperty("latestStageIndirectMeanBlue", Double.toString(this.metrics.latestStageIndirectMeanBlue));
         props.setProperty("latestIndirectMeanRed", Double.toString(this.metrics.latestIndirectMeanRed));
         props.setProperty("latestIndirectMeanGreen", Double.toString(this.metrics.latestIndirectMeanGreen));
         props.setProperty("latestIndirectMeanBlue", Double.toString(this.metrics.latestIndirectMeanBlue));
         props.setProperty("latestIndirectMeanAlpha", Double.toString(this.metrics.latestIndirectMeanAlpha));
         props.setProperty("latestIndirectZeroAlphaFraction", Double.toString(this.metrics.latestIndirectZeroAlphaFraction));
         props.setProperty("latestStageIndirectMeanAlpha", Double.toString(this.metrics.latestStageIndirectMeanAlpha));
         props.setProperty("latestStageIndirectZeroAlphaFraction", Double.toString(this.metrics.latestStageIndirectZeroAlphaFraction));
         props.setProperty("latestTracedLightCount", Integer.toString(this.latestTracedLightCount));
         props.setProperty("latestTotalLightCount", Integer.toString(this.latestTotalLightCount));
         props.setProperty("maxTracedLightCount", Integer.toString(this.maxTracedLightCount));
         props.setProperty("maxTotalLightCount", Integer.toString(this.maxTotalLightCount));
         props.setProperty("latestLightSelectionCapped", Boolean.toString(this.latestLightSelectionCapped));
         props.setProperty("lightSelectionCappedCaptures", Integer.toString(this.lightSelectionCappedCaptures));
         props.setProperty("latestLightBlendFactor", Double.toString(this.latestLightBlendFactor));
         props.setProperty("latestLightBlendRegionCount", Integer.toString(this.latestLightBlendRegionCount));
         props.setProperty("latestGlobalLightReload", Boolean.toString(this.latestGlobalLightReload));
         props.setProperty("latestWorldBuildWorkPending", Boolean.toString(this.latestWorldBuildWorkPending));
         props.setProperty("latestResetRequestsTotal", Long.toString(this.latestResetRequestsTotal));
         props.setProperty("latestResetRequestsWorldOffset", Long.toString(this.latestResetRequestsWorldOffset));
         props.setProperty("latestResetRequestsTopology", Long.toString(this.latestResetRequestsTopology));
         props.setProperty("latestResetRequestsOther", Long.toString(this.latestResetRequestsOther));
         props.setProperty("latestBlendFullActivations", Long.toString(this.latestBlendFullActivations));
         props.setProperty("latestBlendRegionActivations", Long.toString(this.latestBlendRegionActivations));
         props.setProperty("latestBlendCompletions", Long.toString(this.latestBlendCompletions));
         props.setProperty("latestFramesGlobalReloadActive", Long.toString(this.latestFramesGlobalReloadActive));
         props.setProperty("latestFramesBlendActive", Long.toString(this.latestFramesBlendActive));
         props.setProperty("latestFramesPendingWork", Long.toString(this.latestFramesPendingWork));
         props.setProperty("latestCompileFramesLightWorkNeeded", Long.toString(this.latestCompileFramesLightWorkNeeded));
         props.setProperty("latestCompileFramesLightCompiled", Long.toString(this.latestCompileFramesLightCompiled));
         props.setProperty("latestCompileFramesWorldOffsetChanged", Long.toString(this.latestCompileFramesWorldOffsetChanged));
         props.setProperty("latestCompileFramesChunkTopologyChanged", Long.toString(this.latestCompileFramesChunkTopologyChanged));
         props.setProperty("latestCompileFramesChunkContentChanged", Long.toString(this.latestCompileFramesChunkContentChanged));
         props.setProperty("latestCompileFramesTracedLightDirty", Long.toString(this.latestCompileFramesTracedLightDirty));
         props.setProperty("latestPendingBlendMutationEvents", Long.toString(this.latestPendingBlendMutationEvents));
         props.setProperty("latestMaxPendingBlendRegions", Integer.toString(this.latestMaxPendingBlendRegions));
         props.setProperty("latestMaxPendingBlendVolume", Long.toString(this.latestMaxPendingBlendVolume));
         props.setProperty("globalLightReloadCaptures", Integer.toString(this.globalLightReloadCaptures));
         props.setProperty("directSoftSignalDetected", Boolean.toString(this.metrics.directSoftSignalDetected));
         props.setProperty("directSoftSignalCaptureCount", Integer.toString(this.metrics.directSoftSignalCaptureCount));
         props.setProperty("directSoftZeroCaptureCount", Integer.toString(this.metrics.directSoftZeroCaptureCount));
         props.setProperty("directSoftMissingSignalWarningIssued", Boolean.toString(this.metrics.directSoftMissingSignalWarningIssued));
         props.setProperty("latestDirectTemporalDelta", Double.toString(this.metrics.latestDirectTemporalDelta));
         props.setProperty("directTemporalDeltaAvg", Double.toString(this.metrics.averageTemporalDelta(false, false)));
         props.setProperty("directTemporalDeltaMax", Double.toString(this.metrics.directTemporalDeltaMax));
         props.setProperty("latestDirectTemporalMaxPixelDelta", Double.toString(this.metrics.latestDirectTemporalMaxPixelDelta));
         props.setProperty("directTemporalMaxPixelDeltaAvg", Double.toString(this.metrics.averageDirectTemporalMaxPixelDelta()));
         props.setProperty("directTemporalMaxPixelDeltaMax", Double.toString(this.metrics.directTemporalMaxPixelDeltaMax));
         props.setProperty("latestWholeLightFlashDirectDrop", Double.toString(this.metrics.latestWholeLightFlashDirectDrop));
         props.setProperty("latestWholeLightFlashResolvedValidDrop", Double.toString(this.metrics.latestWholeLightFlashResolvedValidDrop));
         props.setProperty("latestWholeLightFlashLightCountDrop", Double.toString(this.metrics.latestWholeLightFlashLightCountDrop));
         props.setProperty("latestWholeLightFlashResolvedMDrop", Double.toString(this.metrics.latestWholeLightFlashResolvedMDrop));
         props.setProperty("latestWholeLightFlashBlendFactorJump", Double.toString(this.metrics.latestWholeLightFlashBlendFactorJump));
         props.setProperty("maxWholeLightFlashDirectDrop", Double.toString(this.metrics.maxWholeLightFlashDirectDrop));
         props.setProperty("maxWholeLightFlashResolvedValidDrop", Double.toString(this.metrics.maxWholeLightFlashResolvedValidDrop));
         props.setProperty("maxWholeLightFlashLightCountDrop", Double.toString(this.metrics.maxWholeLightFlashLightCountDrop));
         props.setProperty("maxWholeLightFlashResolvedMDrop", Double.toString(this.metrics.maxWholeLightFlashResolvedMDrop));
         props.setProperty("maxWholeLightFlashBlendFactorJump", Double.toString(this.metrics.maxWholeLightFlashBlendFactorJump));
         props.setProperty("wholeLightFlashSuspectCaptures", Integer.toString(this.metrics.wholeLightFlashSuspectCaptures));
         props.setProperty("wholeLightFlashLastCapture", Integer.toString(this.metrics.wholeLightFlashLastCapture));
         props.setProperty("wholeLightFlashDirectDropCaptures", Integer.toString(this.metrics.wholeLightFlashDirectDropCaptures));
         props.setProperty("wholeLightFlashResolvedValidDropCaptures", Integer.toString(this.metrics.wholeLightFlashResolvedValidDropCaptures));
         props.setProperty("wholeLightFlashLightCountDropCaptures", Integer.toString(this.metrics.wholeLightFlashLightCountDropCaptures));
         props.setProperty("wholeLightFlashBlendJumpCaptures", Integer.toString(this.metrics.wholeLightFlashBlendJumpCaptures));
         props.setProperty("previousCaptureResolvedMeanWeight", Double.toString(this.metrics.previousCaptureResolvedMeanWeight));
         props.setProperty("previousCaptureResolvedMeanM", Double.toString(this.metrics.previousCaptureResolvedMeanM));
         props.setProperty("previousCaptureResolvedStrictValidFraction", Double.toString(this.metrics.previousCaptureResolvedStrictValidFraction));
         props.setProperty("latestResolvedMeanM", Double.toString(this.metrics.latestResolvedMeanM));
         props.setProperty("previousCaptureDirectMeanLuma", Double.toString(this.metrics.previousCaptureDirectMeanLuma));
         props.setProperty("previousCaptureLightBlendFactor", Double.toString(this.metrics.previousCaptureLightBlendFactor));
         props.setProperty("previousCaptureTracedLightCount", Integer.toString(this.metrics.previousCaptureTracedLightCount));
         props.setProperty("latestDirectSoftTemporalDelta", Double.toString(this.metrics.latestDirectSoftTemporalDelta));
         props.setProperty("directSoftTemporalDeltaAvg", Double.toString(this.metrics.averageTemporalDelta(true, false)));
         props.setProperty("directSoftTemporalDeltaMax", Double.toString(this.metrics.directSoftTemporalDeltaMax));
         props.setProperty("indirectTemporalDeltaAvg", Double.toString(this.metrics.averageTemporalDelta(false, true)));
         props.setProperty("indirectTemporalDeltaMax", Double.toString(this.metrics.indirectTemporalDeltaMax));
         props.setProperty("latestDirectDenoiserGain", Double.toString(this.metrics.latestDirectDenoiserGain));
         props.setProperty("latestSpecDenoiserGain", Double.toString(this.metrics.latestSpecDenoiserGain));
         props.setProperty("latestIndirectResolveGain", Double.toString(this.metrics.latestIndirectResolveGain));
         props.setProperty("directDenoiserGainAvg", Double.toString(this.metrics.directDenoiserGainSamples == 0 ? 0.0 : this.metrics.directDenoiserGainSum / this.metrics.directDenoiserGainSamples));
         props.setProperty("directDenoiserGainMax", Double.toString(this.metrics.directDenoiserGainMax));
         props.setProperty("specDenoiserGainAvg", Double.toString(this.metrics.specDenoiserGainSamples == 0 ? 0.0 : this.metrics.specDenoiserGainSum / this.metrics.specDenoiserGainSamples));
         props.setProperty("specDenoiserGainMax", Double.toString(this.metrics.specDenoiserGainMax));
         props.setProperty("indirectResolveGainAvg", Double.toString(this.metrics.indirectResolveGainSamples == 0 ? 0.0 : this.metrics.indirectResolveGainSum / this.metrics.indirectResolveGainSamples));
         props.setProperty("indirectResolveGainMax", Double.toString(this.metrics.indirectResolveGainMax));
         props.setProperty("postMotionDropSamples", Integer.toString(this.metrics.postMotionDropSamples));
         props.setProperty("postMotionDirectMeanAtStop", Double.toString(this.metrics.postMotionDirectMeanAtStop));
         props.setProperty("postMotionRawDirectMeanAtStop", Double.toString(this.metrics.postMotionRawDirectMeanAtStop));
         props.setProperty("postMotionIndirectMeanAtStop", Double.toString(this.metrics.postMotionIndirectMeanAtStop));
         props.setProperty("postMotionStageIndirectMeanAtStop", Double.toString(this.metrics.postMotionStageIndirectMeanAtStop));
         props.setProperty("latestPostMotionDirectDrop", Double.toString(this.metrics.latestPostMotionDirectDrop));
         props.setProperty("latestPostMotionRawDirectDrop", Double.toString(this.metrics.latestPostMotionRawDirectDrop));
         props.setProperty("latestPostMotionIndirectDrop", Double.toString(this.metrics.latestPostMotionIndirectDrop));
         props.setProperty("latestPostMotionStageIndirectDrop", Double.toString(this.metrics.latestPostMotionStageIndirectDrop));
         props.setProperty("postMotionDirectDropAvg", Double.toString(this.metrics.postMotionDropSamples == 0 ? 0.0 : this.metrics.postMotionDirectDropSum / this.metrics.postMotionDropSamples));
         props.setProperty("postMotionRawDirectDropAvg", Double.toString(this.metrics.postMotionDropSamples == 0 ? 0.0 : this.metrics.postMotionRawDirectDropSum / this.metrics.postMotionDropSamples));
         props.setProperty("postMotionIndirectDropAvg", Double.toString(this.metrics.postMotionDropSamples == 0 ? 0.0 : this.metrics.postMotionIndirectDropSum / this.metrics.postMotionDropSamples));
         props.setProperty("postMotionStageIndirectDropAvg", Double.toString(this.metrics.postMotionDropSamples == 0 ? 0.0 : this.metrics.postMotionStageIndirectDropSum / this.metrics.postMotionDropSamples));
         props.setProperty("postMotionDirectDropMax", Double.toString(this.metrics.postMotionDirectDropMax));
         props.setProperty("postMotionRawDirectDropMax", Double.toString(this.metrics.postMotionRawDirectDropMax));
         props.setProperty("postMotionIndirectDropMax", Double.toString(this.metrics.postMotionIndirectDropMax));
         props.setProperty("postMotionStageIndirectDropMax", Double.toString(this.metrics.postMotionStageIndirectDropMax));
         props.setProperty("motionRepeatDirectDeltaAvg", Double.toString(this.metrics.averageMotionRepeatDelta(true)));
         props.setProperty("motionRepeatDirectDeltaMax", Double.toString(this.metrics.motionRepeatDirectDeltaMax));
         props.setProperty("motionRepeatDirectDeltaSamples", Integer.toString(this.metrics.motionRepeatDirectDeltaSamples));
         props.setProperty("motionRepeatIndirectDeltaAvg", Double.toString(this.metrics.averageMotionRepeatDelta(false)));
         props.setProperty("motionRepeatIndirectDeltaMax", Double.toString(this.metrics.motionRepeatIndirectDeltaMax));
         props.setProperty("motionRepeatIndirectDeltaSamples", Integer.toString(this.metrics.motionRepeatIndirectDeltaSamples));
         props.setProperty("motionRepeatDirectTopDeltas", ShaderAutomationFrameMetrics.formatRepeatDeltaDiagnostics(this.metrics.topDirectRepeatDeltas));
         props.setProperty("motionRepeatIndirectTopDeltas", ShaderAutomationFrameMetrics.formatRepeatDeltaDiagnostics(this.metrics.topIndirectRepeatDeltas));
         props.setProperty("maxMotionRepeatDirectDeltaAvg", Double.toString(this.maxMotionRepeatDirectDeltaAvg));
         props.setProperty("maxMotionRepeatDirectDeltaMax", Double.toString(this.maxMotionRepeatDirectDeltaMax));
         props.setProperty("maxMotionRepeatIndirectDeltaAvg", Double.toString(this.maxMotionRepeatIndirectDeltaAvg));
         props.setProperty("maxMotionRepeatIndirectDeltaMax", Double.toString(this.maxMotionRepeatIndirectDeltaMax));
         props.setProperty("maxDirectTemporalDeltaAvg", Double.toString(this.maxDirectTemporalDeltaAvg));
         props.setProperty("maxDirectTemporalDeltaMax", Double.toString(this.maxDirectTemporalDeltaMax));
         props.setProperty("maxIndirectTemporalDeltaAvg", Double.toString(this.maxIndirectTemporalDeltaAvg));
         props.setProperty("maxIndirectTemporalDeltaMax", Double.toString(this.maxIndirectTemporalDeltaMax));
         props.setProperty("maxIndirectLinearOverbrightFraction", Double.toString(this.maxIndirectLinearOverbrightFraction));
         props.setProperty("maxIndirectLinearSevereFireflyFraction", Double.toString(this.maxIndirectLinearSevereFireflyFraction));
         props.setProperty("maxIndirectRawLinearOverbrightFraction", Double.toString(this.maxIndirectRawLinearOverbrightFraction));
         props.setProperty("patchId", this.patchId);

         try (OutputStream outputStream = Files.newOutputStream(this.reportFile)) {
            props.store(outputStream, null);
         }
      } catch (IOException e) {
         Photonic.error("Failed to write shader automation report", e);
      }
   }

   private boolean stableSceneSatisfied() {
      return this.stableSceneTicks >= this.stableSceneSettleTicks;
   }

   private boolean shouldSuppressWorldMutationIngress() {
      return Boolean.getBoolean("photonics.automation.suppressWorldMutationIngress")
         && this.worldController.isWorldAutomationPrepared()
         && this.activeTicks >= this.startDelayTicks
         && !this.finished;
   }

   private boolean isStableSceneNow() {
      return !this.latestGlobalLightReload
         && this.latestLightBlendRegionCount <= this.stableSceneBlendRegionThreshold
         && this.latestLightBlendFactor <= this.stableSceneBlendFactorThreshold;
   }

   private boolean buildSuccess() {
      return this.failureReason.isBlank()
         && this.expectedShaderPackMatched
         && this.patchIdMatches()
         && this.raytracerActive
         && this.stableSceneSatisfied()
         && (!this.requireDirectSignal || this.directSignalDetected)
         && this.directSoftSignalSatisfied()
         && this.worldAutomationSatisfied()
         && this.motionRepeatValidationSatisfied()
         && this.qualityThresholdsSatisfied()
         && ShaderAutomationValidators.isCompletionSatisfied(
            this.capturesTaken,
            this.captureTarget,
            this.litCapturesTaken,
            this.minLitCaptures,
            this.lightingSignalDetected,
            this.activeTicks,
            this.minActiveTicksBeforeSuccess,
            ShaderAutomationValidators.activeTicksSinceFirstSignal(this.activeTicks, this.firstLightingSignalActiveTick),
            this.minActiveTicksAfterSignal);
   }

   private boolean patchIdMatches() {
      return ShaderAutomationValidators.matchesExpectedPatchIdPrefix(this.expectedPatchIdPrefix, this.patchId);
   }

   private boolean shouldCaptureThisFrame() {
      if (!this.stableSceneSatisfied()) {
         this.pendingBurstCaptures = 0;
         return false;
      }
      if (this.pendingBurstCaptures > 0) {
         this.pendingBurstCaptures--;
         return true;
      }
      if (ShaderAutomationValidators.shouldCaptureOnActiveTick(this.activeTicks, this.captureEveryActiveTicks, this.lastCapturedActiveTick)) {
         this.lastCapturedActiveTick = this.activeTicks;
         return true;
      }
      if (this.captureEveryActiveTicks > 0) {
         return false;
      }
      return this.renderedFrames % this.captureEveryN == 0;
   }

   private boolean isCameraMotionEnabled() {
      return this.cameraController.isEnabled();
   }

   private boolean isMotionRepeatValidationEnabled() {
      return this.isCameraMotionEnabled() && this.captureEveryActiveTicks > 0;
   }

   private boolean worldAutomationSatisfied() {
      long[] timeOfDaySequence = this.worldController.getTimeOfDaySequence();
      if (timeOfDaySequence.length > 0 && this.worldController.getTimeOfDayCommandsIssued() < timeOfDaySequence.length) {
         return false;
      }
      int blockToggleCount = this.worldController.getBlockToggleCount();
      return blockToggleCount <= 0 || this.worldController.getBlockToggleCommandsIssued() >= blockToggleCount;
   }

   private boolean directSoftSignalSatisfied() {
      return this.metrics.directSoftSignalDetected || this.metrics.directSoftZeroCaptureCount < 50;
   }

   private boolean motionRepeatValidationSatisfied() {
      if (!this.isMotionRepeatValidationEnabled()) {
         return true;
      }
      if (this.metrics.motionRepeatDirectDeltaSamples == 0 || this.metrics.motionRepeatIndirectDeltaSamples == 0) {
         return false;
      }
      return thresholdSatisfied(this.metrics.averageMotionRepeatDelta(true), this.maxMotionRepeatDirectDeltaAvg)
         && thresholdSatisfied(this.metrics.motionRepeatDirectDeltaMax, this.maxMotionRepeatDirectDeltaMax)
         && thresholdSatisfied(this.metrics.averageMotionRepeatDelta(false), this.maxMotionRepeatIndirectDeltaAvg)
         && thresholdSatisfied(this.metrics.motionRepeatIndirectDeltaMax, this.maxMotionRepeatIndirectDeltaMax);
   }

   private boolean qualityThresholdsSatisfied() {
      return directTemporalValidationSatisfied()
         && thresholdSatisfied(this.metrics.averageTemporalDelta(false, true), this.maxIndirectTemporalDeltaAvg)
         && thresholdSatisfied(this.metrics.indirectTemporalDeltaMax, this.maxIndirectTemporalDeltaMax)
         && thresholdSatisfied(this.metrics.latestIndirectLinearOverbrightFraction, this.maxIndirectLinearOverbrightFraction)
         && thresholdSatisfied(this.metrics.latestIndirectLinearSevereFireflyFraction, this.maxIndirectLinearSevereFireflyFraction)
         && thresholdSatisfied(this.metrics.latestIndirectRawLinearOverbrightFraction, this.maxIndirectRawLinearOverbrightFraction);
   }

   private boolean directTemporalValidationSatisfied() {
      if (this.isMotionRepeatValidationEnabled()) {
         return true;
      }
      return thresholdSatisfied(this.metrics.averageTemporalDelta(false, false), this.maxDirectTemporalDeltaAvg)
         && thresholdSatisfied(this.metrics.directTemporalDeltaMax, this.maxDirectTemporalDeltaMax);
   }

   private static boolean thresholdSatisfied(double value, double maxAllowed) {
      return maxAllowed < 0.0 || value <= maxAllowed;
   }


   private String defaultFailureReason() {
      if (!this.expectedShaderPackMatched) {
         return "Unexpected shader pack: " + this.shaderPackName;
      }
      if (!this.patchIdMatches()) {
         return "Unexpected patch id: " + this.patchId + " (expected prefix " + this.expectedPatchIdPrefix + ")";
      }
      if (!this.raytracerActive) {
         return "Raytracer never became active";
      }
      if (this.capturesTaken < this.captureTarget) {
         return "Insufficient captures: " + this.capturesTaken + "/" + this.captureTarget;
      }
      if (!this.lightingSignalDetected) {
         return "No lighting signal detected";
      }
      if (this.requireDirectSignal && !this.directSignalDetected) {
         return "No direct lighting signal detected"
            + " (directMaxLuma=" + this.metrics.directMaxLuma
            + ", directSoftMaxLuma=" + this.metrics.directSoftMaxLuma
            + ", directDenoisedMaxLuma=" + this.metrics.directDenoisedMaxLuma
            + ", directRawMaxLuma=" + this.metrics.directRawMaxLuma
            + ", lightingBufferMaxLuma=" + this.metrics.lightingBufferMaxLuma
            + ", stageLightingMaxLuma=" + this.metrics.stageLightingMaxLuma
            + ")";
      }
      if (!this.directSoftSignalSatisfied()) {
         return "direct_soft remained black for " + this.metrics.directSoftZeroCaptureCount + " captures";
      }
      if (this.litCapturesTaken < this.minLitCaptures) {
         return "Insufficient lit captures: " + this.litCapturesTaken + "/" + this.minLitCaptures;
      }
      if (this.isMotionRepeatValidationEnabled()) {
         if (this.metrics.motionRepeatDirectDeltaSamples == 0 || this.metrics.motionRepeatIndirectDeltaSamples == 0) {
            return "Camera-motion validation captured no repeated phases (directSamples="
               + this.metrics.motionRepeatDirectDeltaSamples
               + ", indirectSamples="
               + this.metrics.motionRepeatIndirectDeltaSamples
               + ")";
         }
         if (!thresholdSatisfied(this.metrics.averageMotionRepeatDelta(true), this.maxMotionRepeatDirectDeltaAvg)) {
            return "Direct repeat delta average exceeded threshold: "
               + this.metrics.averageMotionRepeatDelta(true)
               + " > "
               + this.maxMotionRepeatDirectDeltaAvg;
         }
         if (!thresholdSatisfied(this.metrics.motionRepeatDirectDeltaMax, this.maxMotionRepeatDirectDeltaMax)) {
            return "Direct repeat delta max exceeded threshold: "
               + this.metrics.motionRepeatDirectDeltaMax
               + " > "
               + this.maxMotionRepeatDirectDeltaMax
               + " topDeltas=["
               + ShaderAutomationFrameMetrics.formatRepeatDeltaDiagnostics(this.metrics.topDirectRepeatDeltas)
               + "]";
         }
         if (!thresholdSatisfied(this.metrics.averageMotionRepeatDelta(false), this.maxMotionRepeatIndirectDeltaAvg)) {
            return "Indirect repeat delta average exceeded threshold: "
               + this.metrics.averageMotionRepeatDelta(false)
               + " > "
               + this.maxMotionRepeatIndirectDeltaAvg
               + " topDeltas=["
               + ShaderAutomationFrameMetrics.formatRepeatDeltaDiagnostics(this.metrics.topIndirectRepeatDeltas)
               + "]";
         }
         if (!thresholdSatisfied(this.metrics.motionRepeatIndirectDeltaMax, this.maxMotionRepeatIndirectDeltaMax)) {
            return "Indirect repeat delta max exceeded threshold: "
               + this.metrics.motionRepeatIndirectDeltaMax
               + " > "
               + this.maxMotionRepeatIndirectDeltaMax
               + " topDeltas=["
               + ShaderAutomationFrameMetrics.formatRepeatDeltaDiagnostics(this.metrics.topIndirectRepeatDeltas)
               + "]";
         }
      }
      if (!directTemporalValidationSatisfied()) {
         if (!thresholdSatisfied(this.metrics.averageTemporalDelta(false, false), this.maxDirectTemporalDeltaAvg)) {
            return "Direct temporal delta average exceeded threshold: "
               + this.metrics.averageTemporalDelta(false, false)
               + " > "
               + this.maxDirectTemporalDeltaAvg;
         }
         if (!thresholdSatisfied(this.metrics.directTemporalDeltaMax, this.maxDirectTemporalDeltaMax)) {
            return "Direct temporal delta max exceeded threshold: "
               + this.metrics.directTemporalDeltaMax
               + " > "
               + this.maxDirectTemporalDeltaMax;
         }
      }
      if (!thresholdSatisfied(this.metrics.averageTemporalDelta(false, true), this.maxIndirectTemporalDeltaAvg)) {
         return "Indirect temporal delta average exceeded threshold: "
            + this.metrics.averageTemporalDelta(false, true)
            + " > "
            + this.maxIndirectTemporalDeltaAvg;
      }
      if (!thresholdSatisfied(this.metrics.indirectTemporalDeltaMax, this.maxIndirectTemporalDeltaMax)) {
         return "Indirect temporal delta max exceeded threshold: "
            + this.metrics.indirectTemporalDeltaMax
            + " > "
            + this.maxIndirectTemporalDeltaMax;
      }
      if (!thresholdSatisfied(this.metrics.latestIndirectLinearOverbrightFraction, this.maxIndirectLinearOverbrightFraction)) {
         return "Indirect resolve overbright fraction exceeded threshold: "
            + this.metrics.latestIndirectLinearOverbrightFraction
            + " > "
            + this.maxIndirectLinearOverbrightFraction;
      }
      if (!thresholdSatisfied(this.metrics.latestIndirectLinearSevereFireflyFraction, this.maxIndirectLinearSevereFireflyFraction)) {
         return "Indirect resolve severe firefly fraction exceeded threshold: "
            + this.metrics.latestIndirectLinearSevereFireflyFraction
            + " > "
            + this.maxIndirectLinearSevereFireflyFraction;
      }
      if (!thresholdSatisfied(this.metrics.latestIndirectRawLinearOverbrightFraction, this.maxIndirectRawLinearOverbrightFraction)) {
         return "Indirect raw overbright fraction exceeded threshold: "
            + this.metrics.latestIndirectRawLinearOverbrightFraction
            + " > "
            + this.maxIndirectRawLinearOverbrightFraction;
      }
      long[] timeOfDaySequence = this.worldController.getTimeOfDaySequence();
      int timeOfDayCommandsIssued = this.worldController.getTimeOfDayCommandsIssued();
      if (timeOfDaySequence.length > 0 && timeOfDayCommandsIssued < timeOfDaySequence.length) {
         return "Time-of-day automation incomplete: " + timeOfDayCommandsIssued + "/" + timeOfDaySequence.length;
      }
      int blockToggleCount = this.worldController.getBlockToggleCount();
      int blockToggleCommandsIssued = this.worldController.getBlockToggleCommandsIssued();
      if (blockToggleCount > 0 && blockToggleCommandsIssued < blockToggleCount) {
         return "Block-toggle automation incomplete: " + blockToggleCommandsIssued + "/" + blockToggleCount;
      }
      if (this.activeTicks < this.minActiveTicksBeforeSuccess) {
         return "Automation ended before minimum active ticks: " + this.activeTicks + "/" + this.minActiveTicksBeforeSuccess;
      }
      int activeTicksSinceFirstSignal = ShaderAutomationValidators.activeTicksSinceFirstSignal(this.activeTicks, this.firstLightingSignalActiveTick);
      if (activeTicksSinceFirstSignal < this.minActiveTicksAfterSignal) {
         return "Automation ended before post-signal settle window: " + activeTicksSinceFirstSignal + "/" + this.minActiveTicksAfterSignal;
      }
      return "Automation failed";
   }

   record MotionRepeatKey(
      int phaseKey,
      int timeOfDayCommandCount,
      int blockToggleCommandCount,
      int historyEpoch
   ) {
   }

   record MotionPhaseSample(
      BufferedImage image,
      int captureIndex,
      int activeTick,
      int ticksSinceAutomationCommand,
      int timeOfDayCommandCount,
      int blockToggleCommandCount,
      int historyEpoch
   ) {
   }

   record MotionRepeatDeltaRecord(
      double delta,
      int phaseKey,
      int previousCaptureIndex,
      int currentCaptureIndex,
      int previousActiveTick,
      int currentActiveTick,
      int previousTicksSinceAutomationCommand,
      int currentTicksSinceAutomationCommand,
      int previousTimeOfDayCommandCount,
      int previousBlockToggleCommandCount,
      int currentTimeOfDayCommandCount,
      int currentBlockToggleCommandCount,
      int historyEpoch
   ) {
   }

   record RowJumpStats(
      int rowFromBottom,
      int rowFromTop,
      double delta,
      double previousMean,
      double nextMean
   ) {
      static final RowJumpStats EMPTY = new RowJumpStats(0, 0, 0.0, 0.0, 0.0);
   }

   private record ReservoirRowJumpStats(
      RowJumpStats validFractionJump,
      RowJumpStats weightJump,
      RowJumpStats targetPdfJump,
      RowJumpStats weightTimesTargetPdfJump,
      RowJumpStats meanMJump
   ) {
      private static final ReservoirRowJumpStats EMPTY = new ReservoirRowJumpStats(
         RowJumpStats.EMPTY,
         RowJumpStats.EMPTY,
         RowJumpStats.EMPTY,
         RowJumpStats.EMPTY,
         RowJumpStats.EMPTY
      );
   }

   private record ReGIRCoverageRowJumpStats(
      RowJumpStats nominalCoverageJump,
      RowJumpStats expandedCoverageJump
   ) {
      private static final ReGIRCoverageRowJumpStats EMPTY = new ReGIRCoverageRowJumpStats(RowJumpStats.EMPTY, RowJumpStats.EMPTY);
   }

   private record ReservoirSampleDebugStats(
      double nonZeroFraction,
      double meanU,
      double meanV
   ) {
      private static final ReservoirSampleDebugStats EMPTY = new ReservoirSampleDebugStats(0.0, 0.0, 0.0);
   }

   private record ReservoirMetaDebugStats(
      double nonZeroFraction,
      double meanAge,
      double meanAbsDistanceX,
      double meanAbsDistanceY
   ) {
      private static final ReservoirMetaDebugStats EMPTY = new ReservoirMetaDebugStats(0.0, 0.0, 0.0, 0.0);
   }

   private record PositionDebugStats(
      double meanX,
      double meanY,
      double meanZ,
      double minX,
      double minY,
      double minZ,
      double maxX,
      double maxY,
      double maxZ
   ) {
      private static final PositionDebugStats EMPTY = new PositionDebugStats(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
   }

   record FireflyStats(
      double fireflyFraction,
      double severeFireflyFraction,
      double fireflyLumaShare,
      double saturatedPixelFraction,
      double nonFiniteFraction
   ) {
      private static final FireflyStats EMPTY = new FireflyStats(0.0, 0.0, 0.0, 0.0, 0.0);
   }

}








