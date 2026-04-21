package at.redi2go.photonic.client.rendering.world;

public abstract class PaletteEntry implements Comparable<PaletteEntry> {
   protected short usages = 0;
   protected short presentFaces = -1;
   protected final TextureData[] faces = new TextureData[6];
   protected long hashCode = 0L;
   protected boolean hasTransparent = false;

   protected void copyFrom(PaletteEntry other) {
      this.presentFaces = other.presentFaces;
      System.arraycopy(other.faces, 0, this.faces, 0, this.faces.length);
      this.hasTransparent = other.hasTransparent;
      this.computeHashCode();
   }

   protected void computeHashCode() {
      this.presentFaces = 0;
      this.hashCode = 0L;
      for (int i = 0; i < this.faces.length; i++) {
         TextureData face = this.faces[i];
         if (face == null) {
            this.hashCode *= 31L;
         } else {
            this.presentFaces = (short)(this.presentFaces | 1 << i);
            this.hashCode = 31L * this.hashCode + face.hashCode();
         }
      }
   }

   public int usages() {
      return this.usages;
   }

   public boolean hasTransparentFace() {
      return this.hasTransparent;
   }

   public boolean hasMissingFace() {
      return this.presentFaces != 63;
   }

   public boolean hasFace(int face) {
      return ((this.presentFaces >> face) & 1) == 1;
   }

   public TextureData getFace(int face) {
      return this.faces[face];
   }

   @Override
   public int hashCode() {
      return Long.hashCode(this.hashCode);
   }

   @Override
   public boolean equals(Object obj) {
      return obj instanceof PaletteEntry other && this.hashCode == other.hashCode;
   }

   @Override
   public int compareTo(PaletteEntry other) {
      return Integer.compare(this.usages, other.usages);
   }
}
