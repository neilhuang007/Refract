package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.config.lights.BlockLightInfo;

public record TracedLightPosition(int blockId, BlockLightInfo lightInfo, long semanticHash, boolean active) {
   public TracedLightPosition(int blockId, BlockLightInfo lightInfo) {
      this(blockId, lightInfo, true);
   }

   public TracedLightPosition(int blockId, BlockLightInfo lightInfo, boolean active) {
      this(blockId, lightInfo, LightRegistry.semanticLightDescriptorHash(lightInfo), active);
   }

   public TracedLightPosition withActive(boolean active) {
      return this.active == active ? this : new TracedLightPosition(this.blockId, this.lightInfo, this.semanticHash, active);
   }
}
