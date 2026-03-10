package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.config.lights.BlockLightInfo;
import org.joml.Vector3f;

public class LightInvalidation {
   public final Vector3f pos;
   public BlockLightInfo before;
   public BlockLightInfo after;
   public int beforeIndex;
   public int afterIndex;

   public LightInvalidation(Vector3f pos) {
      this.pos = pos;
   }
}
