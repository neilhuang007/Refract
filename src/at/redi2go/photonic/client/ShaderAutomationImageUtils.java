package at.redi2go.photonic.client;

import java.awt.image.BufferedImage;

public final class ShaderAutomationImageUtils {
   private ShaderAutomationImageUtils() {}

   public static double[] computeImageStats(BufferedImage image) {
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

   public static double[] computeImageAlphaStats(BufferedImage image) {
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

   public static double computeImageBrightnessVariance(BufferedImage image) {
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

   public static double computeImageBrightnessStdDev(BufferedImage image) {
      return Math.sqrt(computeImageBrightnessVariance(image));
   }

   public static double computeMaxLumaPixelDelta(BufferedImage previousImage, BufferedImage currentImage) {
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

   public static double computeAlphaDelta(BufferedImage previousImage, BufferedImage currentImage) {
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

   public static double computeMaxLuma(BufferedImage image) {
      return computeImageStats(image)[0];
   }

   public static double computeMeanLumaDelta(BufferedImage previousImage, BufferedImage currentImage) {
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

   public static double computeRelativeImprovement(double baseline, double improved) {
      if (baseline <= 1.0e-6) {
         return 0.0;
      }
      return Math.max(0.0, (baseline - improved) / baseline);
   }

   public static double computeLuma(int argb) {
      double red = ((argb >> 16) & 255) / 255.0;
      double green = ((argb >> 8) & 255) / 255.0;
      double blue = (argb & 255) / 255.0;
      return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
   }
}
