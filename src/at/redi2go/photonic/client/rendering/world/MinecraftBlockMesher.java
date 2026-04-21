package at.redi2go.photonic.client.rendering.world;

import at.redi2go.photonic.client.rendering.util.IrisUtil;
import at.redi2go.photonics.api.mc.Id;
import at.redi2go.photonics.api.mc.core.IBlockPos;
import at.redi2go.photonics.api.mc.world.level.IBlockAndTintGetter;
import at.redi2go.photonics.api.mc.world.level.IBlockState;
import at.redi2go.photonics.core.rendering.world.WorldOrigin;
import at.redi2go.photonics.core.rendering.world.bakery.BlockMesher;
import at.redi2go.photonics.core.rendering.world.bakery.VertexBuilder;
import net.minecraft.block.BlockRenderType;
import net.minecraft.block.BlockState;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.render.VertexConsumer;
import net.minecraft.client.render.block.BlockRenderManager;
import net.minecraft.client.texture.SpriteAtlasTexture;
import net.minecraft.client.util.math.MatrixStack;
import net.minecraft.fluid.FluidState;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.random.Random;
import net.minecraft.world.BlockRenderView;

public class MinecraftBlockMesher implements BlockMesher {
   private final ThreadLocal<Renderer> renderer = ThreadLocal.withInitial(Renderer::new);

   @Override
   public void meshBlock(
      WorldOrigin origin,
      IBlockPos pos,
      IBlockState blockState,
      IBlockAndTintGetter blockAndTintGetter,
      VertexBuilder vertexBuilder
   ) {
      meshBlock(
         origin,
         (BlockPos)(Object)pos,
         (BlockState)(Object)blockState,
         (BlockRenderView)(Object)blockAndTintGetter,
         vertexBuilder
      );
   }

   private void meshBlock(
      WorldOrigin origin,
      BlockPos pos,
      BlockState blockState,
      BlockRenderView blockRenderView,
      VertexBuilder builder
   ) {
      Renderer renderer = this.renderer.get();
      builder.useBlockId(IrisUtil.getBlockId(blockState));

      FluidState fluidState = blockState.getFluidState();
      if (!fluidState.isEmpty()) {
         renderer.submitFluid(origin, pos, blockRenderView, builder, blockState, fluidState);
      }

      if (blockState.getRenderType() == BlockRenderType.MODEL) {
         renderer.submitBlock(origin, pos, blockState, blockRenderView, builder);
      }
   }

   private static final class Renderer {
      private static final Id BLOCK_ATLAS = (Id)(Object)SpriteAtlasTexture.BLOCK_ATLAS_TEXTURE;

      private final Random random = Random.create();
      private final BlockRenderManager blockRenderer = MinecraftClient.getInstance().getBlockRenderManager();
      private final MatrixStack matrices = new MatrixStack();

      private void submitFluid(
         WorldOrigin origin,
         BlockPos blockPos,
         BlockRenderView blockRenderView,
         VertexBuilder builder,
         BlockState blockState,
         FluidState fluidState
      ) {
         builder.useAtlas(BLOCK_ATLAS);
         builder.setOffset(origin.applyOffset(IBlockPos.of(
            blockPos.getX() - (blockPos.getX() & 15),
            blockPos.getY() - (blockPos.getY() & 15),
            blockPos.getZ() - (blockPos.getZ() & 15)
         )));

         blockRenderer.renderFluid(blockPos, blockRenderView, (VertexConsumer)builder, blockState, fluidState);
      }

      private void submitBlock(
         WorldOrigin origin,
         BlockPos pos,
         BlockState blockState,
         BlockRenderView blockRenderView,
         VertexBuilder builder
      ) {
         builder.useAtlas(BLOCK_ATLAS);
         builder.setOffset(origin.applyOffset((IBlockPos)(Object)pos));

         matrices.push();
         random.setSeed(blockState.getRenderingSeed(pos));
         blockRenderer.renderBlock(blockState, pos, blockRenderView, matrices, (VertexConsumer)builder, false, random);
         matrices.pop();
      }
   }
}
