package at.redi2go.photonic.client.config.lights;

import at.redi2go.photonic.client.config.lights.color.LightColor;
import at.redi2go.photonic.client.config.lights.predicate.LightPredicate;
import java.util.Objects;
import net.minecraft.block.Block;
import net.minecraft.block.pattern.CachedBlockPosition;
import net.minecraft.util.math.BlockPos;
import net.minecraft.world.WorldView;
import org.joml.Vector2f;
import org.joml.Vector3f;

public final class BlockLightInfo implements Comparable<BlockLightInfo> {
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

   public BlockLightInfo(LightPredicate predicate, LightColor color, float intensity, float radius, float falloff, boolean isTraced, boolean requestedTrace) {
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
      this.adjustedIntensity = intensity / 100.0F;
      this.luminanceDotColor = this.rawColor.dot(0.2126F, 0.7152F, 0.0722F) * this.adjustedIntensity;
      this.radiusRcp = 1.0F / radius;
      float radiusSquared = Math.max((this.luminanceDotColor / 0.001F - 0.9F) / this.radiusRcp / falloff, 0.0F);
      this.blockRadius = (float) Math.sqrt(radiusSquared);
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

   public Vector3f getRawColorAsVector() {
      return new Vector3f(this.rawColor);
   }

   public Vector3f getColorAsVector() {
      return new Vector3f(this.rawColor).mul(this.adjustedIntensity);
   }

   public Vector2f getAttenuationAsVector() {
      return new Vector2f(0.9F, this.radiusRcp);
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
