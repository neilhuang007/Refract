package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.BakedQuadExt;
import at.redi2go.photonic.client.BlockElementFaceExt;
import net.minecraft.client.texture.Sprite;
import net.minecraft.util.math.Direction;
import net.minecraft.client.render.model.ModelBakeSettings;
import net.minecraft.client.render.model.BakedQuad;
import net.minecraft.client.render.model.json.ModelElementFace;
import net.minecraft.client.render.model.json.ModelRotation;
import net.minecraft.client.render.model.BakedQuadFactory;
import org.joml.Vector3f;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(BakedQuadFactory.class)
public class FaceBakeryMixin {
   @Inject(method = "bakeQuad", at = @At("RETURN"))
   private static void bakeQuad(
      Vector3f vector3f,
      Vector3f vector3f2,
      ModelElementFace blockElementFace,
      Sprite textureAtlasSprite,
      Direction direction,
      ModelBakeSettings modelState,
      ModelRotation blockElementRotation,
      boolean bl,
      CallbackInfoReturnable<BakedQuad> cir
   ) {
      BakedQuad bakedQuad = (BakedQuad)cir.getReturnValue();
      boolean shouldBeVoxelized = ((BlockElementFaceExt)(Object)blockElementFace).photonic$shouldBeVoxelized();
      ((BakedQuadExt)bakedQuad).photonic$setShouldBeVoxelized(shouldBeVoxelized);
   }
}
