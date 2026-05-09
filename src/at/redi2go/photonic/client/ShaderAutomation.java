package at.redi2go.photonic.client;

import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.opengl.rendering.RegirComputeProgram;
import at.redi2go.photonic.client.rendering.util.BufferUtils;
import at.redi2go.photonic.client.rendering.opengl.rendering.renderers.MainRenderer;
import at.redi2go.photonic.client.rendering.world.LightRegistry;
import at.redi2go.photonic.client.rendering.world.WorldRegistry;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
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
   private static final int RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED = 1;
   private static final int RTXDI_TILE_SIZE_IN_PIXELS = 16;
   private static final float REGIR_CELL_SIZE = 32.0f;
   private static final int REGIR_HASH_MAX_PROBES = 128;
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
   private final double maxDirectTemporalDeltaAvg;
   private final double maxDirectTemporalDeltaMax;
   private final double maxIndirectTemporalDeltaAvg;
   private final double maxIndirectTemporalDeltaMax;
   private final double maxIndirectLinearOverbrightFraction;
   private final double maxIndirectLinearSevereFireflyFraction;
   private final double maxIndirectRawLinearOverbrightFraction;
   private final int worldPrepActiveTick;
   private final int stableSceneSettleTicks;
   private final int stableSceneBlendRegionThreshold;
   private final double stableSceneBlendFactorThreshold;
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
   private double latestDirectRawLinearMeanLuma = 0.0;
   private double latestDirectRawLinearMaxLuma = 0.0;
   private double latestDirectRawLinearOverbrightFraction = 0.0;
   private double latestDirectRawLinearFireflyFraction = 0.0;
   private double latestDirectRawLinearSevereFireflyFraction = 0.0;
   private double latestDirectRawLinearFireflyLumaShare = 0.0;
   private double latestDirectRawLinearSaturatedPixelFraction = 0.0;
   private double latestDirectRawLinearNonFiniteFraction = 0.0;
   private double latestDirectDenoisedLinearMeanLuma = 0.0;
   private double latestDirectDenoisedLinearMaxLuma = 0.0;
   private double latestDirectDenoisedLinearOverbrightFraction = 0.0;
   private double latestDirectDenoisedLinearFireflyFraction = 0.0;
   private double latestDirectDenoisedLinearSevereFireflyFraction = 0.0;
   private double latestDirectDenoisedLinearFireflyLumaShare = 0.0;
   private double latestDirectDenoisedLinearSaturatedPixelFraction = 0.0;
   private double latestDirectDenoisedLinearNonFiniteFraction = 0.0;
   private double latestLightingMeanLuma = 0.0;
   private double latestStageLightingMeanLuma = 0.0;
   private double latestStageIndirectMeanLuma = 0.0;
   private double latestIndirectMeanLuma = 0.0;
   private double latestIndirectRawMeanLuma = 0.0;
   private double latestIndirectRawLinearMeanLuma = 0.0;
   private double latestIndirectRawLinearMaxLuma = 0.0;
   private double latestIndirectRawLinearOverbrightFraction = 0.0;
   private double latestIndirectRawLinearFireflyFraction = 0.0;
   private double latestIndirectRawLinearSevereFireflyFraction = 0.0;
   private double latestIndirectRawLinearFireflyLumaShare = 0.0;
   private double latestIndirectRawLinearSaturatedPixelFraction = 0.0;
   private double latestIndirectRawLinearNonFiniteFraction = 0.0;
   private double latestStageIndirectLinearMeanLuma = 0.0;
   private double latestStageIndirectLinearMaxLuma = 0.0;
   private double latestStageIndirectLinearOverbrightFraction = 0.0;
   private double latestIndirectLinearMeanLuma = 0.0;
   private double latestIndirectLinearMaxLuma = 0.0;
   private double latestIndirectLinearOverbrightFraction = 0.0;
   private double latestIndirectLinearFireflyFraction = 0.0;
   private double latestIndirectLinearSevereFireflyFraction = 0.0;
   private double latestIndirectLinearFireflyLumaShare = 0.0;
   private double latestIndirectLinearSaturatedPixelFraction = 0.0;
   private double latestIndirectLinearNonFiniteFraction = 0.0;
   private double latestSpecRawLinearMeanLuma = 0.0;
   private double latestSpecRawLinearMaxLuma = 0.0;
   private double latestSpecRawLinearOverbrightFraction = 0.0;
   private double latestSpecRawLinearFireflyFraction = 0.0;
   private double latestSpecRawLinearSevereFireflyFraction = 0.0;
   private double latestSpecRawLinearFireflyLumaShare = 0.0;
   private double latestSpecRawLinearSaturatedPixelFraction = 0.0;
   private double latestSpecRawLinearNonFiniteFraction = 0.0;
   private double latestSpecDenoisedLinearMeanLuma = 0.0;
   private double latestSpecDenoisedLinearMaxLuma = 0.0;
   private double latestSpecDenoisedLinearOverbrightFraction = 0.0;
   private double latestSpecDenoisedLinearFireflyFraction = 0.0;
   private double latestSpecDenoisedLinearSevereFireflyFraction = 0.0;
   private double latestSpecDenoisedLinearFireflyLumaShare = 0.0;
   private double latestSpecDenoisedLinearSaturatedPixelFraction = 0.0;
   private double latestSpecDenoisedLinearNonFiniteFraction = 0.0;
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
   private double directTemporalDeltaSum = 0.0;
   private double directTemporalDeltaMax = 0.0;
   private int directTemporalDeltaSamples = 0;
   private double latestDirectTemporalDelta = 0.0;
   private double latestDirectTemporalMaxPixelDelta = 0.0;
   private double latestWholeLightFlashDirectDrop = 0.0;
   private double latestWholeLightFlashResolvedValidDrop = 0.0;
   private double latestWholeLightFlashLightCountDrop = 0.0;
   private double latestWholeLightFlashBlendFactorJump = 0.0;
   private double maxWholeLightFlashDirectDrop = 0.0;
   private double maxWholeLightFlashResolvedValidDrop = 0.0;
   private double maxWholeLightFlashLightCountDrop = 0.0;
   private double maxWholeLightFlashBlendFactorJump = 0.0;
   private int wholeLightFlashSuspectCaptures = 0;
   private int wholeLightFlashLastCapture = -1;
   private int wholeLightFlashDirectDropCaptures = 0;
   private int wholeLightFlashResolvedValidDropCaptures = 0;
   private int wholeLightFlashLightCountDropCaptures = 0;
   private int wholeLightFlashBlendJumpCaptures = 0;
   private double previousCaptureDirectMeanLuma = Double.NaN;
   private double previousCaptureResolvedStrictValidFraction = Double.NaN;
   private double previousCaptureResolvedMeanWeight = Double.NaN;
   private double previousCaptureResolvedMeanM = Double.NaN;
   private double previousCaptureLightBlendFactor = Double.NaN;
   private int previousCaptureTracedLightCount = -1;
   private double latestResolvedMeanM = 0.0;
   private double latestWholeLightFlashResolvedMDrop = 0.0;
   private double maxWholeLightFlashResolvedMDrop = 0.0;
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
   private double specDenoiserGainSum = 0.0;
   private double specDenoiserGainMax = 0.0;
   private int specDenoiserGainSamples = 0;
   private double indirectResolveGainSum = 0.0;
   private double indirectResolveGainMax = 0.0;
   private int indirectResolveGainSamples = 0;
   private double latestDirectDenoiserGain = 0.0;
   private double latestSpecDenoiserGain = 0.0;
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
   private boolean fullScreenshotSaved = false;
   private boolean reportInitialized = false;
   private boolean fullscreenApplied = false;
   private boolean cameraBaselineCaptured = false;
   private boolean worldAutomationPrepared = false;
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
      this.maxDirectTemporalDeltaAvg = Double.parseDouble(System.getProperty("photonics.automation.maxDirectTemporalDeltaAvg", "-1"));
      this.maxDirectTemporalDeltaMax = Double.parseDouble(System.getProperty("photonics.automation.maxDirectTemporalDeltaMax", "-1"));
      this.maxIndirectTemporalDeltaAvg = Double.parseDouble(System.getProperty("photonics.automation.maxIndirectTemporalDeltaAvg", "-1"));
      this.maxIndirectTemporalDeltaMax = Double.parseDouble(System.getProperty("photonics.automation.maxIndirectTemporalDeltaMax", "-1"));
      this.maxIndirectLinearOverbrightFraction = Double.parseDouble(System.getProperty("photonics.automation.maxIndirectLinearOverbrightFraction", "-1"));
      this.maxIndirectLinearSevereFireflyFraction = Double.parseDouble(System.getProperty("photonics.automation.maxIndirectLinearSevereFireflyFraction", "-1"));
      this.maxIndirectRawLinearOverbrightFraction = Double.parseDouble(System.getProperty("photonics.automation.maxIndirectRawLinearOverbrightFraction", "-1"));
      this.worldPrepActiveTick = Math.max(1, Integer.getInteger("photonics.automation.worldPrepActiveTick", 1));
      this.stableSceneSettleTicks = Math.max(0, Integer.getInteger("photonics.automation.stableSceneSettleTicks", Math.max(this.captureEveryActiveTicks * 2, 120)));
      this.stableSceneBlendRegionThreshold = Math.max(0, Integer.getInteger("photonics.automation.stableSceneBlendRegionThreshold", 0));
      this.stableSceneBlendFactorThreshold = Math.max(0.0, Double.parseDouble(System.getProperty("photonics.automation.stableSceneBlendFactorThreshold", "0.0")));
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

   public static boolean suppressWorldMutationIngress() {
      return INSTANCE != null && INSTANCE.shouldSuppressWorldMutationIngress();
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

   private static ReservoirDebugStats computeReservoirDebugStats(TextureObject texture) {
      if (texture == null) {
         return ReservoirDebugStats.EMPTY;
      }

      texture.updatePerFrame();
      float[] pixels = texture.downloadFloatData();
      if (pixels == null || pixels.length < 4) {
         return ReservoirDebugStats.EMPTY;
      }

      int pixelCount = pixels.length / 4;
      int lightValidPixels = 0;
      int strictValidPixels = 0;
      double weightSum = 0.0;
      double mSum = 0.0;
      for (int i = 0; i < pixelCount; i++) {
         int base = i * 4;
         int lightData = Float.floatToRawIntBits(pixels[base]);
         float weight = pixels[base + 1];
         int reservoirM = decodePackedReservoirM(pixels[base + 3]);
         if (lightData != 0) {
            lightValidPixels++;
         }
         if (lightData != 0 && weight > 0.0f && reservoirM > 0) {
            strictValidPixels++;
         }
         weightSum += Math.max(weight, 0.0f);
         mSum += reservoirM;
      }

      return new ReservoirDebugStats(
         lightValidPixels / (double)pixelCount,
         strictValidPixels / (double)pixelCount,
         weightSum / pixelCount,
         mSum / pixelCount
      );
   }

   static int decodePackedReservoirM(float packedVisibilityAndM) {
      int packed = Float.floatToRawIntBits(packedVisibilityAndM);
      return (packed >>> RTXDI_PACKED_DI_RESERVOIR_M_SHIFT) & RTXDI_PACKED_DI_RESERVOIR_MAX_M_UINT;
   }

   private static InitialSamplingDebugStats computeInitialSamplingDebugStats(TextureObject texture) {
      if (texture == null) {
         return InitialSamplingDebugStats.EMPTY;
      }

      texture.updatePerFrame();
      int[] dimensions = texture.getTextureDimensions();
      if (dimensions.length < 2 || dimensions[0] <= 0 || dimensions[1] <= 1) {
         return InitialSamplingDebugStats.EMPTY;
      }

      float[] pixels = texture.downloadFloatData();
      if (pixels == null || pixels.length < 4) {
         return InitialSamplingDebugStats.EMPTY;
      }

      int width = dimensions[0];
      int height = dimensions[1];
      int pixelCount = Math.max(1, width * height);
      int[] reasonCounts = new int[11];
      double positiveCandidateFractionSum = 0.0;
      double proposalValidSum = 0.0;
      double proposalWeightSum = 0.0;
      double[] successRows = new double[height];
      double[] zeroTargetRows = new double[height];
      double[] proposalValidRows = new double[height];
      double[] proposalWeightRows = new double[height];

      for (int y = 0; y < height; y++) {
         int successCount = 0;
         int zeroTargetCount = 0;
         double proposalValidRowSum = 0.0;
         double proposalWeightRowSum = 0.0;
         for (int x = 0; x < width; x++) {
            int base = (x + y * width) * 4;
            int reason = Math.max(0, Math.min(10, Math.round(pixels[base])));
            float positiveCandidateFraction = pixels[base + 1];
            float proposalValid = pixels[base + 2];
            float proposalWeight = pixels[base + 3];

            reasonCounts[reason]++;
            if (Float.isFinite(positiveCandidateFraction)) {
               positiveCandidateFractionSum += Math.max(0.0f, positiveCandidateFraction);
            }
            if (Float.isFinite(proposalValid)) {
               double clampedProposalValid = Math.max(0.0f, Math.min(1.0f, proposalValid));
               proposalValidSum += clampedProposalValid;
               proposalValidRowSum += clampedProposalValid;
            }
            if (Float.isFinite(proposalWeight)) {
               double clampedProposalWeight = Math.max(0.0f, proposalWeight);
               proposalWeightSum += clampedProposalWeight;
               proposalWeightRowSum += clampedProposalWeight;
            }
            if (reason == 10) {
               successCount++;
            }
            if (reason == 7) {
               zeroTargetCount++;
            }
         }
         successRows[y] = successCount / (double)Math.max(1, width);
         zeroTargetRows[y] = zeroTargetCount / (double)Math.max(1, width);
         proposalValidRows[y] = proposalValidRowSum / (double)Math.max(1, width);
         proposalWeightRows[y] = proposalWeightRowSum / (double)Math.max(1, width);
      }

      return new InitialSamplingDebugStats(
         reasonCounts[0] / (double)pixelCount,
         reasonCounts[1] / (double)pixelCount,
         reasonCounts[2] / (double)pixelCount,
         reasonCounts[3] / (double)pixelCount,
         reasonCounts[4] / (double)pixelCount,
         reasonCounts[5] / (double)pixelCount,
         reasonCounts[6] / (double)pixelCount,
         reasonCounts[7] / (double)pixelCount,
         reasonCounts[8] / (double)pixelCount,
         reasonCounts[9] / (double)pixelCount,
         reasonCounts[10] / (double)pixelCount,
         positiveCandidateFractionSum / pixelCount,
         proposalValidSum / pixelCount,
         proposalWeightSum / pixelCount,
         computeRowJumpStats(successRows),
         computeRowJumpStats(zeroTargetRows),
         computeRowJumpStats(proposalValidRows),
         computeRowJumpStats(proposalWeightRows)
      );
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

   private static ReGIRPixelCorrelationStats computeReGIRPixelCorrelationStats(
      TextureObject resolvedReservoirTexture,
      TextureObject stagePositionTexture,
      LightRegistry lightRegistry,
      int frameIndex
   ) {
      if (resolvedReservoirTexture == null || stagePositionTexture == null || lightRegistry == null) {
         return ReGIRPixelCorrelationStats.EMPTY;
      }

      resolvedReservoirTexture.updatePerFrame();
      stagePositionTexture.updatePerFrame();
      int[] resolvedDimensions = resolvedReservoirTexture.getTextureDimensions();
      int[] stageDimensions = stagePositionTexture.getTextureDimensions();
      if (resolvedDimensions.length < 2
         || stageDimensions.length < 2
         || resolvedDimensions[0] <= 0
         || resolvedDimensions[1] <= 1
         || resolvedDimensions[0] != stageDimensions[0]
         || resolvedDimensions[1] != stageDimensions[1]) {
         return ReGIRPixelCorrelationStats.EMPTY;
      }

      float[] resolvedPixels = resolvedReservoirTexture.downloadFloatData();
      float[] stagePixels = stagePositionTexture.downloadFloatData();
      if (resolvedPixels == null || stagePixels == null) {
         return ReGIRPixelCorrelationStats.EMPTY;
      }

      ReGIRCellBufferStats cellBufferStats = downloadReGIRCellBufferStats(lightRegistry);
      if (cellBufferStats.validSlotCounts().length == 0 || cellBufferStats.meanWeights().length == 0) {
         return ReGIRPixelCorrelationStats.EMPTY;
      }

      int width = resolvedDimensions[0];
      int height = resolvedDimensions[1];
      float samplingJitter = lightRegistry.getRegirLookupJitter();
      float hashCellSize = lightRegistry.getRegirHashCellSizeBlocks();
      int hashNormalBuckets = lightRegistry.getRegirHashNormalBuckets();
      double[] cellValidSlotRows = new double[height];
      double[] cellMeanWeightRows = new double[height];
      double[] outsideGridRows = new double[height];
      double[] jitteredCellChangedRows = new double[height];
      double[] jitteredCellMeanWeightDeltaRows = new double[height];
      double[] jitteredOutsideGridDeltaRows = new double[height];
      int visiblePixels = 0;
      int resolvedStrictValidVisiblePixels = 0;
      int exactOutsideGridVisiblePixels = 0;
      int exactOutsideGridStrictInvalidPixels = 0;
      int exactOutsideGridStrictValidPixels = 0;
      int zeroSlotStrictInvalidPixels = 0;
      int zeroSlotStrictValidPixels = 0;
      double strictInvalidCellSlotSum = 0.0;
      double strictValidCellSlotSum = 0.0;
      double strictInvalidCellWeightSum = 0.0;
      double strictValidCellWeightSum = 0.0;
      int strictInvalidInsideGridPixels = 0;
      int strictValidInsideGridPixels = 0;
      int jitteredCellChangedVisiblePixels = 0;
      int jitteredOutsideGridDeltaVisiblePixels = 0;
      double jitteredCellMeanWeightDeltaSum = 0.0;

      for (int y = 0; y < height; y++) {
         int rowVisiblePixels = 0;
         int rowOutsideGridPixels = 0;
         int rowJitteredCellChangedPixels = 0;
         int rowJitteredOutsideGridDeltaPixels = 0;
         double rowCellSlotSum = 0.0;
         double rowCellWeightSum = 0.0;
         double rowJitteredCellMeanWeightDeltaSum = 0.0;

         for (int x = 0; x < width; x++) {
            int base = (x + y * width) * 4;
            float px = stagePixels[base];
            float py = stagePixels[base + 1];
            float pz = stagePixels[base + 2];
            if (!Float.isFinite(px) || !Float.isFinite(py) || !Float.isFinite(pz)) {
               continue;
            }
            if (Math.abs(px) < 1.0e-6f && Math.abs(py) < 1.0e-6f && Math.abs(pz) < 1.0e-6f) {
               continue;
            }

            rowVisiblePixels++;
            visiblePixels++;

            int resolvedLightData = Float.floatToRawIntBits(resolvedPixels[base]);
            float resolvedWeight = resolvedPixels[base + 1];
            int resolvedM = decodePackedReservoirM(resolvedPixels[base + 3]);
            boolean strictValid = resolvedLightData != 0 && resolvedWeight > 0.0f && resolvedM > 0;
            if (strictValid) {
               resolvedStrictValidVisiblePixels++;
            }

            ReGIRHashCellCoord shaderCellCoord = calculateExactReGIRHashCellCoord(hashCellSize, px, py, pz);
            ReGIRHashCellCoord jitteredReferenceCellCoord = calculateJitteredReGIRHashCellCoord(
               x,
               y,
               frameIndex,
               hashCellSize,
               samplingJitter,
               px,
               py,
               pz
            );
            if (!shaderCellCoord.equals(jitteredReferenceCellCoord)) {
               rowJitteredCellChangedPixels++;
               jitteredCellChangedVisiblePixels++;
            }

            ReGIRCellSampleStats shaderCellStats = lookupReGIRHashCellStats(cellBufferStats, shaderCellCoord, hashNormalBuckets);
            ReGIRCellSampleStats jitteredCellStats = lookupReGIRHashCellStats(cellBufferStats, jitteredReferenceCellCoord, hashNormalBuckets);
            if (shaderCellStats.found() != jitteredCellStats.found()) {
               rowJitteredOutsideGridDeltaPixels++;
               jitteredOutsideGridDeltaVisiblePixels++;
            }
            if (shaderCellStats.found() && jitteredCellStats.found()) {
               double shaderCellMeanWeight = shaderCellStats.meanWeight();
               double jitteredCellMeanWeight = jitteredCellStats.meanWeight();
               double jitteredCellMeanWeightDelta = Math.abs(jitteredCellMeanWeight - shaderCellMeanWeight);
               rowJitteredCellMeanWeightDeltaSum += jitteredCellMeanWeightDelta;
               jitteredCellMeanWeightDeltaSum += jitteredCellMeanWeightDelta;
            }
            if (!shaderCellStats.found()) {
               rowOutsideGridPixels++;
               exactOutsideGridVisiblePixels++;
               if (strictValid) {
                  exactOutsideGridStrictValidPixels++;
               } else {
                  exactOutsideGridStrictInvalidPixels++;
               }
               continue;
            }

            int cellValidSlots = shaderCellStats.validSlots();
            double cellMeanWeight = shaderCellStats.meanWeight();
            rowCellSlotSum += cellValidSlots;
            rowCellWeightSum += cellMeanWeight;

            if (strictValid) {
               strictValidInsideGridPixels++;
               strictValidCellSlotSum += cellValidSlots;
               strictValidCellWeightSum += cellMeanWeight;
               if (cellValidSlots == 0) {
                  zeroSlotStrictValidPixels++;
               }
            } else {
               strictInvalidInsideGridPixels++;
               strictInvalidCellSlotSum += cellValidSlots;
               strictInvalidCellWeightSum += cellMeanWeight;
               if (cellValidSlots == 0) {
                  zeroSlotStrictInvalidPixels++;
               }
            }
         }

         cellValidSlotRows[y] = rowVisiblePixels == 0 ? 0.0 : rowCellSlotSum / rowVisiblePixels;
         cellMeanWeightRows[y] = rowVisiblePixels == 0 ? 0.0 : rowCellWeightSum / rowVisiblePixels;
         outsideGridRows[y] = rowVisiblePixels == 0 ? 0.0 : rowOutsideGridPixels / (double) rowVisiblePixels;
         jitteredCellChangedRows[y] = rowVisiblePixels == 0 ? 0.0 : rowJitteredCellChangedPixels / (double) rowVisiblePixels;
         jitteredCellMeanWeightDeltaRows[y] = rowVisiblePixels == 0 ? 0.0 : rowJitteredCellMeanWeightDeltaSum / rowVisiblePixels;
         jitteredOutsideGridDeltaRows[y] = rowVisiblePixels == 0 ? 0.0 : rowJitteredOutsideGridDeltaPixels / (double) rowVisiblePixels;
      }

      double visiblePixelCount = Math.max(1, visiblePixels);
      return new ReGIRPixelCorrelationStats(
         visiblePixels / (double) Math.max(1, width * height),
         resolvedStrictValidVisiblePixels / visiblePixelCount,
         exactOutsideGridVisiblePixels / visiblePixelCount,
         exactOutsideGridStrictInvalidPixels / visiblePixelCount,
         exactOutsideGridStrictValidPixels / visiblePixelCount,
         strictInvalidInsideGridPixels == 0 ? 0.0 : zeroSlotStrictInvalidPixels / (double) strictInvalidInsideGridPixels,
         strictValidInsideGridPixels == 0 ? 0.0 : zeroSlotStrictValidPixels / (double) strictValidInsideGridPixels,
         strictInvalidInsideGridPixels == 0 ? 0.0 : strictInvalidCellSlotSum / strictInvalidInsideGridPixels,
         strictValidInsideGridPixels == 0 ? 0.0 : strictValidCellSlotSum / strictValidInsideGridPixels,
         strictInvalidInsideGridPixels == 0 ? 0.0 : strictInvalidCellWeightSum / strictInvalidInsideGridPixels,
         strictValidInsideGridPixels == 0 ? 0.0 : strictValidCellWeightSum / strictValidInsideGridPixels,
         jitteredCellChangedVisiblePixels / visiblePixelCount,
         jitteredCellMeanWeightDeltaSum / visiblePixelCount,
         jitteredOutsideGridDeltaVisiblePixels / visiblePixelCount,
         computeRowJumpStats(cellValidSlotRows),
         computeRowJumpStats(cellMeanWeightRows),
         computeRowJumpStats(outsideGridRows),
         computeRowJumpStats(jitteredCellChangedRows),
         computeRowJumpStats(jitteredCellMeanWeightDeltaRows),
         computeRowJumpStats(jitteredOutsideGridDeltaRows)
      );
   }

   private static ReGIRCellBufferStats downloadReGIRCellBufferStats(LightRegistry lightRegistry) {
      int hashTableSize = lightRegistry.getRegirHashTableSize();
      int lightsPerCell = lightRegistry.getRegirLightsPerCell();
      if (hashTableSize <= 0 || lightsPerCell <= 0) {
         return ReGIRCellBufferStats.EMPTY;
      }

      int[] validSlotCounts = new int[hashTableSize];
      double[] meanWeights = new double[hashTableSize];
      int[] checksums = new int[hashTableSize];
      int[] keyX = new int[hashTableSize];
      int[] keyY = new int[hashTableSize];
      int[] keyZ = new int[hashTableSize];
      int[] keyBucket = new int[hashTableSize];
      int regirEntryOffset = RegirComputeProgram.tileCount * RegirComputeProgram.tileSize;
      lightRegistry.getRegirLightIndexMemoryManager().download(downloadedBuffer -> {
         ByteBuffer data = downloadedBuffer.duplicate().order(ByteOrder.LITTLE_ENDIAN);
         for (int hashSlot = 0; hashSlot < hashTableSize; hashSlot++) {
            int validSlots = 0;
            double weightSum = 0.0;
            int cellEntryBase = regirEntryOffset + hashSlot * lightsPerCell;
            for (int slot = 0; slot < lightsPerCell; slot++) {
               int byteIndex = (cellEntryBase + slot) * 8;
               if (byteIndex + 8 > data.capacity()) {
                  break;
               }

               float storedWeight = Float.intBitsToFloat(data.getInt(byteIndex + 4));
               if (Float.isFinite(storedWeight) && storedWeight > 0.0f) {
                  validSlots++;
                  weightSum += storedWeight;
               }
            }

            validSlotCounts[hashSlot] = validSlots;
            meanWeights[hashSlot] = validSlots == 0 ? 0.0 : weightSum / validSlots;
         }
      });
      lightRegistry.getRegirHashChecksumMemoryManager().download(downloadedBuffer -> {
         ByteBuffer data = downloadedBuffer.duplicate().order(ByteOrder.LITTLE_ENDIAN);
         for (int hashSlot = 0; hashSlot < hashTableSize && hashSlot * Integer.BYTES + Integer.BYTES <= data.capacity(); hashSlot++) {
            checksums[hashSlot] = data.getInt(hashSlot * Integer.BYTES);
         }
      });
      lightRegistry.getRegirHashKeyMemoryManager().download(downloadedBuffer -> {
         ByteBuffer data = downloadedBuffer.duplicate().order(ByteOrder.LITTLE_ENDIAN);
         for (int hashSlot = 0; hashSlot < hashTableSize; hashSlot++) {
            int byteIndex = hashSlot * 4 * Integer.BYTES;
            if (byteIndex + 4 * Integer.BYTES > data.capacity()) {
               break;
            }
            keyX[hashSlot] = data.getInt(byteIndex);
            keyY[hashSlot] = data.getInt(byteIndex + Integer.BYTES);
            keyZ[hashSlot] = data.getInt(byteIndex + 2 * Integer.BYTES);
            keyBucket[hashSlot] = data.getInt(byteIndex + 3 * Integer.BYTES);
         }
      });

      return new ReGIRCellBufferStats(validSlotCounts, meanWeights, checksums, keyX, keyY, keyZ, keyBucket);
   }

   private static ReGIRHashCellCoord calculateJitteredReGIRHashCellCoord(
      int pixelX,
      int pixelY,
      int frameIndex,
      float hashCellSize,
      float samplingJitter,
      float worldX,
      float worldY,
      float worldZ
   ) {
      ReGIRHashCellCoord baseCell = calculateExactReGIRHashCellCoord(hashCellSize, worldX, worldY, worldZ);
      int geometrySeed = regirHashPcgKey(baseCell.x(), baseCell.y(), baseCell.z(), 0)
         ^ regirHashXxhashChecksum(baseCell.x(), baseCell.y(), baseCell.z(), 0);
      RandomSamplerState coherentRng = initRTXDIRandomSampler(
         geometrySeed,
         geometrySeed >>> 16,
         0,
         RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED
      );
      float jitterScale = samplingJitter * hashCellSize * 0.5f;
      float jitteredX = worldX + (nextRTXDIRandom(coherentRng) - 0.5f) * jitterScale;
      float jitteredY = worldY + (nextRTXDIRandom(coherentRng) - 0.5f) * jitterScale;
      float jitteredZ = worldZ + (nextRTXDIRandom(coherentRng) - 0.5f) * jitterScale;
      return calculateExactReGIRHashCellCoord(hashCellSize, jitteredX, jitteredY, jitteredZ);
   }

   private static ReGIRHashCellCoord calculateExactReGIRHashCellCoord(
      float hashCellSize,
      float worldX,
      float worldY,
      float worldZ
   ) {
      return new ReGIRHashCellCoord(
         (int) Math.floor(worldX / hashCellSize),
         (int) Math.floor(worldY / hashCellSize),
         (int) Math.floor(worldZ / hashCellSize)
      );
   }

   private static ReGIRCellSampleStats lookupReGIRHashCellStats(
      ReGIRCellBufferStats stats,
      ReGIRHashCellCoord cellCoord,
      int normalBuckets
   ) {
      int validSlots = 0;
      double weightSum = 0.0;
      int representativeSlot = -1;
      for (int bucket = 0; bucket < Math.max(1, normalBuckets); bucket++) {
         int hashSlot = lookupReGIRHashSlot(stats, cellCoord, bucket);
         if (hashSlot < 0) {
            continue;
         }
         if (representativeSlot < 0) {
            representativeSlot = hashSlot;
         }
         int bucketValidSlots = stats.validSlotCounts()[hashSlot];
         validSlots += bucketValidSlots;
         weightSum += stats.meanWeights()[hashSlot] * bucketValidSlots;
      }

      return new ReGIRCellSampleStats(
         representativeSlot,
         validSlots,
         validSlots == 0 ? 0.0 : weightSum / validSlots
      );
   }

   private static int lookupReGIRHashSlot(ReGIRCellBufferStats stats, ReGIRHashCellCoord cellCoord, int bucket) {
      int hashTableSize = stats.checksums().length;
      if (hashTableSize <= 0) {
         return -1;
      }

      int checksum = regirHashXxhashChecksum(cellCoord.x(), cellCoord.y(), cellCoord.z(), bucket);
      int slot = Integer.remainderUnsigned(regirHashPcgKey(cellCoord.x(), cellCoord.y(), cellCoord.z(), bucket), hashTableSize);
      for (int probe = 0; probe < REGIR_HASH_MAX_PROBES; probe++) {
         int stored = stats.checksums()[slot];
         if (stored == 0 || stored == -1) {
            return -1;
         }
         if (stored == checksum
            && stats.keyX()[slot] == cellCoord.x()
            && stats.keyY()[slot] == cellCoord.y()
            && stats.keyZ()[slot] == cellCoord.z()
            && stats.keyBucket()[slot] == bucket) {
            return slot;
         }
         slot = (slot + 1) % hashTableSize;
      }
      return -1;
   }

   private static int regirHashPcgKey(int cellX, int cellY, int cellZ, int bucket) {
      return regirPcgStep(bucket + regirPcgStep(cellZ + regirPcgStep(cellY + regirPcgStep(cellX))));
   }

   private static int regirHashXxhashChecksum(int cellX, int cellY, int cellZ, int bucket) {
      int hash = regirXxhashStep(bucket + regirXxhashStep(cellZ + regirXxhashStep(cellY + regirXxhashStep(cellX))));
      if (hash == 0) {
         return 1;
      }
      if (hash == -1) {
         return -2;
      }
      return hash;
   }

   private static int regirPcgStep(int h) {
      h = h * 747796405 + (int) 2891336453L;
      h = ((h >>> ((h >>> 28) + 4)) ^ h) * 277803737;
      return (h >>> 22) ^ h;
   }

   private static int regirXxhashStep(int h) {
      h += 374761393;
      h = 668265263 * Integer.rotateLeft(h, 17);
      h = -2048144777 * (h ^ (h >>> 15));
      h = -1028477379 * (h ^ (h >>> 13));
      return h ^ (h >>> 16);
   }

   private static RandomSamplerState initRTXDIRandomSampler(int pixelX, int pixelY, int frameIndex, int pass) {
      int linearPixelIndex = rtxdiZCurveToLinearIndex(pixelX, pixelY);
      int seed = rtxdiJenkinsHash(linearPixelIndex) + frameIndex + pass * 31;
      return new RandomSamplerState(seed, 1);
   }

   private static float nextRTXDIRandom(RandomSamplerState rng) {
      int value = murmur3(rng);
      int bits = (value & ((1 << 23) - 1)) | 0x3f800000;
      return Float.intBitsToFloat(bits) - 1.0f;
   }

   private static int murmur3(RandomSamplerState rng) {
      int hash = rng.seed;
      int k = rng.index++;
      k *= 0xcc9e2d51;
      k = Integer.rotateLeft(k, 15);
      k *= 0x1b873593;
      hash ^= k;
      hash = Integer.rotateLeft(hash, 13);
      hash = hash * 5 + 0xe6546b64;
      hash ^= 4;
      hash ^= hash >>> 16;
      hash *= 0x85ebca6b;
      hash ^= hash >>> 13;
      hash *= 0xc2b2ae35;
      hash ^= hash >>> 16;
      return hash;
   }

   private static int rtxdiZCurveToLinearIndex(int x, int y) {
      return rtxdiIntegerExplode(x) | (rtxdiIntegerExplode(y) << 1);
   }

   private static int rtxdiIntegerExplode(int x) {
      x = (x | (x << 8)) & 0x00FF00FF;
      x = (x | (x << 4)) & 0x0F0F0F0F;
      x = (x | (x << 2)) & 0x33333333;
      x = (x | (x << 1)) & 0x55555555;
      return x;
   }

   private static int rtxdiJenkinsHash(int value) {
      int hash = value;
      hash = (hash + 0x7ed55d16) + (hash << 12);
      hash = (hash ^ 0xc761c23c) ^ (hash >>> 19);
      hash = (hash + 0x165667b1) + (hash << 5);
      hash = (hash + 0xd3a2646c) ^ (hash << 9);
      hash = (hash + 0xfd7046c5) + (hash << 3);
      hash = (hash ^ 0xb55a4f09) ^ (hash >>> 16);
      return hash;
   }

   private static boolean isInsideAxisAlignedCube(float x, float y, float z, Vector3f center, float halfExtent) {
      return x >= center.x - halfExtent && x < center.x + halfExtent
         && y >= center.y - halfExtent && y < center.y + halfExtent
         && z >= center.z - halfExtent && z < center.z + halfExtent;
   }

   private static RowJumpStats computeRowJumpStats(double[] rowMeans) {
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
         this.ensureGameplayScreen(client);
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
         ReservoirDebugStats proposalReservoirStats = computeReservoirDebugStats(directReservoirTexture);
         InitialSamplingDebugStats initialSamplingDebugStats = computeInitialSamplingDebugStats(directInitialDebugTexture);
         ReservoirDebugStats resolvedReservoirStats = computeReservoirDebugStats(directResolvedReservoirTexture);
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
         ReGIRPixelCorrelationStats regirPixelCorrelationStats = computeReGIRPixelCorrelationStats(
            directResolvedReservoirTexture,
            stagePositionTexture,
            lightRegistry,
            frameIndex
         );
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
         this.latestDirectRawLinearMeanLuma = directRawLinearStats.meanLuma();
         this.latestDirectRawLinearMaxLuma = directRawLinearStats.maxLuma();
         this.latestDirectRawLinearOverbrightFraction = directRawLinearStats.overbrightFraction();
         this.latestDirectRawLinearFireflyFraction = directRawFireflyStats.fireflyFraction();
         this.latestDirectRawLinearSevereFireflyFraction = directRawFireflyStats.severeFireflyFraction();
         this.latestDirectRawLinearFireflyLumaShare = directRawFireflyStats.fireflyLumaShare();
         this.latestDirectRawLinearSaturatedPixelFraction = directRawFireflyStats.saturatedPixelFraction();
         this.latestDirectRawLinearNonFiniteFraction = directRawFireflyStats.nonFiniteFraction();
         this.latestDirectDenoisedLinearMeanLuma = directDenoisedLinearStats.meanLuma();
         this.latestDirectDenoisedLinearMaxLuma = directDenoisedLinearStats.maxLuma();
         this.latestDirectDenoisedLinearOverbrightFraction = directDenoisedLinearStats.overbrightFraction();
         this.latestDirectDenoisedLinearFireflyFraction = directDenoisedFireflyStats.fireflyFraction();
         this.latestDirectDenoisedLinearSevereFireflyFraction = directDenoisedFireflyStats.severeFireflyFraction();
         this.latestDirectDenoisedLinearFireflyLumaShare = directDenoisedFireflyStats.fireflyLumaShare();
         this.latestDirectDenoisedLinearSaturatedPixelFraction = directDenoisedFireflyStats.saturatedPixelFraction();
         this.latestDirectDenoisedLinearNonFiniteFraction = directDenoisedFireflyStats.nonFiniteFraction();
         this.latestLightingMeanLuma = lightingStats[1];
         this.latestStageLightingMeanLuma = stageLightingStats[1];
         this.latestStageIndirectMeanLuma = stageIndirectStats[1];
         this.latestIndirectRawMeanLuma = indirectRawStats[1];
         this.latestIndirectMeanLuma = indirectStats[1];
         this.latestSpecRawLinearMeanLuma = specRawLinearStats.meanLuma();
         this.latestSpecRawLinearMaxLuma = specRawLinearStats.maxLuma();
         this.latestSpecRawLinearOverbrightFraction = specRawLinearStats.overbrightFraction();
         this.latestSpecRawLinearFireflyFraction = specRawFireflyStats.fireflyFraction();
         this.latestSpecRawLinearSevereFireflyFraction = specRawFireflyStats.severeFireflyFraction();
         this.latestSpecRawLinearFireflyLumaShare = specRawFireflyStats.fireflyLumaShare();
         this.latestSpecRawLinearSaturatedPixelFraction = specRawFireflyStats.saturatedPixelFraction();
         this.latestSpecRawLinearNonFiniteFraction = specRawFireflyStats.nonFiniteFraction();
         this.latestSpecDenoisedLinearMeanLuma = specDenoisedLinearStats.meanLuma();
         this.latestSpecDenoisedLinearMaxLuma = specDenoisedLinearStats.maxLuma();
         this.latestSpecDenoisedLinearOverbrightFraction = specDenoisedLinearStats.overbrightFraction();
         this.latestSpecDenoisedLinearFireflyFraction = specDenoisedFireflyStats.fireflyFraction();
         this.latestSpecDenoisedLinearSevereFireflyFraction = specDenoisedFireflyStats.severeFireflyFraction();
         this.latestSpecDenoisedLinearFireflyLumaShare = specDenoisedFireflyStats.fireflyLumaShare();
         this.latestSpecDenoisedLinearSaturatedPixelFraction = specDenoisedFireflyStats.saturatedPixelFraction();
         this.latestSpecDenoisedLinearNonFiniteFraction = specDenoisedFireflyStats.nonFiniteFraction();
         this.latestIndirectRawLinearMeanLuma = indirectRawLinearStats.meanLuma();
         this.latestIndirectRawLinearMaxLuma = indirectRawLinearStats.maxLuma();
         this.latestIndirectRawLinearOverbrightFraction = indirectRawLinearStats.overbrightFraction();
         this.latestIndirectRawLinearFireflyFraction = indirectRawFireflyStats.fireflyFraction();
         this.latestIndirectRawLinearSevereFireflyFraction = indirectRawFireflyStats.severeFireflyFraction();
         this.latestIndirectRawLinearFireflyLumaShare = indirectRawFireflyStats.fireflyLumaShare();
         this.latestIndirectRawLinearSaturatedPixelFraction = indirectRawFireflyStats.saturatedPixelFraction();
         this.latestIndirectRawLinearNonFiniteFraction = indirectRawFireflyStats.nonFiniteFraction();
         this.latestIndirectLinearMeanLuma = indirectLinearStats.meanLuma();
         this.latestIndirectLinearMaxLuma = indirectLinearStats.maxLuma();
         this.latestIndirectLinearOverbrightFraction = indirectLinearStats.overbrightFraction();
         this.latestIndirectLinearFireflyFraction = indirectFireflyStats.fireflyFraction();
         this.latestIndirectLinearSevereFireflyFraction = indirectFireflyStats.severeFireflyFraction();
         this.latestIndirectLinearFireflyLumaShare = indirectFireflyStats.fireflyLumaShare();
         this.latestIndirectLinearSaturatedPixelFraction = indirectFireflyStats.saturatedPixelFraction();
         this.latestIndirectLinearNonFiniteFraction = indirectFireflyStats.nonFiniteFraction();
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
         this.recordTemporalDelta(directTemporalAndRepeatImage, false, false);
         this.recordTemporalDelta(directSoftImage, true, false);
         this.recordTemporalDelta(indirectImage, false, true);
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
         this.latestSpecDenoiserGain = computeRelativeImprovement(this.latestSpecRawLinearMeanLuma, this.latestSpecDenoisedLinearMeanLuma);
         this.latestIndirectResolveGain = computeRelativeImprovement(stageIndirectStats[1], indirectStats[1]);
         this.directDenoiserGainSum += this.latestDirectDenoiserGain;
         this.directDenoiserGainMax = Math.max(this.directDenoiserGainMax, this.latestDirectDenoiserGain);
         this.directDenoiserGainSamples++;
         this.specDenoiserGainSum += this.latestSpecDenoiserGain;
         this.specDenoiserGainMax = Math.max(this.specDenoiserGainMax, this.latestSpecDenoiserGain);
         this.specDenoiserGainSamples++;
         this.indirectResolveGainSum += this.latestIndirectResolveGain;
         this.indirectResolveGainMax = Math.max(this.indirectResolveGainMax, this.latestIndirectResolveGain);
         this.indirectResolveGainSamples++;
         this.recordMotionRepeatDelta(directTemporalAndRepeatImage, true, captureIndex);
         this.recordMotionRepeatDelta(indirectImage, false, captureIndex);
         this.updateWholeLightFlashDiagnostics(captureIndex, resolvedReservoirStats);
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
            String.format(Locale.ROOT, "%.5f", this.latestDirectRawLinearMeanLuma),
            String.format(Locale.ROOT, "%.5f", this.latestDirectRawLinearMaxLuma),
            String.format(Locale.ROOT, "%.5f", this.latestDirectRawLinearOverbrightFraction),
            String.format(Locale.ROOT, "%.5f", this.latestDirectRawLinearFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.latestDirectRawLinearSevereFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.latestDirectRawLinearFireflyLumaShare),
            String.format(Locale.ROOT, "%.5f", this.latestDirectRawLinearSaturatedPixelFraction),
            String.format(Locale.ROOT, "%.5f", this.latestDirectRawLinearNonFiniteFraction),
            String.format(Locale.ROOT, "%.5f", this.latestDirectDenoisedLinearMeanLuma),
            String.format(Locale.ROOT, "%.5f", this.latestDirectDenoisedLinearMaxLuma),
            String.format(Locale.ROOT, "%.5f", this.latestDirectDenoisedLinearOverbrightFraction),
            String.format(Locale.ROOT, "%.5f", this.latestDirectDenoisedLinearFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.latestDirectDenoisedLinearSevereFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.latestDirectDenoisedLinearFireflyLumaShare),
            String.format(Locale.ROOT, "%.5f", this.latestDirectDenoisedLinearSaturatedPixelFraction),
            String.format(Locale.ROOT, "%.5f", this.latestDirectDenoisedLinearNonFiniteFraction),
            String.format(Locale.ROOT, "%.5f", this.latestSpecRawLinearMeanLuma),
            String.format(Locale.ROOT, "%.5f", this.latestSpecRawLinearMaxLuma),
            String.format(Locale.ROOT, "%.5f", this.latestSpecRawLinearOverbrightFraction),
            String.format(Locale.ROOT, "%.5f", this.latestSpecRawLinearFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.latestSpecRawLinearSevereFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.latestSpecRawLinearFireflyLumaShare),
            String.format(Locale.ROOT, "%.5f", this.latestSpecRawLinearSaturatedPixelFraction),
            String.format(Locale.ROOT, "%.5f", this.latestSpecRawLinearNonFiniteFraction),
            String.format(Locale.ROOT, "%.5f", this.latestSpecDenoisedLinearMeanLuma),
            String.format(Locale.ROOT, "%.5f", this.latestSpecDenoisedLinearMaxLuma),
            String.format(Locale.ROOT, "%.5f", this.latestSpecDenoisedLinearOverbrightFraction),
            String.format(Locale.ROOT, "%.5f", this.latestSpecDenoisedLinearFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.latestSpecDenoisedLinearSevereFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.latestSpecDenoisedLinearFireflyLumaShare),
            String.format(Locale.ROOT, "%.5f", this.latestSpecDenoisedLinearSaturatedPixelFraction),
            String.format(Locale.ROOT, "%.5f", this.latestSpecDenoisedLinearNonFiniteFraction),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectRawLinearMeanLuma),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectRawLinearMaxLuma),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectRawLinearOverbrightFraction),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectRawLinearFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectRawLinearSevereFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectRawLinearFireflyLumaShare),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectRawLinearSaturatedPixelFraction),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectRawLinearNonFiniteFraction),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectLinearMeanLuma),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectLinearMaxLuma),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectLinearOverbrightFraction),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectLinearFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectLinearSevereFireflyFraction),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectLinearFireflyLumaShare),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectLinearSaturatedPixelFraction),
            String.format(Locale.ROOT, "%.5f", this.latestIndirectLinearNonFiniteFraction)
         );
         Photonic.info("[Automation] denoise gain capture={} direct(latest={}, avg={}, max={}) spec(latest={}, avg={}, max={}) indirect(latest={}, avg={}, max={})",
            this.capturesTaken,
            String.format(Locale.ROOT, "%.5f", this.latestDirectDenoiserGain),
            String.format(Locale.ROOT, "%.5f", this.directDenoiserGainSamples == 0 ? 0.0 : this.directDenoiserGainSum / this.directDenoiserGainSamples),
            String.format(Locale.ROOT, "%.5f", this.directDenoiserGainMax),
            String.format(Locale.ROOT, "%.5f", this.latestSpecDenoiserGain),
            String.format(Locale.ROOT, "%.5f", this.specDenoiserGainSamples == 0 ? 0.0 : this.specDenoiserGainSum / this.specDenoiserGainSamples),
            String.format(Locale.ROOT, "%.5f", this.specDenoiserGainMax),
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
      if (!this.isMotionRepeatHistorySettled()) {
         return;
      }

      MotionRepeatKey repeatKey = new MotionRepeatKey(phaseKey, this.timeOfDayCommandsIssued, this.blockToggleCommandsIssued, this.motionRepeatHistoryEpoch());
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
               this.blockToggleCommandsIssued,
               repeatKey.historyEpoch()
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
            this.blockToggleCommandsIssued,
            repeatKey.historyEpoch()
         )
      );
   }

   private void updateWholeLightFlashDiagnostics(int captureIndex, ReservoirDebugStats resolvedReservoirStats) {
      double directDrop = 0.0;
      if (Double.isFinite(this.previousCaptureDirectMeanLuma) && this.previousCaptureDirectMeanLuma > 1.0e-6) {
         directDrop = Math.max(0.0, (this.previousCaptureDirectMeanLuma - this.latestDirectMeanLuma) / this.previousCaptureDirectMeanLuma);
      }

      double resolvedValidDrop = 0.0;
      if (Double.isFinite(this.previousCaptureResolvedStrictValidFraction)) {
         resolvedValidDrop = Math.max(0.0, this.previousCaptureResolvedStrictValidFraction - resolvedReservoirStats.strictValidFraction());
      }

      double lightCountDrop = 0.0;
      if (this.previousCaptureTracedLightCount > 0) {
         lightCountDrop = Math.max(0.0, (this.previousCaptureTracedLightCount - this.latestTracedLightCount) / (double)this.previousCaptureTracedLightCount);
      }

      double resolvedMDrop = 0.0;
      if (Double.isFinite(this.previousCaptureResolvedMeanM) && this.previousCaptureResolvedMeanM > 1.0e-6) {
         resolvedMDrop = Math.max(0.0, (this.previousCaptureResolvedMeanM - resolvedReservoirStats.meanM()) / this.previousCaptureResolvedMeanM);
      }

      double blendFactorJump = 0.0;
      if (Double.isFinite(this.previousCaptureLightBlendFactor)) {
         blendFactorJump = Math.abs(this.latestLightBlendFactor - this.previousCaptureLightBlendFactor);
      }

      this.latestResolvedMeanM = resolvedReservoirStats.meanM();
      this.latestWholeLightFlashDirectDrop = directDrop;
      this.latestWholeLightFlashResolvedValidDrop = resolvedValidDrop;
      this.latestWholeLightFlashLightCountDrop = lightCountDrop;
      this.latestWholeLightFlashResolvedMDrop = resolvedMDrop;
      this.latestWholeLightFlashBlendFactorJump = blendFactorJump;
      this.maxWholeLightFlashDirectDrop = Math.max(this.maxWholeLightFlashDirectDrop, directDrop);
      this.maxWholeLightFlashResolvedValidDrop = Math.max(this.maxWholeLightFlashResolvedValidDrop, resolvedValidDrop);
      this.maxWholeLightFlashLightCountDrop = Math.max(this.maxWholeLightFlashLightCountDrop, lightCountDrop);
      this.maxWholeLightFlashResolvedMDrop = Math.max(this.maxWholeLightFlashResolvedMDrop, resolvedMDrop);
      this.maxWholeLightFlashBlendFactorJump = Math.max(this.maxWholeLightFlashBlendFactorJump, blendFactorJump);

      boolean directDropTriggered = directDrop >= WHOLE_LIGHT_FLASH_DIRECT_DROP_THRESHOLD;
      boolean resolvedValidDropTriggered = resolvedValidDrop >= WHOLE_LIGHT_FLASH_VALID_FRACTION_DROP_THRESHOLD;
      boolean lightCountDropTriggered = lightCountDrop >= WHOLE_LIGHT_FLASH_LIGHT_COUNT_DROP_THRESHOLD;
      boolean blendJumpTriggered = blendFactorJump >= WHOLE_LIGHT_FLASH_BLEND_FACTOR_JUMP_THRESHOLD;

      if (directDropTriggered) {
         this.wholeLightFlashDirectDropCaptures++;
      }
      if (resolvedValidDropTriggered) {
         this.wholeLightFlashResolvedValidDropCaptures++;
      }
      if (lightCountDropTriggered) {
         this.wholeLightFlashLightCountDropCaptures++;
      }
      if (blendJumpTriggered) {
         this.wholeLightFlashBlendJumpCaptures++;
      }

      if (directDropTriggered || resolvedValidDropTriggered || lightCountDropTriggered || blendJumpTriggered) {
         this.wholeLightFlashSuspectCaptures++;
         this.wholeLightFlashLastCapture = captureIndex;
         Photonic.warn(
            "[Automation] whole-light-flash capture={} directDrop={} resolvedValidDrop={} resolvedMDrop={} resolvedWeightDelta={} lightCountDrop={} blendFactorJump={} directMean={} prevDirectMean={} resolvedStrict={} prevResolvedStrict={} resolvedMeanWeight={} prevResolvedMeanWeight={} resolvedMeanM={} prevResolvedMeanM={} tracedLights={}/{} prevTracedLights={} blendFactor={} prevBlendFactor={} triggers(direct={}, resolved={}, lights={}, blend={})",
            captureIndex,
            String.format(Locale.ROOT, "%.5f", directDrop),
            String.format(Locale.ROOT, "%.5f", resolvedValidDrop),
            String.format(Locale.ROOT, "%.5f", resolvedMDrop),
            String.format(Locale.ROOT, "%.5f", Double.isFinite(this.previousCaptureResolvedMeanWeight) ? resolvedReservoirStats.meanWeight() - this.previousCaptureResolvedMeanWeight : 0.0),
            String.format(Locale.ROOT, "%.5f", lightCountDrop),
            String.format(Locale.ROOT, "%.5f", blendFactorJump),
            String.format(Locale.ROOT, "%.5f", this.latestDirectMeanLuma),
            String.format(Locale.ROOT, "%.5f", this.previousCaptureDirectMeanLuma),
            String.format(Locale.ROOT, "%.5f", resolvedReservoirStats.strictValidFraction()),
            String.format(Locale.ROOT, "%.5f", this.previousCaptureResolvedStrictValidFraction),
            String.format(Locale.ROOT, "%.5f", resolvedReservoirStats.meanWeight()),
            String.format(Locale.ROOT, "%.5f", this.previousCaptureResolvedMeanWeight),
            String.format(Locale.ROOT, "%.5f", resolvedReservoirStats.meanM()),
            String.format(Locale.ROOT, "%.5f", this.previousCaptureResolvedMeanM),
            this.latestTracedLightCount,
            this.latestTotalLightCount,
            this.previousCaptureTracedLightCount,
            String.format(Locale.ROOT, "%.5f", this.latestLightBlendFactor),
            String.format(Locale.ROOT, "%.5f", this.previousCaptureLightBlendFactor),
            directDropTriggered,
            resolvedValidDropTriggered,
            lightCountDropTriggered,
            blendJumpTriggered
         );
      }

      this.previousCaptureDirectMeanLuma = this.latestDirectMeanLuma;
      this.previousCaptureResolvedStrictValidFraction = resolvedReservoirStats.strictValidFraction();
      this.previousCaptureResolvedMeanWeight = resolvedReservoirStats.meanWeight();
      this.previousCaptureResolvedMeanM = resolvedReservoirStats.meanM();
      this.previousCaptureLightBlendFactor = this.latestLightBlendFactor;
      this.previousCaptureTracedLightCount = this.latestTracedLightCount;
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
            "delta=%.5f phase=%d epoch=%d captures=%d→%d activeTicks=%d→%d cmdTicks=%d→%d",
            record.delta(),
            record.phaseKey(),
            record.historyEpoch(),
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
      this.patchId = this.currentPatchId();
      this.expectedShaderPackMatched = matchesExpectedShaderPack(this.expectedShaderPack, Iris.getCurrentPackName());
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

   private void applyCameraMotion(MinecraftClient client) {
      if (!this.isCameraMotionEnabled() || client.player == null || !this.stableSceneSatisfied()) {
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
      prepared &= this.executeServerCommand(client, "gamerule randomTickSpeed 0");
      prepared &= this.executeServerCommand(client, "gamerule doMobSpawning false");
      prepared &= this.executeServerCommand(client, "gamerule doFireTick false");
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
         props.setProperty("stableSceneSettleTicks", Integer.toString(this.stableSceneSettleTicks));
         props.setProperty("stableSceneTicks", Integer.toString(this.stableSceneTicks));
         props.setProperty("stableSceneSatisfied", Boolean.toString(this.stableSceneSatisfied()));
         props.setProperty("stableSceneBlendRegionThreshold", Integer.toString(this.stableSceneBlendRegionThreshold));
         props.setProperty("stableSceneBlendFactorThreshold", Double.toString(this.stableSceneBlendFactorThreshold));
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
         props.setProperty("latestDirectRawLinearMeanLuma", Double.toString(this.latestDirectRawLinearMeanLuma));
         props.setProperty("latestDirectRawLinearMaxLuma", Double.toString(this.latestDirectRawLinearMaxLuma));
         props.setProperty("latestDirectRawLinearOverbrightFraction", Double.toString(this.latestDirectRawLinearOverbrightFraction));
         props.setProperty("latestDirectRawLinearFireflyFraction", Double.toString(this.latestDirectRawLinearFireflyFraction));
         props.setProperty("latestDirectRawLinearSevereFireflyFraction", Double.toString(this.latestDirectRawLinearSevereFireflyFraction));
         props.setProperty("latestDirectRawLinearFireflyLumaShare", Double.toString(this.latestDirectRawLinearFireflyLumaShare));
         props.setProperty("latestDirectRawLinearSaturatedPixelFraction", Double.toString(this.latestDirectRawLinearSaturatedPixelFraction));
         props.setProperty("latestDirectRawLinearNonFiniteFraction", Double.toString(this.latestDirectRawLinearNonFiniteFraction));
         props.setProperty("latestDirectDenoisedLinearMeanLuma", Double.toString(this.latestDirectDenoisedLinearMeanLuma));
         props.setProperty("latestDirectDenoisedLinearMaxLuma", Double.toString(this.latestDirectDenoisedLinearMaxLuma));
         props.setProperty("latestDirectDenoisedLinearOverbrightFraction", Double.toString(this.latestDirectDenoisedLinearOverbrightFraction));
         props.setProperty("latestDirectDenoisedLinearFireflyFraction", Double.toString(this.latestDirectDenoisedLinearFireflyFraction));
         props.setProperty("latestDirectDenoisedLinearSevereFireflyFraction", Double.toString(this.latestDirectDenoisedLinearSevereFireflyFraction));
         props.setProperty("latestDirectDenoisedLinearFireflyLumaShare", Double.toString(this.latestDirectDenoisedLinearFireflyLumaShare));
         props.setProperty("latestDirectDenoisedLinearSaturatedPixelFraction", Double.toString(this.latestDirectDenoisedLinearSaturatedPixelFraction));
         props.setProperty("latestDirectDenoisedLinearNonFiniteFraction", Double.toString(this.latestDirectDenoisedLinearNonFiniteFraction));
         props.setProperty("latestLightingMeanLuma", Double.toString(this.latestLightingMeanLuma));
         props.setProperty("latestStageLightingMeanLuma", Double.toString(this.latestStageLightingMeanLuma));
         props.setProperty("latestStageIndirectMeanLuma", Double.toString(this.latestStageIndirectMeanLuma));
         props.setProperty("latestIndirectRawMeanLuma", Double.toString(this.latestIndirectRawMeanLuma));
         props.setProperty("latestIndirectMeanLuma", Double.toString(this.latestIndirectMeanLuma));
         props.setProperty("latestSpecRawLinearMeanLuma", Double.toString(this.latestSpecRawLinearMeanLuma));
         props.setProperty("latestSpecRawLinearMaxLuma", Double.toString(this.latestSpecRawLinearMaxLuma));
         props.setProperty("latestSpecRawLinearOverbrightFraction", Double.toString(this.latestSpecRawLinearOverbrightFraction));
         props.setProperty("latestSpecRawLinearFireflyFraction", Double.toString(this.latestSpecRawLinearFireflyFraction));
         props.setProperty("latestSpecRawLinearSevereFireflyFraction", Double.toString(this.latestSpecRawLinearSevereFireflyFraction));
         props.setProperty("latestSpecRawLinearFireflyLumaShare", Double.toString(this.latestSpecRawLinearFireflyLumaShare));
         props.setProperty("latestSpecRawLinearSaturatedPixelFraction", Double.toString(this.latestSpecRawLinearSaturatedPixelFraction));
         props.setProperty("latestSpecRawLinearNonFiniteFraction", Double.toString(this.latestSpecRawLinearNonFiniteFraction));
         props.setProperty("latestSpecDenoisedLinearMeanLuma", Double.toString(this.latestSpecDenoisedLinearMeanLuma));
         props.setProperty("latestSpecDenoisedLinearMaxLuma", Double.toString(this.latestSpecDenoisedLinearMaxLuma));
         props.setProperty("latestSpecDenoisedLinearOverbrightFraction", Double.toString(this.latestSpecDenoisedLinearOverbrightFraction));
         props.setProperty("latestSpecDenoisedLinearFireflyFraction", Double.toString(this.latestSpecDenoisedLinearFireflyFraction));
         props.setProperty("latestSpecDenoisedLinearSevereFireflyFraction", Double.toString(this.latestSpecDenoisedLinearSevereFireflyFraction));
         props.setProperty("latestSpecDenoisedLinearFireflyLumaShare", Double.toString(this.latestSpecDenoisedLinearFireflyLumaShare));
         props.setProperty("latestSpecDenoisedLinearSaturatedPixelFraction", Double.toString(this.latestSpecDenoisedLinearSaturatedPixelFraction));
         props.setProperty("latestSpecDenoisedLinearNonFiniteFraction", Double.toString(this.latestSpecDenoisedLinearNonFiniteFraction));
         props.setProperty("latestIndirectRawLinearMeanLuma", Double.toString(this.latestIndirectRawLinearMeanLuma));
         props.setProperty("latestIndirectRawLinearMaxLuma", Double.toString(this.latestIndirectRawLinearMaxLuma));
         props.setProperty("latestIndirectRawLinearOverbrightFraction", Double.toString(this.latestIndirectRawLinearOverbrightFraction));
         props.setProperty("latestIndirectRawLinearFireflyFraction", Double.toString(this.latestIndirectRawLinearFireflyFraction));
         props.setProperty("latestIndirectRawLinearSevereFireflyFraction", Double.toString(this.latestIndirectRawLinearSevereFireflyFraction));
         props.setProperty("latestIndirectRawLinearFireflyLumaShare", Double.toString(this.latestIndirectRawLinearFireflyLumaShare));
         props.setProperty("latestIndirectRawLinearSaturatedPixelFraction", Double.toString(this.latestIndirectRawLinearSaturatedPixelFraction));
         props.setProperty("latestIndirectRawLinearNonFiniteFraction", Double.toString(this.latestIndirectRawLinearNonFiniteFraction));
         props.setProperty("latestIndirectLinearMeanLuma", Double.toString(this.latestIndirectLinearMeanLuma));
         props.setProperty("latestIndirectLinearMaxLuma", Double.toString(this.latestIndirectLinearMaxLuma));
         props.setProperty("latestIndirectLinearOverbrightFraction", Double.toString(this.latestIndirectLinearOverbrightFraction));
         props.setProperty("latestIndirectLinearFireflyFraction", Double.toString(this.latestIndirectLinearFireflyFraction));
         props.setProperty("latestIndirectLinearSevereFireflyFraction", Double.toString(this.latestIndirectLinearSevereFireflyFraction));
         props.setProperty("latestIndirectLinearFireflyLumaShare", Double.toString(this.latestIndirectLinearFireflyLumaShare));
         props.setProperty("latestIndirectLinearSaturatedPixelFraction", Double.toString(this.latestIndirectLinearSaturatedPixelFraction));
         props.setProperty("latestIndirectLinearNonFiniteFraction", Double.toString(this.latestIndirectLinearNonFiniteFraction));
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
         props.setProperty("latestWholeLightFlashDirectDrop", Double.toString(this.latestWholeLightFlashDirectDrop));
         props.setProperty("latestWholeLightFlashResolvedValidDrop", Double.toString(this.latestWholeLightFlashResolvedValidDrop));
         props.setProperty("latestWholeLightFlashLightCountDrop", Double.toString(this.latestWholeLightFlashLightCountDrop));
         props.setProperty("latestWholeLightFlashResolvedMDrop", Double.toString(this.latestWholeLightFlashResolvedMDrop));
         props.setProperty("latestWholeLightFlashBlendFactorJump", Double.toString(this.latestWholeLightFlashBlendFactorJump));
         props.setProperty("maxWholeLightFlashDirectDrop", Double.toString(this.maxWholeLightFlashDirectDrop));
         props.setProperty("maxWholeLightFlashResolvedValidDrop", Double.toString(this.maxWholeLightFlashResolvedValidDrop));
         props.setProperty("maxWholeLightFlashLightCountDrop", Double.toString(this.maxWholeLightFlashLightCountDrop));
         props.setProperty("maxWholeLightFlashResolvedMDrop", Double.toString(this.maxWholeLightFlashResolvedMDrop));
         props.setProperty("maxWholeLightFlashBlendFactorJump", Double.toString(this.maxWholeLightFlashBlendFactorJump));
         props.setProperty("wholeLightFlashSuspectCaptures", Integer.toString(this.wholeLightFlashSuspectCaptures));
         props.setProperty("wholeLightFlashLastCapture", Integer.toString(this.wholeLightFlashLastCapture));
         props.setProperty("wholeLightFlashDirectDropCaptures", Integer.toString(this.wholeLightFlashDirectDropCaptures));
         props.setProperty("wholeLightFlashResolvedValidDropCaptures", Integer.toString(this.wholeLightFlashResolvedValidDropCaptures));
         props.setProperty("wholeLightFlashLightCountDropCaptures", Integer.toString(this.wholeLightFlashLightCountDropCaptures));
         props.setProperty("wholeLightFlashBlendJumpCaptures", Integer.toString(this.wholeLightFlashBlendJumpCaptures));
         props.setProperty("previousCaptureResolvedMeanWeight", Double.toString(this.previousCaptureResolvedMeanWeight));
         props.setProperty("previousCaptureResolvedMeanM", Double.toString(this.previousCaptureResolvedMeanM));
         props.setProperty("previousCaptureResolvedStrictValidFraction", Double.toString(this.previousCaptureResolvedStrictValidFraction));
         props.setProperty("latestResolvedMeanM", Double.toString(this.latestResolvedMeanM));
         props.setProperty("previousCaptureDirectMeanLuma", Double.toString(this.previousCaptureDirectMeanLuma));
         props.setProperty("previousCaptureLightBlendFactor", Double.toString(this.previousCaptureLightBlendFactor));
         props.setProperty("previousCaptureTracedLightCount", Integer.toString(this.previousCaptureTracedLightCount));
         props.setProperty("latestDirectSoftTemporalDelta", Double.toString(this.latestDirectSoftTemporalDelta));
         props.setProperty("directSoftTemporalDeltaAvg", Double.toString(this.averageTemporalDelta(true, false)));
         props.setProperty("directSoftTemporalDeltaMax", Double.toString(this.directSoftTemporalDeltaMax));
         props.setProperty("indirectTemporalDeltaAvg", Double.toString(this.averageTemporalDelta(false, true)));
         props.setProperty("indirectTemporalDeltaMax", Double.toString(this.indirectTemporalDeltaMax));
         props.setProperty("latestDirectDenoiserGain", Double.toString(this.latestDirectDenoiserGain));
         props.setProperty("latestSpecDenoiserGain", Double.toString(this.latestSpecDenoiserGain));
         props.setProperty("latestIndirectResolveGain", Double.toString(this.latestIndirectResolveGain));
         props.setProperty("directDenoiserGainAvg", Double.toString(this.directDenoiserGainSamples == 0 ? 0.0 : this.directDenoiserGainSum / this.directDenoiserGainSamples));
         props.setProperty("directDenoiserGainMax", Double.toString(this.directDenoiserGainMax));
         props.setProperty("specDenoiserGainAvg", Double.toString(this.specDenoiserGainSamples == 0 ? 0.0 : this.specDenoiserGainSum / this.specDenoiserGainSamples));
         props.setProperty("specDenoiserGainMax", Double.toString(this.specDenoiserGainMax));
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
         && this.worldAutomationPrepared
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
      if (!this.stableSceneSatisfied()) {
         this.pendingBurstCaptures = 0;
         return false;
      }
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

   private boolean qualityThresholdsSatisfied() {
      return directTemporalValidationSatisfied()
         && thresholdSatisfied(this.averageTemporalDelta(false, true), this.maxIndirectTemporalDeltaAvg)
         && thresholdSatisfied(this.indirectTemporalDeltaMax, this.maxIndirectTemporalDeltaMax)
         && thresholdSatisfied(this.latestIndirectLinearOverbrightFraction, this.maxIndirectLinearOverbrightFraction)
         && thresholdSatisfied(this.latestIndirectLinearSevereFireflyFraction, this.maxIndirectLinearSevereFireflyFraction)
         && thresholdSatisfied(this.latestIndirectRawLinearOverbrightFraction, this.maxIndirectRawLinearOverbrightFraction);
   }

   private boolean directTemporalValidationSatisfied() {
      if (this.isMotionRepeatValidationEnabled()) {
         return true;
      }
      return thresholdSatisfied(this.averageTemporalDelta(false, false), this.maxDirectTemporalDeltaAvg)
         && thresholdSatisfied(this.directTemporalDeltaMax, this.maxDirectTemporalDeltaMax);
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
      if (!directTemporalValidationSatisfied()) {
         if (!thresholdSatisfied(this.averageTemporalDelta(false, false), this.maxDirectTemporalDeltaAvg)) {
            return "Direct temporal delta average exceeded threshold: "
               + this.averageTemporalDelta(false, false)
               + " > "
               + this.maxDirectTemporalDeltaAvg;
         }
         if (!thresholdSatisfied(this.directTemporalDeltaMax, this.maxDirectTemporalDeltaMax)) {
            return "Direct temporal delta max exceeded threshold: "
               + this.directTemporalDeltaMax
               + " > "
               + this.maxDirectTemporalDeltaMax;
         }
      }
      if (!thresholdSatisfied(this.averageTemporalDelta(false, true), this.maxIndirectTemporalDeltaAvg)) {
         return "Indirect temporal delta average exceeded threshold: "
            + this.averageTemporalDelta(false, true)
            + " > "
            + this.maxIndirectTemporalDeltaAvg;
      }
      if (!thresholdSatisfied(this.indirectTemporalDeltaMax, this.maxIndirectTemporalDeltaMax)) {
         return "Indirect temporal delta max exceeded threshold: "
            + this.indirectTemporalDeltaMax
            + " > "
            + this.maxIndirectTemporalDeltaMax;
      }
      if (!thresholdSatisfied(this.latestIndirectLinearOverbrightFraction, this.maxIndirectLinearOverbrightFraction)) {
         return "Indirect resolve overbright fraction exceeded threshold: "
            + this.latestIndirectLinearOverbrightFraction
            + " > "
            + this.maxIndirectLinearOverbrightFraction;
      }
      if (!thresholdSatisfied(this.latestIndirectLinearSevereFireflyFraction, this.maxIndirectLinearSevereFireflyFraction)) {
         return "Indirect resolve severe firefly fraction exceeded threshold: "
            + this.latestIndirectLinearSevereFireflyFraction
            + " > "
            + this.maxIndirectLinearSevereFireflyFraction;
      }
      if (!thresholdSatisfied(this.latestIndirectRawLinearOverbrightFraction, this.maxIndirectRawLinearOverbrightFraction)) {
         return "Indirect raw overbright fraction exceeded threshold: "
            + this.latestIndirectRawLinearOverbrightFraction
            + " > "
            + this.maxIndirectRawLinearOverbrightFraction;
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
      int blockToggleCommandCount,
      int historyEpoch
   ) {
   }

   private record MotionPhaseSample(
      BufferedImage image,
      int captureIndex,
      int activeTick,
      int ticksSinceAutomationCommand,
      int timeOfDayCommandCount,
      int blockToggleCommandCount,
      int historyEpoch
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
      int currentBlockToggleCommandCount,
      int historyEpoch
   ) {
   }

   private record RowJumpStats(
      int rowFromBottom,
      int rowFromTop,
      double delta,
      double previousMean,
      double nextMean
   ) {
      private static final RowJumpStats EMPTY = new RowJumpStats(0, 0, 0.0, 0.0, 0.0);
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

   private record ReGIRCellBufferStats(
      int[] validSlotCounts,
      double[] meanWeights,
      int[] checksums,
      int[] keyX,
      int[] keyY,
      int[] keyZ,
      int[] keyBucket
   ) {
      private static final ReGIRCellBufferStats EMPTY = new ReGIRCellBufferStats(
         new int[0],
         new double[0],
         new int[0],
         new int[0],
         new int[0],
         new int[0],
         new int[0]
      );
   }

   private record ReGIRHashCellCoord(int x, int y, int z) {
   }

   private record ReGIRCellSampleStats(int representativeSlot, int validSlots, double meanWeight) {
      boolean found() {
         return this.representativeSlot >= 0;
      }
   }

   private record ReGIRPixelCorrelationStats(
      double visiblePixelFraction,
      double strictValidVisibleFraction,
      double exactOutsideGridFraction,
      double strictInvalidOutsideGridFraction,
      double strictValidOutsideGridFraction,
      double strictInvalidZeroSlotFraction,
      double strictValidZeroSlotFraction,
      double strictInvalidMeanCellValidSlots,
      double strictValidMeanCellValidSlots,
      double strictInvalidMeanCellWeight,
      double strictValidMeanCellWeight,
      double jitteredCellChangedFraction,
      double jitteredMeanCellWeightDelta,
      double jitteredOutsideGridDeltaFraction,
      RowJumpStats cellValidSlotsJump,
      RowJumpStats cellMeanWeightJump,
      RowJumpStats outsideGridJump,
      RowJumpStats jitteredCellChangedJump,
      RowJumpStats jitteredCellMeanWeightDeltaJump,
      RowJumpStats jitteredOutsideGridDeltaJump
   ) {
      private static final ReGIRPixelCorrelationStats EMPTY = new ReGIRPixelCorrelationStats(
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         RowJumpStats.EMPTY,
         RowJumpStats.EMPTY,
         RowJumpStats.EMPTY,
         RowJumpStats.EMPTY,
         RowJumpStats.EMPTY,
         RowJumpStats.EMPTY
      );
   }

   private record ReservoirDebugStats(
      double lightValidFraction,
      double strictValidFraction,
      double meanWeight,
      double meanM
   ) {
      private static final ReservoirDebugStats EMPTY = new ReservoirDebugStats(0.0, 0.0, 0.0, 0.0);
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

   private record InitialSamplingDebugStats(
      double invalidSurfaceFraction,
      double noLightsFraction,
      double noLocalSamplesFraction,
      double invalidLightSelectionFraction,
      double invalidLightSampleFraction,
      double zeroRadianceFraction,
      double zeroSourcePdfFraction,
      double zeroTargetPdfFraction,
      double nonFiniteSourcePdfFraction,
      double nonFiniteTargetPdfFraction,
      double successFraction,
      double meanPositiveCandidateFraction,
      double proposalValidFraction,
      double meanProposalWeight,
      RowJumpStats successRowJump,
      RowJumpStats zeroTargetRowJump,
      RowJumpStats proposalValidRowJump,
      RowJumpStats proposalWeightRowJump
   ) {
      private static final InitialSamplingDebugStats EMPTY = new InitialSamplingDebugStats(
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         0.0,
         RowJumpStats.EMPTY,
         RowJumpStats.EMPTY,
         RowJumpStats.EMPTY,
         RowJumpStats.EMPTY
      );
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

   private static final class RandomSamplerState {
      private final int seed;
      private int index;

      private RandomSamplerState(int seed, int index) {
         this.seed = seed;
         this.index = index;
      }
   }
}








