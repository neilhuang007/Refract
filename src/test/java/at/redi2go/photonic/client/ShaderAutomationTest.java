package at.redi2go.photonic.client;

import java.awt.Color;
import java.awt.image.BufferedImage;
import java.util.Arrays;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ShaderAutomationTest {
   private static final double EPSILON = 1.0e-9;

   @Test
   void blankExpectedShaderPackMatchesAnything() {
      assertTrue(ShaderAutomation.matchesExpectedShaderPack("", "ComplementaryReimagined_r2.0.3"));
      assertTrue(ShaderAutomation.matchesExpectedShaderPack(null, "ComplementaryReimagined_r2.0.3"));
   }

   @Test
   void expectedShaderPackNormalizesVersionSuffixesPunctuationAndEuphoriaAliases() {
      assertTrue(ShaderAutomation.matchesExpectedShaderPack("ComplementaryReimagined", "ComplementaryReimagined_r2.0.3"));
      assertTrue(ShaderAutomation.matchesExpectedShaderPack("ComplementaryReimagined_r2.0.3", "Complementary Reimagined"));
      assertTrue(ShaderAutomation.matchesExpectedShaderPack("ComplementaryReimagined", "Euphoria-patches.zip"));
      assertTrue(ShaderAutomation.matchesExpectedShaderPack("EuphoriaPatches", "ComplementaryReimagined_r5.7.1"));
      assertFalse(ShaderAutomation.matchesExpectedShaderPack("ComplementaryUnbound", "ComplementaryReimagined_r2.0.3"));
   }

   @Test
   void nonBlankExpectedShaderPackRequiresNonBlankActualName() {
      assertFalse(ShaderAutomation.matchesExpectedShaderPack("ComplementaryReimagined", ""));
      assertFalse(ShaderAutomation.matchesExpectedShaderPack("ComplementaryReimagined", null));
   }

   @Test
   void blankExpectedPatchIdPrefixMatchesAnything() {
      assertTrue(ShaderAutomation.matchesExpectedPatchIdPrefix("", "BASIC:native"));
      assertTrue(ShaderAutomation.matchesExpectedPatchIdPrefix(null, "OCTRAY:patched"));
   }

   @Test
   void expectedPatchIdPrefixRequiresMatchingPatchIdPrefix() {
      assertTrue(ShaderAutomation.matchesExpectedPatchIdPrefix("OCTRAY:", "OCTRAY:native"));
      assertFalse(ShaderAutomation.matchesExpectedPatchIdPrefix("OCTRAY:", "BASIC:native"));
   }

   @Test
   void maxLumaTracksBrightestPixelInImage() {
      BufferedImage image = new BufferedImage(2, 2, BufferedImage.TYPE_INT_ARGB);
      image.setRGB(0, 0, new Color(0, 0, 0, 255).getRGB());
      image.setRGB(1, 0, new Color(255, 0, 0, 255).getRGB());
      image.setRGB(0, 1, new Color(0, 255, 0, 255).getRGB());
      image.setRGB(1, 1, new Color(255, 255, 255, 255).getRGB());

      assertEquals(1.0, ShaderAutomation.computeMaxLuma(image), EPSILON);
   }

   @Test
   void maxLumaUsesStandardRec709Weights() {
      BufferedImage image = new BufferedImage(1, 1, BufferedImage.TYPE_INT_ARGB);
      image.setRGB(0, 0, new Color(255, 0, 0, 255).getRGB());

      assertEquals(0.2126, ShaderAutomation.computeMaxLuma(image), EPSILON);
   }

   @Test
   void activeTicksSinceFirstSignalUsesSentinelBeforeSignalAndDeltaAfterward() {
      assertEquals(-1, ShaderAutomation.activeTicksSinceFirstSignal(120, -1));
      assertEquals(0, ShaderAutomation.activeTicksSinceFirstSignal(120, 120));
      assertEquals(45, ShaderAutomation.activeTicksSinceFirstSignal(120, 75));
   }

   @Test
   void completionSatisfiedRequiresMoreThanAnySingleLightingSignal() {
      assertFalse(ShaderAutomation.isCompletionSatisfied(5, 3, 1, 3, true, 320, 300, 200, 120));
      assertFalse(ShaderAutomation.isCompletionSatisfied(5, 3, 3, 3, true, 250, 300, 200, 120));
      assertFalse(ShaderAutomation.isCompletionSatisfied(5, 3, 3, 3, true, 320, 300, 60, 120));
      assertFalse(ShaderAutomation.isCompletionSatisfied(2, 3, 2, 3, true, 320, 300, 200, 120));
      assertFalse(ShaderAutomation.isCompletionSatisfied(5, 3, 3, 3, false, 320, 300, 200, 120));
   }

   @Test
   void completionSatisfiedAcceptsSustainedLitCapturesAfterSettleWindow() {
      assertTrue(ShaderAutomation.isCompletionSatisfied(5, 3, 4, 4, true, 360, 300, 180, 120));
      assertTrue(ShaderAutomation.isCompletionSatisfied(7, 3, 7, 4, true, 500, 300, 240, 120));
   }

   @Test
   void sineCameraMotionStaysIdleBeforeStartAndHitsAmplitudeAtQuarterCycle() {
      assertEquals(0.0f, ShaderAutomation.computeSineMotionOffset(59, 60, 120, 30.0f), EPSILON);
      assertEquals(30.0f, ShaderAutomation.computeSineMotionOffset(90, 60, 120, 30.0f), 1.0e-4);
      assertEquals(0.0f, ShaderAutomation.computeSineMotionOffset(120, 60, 120, 30.0f), 1.0e-4);
   }

   @Test
   void motionPhaseKeyWrapsWithinConfiguredPeriod() {
      assertEquals(-1, ShaderAutomation.motionPhaseKey(59, 60, 120));
      assertEquals(0, ShaderAutomation.motionPhaseKey(60, 60, 120));
      assertEquals(30, ShaderAutomation.motionPhaseKey(90, 60, 120));
      assertEquals(0, ShaderAutomation.motionPhaseKey(180, 60, 120));
   }

   @Test
   void activeTickCaptureFiresOncePerInterval() {
      assertFalse(ShaderAutomation.shouldCaptureOnActiveTick(29, 30, Integer.MIN_VALUE));
      assertTrue(ShaderAutomation.shouldCaptureOnActiveTick(30, 30, Integer.MIN_VALUE));
      assertFalse(ShaderAutomation.shouldCaptureOnActiveTick(30, 30, 30));
      assertTrue(ShaderAutomation.shouldCaptureOnActiveTick(60, 30, 30));
   }

   @Test
   void parseLongSequenceHandlesBlankAndCommaSeparatedValues() {
      assertTrue(Arrays.equals(new long[0], ShaderAutomation.parseLongSequence("")));
      assertTrue(Arrays.equals(new long[]{6000L, 9000L, 12000L}, ShaderAutomation.parseLongSequence("6000, 9000,12000")));
   }
}
