package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.BlockBuilder;
import at.redi2go.photonic.client.rendering.util.BufferUtils;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryOwner;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import java.nio.IntBuffer;
import java.util.Arrays;
import org.joml.Vector3f;

public class NativeBlockPayload implements MemoryOwner {
   public static int numAllocated = 0;
   public static final int BLOCK_SIZE = BlockBuilder.BLOCK_VOXEL_SIZE;
   public static final int SCHEMATIC_SIZE = BLOCK_SIZE * BLOCK_SIZE * BLOCK_SIZE;
   public static final int BYTE_SIZE = SCHEMATIC_SIZE * Integer.BYTES + Integer.BYTES * 2;
   public final int blockId;
   public int emissionColor;
   public boolean canOcclude = false;
   private int[] voxelData;
   private MemoryRegion blockMemory;
   private int timesUsed = 0;
   private boolean needsUpdate = false;

   public NativeBlockPayload(int blockId, int[] voxelData) {
      if (voxelData == null) {
         throw new IllegalArgumentException("voxelData must not be null");
      }
      if (voxelData.length != SCHEMATIC_SIZE) {
         throw new IllegalArgumentException("voxelData must have length " + SCHEMATIC_SIZE);
      }
      this.blockId = blockId;
      this.voxelData = Arrays.copyOf(voxelData, voxelData.length);
   }

   public boolean needsUpdate() {
      return this.needsUpdate;
   }

   public boolean isUsed() {
      return this.timesUsed > 0;
   }

   public void changeTimesUsed(int delta) {
      this.timesUsed = Math.max(0, this.timesUsed + delta);
   }

   public boolean isAllocated() {
      return this.blockMemory != null;
   }

   @Override
   public void allocate(MemoryManager memoryManager) {
      if (this.blockMemory == null) {
         this.blockMemory = memoryManager.allocate(this.getSize());
         this.needsUpdate = true;
         numAllocated++;
      }
   }

   @Override
   public void free(MemoryManager memoryManager) {
      if (this.blockMemory != null) {
         memoryManager.free(this.blockMemory);
         this.needsUpdate = true;
         this.blockMemory = null;
         numAllocated = Math.max(0, numAllocated - 1);
      }
   }

   @Override
   public boolean update(MemoryManager memoryManager) {
      if (!this.needsUpdate) {
         return false;
      }
      this.needsUpdate = false;
      IntBuffer buffer = this.blockMemory.getBuffer().asIntBuffer();
      buffer.position(0);
      buffer.put(this.blockId);
      buffer.put(this.emissionColor);
      buffer.put(this.voxelData);

      memoryManager.queueUploadPriority(this);
      return true;
   }

   @Override
   public void afterUpload() {
   }

   @Override
   public int getSize() {
      return BYTE_SIZE;
   }

   @Override
   public MemoryRegion getMemory() {
      return this.blockMemory;
   }

   public int getIndex() {
      return this.blockMemory.begin / (BYTE_SIZE / 4095);
   }

   public void setVoxelData(int[] voxelData) {
      if (voxelData == null) {
         throw new IllegalArgumentException("voxelData must not be null");
      }
      if (voxelData.length != SCHEMATIC_SIZE) {
         throw new IllegalArgumentException("voxelData must have length " + SCHEMATIC_SIZE);
      }
      this.voxelData = Arrays.copyOf(voxelData, voxelData.length);
      this.needsUpdate = true;
   }

   public void setEmissionColor(Vector3f color) {
      int[] bytes = BufferUtils.packUnorm4x8(color.x, color.y, color.z, 0.0F);
      this.emissionColor = bytes[0] | bytes[1] << 8 | bytes[2] << 16;
      this.needsUpdate = true;
   }

   public void setPackedEmissionColor(int packedColor) {
      this.emissionColor = packedColor & 16777215;
      this.needsUpdate = true;
   }
}
