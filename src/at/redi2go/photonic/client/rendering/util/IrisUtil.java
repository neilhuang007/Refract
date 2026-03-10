package at.redi2go.photonic.client.rendering.util;

import it.unimi.dsi.fastutil.objects.Object2IntMap;
import net.irisshaders.iris.shaderpack.materialmap.WorldRenderingSettings;
import net.minecraft.block.BlockState;

public class IrisUtil {
   public static int getBlockId(BlockState blockState) {
      Object2IntMap<BlockState> blockIds = WorldRenderingSettings.INSTANCE.getBlockStateIds();
      return blockIds == null ? -1 : blockIds.getOrDefault(blockState, -1);
   }
}
