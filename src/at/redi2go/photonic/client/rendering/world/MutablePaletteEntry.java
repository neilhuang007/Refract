package at.redi2go.photonic.client.rendering.world;

import it.unimi.dsi.fastutil.objects.ObjectSet;

public final class MutablePaletteEntry extends PaletteEntry {
   int index = 0;

   public MutablePaletteEntry() {
   }

   public MutablePaletteEntry(PaletteEntry other) {
      this.copyFrom(other);
   }

   public boolean canMerge(MutablePaletteEntry other) {
      return (this.presentFaces & other.presentFaces) == 0;
   }

   public void addFaces(MutablePaletteEntry other, ObjectSet<MutablePaletteEntry>[] missingFaces) {
      for (int i = 0; i < this.faces.length; i++) {
         TextureData face = other.faces[i];
         ObjectSet<MutablePaletteEntry> missingFaceSet = missingFaces[i];
         if (!this.hasFace(i) && missingFaceSet != null) {
            missingFaceSet.remove(this);
         }

         if (face == null) {
            if (missingFaceSet != null) {
               missingFaceSet.remove(other);
            }
            continue;
         }

         this.faces[i] = face;
      }

      this.presentFaces = (short)(this.presentFaces | other.presentFaces);
      this.hasTransparent = this.hasTransparent || other.hasTransparent;
      this.usages += other.usages;
      this.computeHashCode();

      for (int i = 0; i < this.faces.length; i++) {
         if (!this.hasFace(i) && missingFaces[i] != null) {
            missingFaces[i].add(this);
         }
      }
   }

   public boolean update(int normal, TextureData data) {
      TextureData face = this.faces[normal];
      if (face == null || data.gt(face)) {
         this.faces[normal] = data;
         this.hasTransparent = this.hasTransparent || VoxelColor.a(data.color()) != 255;
         this.computeHashCode();
         return true;
      }

      return false;
   }
}
