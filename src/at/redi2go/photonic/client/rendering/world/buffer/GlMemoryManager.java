package at.redi2go.photonic.client.rendering.world.buffer;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.rendering.opengl.objects.Destructable;
import at.redi2go.photonic.client.rendering.opengl.objects.GlTarget;
import at.redi2go.photonic.client.rendering.util.BufferUtils;
import java.nio.ByteBuffer;
import java.util.Deque;
import java.util.Iterator;
import java.util.Queue;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedDeque;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.function.Consumer;
import org.lwjgl.opengl.GL15;
import org.lwjgl.opengl.GL30;
import org.lwjgl.opengl.GL31;
import org.lwjgl.opengl.GL43;

public class GlMemoryManager implements MemoryManager {
   private int id;
   private final GlTarget target;
   private final boolean staticData;
   private final String name;
   private final ByteBuffer buffer;
   public int index = 0;
   private int uploadBatchSize = Integer.MAX_VALUE;
   private final Deque<MemoryOwner> uploadQueue = new ConcurrentLinkedDeque<>();
   private final Set<MemoryOwner> queuedUploads = ConcurrentHashMap.newKeySet();
   private volatile int lastUploadCount = 0;
   private volatile long lastUploadedBytes = 0L;
   public final Queue<MemoryRegion> unusedBuffers = new ConcurrentLinkedQueue<>();

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
      if (end > this.buffer.capacity()) {
         throw new OutOfMemoryError("Could not allocate " + byteSize + " bytes");
      }
      this.index += byteSize;
      return new MemoryRegion(this.buffer.slice(begin, end - begin).order(this.buffer.order()), begin, end);
   }

   public MemoryManager allocateRegion(int byteSize) {
      return new BufferRegion(this.allocate(byteSize));
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

   public String getName() {
      return this.name;
   }

   public boolean upload() {
      this.ensureAllocated();
      GL15.glBindBuffer(this.target.target, this.id);
      int uploadedCount = 0;
      long uploadedBytes = 0L;

      for (int i = 0; i < this.uploadBatchSize && !this.uploadQueue.isEmpty(); i++) {
         MemoryOwner memoryOwner = this.uploadQueue.poll();
         if (memoryOwner == null) {
            Photonic.warn("Memory owner is null?");
         } else {
            this.queuedUploads.remove(memoryOwner);
            synchronized (memoryOwner) {
               MemoryRegion memoryRegion = memoryOwner.getMemory();
               if (memoryRegion != null) {
                  GL15.glBufferSubData(this.target.target, memoryRegion.begin, memoryRegion.getBuffer());
                  uploadedCount++;
                  uploadedBytes += (long) (memoryRegion.end - memoryRegion.begin);
                  memoryOwner.afterUpload();
               }
            }
         }
      }

      this.lastUploadCount = uploadedCount;
      this.lastUploadedBytes = uploadedBytes;
      GL15.glBindBuffer(this.target.target, 0);
      return this.uploadQueue.isEmpty();
   }

   public boolean uploadIfNeeded() {
      if (this.uploadQueue.isEmpty()) {
         this.lastUploadCount = 0;
         this.lastUploadedBytes = 0L;
         return true;
      }
      return this.upload();
   }

   public void download(Consumer<ByteBuffer> downloadContext) {
      this.ensureAllocated();
      GL15.glBindBuffer(this.target.target, this.id);
      ByteBuffer downloadedBuffer = GL15.glMapBuffer(this.target.target, GL15.GL_READ_WRITE, null);
      if (downloadedBuffer == null) {
         GL15.glBindBuffer(this.target.target, 0);
         return;
      }
      try {
         downloadContext.accept(downloadedBuffer);
      } finally {
         GL15.glUnmapBuffer(this.target.target);
      }
      GL15.glBindBuffer(this.target.target, 0);
   }

   public void queueUpload(MemoryOwner memoryOwner) {
      if (memoryOwner == null) {
         System.err.println("Trying to upload null?");
      } else if (this.queuedUploads.add(memoryOwner)) {
         this.uploadQueue.addLast(memoryOwner);
      }
   }

   public void queueUploadPriority(MemoryOwner memoryOwner) {
      if (memoryOwner == null) {
         System.err.println("Trying to priority-upload null?");
      } else if (this.queuedUploads.add(memoryOwner)) {
         this.uploadQueue.addFirst(memoryOwner);
      }
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

   public int getId() {
      this.ensureAllocated();
      return this.id;
   }

   public int getCapacity() {
      return this.buffer.capacity();
   }

   public int getPendingUploadCount() {
      return this.uploadQueue.size();
   }

   public int getLastUploadCount() {
      return this.lastUploadCount;
   }

   public long getLastUploadedBytes() {
      return this.lastUploadedBytes;
   }

   @Override
   public void free() {
      if (this.id != 0) {
         GL15.glDeleteBuffers(this.id);
         this.id = -1;
      }
   }

   private class BufferRegion implements MemoryManager {
      private final MemoryRegion memory;
      private int index;
      public final Queue<MemoryRegion> unusedBuffers = new ConcurrentLinkedQueue<>();

      BufferRegion(MemoryRegion region) {
         this.memory = region;
         this.index = region.begin;
      }

      @Override
      public int getCapacity() {
         return this.memory.end - this.memory.begin;
      }

      @Override
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
         if (end > this.memory.end) {
            throw new OutOfMemoryError("Could not allocate " + byteSize + " bytes");
         }

         this.index += byteSize;
         return new MemoryRegion(GlMemoryManager.this.buffer.slice(begin, end - begin).order(GlMemoryManager.this.buffer.order()), begin, end);
      }

      @Override
      public boolean upload() {
         return GlMemoryManager.this.upload();
      }

      @Override
      public void queueUpload(MemoryOwner memoryOwner) {
         GlMemoryManager.this.queueUpload(memoryOwner);
      }

      @Override
      public void queueUploadPriority(MemoryOwner memoryOwner) {
         GlMemoryManager.this.queueUploadPriority(memoryOwner);
      }

      @Override
      public void free(MemoryRegion memoryRegion) {
         memoryRegion.allocated = false;
         this.unusedBuffers.add(memoryRegion);
      }

      @Override
      public void free() {
         GlMemoryManager.this.free(this.memory);
      }
   }
}
