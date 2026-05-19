package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.PhotonicsStorage;
import at.redi2go.photonic.client.rendering.world.position.PBlockPos;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import java.util.Arrays;
import net.minecraft.util.math.BlockPos;
import org.joml.Vector3d;

/**
 * Owns all state for the temporal light-blend subsystem:
 * pending/live AABB region lists, the blend age counter,
 * full-reset state, and the frame-advance clock.
 *
 * WorldRegistry holds a single instance and delegates every public
 * blend API to it so that external callers require no changes.
 */
public final class LightBlendController {

   public static final int TEMPORAL_BLEND_FRAMES = 8;
   static final int MAX_LIGHT_BLEND_REGIONS = 8;
   private static final int LIGHT_BLEND_EXPANSION_BLOCKS = 16;

   // Pending (not yet activated) region list
   private final PBlockPos[] pendingLightBlendMin = new PBlockPos[MAX_LIGHT_BLEND_REGIONS];
   private final PBlockPos[] pendingLightBlendMax = new PBlockPos[MAX_LIGHT_BLEND_REGIONS];
   private int pendingLightBlendRegionCount = 0;
   private boolean pendingLightBlendDirty = false;

   // Full-reset request state
   private boolean pendingFullLightBlendReset = true;
   private String pendingFullLightBlendResetReason = "initial";

   // Live (currently blending) region list
   private final PBlockPos[] liveLightBlendMin = new PBlockPos[MAX_LIGHT_BLEND_REGIONS];
   private final PBlockPos[] liveLightBlendMax = new PBlockPos[MAX_LIGHT_BLEND_REGIONS];
   private int liveLightBlendRegionCount = 0;

   // Blend age / frame tracking
   private int lightBlendAge = 0;
   private boolean fullLightBlendActive = false;
   private int lastLightBlendFrame = -1;

   // Logging state (only used by logPendingBlendRegionTransition)
   private int lastLoggedPendingBlendCount = -1;
   private long lastLoggedPendingBlendVolume = -1L;
   private long lastLoggedPendingBlendLargest = -1L;

   // Automation counters (blend-specific)
   private long automationBlendFullActivations = 0L;
   private long automationBlendRegionActivations = 0L;
   private long automationBlendCompletions = 0L;
   private long automationPendingBlendMutationEvents = 0L;
   private int automationMaxPendingBlendRegions = 0;
   private long automationMaxPendingBlendVolume = 0L;

   public LightBlendController() {
   }

   // -------------------------------------------------------------------------
   // Mutators called from WorldRegistry on block-update / chunk-load paths
   // -------------------------------------------------------------------------

   public void markLightBlendBlock(BlockPos blockPos) {
      int expand = LIGHT_BLEND_EXPANSION_BLOCKS;
      this.markLightBlendRegion(
         blockPos.getX() - expand,
         blockPos.getY() - expand,
         blockPos.getZ() - expand,
         blockPos.getX() + 1 + expand,
         blockPos.getY() + 1 + expand,
         blockPos.getZ() + 1 + expand
      );
   }

   public void markLightBlendChunk(PChunkPos chunkPos) {
      PBlockPos chunkMin = chunkPos.toBlockPos();
      int expand = LIGHT_BLEND_EXPANSION_BLOCKS;
      this.markLightBlendRegion(
         chunkMin.x - expand,
         chunkMin.y - expand,
         chunkMin.z - expand,
         chunkMin.x + 16 + expand,
         chunkMin.y + 16 + expand,
         chunkMin.z + 16 + expand
      );
   }

   public void markLightBlendRegion(int minX, int minY, int minZ, int maxX, int maxY, int maxZ) {
      PBlockPos newMin = new PBlockPos(minX, minY, minZ);
      PBlockPos newMax = new PBlockPos(maxX, maxY, maxZ);
      if (lightBlendRegionsContain(this.pendingLightBlendMin, this.pendingLightBlendMax, this.pendingLightBlendRegionCount, newMin, newMax)
         || this.lightBlendAge > 0
         && lightBlendRegionsContain(this.liveLightBlendMin, this.liveLightBlendMax, this.liveLightBlendRegionCount, newMin, newMax)) {
         return;
      }

      int previousCount = this.pendingLightBlendRegionCount;
      long previousVolume = totalLightBlendVolume(this.pendingLightBlendMin, this.pendingLightBlendMax, previousCount);
      long previousLargest = largestLightBlendRegionVolume(this.pendingLightBlendMin, this.pendingLightBlendMax, previousCount);
      this.pendingLightBlendRegionCount = WorldRegistry.appendLightBlendRegion(
         this.pendingLightBlendMin,
         this.pendingLightBlendMax,
         this.pendingLightBlendRegionCount,
         MAX_LIGHT_BLEND_REGIONS,
         minX,
         minY,
         minZ,
         maxX,
         maxY,
         maxZ
      );
      this.pendingLightBlendDirty = this.pendingLightBlendRegionCount > 0;
      this.automationPendingBlendMutationEvents++;
      this.automationMaxPendingBlendRegions = Math.max(this.automationMaxPendingBlendRegions, this.pendingLightBlendRegionCount);
      this.automationMaxPendingBlendVolume = Math.max(
         this.automationMaxPendingBlendVolume,
         totalLightBlendVolume(this.pendingLightBlendMin, this.pendingLightBlendMax, this.pendingLightBlendRegionCount)
      );
      this.logPendingBlendRegionTransition(previousCount, previousVolume, previousLargest, "chunk_mutation");
   }

   /**
    * Activates the pending region list as the live blend.
    * Called from WorldRegistry.upload() when a region (not full) blend is needed.
    *
    * @return true if at least one live region was set
    */
   public boolean activatePendingLightBlend() {
      if (!this.pendingLightBlendDirty) {
         return false;
      }
      long pendingVolume = totalLightBlendVolume(this.pendingLightBlendMin, this.pendingLightBlendMax, this.pendingLightBlendRegionCount);
      long pendingLargest = largestLightBlendRegionVolume(this.pendingLightBlendMin, this.pendingLightBlendMax, this.pendingLightBlendRegionCount);
      this.automationBlendRegionActivations++;
      this.automationMaxPendingBlendRegions = Math.max(this.automationMaxPendingBlendRegions, this.pendingLightBlendRegionCount);
      this.automationMaxPendingBlendVolume = Math.max(this.automationMaxPendingBlendVolume, pendingVolume);
      this.liveLightBlendRegionCount = copyLightBlendRegions(
         this.pendingLightBlendMin,
         this.pendingLightBlendMax,
         this.pendingLightBlendRegionCount,
         this.liveLightBlendMin,
         this.liveLightBlendMax
      );
      this.lightBlendAge = TEMPORAL_BLEND_FRAMES;
      this.fullLightBlendActive = false;
      this.clearPendingLightBlendRegions();
      if (PhotonicsStorage.PROFILER_ENABLED.value && this.liveLightBlendRegionCount > 0) {
         Photonic.info("[Profiler] temporalBlend activate: mode=region regions={} volume={} largest={} frames={}",
            this.liveLightBlendRegionCount,
            pendingVolume,
            pendingLargest,
            TEMPORAL_BLEND_FRAMES);
      }
      return this.liveLightBlendRegionCount > 0;
   }

   /**
    * Activates a full-world blend reset covering the entire tracked volume.
    * Called from WorldRegistry.upload() (formerly private, same call site).
    *
    * @param reason         diagnostic string for profiler logs
    * @param worldOffset    current live world block offset (liveWorldBlockOffset)
    * @param worldBlockSize half-size of the RT world volume in blocks
    */
   public void activateFullLightBlendReset(String reason, Vector3d worldOffset, int worldBlockSize) {
      this.liveLightBlendMin[0] = new PBlockPos(
         (int) worldOffset.x - worldBlockSize,
         (int) worldOffset.y - worldBlockSize,
         (int) worldOffset.z - worldBlockSize
      );
      this.liveLightBlendMax[0] = new PBlockPos(
         (int) worldOffset.x + worldBlockSize,
         (int) worldOffset.y + worldBlockSize,
         (int) worldOffset.z + worldBlockSize
      );
      this.liveLightBlendRegionCount = 1;
      this.lightBlendAge = TEMPORAL_BLEND_FRAMES;
      this.fullLightBlendActive = true;
      this.automationBlendFullActivations++;
      if (PhotonicsStorage.PROFILER_ENABLED.value) {
         Photonic.info("[Profiler] temporalBlend activate: mode=full reason={} regions=1 volume={} frames={}",
            reason,
            lightBlendRegionVolume(this.liveLightBlendMin[0], this.liveLightBlendMax[0]),
            TEMPORAL_BLEND_FRAMES);
      }
   }

   /**
    * Advances the blend age counter by one tick.
    * No-op if this frame was already processed (deduplicates multi-calls per frame).
    */
   public void advanceLightBlendFrame(int frame) {
      if (frame == this.lastLightBlendFrame) {
         return;
      }
      this.lastLightBlendFrame = frame;
      if (this.lightBlendAge > 0) {
         this.lightBlendAge--;
         if (this.lightBlendAge <= 0) {
            boolean wasFullBlend = this.fullLightBlendActive;
            int completedRegions = this.liveLightBlendRegionCount;
            long completedVolume = totalLightBlendVolume(this.liveLightBlendMin, this.liveLightBlendMax, this.liveLightBlendRegionCount);
            this.automationBlendCompletions++;
            this.fullLightBlendActive = false;
            Arrays.fill(this.liveLightBlendMin, null);
            Arrays.fill(this.liveLightBlendMax, null);
            this.liveLightBlendRegionCount = 0;
            if (PhotonicsStorage.PROFILER_ENABLED.value) {
               Photonic.info("[Profiler] temporalBlend complete: mode={} regions={} volume={}",
                  wasFullBlend ? "full" : "region",
                  completedRegions,
                  completedVolume);
            }
         }
      }
   }

   // -------------------------------------------------------------------------
   // Pending-reset management (called from WorldRegistry.requestFullLightBlendReset)
   // -------------------------------------------------------------------------

   /**
    * Records a request for a full blend reset to be applied on the next upload.
    *
    * @return true if this was a new (not already-pending same-reason) request,
    *         so the caller (WorldRegistry) can increment its automation counters.
    */
   public boolean requestFullLightBlendReset(String reason) {
      String resolvedReason = reason == null || reason.isBlank() ? "unknown" : reason;
      String currentReason = this.pendingFullLightBlendResetReason == null || this.pendingFullLightBlendResetReason.isBlank()
         ? "none"
         : this.pendingFullLightBlendResetReason;
      boolean alreadyPendingSameReason = this.pendingFullLightBlendReset && WorldRegistry.hasResetReason(currentReason, resolvedReason);
      boolean wasPending = this.pendingFullLightBlendReset;
      this.pendingFullLightBlendReset = true;
      if (!wasPending || currentReason.equals("none")) {
         this.pendingFullLightBlendResetReason = resolvedReason;
      } else if (!currentReason.equals(resolvedReason) && !currentReason.contains(resolvedReason)) {
         this.pendingFullLightBlendResetReason = currentReason + "+" + resolvedReason;
      }
      if (PhotonicsStorage.PROFILER_ENABLED.value && !wasPending) {
         Photonic.info("[Profiler] temporalReset pending: reason={} liveAge={} liveRegions={} pendingRegions={}",
            this.pendingFullLightBlendResetReason,
            this.lightBlendAge,
            this.liveLightBlendRegionCount,
            this.pendingLightBlendRegionCount);
      }
      return !alreadyPendingSameReason;
   }

   /**
    * Returns true if a full reset is pending and consumes it (clears the flag).
    * Also clears the pending region list via clearPendingLightBlendRegions.
    * Returns the pending reason string, or null if no reset was pending.
    *
    * Caller (WorldRegistry.upload) pattern:
    *   if (lightBlend.consumePendingFullReset()) { ... lightBlend.clearPendingRegions(); }
    */
   public boolean isPendingFullLightBlendReset() {
      return this.pendingFullLightBlendReset;
   }

   public String getPendingFullLightBlendResetReason() {
      return this.pendingFullLightBlendResetReason;
   }

   public void clearPendingFullLightBlendReset() {
      this.pendingFullLightBlendReset = false;
      this.pendingFullLightBlendResetReason = "none";
   }

   public void clearPendingLightBlendRegions() {
      Arrays.fill(this.pendingLightBlendMin, null);
      Arrays.fill(this.pendingLightBlendMax, null);
      this.pendingLightBlendRegionCount = 0;
      this.pendingLightBlendDirty = false;
      this.lastLoggedPendingBlendCount = -1;
      this.lastLoggedPendingBlendVolume = -1L;
      this.lastLoggedPendingBlendLargest = -1L;
   }

   // -------------------------------------------------------------------------
   // Read APIs called from renderer / shader uniform setup
   // -------------------------------------------------------------------------

   public boolean hasActiveLightBlend() {
      return this.lightBlendAge > 0 && this.liveLightBlendRegionCount > 0;
   }

   public float fetchLightBlendFactor() {
      if (this.lightBlendAge > 0) {
         return (float) this.lightBlendAge / TEMPORAL_BLEND_FRAMES;
      }
      return 0.0f;
   }

   public boolean fetchLightReload() {
      return WorldRegistry.isGlobalLightReloadActive(this.lightBlendAge, this.fullLightBlendActive);
   }

   public boolean isFullLightBlendActive() {
      return this.fullLightBlendActive;
   }

   public int getLightBlendRegionCount() {
      return this.lightBlendAge > 0 ? this.liveLightBlendRegionCount : 0;
   }

   public int getLastLightBlendFrame() {
      return this.lastLightBlendFrame;
   }

   public int getLightBlendAge() {
      return this.lightBlendAge;
   }

   public int getPendingLightBlendRegionCount() {
      return this.pendingLightBlendRegionCount;
   }

   public boolean isPendingLightBlendDirty() {
      return this.pendingLightBlendDirty;
   }

   public Vector3d getLightBlendMin(int index) {
      if (this.lightBlendAge > 0 && index >= 0 && index < this.liveLightBlendRegionCount && this.liveLightBlendMin[index] != null) {
         return new Vector3d(this.liveLightBlendMin[index].x, this.liveLightBlendMin[index].y, this.liveLightBlendMin[index].z);
      }
      return new Vector3d(0, 0, 0);
   }

   public Vector3d getLightBlendMax(int index) {
      if (this.lightBlendAge > 0 && index >= 0 && index < this.liveLightBlendRegionCount && this.liveLightBlendMax[index] != null) {
         return new Vector3d(this.liveLightBlendMax[index].x, this.liveLightBlendMax[index].y, this.liveLightBlendMax[index].z);
      }
      return new Vector3d(0, 0, 0);
   }

   // -------------------------------------------------------------------------
   // Automation counter accessors
   // -------------------------------------------------------------------------

   public long getAutomationBlendFullActivations() {
      return this.automationBlendFullActivations;
   }

   public long getAutomationBlendRegionActivations() {
      return this.automationBlendRegionActivations;
   }

   public long getAutomationBlendCompletions() {
      return this.automationBlendCompletions;
   }

   public long getAutomationPendingBlendMutationEvents() {
      return this.automationPendingBlendMutationEvents;
   }

   public int getAutomationMaxPendingBlendRegions() {
      return this.automationMaxPendingBlendRegions;
   }

   public long getAutomationMaxPendingBlendVolume() {
      return this.automationMaxPendingBlendVolume;
   }

   // -------------------------------------------------------------------------
   // Private helpers
   // -------------------------------------------------------------------------

   private void logPendingBlendRegionTransition(int previousCount, long previousVolume, long previousLargest, String reason) {
      if (!PhotonicsStorage.PROFILER_ENABLED.value || !this.pendingLightBlendDirty) {
         return;
      }
      long currentVolume = totalLightBlendVolume(this.pendingLightBlendMin, this.pendingLightBlendMax, this.pendingLightBlendRegionCount);
      long currentLargest = largestLightBlendRegionVolume(this.pendingLightBlendMin, this.pendingLightBlendMax, this.pendingLightBlendRegionCount);
      if (previousCount == this.pendingLightBlendRegionCount
         && previousVolume == currentVolume
         && previousLargest == currentLargest
         && this.lastLoggedPendingBlendCount == this.pendingLightBlendRegionCount
         && this.lastLoggedPendingBlendVolume == currentVolume
         && this.lastLoggedPendingBlendLargest == currentLargest) {
         return;
      }
      this.lastLoggedPendingBlendCount = this.pendingLightBlendRegionCount;
      this.lastLoggedPendingBlendVolume = currentVolume;
      this.lastLoggedPendingBlendLargest = currentLargest;
      Photonic.info("[Profiler] temporalBlend pending: reason={} regions={}→{} volume={}→{} largest={}→{} liveActive={} liveAge={}",
         reason,
         previousCount,
         this.pendingLightBlendRegionCount,
         previousVolume,
         currentVolume,
         previousLargest,
         currentLargest,
         this.liveLightBlendRegionCount,
         this.lightBlendAge);
   }

   private static int copyLightBlendRegions(PBlockPos[] sourceMins,
                                            PBlockPos[] sourceMaxs,
                                            int sourceCount,
                                            PBlockPos[] targetMins,
                                            PBlockPos[] targetMaxs) {
      Arrays.fill(targetMins, null);
      Arrays.fill(targetMaxs, null);
      for (int i = 0; i < sourceCount; i++) {
         targetMins[i] = new PBlockPos(sourceMins[i].x, sourceMins[i].y, sourceMins[i].z);
         targetMaxs[i] = new PBlockPos(sourceMaxs[i].x, sourceMaxs[i].y, sourceMaxs[i].z);
      }
      return sourceCount;
   }

   static boolean lightBlendRegionContains(PBlockPos outerMin, PBlockPos outerMax, PBlockPos innerMin, PBlockPos innerMax) {
      return outerMin.x <= innerMin.x && outerMax.x >= innerMax.x
         && outerMin.y <= innerMin.y && outerMax.y >= innerMax.y
         && outerMin.z <= innerMin.z && outerMax.z >= innerMax.z;
   }

   private static boolean lightBlendRegionsContain(PBlockPos[] mins,
                                                   PBlockPos[] maxs,
                                                   int regionCount,
                                                   PBlockPos innerMin,
                                                   PBlockPos innerMax) {
      for (int i = 0; i < regionCount; i++) {
         if (mins[i] != null && maxs[i] != null && lightBlendRegionContains(mins[i], maxs[i], innerMin, innerMax)) {
            return true;
         }
      }
      return false;
   }

   static long lightBlendRegionUnionVolume(PBlockPos minA, PBlockPos maxA, PBlockPos minB, PBlockPos maxB) {
      return lightBlendRegionVolume(
         new PBlockPos(Math.min(minA.x, minB.x), Math.min(minA.y, minB.y), Math.min(minA.z, minB.z)),
         new PBlockPos(Math.max(maxA.x, maxB.x), Math.max(maxA.y, maxB.y), Math.max(maxA.z, maxB.z))
      );
   }

   static long lightBlendRegionVolume(PBlockPos min, PBlockPos max) {
      long dx = Math.max(1, (long) max.x - min.x);
      long dy = Math.max(1, (long) max.y - min.y);
      long dz = Math.max(1, (long) max.z - min.z);
      return dx * dy * dz;
   }

   static long totalLightBlendVolume(PBlockPos[] mins, PBlockPos[] maxs, int regionCount) {
      long total = 0L;
      for (int i = 0; i < regionCount; i++) {
         total += lightBlendRegionVolume(mins[i], maxs[i]);
      }
      return total;
   }

   static long largestLightBlendRegionVolume(PBlockPos[] mins, PBlockPos[] maxs, int regionCount) {
      long largest = 0L;
      for (int i = 0; i < regionCount; i++) {
         largest = Math.max(largest, lightBlendRegionVolume(mins[i], maxs[i]));
      }
      return largest;
   }
}
