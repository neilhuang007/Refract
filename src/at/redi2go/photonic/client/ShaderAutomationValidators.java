package at.redi2go.photonic.client;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public final class ShaderAutomationValidators {
   private ShaderAutomationValidators() {}

   public static boolean matchesExpectedShaderPack(String expected, String actual) {
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

   public static int activeTicksSinceFirstSignal(int activeTicks, int firstLightingSignalActiveTick) {
      return firstLightingSignalActiveTick < 0 ? -1 : Math.max(0, activeTicks - firstLightingSignalActiveTick);
   }

   public static boolean isCompletionSatisfied(int capturesTaken,
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

   public static boolean matchesExpectedPatchIdPrefix(String expectedPatchIdPrefix, String patchId) {
      return expectedPatchIdPrefix == null || expectedPatchIdPrefix.isBlank() || patchId.startsWith(expectedPatchIdPrefix);
   }

   public static boolean shouldCaptureOnActiveTick(int activeTicks, int captureEveryActiveTicks, int lastCapturedActiveTick) {
      return captureEveryActiveTicks > 0
         && activeTicks > 0
         && activeTicks % captureEveryActiveTicks == 0
         && activeTicks != lastCapturedActiveTick;
   }

   public static float computeSineMotionOffset(int activeTicks, int motionStartActiveTick, int motionPeriodTicks, float amplitudeDegrees) {
      if (motionPeriodTicks <= 0 || amplitudeDegrees <= 0.0f || activeTicks < motionStartActiveTick) {
         return 0.0f;
      }

      double phase = (double) (activeTicks - motionStartActiveTick) / (double) motionPeriodTicks;
      return (float) (Math.sin(phase * Math.PI * 2.0) * amplitudeDegrees);
   }

   public static int motionPhaseKey(int activeTicks, int motionStartActiveTick, int motionPeriodTicks) {
      if (motionPeriodTicks <= 0 || activeTicks < motionStartActiveTick) {
         return -1;
      }

      return Math.floorMod(activeTicks - motionStartActiveTick, motionPeriodTicks);
   }

   public static long[] parseLongSequence(String value) {
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
}
