package at.redi2go.photonic.client.rendering.world;

import java.util.Objects;
import org.joml.Vector3f;

public class LightInstance {
   private final Vector3f position;
   private final LightType type;

   public LightInstance(Vector3f position, LightType type) {
      this.position = position;
      this.type = type;
   }

   public Vector3f getPosition() {
      return this.position;
   }

   public LightType getType() {
      return this.type;
   }

   @Override
   public boolean equals(Object object) {
      if (this == object) {
         return true;
      } else {
         return !(object instanceof LightInstance that) ? false : Objects.equals(this.position, that.position) && Objects.equals(this.type, that.type);
      }
   }

   @Override
   public int hashCode() {
      return Objects.hash(this.position, this.type);
   }
}
