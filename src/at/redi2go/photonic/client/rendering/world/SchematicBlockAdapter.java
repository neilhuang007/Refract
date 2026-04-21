package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.schematics.AirEntry;
import at.redi2go.photonic.client.rendering.schematics.Schematic;
import java.util.Arrays;

public final class SchematicBlockAdapter {
   private static final int[] FACE_DX = {1, -1, 0, 0, 0, 0};
   private static final int[] FACE_DY = {0, 0, 1, -1, 0, 0};
   private static final int[] FACE_DZ = {0, 0, 0, 0, 1, -1};
   private static final int FACE_COUNT = 6;

   private SchematicBlockAdapter() {
   }

   public static AdaptedBlock adapt(Schematic schematic, int blockId) {
      MutablePaletteEntry[] voxels = new MutablePaletteEntry[schematic.getData().length];
      PaletteBuilder paletteBuilder = new PaletteBuilder();
      int occupiedVoxelCount = 0;
      for (int x = 0; x < schematic.getWidth(); x++) {
         for (int y = 0; y < schematic.getHeight(); y++) {
            for (int z = 0; z < schematic.getDepth(); z++) {
               int entry = schematic.getUncheckedEntry(x, y, z);
               if (!isOccupied(entry)) {
                  continue;
               }

               MutablePaletteEntry paletteEntry = new MutablePaletteEntry();
               TextureData textureData = new TextureData(blockId, normalizeColor(entry));
               for (int face = 0; face < FACE_COUNT; face++) {
                  int nx = x + FACE_DX[face];
                  int ny = y + FACE_DY[face];
                  int nz = z + FACE_DZ[face];
                  if (!schematic.isInBounds(nx, ny, nz) || !isOccupied(schematic.getUncheckedEntry(nx, ny, nz))) {
                     paletteEntry.update(face, textureData);
                  }
               }

               if (paletteEntry.hasMissingFace() && paletteEntry.usages() == 0 && !hasAnyFace(paletteEntry)) {
                  continue;
               }

               paletteBuilder.add(paletteEntry);
               voxels[Schematic.toSchematicIndex(x, y, z)] = paletteEntry;
               occupiedVoxelCount++;
            }
         }
      }
      BlockPalette palette = paletteBuilder.build();
      return new AdaptedBlock(voxels, palette, occupiedVoxelCount);
   }

   private static boolean hasAnyFace(MutablePaletteEntry entry) {
      for (int i = 0; i < FACE_COUNT; i++) {
         if (entry.hasFace(i)) {
            return true;
         }
      }
      return false;
   }

   private static boolean isOccupied(int entry) {
      return entry != 0 && !AirEntry.isAirEntry(entry);
   }

   private static int normalizeColor(int entry) {
      if (entry < 0) {
         entry = AirEntry.fromData(entry);
      }
      int alpha = entry >>> 24;
      if (alpha == 0 && (entry & 0x00FFFFFF) != 0) {
         alpha = 255;
      }
      return (entry & 0x00FFFFFF) | (alpha << 24);
   }

   public record AdaptedBlock(MutablePaletteEntry[] voxels, BlockPalette palette, int occupiedVoxelCount) {
      public AdaptedBlock {
         voxels = Arrays.copyOf(voxels, voxels.length);
      }

      public int paletteIndexAt(int x, int y, int z) {
         return this.palette.getIndex(this.voxels[Schematic.toSchematicIndex(x, y, z)]);
      }
   }
}
