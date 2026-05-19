package at.redi2go.photonic.client;

import java.awt.image.BufferedImage;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Holds all per-frame image-measurement state and temporal/motion-delta tracking
 * that was previously scattered across {@link ShaderAutomation}.
 *
 * <p>All fields and methods are package-private so {@link ShaderAutomation} can
 * access them directly without getter boilerplate.
 */
final class ShaderAutomationFrameMetrics {

   private static final int MAX_REPEAT_DIAGNOSTICS = 5;

   // -------------------------------------------------------------------------
   // Max-luma trackers (running peak across all captures)
   // -------------------------------------------------------------------------
   double directMaxLuma = 0.0;
   double directSoftMaxLuma = 0.0;
   double directDenoisedMaxLuma = 0.0;
   double directRawMaxLuma = 0.0;
   double lightingBufferMaxLuma = 0.0;
   double stageLightingMaxLuma = 0.0;
   double stageIndirectMaxLuma = 0.0;
   double handheldMaxLuma = 0.0;
   double indirectMaxLuma = 0.0;
   double indirectRawMaxLuma = 0.0;

   // -------------------------------------------------------------------------
   // Latest per-capture image statistics
   // -------------------------------------------------------------------------
   double latestDirectMeanLuma = 0.0;
   double latestDirectDenoisedMeanLuma = 0.0;
   double latestDirectRawMeanLuma = 0.0;
   double latestDirectRawLinearMeanLuma = 0.0;
   double latestDirectRawLinearMaxLuma = 0.0;
   double latestDirectRawLinearOverbrightFraction = 0.0;
   double latestDirectRawLinearFireflyFraction = 0.0;
   double latestDirectRawLinearSevereFireflyFraction = 0.0;
   double latestDirectRawLinearFireflyLumaShare = 0.0;
   double latestDirectRawLinearSaturatedPixelFraction = 0.0;
   double latestDirectRawLinearNonFiniteFraction = 0.0;
   double latestDirectDenoisedLinearMeanLuma = 0.0;
   double latestDirectDenoisedLinearMaxLuma = 0.0;
   double latestDirectDenoisedLinearOverbrightFraction = 0.0;
   double latestDirectDenoisedLinearFireflyFraction = 0.0;
   double latestDirectDenoisedLinearSevereFireflyFraction = 0.0;
   double latestDirectDenoisedLinearFireflyLumaShare = 0.0;
   double latestDirectDenoisedLinearSaturatedPixelFraction = 0.0;
   double latestDirectDenoisedLinearNonFiniteFraction = 0.0;
   double latestLightingMeanLuma = 0.0;
   double latestStageLightingMeanLuma = 0.0;
   double latestStageIndirectMeanLuma = 0.0;
   double latestIndirectMeanLuma = 0.0;
   double latestIndirectRawMeanLuma = 0.0;
   double latestIndirectRawLinearMeanLuma = 0.0;
   double latestIndirectRawLinearMaxLuma = 0.0;
   double latestIndirectRawLinearOverbrightFraction = 0.0;
   double latestIndirectRawLinearFireflyFraction = 0.0;
   double latestIndirectRawLinearSevereFireflyFraction = 0.0;
   double latestIndirectRawLinearFireflyLumaShare = 0.0;
   double latestIndirectRawLinearSaturatedPixelFraction = 0.0;
   double latestIndirectRawLinearNonFiniteFraction = 0.0;
   double latestStageIndirectLinearMeanLuma = 0.0;
   double latestStageIndirectLinearMaxLuma = 0.0;
   double latestStageIndirectLinearOverbrightFraction = 0.0;
   double latestIndirectLinearMeanLuma = 0.0;
   double latestIndirectLinearMaxLuma = 0.0;
   double latestIndirectLinearOverbrightFraction = 0.0;
   double latestIndirectLinearFireflyFraction = 0.0;
   double latestIndirectLinearSevereFireflyFraction = 0.0;
   double latestIndirectLinearFireflyLumaShare = 0.0;
   double latestIndirectLinearSaturatedPixelFraction = 0.0;
   double latestIndirectLinearNonFiniteFraction = 0.0;
   double latestSpecRawLinearMeanLuma = 0.0;
   double latestSpecRawLinearMaxLuma = 0.0;
   double latestSpecRawLinearOverbrightFraction = 0.0;
   double latestSpecRawLinearFireflyFraction = 0.0;
   double latestSpecRawLinearSevereFireflyFraction = 0.0;
   double latestSpecRawLinearFireflyLumaShare = 0.0;
   double latestSpecRawLinearSaturatedPixelFraction = 0.0;
   double latestSpecRawLinearNonFiniteFraction = 0.0;
   double latestSpecDenoisedLinearMeanLuma = 0.0;
   double latestSpecDenoisedLinearMaxLuma = 0.0;
   double latestSpecDenoisedLinearOverbrightFraction = 0.0;
   double latestSpecDenoisedLinearFireflyFraction = 0.0;
   double latestSpecDenoisedLinearSevereFireflyFraction = 0.0;
   double latestSpecDenoisedLinearFireflyLumaShare = 0.0;
   double latestSpecDenoisedLinearSaturatedPixelFraction = 0.0;
   double latestSpecDenoisedLinearNonFiniteFraction = 0.0;

   // Mean RGB / alpha channels
   double latestDirectMeanRed = 0.0;
   double latestDirectMeanGreen = 0.0;
   double latestDirectMeanBlue = 0.0;
   double latestDirectMeanAlpha = 0.0;
   double latestDirectZeroAlphaFraction = 0.0;
   double latestLightingMeanRed = 0.0;
   double latestLightingMeanGreen = 0.0;
   double latestLightingMeanBlue = 0.0;
   double latestStageLightingMeanRed = 0.0;
   double latestStageLightingMeanGreen = 0.0;
   double latestStageLightingMeanBlue = 0.0;
   double latestStageIndirectMeanRed = 0.0;
   double latestStageIndirectMeanGreen = 0.0;
   double latestStageIndirectMeanBlue = 0.0;
   double latestIndirectMeanRed = 0.0;
   double latestIndirectMeanGreen = 0.0;
   double latestIndirectMeanBlue = 0.0;
   double latestIndirectMeanAlpha = 0.0;
   double latestIndirectZeroAlphaFraction = 0.0;
   double latestStageIndirectMeanAlpha = 0.0;
   double latestStageIndirectZeroAlphaFraction = 0.0;

   // -------------------------------------------------------------------------
   // Alpha delta accumulator
   // -------------------------------------------------------------------------
   double latestDirectAlphaDelta = 0.0;
   double directAlphaDeltaSum = 0.0;
   double directAlphaDeltaMax = 0.0;
   int directAlphaDeltaSamples = 0;

   // -------------------------------------------------------------------------
   // Brightness variance accumulators
   // -------------------------------------------------------------------------
   double latestDirectBrightnessVariance = 0.0;
   double latestDirectBrightnessStdDev = 0.0;
   double directBrightnessVarianceSum = 0.0;
   double directBrightnessVarianceMax = 0.0;
   int directBrightnessVarianceSamples = 0;
   double latestHandheldBrightnessVariance = 0.0;
   double latestHandheldBrightnessStdDev = 0.0;
   double handheldBrightnessVarianceSum = 0.0;
   double handheldBrightnessVarianceMax = 0.0;
   int handheldBrightnessVarianceSamples = 0;

   // -------------------------------------------------------------------------
   // Direct soft signal state
   // -------------------------------------------------------------------------
   boolean directSoftSignalDetected = false;
   int directSoftSignalCaptureCount = 0;
   int directSoftZeroCaptureCount = 0;
   boolean directSoftMissingSignalWarningIssued = false;

   // -------------------------------------------------------------------------
   // Temporal delta accumulators
   // -------------------------------------------------------------------------
   double latestDirectTemporalDelta = 0.0;
   double latestDirectTemporalMaxPixelDelta = 0.0;
   double directTemporalDeltaSum = 0.0;
   double directTemporalDeltaMax = 0.0;
   int directTemporalDeltaSamples = 0;
   double directTemporalMaxPixelDeltaSum = 0.0;
   double directTemporalMaxPixelDeltaMax = 0.0;
   int directTemporalMaxPixelDeltaSamples = 0;
   double latestDirectSoftTemporalDelta = 0.0;
   double directSoftTemporalDeltaSum = 0.0;
   double directSoftTemporalDeltaMax = 0.0;
   int directSoftTemporalDeltaSamples = 0;
   double indirectTemporalDeltaSum = 0.0;
   double indirectTemporalDeltaMax = 0.0;
   int indirectTemporalDeltaSamples = 0;

   // Previous-frame buffers for temporal delta
   BufferedImage previousDirectImage = null;
   BufferedImage previousDirectSoftImage = null;
   BufferedImage previousIndirectImage = null;

   // -------------------------------------------------------------------------
   // Motion-repeat delta accumulators
   // -------------------------------------------------------------------------
   double motionRepeatDirectDeltaSum = 0.0;
   double motionRepeatDirectDeltaMax = 0.0;
   int motionRepeatDirectDeltaSamples = 0;
   double motionRepeatIndirectDeltaSum = 0.0;
   double motionRepeatIndirectDeltaMax = 0.0;
   int motionRepeatIndirectDeltaSamples = 0;
   final Map<ShaderAutomation.MotionRepeatKey, ShaderAutomation.MotionPhaseSample> previousDirectImagesByPhase = new HashMap<>();
   final Map<ShaderAutomation.MotionRepeatKey, ShaderAutomation.MotionPhaseSample> previousIndirectImagesByPhase = new HashMap<>();
   final List<ShaderAutomation.MotionRepeatDeltaRecord> topDirectRepeatDeltas = new ArrayList<>();
   final List<ShaderAutomation.MotionRepeatDeltaRecord> topIndirectRepeatDeltas = new ArrayList<>();

   // -------------------------------------------------------------------------
   // Denoiser / resolve gain accumulators
   // -------------------------------------------------------------------------
   double latestDirectDenoiserGain = 0.0;
   double directDenoiserGainSum = 0.0;
   double directDenoiserGainMax = 0.0;
   int directDenoiserGainSamples = 0;
   double latestSpecDenoiserGain = 0.0;
   double specDenoiserGainSum = 0.0;
   double specDenoiserGainMax = 0.0;
   int specDenoiserGainSamples = 0;
   double latestIndirectResolveGain = 0.0;
   double indirectResolveGainSum = 0.0;
   double indirectResolveGainMax = 0.0;
   int indirectResolveGainSamples = 0;

   // -------------------------------------------------------------------------
   // Post-motion drop metrics
   // -------------------------------------------------------------------------
   int postMotionDropSamples = 0;
   double postMotionDirectMeanAtStop = 0.0;
   double postMotionIndirectMeanAtStop = 0.0;
   double postMotionRawDirectMeanAtStop = 0.0;
   double postMotionStageIndirectMeanAtStop = 0.0;
   double latestPostMotionDirectDrop = 0.0;
   double latestPostMotionIndirectDrop = 0.0;
   double latestPostMotionRawDirectDrop = 0.0;
   double latestPostMotionStageIndirectDrop = 0.0;
   double postMotionDirectDropMax = 0.0;
   double postMotionIndirectDropMax = 0.0;
   double postMotionRawDirectDropMax = 0.0;
   double postMotionStageIndirectDropMax = 0.0;
   double postMotionDirectDropSum = 0.0;
   double postMotionIndirectDropSum = 0.0;
   double postMotionRawDirectDropSum = 0.0;
   double postMotionStageIndirectDropSum = 0.0;

   // -------------------------------------------------------------------------
   // Whole-light-flash diagnostics
   // -------------------------------------------------------------------------
   double latestWholeLightFlashDirectDrop = 0.0;
   double latestWholeLightFlashResolvedValidDrop = 0.0;
   double latestWholeLightFlashLightCountDrop = 0.0;
   double latestWholeLightFlashBlendFactorJump = 0.0;
   double maxWholeLightFlashDirectDrop = 0.0;
   double maxWholeLightFlashResolvedValidDrop = 0.0;
   double maxWholeLightFlashLightCountDrop = 0.0;
   double maxWholeLightFlashBlendFactorJump = 0.0;
   int wholeLightFlashSuspectCaptures = 0;
   int wholeLightFlashLastCapture = -1;
   int wholeLightFlashDirectDropCaptures = 0;
   int wholeLightFlashResolvedValidDropCaptures = 0;
   int wholeLightFlashLightCountDropCaptures = 0;
   int wholeLightFlashBlendJumpCaptures = 0;
   double previousCaptureDirectMeanLuma = Double.NaN;
   double previousCaptureResolvedStrictValidFraction = Double.NaN;
   double previousCaptureResolvedMeanWeight = Double.NaN;
   double previousCaptureResolvedMeanM = Double.NaN;
   double previousCaptureLightBlendFactor = Double.NaN;
   int previousCaptureTracedLightCount = -1;
   double latestResolvedMeanM = 0.0;
   double latestWholeLightFlashResolvedMDrop = 0.0;
   double maxWholeLightFlashResolvedMDrop = 0.0;

   // =========================================================================
   // Methods
   // =========================================================================

   /**
    * Updates the direct_soft signal detection state.
    */
   void updateDirectSoftSignalState(
      double directSoftLuma,
      int captureIndex,
      int activeTicks,
      double directMaxLumaForLog,
      double directRawMaxLumaForLog,
      double handheldMaxLumaForLog
   ) {
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
         activeTicks,
         String.format(Locale.ROOT, "%.4f", directMaxLumaForLog),
         String.format(Locale.ROOT, "%.4f", directRawMaxLumaForLog),
         String.format(Locale.ROOT, "%.4f", handheldMaxLumaForLog));
   }

   /**
    * Records temporal delta between the previous and current image for the given channel.
    */
   void recordTemporalDelta(BufferedImage currentImage, boolean directSoft, boolean indirect) {
      if (currentImage == null) {
         return;
      }

      if (indirect) {
         double delta = ShaderAutomationImageUtils.computeMeanLumaDelta(this.previousIndirectImage, currentImage);
         if (this.previousIndirectImage != null) {
            this.indirectTemporalDeltaSum += delta;
            this.indirectTemporalDeltaMax = Math.max(this.indirectTemporalDeltaMax, delta);
            this.indirectTemporalDeltaSamples++;
         }
         this.previousIndirectImage = currentImage;
         return;
      }

      if (directSoft) {
         double delta = ShaderAutomationImageUtils.computeMeanLumaDelta(this.previousDirectSoftImage, currentImage);
         if (this.previousDirectSoftImage != null) {
            this.latestDirectSoftTemporalDelta = delta;
            this.directSoftTemporalDeltaSum += delta;
            this.directSoftTemporalDeltaMax = Math.max(this.directSoftTemporalDeltaMax, delta);
            this.directSoftTemporalDeltaSamples++;
         }
         this.previousDirectSoftImage = currentImage;
         return;
      }

      double delta = ShaderAutomationImageUtils.computeMeanLumaDelta(this.previousDirectImage, currentImage);
      double maxPixelDelta = ShaderAutomationImageUtils.computeMaxLumaPixelDelta(this.previousDirectImage, currentImage);
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

   /**
    * Records motion-repeat delta for the given image and channel (direct or indirect).
    */
   void recordMotionRepeatDelta(
      BufferedImage currentImage,
      boolean direct,
      int captureIndex,
      int activeTicks,
      int motionRepeatSettleTicks,
      int ticksSinceLastCommand,
      boolean isMotionRepeatHistorySettled,
      int cameraMotionStartActiveTick,
      int cameraMotionPeriodTicks,
      int timeOfDayCommandsIssued,
      int blockToggleCommandsIssued,
      int motionRepeatHistoryEpoch
   ) {
      if (currentImage == null) {
         return;
      }

      int phaseKey = ShaderAutomationValidators.motionPhaseKey(activeTicks, cameraMotionStartActiveTick, cameraMotionPeriodTicks);
      if (phaseKey < 0) {
         return;
      }

      if (ticksSinceLastCommand < motionRepeatSettleTicks) {
         return;
      }
      if (!isMotionRepeatHistorySettled) {
         return;
      }

      ShaderAutomation.MotionRepeatKey repeatKey = new ShaderAutomation.MotionRepeatKey(phaseKey, timeOfDayCommandsIssued, blockToggleCommandsIssued, motionRepeatHistoryEpoch);
      Map<ShaderAutomation.MotionRepeatKey, ShaderAutomation.MotionPhaseSample> historyByPhase = direct ? this.previousDirectImagesByPhase : this.previousIndirectImagesByPhase;
      ShaderAutomation.MotionPhaseSample previousSample = historyByPhase.get(repeatKey);
      if (previousSample != null) {
         double delta = ShaderAutomationImageUtils.computeMeanLumaDelta(previousSample.image(), currentImage);
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
            new ShaderAutomation.MotionRepeatDeltaRecord(
               delta,
               phaseKey,
               previousSample.captureIndex(),
               captureIndex,
               previousSample.activeTick(),
               activeTicks,
               previousSample.ticksSinceAutomationCommand(),
               ticksSinceLastCommand,
               previousSample.timeOfDayCommandCount(),
               previousSample.blockToggleCommandCount(),
               timeOfDayCommandsIssued,
               blockToggleCommandsIssued,
               repeatKey.historyEpoch()
            )
         );
      }
      historyByPhase.put(
         repeatKey,
         new ShaderAutomation.MotionPhaseSample(
            currentImage,
            captureIndex,
            activeTicks,
            ticksSinceLastCommand,
            timeOfDayCommandsIssued,
            blockToggleCommandsIssued,
            repeatKey.historyEpoch()
         )
      );
   }

   /**
    * Updates post-motion drop metrics.
    *
    * @param cameraMotionStopActiveTick SA's cameraMotionStopActiveTick field (SA owns it)
    * @param activeTicks               current active-tick count from SA
    */
   void updatePostMotionDropMetrics(int cameraMotionStopActiveTick, int activeTicks) {
      if (cameraMotionStopActiveTick < 0 || activeTicks < cameraMotionStopActiveTick) {
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

   /**
    * Updates whole-light-flash diagnostics for the current capture.
    *
    * @param captureIndex           current capture index
    * @param resolvedReservoirStats resolved reservoir debug stats
    * @param latestTracedLightCount current traced light count (from SA)
    * @param latestTotalLightCount  current total light count (from SA)
    * @param latestLightBlendFactor current blend factor (from SA)
    * @param wholeLightFlashDirectDropThreshold threshold constant from SA
    * @param wholeLightFlashValidFractionDropThreshold threshold constant from SA
    * @param wholeLightFlashLightCountDropThreshold threshold constant from SA
    * @param wholeLightFlashBlendFactorJumpThreshold threshold constant from SA
    */
   void updateWholeLightFlashDiagnostics(
      int captureIndex,
      ShaderAutomationGpuDebugExtractor.ReservoirDebugStats resolvedReservoirStats,
      int latestTracedLightCount,
      int latestTotalLightCount,
      double latestLightBlendFactor,
      double wholeLightFlashDirectDropThreshold,
      double wholeLightFlashValidFractionDropThreshold,
      double wholeLightFlashLightCountDropThreshold,
      double wholeLightFlashBlendFactorJumpThreshold
   ) {
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
         lightCountDrop = Math.max(0.0, (this.previousCaptureTracedLightCount - latestTracedLightCount) / (double)this.previousCaptureTracedLightCount);
      }

      double resolvedMDrop = 0.0;
      if (Double.isFinite(this.previousCaptureResolvedMeanM) && this.previousCaptureResolvedMeanM > 1.0e-6) {
         resolvedMDrop = Math.max(0.0, (this.previousCaptureResolvedMeanM - resolvedReservoirStats.meanM()) / this.previousCaptureResolvedMeanM);
      }

      double blendFactorJump = 0.0;
      if (Double.isFinite(this.previousCaptureLightBlendFactor)) {
         blendFactorJump = Math.abs(latestLightBlendFactor - this.previousCaptureLightBlendFactor);
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

      boolean directDropTriggered = directDrop >= wholeLightFlashDirectDropThreshold;
      boolean resolvedValidDropTriggered = resolvedValidDrop >= wholeLightFlashValidFractionDropThreshold;
      boolean lightCountDropTriggered = lightCountDrop >= wholeLightFlashLightCountDropThreshold;
      boolean blendJumpTriggered = blendFactorJump >= wholeLightFlashBlendFactorJumpThreshold;

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
            latestTracedLightCount,
            latestTotalLightCount,
            this.previousCaptureTracedLightCount,
            String.format(Locale.ROOT, "%.5f", latestLightBlendFactor),
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
      this.previousCaptureLightBlendFactor = latestLightBlendFactor;
      this.previousCaptureTracedLightCount = latestTracedLightCount;
   }

   // -------------------------------------------------------------------------
   // Averaging helpers (called from SA for buildSuccess / writeReport)
   // -------------------------------------------------------------------------

   double averageTemporalDelta(boolean directSoft, boolean indirect) {
      if (indirect) {
         return this.indirectTemporalDeltaSamples == 0 ? 0.0 : this.indirectTemporalDeltaSum / this.indirectTemporalDeltaSamples;
      }
      if (directSoft) {
         return this.directSoftTemporalDeltaSamples == 0 ? 0.0 : this.directSoftTemporalDeltaSum / this.directSoftTemporalDeltaSamples;
      }
      return this.directTemporalDeltaSamples == 0 ? 0.0 : this.directTemporalDeltaSum / this.directTemporalDeltaSamples;
   }

   double averageDirectTemporalMaxPixelDelta() {
      return this.directTemporalMaxPixelDeltaSamples == 0
         ? 0.0
         : this.directTemporalMaxPixelDeltaSum / this.directTemporalMaxPixelDeltaSamples;
   }

   double averageDirectAlphaDelta() {
      return this.directAlphaDeltaSamples == 0 ? 0.0 : this.directAlphaDeltaSum / this.directAlphaDeltaSamples;
   }

   double averageDirectBrightnessVariance() {
      return this.directBrightnessVarianceSamples == 0 ? 0.0 : this.directBrightnessVarianceSum / this.directBrightnessVarianceSamples;
   }

   double averageHandheldBrightnessVariance() {
      return this.handheldBrightnessVarianceSamples == 0 ? 0.0 : this.handheldBrightnessVarianceSum / this.handheldBrightnessVarianceSamples;
   }

   double averageMotionRepeatDelta(boolean direct) {
      if (direct) {
         return this.motionRepeatDirectDeltaSamples == 0 ? 0.0 : this.motionRepeatDirectDeltaSum / this.motionRepeatDirectDeltaSamples;
      }
      return this.motionRepeatIndirectDeltaSamples == 0 ? 0.0 : this.motionRepeatIndirectDeltaSum / this.motionRepeatIndirectDeltaSamples;
   }

   // -------------------------------------------------------------------------
   // Diagnostics formatting helper (used by SA.writeReport and defaultFailureReason)
   // -------------------------------------------------------------------------

   static String formatRepeatDeltaDiagnostics(List<ShaderAutomation.MotionRepeatDeltaRecord> records) {
      if (records.isEmpty()) {
         return "";
      }

      List<String> parts = new ArrayList<>(records.size());
      for (ShaderAutomation.MotionRepeatDeltaRecord record : records) {
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

   // -------------------------------------------------------------------------
   // Internal helpers
   // -------------------------------------------------------------------------

   private void recordTopRepeatDelta(boolean direct, ShaderAutomation.MotionRepeatDeltaRecord record) {
      List<ShaderAutomation.MotionRepeatDeltaRecord> topDeltas = direct ? this.topDirectRepeatDeltas : this.topIndirectRepeatDeltas;
      topDeltas.add(record);
      topDeltas.sort((left, right) -> Double.compare(right.delta(), left.delta()));
      if (topDeltas.size() > MAX_REPEAT_DIAGNOSTICS) {
         topDeltas.remove(topDeltas.size() - 1);
      }
   }
}
