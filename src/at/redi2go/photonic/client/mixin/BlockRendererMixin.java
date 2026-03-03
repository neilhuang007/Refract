package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.BlockRendererExt;
import at.redi2go.photonic.client.Raytracer;
import net.caffeinemc.mods.sodium.client.render.chunk.compile.ChunkBuildBuffers;
import net.caffeinemc.mods.sodium.client.render.chunk.compile.buffers.ChunkModelBuilder;
import net.caffeinemc.mods.sodium.client.render.chunk.compile.pipeline.BlockRenderer;
import net.caffeinemc.mods.sodium.client.render.chunk.terrain.TerrainRenderPass;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;

@Mixin(value = BlockRenderer.class, remap = false)
public class BlockRendererMixin implements BlockRendererExt {
   @Unique
   private boolean renderingVoxelBlock = false;

   @Redirect(
      method = "bufferQuad",
      at = @At(
         value = "INVOKE",
         target = "Lnet/caffeinemc/mods/sodium/client/render/chunk/compile/ChunkBuildBuffers;get(Lnet/caffeinemc/mods/sodium/client/render/chunk/terrain/TerrainRenderPass;)Lnet/caffeinemc/mods/sodium/client/render/chunk/compile/buffers/ChunkModelBuilder;"
      )
   )
   public ChunkModelBuilder get(ChunkBuildBuffers instance, TerrainRenderPass pass) {
      return !this.renderingVoxelBlock ? instance.get(pass) : instance.get(Raytracer.VOXEL);
   }

   @Override
   public boolean photonic$isRenderingVoxelBlock() {
      return this.renderingVoxelBlock;
   }

   @Override
   public void photonic$setRenderingVoxelBlock(boolean renderingVoxelBlock) {
      this.renderingVoxelBlock = renderingVoxelBlock;
   }
}
