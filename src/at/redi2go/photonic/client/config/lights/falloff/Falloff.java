package at.redi2go.photonic.client.config.lights.falloff;

public record Falloff(float value) implements LightFalloff {
   @Override
   public float get() { return this.value; }
}
