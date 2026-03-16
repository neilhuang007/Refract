package at.redi2go.photonic.client;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class BlockBuilderVoxelPackingTest {
   @Test
   void repackShaderVoxelWordMovesSevenBitAlphaIntoHighByte() {
      int rgbPayload = 0x123456 << 7;
      int alpha = 0x5A;
      int packed = rgbPayload | alpha;

      int repacked = BlockBuilder.repackShaderVoxelWord(packed);

      assertEquals(0x123456 | (alpha << 24), repacked);
   }
}
