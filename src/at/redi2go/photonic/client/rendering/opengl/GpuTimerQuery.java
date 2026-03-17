package at.redi2go.photonic.client.rendering.opengl;

import java.util.ArrayDeque;
import java.util.Arrays;
import org.lwjgl.opengl.GL15;
import org.lwjgl.opengl.GL33;

public class GpuTimerQuery {
   private static final int frameBufferCount = 3;

   private final String[] regionNames;
   private final int[][] startQueryIds;
   private final int[][] endQueryIds;
   private final long[] regionTimeNanos;
   private final boolean[] frameSubmitted;
   private final ArrayDeque<Integer> queryPool = new ArrayDeque<>();
   private int currentFrameSlot = 0;
   private int resolveFrameSlot = -1;
   private boolean isDestroyed;

   public GpuTimerQuery(String[] regionNames) {
      this.regionNames = Arrays.copyOf(regionNames, regionNames.length);
      this.startQueryIds = new int[frameBufferCount][regionNames.length];
      this.endQueryIds = new int[frameBufferCount][regionNames.length];
      this.regionTimeNanos = new long[regionNames.length];
      this.frameSubmitted = new boolean[frameBufferCount];
   }

   public void begin(int regionIndex) {
      this.validateActive();
      this.validateRegionIndex(regionIndex);
      this.releaseQuery(this.startQueryIds[this.currentFrameSlot][regionIndex]);
      int queryId = this.acquireQuery();
      this.startQueryIds[this.currentFrameSlot][regionIndex] = queryId;
      GL33.glQueryCounter(queryId, GL33.GL_TIMESTAMP);
   }

   public void end(int regionIndex) {
      this.validateActive();
      this.validateRegionIndex(regionIndex);
      this.releaseQuery(this.endQueryIds[this.currentFrameSlot][regionIndex]);
      int queryId = this.acquireQuery();
      this.endQueryIds[this.currentFrameSlot][regionIndex] = queryId;
      GL33.glQueryCounter(queryId, GL33.GL_TIMESTAMP);
      this.frameSubmitted[this.currentFrameSlot] = true;
   }

   public boolean resolve() {
      this.validateActive();
      if (this.resolveFrameSlot < 0) {
         this.resolveFrameSlot = this.findNextSubmittedFrame(this.currentFrameSlot);
         if (this.resolveFrameSlot < 0) {
            return false;
         }
      }

      if (!this.areFrameQueriesReady(this.resolveFrameSlot)) {
         return false;
      }

      for (int regionIndex = 0; regionIndex < this.regionNames.length; regionIndex++) {
         int startQueryId = this.startQueryIds[this.resolveFrameSlot][regionIndex];
         int endQueryId = this.endQueryIds[this.resolveFrameSlot][regionIndex];
         if (startQueryId == 0 || endQueryId == 0) {
            this.regionTimeNanos[regionIndex] = 0L;
            continue;
         }

         long startTime = GL33.glGetQueryObjecti64(startQueryId, GL15.GL_QUERY_RESULT);
         long endTime = GL33.glGetQueryObjecti64(endQueryId, GL15.GL_QUERY_RESULT);
         this.regionTimeNanos[regionIndex] = Math.max(0L, endTime - startTime);
      }

      this.recycleFrameQueries(this.resolveFrameSlot);
      this.resolveFrameSlot = -1;
      return true;
   }

   public long getTimeNanos(int regionIndex) {
      this.validateActive();
      this.validateRegionIndex(regionIndex);
      return this.regionTimeNanos[regionIndex];
   }

   public long getTimeMillis(int regionIndex) {
      return this.getTimeNanos(regionIndex) / 1_000_000L;
   }

   public void destroy() {
      if (this.isDestroyed) {
         return;
      }

      for (int frameSlot = 0; frameSlot < frameBufferCount; frameSlot++) {
         this.recycleFrameQueries(frameSlot);
      }

      while (!this.queryPool.isEmpty()) {
         GL33.glDeleteQueries(this.queryPool.removeFirst());
      }

      this.isDestroyed = true;
   }

   private int acquireQuery() {
      if (!this.queryPool.isEmpty()) {
         return this.queryPool.removeFirst();
      }
      return GL33.glGenQueries();
   }

   public void nextFrame() {
      this.validateActive();
      this.currentFrameSlot = this.getNextFrameSlot(this.currentFrameSlot);
      if (this.frameSubmitted[this.currentFrameSlot]) {
         this.recycleFrameQueries(this.currentFrameSlot);
      }
   }

   private boolean areFrameQueriesReady(int frameSlot) {
      for (int regionIndex = 0; regionIndex < this.regionNames.length; regionIndex++) {
         int startQueryId = this.startQueryIds[frameSlot][regionIndex];
         int endQueryId = this.endQueryIds[frameSlot][regionIndex];
         if (startQueryId == 0 || endQueryId == 0) {
            continue;
         }
         if (GL33.glGetQueryObjecti(startQueryId, GL15.GL_QUERY_RESULT_AVAILABLE) == 0
            || GL33.glGetQueryObjecti(endQueryId, GL15.GL_QUERY_RESULT_AVAILABLE) == 0) {
            return false;
         }
      }
      return true;
   }

   private int findNextSubmittedFrame(int preferredStartSlot) {
      for (int offset = 1; offset <= frameBufferCount; offset++) {
         int slot = (preferredStartSlot + offset) % frameBufferCount;
         if (this.frameSubmitted[slot]) {
            return slot;
         }
      }
      return -1;
   }

   private void recycleFrameQueries(int frameSlot) {
      for (int regionIndex = 0; regionIndex < this.regionNames.length; regionIndex++) {
         this.releaseQuery(this.startQueryIds[frameSlot][regionIndex]);
         this.startQueryIds[frameSlot][regionIndex] = 0;
         this.releaseQuery(this.endQueryIds[frameSlot][regionIndex]);
         this.endQueryIds[frameSlot][regionIndex] = 0;
      }
      this.frameSubmitted[frameSlot] = false;
   }

   private void releaseQuery(int queryId) {
      if (queryId == 0) {
         return;
      }
      this.queryPool.addLast(queryId);
   }

   private int getNextFrameSlot(int frameSlot) {
      return (frameSlot + 1) % frameBufferCount;
   }

   private void validateRegionIndex(int regionIndex) {
      if (regionIndex >= 0 && regionIndex < this.regionNames.length) {
         return;
      }
      throw new IllegalArgumentException("Invalid GPU timer region index: " + regionIndex);
   }

   private void validateActive() {
      if (!this.isDestroyed) {
         return;
      }
      throw new IllegalStateException("GpuTimerQuery has already been destroyed");
   }
}
