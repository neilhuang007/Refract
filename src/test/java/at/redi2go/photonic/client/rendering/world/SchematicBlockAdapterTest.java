package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.schematics.Schematic;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SchematicBlockAdapterTest {
   @Test
   void adaptsSingleVoxelIntoSinglePaletteEntry() {
      Schematic schematic = new Schematic(16, 16, 16);
      schematic.setEntry(1, 2, 3, 0xFF336699);

      SchematicBlockAdapter.AdaptedBlock adapted = SchematicBlockAdapter.adapt(schematic, 42);

      assertEquals(1, adapted.occupiedVoxelCount());
      assertEquals(1, adapted.palette().size());
      assertEquals(1, adapted.paletteIndexAt(1, 2, 3));
   }

   @Test
   void adaptsNeighborVoxelsWithCompactVisibleFacePalettes() {
      Schematic schematic = new Schematic(16, 16, 16);
      schematic.setEntry(1, 1, 1, 0xFF112233);
      schematic.setEntry(2, 1, 1, 0xFF112233);

      SchematicBlockAdapter.AdaptedBlock adapted = SchematicBlockAdapter.adapt(schematic, 7);

      assertEquals(2, adapted.occupiedVoxelCount());
      assertEquals(2, adapted.palette().size());
      assertTrue(adapted.paletteIndexAt(1, 1, 1) > 0);
      assertTrue(adapted.paletteIndexAt(2, 1, 1) > 0);
   }

   @Test
   void keepsHigherPriorityFaceColorWhenVoxelWordChanges() {
      MutablePaletteEntry entry = new MutablePaletteEntry();
      assertTrue(entry.update(0, new TextureData(1, 0x40101010)));
      assertTrue(entry.update(0, new TextureData(1, 0xFF010101)));
      assertEquals(0xFF010101, entry.getFace(0).color());
   }
}
