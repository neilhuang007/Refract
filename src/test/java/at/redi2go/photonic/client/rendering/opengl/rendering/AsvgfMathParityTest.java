package at.redi2go.photonic.client.rendering.opengl.rendering;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Extended parity tests for AsvgfMath to verify that Java-side SVGF math
 * functions match the behavior required by the shader-side denoiser.
 */
class AsvgfMathParityTest {
   private static final float EPSILON = 1.0e-5f;

   @Test
   void antilagAlphaClampsBelowZero() {
      assertEquals(0.0f, AsvgfMath.computeAntilagAlpha(-0.5f), EPSILON,
         "Negative temporal gradient must be clamped to 0");
   }

   @Test
   void antilagAlphaClampsAboveOne() {
      assertEquals(1.0f, AsvgfMath.computeAntilagAlpha(1.5f), EPSILON,
         "Temporal gradient above 1 must be clamped to 1");
   }

   @Test
   void antilagAlphaPassthroughInRange() {
      assertEquals(0.42f, AsvgfMath.computeAntilagAlpha(0.42f), EPSILON,
         "Gradient in [0,1] must pass through unchanged");
   }

   @Test
   void historyLengthIncrementsByOneWithZeroAntilag() {
      float result = AsvgfMath.computeHistoryLength(10.0f, 0.0f, 32.0f);
      assertEquals(11.0f, result, EPSILON, "Zero antilag means history grows by one per frame");
   }

   @Test
   void historyLengthCappedByMaxTimesOneMinusAntilag() {
      float antilag = 0.5f;
      float maxHistory = 32.0f;
      float result = AsvgfMath.computeHistoryLength(20.0f, antilag, maxHistory);
      float expectedCap = maxHistory * (1.0f - antilag);
      assertTrue(result <= expectedCap + EPSILON,
         "History length must be capped by maxHistoryLength * (1 - antilagAlpha)");
   }

   @Test
   void historyLengthNeverBelowOne() {
      float result = AsvgfMath.computeHistoryLength(0.0f, 0.99f, 32.0f);
      assertTrue(result >= 1.0f, "History length must never go below 1");
   }

   @Test
   void historyLengthZeroPrevZeroAntilag() {
      assertEquals(1.0f, AsvgfMath.computeHistoryLength(0.0f, 0.0f, 32.0f), EPSILON);
   }

   @Test
   void historyLengthFivePrevZeroAntilag() {
      assertEquals(6.0f, AsvgfMath.computeHistoryLength(5.0f, 0.0f, 32.0f), EPSILON);
   }

   @Test
   void historyLengthCapsAtMax() {
      assertEquals(32.0f, AsvgfMath.computeHistoryLength(31.0f, 0.0f, 32.0f), EPSILON);
   }

   @Test
   void historyLengthWithFullAntilag() {
      assertEquals(1.0f, AsvgfMath.computeHistoryLength(0.0f, 1.0f, 32.0f), EPSILON);
   }

   @Test
   void temporalAlphaIsInverseHistoryWhenAntilagZero() {
      float history = 16.0f;
      float alpha = AsvgfMath.computeTemporalAlpha(history, 0.0f, 32.0f);
      assertEquals(1.0f / history, alpha, EPSILON, "With zero antilag, alpha = 1/history");
   }

   @Test
   void temporalAlphaFlooredByAntilagWhenHistoryIsLong() {
      float alpha = AsvgfMath.computeTemporalAlpha(100.0f, 0.5f, 128.0f);
      assertEquals(0.5f, alpha, EPSILON, "Antilag must floor the temporal alpha when history is long");
   }

   @Test
   void temporalAlphaIsOneForFirstFrame() {
      float alpha = AsvgfMath.computeTemporalAlpha(1.0f, 0.0f, 32.0f);
      assertEquals(1.0f, alpha, EPSILON, "First frame (history=1) must fully trust current sample");
   }

   @Test
   void varianceIsZeroForConstantSignal() {
      assertEquals(0.0f, AsvgfMath.computeVariance(0.7f, 0.49f), EPSILON,
         "E[X^2] - E[X]^2 = 0 for constant signal");
   }

   @Test
   void varianceFloorsAtZero() {
      float result = AsvgfMath.computeVariance(0.9f, 0.5f);
      assertTrue(result >= 0.0f, "Variance must never be negative (floored at zero)");
   }

   @Test
   void varianceProportionalToSpread() {
      float narrowVariance = AsvgfMath.computeVariance(0.5f, 0.26f);
      float wideVariance = AsvgfMath.computeVariance(0.5f, 0.50f);
      assertTrue(wideVariance > narrowVariance, "Wider spread must produce higher variance");
   }

   @Test
   void depthWeightIsOneForIdenticalDepths() {
      float w = AsvgfMath.computeDepthWeight(10.0f, 10.0f, 0.01f, 1);
      assertEquals(1.0f, w, EPSILON, "Identical depths must produce weight of 1.0");
   }

   @Test
   void depthWeightDecaysWithDepthDifference() {
      float close = AsvgfMath.computeDepthWeight(10.0f, 10.01f, 0.01f, 1);
      float far = AsvgfMath.computeDepthWeight(10.0f, 11.0f, 0.01f, 1);
      assertTrue(close > far, "Larger depth difference must produce smaller weight");
   }

   @Test
   void depthWeightPhiFlooredAtMinimum() {
      float w = AsvgfMath.computeDepthWeight(10.0f, 10.01f, 0.0f, 1);
      assertTrue(w > 0.0f && w < 1.0f,
         "Even with zero gradient, phi floor (1e-4) must produce finite non-zero weight");
   }

   @Test
   void depthWeightRelaxedByLargerGradient() {
      float flat = AsvgfMath.computeDepthWeight(10.0f, 10.1f, 0.001f, 4);
      float sloped = AsvgfMath.computeDepthWeight(10.0f, 10.1f, 0.1f, 4);
      assertTrue(sloped > flat, "Larger depth gradient must produce a more permissive weight");
   }

   @Test
   void gradientFilterPreservesUniformInput() {
      float[][] uniform = {
         {0.5f, 0.5f, 0.5f},
         {0.5f, 0.5f, 0.5f},
         {0.5f, 0.5f, 0.5f}
      };
      float[][] filtered = AsvgfMath.filterGradient3x3(uniform);
      for (int y = 0; y < 3; y++) {
         for (int x = 0; x < 3; x++) {
            assertEquals(0.5f, filtered[y][x], EPSILON,
               "Uniform input must pass through unchanged at (" + x + "," + y + ")");
         }
      }
   }

   @Test
   void gradientFilterCenterHasHighestKernelWeight() {
      float[][] spike = {
         {0.0f, 0.0f, 0.0f},
         {0.0f, 1.0f, 0.0f},
         {0.0f, 0.0f, 0.0f}
      };
      float[][] filtered = AsvgfMath.filterGradient3x3(spike);
      for (int y = 0; y < 3; y++) {
         for (int x = 0; x < 3; x++) {
            if (y != 1 || x != 1) {
               assertTrue(filtered[1][1] > filtered[y][x],
                  "Center must retain highest value after filtering a center spike");
            }
         }
      }
   }

   @Test
   void gradientFilterEdgesPropagateMoreThanCorners() {
      float[][] spike = {
         {0.0f, 0.0f, 0.0f},
         {0.0f, 1.0f, 0.0f},
         {0.0f, 0.0f, 0.0f}
      };
      float[][] filtered = AsvgfMath.filterGradient3x3(spike);
      assertTrue(filtered[0][1] > filtered[0][0],
         "Edge neighbors must receive more energy than corner neighbors");
      assertTrue(filtered[1][0] > filtered[0][0],
         "Edge neighbors must receive more energy than corner neighbors");
   }
}
