package at.redi2go.photonic.client.magicavoxel;

import at.redi2go.photonic.client.rendering.schematics.Schematic;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class VoxReaderTest {
   @Test
   void readsMinimalValidVoxIntoSchematic() throws IOException {
      byte[] vox = createVox(true);
      Schematic schematic = VoxReader.readToSchematic(new ByteArrayInputStream(vox));

      assertEquals(1, schematic.getWidth());
      assertEquals(1, schematic.getHeight());
      assertEquals(1, schematic.getDepth());

      int expectedColor = MagicaVox.packNormalized(new float[]{1.0F, 1.0F, 1.0F, 0.0F});
      assertEquals(expectedColor, schematic.getEntry(0, 0, 0));
   }

   @Test
   void missingSizeChunkThrowsMeaningfulErrorInsteadOfNpe() throws IOException {
      byte[] vox = createVox(false);

      IllegalStateException exception = assertThrows(
         IllegalStateException.class,
         () -> VoxReader.readToSchematic(new ByteArrayInputStream(vox))
      );
      assertEquals("Missing required VOX chunk: SIZE", exception.getMessage());
   }

   private static byte[] createVox(boolean includeSizeChunk) throws IOException {
      ByteArrayOutputStream children = new ByteArrayOutputStream();

      if (includeSizeChunk) {
         ByteArrayOutputStream sizeContent = new ByteArrayOutputStream();
         writeIntLE(sizeContent, 1);
         writeIntLE(sizeContent, 1);
         writeIntLE(sizeContent, 1);
         writeChunk(children, "SIZE", sizeContent.toByteArray(), new byte[0]);
      }

      ByteArrayOutputStream xyziContent = new ByteArrayOutputStream();
      writeIntLE(xyziContent, 1);
      xyziContent.write(0);
      xyziContent.write(0);
      xyziContent.write(0);
      xyziContent.write(2);
      writeChunk(children, "XYZI", xyziContent.toByteArray(), new byte[0]);

      ByteArrayOutputStream mainChunk = new ByteArrayOutputStream();
      writeChunk(mainChunk, "MAIN", new byte[0], children.toByteArray());

      ByteArrayOutputStream out = new ByteArrayOutputStream();
      out.write("VOX ".getBytes(StandardCharsets.US_ASCII));
      writeIntLE(out, 150);
      out.write(mainChunk.toByteArray());
      return out.toByteArray();
   }

   private static void writeChunk(ByteArrayOutputStream out, String id, byte[] content, byte[] children) throws IOException {
      out.write(id.getBytes(StandardCharsets.US_ASCII));
      writeIntLE(out, content.length);
      writeIntLE(out, children.length);
      out.write(content);
      out.write(children);
   }

   private static void writeIntLE(ByteArrayOutputStream out, int value) {
      out.write(value & 0xFF);
      out.write(value >> 8 & 0xFF);
      out.write(value >> 16 & 0xFF);
      out.write(value >> 24 & 0xFF);
   }
}
