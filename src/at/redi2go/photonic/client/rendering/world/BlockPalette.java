package at.redi2go.photonic.client.rendering.world;

import it.unimi.dsi.fastutil.objects.Object2ObjectMap;
import java.util.AbstractList;
import java.util.List;

public class BlockPalette extends AbstractList<PaletteEntry> {
   private final Object2ObjectMap<MutablePaletteEntry, MutablePaletteEntry> mapping;
   private final List<? extends PaletteEntry> entries;

   public BlockPalette(Object2ObjectMap<MutablePaletteEntry, MutablePaletteEntry> mapping, List<? extends PaletteEntry> entries) {
      this.mapping = mapping;
      this.entries = entries;
   }

   public int getIndex(MutablePaletteEntry entry) {
      return entry == null ? 0 : this.mapping.get(entry).index + 1;
   }

   @Override
   public int size() {
      return this.entries.size();
   }

   @Override
   public PaletteEntry get(int index) {
      return this.entries.get(index);
   }
}
