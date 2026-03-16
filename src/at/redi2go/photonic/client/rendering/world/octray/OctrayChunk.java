package at.redi2go.photonic.client.rendering.world.octray;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.rendering.schematics.AirEntry;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.PBlock;
import at.redi2go.photonic.client.rendering.world.WorldChunk;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryManager;
import at.redi2go.photonic.client.rendering.world.buffer.MemoryRegion;
import it.unimi.dsi.fastutil.objects.Object2IntMap;
import it.unimi.dsi.fastutil.objects.Object2IntOpenHashMap;
import java.nio.IntBuffer;
import java.util.Arrays;
import java.util.concurrent.CompletableFuture;

public class OctrayChunk implements WorldChunk {
   static final int CHUNK_EDGE = 16;
   static final int LEAF_INT_COUNT = CHUNK_EDGE * CHUNK_EDGE * CHUNK_EDGE;
   static final int LOD1_OFFSET = LEAF_INT_COUNT;
   static final int LOD1_INT_COUNT = 8 * 8 * 8;
   static final int LOD2_OFFSET = LOD1_OFFSET + LOD1_INT_COUNT;
   static final int LOD2_INT_COUNT = 4 * 4 * 4;
   static final int LOD3_OFFSET = LOD2_OFFSET + LOD2_INT_COUNT;
   static final int LOD3_INT_COUNT = 2 * 2 * 2;
   static final int LOD4_OFFSET = LOD3_OFFSET + LOD3_INT_COUNT;
   static final int LOD4_INT_COUNT = 1;
   static final int CHUNK_PAGE_INT_COUNT = LOD4_OFFSET + LOD4_INT_COUNT;
   private static final int MAX_SHADER_BLOCK_INDEX = 0xFFF;
   private static final int DEBUG_LOG_LIMIT = 16;
   private static int blockPointerOverflowLogs = 0;
   private final int[] leafData = new int[LEAF_INT_COUNT];
   private final boolean[] occupied = new boolean[LEAF_INT_COUNT];
   private final int[] mipData = new int[CHUNK_PAGE_INT_COUNT - LEAF_INT_COUNT];
   private final Object2IntMap<PBlock> blocks = new Object2IntOpenHashMap<>();
   private MemoryRegion chunkMemory;
   private boolean dirty = true;

   public OctrayChunk() {
      this.resetLeafData();
   }

   @Override
   public void freeBlocks() {
      for (Object2IntMap.Entry<PBlock> entry : this.blocks.object2IntEntrySet()) {
         entry.getKey().changeTimesUsed(-entry.getIntValue());
      }
      this.blocks.clear();
      Arrays.fill(this.occupied, false);
      Arrays.fill(this.mipData, 0);
      this.resetLeafData();
      this.dirty = true;
   }

   @Override
   public void set(int x, int y, int z, PBlock block, int skyBrightness) {
      int value;
      if (block != null) {
         value = block.getMemory().begin >> 2;
         block.changeTimesUsed(1);
         this.blocks.mergeInt(block, 1, Integer::sum);
      } else {
         value = 0;
      }

      value /= PBlock.BYTE_SIZE / 4;
      if (value > MAX_SHADER_BLOCK_INDEX) {
         if (blockPointerOverflowLogs < DEBUG_LOG_LIMIT) {
            blockPointerOverflowLogs++;
            Photonic.warn(
               "[OctrayChunkDebug] Block pointer overflow: blockId={} shaderIndex={} exceeds 12-bit budget, falling back to air",
               block == null ? -1 : block.blockId,
               value
            );
         }
         value = 0;
      }
      if (skyBrightness != -1 && value != 0) {
         value |= skyBrightness << 12;
      }

      int index = Schematic.toSchematicIndex(x, y, z);
      this.occupied[index] = value != 0;
      this.leafData[index] = value != 0 ? -value : AirEntry.toAirEntry(x, y, z, x + 1, y + 1, z + 1);
      this.dirty = true;
   }

   @Override
   public CompletableFuture<Void> optimizeAsync() {
      return CompletableFuture.completedFuture(null);
   }

   @Override
   public void finishUpdate(MemoryManager memoryManager) {
      if (!this.dirty || this.chunkMemory == null) {
         return;
      }

      this.rebuildMipChain();
      IntBuffer buffer = this.chunkMemory.getBuffer().asIntBuffer();
      buffer.position(0);
      buffer.put(this.leafData);
      buffer.put(this.mipData);
      memoryManager.queueUpload(this);
   }

   @Override
   public boolean isDirty() {
      return this.dirty;
   }

   @Override
   public void allocate(MemoryManager memoryManager) {
      this.chunkMemory = memoryManager.allocate(this.getSize());
   }

   @Override
   public void free(MemoryManager memoryManager) {
      if (this.chunkMemory != null) {
         memoryManager.free(this.chunkMemory);
         this.chunkMemory = null;
      }
   }

   @Override
   public boolean update(MemoryManager memoryManager) {
      if (!this.dirty) {
         return false;
      }

      this.finishUpdate(memoryManager);
      return true;
   }

   @Override
   public void afterUpload() {
      this.dirty = false;
   }

   @Override
   public int getSize() {
      return CHUNK_PAGE_INT_COUNT * Integer.BYTES;
   }

   @Override
   public MemoryRegion getMemory() {
      return this.chunkMemory;
   }

   static int getSubChunkLodBaseAddr(int lod) {
      return switch (lod) {
         case 0 -> 0;
         case 1 -> LOD1_OFFSET;
         case 2 -> LOD2_OFFSET;
         case 3 -> LOD3_OFFSET;
         case 4 -> LOD4_OFFSET;
         default -> throw new IllegalArgumentException("Unsupported lod: " + lod);
      };
   }

   static int getSubChunkAddr(int x, int y, int z, int lod) {
      int voxelX = (x & 15) >> lod;
      int voxelY = (y & 15) >> lod;
      int voxelZ = (z & 15) >> lod;
      int edge = CHUNK_EDGE >> lod;
      return getSubChunkLodBaseAddr(lod) + voxelX * edge + voxelY * edge * edge + voxelZ;
   }

   private void rebuildMipChain() {
      Arrays.fill(this.mipData, 0);
      this.rebuildMipLod1();
      this.rebuildMipFromPrevious(2, LOD1_OFFSET, 8);
      this.rebuildMipFromPrevious(3, LOD2_OFFSET, 4);
      this.rebuildMipFromPrevious(4, LOD3_OFFSET, 2);
   }

   private void rebuildMipLod1() {
      int edge = 8;
      for (int y = 0; y < edge; y++) {
         for (int x = 0; x < edge; x++) {
            for (int z = 0; z < edge; z++) {
               int baseX = x * 2, baseY = y * 2, baseZ = z * 2;
               if (this.occupied[Schematic.toSchematicIndex(baseX, baseY, baseZ)]
                  || this.occupied[Schematic.toSchematicIndex(baseX + 1, baseY, baseZ)]
                  || this.occupied[Schematic.toSchematicIndex(baseX, baseY + 1, baseZ)]
                  || this.occupied[Schematic.toSchematicIndex(baseX + 1, baseY + 1, baseZ)]
                  || this.occupied[Schematic.toSchematicIndex(baseX, baseY, baseZ + 1)]
                  || this.occupied[Schematic.toSchematicIndex(baseX + 1, baseY, baseZ + 1)]
                  || this.occupied[Schematic.toSchematicIndex(baseX, baseY + 1, baseZ + 1)]
                  || this.occupied[Schematic.toSchematicIndex(baseX + 1, baseY + 1, baseZ + 1)]) {
                  this.mipData[getSubChunkAddr(baseX, baseY, baseZ, 1) - LEAF_INT_COUNT] = 1;
               }
            }
         }
      }
   }

   private void rebuildMipFromPrevious(int lod, int prevLodOffset, int prevEdge) {
      int edge = CHUNK_EDGE >> lod;
      for (int y = 0; y < edge; y++) {
         for (int x = 0; x < edge; x++) {
            for (int z = 0; z < edge; z++) {
               int bx = x * 2, by = y * 2, bz = z * 2;
               int prevE = prevEdge;
               if (this.mipData[bx * prevE + by * prevE * prevE + bz + prevLodOffset - LEAF_INT_COUNT] != 0
                  || this.mipData[(bx + 1) * prevE + by * prevE * prevE + bz + prevLodOffset - LEAF_INT_COUNT] != 0
                  || this.mipData[bx * prevE + (by + 1) * prevE * prevE + bz + prevLodOffset - LEAF_INT_COUNT] != 0
                  || this.mipData[(bx + 1) * prevE + (by + 1) * prevE * prevE + bz + prevLodOffset - LEAF_INT_COUNT] != 0
                  || this.mipData[bx * prevE + by * prevE * prevE + (bz + 1) + prevLodOffset - LEAF_INT_COUNT] != 0
                  || this.mipData[(bx + 1) * prevE + by * prevE * prevE + (bz + 1) + prevLodOffset - LEAF_INT_COUNT] != 0
                  || this.mipData[bx * prevE + (by + 1) * prevE * prevE + (bz + 1) + prevLodOffset - LEAF_INT_COUNT] != 0
                  || this.mipData[(bx + 1) * prevE + (by + 1) * prevE * prevE + (bz + 1) + prevLodOffset - LEAF_INT_COUNT] != 0) {
                  int span = 1 << lod;
                  this.mipData[getSubChunkAddr(x * span, y * span, z * span, lod) - LEAF_INT_COUNT] = 1;
               }
            }
         }
      }
   }

   private void resetLeafData() {
      for (int y = 0; y < CHUNK_EDGE; y++) {
         for (int x = 0; x < CHUNK_EDGE; x++) {
            for (int z = 0; z < CHUNK_EDGE; z++) {
               this.leafData[Schematic.toSchematicIndex(x, y, z)] = AirEntry.toAirEntry(x, y, z, x + 1, y + 1, z + 1);
            }
         }
      }
   }
}
