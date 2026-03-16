package at.redi2go.photonic.client.rendering.opengl.rendering;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AsvgfMathTest {
   private static final float EPSILON = 1.0e-6f;

   @Test
   void highTemporalGradientShortensHistoryAndRaisesAccumulationAlpha() {
      float stableAntilag = AsvgfMath.computeAntilagAlpha(0.02f);
      float reactiveAntilag = AsvgfMath.computeAntilagAlpha(0.85f);

      float stableHistory = AsvgfMath.computeHistoryLength(24.0f, stableAntilag, 32.0f);
      float reactiveHistory = AsvgfMath.computeHistoryLength(24.0f, reactiveAntilag, 32.0f);

      float stableAlpha = AsvgfMath.computeTemporalAlpha(stableHistory, stableAntilag, 32.0f);
      float reactiveAlpha = AsvgfMath.computeTemporalAlpha(reactiveHistory, reactiveAntilag, 32.0f);

      assertTrue(reactiveAntilag > stableAntilag, "Large gradients must increase anti-lag strength");
      assertTrue(reactiveHistory < stableHistory, "Large gradients must shorten effective history");
      assertTrue(reactiveAlpha > stableAlpha, "Large gradients must bias temporal blending toward current samples");
   }

   @Test
   void missingHistoryFallsBackToCurrentSample() {
      float antilag = AsvgfMath.computeAntilagAlpha(0.35f);
      float historyLength = AsvgfMath.computeHistoryLength(0.0f, antilag, 32.0f);
      float alpha = AsvgfMath.computeTemporalAlpha(historyLength, antilag, 32.0f);

      assertEquals(1.0f, historyLength, EPSILON, "Missing history must reset the effective history length");
      assertEquals(1.0f, alpha, EPSILON, "Missing history must fully trust the current sample");
   }

   @Test
   void momentsVarianceDistinguishesStableAndNoisySignals() {
      float stableVariance = AsvgfMath.computeVariance(0.5f, 0.25f);
      float noisyVariance = AsvgfMath.computeVariance(0.5f, 0.50f);

      assertEquals(0.0f, stableVariance, EPSILON, "Constant signals must have zero variance");
      assertTrue(noisyVariance > stableVariance, "Noisy signals must report higher variance");
   }

   @Test
   void depthGradientAwarePhiPreservesSlopedSurfacesBetterThanFlatPhi() {
      float flatWeight = AsvgfMath.computeDepthWeight(10.0f, 10.05f, 0.001f, 4);
      float slopedWeight = AsvgfMath.computeDepthWeight(10.0f, 10.05f, 0.05f, 4);

      assertTrue(slopedWeight > flatWeight, "Higher local depth gradients should relax the depth rejection on sloped surfaces");
   }

   @Test
   void waveletGradientFilterSpreadsSinglePixelSpikes() {
      float[][] input = new float[][]{
         {0.0f, 0.0f, 0.0f},
         {0.0f, 1.0f, 0.0f},
         {0.0f, 0.0f, 0.0f}
      };

      float[][] filtered = AsvgfMath.filterGradient3x3(input);

      assertTrue(filtered[1][1] < 1.0f, "Filtering must attenuate isolated spikes");
      assertTrue(filtered[0][1] > 0.0f, "Filtering must spread energy to neighboring pixels");
      assertTrue(filtered[1][0] > 0.0f, "Filtering must spread energy to neighboring pixels");
   }
}
