package at.redi2go.photonic.client.rendering.world.buffer;

import java.nio.ByteBuffer;

public class MemoryRegion {
   private final ByteBuffer buffer;
   public final int begin;
   public final int end;
   public boolean allocated = true;

   MemoryRegion(ByteBuffer buffer, int begin, int end) {
      this.buffer = buffer;
      this.begin = begin;
      this.end = end;
   }

   public ByteBuffer getBuffer() {
      return this.buffer.duplicate().order(this.buffer.order());
   }

   public MemoryRegion slice(int relativeBegin, int byteSize) {
      if (relativeBegin < 0 || byteSize < 0 || relativeBegin + byteSize > this.end - this.begin) {
         throw new IllegalArgumentException("Slice exceeds memory region bounds");
      }

      int sliceBegin = this.begin + relativeBegin;
      int sliceEnd = sliceBegin + byteSize;
      ByteBuffer sliceBuffer = this.buffer.slice(relativeBegin, byteSize).order(this.buffer.order());
      return new MemoryRegion(sliceBuffer, sliceBegin, sliceEnd);
   }
}
