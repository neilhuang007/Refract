package at.redi2go.photonic.client;

import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.opengl.rendering.RegirComputeProgram;
import at.redi2go.photonic.client.rendering.world.LightRegistry;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

public final class ShaderAutomationGpuDebugExtractor {

   private static final int RTXDI_DI_GENERATE_INITIAL_SAMPLES_RANDOM_SEED = 1;
   private static final int REGIR_HASH_MAX_PROBES = 128;

   private ShaderAutomationGpuDebugExtractor() {
   }

   // -------------------------------------------------------------------------
   // Public records
   // -------------------------------------------------------------------------

   public record ReservoirDebugStats(
      double lightValidFraction,
      double strictValidFraction,
      double meanWeight,
      double meanM
   ) {
      static final ReservoirDebugStats EMPTY = new ReservoirDebugStats(0.0, 0.0, 0.0, 0.0);
   }

   public record InitialSamplingDebugStats(
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
      ShaderAutomation.RowJumpStats successRowJump,
      ShaderAutomation.RowJumpStats zeroTargetRowJump,
      ShaderAutomation.RowJumpStats proposalValidRowJump,
      ShaderAutomation.RowJumpStats proposalWeightRowJump
   ) {
      static final InitialSamplingDebugStats EMPTY = new InitialSamplingDebugStats(
         0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
         ShaderAutomation.RowJumpStats.EMPTY,
         ShaderAutomation.RowJumpStats.EMPTY,
         ShaderAutomation.RowJumpStats.EMPTY,
         ShaderAutomation.RowJumpStats.EMPTY
      );
   }

   public record ReGIRPixelCorrelationStats(
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
      ShaderAutomation.RowJumpStats cellValidSlotsJump,
      ShaderAutomation.RowJumpStats cellMeanWeightJump,
      ShaderAutomation.RowJumpStats outsideGridJump,
      ShaderAutomation.RowJumpStats jitteredCellChangedJump,
      ShaderAutomation.RowJumpStats jitteredCellMeanWeightDeltaJump,
      ShaderAutomation.RowJumpStats jitteredOutsideGridDeltaJump
   ) {
      static final ReGIRPixelCorrelationStats EMPTY = new ReGIRPixelCorrelationStats(
         0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
         ShaderAutomation.RowJumpStats.EMPTY,
         ShaderAutomation.RowJumpStats.EMPTY,
         ShaderAutomation.RowJumpStats.EMPTY,
         ShaderAutomation.RowJumpStats.EMPTY,
         ShaderAutomation.RowJumpStats.EMPTY,
         ShaderAutomation.RowJumpStats.EMPTY
      );
   }

   // -------------------------------------------------------------------------
   // Private records / helper types
   // -------------------------------------------------------------------------

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
         new int[0], new double[0], new int[0], new int[0], new int[0], new int[0], new int[0]
      );
   }

   private record ReGIRHashCellCoord(int x, int y, int z) {
   }

   private record ReGIRCellSampleStats(int representativeSlot, int validSlots, double meanWeight) {
      boolean found() {
         return this.representativeSlot >= 0;
      }
   }

   private static final class RandomSamplerState {
      private final int seed;
      private int index;

      private RandomSamplerState(int seed, int index) {
         this.seed = seed;
         this.index = index;
      }
   }

   // -------------------------------------------------------------------------
   // Public static methods
   // -------------------------------------------------------------------------

   public static ReservoirDebugStats computeReservoirDebugStats(TextureObject texture) {
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
         int reservoirM = ShaderAutomation.decodePackedReservoirM(pixels[base + 3]);
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

   public static InitialSamplingDebugStats computeInitialSamplingDebugStats(TextureObject texture) {
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
         ShaderAutomation.computeRowJumpStats(successRows),
         ShaderAutomation.computeRowJumpStats(zeroTargetRows),
         ShaderAutomation.computeRowJumpStats(proposalValidRows),
         ShaderAutomation.computeRowJumpStats(proposalWeightRows)
      );
   }

   public static ReGIRPixelCorrelationStats computeReGIRPixelCorrelationStats(
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
            int resolvedM = ShaderAutomation.decodePackedReservoirM(resolvedPixels[base + 3]);
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
         ShaderAutomation.computeRowJumpStats(cellValidSlotRows),
         ShaderAutomation.computeRowJumpStats(cellMeanWeightRows),
         ShaderAutomation.computeRowJumpStats(outsideGridRows),
         ShaderAutomation.computeRowJumpStats(jitteredCellChangedRows),
         ShaderAutomation.computeRowJumpStats(jitteredCellMeanWeightDeltaRows),
         ShaderAutomation.computeRowJumpStats(jitteredOutsideGridDeltaRows)
      );
   }

   // -------------------------------------------------------------------------
   // Private static helpers — exclusively used by the above
   // -------------------------------------------------------------------------

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
}
