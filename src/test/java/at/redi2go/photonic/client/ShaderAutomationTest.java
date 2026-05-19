package at.redi2go.photonic.client;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.awt.Color;
import java.awt.image.BufferedImage;
import java.util.Arrays;
import org.junit.jupiter.api.Test;

class ShaderAutomationTest {
   private static final double EPSILON = 1.0e-9;

   @Test
   void blankExpectedShaderPackMatchesAnything() {
      assertTrue(ShaderAutomationValidators.matchesExpectedShaderPack("", "ComplementaryReimagined_r2.0.3"));
      assertTrue(ShaderAutomationValidators.matchesExpectedShaderPack(null, "ComplementaryReimagined_r2.0.3"));
   }

   @Test
   void expectedShaderPackNormalizesVersionSuffixesPunctuationAndEuphoriaAliases() {
      assertTrue(ShaderAutomationValidators.matchesExpectedShaderPack("ComplementaryReimagined", "ComplementaryReimagined_r2.0.3"));
      assertTrue(ShaderAutomationValidators.matchesExpectedShaderPack("ComplementaryReimagined_r2.0.3", "Complementary Reimagined"));
      assertTrue(ShaderAutomationValidators.matchesExpectedShaderPack("ComplementaryReimagined", "Euphoria-patches.zip"));
      assertTrue(ShaderAutomationValidators.matchesExpectedShaderPack("EuphoriaPatches", "ComplementaryReimagined_r5.7.1"));
      assertFalse(ShaderAutomationValidators.matchesExpectedShaderPack("ComplementaryUnbound", "ComplementaryReimagined_r2.0.3"));
   }

   @Test
   void nonBlankExpectedShaderPackRequiresNonBlankActualName() {
      assertFalse(ShaderAutomationValidators.matchesExpectedShaderPack("ComplementaryReimagined", ""));
      assertFalse(ShaderAutomationValidators.matchesExpectedShaderPack("ComplementaryReimagined", null));
   }

   @Test
   void blankExpectedPatchIdPrefixMatchesAnything() {
      assertTrue(ShaderAutomationValidators.matchesExpectedPatchIdPrefix("", "REGIR_RESTIR:stable"));
      assertTrue(ShaderAutomationValidators.matchesExpectedPatchIdPrefix(null, "REGIR_RESTIR:patched"));
   }

   @Test
   void expectedPatchIdPrefixRequiresMatchingPatchIdPrefix() {
      assertTrue(ShaderAutomationValidators.matchesExpectedPatchIdPrefix("REGIR_RESTIR:", "REGIR_RESTIR:native"));
      assertFalse(ShaderAutomationValidators.matchesExpectedPatchIdPrefix("REGIR_RESTIR:", "BASIC:native"));
   }

   @Test
   void maxLumaTracksBrightestPixelInImage() {
      BufferedImage image = new BufferedImage(2, 2, BufferedImage.TYPE_INT_ARGB);
      image.setRGB(0, 0, new Color(0, 0, 0, 255).getRGB());
      image.setRGB(1, 0, new Color(255, 0, 0, 255).getRGB());
      image.setRGB(0, 1, new Color(0, 255, 0, 255).getRGB());
      image.setRGB(1, 1, new Color(255, 255, 255, 255).getRGB());

      assertEquals(1.0, ShaderAutomationImageUtils.computeMaxLuma(image), EPSILON);
   }

   @Test
   void maxLumaUsesStandardRec709Weights() {
      BufferedImage image = new BufferedImage(1, 1, BufferedImage.TYPE_INT_ARGB);
      image.setRGB(0, 0, new Color(255, 0, 0, 255).getRGB());

      assertEquals(0.2126, ShaderAutomationImageUtils.computeMaxLuma(image), EPSILON);
   }

   @Test
   void activeTicksSinceFirstSignalUsesSentinelBeforeSignalAndDeltaAfterward() {
      assertEquals(-1, ShaderAutomationValidators.activeTicksSinceFirstSignal(120, -1));
      assertEquals(0, ShaderAutomationValidators.activeTicksSinceFirstSignal(120, 120));
      assertEquals(45, ShaderAutomationValidators.activeTicksSinceFirstSignal(120, 75));
   }

   @Test
   void completionSatisfiedRequiresMoreThanAnySingleLightingSignal() {
      assertFalse(ShaderAutomationValidators.isCompletionSatisfied(5, 3, 1, 3, true, 320, 300, 200, 120));
      assertFalse(ShaderAutomationValidators.isCompletionSatisfied(5, 3, 3, 3, true, 250, 300, 200, 120));
      assertFalse(ShaderAutomationValidators.isCompletionSatisfied(5, 3, 3, 3, true, 320, 300, 60, 120));
      assertFalse(ShaderAutomationValidators.isCompletionSatisfied(2, 3, 2, 3, true, 320, 300, 200, 120));
      assertFalse(ShaderAutomationValidators.isCompletionSatisfied(5, 3, 3, 3, false, 320, 300, 200, 120));
   }

   @Test
   void completionSatisfiedAcceptsSustainedLitCapturesAfterSettleWindow() {
      assertTrue(ShaderAutomationValidators.isCompletionSatisfied(5, 3, 4, 4, true, 360, 300, 180, 120));
      assertTrue(ShaderAutomationValidators.isCompletionSatisfied(7, 3, 7, 4, true, 500, 300, 240, 120));
   }

   @Test
   void sineCameraMotionStaysIdleBeforeStartAndHitsAmplitudeAtQuarterCycle() {
      assertEquals(0.0f, ShaderAutomationValidators.computeSineMotionOffset(59, 60, 120, 30.0f), EPSILON);
      assertEquals(30.0f, ShaderAutomationValidators.computeSineMotionOffset(90, 60, 120, 30.0f), 1.0e-4);
      assertEquals(0.0f, ShaderAutomationValidators.computeSineMotionOffset(120, 60, 120, 30.0f), 1.0e-4);
   }

   @Test
   void motionPhaseKeyWrapsWithinConfiguredPeriod() {
      assertEquals(-1, ShaderAutomationValidators.motionPhaseKey(59, 60, 120));
      assertEquals(0, ShaderAutomationValidators.motionPhaseKey(60, 60, 120));
      assertEquals(30, ShaderAutomationValidators.motionPhaseKey(90, 60, 120));
      assertEquals(0, ShaderAutomationValidators.motionPhaseKey(180, 60, 120));
   }

   @Test
   void activeTickCaptureFiresOncePerInterval() {
      assertFalse(ShaderAutomationValidators.shouldCaptureOnActiveTick(29, 30, Integer.MIN_VALUE));
      assertTrue(ShaderAutomationValidators.shouldCaptureOnActiveTick(30, 30, Integer.MIN_VALUE));
      assertFalse(ShaderAutomationValidators.shouldCaptureOnActiveTick(30, 30, 30));
      assertTrue(ShaderAutomationValidators.shouldCaptureOnActiveTick(60, 30, 30));
   }

   @Test
   void parseLongSequenceHandlesBlankAndCommaSeparatedValues() {
      assertTrue(Arrays.equals(new long[0], ShaderAutomationValidators.parseLongSequence("")));
      assertTrue(Arrays.equals(new long[]{6000L, 9000L, 12000L}, ShaderAutomationValidators.parseLongSequence("6000, 9000,12000")));
   }

   @Test
   void brightnessVarianceIsZeroForUniformImage() {
      BufferedImage image = solidImage(2, 2, new Color(128, 128, 128, 255));

      assertEquals(0.0, ShaderAutomationImageUtils.computeImageBrightnessVariance(image), EPSILON);
      assertEquals(0.0, ShaderAutomationImageUtils.computeImageBrightnessStdDev(image), EPSILON);
   }

   @Test
   void brightnessVarianceTracksSpreadInPixelLuma() {
      BufferedImage image = new BufferedImage(2, 1, BufferedImage.TYPE_INT_ARGB);
      image.setRGB(0, 0, new Color(0, 0, 0, 255).getRGB());
      image.setRGB(1, 0, new Color(255, 255, 255, 255).getRGB());

      assertEquals(0.25, ShaderAutomationImageUtils.computeImageBrightnessVariance(image), EPSILON);
      assertEquals(0.5, ShaderAutomationImageUtils.computeImageBrightnessStdDev(image), EPSILON);
   }

   @Test
   void maxLumaPixelDeltaTracksLargestPerPixelChange() {
      BufferedImage previousImage = solidImage(2, 1, new Color(0, 0, 0, 255));
      BufferedImage currentImage = new BufferedImage(2, 1, BufferedImage.TYPE_INT_ARGB);
      currentImage.setRGB(0, 0, new Color(255, 0, 0, 255).getRGB());
      currentImage.setRGB(1, 0, new Color(255, 255, 255, 255).getRGB());

      assertEquals(1.0, ShaderAutomationImageUtils.computeMaxLumaPixelDelta(previousImage, currentImage), EPSILON);
   }

   @Test
   void alphaDeltaAveragesPerPixelAlphaChange() {
      BufferedImage previousImage = new BufferedImage(2, 1, BufferedImage.TYPE_INT_ARGB);
      BufferedImage currentImage = new BufferedImage(2, 1, BufferedImage.TYPE_INT_ARGB);
      previousImage.setRGB(0, 0, new Color(0, 0, 0, 255).getRGB());
      previousImage.setRGB(1, 0, new Color(0, 0, 0, 0).getRGB());
      currentImage.setRGB(0, 0, new Color(0, 0, 0, 255).getRGB());
      currentImage.setRGB(1, 0, new Color(0, 0, 0, 255).getRGB());

      assertEquals(0.5, ShaderAutomationImageUtils.computeAlphaDelta(previousImage, currentImage), EPSILON);
   }

   @Test
   void decodePackedReservoirMReadsBitPackedCountFromFloatBits() {
      int packedVisibility = 0x3ffff;
      int reservoirM = 3210;
      int packed = packedVisibility | (reservoirM << 18);

      assertEquals(reservoirM, ShaderAutomation.decodePackedReservoirM(Float.intBitsToFloat(packed)));
   }

   @Test
   void fireflyStatsTrackHotPixelsEnergySaturationAndNonFiniteValues() {
      float[] pixels = {
         1.0f, 1.0f, 1.0f, 1.0f,
         32.0f, 32.0f, 32.0f, 1.0f,
         128.0f, 128.0f, 128.0f, 1.0f,
         65504.0f, 0.0f, 0.0f, 1.0f,
         Float.NaN, 2.0f, 3.0f, 1.0f
      };

      ShaderAutomation.FireflyStats stats = ShaderAutomation.computeFireflyStats(pixels);
      double saturatedRedLuma = 65504.0 * 0.2126;

      assertEquals(0.6, stats.fireflyFraction(), EPSILON);
      assertEquals(0.4, stats.severeFireflyFraction(), EPSILON);
      assertEquals(1.0 / 5.0, stats.saturatedPixelFraction(), EPSILON);
      assertEquals(1.0 / 5.0, stats.nonFiniteFraction(), EPSILON);
      assertEquals((32.0 + 128.0 + saturatedRedLuma) / (1.0 + 32.0 + 128.0 + saturatedRedLuma), stats.fireflyLumaShare(), 1.0e-9);
   }

   private static BufferedImage solidImage(int width, int height, Color color) {
      BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB);
      for (int y = 0; y < height; y++) {
         for (int x = 0; x < width; x++) {
            image.setRGB(x, y, color.getRGB());
         }
      }
      return image;
   }
}
