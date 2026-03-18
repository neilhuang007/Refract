package at.redi2go.photonic.client;

import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.util.BufferUtils;
import at.redi2go.photonic.client.rendering.opengl.rendering.renderers.MainRenderer;
import at.redi2go.photonic.client.rendering.world.LightRegistry;
import at.redi2go.photonic.client.rendering.world.WorldRegistry;
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
import net.minecraft.client.MinecraftClient;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL30;

public final class ShaderAutomation {
   private static final int MAX_REPEAT_DIAGNOSTICS = 5;
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
   private final String cameraMotionMode;
   private final int cameraMotionStartActiveTick;
   private final int cameraMotionPeriodTicks;
   private final float cameraYawAmplitudeDegrees;
   private final float cameraPitchAmplitudeDegrees;
   private final int motionRepeatSettleTicks;
   private final double maxMotionRepeatDirectDeltaAvg;
   private final double maxMotionRepeatDirectDeltaMax;
   private final double maxMotionRepeatIndirectDeltaAvg;
   private final double maxMotionRepeatIndirectDeltaMax;
   private final int worldPrepActiveTick;
   private final long[] timeOfDaySequence;
   private final int timeOfDayStartActiveTick;
   private final int timeOfDayStepTicks;
   private final int blockToggleStartActiveTick;
   private final int blockTogglePeriodTicks;
   private final int blockToggleCount;
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
   private int cameraMotionAppliedTicks = 0;
   private int firstLightingSignalActiveTick = -1;
   private double directMaxLuma = 0.0;
   private double directSoftMaxLuma = 0.0;
   private double directDenoisedMaxLuma = 0.0;
   private double directRawMaxLuma = 0.0;
   private double lightingBufferMaxLuma = 0.0;
   private double stageLightingMaxLuma = 0.0;
   private double stageIndirectMaxLuma = 0.0;
   private double handheldMaxLuma = 0.0;
   private double indirectMaxLuma = 0.0;
   private double indirectRawMaxLuma = 0.0;
   private double latestDirectMeanLuma = 0.0;
   private double latestDirectDenoisedMeanLuma = 0.0;
   private double latestDirectRawMeanLuma = 0.0;
   private double latestLightingMeanLuma = 0.0;
   private double latestStageLightingMeanLuma = 0.0;
   private double latestStageIndirectMeanLuma = 0.0;
   private double latestIndirectMeanLuma = 0.0;
   private double latestIndirectRawMeanLuma = 0.0;
   private double latestIndirectRawLinearMeanLuma = 0.0;
   private double latestIndirectRawLinearMaxLuma = 0.0;
   private double latestIndirectRawLinearOverbrightFraction = 0.0;
   private double latestStageIndirectLinearMeanLuma = 0.0;
   private double latestStageIndirectLinearMaxLuma = 0.0;
   private double latestStageIndirectLinearOverbrightFraction = 0.0;
   private double latestDirectMeanRed = 0.0;
   private double latestDirectMeanGreen = 0.0;
   private double latestDirectMeanBlue = 0.0;
   private double latestDirectMeanAlpha = 0.0;
   private double latestDirectZeroAlphaFraction = 0.0;
   private double latestDirectAlphaDelta = 0.0;
   private double directAlphaDeltaSum = 0.0;
   private double directAlphaDeltaMax = 0.0;
   private int directAlphaDeltaSamples = 0;
   private double latestDirectBrightnessVariance = 0.0;
   private double latestDirectBrightnessStdDev = 0.0;
   private double directBrightnessVarianceSum = 0.0;
   private double directBrightnessVarianceMax = 0.0;
   private int directBrightnessVarianceSamples = 0;
   private double latestHandheldBrightnessVariance = 0.0;
   private double latestHandheldBrightnessStdDev = 0.0;
   private double handheldBrightnessVarianceSum = 0.0;
   private double handheldBrightnessVarianceMax = 0.0;
   private int handheldBrightnessVarianceSamples = 0;
   private double latestLightingMeanRed = 0.0;
   private double latestLightingMeanGreen = 0.0;
   private double latestLightingMeanBlue = 0.0;
   private double latestStageLightingMeanRed = 0.0;
   private double latestStageLightingMeanGreen = 0.0;
   private double latestStageLightingMeanBlue = 0.0;
   private double latestStageIndirectMeanRed = 0.0;
   private double latestStageIndirectMeanGreen = 0.0;
   private double latestStageIndirectMeanBlue = 0.0;
   private double latestIndirectMeanRed = 0.0;
   private double latestIndirectMeanGreen = 0.0;
   private double latestIndirectMeanBlue = 0.0;
   private double latestIndirectMeanAlpha = 0.0;
   private double latestIndirectZeroAlphaFraction = 0.0;
   private double latestStageIndirectMeanAlpha = 0.0;
   private double latestStageIndirectZeroAlphaFraction = 0.0;
   private int latestTracedLightCount = 0;
   private int latestTotalLightCount = 0;
   private int maxTracedLightCount = 0;
   private int maxTotalLightCount = 0;
   private int latestLightBlendRegionCount = 0;
   private int lightSelectionCappedCaptures = 0;
   private int globalLightReloadCaptures = 0;
   private int timeOfDayCommandsIssued = 0;
   private int blockToggleCommandsIssued = 0;
   private int pendingBurstCaptures = 0;
   private double latestLightBlendFactor = 0.0;
   private boolean latestLightSelectionCapped = false;
   private boolean latestGlobalLightReload = false;
   private double directTemporalDeltaSum = 0.0;
   private double directTemporalDeltaMax = 0.0;
   private int directTemporalDeltaSamples = 0;
   private double latestDirectTemporalDelta = 0.0;
   private double latestDirectTemporalMaxPixelDelta = 0.0;
   private double directTemporalMaxPixelDeltaSum = 0.0;
   private double directTemporalMaxPixelDeltaMax = 0.0;
   private int directTemporalMaxPixelDeltaSamples = 0;
   private double directSoftTemporalDeltaSum = 0.0;
   private double directSoftTemporalDeltaMax = 0.0;
   private int directSoftTemporalDeltaSamples = 0;
   private double latestDirectSoftTemporalDelta = 0.0;
   private int directSoftZeroCaptureCount = 0;
   private int directSoftSignalCaptureCount = 0;
   private boolean directSoftSignalDetected = false;
   private boolean directSoftMissingSignalWarningIssued = false;
   private double indirectTemporalDeltaSum = 0.0;
   private double indirectTemporalDeltaMax = 0.0;
   private int indirectTemporalDeltaSamples = 0;
   private double motionRepeatDirectDeltaSum = 0.0;
   private double motionRepeatDirectDeltaMax = 0.0;
   private int motionRepeatDirectDeltaSamples = 0;
   private double motionRepeatIndirectDeltaSum = 0.0;
   private double motionRepeatIndirectDeltaMax = 0.0;
   private int motionRepeatIndirectDeltaSamples = 0;
   private double directDenoiserGainSum = 0.0;
   private double directDenoiserGainMax = 0.0;
   private int directDenoiserGainSamples = 0;
   private double indirectResolveGainSum = 0.0;
   private double indirectResolveGainMax = 0.0;
   private int indirectResolveGainSamples = 0;
   private double latestDirectDenoiserGain = 0.0;
   private double latestIndirectResolveGain = 0.0;
   private int cameraMotionStopActiveTick = -1;
   private int postMotionDropSamples = 0;
   private double postMotionDirectMeanAtStop = 0.0;
   private double postMotionIndirectMeanAtStop = 0.0;
   private double postMotionRawDirectMeanAtStop = 0.0;
   private double postMotionStageIndirectMeanAtStop = 0.0;
   private double latestPostMotionDirectDrop = 0.0;
   private double latestPostMotionIndirectDrop = 0.0;
   private double latestPostMotionRawDirectDrop = 0.0;
   private double latestPostMotionStageIndirectDrop = 0.0;
   private double postMotionDirectDropMax = 0.0;
   private double postMotionIndirectDropMax = 0.0;
   private double postMotionRawDirectDropMax = 0.0;
   private double postMotionStageIndirectDropMax = 0.0;
   private double postMotionDirectDropSum = 0.0;
   private double postMotionIndirectDropSum = 0.0;
   private double postMotionRawDirectDropSum = 0.0;
   private double postMotionStageIndirectDropSum = 0.0;
   private float motionYawOffsetMin = 0.0f;
   private float motionYawOffsetMax = 0.0f;
   private float motionPitchOffsetMin = 0.0f;
   private float motionPitchOffsetMax = 0.0f;
   private BufferedImage previousDirectImage = null;
   private BufferedImage previousDirectSoftImage = null;
   private BufferedImage previousIndirectImage = null;
   private final Map<MotionRepeatKey, MotionPhaseSample> previousDirectImagesByPhase = new HashMap<>();
   private final Map<MotionRepeatKey, MotionPhaseSample> previousIndirectImagesByPhase = new HashMap<>();
   private final List<MotionRepeatDeltaRecord> topDirectRepeatDeltas = new ArrayList<>();
   private final List<MotionRepeatDeltaRecord> topIndirectRepeatDeltas = new ArrayList<>();
   private boolean raytracerActive = false;
   private boolean directSignalDetected = false;
   private boolean lightingSignalDetected = false;
   private boolean finished = false;
   private boolean reportInitialized = false;
   private boolean fullscreenApplied = false;
   private boolean cameraBaselineCaptured = false;
   private boolean worldAutomationPrepared = false;
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
   private float baselineCameraYaw = 0.0f;
   private float baselineCameraPitch = 0.0f;
   private int automationBlockX = Integer.MIN_VALUE;
   private int automationBlockY = Integer.MIN_VALUE;
   private int automationBlockZ = Integer.MIN_VALUE;
   private int lastAutomationCommandActiveTick = Integer.MIN_VALUE;

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
      this.cameraMotionMode = System.getProperty("photonics.automation.cameraMotion", "none").trim().toLowerCase(Locale.ROOT);
      this.cameraMotionStartActiveTick = Math.max(0, Integer.getInteger("photonics.automation.cameraMotionStartActiveTick", this.startDelayTicks + Math.max(this.captureEveryActiveTicks, 30)));
      this.cameraMotionPeriodTicks = Math.max(0, Integer.getInteger("photonics.automation.cameraMotionPeriodTicks", 120));
      this.cameraYawAmplitudeDegrees = Math.max(0.0f, Float.parseFloat(System.getProperty("photonics.automation.cameraYawAmplitudeDegrees", "0.0")));
      this.cameraPitchAmplitudeDegrees = Math.max(0.0f, Float.parseFloat(System.getProperty("photonics.automation.cameraPitchAmplitudeDegrees", "0.0")));
      this.motionRepeatSettleTicks = Math.max(this.captureEveryActiveTicks * 2, 60);
      this.maxMotionRepeatDirectDeltaAvg = Double.parseDouble(System.getProperty("photonics.automation.maxMotionRepeatDirectDeltaAvg", "-1"));
      this.maxMotionRepeatDirectDeltaMax = Double.parseDouble(System.getProperty("photonics.automation.maxMotionRepeatDirectDeltaMax", "-1"));
      this.maxMotionRepeatIndirectDeltaAvg = Double.parseDouble(System.getProperty("photonics.automation.maxMotionRepeatIndirectDeltaAvg", "-1"));
      this.maxMotionRepeatIndirectDeltaMax = Double.parseDouble(System.getProperty("photonics.automation.maxMotionRepeatIndirectDeltaMax", "-1"));
      this.worldPrepActiveTick = Math.max(1, Integer.getInteger("photonics.automation.worldPrepActiveTick", 1));
      this.timeOfDaySequence = parseLongSequence(System.getProperty("photonics.automation.timeOfDaySequence", ""));
      this.timeOfDayStartActiveTick = Math.max(0, Integer.getInteger("photonics.automation.timeOfDayStartActiveTick", this.cameraMotionStartActiveTick + this.cameraMotionPeriodTicks));
      this.timeOfDayStepTicks = Math.max(1, Integer.getInteger("photonics.automation.timeOfDayStepTicks", Math.max(this.captureEveryActiveTicks, 30)));
      this.blockToggleStartActiveTick = Math.max(0, Integer.getInteger("photonics.automation.blockToggleStartActiveTick", this.timeOfDayStartActiveTick + this.timeOfDayStepTicks * Math.max(this.timeOfDaySequence.length, 1)));
      this.blockTogglePeriodTicks = Math.max(1, Integer.getInteger("photonics.automation.blockTogglePeriodTicks", Math.max(this.captureEveryActiveTicks, 30)));
      this.blockToggleCount = Math.max(0, Integer.getInteger("photonics.automation.blockToggleCount", 0));
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

   static boolean matchesExpectedShaderPack(String expected, String actual) {
      if (expected == null || expected.isBlank()) {
         return true;
      }
      if (actual == null || actual.isBlank()) {
         return false;
      }

      for (String normalizedExpected : normalizedShaderPackNames(expected)) {
         for (String normalizedActual : normalizedShaderPackNames(actual)) {
            if (normalizedActual.contains(normalizedExpected) || normalizedExpected.contains(normalizedActual)) {
               return true;
            }
         }
      }
      return false;
   }

   static int activeTicksSinceFirstSignal(int activeTicks, int firstLightingSignalActiveTick) {
      return firstLightingSignalActiveTick < 0 ? -1 : Math.max(0, activeTicks - firstLightingSignalActiveTick);
   }

   static boolean isCompletionSatisfied(int capturesTaken,
                                        int captureTarget,
                                        int litCapturesTaken,
                                        int minLitCaptures,
                                        boolean lightingSignalDetected,
                                        int activeTicks,
                                        int minActiveTicksBeforeSuccess,
                                        int activeTicksSinceFirstSignal,
                                        int minActiveTicksAfterSignal) {
      return capturesTaken >= captureTarget
         && litCapturesTaken >= minLitCaptures
         && lightingSignalDetected
         && activeTicks >= minActiveTicksBeforeSuccess
         && activeTicksSinceFirstSignal >= minActiveTicksAfterSignal;
   }

   static boolean matchesExpectedPatchIdPrefix(String expectedPatchIdPrefix, String patchId) {
      return expectedPatchIdPrefix == null || expectedPatchIdPrefix.isBlank() || patchId.startsWith(expectedPatchIdPrefix);
   }

   static boolean shouldCaptureOnActiveTick(int activeTicks, int captureEveryActiveTicks, int lastCapturedActiveTick) {
      return captureEveryActiveTicks > 0
         && activeTicks > 0
         && activeTicks % captureEveryActiveTicks == 0
         && activeTicks != lastCapturedActiveTick;
   }

   static float computeSineMotionOffset(int activeTicks, int motionStartActiveTick, int motionPeriodTicks, float amplitudeDegrees) {
      if (motionPeriodTicks <= 0 || amplitudeDegrees <= 0.0f || activeTicks < motionStartActiveTick) {
         return 0.0f;
      }

      double phase = (double) (activeTicks - motionStartActiveTick) / (double) motionPeriodTicks;
      return (float) (Math.sin(phase * Math.PI * 2.0) * amplitudeDegrees);
   }

   static int motionPhaseKey(int activeTicks, int motionStartActiveTick, int motionPeriodTicks) {
      if (motionPeriodTicks <= 0 || activeTicks < motionStartActiveTick) {
         return -1;
      }

      return Math.floorMod(activeTicks - motionStartActiveTick, motionPeriodTicks);
   }

   static long[] parseLongSequence(String value) {
      if (value == null || value.isBlank()) {
         return new long[0];
      }

      String[] parts = value.split(",");
      List<Long> parsed = new ArrayList<>();
      for (String part : parts) {
         String trimmed = part.trim();
         if (trimmed.isEmpty()) {
            continue;
         }
         parsed.add(Long.parseLong(trimmed));
      }

      long[] result = new long[parsed.size()];
      for (int i = 0; i < parsed.size(); i++) {
         result[i] = parsed.get(i);
      }
      return result;
   }

   static double[] computeImageStats(BufferedImage image) {
      if (image == null) {
         return new double[]{0.0, 0.0, 0.0, 0.0, 0.0};
      }

      double maxLuma = 0.0;
      double lumaSum = 0.0;
      double redSum = 0.0;
      double greenSum = 0.0;
      double blueSum = 0.0;
      for (int y = 0; y < image.getHeight(); y++) {
         for (int x = 0; x < image.getWidth(); x++) {
            int argb = image.getRGB(x, y);
            double r = ((argb >> 16) & 255) / 255.0;
            double g = ((argb >> 8) & 255) / 255.0;
            double b = (argb & 255) / 255.0;
            double luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
            maxLuma = Math.max(maxLuma, luma);
            lumaSum += luma;
            redSum += r;
            greenSum += g;
            blueSum += b;
         }
      }
      double pixelCount = Math.max(1, image.getWidth() * image.getHeight());
      return new double[]{
         maxLuma,
         lumaSum / pixelCount,
         redSum / pixelCount,
         greenSum / pixelCount,
         blueSum / pixelCount
      };
   }

   static double[] computeImageAlphaStats(BufferedImage image) {
      if (image == null) {
         return new double[]{0.0, 0.0, 0.0, 0.0};
      }

      double minAlpha = 1.0;
      double maxAlpha = 0.0;
      double alphaSum = 0.0;
      int zeroAlphaPixels = 0;
      for (int y = 0; y < image.getHeight(); y++) {
         for (int x = 0; x < image.getWidth(); x++) {
            double alpha = ((image.getRGB(x, y) >> 24) & 255) / 255.0;
            minAlpha = Math.min(minAlpha, alpha);
            maxAlpha = Math.max(maxAlpha, alpha);
            alphaSum += alpha;
            if (alpha <= 1.0e-6) {
               zeroAlphaPixels++;
            }
         }
      }
      double pixelCount = Math.max(1, image.getWidth() * image.getHeight());
      return new double[]{
         alphaSum / pixelCount,
         minAlpha,
         maxAlpha,
         zeroAlphaPixels / pixelCount
      };
   }

   static double computeImageBrightnessVariance(BufferedImage image) {
      if (image == null) {
         return 0.0;
      }

      int width = image.getWidth();
      int height = image.getHeight();
      if (width <= 0 || height <= 0) {
         return 0.0;
      }

      double pixelCount = Math.max(1, width * height);
      double meanLuma = computeImageStats(image)[1];
      double varianceSum = 0.0;
      for (int y = 0; y < height; y++) {
         for (int x = 0; x < width; x++) {
            double luma = computeLuma(image.getRGB(x, y));
            double delta = luma - meanLuma;
            varianceSum += delta * delta;
         }
      }
      return varianceSum / pixelCount;
   }

   static double computeImageBrightnessStdDev(BufferedImage image) {
      return Math.sqrt(computeImageBrightnessVariance(image));
   }

   static double computeMaxLumaPixelDelta(BufferedImage previousImage, BufferedImage currentImage) {
      if (previousImage == null || currentImage == null) {
         return 0.0;
      }

      int width = Math.min(previousImage.getWidth(), currentImage.getWidth());
      int height = Math.min(previousImage.getHeight(), currentImage.getHeight());
      if (width <= 0 || height <= 0) {
         return 0.0;
      }

      double maxDelta = 0.0;
      for (int y = 0; y < height; y++) {
         for (int x = 0; x < width; x++) {
            double delta = Math.abs(computeLuma(currentImage.getRGB(x, y)) - computeLuma(previousImage.getRGB(x, y)));
            maxDelta = Math.max(maxDelta, delta);
         }
      }
      return maxDelta;
   }

   private static double computeLuma(int argb) {
      double red = ((argb >> 16) & 255) / 255.0;
      double green = ((argb >> 8) & 255) / 255.0;
      double blue = (argb & 255) / 255.0;
      return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
   }

   static double computeAlphaDelta(BufferedImage previousImage, BufferedImage currentImage) {
      if (previousImage == null || currentImage == null) {
         return 0.0;
      }

      int width = Math.min(previousImage.getWidth(), currentImage.getWidth());
      int height = Math.min(previousImage.getHeight(), currentImage.getHeight());
      if (width <= 0 || height <= 0) {
         return 0.0;
      }

      double pixelCount = Math.max(1, width * height);
      double deltaSum = 0.0;
      for (int y = 0; y < height; y++) {
         for (int x = 0; x < width; x++) {
            double previousAlpha = ((previousImage.getRGB(x, y) >> 24) & 255) / 255.0;
            double currentAlpha = ((currentImage.getRGB(x, y) >> 24) & 255) / 255.0;
            deltaSum += Math.abs(currentAlpha - previousAlpha);
         }
      }
      return deltaSum / pixelCount;
   }

   static double computeMaxLuma(BufferedImage image) {
      return computeImageStats(image)[0];
   }

   static double computeMeanLumaDelta(BufferedImage previousImage, BufferedImage currentImage) {
      if (previousImage == null || currentImage == null) {
         return 0.0;
      }
      int width = Math.min(previousImage.getWidth(), currentImage.getWidth());
      int height = Math.min(previousImage.getHeight(), currentImage.getHeight());
      if (width <= 0 || height <= 0) {
         return 0.0;
      }

      double deltaSum = 0.0;
      int pixelCount = width * height;
      for (int y = 0; y < height; y++) {
         for (int x = 0; x < width; x++) {
            deltaSum += Math.abs(computeLuma(currentImage.getRGB(x, y)) - computeLuma(previousImage.getRGB(x, y)));
         }
      }

      return deltaSum / pixelCount;
   }

   static double computeRelativeImprovement(double baseline, double improved) {
      if (baseline <= 1.0e-6) {
         return 0.0;
      }
      return Math.max(0.0, (baseline - improved) / baseline);
   }

   private static List<String> normalizedShaderPackNames(String value) {
      String normalized = normalizeShaderPackName(value);
      List<String> normalizedNames = new ArrayList<>();
      normalizedNames.add(normalized);
      if (normalized.contains("euphoriapatches")) {
         normalizedNames.add("complementaryreimagined");
      }
      if (normalized.contains("complementaryreimagined")) {
         normalizedNames.add("euphoriapatches");
      }
      return normalizedNames;
   }

   private static String normalizeShaderPackName(String value) {
      return value.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9]", "");
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
      }

      if (client.world != null && this.raytracerActive) {
         this.activeTicks++;
         this.applyCameraMotion(client);
         this.applyWorldAutomation(client);
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
         TextureObject directSoftTexture = textures.get("direct_soft");
         TextureObject directDenoisedTexture = textures.get("direct_denoised");
         TextureObject directRawTexture = textures.get("direct_raw");
         TextureObject lightingTexture = textures.get("lighting");
         TextureObject stageLightingTexture = textures.get("stage_lighting");
         TextureObject stageIndirectTexture = textures.get("stage_indirect");
         TextureObject handheldTexture = textures.get("handheld");
         TextureObject indirectRawTexture = textures.get("indirect_raw");
         TextureObject indirectTexture = textures.get("indirect");
         BufferedImage directImage = this.captureTexture("direct", directTexture, captureIndex);
         BufferedImage directSoftImage = this.captureTexture("direct_soft", directSoftTexture, captureIndex);
         BufferedImage directDenoisedImage = this.captureTexture("direct_denoised", directDenoisedTexture, captureIndex);
         BufferedImage directRawImage = this.captureTexture("direct_raw", directRawTexture, captureIndex);
         BufferedImage lightingImage = this.captureTexture("lighting", lightingTexture, captureIndex);
         BufferedImage stageLightingImage = this.captureTexture("stage_lighting", stageLightingTexture, captureIndex);
         BufferedImage stageIndirectImage = this.captureTexture("stage_indirect", stageIndirectTexture, captureIndex);
         BufferedImage handheldImage = this.captureTexture("handheld", handheldTexture, captureIndex);
         BufferedImage indirectRawImage = this.captureTexture("indirect_raw", indirectRawTexture, captureIndex);
         BufferedImage indirectImage = this.captureTexture("indirect", indirectTexture, captureIndex);
         TextureObject.TextureStats indirectRawLinearStats =
            indirectRawTexture == null ? TextureObject.TextureStats.EMPTY : indirectRawTexture.readStats();
         TextureObject.TextureStats stageIndirectLinearStats =
            stageIndirectTexture == null ? TextureObject.TextureStats.EMPTY : stageIndirectTexture.readStats();
         double[] directStats = computeImageStats(directImage);
         double[] directSoftStats = computeImageStats(directSoftImage);
         double[] directDenoisedStats = computeImageStats(directDenoisedImage);
         double[] directRawStats = computeImageStats(directRawImage);
         double[] lightingStats = computeImageStats(lightingImage);
         double[] stageLightingStats = computeImageStats(stageLightingImage);
         double[] stageIndirectStats = computeImageStats(stageIndirectImage);
         double[] handheldStats = computeImageStats(handheldImage);
         double[] indirectRawStats = computeImageStats(indirectRawImage);
         double[] indirectStats = computeImageStats(indirectImage);
         double[] directAlphaStats = computeImageAlphaStats(directImage);
         double[] stageIndirectAlphaStats = computeImageAlphaStats(stageIndirectImage);
         double[] indirectAlphaStats = computeImageAlphaStats(indirectImage);
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
         this.directMaxLuma = Math.max(this.directMaxLuma, directLuma);
         this.directSoftMaxLuma = Math.max(this.directSoftMaxLuma, directSoftLuma);
         this.directDenoisedMaxLuma = Math.max(this.directDenoisedMaxLuma, directDenoisedLuma);
         this.directRawMaxLuma = Math.max(this.directRawMaxLuma, directRawLuma);
         this.lightingBufferMaxLuma = Math.max(this.lightingBufferMaxLuma, lightingLuma);
         this.stageLightingMaxLuma = Math.max(this.stageLightingMaxLuma, stageLightingLuma);
         this.stageIndirectMaxLuma = Math.max(this.stageIndirectMaxLuma, stageIndirectLuma);
         this.handheldMaxLuma = Math.max(this.handheldMaxLuma, handheldLuma);
         this.indirectRawMaxLuma = Math.max(this.indirectRawMaxLuma, indirectRawLuma);
         this.indirectMaxLuma = Math.max(this.indirectMaxLuma, indirectLuma);
         this.latestDirectMeanLuma = directStats[1];
         this.latestDirectDenoisedMeanLuma = directDenoisedStats[1];
         this.latestDirectRawMeanLuma = directRawStats[1];
         this.latestLightingMeanLuma = lightingStats[1];
         this.latestStageLightingMeanLuma = stageLightingStats[1];
         this.latestStageIndirectMeanLuma = stageIndirectStats[1];
         this.latestIndirectRawMeanLuma = indirectRawStats[1];
         this.latestIndirectMeanLuma = indirectStats[1];
         this.latestIndirectRawLinearMeanLuma = indirectRawLinearStats.meanLuma();
         this.latestIndirectRawLinearMaxLuma = indirectRawLinearStats.maxLuma();
         this.latestIndirectRawLinearOverbrightFraction = indirectRawLinearStats.overbrightFraction();
         this.latestStageIndirectLinearMeanLuma = stageIndirectLinearStats.meanLuma();
         this.latestStageIndirectLinearMaxLuma = stageIndirectLinearStats.maxLuma();
         this.latestStageIndirectLinearOverbrightFraction = stageIndirectLinearStats.overbrightFraction();
         this.latestDirectMeanRed = directStats[2];
         this.latestDirectMeanGreen = directStats[3];
         this.latestDirectMeanBlue = directStats[4];
         this.latestDirectMeanAlpha = directAlphaStats[0];
         this.latestDirectZeroAlphaFraction = directAlphaStats[3];
         this.latestDirectAlphaDelta = computeAlphaDelta(this.previousDirectImage, directImage);
         if (this.previousDirectImage != null) {
            this.directAlphaDeltaSum += this.latestDirectAlphaDelta;
            this.directAlphaDeltaMax = Math.max(this.directAlphaDeltaMax, this.latestDirectAlphaDelta);
            this.directAlphaDeltaSamples++;
         }
         this.latestDirectBrightnessVariance = computeImageBrightnessVariance(directImage);
         this.latestDirectBrightnessStdDev = Math.sqrt(this.latestDirectBrightnessVariance);
         this.directBrightnessVarianceSum += this.latestDirectBrightnessVariance;
         this.directBrightnessVarianceMax = Math.max(this.directBrightnessVarianceMax, this.latestDirectBrightnessVariance);
         this.directBrightnessVarianceSamples++;
         this.latestHandheldBrightnessVariance = computeImageBrightnessVariance(handheldImage);
         this.latestHandheldBrightnessStdDev = Math.sqrt(this.latestHandheldBrightnessVariance);
         this.handheldBrightnessVarianceSum += this.latestHandheldBrightnessVariance;
         this.handheldBrightnessVarianceMax = Math.max(this.handheldBrightnessVarianceMax, this.latestHandheldBrightnessVariance);
         this.handheldBrightnessVarianceSamples++;
         this.latestLightingMeanRed = lightingStats[2];
         this.latestLightingMeanGreen = lightingStats[3];
         this.latestLightingMeanBlue = lightingStats[4];
         this.latestStageLightingMeanRed = stageLightingStats[2];
         this.latestStageLightingMeanGreen = stageLightingStats[3];
         this.latestStageLightingMeanBlue = stageLightingStats[4];
         this.latestStageIndirectMeanRed = stageIndirectStats[2];
         this.latestStageIndirectMeanGreen = stageIndirectStats[3];
         this.latestStageIndirectMeanBlue = stageIndirectStats[4];
         this.latestIndirectMeanRed = indirectStats[2];
         this.latestIndirectMeanGreen = indirectStats[3];
         this.latestIndirectMeanBlue = indirectStats[4];
         this.latestStageIndirectMeanAlpha = stageIndirectAlphaStats[0];
         this.latestStageIndirectZeroAlphaFraction = stageIndirectAlphaStats[3];
         this.latestIndirectMeanAlpha = indirectAlphaStats[0];
         this.latestIndirectZeroAlphaFraction = indirectAlphaStats[3];
         this.updateDirectSoftSignalState(directSoftLuma, captureIndex);
         this.recordTemporalDelta(directImage, false, false);
         this.recordTemporalDelta(directSoftImage, true, false);
         this.recordTemporalDelta(indirectImage, false, true);
         WorldRegistry worldRegistry = Raytracer.INSTANCE.getWorldRegistry();
         LightRegistry lightRegistry = worldRegistry.getLightRegistry();
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
         this.updatePostMotionDropMetrics();
         this.latestDirectDenoiserGain = computeRelativeImprovement(directRawStats[1], directDenoisedStats[1]);
         this.latestIndirectResolveGain = computeRelativeImprovement(stageIndirectStats[1], indirectStats[1]);
         this.directDenoiserGainSum += this.latestDirectDenoiserGain;
         this.directDenoiserGainMax = Math.max(this.directDenoiserGainMax, this.latestDirectDenoiserGain);
         this.directDenoiserGainSamples++;
         this.indirectResolveGainSum += this.latestIndirectResolveGain;
         this.indirectResolveGainMax = Math.max(this.indirectResolveGainMax, this.latestIndirectResolveGain);
         this.indirectResolveGainSamples++;
         this.recordMotionRepeatDelta(directImage, true, captureIndex);
         this.recordMotionRepeatDelta(indirectImage, false, captureIndex);
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
         this.directSignalDetected = this.directMaxLuma > 0.0 || this.directSoftMaxLuma > 0.0 || this.directRawMaxLuma > 0.0 || this.handheldMaxLuma > 0.0;
         this.lightingSignalDetected = this.directMaxLuma > 0.0 || this.directSoftMaxLuma > 0.0 || this.handheldMaxLuma > 0.0 || this.indirectMaxLuma > 0.0;
         Photonic.info("[Automation] capture={} signal={} directSignal={} directSoftSignal={} litCaptures={}/{} activeTicks={} renderedFrames={} lights={}/{} capped={} blendFactor={} blendRegions={} globalReload={} luma(direct={}, soft={}, denoised={}, rawDirect={}, lighting={}, stageLighting={}, stageIndirect={}, handheld={}, rawIndirect={}, indirect={}) mean(direct={}, denoised={}, rawDirect={}, lighting={}, stageLighting={}, stageIndirect={}, rawIndirect={}, indirect={}) variance(direct={}, handheld={}) stddev(direct={}, handheld={}) directAlpha(mean={}, zeroFrac={}) linearIndirect(rawMean={}, rawMax={}, rawOverbright={}, stageMean={}, stageMax={}, stageOverbright={}) meanRgb(direct=({}, {}, {}), lighting=({}, {}, {}), stageLighting=({}, {}, {}), stageIndirect=({}, {}, {}), indirect=({}, {}, {})) indirectAlpha(mainMean={}, mainZeroFrac={}, stageMean={}, stageZeroFrac={}) temporalDelta(directAvg={}, directMax={}, directPixelMaxLatest={}, directPixelMaxAvg={}, softAvg={}, softMax={}, indirectAvg={}, indirectMax={})",
            this.capturesTaken,
            successSignalThisCapture,
            directThisCapture,
            this.directSoftSignalDetected,
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
            String.format(Locale.ROOT, "%.6f", this.latestDirectBrightnessVariance),
            String.format(Locale.ROOT, "%.6f", this.latestHandheldBrightnessVariance),
            String.format(Locale.ROOT, "%.6f", this.latestDirectBrightnessStdDev),
            String.format(Locale.ROOT, "%.6f", this.latestHandheldBrightnessStdDev),
            String.format(Locale.ROOT, "%.5f", this.latestDirectMeanAlpha),
            String.format(Locale.ROOT, "%.5f", this.latestDirectZeroAlphaFraction),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectRawLinearMeanLuma),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectRawLinearMaxLuma),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectRawLinearOverbrightFraction),
            String.format(Locale.ROOT, "%.5f", this.latestStageIndirectLinearMeanLuma),
            String.format(Locale.ROOT, "%.5f", this.latestStageIndirectLinearMaxLuma),
            String.format(Locale.ROOT, "%.5f", this.latestStageIndirectLinearOverbrightFraction),
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
            String.format(Locale.ROOT, "%.5f", this.latestIndirectMeanAlpha),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectZeroAlphaFraction),
            String.format(Locale.ROOT, "%.5f", this.latestStageIndirectMeanAlpha),
            String.format(Locale.ROOT, "%.5f", this.latestStageIndirectZeroAlphaFraction),
            String.format(Locale.ROOT, "%.5f", this.averageTemporalDelta(false, false)),
            String.format(Locale.ROOT, "%.5f", this.directTemporalDeltaMax),
            String.format(Locale.ROOT, "%.5f", this.latestDirectTemporalMaxPixelDelta),
            String.format(Locale.ROOT, "%.5f", this.averageDirectTemporalMaxPixelDelta()),
            String.format(Locale.ROOT, "%.5f", this.averageTemporalDelta(true, false)),
            String.format(Locale.ROOT, "%.5f", this.directSoftTemporalDeltaMax),
            String.format(Locale.ROOT, "%.5f", this.averageTemporalDelta(false, true)),
            String.format(Locale.ROOT, "%.5f", this.indirectTemporalDeltaMax));
         Photonic.info("[Automation] denoise gain capture={} direct(latest={}, avg={}, max={}) indirect(latest={}, avg={}, max={})",
            this.capturesTaken,
            String.format(Locale.ROOT, "%.5f", this.latestDirectDenoiserGain),
            String.format(Locale.ROOT, "%.5f", this.directDenoiserGainSamples == 0 ? 0.0 : this.directDenoiserGainSum / this.directDenoiserGainSamples),
            String.format(Locale.ROOT, "%.5f", this.directDenoiserGainMax),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectResolveGain),
            String.format(Locale.ROOT, "%.5f", this.indirectResolveGainSamples == 0 ? 0.0 : this.indirectResolveGainSum / this.indirectResolveGainSamples),
            String.format(Locale.ROOT, "%.5f", this.indirectResolveGainMax));
         Photonic.info("[Automation] post-motion drop capture={} samples={} direct(stop={}, latestDrop={}, avg={}, max={}) rawDirect(stop={}, latestDrop={}, avg={}, max={}) indirect(stop={}, latestDrop={}, avg={}, max={}) stageIndirect(stop={}, latestDrop={}, avg={}, max={})",
            this.capturesTaken,
            this.postMotionDropSamples,
            String.format(Locale.ROOT, "%.5f", this.postMotionDirectMeanAtStop),
            String.format(Locale.ROOT, "%.5f", this.latestPostMotionDirectDrop),
            String.format(Locale.ROOT, "%.5f", this.postMotionDropSamples == 0 ? 0.0 : this.postMotionDirectDropSum / this.postMotionDropSamples),
            String.format(Locale.ROOT, "%.5f", this.postMotionDirectDropMax),
            String.format(Locale.ROOT, "%.5f", this.postMotionRawDirectMeanAtStop),
            String.format(Locale.ROOT, "%.5f", this.latestPostMotionRawDirectDrop),
            String.format(Locale.ROOT, "%.5f", this.postMotionDropSamples == 0 ? 0.0 : this.postMotionRawDirectDropSum / this.postMotionDropSamples),
            String.format(Locale.ROOT, "%.5f", this.postMotionRawDirectDropMax),
            String.format(Locale.ROOT, "%.5f", this.postMotionIndirectMeanAtStop),
            String.format(Locale.ROOT, "%.5f", this.latestPostMotionIndirectDrop),
            String.format(Locale.ROOT, "%.5f", this.postMotionDropSamples == 0 ? 0.0 : this.postMotionIndirectDropSum / this.postMotionDropSamples),
            String.format(Locale.ROOT, "%.5f", this.postMotionIndirectDropMax),
            String.format(Locale.ROOT, "%.5f", this.postMotionStageIndirectMeanAtStop),
            String.format(Locale.ROOT, "%.5f", this.latestPostMotionStageIndirectDrop),
            String.format(Locale.ROOT, "%.5f", this.postMotionDropSamples == 0 ? 0.0 : this.postMotionStageIndirectDropSum / this.postMotionDropSamples),
            String.format(Locale.ROOT, "%.5f", this.postMotionStageIndirectDropMax));
         if (this.isCameraMotionEnabled()) {
            Photonic.info("[Automation] motion mode={} ticks={} yawOffsetRange=[{}, {}] pitchOffsetRange=[{}, {}] repeatDelta(directAvg={}, directMax={}, indirectAvg={}, indirectMax={}, phaseSamples={}/{})",
               this.cameraMotionMode,
               this.cameraMotionAppliedTicks,
               String.format(Locale.ROOT, "%.2f", this.motionYawOffsetMin),
               String.format(Locale.ROOT, "%.2f", this.motionYawOffsetMax),
               String.format(Locale.ROOT, "%.2f", this.motionPitchOffsetMin),
               String.format(Locale.ROOT, "%.2f", this.motionPitchOffsetMax),
               String.format(Locale.ROOT, "%.5f", this.averageMotionRepeatDelta(true)),
               String.format(Locale.ROOT, "%.5f", this.motionRepeatDirectDeltaMax),
               String.format(Locale.ROOT, "%.5f", this.averageMotionRepeatDelta(false)),
               String.format(Locale.ROOT, "%.5f", this.motionRepeatIndirectDeltaMax),
               this.motionRepeatDirectDeltaSamples,
               this.motionRepeatIndirectDeltaSamples);
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

         double[] finalStats = computeImageStats(image);
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
      BufferedImage image = texture.download();
      if (image == null) {
         Photonic.info("[Automation] capture={} skipped texture='{}' because it is unavailable or zero-sized", captureIndex, name);
         return null;
      }

      String filename = name + "-" + String.format(Locale.ROOT, "%03d", captureIndex) + ".png";
      ImageIO.write(image, "PNG", this.captureDir.resolve(filename).toFile());
      return image;
   }

   private void updatePostMotionWindow() {
      if (!this.isCameraMotionEnabled() || this.cameraMotionAppliedTicks <= 0) {
         return;
      }

      if (this.cameraMotionStopActiveTick >= 0) {
         return;
      }

      if (this.timeOfDaySequence.length == 0 && this.blockToggleCount == 0) {
         return;
      }

      int motionEndTick = this.timeOfDaySequence.length > 0
         ? this.timeOfDayStartActiveTick
         : this.blockToggleStartActiveTick;
      if (motionEndTick > 0 && this.activeTicks >= motionEndTick) {
         this.cameraMotionStopActiveTick = motionEndTick;
      }
   }

   private void updatePostMotionDropMetrics() {
      if (this.cameraMotionStopActiveTick < 0 || this.activeTicks < this.cameraMotionStopActiveTick) {
         return;
      }

      if (this.postMotionDropSamples == 0) {
         this.postMotionDirectMeanAtStop = this.latestDirectMeanLuma;
         this.postMotionIndirectMeanAtStop = this.latestIndirectMeanLuma;
         this.postMotionRawDirectMeanAtStop = this.latestDirectRawMeanLuma;
         this.postMotionStageIndirectMeanAtStop = this.latestStageIndirectMeanLuma;
      }

      this.latestPostMotionDirectDrop = Math.max(0.0, this.postMotionDirectMeanAtStop - this.latestDirectMeanLuma);
      this.latestPostMotionIndirectDrop = Math.max(0.0, this.postMotionIndirectMeanAtStop - this.latestIndirectMeanLuma);
      this.latestPostMotionRawDirectDrop = Math.max(0.0, this.postMotionRawDirectMeanAtStop - this.latestDirectRawMeanLuma);
      this.latestPostMotionStageIndirectDrop = Math.max(0.0, this.postMotionStageIndirectMeanAtStop - this.latestStageIndirectMeanLuma);
      this.postMotionDirectDropMax = Math.max(this.postMotionDirectDropMax, this.latestPostMotionDirectDrop);
      this.postMotionIndirectDropMax = Math.max(this.postMotionIndirectDropMax, this.latestPostMotionIndirectDrop);
      this.postMotionRawDirectDropMax = Math.max(this.postMotionRawDirectDropMax, this.latestPostMotionRawDirectDrop);
      this.postMotionStageIndirectDropMax = Math.max(this.postMotionStageIndirectDropMax, this.latestPostMotionStageIndirectDrop);
      this.postMotionDirectDropSum += this.latestPostMotionDirectDrop;
      this.postMotionIndirectDropSum += this.latestPostMotionIndirectDrop;
      this.postMotionRawDirectDropSum += this.latestPostMotionRawDirectDrop;
      this.postMotionStageIndirectDropSum += this.latestPostMotionStageIndirectDrop;
      this.postMotionDropSamples++;
   }

   private void updateDirectSoftSignalState(double directSoftLuma, int captureIndex) {
      if (directSoftLuma > 0.0) {
         this.directSoftSignalDetected = true;
         this.directSoftSignalCaptureCount++;
         return;
      }

      this.directSoftZeroCaptureCount++;
      if (this.directSoftMissingSignalWarningIssued || this.directSoftZeroCaptureCount < 50) {
         return;
      }

      this.directSoftMissingSignalWarningIssued = true;
      Photonic.warn(
         "[Automation] direct_soft remained black for {} captures; capture={} activeTicks={} directMaxLuma={} directRawMaxLuma={} handheldMaxLuma={}",
         this.directSoftZeroCaptureCount,
         captureIndex,
         this.activeTicks,
         String.format(Locale.ROOT, "%.4f", this.directMaxLuma),
         String.format(Locale.ROOT, "%.4f", this.directRawMaxLuma),
         String.format(Locale.ROOT, "%.4f", this.handheldMaxLuma));
   }

   private void recordTemporalDelta(BufferedImage currentImage, boolean directSoft, boolean indirect) {
      if (currentImage == null) {
         return;
      }

      if (indirect) {
         double delta = computeMeanLumaDelta(this.previousIndirectImage, currentImage);
         if (this.previousIndirectImage != null) {
            this.indirectTemporalDeltaSum += delta;
            this.indirectTemporalDeltaMax = Math.max(this.indirectTemporalDeltaMax, delta);
            this.indirectTemporalDeltaSamples++;
         }
         this.previousIndirectImage = currentImage;
         return;
      }

      if (directSoft) {
         double delta = computeMeanLumaDelta(this.previousDirectSoftImage, currentImage);
         if (this.previousDirectSoftImage != null) {
            this.latestDirectSoftTemporalDelta = delta;
            this.directSoftTemporalDeltaSum += delta;
            this.directSoftTemporalDeltaMax = Math.max(this.directSoftTemporalDeltaMax, delta);
            this.directSoftTemporalDeltaSamples++;
         }
         this.previousDirectSoftImage = currentImage;
         return;
      }

      double delta = computeMeanLumaDelta(this.previousDirectImage, currentImage);
      double maxPixelDelta = computeMaxLumaPixelDelta(this.previousDirectImage, currentImage);
      if (this.previousDirectImage != null) {
         this.latestDirectTemporalDelta = delta;
         this.latestDirectTemporalMaxPixelDelta = maxPixelDelta;
         this.directTemporalDeltaSum += delta;
         this.directTemporalDeltaMax = Math.max(this.directTemporalDeltaMax, delta);
         this.directTemporalDeltaSamples++;
         this.directTemporalMaxPixelDeltaSum += maxPixelDelta;
         this.directTemporalMaxPixelDeltaMax = Math.max(this.directTemporalMaxPixelDeltaMax, maxPixelDelta);
         this.directTemporalMaxPixelDeltaSamples++;
      }
      this.previousDirectImage = currentImage;
   }

   private void recordMotionRepeatDelta(BufferedImage currentImage, boolean direct, int captureIndex) {
      if (!this.isMotionRepeatValidationEnabled() || currentImage == null) {
         return;
      }

      int phaseKey = motionPhaseKey(this.activeTicks, this.cameraMotionStartActiveTick, this.cameraMotionPeriodTicks);
      if (phaseKey < 0) {
         return;
      }

      int ticksSinceCommand = this.ticksSinceLastAutomationCommand();
      if (ticksSinceCommand < this.motionRepeatSettleTicks) {
         return;
      }

      MotionRepeatKey repeatKey = new MotionRepeatKey(phaseKey, this.timeOfDayCommandsIssued, this.blockToggleCommandsIssued);
      Map<MotionRepeatKey, MotionPhaseSample> historyByPhase = direct ? this.previousDirectImagesByPhase : this.previousIndirectImagesByPhase;
      MotionPhaseSample previousSample = historyByPhase.get(repeatKey);
      if (previousSample != null) {
         double delta = computeMeanLumaDelta(previousSample.image(), currentImage);
         if (direct) {
            this.motionRepeatDirectDeltaSum += delta;
            this.motionRepeatDirectDeltaMax = Math.max(this.motionRepeatDirectDeltaMax, delta);
            this.motionRepeatDirectDeltaSamples++;
         } else {
            this.motionRepeatIndirectDeltaSum += delta;
            this.motionRepeatIndirectDeltaMax = Math.max(this.motionRepeatIndirectDeltaMax, delta);
            this.motionRepeatIndirectDeltaSamples++;
         }
         this.recordTopRepeatDelta(
            direct,
            new MotionRepeatDeltaRecord(
               delta,
               phaseKey,
               previousSample.captureIndex(),
               captureIndex,
               previousSample.activeTick(),
               this.activeTicks,
               previousSample.ticksSinceAutomationCommand(),
               ticksSinceCommand,
               previousSample.timeOfDayCommandCount(),
               previousSample.blockToggleCommandCount(),
               this.timeOfDayCommandsIssued,
               this.blockToggleCommandsIssued
            )
         );
      }
      historyByPhase.put(
         repeatKey,
         new MotionPhaseSample(
            currentImage,
            captureIndex,
            this.activeTicks,
            ticksSinceCommand,
            this.timeOfDayCommandsIssued,
            this.blockToggleCommandsIssued
         )
      );
   }

   private double averageTemporalDelta(boolean directSoft, boolean indirect) {
      if (indirect) {
         return this.indirectTemporalDeltaSamples == 0 ? 0.0 : this.indirectTemporalDeltaSum / this.indirectTemporalDeltaSamples;
      }
      if (directSoft) {
         return this.directSoftTemporalDeltaSamples == 0 ? 0.0 : this.directSoftTemporalDeltaSum / this.directSoftTemporalDeltaSamples;
      }
      return this.directTemporalDeltaSamples == 0 ? 0.0 : this.directTemporalDeltaSum / this.directTemporalDeltaSamples;
   }

   private double averageDirectTemporalMaxPixelDelta() {
      return this.directTemporalMaxPixelDeltaSamples == 0
         ? 0.0
         : this.directTemporalMaxPixelDeltaSum / this.directTemporalMaxPixelDeltaSamples;
   }

   private double averageDirectAlphaDelta() {
      return this.directAlphaDeltaSamples == 0 ? 0.0 : this.directAlphaDeltaSum / this.directAlphaDeltaSamples;
   }

   private double averageDirectBrightnessVariance() {
      return this.directBrightnessVarianceSamples == 0 ? 0.0 : this.directBrightnessVarianceSum / this.directBrightnessVarianceSamples;
   }

   private double averageHandheldBrightnessVariance() {
      return this.handheldBrightnessVarianceSamples == 0 ? 0.0 : this.handheldBrightnessVarianceSum / this.handheldBrightnessVarianceSamples;
   }

   private double averageMotionRepeatDelta(boolean direct) {
      if (direct) {
         return this.motionRepeatDirectDeltaSamples == 0 ? 0.0 : this.motionRepeatDirectDeltaSum / this.motionRepeatDirectDeltaSamples;
      }
      return this.motionRepeatIndirectDeltaSamples == 0 ? 0.0 : this.motionRepeatIndirectDeltaSum / this.motionRepeatIndirectDeltaSamples;
   }

   private int ticksSinceLastAutomationCommand() {
      return this.lastAutomationCommandActiveTick == Integer.MIN_VALUE
         ? Integer.MAX_VALUE
         : Math.max(0, this.activeTicks - this.lastAutomationCommandActiveTick);
   }

   private void recordTopRepeatDelta(boolean direct, MotionRepeatDeltaRecord record) {
      List<MotionRepeatDeltaRecord> topDeltas = direct ? this.topDirectRepeatDeltas : this.topIndirectRepeatDeltas;
      topDeltas.add(record);
      topDeltas.sort((left, right) -> Double.compare(right.delta(), left.delta()));
      if (topDeltas.size() > MAX_REPEAT_DIAGNOSTICS) {
         topDeltas.remove(topDeltas.size() - 1);
      }
   }

   private static String formatRepeatDeltaDiagnostics(List<MotionRepeatDeltaRecord> records) {
      if (records.isEmpty()) {
         return "";
      }

      List<String> parts = new ArrayList<>(records.size());
      for (MotionRepeatDeltaRecord record : records) {
         parts.add(String.format(
            Locale.ROOT,
            "delta=%.5f phase=%d scene=t%d/b%d>t%d/b%d captures=%d>%d activeTicks=%d>%d ticksSinceCommand=%d>%d",
            record.delta(),
            record.phaseKey(),
            record.previousTimeOfDayCommandCount(),
            record.previousBlockToggleCommandCount(),
            record.currentTimeOfDayCommandCount(),
            record.currentBlockToggleCommandCount(),
            record.previousCaptureIndex(),
            record.currentCaptureIndex(),
            record.previousActiveTick(),
            record.currentActiveTick(),
            record.previousTicksSinceAutomationCommand(),
            record.currentTicksSinceAutomationCommand()
         ));
      }
      return String.join(" | ", parts);
   }

   private void refreshRuntimeState() {
      this.shaderPackName = Iris.getIrisConfig().getShaderPackName().orElse("");
      this.expectedShaderPackMatched = matchesExpectedShaderPack(this.expectedShaderPack, this.shaderPackName);
      this.raytracerActive |= Raytracer.INSTANCE != null && !Raytracer.isDisabled();
      this.patchId = currentPatchId();
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

      Path latestLog = Path.of("run/logs/latest.log");
      if (!Files.exists(latestLog)) {
         return;
      }

      try {
         String logContent = Files.readString(latestLog);
         if (logContent.contains("Failed to create shader rendering pipeline")
            || logContent.contains("The shaderpack failed to load! Please report the error to the shader developer.")) {
            String compileReason = photonics$extractShaderCompileReason(logContent);
            String failureMessage = compileReason == null
               ? "Fatal shader compilation failure detected in latest.log"
               : "Fatal shader compilation failure: " + compileReason;
            Photonic.warn("[Automation] {}", failureMessage);
            this.finish(failureMessage);
            this.scheduleFatalShutdown(client);
         }
      } catch (IOException ignored) {
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

   private void applyCameraMotion(MinecraftClient client) {
      if (!this.isCameraMotionEnabled() || client.player == null) {
         return;
      }

      if (!this.cameraBaselineCaptured) {
         this.cameraBaselineCaptured = true;
         this.baselineCameraYaw = client.player.getYaw();
         this.baselineCameraPitch = client.player.getPitch();
      }

      float yawOffset = computeSineMotionOffset(this.activeTicks, this.cameraMotionStartActiveTick, this.cameraMotionPeriodTicks, this.cameraYawAmplitudeDegrees);
      float pitchOffset = computeSineMotionOffset(
         this.activeTicks + Math.max(this.cameraMotionPeriodTicks / 4, 1),
         this.cameraMotionStartActiveTick,
         this.cameraMotionPeriodTicks,
         this.cameraPitchAmplitudeDegrees
      );
      float targetYaw = this.baselineCameraYaw + yawOffset;
      float targetPitch = clampPitch(this.baselineCameraPitch + pitchOffset);

      client.player.setYaw(targetYaw);
      client.player.setPitch(targetPitch);
      client.player.setHeadYaw(targetYaw);
      client.player.setBodyYaw(targetYaw);

      if (this.activeTicks >= this.cameraMotionStartActiveTick) {
         this.cameraMotionAppliedTicks++;
         this.motionYawOffsetMin = Math.min(this.motionYawOffsetMin, yawOffset);
         this.motionYawOffsetMax = Math.max(this.motionYawOffsetMax, yawOffset);
         this.motionPitchOffsetMin = Math.min(this.motionPitchOffsetMin, pitchOffset);
         this.motionPitchOffsetMax = Math.max(this.motionPitchOffsetMax, pitchOffset);
      }
   }

   private void applyWorldAutomation(MinecraftClient client) {
      if (client.world == null || client.player == null || client.getServer() == null) {
         return;
      }

      this.prepareWorldAutomation(client);
      this.applyTimeOfDayAutomation(client);
      this.applyBlockToggleAutomation(client);
   }

   private void prepareWorldAutomation(MinecraftClient client) {
      if (this.worldAutomationPrepared || this.activeTicks < this.worldPrepActiveTick) {
         return;
      }

      boolean prepared = true;
      prepared &= this.executeServerCommand(client, "gamerule doDaylightCycle false");
      prepared &= this.executeServerCommand(client, "gamerule doWeatherCycle false");
      prepared &= this.executeServerCommand(client, "weather clear");
      if (prepared) {
         this.worldAutomationPrepared = true;
         this.queueBurstCaptures(2);
      }
   }

   private void applyTimeOfDayAutomation(MinecraftClient client) {
      if (this.timeOfDaySequence.length == 0 || this.activeTicks < this.timeOfDayStartActiveTick) {
         return;
      }

      int sequenceIndex = (this.activeTicks - this.timeOfDayStartActiveTick) / this.timeOfDayStepTicks;
      if (sequenceIndex < 0 || sequenceIndex >= this.timeOfDaySequence.length || sequenceIndex < this.timeOfDayCommandsIssued) {
         return;
      }

      long timeOfDay = this.timeOfDaySequence[sequenceIndex];
      if (this.executeServerCommand(client, "time set " + timeOfDay)) {
         this.timeOfDayCommandsIssued = sequenceIndex + 1;
         this.queueBurstCaptures(3);
      }
   }

   private void applyBlockToggleAutomation(MinecraftClient client) {
      if (this.blockToggleCount <= 0 || this.activeTicks < this.blockToggleStartActiveTick) {
         return;
      }

      int toggleIndex = (this.activeTicks - this.blockToggleStartActiveTick) / this.blockTogglePeriodTicks;
      if (toggleIndex < 0 || toggleIndex >= this.blockToggleCount || toggleIndex < this.blockToggleCommandsIssued) {
         return;
      }

      this.ensureAutomationBlockTarget(client);
      if (this.automationBlockX == Integer.MIN_VALUE) {
         return;
      }

      String command = (toggleIndex & 1) == 0
         ? "setblock " + this.automationBlockX + " " + this.automationBlockY + " " + this.automationBlockZ + " minecraft:glowstone replace"
         : "setblock " + this.automationBlockX + " " + this.automationBlockY + " " + this.automationBlockZ + " minecraft:air destroy";
      if (this.executeServerCommand(client, command)) {
         this.blockToggleCommandsIssued = toggleIndex + 1;
         this.queueBurstCaptures(3);
      }
   }

   private void ensureAutomationBlockTarget(MinecraftClient client) {
      if (this.automationBlockX != Integer.MIN_VALUE || client.player == null) {
         return;
      }

      double yawRadians = Math.toRadians(client.player.getYaw());
      this.automationBlockX = (int)Math.floor(client.player.getX() - Math.sin(yawRadians) * 3.0);
      this.automationBlockY = (int)Math.floor(client.player.getY());
      this.automationBlockZ = (int)Math.floor(client.player.getZ() + Math.cos(yawRadians) * 3.0);
   }

   private boolean executeServerCommand(MinecraftClient client, String command) {
      if (client.getServer() == null) {
         return false;
      }

      try {
         client.getServer().execute(() -> client.getServer().getCommandManager().executeWithPrefix(client.getServer().getCommandSource(), command));
         this.lastAutomationCommandActiveTick = this.activeTicks;
         Photonic.info("[Automation] command activeTicks={} command={}", this.activeTicks, command);
         return true;
      } catch (RuntimeException e) {
         Photonic.warn("[Automation] command failed activeTicks={} command={} error={}", this.activeTicks, command, e.toString());
         return false;
      }
   }

   private void queueBurstCaptures(int burstCaptureCount) {
      this.pendingBurstCaptures = Math.max(this.pendingBurstCaptures, burstCaptureCount);
   }

   private String currentPatchId() {
      String patchState = Raytracer.getAppliedPatch() == null ? "native" : "patched";
      return "LIGHT_TREE_RESTIR:" + patchState;
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
         activeTicksSinceFirstSignal(this.activeTicks, this.firstLightingSignalActiveTick),
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
         props.setProperty("activeTicksSinceFirstSignal", Integer.toString(activeTicksSinceFirstSignal(this.activeTicks, this.firstLightingSignalActiveTick)));
         props.setProperty("cameraMotionMode", this.cameraMotionMode);
         props.setProperty("cameraMotionStartActiveTick", Integer.toString(this.cameraMotionStartActiveTick));
         props.setProperty("cameraMotionPeriodTicks", Integer.toString(this.cameraMotionPeriodTicks));
         props.setProperty("cameraYawAmplitudeDegrees", Float.toString(this.cameraYawAmplitudeDegrees));
         props.setProperty("cameraPitchAmplitudeDegrees", Float.toString(this.cameraPitchAmplitudeDegrees));
         props.setProperty("cameraMotionAppliedTicks", Integer.toString(this.cameraMotionAppliedTicks));
         props.setProperty("cameraMotionStopActiveTick", Integer.toString(this.cameraMotionStopActiveTick));
         props.setProperty("motionRepeatSettleTicks", Integer.toString(this.motionRepeatSettleTicks));
         props.setProperty("worldPrepActiveTick", Integer.toString(this.worldPrepActiveTick));
         props.setProperty("worldAutomationPrepared", Boolean.toString(this.worldAutomationPrepared));
         props.setProperty("timeOfDaySequenceLength", Integer.toString(this.timeOfDaySequence.length));
         props.setProperty("timeOfDayStartActiveTick", Integer.toString(this.timeOfDayStartActiveTick));
         props.setProperty("timeOfDayStepTicks", Integer.toString(this.timeOfDayStepTicks));
         props.setProperty("timeOfDayCommandsIssued", Integer.toString(this.timeOfDayCommandsIssued));
         props.setProperty("blockToggleStartActiveTick", Integer.toString(this.blockToggleStartActiveTick));
         props.setProperty("blockTogglePeriodTicks", Integer.toString(this.blockTogglePeriodTicks));
         props.setProperty("blockToggleCount", Integer.toString(this.blockToggleCount));
         props.setProperty("blockToggleCommandsIssued", Integer.toString(this.blockToggleCommandsIssued));
         props.setProperty("motionYawOffsetMin", Float.toString(this.motionYawOffsetMin));
         props.setProperty("motionYawOffsetMax", Float.toString(this.motionYawOffsetMax));
         props.setProperty("motionPitchOffsetMin", Float.toString(this.motionPitchOffsetMin));
         props.setProperty("motionPitchOffsetMax", Float.toString(this.motionPitchOffsetMax));
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
         props.setProperty("directMaxLuma", Double.toString(this.directMaxLuma));
         props.setProperty("directSoftMaxLuma", Double.toString(this.directSoftMaxLuma));
         props.setProperty("directDenoisedMaxLuma", Double.toString(this.directDenoisedMaxLuma));
         props.setProperty("directRawMaxLuma", Double.toString(this.directRawMaxLuma));
         props.setProperty("lightingBufferMaxLuma", Double.toString(this.lightingBufferMaxLuma));
         props.setProperty("stageLightingMaxLuma", Double.toString(this.stageLightingMaxLuma));
         props.setProperty("stageIndirectMaxLuma", Double.toString(this.stageIndirectMaxLuma));
         props.setProperty("handheldMaxLuma", Double.toString(this.handheldMaxLuma));
         props.setProperty("indirectRawMaxLuma", Double.toString(this.indirectRawMaxLuma));
         props.setProperty("indirectMaxLuma", Double.toString(this.indirectMaxLuma));
         props.setProperty("finalCaptureIndex", Integer.toString(this.latestFinalCaptureIndex));
         props.setProperty("finalFrameMaxLuma", Double.toString(this.finalFrameMaxLuma));
         props.setProperty("latestFinalMeanLuma", Double.toString(this.latestFinalMeanLuma));
         props.setProperty("latestFinalMeanRed", Double.toString(this.latestFinalMeanRed));
         props.setProperty("latestFinalMeanGreen", Double.toString(this.latestFinalMeanGreen));
         props.setProperty("latestFinalMeanBlue", Double.toString(this.latestFinalMeanBlue));
         props.setProperty("finalSignalDetected", Boolean.toString(this.finalSignalDetected));
         props.setProperty("latestDirectMeanLuma", Double.toString(this.latestDirectMeanLuma));
         props.setProperty("latestDirectDenoisedMeanLuma", Double.toString(this.latestDirectDenoisedMeanLuma));
         props.setProperty("latestDirectRawMeanLuma", Double.toString(this.latestDirectRawMeanLuma));
         props.setProperty("latestLightingMeanLuma", Double.toString(this.latestLightingMeanLuma));
         props.setProperty("latestStageLightingMeanLuma", Double.toString(this.latestStageLightingMeanLuma));
         props.setProperty("latestStageIndirectMeanLuma", Double.toString(this.latestStageIndirectMeanLuma));
         props.setProperty("latestIndirectRawMeanLuma", Double.toString(this.latestIndirectRawMeanLuma));
         props.setProperty("latestIndirectMeanLuma", Double.toString(this.latestIndirectMeanLuma));
         props.setProperty("latestIndirectRawLinearMeanLuma", Double.toString(this.latestIndirectRawLinearMeanLuma));
         props.setProperty("latestIndirectRawLinearMaxLuma", Double.toString(this.latestIndirectRawLinearMaxLuma));
         props.setProperty("latestIndirectRawLinearOverbrightFraction", Double.toString(this.latestIndirectRawLinearOverbrightFraction));
         props.setProperty("latestStageIndirectLinearMeanLuma", Double.toString(this.latestStageIndirectLinearMeanLuma));
         props.setProperty("latestStageIndirectLinearMaxLuma", Double.toString(this.latestStageIndirectLinearMaxLuma));
         props.setProperty("latestStageIndirectLinearOverbrightFraction", Double.toString(this.latestStageIndirectLinearOverbrightFraction));
         props.setProperty("latestDirectMeanRed", Double.toString(this.latestDirectMeanRed));
         props.setProperty("latestDirectMeanGreen", Double.toString(this.latestDirectMeanGreen));
         props.setProperty("latestDirectMeanBlue", Double.toString(this.latestDirectMeanBlue));
         props.setProperty("latestDirectMeanAlpha", Double.toString(this.latestDirectMeanAlpha));
         props.setProperty("latestDirectZeroAlphaFraction", Double.toString(this.latestDirectZeroAlphaFraction));
         props.setProperty("latestDirectAlphaDelta", Double.toString(this.latestDirectAlphaDelta));
         props.setProperty("directAlphaDeltaAvg", Double.toString(this.averageDirectAlphaDelta()));
         props.setProperty("directAlphaDeltaMax", Double.toString(this.directAlphaDeltaMax));
         props.setProperty("latestDirectBrightnessVariance", Double.toString(this.latestDirectBrightnessVariance));
         props.setProperty("latestDirectBrightnessStdDev", Double.toString(this.latestDirectBrightnessStdDev));
         props.setProperty("directBrightnessVarianceAvg", Double.toString(this.averageDirectBrightnessVariance()));
         props.setProperty("directBrightnessVarianceMax", Double.toString(this.directBrightnessVarianceMax));
         props.setProperty("latestHandheldBrightnessVariance", Double.toString(this.latestHandheldBrightnessVariance));
         props.setProperty("latestHandheldBrightnessStdDev", Double.toString(this.latestHandheldBrightnessStdDev));
         props.setProperty("handheldBrightnessVarianceAvg", Double.toString(this.averageHandheldBrightnessVariance()));
         props.setProperty("handheldBrightnessVarianceMax", Double.toString(this.handheldBrightnessVarianceMax));
         props.setProperty("latestLightingMeanRed", Double.toString(this.latestLightingMeanRed));
         props.setProperty("latestLightingMeanGreen", Double.toString(this.latestLightingMeanGreen));
         props.setProperty("latestLightingMeanBlue", Double.toString(this.latestLightingMeanBlue));
         props.setProperty("latestStageLightingMeanRed", Double.toString(this.latestStageLightingMeanRed));
         props.setProperty("latestStageLightingMeanGreen", Double.toString(this.latestStageLightingMeanGreen));
         props.setProperty("latestStageLightingMeanBlue", Double.toString(this.latestStageLightingMeanBlue));
         props.setProperty("latestStageIndirectMeanRed", Double.toString(this.latestStageIndirectMeanRed));
         props.setProperty("latestStageIndirectMeanGreen", Double.toString(this.latestStageIndirectMeanGreen));
         props.setProperty("latestStageIndirectMeanBlue", Double.toString(this.latestStageIndirectMeanBlue));
         props.setProperty("latestIndirectMeanRed", Double.toString(this.latestIndirectMeanRed));
         props.setProperty("latestIndirectMeanGreen", Double.toString(this.latestIndirectMeanGreen));
         props.setProperty("latestIndirectMeanBlue", Double.toString(this.latestIndirectMeanBlue));
         props.setProperty("latestIndirectMeanAlpha", Double.toString(this.latestIndirectMeanAlpha));
         props.setProperty("latestIndirectZeroAlphaFraction", Double.toString(this.latestIndirectZeroAlphaFraction));
         props.setProperty("latestStageIndirectMeanAlpha", Double.toString(this.latestStageIndirectMeanAlpha));
         props.setProperty("latestStageIndirectZeroAlphaFraction", Double.toString(this.latestStageIndirectZeroAlphaFraction));
         props.setProperty("latestTracedLightCount", Integer.toString(this.latestTracedLightCount));
         props.setProperty("latestTotalLightCount", Integer.toString(this.latestTotalLightCount));
         props.setProperty("maxTracedLightCount", Integer.toString(this.maxTracedLightCount));
         props.setProperty("maxTotalLightCount", Integer.toString(this.maxTotalLightCount));
         props.setProperty("latestLightSelectionCapped", Boolean.toString(this.latestLightSelectionCapped));
         props.setProperty("lightSelectionCappedCaptures", Integer.toString(this.lightSelectionCappedCaptures));
         props.setProperty("latestLightBlendFactor", Double.toString(this.latestLightBlendFactor));
         props.setProperty("latestLightBlendRegionCount", Integer.toString(this.latestLightBlendRegionCount));
         props.setProperty("latestGlobalLightReload", Boolean.toString(this.latestGlobalLightReload));
         props.setProperty("globalLightReloadCaptures", Integer.toString(this.globalLightReloadCaptures));
         props.setProperty("directSoftSignalDetected", Boolean.toString(this.directSoftSignalDetected));
         props.setProperty("directSoftSignalCaptureCount", Integer.toString(this.directSoftSignalCaptureCount));
         props.setProperty("directSoftZeroCaptureCount", Integer.toString(this.directSoftZeroCaptureCount));
         props.setProperty("directSoftMissingSignalWarningIssued", Boolean.toString(this.directSoftMissingSignalWarningIssued));
         props.setProperty("latestDirectTemporalDelta", Double.toString(this.latestDirectTemporalDelta));
         props.setProperty("directTemporalDeltaAvg", Double.toString(this.averageTemporalDelta(false, false)));
         props.setProperty("directTemporalDeltaMax", Double.toString(this.directTemporalDeltaMax));
         props.setProperty("latestDirectTemporalMaxPixelDelta", Double.toString(this.latestDirectTemporalMaxPixelDelta));
         props.setProperty("directTemporalMaxPixelDeltaAvg", Double.toString(this.averageDirectTemporalMaxPixelDelta()));
         props.setProperty("directTemporalMaxPixelDeltaMax", Double.toString(this.directTemporalMaxPixelDeltaMax));
         props.setProperty("latestDirectSoftTemporalDelta", Double.toString(this.latestDirectSoftTemporalDelta));
         props.setProperty("directSoftTemporalDeltaAvg", Double.toString(this.averageTemporalDelta(true, false)));
         props.setProperty("directSoftTemporalDeltaMax", Double.toString(this.directSoftTemporalDeltaMax));
         props.setProperty("indirectTemporalDeltaAvg", Double.toString(this.averageTemporalDelta(false, true)));
         props.setProperty("indirectTemporalDeltaMax", Double.toString(this.indirectTemporalDeltaMax));
         props.setProperty("latestDirectDenoiserGain", Double.toString(this.latestDirectDenoiserGain));
         props.setProperty("latestIndirectResolveGain", Double.toString(this.latestIndirectResolveGain));
         props.setProperty("directDenoiserGainAvg", Double.toString(this.directDenoiserGainSamples == 0 ? 0.0 : this.directDenoiserGainSum / this.directDenoiserGainSamples));
         props.setProperty("directDenoiserGainMax", Double.toString(this.directDenoiserGainMax));
         props.setProperty("indirectResolveGainAvg", Double.toString(this.indirectResolveGainSamples == 0 ? 0.0 : this.indirectResolveGainSum / this.indirectResolveGainSamples));
         props.setProperty("indirectResolveGainMax", Double.toString(this.indirectResolveGainMax));
         props.setProperty("postMotionDropSamples", Integer.toString(this.postMotionDropSamples));
         props.setProperty("postMotionDirectMeanAtStop", Double.toString(this.postMotionDirectMeanAtStop));
         props.setProperty("postMotionRawDirectMeanAtStop", Double.toString(this.postMotionRawDirectMeanAtStop));
         props.setProperty("postMotionIndirectMeanAtStop", Double.toString(this.postMotionIndirectMeanAtStop));
         props.setProperty("postMotionStageIndirectMeanAtStop", Double.toString(this.postMotionStageIndirectMeanAtStop));
         props.setProperty("latestPostMotionDirectDrop", Double.toString(this.latestPostMotionDirectDrop));
         props.setProperty("latestPostMotionRawDirectDrop", Double.toString(this.latestPostMotionRawDirectDrop));
         props.setProperty("latestPostMotionIndirectDrop", Double.toString(this.latestPostMotionIndirectDrop));
         props.setProperty("latestPostMotionStageIndirectDrop", Double.toString(this.latestPostMotionStageIndirectDrop));
         props.setProperty("postMotionDirectDropAvg", Double.toString(this.postMotionDropSamples == 0 ? 0.0 : this.postMotionDirectDropSum / this.postMotionDropSamples));
         props.setProperty("postMotionRawDirectDropAvg", Double.toString(this.postMotionDropSamples == 0 ? 0.0 : this.postMotionRawDirectDropSum / this.postMotionDropSamples));
         props.setProperty("postMotionIndirectDropAvg", Double.toString(this.postMotionDropSamples == 0 ? 0.0 : this.postMotionIndirectDropSum / this.postMotionDropSamples));
         props.setProperty("postMotionStageIndirectDropAvg", Double.toString(this.postMotionDropSamples == 0 ? 0.0 : this.postMotionStageIndirectDropSum / this.postMotionDropSamples));
         props.setProperty("postMotionDirectDropMax", Double.toString(this.postMotionDirectDropMax));
         props.setProperty("postMotionRawDirectDropMax", Double.toString(this.postMotionRawDirectDropMax));
         props.setProperty("postMotionIndirectDropMax", Double.toString(this.postMotionIndirectDropMax));
         props.setProperty("postMotionStageIndirectDropMax", Double.toString(this.postMotionStageIndirectDropMax));
         props.setProperty("motionRepeatDirectDeltaAvg", Double.toString(this.averageMotionRepeatDelta(true)));
         props.setProperty("motionRepeatDirectDeltaMax", Double.toString(this.motionRepeatDirectDeltaMax));
         props.setProperty("motionRepeatDirectDeltaSamples", Integer.toString(this.motionRepeatDirectDeltaSamples));
         props.setProperty("motionRepeatIndirectDeltaAvg", Double.toString(this.averageMotionRepeatDelta(false)));
         props.setProperty("motionRepeatIndirectDeltaMax", Double.toString(this.motionRepeatIndirectDeltaMax));
         props.setProperty("motionRepeatIndirectDeltaSamples", Integer.toString(this.motionRepeatIndirectDeltaSamples));
         props.setProperty("motionRepeatDirectTopDeltas", formatRepeatDeltaDiagnostics(this.topDirectRepeatDeltas));
         props.setProperty("motionRepeatIndirectTopDeltas", formatRepeatDeltaDiagnostics(this.topIndirectRepeatDeltas));
         props.setProperty("maxMotionRepeatDirectDeltaAvg", Double.toString(this.maxMotionRepeatDirectDeltaAvg));
         props.setProperty("maxMotionRepeatDirectDeltaMax", Double.toString(this.maxMotionRepeatDirectDeltaMax));
         props.setProperty("maxMotionRepeatIndirectDeltaAvg", Double.toString(this.maxMotionRepeatIndirectDeltaAvg));
         props.setProperty("maxMotionRepeatIndirectDeltaMax", Double.toString(this.maxMotionRepeatIndirectDeltaMax));
         props.setProperty("patchId", this.patchId);

         try (OutputStream outputStream = Files.newOutputStream(this.reportFile)) {
            props.store(outputStream, null);
         }
      } catch (IOException e) {
         Photonic.error("Failed to write shader automation report", e);
      }
   }

   private boolean buildSuccess() {
      return this.failureReason.isBlank()
         && this.expectedShaderPackMatched
         && this.patchIdMatches()
         && this.raytracerActive
         && (!this.requireDirectSignal || this.directSignalDetected)
         && this.directSoftSignalSatisfied()
         && this.worldAutomationSatisfied()
         && this.motionRepeatValidationSatisfied()
         && isCompletionSatisfied(
            this.capturesTaken,
            this.captureTarget,
            this.litCapturesTaken,
            this.minLitCaptures,
            this.lightingSignalDetected,
            this.activeTicks,
            this.minActiveTicksBeforeSuccess,
            activeTicksSinceFirstSignal(this.activeTicks, this.firstLightingSignalActiveTick),
            this.minActiveTicksAfterSignal);
   }

   private boolean patchIdMatches() {
      return matchesExpectedPatchIdPrefix(this.expectedPatchIdPrefix, this.patchId);
   }

   private boolean shouldCaptureThisFrame() {
      if (this.pendingBurstCaptures > 0) {
         this.pendingBurstCaptures--;
         return true;
      }
      if (shouldCaptureOnActiveTick(this.activeTicks, this.captureEveryActiveTicks, this.lastCapturedActiveTick)) {
         this.lastCapturedActiveTick = this.activeTicks;
         return true;
      }
      if (this.captureEveryActiveTicks > 0) {
         return false;
      }
      return this.renderedFrames % this.captureEveryN == 0;
   }

   private boolean isCameraMotionEnabled() {
      return !"none".equals(this.cameraMotionMode)
         && this.cameraMotionPeriodTicks > 0
         && (this.cameraYawAmplitudeDegrees > 0.0f || this.cameraPitchAmplitudeDegrees > 0.0f);
   }

   private boolean isMotionRepeatValidationEnabled() {
      return this.isCameraMotionEnabled() && this.captureEveryActiveTicks > 0;
   }

   private boolean worldAutomationSatisfied() {
      if (this.timeOfDaySequence.length > 0 && this.timeOfDayCommandsIssued < this.timeOfDaySequence.length) {
         return false;
      }
      return this.blockToggleCount <= 0 || this.blockToggleCommandsIssued >= this.blockToggleCount;
   }

   private boolean directSoftSignalSatisfied() {
      return this.directSoftSignalDetected || this.directSoftZeroCaptureCount < 50;
   }

   private boolean motionRepeatValidationSatisfied() {
      if (!this.isMotionRepeatValidationEnabled()) {
         return true;
      }
      if (this.motionRepeatDirectDeltaSamples == 0 || this.motionRepeatIndirectDeltaSamples == 0) {
         return false;
      }
      return thresholdSatisfied(this.averageMotionRepeatDelta(true), this.maxMotionRepeatDirectDeltaAvg)
         && thresholdSatisfied(this.motionRepeatDirectDeltaMax, this.maxMotionRepeatDirectDeltaMax)
         && thresholdSatisfied(this.averageMotionRepeatDelta(false), this.maxMotionRepeatIndirectDeltaAvg)
         && thresholdSatisfied(this.motionRepeatIndirectDeltaMax, this.maxMotionRepeatIndirectDeltaMax);
   }

   private static boolean thresholdSatisfied(double value, double maxAllowed) {
      return maxAllowed < 0.0 || value <= maxAllowed;
   }

   private static float clampPitch(float pitch) {
      return Math.max(-89.0f, Math.min(89.0f, pitch));
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
            + " (directMaxLuma=" + this.directMaxLuma
            + ", directSoftMaxLuma=" + this.directSoftMaxLuma
            + ", directDenoisedMaxLuma=" + this.directDenoisedMaxLuma
            + ", directRawMaxLuma=" + this.directRawMaxLuma
            + ", lightingBufferMaxLuma=" + this.lightingBufferMaxLuma
            + ", stageLightingMaxLuma=" + this.stageLightingMaxLuma
            + ")";
      }
      if (!this.directSoftSignalSatisfied()) {
         return "direct_soft remained black for " + this.directSoftZeroCaptureCount + " captures";
      }
      if (this.litCapturesTaken < this.minLitCaptures) {
         return "Insufficient lit captures: " + this.litCapturesTaken + "/" + this.minLitCaptures;
      }
      if (this.isMotionRepeatValidationEnabled()) {
         if (this.motionRepeatDirectDeltaSamples == 0 || this.motionRepeatIndirectDeltaSamples == 0) {
            return "Camera-motion validation captured no repeated phases (directSamples="
               + this.motionRepeatDirectDeltaSamples
               + ", indirectSamples="
               + this.motionRepeatIndirectDeltaSamples
               + ")";
         }
         if (!thresholdSatisfied(this.averageMotionRepeatDelta(true), this.maxMotionRepeatDirectDeltaAvg)) {
            return "Direct repeat delta average exceeded threshold: "
               + this.averageMotionRepeatDelta(true)
               + " > "
               + this.maxMotionRepeatDirectDeltaAvg;
         }
         if (!thresholdSatisfied(this.motionRepeatDirectDeltaMax, this.maxMotionRepeatDirectDeltaMax)) {
            return "Direct repeat delta max exceeded threshold: "
               + this.motionRepeatDirectDeltaMax
               + " > "
               + this.maxMotionRepeatDirectDeltaMax
               + " topDeltas=["
               + formatRepeatDeltaDiagnostics(this.topDirectRepeatDeltas)
               + "]";
         }
         if (!thresholdSatisfied(this.averageMotionRepeatDelta(false), this.maxMotionRepeatIndirectDeltaAvg)) {
            return "Indirect repeat delta average exceeded threshold: "
               + this.averageMotionRepeatDelta(false)
               + " > "
               + this.maxMotionRepeatIndirectDeltaAvg
               + " topDeltas=["
               + formatRepeatDeltaDiagnostics(this.topIndirectRepeatDeltas)
               + "]";
         }
         if (!thresholdSatisfied(this.motionRepeatIndirectDeltaMax, this.maxMotionRepeatIndirectDeltaMax)) {
            return "Indirect repeat delta max exceeded threshold: "
               + this.motionRepeatIndirectDeltaMax
               + " > "
               + this.maxMotionRepeatIndirectDeltaMax
               + " topDeltas=["
               + formatRepeatDeltaDiagnostics(this.topIndirectRepeatDeltas)
               + "]";
         }
      }
      if (this.timeOfDaySequence.length > 0 && this.timeOfDayCommandsIssued < this.timeOfDaySequence.length) {
         return "Time-of-day automation incomplete: " + this.timeOfDayCommandsIssued + "/" + this.timeOfDaySequence.length;
      }
      if (this.blockToggleCount > 0 && this.blockToggleCommandsIssued < this.blockToggleCount) {
         return "Block-toggle automation incomplete: " + this.blockToggleCommandsIssued + "/" + this.blockToggleCount;
      }
      if (this.activeTicks < this.minActiveTicksBeforeSuccess) {
         return "Automation ended before minimum active ticks: " + this.activeTicks + "/" + this.minActiveTicksBeforeSuccess;
      }
      int activeTicksSinceFirstSignal = activeTicksSinceFirstSignal(this.activeTicks, this.firstLightingSignalActiveTick);
      if (activeTicksSinceFirstSignal < this.minActiveTicksAfterSignal) {
         return "Automation ended before post-signal settle window: " + activeTicksSinceFirstSignal + "/" + this.minActiveTicksAfterSignal;
      }
      return "Automation failed";
   }

   private record MotionRepeatKey(
      int phaseKey,
      int timeOfDayCommandCount,
      int blockToggleCommandCount
   ) {
   }

   private record MotionPhaseSample(
      BufferedImage image,
      int captureIndex,
      int activeTick,
      int ticksSinceAutomationCommand,
      int timeOfDayCommandCount,
      int blockToggleCommandCount
   ) {
   }

   private record MotionRepeatDeltaRecord(
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
      int currentBlockToggleCommandCount
   ) {
   }
}









