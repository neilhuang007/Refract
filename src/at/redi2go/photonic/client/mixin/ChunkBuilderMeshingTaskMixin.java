package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.BlockRendererExt;
import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.config.PhotonicsConfig;
import at.redi2go.photonic.client.rendering.world.PBlock;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import com.llamalad7.mixinextras.sugar.Local;
import net.caffeinemc.mods.sodium.client.render.chunk.compile.ChunkBuildContext;
import net.caffeinemc.mods.sodium.client.render.chunk.compile.ChunkBuildOutput;
import net.caffeinemc.mods.sodium.client.render.chunk.compile.pipeline.BlockRenderCache;
import net.caffeinemc.mods.sodium.client.render.chunk.compile.tasks.ChunkBuilderMeshingTask;
import net.caffeinemc.mods.sodium.client.util.task.CancellationToken;
import net.minecraft.client.render.model.BakedModel;
import net.minecraft.block.BlockState;
import net.minecraft.block.Blocks;
import net.minecraft.util.math.BlockPos;
import net.minecraft.block.BlockRenderType;
import net.minecraft.util.math.BlockPos.Mutable;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.Redirect;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(ChunkBuilderMeshingTask.class)
public class ChunkBuilderMeshingTaskMixin {
   @Inject(
      method = "execute(Lnet/caffeinemc/mods/sodium/client/render/chunk/compile/ChunkBuildContext;Lnet/caffeinemc/mods/sodium/client/util/task/CancellationToken;)Lnet/caffeinemc/mods/sodium/client/render/chunk/compile/ChunkBuildOutput;",
      at = @At("TAIL"),
      remap = false
   )
   public void execute(
      ChunkBuildContext buildContext,
      CancellationToken cancellationToken,
      CallbackInfoReturnable<ChunkBuildOutput> cir,
      @Local(ordinal = 0) int minX,
      @Local(ordinal = 1) int minY,
      @Local(ordinal = 2) int minZ,
      @Local(ordinal = 3) int maxX,
      @Local(ordinal = 4) int maxY,
      @Local(ordinal = 5) int maxZ
   ) {
      if (!Raytracer.isDisabled()) {
         BlockPos lowerCorner = new BlockPos(minX, minY, minZ);
         BlockPos upperCorner = new BlockPos(maxX, maxY, maxZ);
         Raytracer.INSTANCE
            .getWorldRegistry()
            .queueChunkLoad(new PChunkPos(
               Math.floorDiv(lowerCorner.getX(), 16),
               Math.floorDiv(lowerCorner.getY(), 16),
               Math.floorDiv(lowerCorner.getZ(), 16)
            ));

         Raytracer.INSTANCE.getWorldRegistry().wakeUpWorldBuilder();
      }
   }

   @Redirect(
      method = "execute(Lnet/caffeinemc/mods/sodium/client/render/chunk/compile/ChunkBuildContext;Lnet/caffeinemc/mods/sodium/client/util/task/CancellationToken;)Lnet/caffeinemc/mods/sodium/client/render/chunk/compile/ChunkBuildOutput;",
      at = @At(value = "INVOKE", target = "Lnet/minecraft/block/BlockState;hasBlockEntity()Z", remap = true),
      remap = false
   )
   public boolean hasBlockEntity(BlockState instance) {
      return !Raytracer.isDisabled() && PhotonicsConfig.isVoxelized(instance.getBlock()) ? false : instance.hasBlockEntity();
   }

   @Redirect(
      method = "execute(Lnet/caffeinemc/mods/sodium/client/render/chunk/compile/ChunkBuildContext;Lnet/caffeinemc/mods/sodium/client/util/task/CancellationToken;)Lnet/caffeinemc/mods/sodium/client/render/chunk/compile/ChunkBuildOutput;",
      at = @At(value = "INVOKE", target = "Lnet/minecraft/block/BlockState;getRenderType()Lnet/minecraft/block/BlockRenderType;", remap = true),
      remap = false
   )
   public BlockRenderType getRenderShape(
      BlockState instance, @Local BlockRenderCache cache, @Local(ordinal = 0) Mutable blockPos, @Local(ordinal = 1) Mutable modelOffset
   ) {
      if (!Raytracer.isDisabled() && PhotonicsConfig.isVoxelized(instance.getBlock())) {
         PBlock block = Raytracer.INSTANCE.getBlockRegistry().getBlock(instance);
         BlockState blockState = block != null && block.canOcclude ? Blocks.STONE.getDefaultState() : Blocks.GLASS.getDefaultState();
         BakedModel model = cache.getBlockModels().getModelManager().getMissingModel();
         ((BlockRendererExt)cache.getBlockRenderer()).photonic$setRenderingVoxelBlock(true);
         cache.getBlockRenderer().renderModel(model, blockState, blockPos, modelOffset);
         ((BlockRendererExt)cache.getBlockRenderer()).photonic$setRenderingVoxelBlock(false);
         return BlockRenderType.INVISIBLE;
      } else {
         return instance.getRenderType();
      }
   }
}
