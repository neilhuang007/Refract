package at.redi2go.photonic.client;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class BlockBuilderVoxelPackingTest {
   @Test
   void repackShaderVoxelWordMovesSevenBitAlphaIntoHighByte() {
      int rgbPayload = 0x123456 << 7;
      int alpha = 0x5A;
      int packed = rgbPayload | alpha;

      int repacked = BlockBuilder.repackShaderVoxelWord(packed);

      assertEquals(0x123456 | (alpha << 24), repacked);
   }

   @Test
   void voxelRepackIsUnconditionalMatchingThreePointOneZero() throws IOException {
      // 3.1.0 parity: voxel word repacking must be unconditional (no shouldRepack check)
      String source = Files.readString(Path.of("src/at/redi2go/photonic/client/BlockBuilder.java"));
      assertFalse(source.contains("shouldRepackShaderVoxelWords"), "Conditional repack check was removed for 3.1.0 parity");
      assertTrue(source.contains("schematicData[i] = repackShaderVoxelWord(schematicData[i]);"));
   }

   @Test
   void schematicShaderPacksSevenBitAlphaIntoVoxelWords() throws IOException {
      String shader = Files.readString(Path.of("assets/minecraft/shaders/core/schematic.fsh"));

      assertTrue(shader.contains("if (color.a < 0.0078125)"));
      assertTrue(shader.contains("int alpha = int((color.a * 127));"));
      assertTrue(shader.contains("(127 - alpha) | (icolor.x << 7) | (icolor.y << 15) | (icolor.z << 23)"));
      assertTrue(shader.contains("discard;"));
      assertFalse(shader.contains("icolor.x | (icolor.y << 8) | (icolor.z << 16)"));
   }
}
