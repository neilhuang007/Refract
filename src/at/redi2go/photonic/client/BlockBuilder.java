package at.redi2go.photonic.client;

import at.redi2go.photonic.client.rendering.schematics.Schematic;
import at.redi2go.photonic.client.rendering.world.NativeBlockPayload;
import at.redi2go.photonic.client.rendering.world.NativeBlockPayloadBuilder;
import net.minecraft.block.BlockState;

public class BlockBuilder {
   public static final int BLOCK_VOXEL_SIZE = 16;
   public static int RENDER_INDEX = 0;
   public static boolean IS_BUILDING_BLOCK_BUFFER = false;

   public static void streamBlockBuild(BlockState blockState, NativeBlockPayload block) {
      block.setVoxelData(NativeBlockPayloadBuilder.build(blockState, block.blockId));
   }

   public static int repackShaderVoxelWord(int packed) {
      int alpha = packed >>> 24;
      return (packed & 0x00FFFFFF) | ((127 - alpha) << 24);
   }

   public static Schematic buildBlockSchematic(BlockState blockState) {
      return buildBlockSchematic(blockState, BLOCK_VOXEL_SIZE);
   }

   public static Schematic buildBlockSchematic(BlockState blockState, int voxelResolution) {
      BlockRegistry blockRegistry = Raytracer.INSTANCE != null ? Raytracer.INSTANCE.getBlockRegistry() : null;
      Schematic schematic = blockRegistry != null ? blockRegistry.getSchematic(blockState) : null;
      return schematic != null ? schematic : new Schematic(new int[voxelResolution * voxelResolution * voxelResolution], voxelResolution, voxelResolution, voxelResolution);
   }
}
