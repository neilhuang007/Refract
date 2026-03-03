package at.redi2go.photonic.client.rendering.opengl.objects;

public enum GlTarget {
   SSBO(37074),
   UBO(35345);

   public final int target;

   private GlTarget(int target) {
      this.target = target;
   }
}
