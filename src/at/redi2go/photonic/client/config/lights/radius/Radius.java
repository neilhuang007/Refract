package at.redi2go.photonic.client.config.lights.radius;

public record Radius(float value) implements LightRadius {
   @Override
   public float get() { return this.value; }
}
