package at.redi2go.photonic.client.magicavoxel;

import at.redi2go.photonic.client.rendering.schematics.Schematic;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Objects;

public class VoxReader {
   public static Schematic readToSchematic(InputStream inputStream) {
      MagicaVox.Chunk mainChunk = Objects.requireNonNull(readToVox(inputStream)).main;

      assert mainChunk != null;

      if (mainChunk.get(MagicaVox.Size.class) == null) {
         throw new IllegalStateException("Missing required VOX chunk: SIZE");
      }
      MagicaVox.Size size = (MagicaVox.Size)mainChunk.get(MagicaVox.Size.class).get(0).content;
      MagicaVox.Palette palette = mainChunk.get(MagicaVox.Palette.class) != null ? (MagicaVox.Palette)mainChunk.get(MagicaVox.Palette.class).get(0).content : MagicaVox.DEFAULT_PALETTE;
      if (palette.colors == null) {
          palette.colors = new int[256];
      }
      MagicaVox.Voxels voxels = mainChunk.get(MagicaVox.Voxels.class) != null ? (MagicaVox.Voxels)mainChunk.get(MagicaVox.Voxels.class).get(0).content : new MagicaVox.Voxels();
      if (voxels.voxels == null) {
          voxels.voxels = new byte[size.width * size.height * size.depth];
          voxels.size = size;
      }
      Schematic schematic = new Schematic(size.width, size.height, size.depth);

      for (int x = 0; x < size.width; x++) {
         for (int y = 0; y < size.height; y++) {
            for (int z = 0; z < size.depth; z++) {
               int paletteIndex = voxels.get(x, y, z);
               if (paletteIndex != 0) {
                  float[] color = MagicaVox.unpackNormalized(palette.get(paletteIndex));
                  color[3] = 0.5F - color[3] * 0.5F;
                  schematic.setEntry(x, y, z, MagicaVox.packNormalized(color));
               }
            }
         }
      }

      return schematic;
   }

   public static MagicaVox.Vox readToVox(InputStream inputStream) {
      InputBuffer buffer;
      try {
         buffer = new InputBuffer(MagicaVox.BYTE_ORDER, inputStream.readAllBytes());
      } catch (IOException var3) {
         throw new RuntimeException(var3);
      }

      if (!readString(buffer, 4).equals("VOX ")) {
         return null;
      } else {
         MagicaVox.Vox vox = new MagicaVox.Vox();
         vox.version = buffer.getInt();
         vox.main = readChunk(null, buffer);
         return vox;
      }
   }

   private static MagicaVox.Chunk readChunk(MagicaVox.Chunk root, InputBuffer buffer) {
      MagicaVox.Chunk chunk = new MagicaVox.Chunk();
      root = root != null ? root : chunk;
      chunk.id = readString(buffer, 4);
      int chunkContentSize = buffer.getInt();
      int chunkChildrenSize = buffer.getInt();
      InputBuffer contentBuffer = buffer.slice(chunkContentSize);
      InputBuffer childrenBuffer = buffer.slice(chunkChildrenSize);
      chunk.children = new HashMap<>();

      while (childrenBuffer.isAvailable()) {
         MagicaVox.Chunk childChunk = readChunk(root, childrenBuffer);
         if (childChunk.content != null) {
            chunk.children.computeIfAbsent(childChunk.content.getClass(), k -> new ArrayList<>()).add(childChunk);
         }
      }

      chunk.content = readContent(root, chunk.id, contentBuffer);
      return chunk;
   }

   private static Object readContent(MagicaVox.Chunk root, String id, InputBuffer buffer) {
      switch (id) {
         case "MAIN":
            return "MAIN";
         case "SIZE":
            MagicaVox.Size size = new MagicaVox.Size();
            size.width = buffer.getInt();
            size.depth = buffer.getInt();
            size.height = buffer.getInt();
            return size;
         case "XYZI":
            if (root.children.get(MagicaVox.Size.class) == null) {
               throw new IllegalStateException("Missing required VOX chunk: SIZE");
            }
            MagicaVox.Voxels voxels = new MagicaVox.Voxels();
            voxels.size = (MagicaVox.Size) root.children.get(MagicaVox.Size.class).get(0).content;
            voxels.voxels = new byte[voxels.size.width * voxels.size.height * voxels.size.depth];
            int numVoxels = buffer.getInt();
            for (int i = 0; i < numVoxels; i++) {
               int x = buffer.get() & 0xFF;
               int y = buffer.get() & 0xFF;
               int z = buffer.get() & 0xFF;
               int colorIndex = buffer.get() & 0xFF;
               voxels.set(x, z, y, colorIndex);
            }
            if (buffer.isAvailable()) {
               throw new IllegalStateException("Buffer still has data after reading all voxels");
            }
            return voxels;
         case "RGBA":
            MagicaVox.Palette palette = new MagicaVox.Palette();
            palette.colors = new int[buffer.available() / 4];
            buffer.getInt(palette.colors);
            return palette;
         case "nTRN":
         case "nGRP":
         case "nSHP":
         case "LAYR":
         case "MATL":
         case "rOBJ":
         case "rCAM":
         case "NOTE":
            return null;
         default:
            throw new IllegalStateException("Unknown chunk id: " + id);
      }
   }

   private static String readString(InputBuffer buffer, int length) {
      byte[] content = new byte[length];

      for (int i = 0; i < content.length; i++) {
         content[i] = buffer.get();
      }

      return new String(content);
   }
}
