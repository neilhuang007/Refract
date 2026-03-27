package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.config.lights.BlockLightInfo;
import java.util.Objects;
import org.joml.Vector3f;

public final class LightInstance {
   private final int blockId;
   private final Vector3f position;
   private final BlockLightInfo type;
   private final boolean active;
   private int index = -1;

   public LightInstance(int blockId, Vector3f position, BlockLightInfo type) {
      this(blockId, position, type, true);
   }

   public LightInstance(int blockId, Vector3f position, BlockLightInfo type, boolean active) {
      this.blockId = blockId;
      this.position = position;
      this.type = type;
      this.active = active;
   }

   public int blockId() {
      return this.blockId;
   }

   public Vector3f position() {
      return this.position;
   }

   public BlockLightInfo type() {
      return this.type;
   }

   public boolean active() {
      return this.active;
   }

   public int index() {
      return this.index;
   }

   public void setIndex(int index) {
      this.index = index;
   }

   @Override
   public boolean equals(Object obj) {
      if (obj == this) {
         return true;
      } else if (obj != null && obj.getClass() == this.getClass()) {
         LightInstance that = (LightInstance) obj;
         return Objects.equals(this.position, that.position) && Objects.equals(this.type, that.type);
      } else {
         return false;
      }
   }

   @Override
   public int hashCode() {
      return Objects.hash(this.position, this.type);
   }

   @Override
   public String toString() {
      return "LightInstance[position=" + this.position + ", type=" + this.type + ", active=" + this.active + "]";
   }
}
