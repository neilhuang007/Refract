package at.redi2go.photonic.client.config.lights.intensity;

public record Intensity(float value) implements LightIntensity {
   @Override
   public float get() { return this.value; }
}
