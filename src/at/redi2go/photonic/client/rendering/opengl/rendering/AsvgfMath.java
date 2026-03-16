package at.redi2go.photonic.client.rendering.opengl.rendering;

/**
 * Test-only helper mirroring A-SVGF denoising math used in the Photonics shader pipeline.
 */
public final class AsvgfMath {

    private AsvgfMath() {
    }

    /**
     * Maps a temporal gradient to an anti-lag strength in [0, 1].
     * Larger gradients signal scene changes and produce stronger anti-lag response.
     */
    public static float computeAntilagAlpha(float temporalGradient) {
        return Math.min(Math.max(temporalGradient, 0.0f), 1.0f);
    }

    /**
     * Advances the effective history length by one frame, clamped by both the
     * maximum allowed history and the anti-lag factor which shortens history
     * during disocclusion events.  Zero previous history always resets to 1.
     */
    public static float computeHistoryLength(float previousHistoryLength, float antilagAlpha, float maxHistoryLength) {
        float candidate = previousHistoryLength + 1.0f;
        float antilagCap = maxHistoryLength * (1.0f - antilagAlpha);
        return Math.max(1.0f, Math.min(candidate, antilagCap));
    }

    /**
     * Computes the temporal accumulation alpha (blend weight toward the current
     * sample).  Combines the inverse-history fallback with the anti-lag floor
     * so that disoccluded pixels immediately trust new data.
     */
    public static float computeTemporalAlpha(float historyLength, float antilagAlpha, float maxHistoryLength) {
        float inverseHistory = 1.0f / Math.max(historyLength, 1.0f);
        return Math.max(inverseHistory, antilagAlpha);
    }

    /**
     * Variance from the first two raw moments: Var = E[X^2] - E[X]^2, floored at zero.
     */
    public static float computeVariance(float firstMoment, float secondMoment) {
        return Math.max(secondMoment - firstMoment * firstMoment, 0.0f);
    }

    /**
     * Depth edge-stopping weight matching the denoising shader formula.
     * phi = max(depthGradient * stepWidth, 1e-4), w = exp(-|delta| / phi).
     */
    public static float computeDepthWeight(float centerDepth, float sampleDepth, float depthGradient, int stepWidth) {
        float phi = Math.max(depthGradient * stepWidth, 1e-4f);
        return (float) Math.exp(-Math.abs(centerDepth - sampleDepth) / phi);
    }

    /**
     * 3x3 wavelet-style normalized filter that attenuates isolated spikes and
     * spreads energy to neighbors.  Uses the same kernel shape as the shader's
     * Gaussian weights: corners 1/6, edges 2/3, center 1.
     *
     * @throws IllegalArgumentException if input is not exactly 3x3
     */
    public static float[][] filterGradient3x3(float[][] input) {
        if (input == null || input.length != 3) {
            throw new IllegalArgumentException("Input must be a 3x3 array");
        }
        for (float[] row : input) {
            if (row == null || row.length != 3) {
                throw new IllegalArgumentException("Input must be a 3x3 array");
            }
        }

        float[][] kernel = {
            {1.0f / 6.0f, 2.0f / 3.0f, 1.0f / 6.0f},
            {2.0f / 3.0f, 1.0f,         2.0f / 3.0f},
            {1.0f / 6.0f, 2.0f / 3.0f, 1.0f / 6.0f}
        };

        float kernelSum = 0.0f;
        for (float[] row : kernel) {
            for (float v : row) {
                kernelSum += v;
            }
        }

        float[][] output = new float[3][3];
        for (int y = 0; y < 3; y++) {
            for (int x = 0; x < 3; x++) {
                float sum = 0.0f;
                float wSum = 0.0f;
                for (int ky = 0; ky < 3; ky++) {
                    for (int kx = 0; kx < 3; kx++) {
                        int sy = y + ky - 1;
                        int sx = x + kx - 1;
                        if (sy >= 0 && sy < 3 && sx >= 0 && sx < 3) {
                            float w = kernel[ky][kx];
                            sum += input[sy][sx] * w;
                            wSum += w;
                        }
                    }
                }
                output[y][x] = sum / wSum;
            }
        }
        return output;
    }
}
