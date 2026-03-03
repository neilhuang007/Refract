package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.BakedQuadExt;
import at.redi2go.photonic.client.BlockBuilder;
import at.redi2go.photonic.client.Raytracer;
import net.minecraft.world.BlockRenderView;
import net.minecraft.util.math.BlockPos;
import net.minecraft.block.BlockState;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.render.VertexConsumer;
import net.minecraft.client.render.model.BakedQuad;
import net.minecraft.client.render.block.BlockModelRenderer;
import net.minecraft.client.util.math.MatrixStack.Entry;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.Redirect;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(BlockModelRenderer.class)
public class BlockModelRendererMixin {
   @Redirect(method = "tesselateBlock", at = @At(value = "INVOKE", target = "Lnet/minecraft/client/Minecraft;useAmbientOcclusion()Z"))
   public boolean useAmbientOcclusion() {
      return Raytracer.isDisabled() ? MinecraftClient.isAmbientOcclusionEnabled() : false;
   }

   @Inject(method = "putQuadData", at = @At("HEAD"), cancellable = true)
   public void putQuadData(
      BlockRenderView blockAndTintGetter,
      BlockState blockState,
      BlockPos blockPos,
      VertexConsumer vertexConsumer,
      Entry pose,
      BakedQuad bakedQuad,
      float f,
      float g,
      float h,
      float i,
      int j,
      int k,
      int l,
      int m,
      int n,
      CallbackInfo ci
   ) {
      if (BlockBuilder.IS_BUILDING_BLOCK_BUFFER) {
         if (!((BakedQuadExt)bakedQuad).photonic$shouldBeVoxelized()) {
            ci.cancel();
         }
      }
   }
}
