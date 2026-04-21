package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.config.lights.FakeLevelReader;
import at.redi2go.photonic.client.rendering.schematics.AirEntry;
import at.redi2go.photonics.api.gpu.buffers.BufferUsage;
import at.redi2go.photonics.api.gpu.systems.IRenderSystem;
import at.redi2go.photonics.core.rendering.world.WorldOrigin;
import at.redi2go.photonics.core.rendering.world.allocator.BufferWorldAllocator;
import at.redi2go.photonics.core.rendering.world.allocator.palette.BufferPaletteAllocator;
import at.redi2go.photonics.core.rendering.world.bakery.BlockBakery;
import at.redi2go.photonics.core.rendering.world.block.BlockEntry;
import at.redi2go.photonics.core.rendering.world.block.palette.TextureData;
import net.minecraft.block.BlockState;
import net.minecraft.util.math.BlockPos;

public final class NativeBlockPayloadBuilder {
   private static final WorldOrigin ORIGIN = new WorldOrigin();
   private static final BlockPos BAKE_POS = BlockPos.ORIGIN;
   private static final MinecraftAtlasDownloader ATLAS_DOWNLOADER = new MinecraftAtlasDownloader();

   private NativeBlockPayloadBuilder() {
   }

   public static BufferWorldAllocator createAllocator(MinecraftAtlasDownloader atlasDownloader) {
      return new BufferWorldAllocator(536870912L, new BufferPaletteAllocator(256, 256));
   }

   public static VoxelBake buildBake(BlockState blockState, int blockId) {
      return bakeNativeBlock(blockState, blockId, new BlockBakery(ATLAS_DOWNLOADER));
   }

   public static int[] build(BlockState blockState, int blockId) {
      return buildBake(blockState, blockId).data();
   }

   public static boolean canOcclude(BlockState blockState, int blockId) {
      return buildBake(blockState, blockId).solidVoxelCount() >= NativeBlockPayload.SCHEMATIC_SIZE;
   }

   public static ReferenceBake buildReferenceBake(BlockState blockState, int blockId, BufferWorldAllocator allocator) {
      BlockEntry.Builder builder = allocator.createBlockBuilder();
      BlockBakery bakery = new BlockBakery(ATLAS_DOWNLOADER);
      FakeLevelReader levelReader = new FakeLevelReader(blockState);
      SolidVoxelCounter counter = new SolidVoxelCounter();
      bakery.meshBlock(ORIGIN, (at.redi2go.photonics.api.mc.core.IBlockPos) (Object) BAKE_POS, (at.redi2go.photonics.api.mc.world.level.IBlockState) (Object) blockState, (at.redi2go.photonics.api.mc.world.level.IBlockAndTintGetter) (Object) levelReader);
      bakery.bake((x, y, z, normal, textureData) -> {
         if (x < 0 || y < 0 || z < 0 || x >= NativeBlockPayload.BLOCK_SIZE || y >= NativeBlockPayload.BLOCK_SIZE || z >= NativeBlockPayload.BLOCK_SIZE) {
            return;
         }
         if (builder.insert(x, y, z, (short) 0, normal, textureData)) {
            counter.count++;
         }
      });
      builder.setSkylight(0);
      BlockEntry entry = counter.count > 0 ? builder.build() : null;
      builder.close();
      return new ReferenceBake(entry, counter.count);
   }

   private static VoxelBake bakeNativeBlock(BlockState blockState, int blockId, BlockBakery bakery) {
      int[] data = new int[NativeBlockPayload.SCHEMATIC_SIZE];
      for (int x = 0; x < NativeBlockPayload.BLOCK_SIZE; x++) {
         for (int y = 0; y < NativeBlockPayload.BLOCK_SIZE; y++) {
            for (int z = 0; z < NativeBlockPayload.BLOCK_SIZE; z++) {
               data[index(x, y, z)] = AirEntry.toAirEntry(x, y, z, x + 1, y + 1, z + 1);
            }
         }
      }

      FakeLevelReader levelReader = new FakeLevelReader(blockState);
      SolidVoxelCounter counter = new SolidVoxelCounter();
      bakery.meshBlock(ORIGIN, (at.redi2go.photonics.api.mc.core.IBlockPos) (Object) BAKE_POS, (at.redi2go.photonics.api.mc.world.level.IBlockState) (Object) blockState, (at.redi2go.photonics.api.mc.world.level.IBlockAndTintGetter) (Object) levelReader);
      bakery.bake((x, y, z, normal, textureData) -> putVoxel(data, x, y, z, textureData, blockId, counter));
      return new VoxelBake(data, counter.count);
   }

   private static void putVoxel(int[] data, int x, int y, int z, TextureData textureData, int blockId, SolidVoxelCounter counter) {
      if (x < 0 || y < 0 || z < 0 || x >= NativeBlockPayload.BLOCK_SIZE || y >= NativeBlockPayload.BLOCK_SIZE || z >= NativeBlockPayload.BLOCK_SIZE) {
         return;
      }
      int index = index(x, y, z);
      if (isAir(data[index])) {
         counter.count++;
      }
      int packed = textureData != null ? textureData.color() : blockId;
      data[index] = AirEntry.toData(Math.max(1, packed & 0x7FFFFFFF));
   }

   private static boolean isAir(int value) {
      return value < 0;
   }

   private static int index(int x, int y, int z) {
      return x + (y * NativeBlockPayload.BLOCK_SIZE) + (z * NativeBlockPayload.BLOCK_SIZE * NativeBlockPayload.BLOCK_SIZE);
   }

   public record VoxelBake(int[] data, int solidVoxelCount) {
   }

   public record ReferenceBake(BlockEntry entry, int solidVoxelCount) {
   }

   private static final class SolidVoxelCounter {
      private int count;
   }
}
