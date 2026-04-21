package at.redi2go.photonic.client.config.lights;

import at.redi2go.photonic.client.config.lights.color.LightColor;
import at.redi2go.photonic.client.config.lights.predicate.LightPredicate;
import at.redi2go.photonic.client.config.lights.orientation.LightOrientation;
import java.util.Objects;
import net.minecraft.block.Block;
import net.minecraft.block.pattern.CachedBlockPosition;
import net.minecraft.util.math.BlockPos;
import net.minecraft.world.WorldView;
import org.joml.Vector2f;
import org.joml.Vector3f;

public final class BlockLightInfo implements Comparable<BlockLightInfo> {
   private static final float FOUR_PI = (float) (Math.PI * 4.0);
   private final LightPredicate predicate;
   private final LightColor color;
   private final float intensity;
   private final float radius;
   private final float falloff;
   private final boolean isTraced;
   private final boolean requestedTrace;
   private final float adjustedIntensity;
   private final float luminanceDotColor;
   private final float radiusRcp;
   private final float blockRadius;
   private final Vector3f rawColor;
   private final Vector3f emissionAxis;
   private final float orientationSpread;
   private final float emissionSpread;
   private final float sourcePower;

   public BlockLightInfo(LightPredicate predicate, LightColor color, float intensity, float radius, float falloff, boolean isTraced, boolean requestedTrace, LightOrientation orientation) {
      Objects.requireNonNull(predicate, "predicate was null");
      Objects.requireNonNull(color, "color was null");
      this.predicate = predicate;
      this.color = color;
      this.intensity = intensity;
      this.radius = radius;
      this.falloff = falloff;
      this.isTraced = isTraced;
      this.requestedTrace = requestedTrace;
      this.rawColor = color.toVec3f();
      LightOrientation resolvedOrientation = orientation == null ? LightOrientation.OMNI : orientation;
      this.emissionAxis = resolvedOrientation.axis();
      this.orientationSpread = resolvedOrientation.orientationSpread();
      this.emissionSpread = resolvedOrientation.emissionSpread();
      this.adjustedIntensity = intensity / 100.0F;
      this.luminanceDotColor = this.rawColor.dot(0.2126F, 0.7152F, 0.0722F) * this.adjustedIntensity;
      this.radiusRcp = 1.0F / radius;
      float radiusSquared = Math.max((this.luminanceDotColor / 0.001F - 0.9F) / this.radiusRcp / falloff, 0.0F);
      this.blockRadius = (float) Math.sqrt(radiusSquared);
      this.sourcePower = computeSourcePower(
         this.luminanceDotColor,
         this.radius,
         this.falloff,
         this.orientationSpread + this.emissionSpread
      );
   }

   public Block block() {
      return this.predicate.block();
   }

   public float intensity() {
      return this.intensity;
   }

   public float radius() {
      return this.radius;
   }

   public float falloff() {
      return this.falloff;
   }

   public boolean isTraced() {
      return this.isTraced;
   }

   public boolean requestedTrace() {
      return this.requestedTrace;
   }

   public float radiusInBlocks() {
      return this.blockRadius;
   }

   public boolean emitsLight(BlockPos pos, WorldView level) {
      return this.predicate.test(new CachedBlockPosition(level, pos, false));
   }

   public float luminanceFrom(Vector3f lightPosition, Vector3f samplePosition) {
      float dx = samplePosition.x - lightPosition.x;
      float dy = samplePosition.y - lightPosition.y;
      float dz = samplePosition.z - lightPosition.z;
      float distanceSquared = (dx * dx + dy * dy + dz * dz) * this.falloff;
      return this.luminanceDotColor / (0.9F + distanceSquared * this.radiusRcp);
   }

   public float adjustedIntensity() {
      return this.adjustedIntensity;
   }

   public float sourcePower() {
      return this.sourcePower;
   }

   public Vector3f getRawColorAsVector() {
      return new Vector3f(this.rawColor);
   }

   public Vector3f getColorAsVector() {
      return new Vector3f(this.rawColor).mul(this.adjustedIntensity);
   }

   public Vector2f getAttenuationAsVector() {
      return new Vector2f(0.9F, this.radiusRcp);
   }

   public Vector3f emissionAxis() {
      return new Vector3f(this.emissionAxis);
   }

   public float orientationSpread() {
      return this.orientationSpread;
   }

   public float emissionSpread() {
      return this.emissionSpread;
   }

   private static float computeSourcePower(float luminanceDotColor, float radius, float falloff, float spread) {
      if (luminanceDotColor <= 0.0F || radius <= 0.0F || falloff <= 1.0e-6F) {
         return 0.0F;
      }

      // Match RTXDI's local-light PDF semantics: the presampling texture stores a per-light
      // power/flux term rather than a receiver-space evaluation. The shader attenuation model is
      // asymptotically color*intensity*(radius/falloff)/distance^2, so the equivalent isotropic
      // flux term is luminance(color*intensity) * radius / falloff.
      float fluxLuminance = luminanceDotColor * radius / falloff;
      return FOUR_PI * fluxLuminance * computeEmissionFluxFactor(spread);
   }

   private static float computeEmissionFluxFactor(float spread) {
      float clampedSpread = Math.max(0.0F, Math.min(spread, (float) Math.PI));
      if (clampedSpread >= Math.PI) {
         return 1.0F;
      }

      float sinSpread = (float) Math.sin(clampedSpread);
      float cosSpread = (float) Math.cos(clampedSpread);
      if (clampedSpread <= (float) (Math.PI * 0.5)) {
         return 0.5F - 0.25F * cosSpread + (float) (Math.PI * 0.125) * sinSpread;
      }

      return 0.5F * (1.0F - cosSpread) + 0.25F * sinSpread * ((float) Math.PI - clampedSpread);
   }


   public int compareTo(BlockLightInfo o) {
      return this.predicate.compareTo(o.predicate);
   }

   @Override
   public String toString() {
      return "BlockLightInfo{predicate=" + this.predicate + ", color=" + this.color + ", intensity=" + this.intensity
         + ", radius=" + this.radius + ", falloff=" + this.falloff + ", isTraced=" + this.isTraced
         + ", requestedTrace=" + this.requestedTrace + "}";
   }
}
