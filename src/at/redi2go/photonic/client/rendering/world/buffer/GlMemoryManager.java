package at.redi2go.photonic.client.rendering.world.buffer;

import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;
import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.util.BufferUtils;
import java.nio.ByteBuffer;
import java.util.Deque;
import java.util.Iterator;
import java.util.LinkedList;
import java.util.Queue;
import java.util.function.Consumer;
import org.lwjgl.opengl.GL15;
import org.lwjgl.opengl.GL30;
import org.lwjgl.opengl.GL31;
import org.lwjgl.opengl.GL43;

public class GlMemoryManager implements Destructable {
   private int id;
   private final GlTarget target;
   private final boolean staticData;
   private final String name;
   private final ByteBuffer buffer;
   public int index = 0;
   private int uploadBatchSize = Integer.MAX_VALUE;
   private final Deque<MemoryOwner> uploadQueue = new LinkedList<>();
   public final Queue<MemoryRegion> unusedBuffers = new LinkedList<>();

   public GlMemoryManager(GlTarget target, String name, int byteSize, boolean staticData) {
      this.target = target;
      this.name = name;
      this.staticData = staticData;
      this.buffer = BufferUtils.createByteBuffer(byteSize);
   }

   public MemoryRegion allocate(int byteSize) {
      Iterator<MemoryRegion> memoryIterator = this.unusedBuffers.iterator();

      while (memoryIterator.hasNext()) {
         MemoryRegion region = memoryIterator.next();
         if (region.end - region.begin == byteSize) {
            memoryIterator.remove();
            region.allocated = true;
            return region;
         }
      }

      int begin = this.index;
      int end = this.index + byteSize;
      this.index += byteSize;
      return new MemoryRegion(this.buffer.slice(begin, end - begin).order(this.buffer.order()), begin, end);
   }

   public void bind(int program, int blockIndex, int bindingPointIndex) {
      this.ensureAllocated();
      GL30.glBindBufferBase(this.target.target, bindingPointIndex, this.id);
      if (this.target == GlTarget.SSBO) {
         GL43.glShaderStorageBlockBinding(program, blockIndex, bindingPointIndex);
      } else if (this.target == GlTarget.UBO) {
         GL31.glUniformBlockBinding(program, blockIndex, bindingPointIndex);
      }
   }

   public int findInProgram(int program) {
      this.ensureAllocated();

      return switch (this.target) {
         case SSBO -> GL43.glGetProgramResourceIndex(program, 37606, this.name);
         case UBO -> GL31.glGetUniformBlockIndex(program, this.name);
      };
   }

   public boolean upload() {
      this.ensureAllocated();
      GL15.glBindBuffer(this.target.target, this.id);

      for (int i = 0; i < this.uploadBatchSize && !this.uploadQueue.isEmpty(); i++) {
         MemoryOwner memoryOwner = this.uploadQueue.poll();
         MemoryRegion memoryRegion = memoryOwner.getMemory();
         GL15.glBufferSubData(this.target.target, memoryRegion.begin, memoryRegion.getBuffer());
         memoryOwner.afterUpload();
      }

      GL15.glBindBuffer(this.target.target, 0);
      return this.uploadQueue.isEmpty();
   }

   public void download(Consumer<ByteBuffer> downloadContext) {
      this.ensureAllocated();
      GL15.glBindBuffer(this.target.target, this.id);
      ByteBuffer downloadedBuffer = GL15.glMapBuffer(this.target.target, 35002, null);
      downloadContext.accept(downloadedBuffer);
      GL15.glUnmapBuffer(this.target.target);
      GL15.glBindBuffer(this.target.target, 0);
   }

   public void queueUpload(MemoryOwner memoryOwner) {
      this.uploadQueue.addLast(memoryOwner);
   }

   public void queueUploadPriority(MemoryOwner memoryOwner) {
      this.uploadQueue.addFirst(memoryOwner);
   }

   public void free(MemoryRegion memoryRegion) {
      memoryRegion.allocated = false;
      this.unusedBuffers.add(memoryRegion);
   }

   private void ensureAllocated() {
      if (this.id == 0) {
         this.id = GL15.glGenBuffers();
         GL15.glBindBuffer(this.target.target, this.id);
         GL15.glBufferData(this.target.target, this.buffer.capacity(), this.staticData ? '裤' : '裨');
         GL15.glBindBuffer(this.target.target, 0);
      }
   }

   public void setUploadBatchSize(int uploadBatchSize) {
      this.uploadBatchSize = uploadBatchSize;
   }

   public int getCapacity() {
      return this.buffer.capacity();
   }

   @Override
   public void free() {
      if (this.id != 0) {
         GL15.glDeleteBuffers(this.id);
      }
   }
}
