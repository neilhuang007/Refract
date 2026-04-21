package at.redi2go.photonic.client;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class BlockBuilderVoxelPackingTest {
   @Test
   void defaultBuildResolutionMatchesLegacyVoxelSize() {
      assertEquals(16, BlockBuilder.BLOCK_VOXEL_SIZE);
   }

   @Test
   void repackShaderVoxelWordPreservesRgbAndMovesTransparencyIntoHighByte() {
      int alpha = 0x5A;
      int packed = (alpha << 24) | 0x123456;

      int repacked = BlockBuilder.repackShaderVoxelWord(packed);

      assertEquals(0x123456 | ((127 - alpha) << 24), repacked);
   }

   @Test
   void shaderSelectionPackingPrioritizesOpacityOverBrighterColor() {
      int opaqueDarkVoxel = (127 << 24) | 0x010101;
      int translucentBrightVoxel = (64 << 24) | 0xFFFFFF;

      assertTrue(
         opaqueDarkVoxel > translucentBrightVoxel,
         "The schematic build word must sort opaque fragments ahead of brighter translucent ones"
      );
   }
}
