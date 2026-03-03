package at.redi2go.photonic.client.rendering.world;

import net.minecraft.block.Block;

public class LightBlock {
   public final Block block;
   public LightType lightType;

   public LightBlock(Block block, LightType lightType) {
      this.block = block;
      this.lightType = lightType;
   }
}
