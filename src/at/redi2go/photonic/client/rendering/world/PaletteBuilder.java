package at.redi2go.photonic.client.rendering.world;

import it.unimi.dsi.fastutil.objects.Object2ObjectMap;
import it.unimi.dsi.fastutil.objects.Object2ObjectOpenHashMap;
import it.unimi.dsi.fastutil.objects.ObjectOpenHashSet;
import it.unimi.dsi.fastutil.objects.ObjectRBTreeSet;
import it.unimi.dsi.fastutil.objects.ObjectSet;
import java.util.ArrayList;
import java.util.Arrays;

public class PaletteBuilder {
   private final Object2ObjectMap<MutablePaletteEntry, MutablePaletteEntry> intern = new Object2ObjectOpenHashMap<>();
   private MutablePaletteEntry[] sortedEntries;
   @SuppressWarnings("unchecked")
   private final ObjectSet<MutablePaletteEntry>[] missingFaces = new ObjectSet[6];

   private void addMissingFaces(MutablePaletteEntry data) {
      for (int i = 0; i < 6; i++) {
         if (data.hasFace(i)) {
            continue;
         }

         ObjectSet<MutablePaletteEntry> set = this.missingFaces[i];
         if (set == null) {
            set = new ObjectRBTreeSet<>();
            this.missingFaces[i] = set;
         }
         set.add(data);
      }
   }

   public void add(MutablePaletteEntry data) {
      data.computeHashCode();
      this.intern.computeIfAbsent(data, entry -> (MutablePaletteEntry)entry).usages++;
   }

   private void sort() {
      this.sortedEntries = new MutablePaletteEntry[this.intern.size()];
      int i = 0;
      for (MutablePaletteEntry entry : this.intern.values()) {
         this.sortedEntries[i++] = entry;
         this.addMissingFaces(entry);
      }
      Arrays.sort(this.sortedEntries);
   }

   private void merge() {
      this.sort();
      for (MutablePaletteEntry entry : this.sortedEntries) {
         if (!entry.hasMissingFace()) {
            continue;
         }

         boolean merged = false;
         for (int i = 0; i < 6 && !merged; i++) {
            if (entry.hasFace(i)) {
               continue;
            }
            ObjectSet<MutablePaletteEntry> candidates = this.missingFaces[i];
            if (candidates == null) {
               continue;
            }
            for (MutablePaletteEntry candidate : candidates) {
               if (candidate.canMerge(entry)) {
                  candidate.addFaces(entry, this.missingFaces);
                  this.intern.put(entry, candidate);
                  merged = true;
                  break;
               }
            }
         }

         if (!merged) {
            for (int i = 0; i < 6; i++) {
               if (!entry.hasFace(i) && this.missingFaces[i] != null) {
                  this.missingFaces[i].remove(entry);
               }
            }
         }
      }
   }

   public BlockPalette build() {
      this.sort();
      this.merge();
      ObjectOpenHashSet<MutablePaletteEntry> seen = new ObjectOpenHashSet<>();
      ArrayList<MutablePaletteEntry> counts = new ArrayList<>();
      for (MutablePaletteEntry entry : this.intern.values()) {
         if (seen.add(entry)) {
            counts.add(entry);
         }
      }
      counts.sort(MutablePaletteEntry::compareTo);
      for (int i = 0; i < counts.size(); i++) {
         counts.get(i).index = i;
      }
      return new BlockPalette(this.intern, counts);
   }
}
