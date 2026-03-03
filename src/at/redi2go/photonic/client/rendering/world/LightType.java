package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.Raytracer;
import java.util.Objects;
import net.minecraft.block.BlockState;
import org.joml.Vector2f;
import org.joml.Vector3f;

public class LightType {
   private final Vector3f color;
   private final Vector2f attenuation;
   private final float luminanceDotColor;
   private final boolean traced;

   public LightType(Vector3f color, Vector2f lightFalloff, boolean traced) {
      this.color = color;
      this.attenuation = lightFalloff;
      this.luminanceDotColor = color.dot(new Vector3f(0.2126F, 0.7152F, 0.0722F));
      this.traced = traced;
   }

   public float luminanceFrom(Vector3f lightPosition, Vector3f samplePosition) {
      float dx = samplePosition.x - lightPosition.x;
      float dy = samplePosition.y - lightPosition.y;
      float dz = samplePosition.z - lightPosition.z;
      float distanceSquared = dx * dx + dy * dy + dz * dz;
      return this.luminanceDotColor / (this.attenuation.x + distanceSquared * this.attenuation.y);
   }

   public boolean blockStateEmitsLight(BlockState blockState) {
      return Raytracer.blockStateEmitsLight(blockState);
   }

   public Vector3f getColor() {
      return this.color;
   }

   public Vector2f getAttenuation() {
      return this.attenuation;
   }

   public boolean isTraced() {
      return this.traced;
   }

   @Override
   public boolean equals(Object o) {
      if (this == o) {
         return true;
      } else if (o != null && this.getClass() == o.getClass()) {
         LightType lightType = (LightType)o;
         return Objects.equals(this.color, lightType.color) && Objects.equals(this.attenuation, lightType.attenuation);
      } else {
         return false;
      }
   }

   @Override
   public int hashCode() {
      return Objects.hash(this.color, this.attenuation);
   }
}
