package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.BlockRendererExt;
import at.redi2go.photonic.client.PhotonicsStorage;
import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.rendering.world.LightRegistry;
import at.redi2go.photonic.client.rendering.world.position.PChunkPos;
import com.llamalad7.mixinextras.sugar.Local;
import net.caffeinemc.mods.sodium.client.render.chunk.compile.ChunkBuildContext;
import net.caffeinemc.mods.sodium.client.render.chunk.compile.ChunkBuildOutput;
import net.caffeinemc.mods.sodium.client.render.chunk.compile.pipeline.BlockRenderCache;
import net.caffeinemc.mods.sodium.client.render.chunk.compile.tasks.ChunkBuilderMeshingTask;
import net.caffeinemc.mods.sodium.client.util.task.CancellationToken;
import net.minecraft.client.render.model.BakedModel;
import net.minecraft.util.math.BlockPos;
import net.minecraft.block.BlockRenderType;
import net.minecraft.block.BlockState;
import net.minecraft.util.math.BlockPos.Mutable;
import org.joml.Vector3f;
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
            .queueBuildJob(
               () -> Raytracer.INSTANCE
                  .getWorldRegistry()
                  .loadChunk(new PChunkPos(lowerCorner.getX() / 16, lowerCorner.getY() / 16, lowerCorner.getZ() / 16))
            );
         Raytracer.INSTANCE.getWorldRegistry().wakeUpWorldBuilder();
         LightRegistry lightRegistry = Raytracer.INSTANCE.getWorldRegistry().getLightRegistry();

         for (BlockPos blockPos : BlockPos.iterate(lowerCorner, upperCorner)) {
            lightRegistry.onBlockLoad(new Vector3f(blockPos.getX(), blockPos.getY(), blockPos.getZ()));
         }
      }
   }

   @Redirect(
      method = "execute(Lnet/caffeinemc/mods/sodium/client/render/chunk/compile/ChunkBuildContext;Lnet/caffeinemc/mods/sodium/client/util/task/CancellationToken;)Lnet/caffeinemc/mods/sodium/client/render/chunk/compile/ChunkBuildOutput;",
      at = @At(value = "INVOKE", target = "Lnet/minecraft/world/level/block/state/BlockState;hasBlockEntity()Z")
   )
   public boolean hasBlockEntity(BlockState instance) {
      return !Raytracer.isDisabled() && PhotonicsStorage.VOLUMETRIC_RENDERED_BLOCKS.value.contains(instance.getBlock()) ? false : instance.hasBlockEntity();
   }

   @Redirect(
      method = "execute(Lnet/caffeinemc/mods/sodium/client/render/chunk/compile/ChunkBuildContext;Lnet/caffeinemc/mods/sodium/client/util/task/CancellationToken;)Lnet/caffeinemc/mods/sodium/client/render/chunk/compile/ChunkBuildOutput;",
      at = @At(value = "INVOKE", target = "Lnet/minecraft/world/level/block/state/BlockState;getRenderShape()Lnet/minecraft/world/level/block/RenderShape;")
   )
   public BlockRenderType getRenderShape(
      BlockState instance, @Local BlockRenderCache cache, @Local(ordinal = 0) Mutable blockPos, @Local(ordinal = 1) Mutable modelOffset
   ) {
      if (!Raytracer.isDisabled() && PhotonicsStorage.VOLUMETRIC_RENDERED_BLOCKS.value.contains(instance.getBlock())) {
         BakedModel model = cache.getBlockModels().getModel(instance);
         ((BlockRendererExt)cache.getBlockRenderer()).photonic$setRenderingVoxelBlock(true);
         cache.getBlockRenderer().renderModel(model, instance, blockPos, modelOffset);
         ((BlockRendererExt)cache.getBlockRenderer()).photonic$setRenderingVoxelBlock(false);
         return BlockRenderType.INVISIBLE;
      } else {
         return instance.getRenderType();
      }
   }
}
