package at.redi2go.photonic.client.rendering.opengl.objects;

public enum BufferType {
   SCHEMATIC(0),
   POINT_LIGHTS(1),
   POINT_LIGHT_STRUCTURE(3),
   EXPOSURE(4),
   TRACE(5);

   public final int binding;

   private BufferType(int binding) {
      this.binding = binding;
   }
}
