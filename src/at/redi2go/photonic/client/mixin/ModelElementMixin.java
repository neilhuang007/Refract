package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.Raytracer;
import java.util.Map;
import net.minecraft.util.math.Direction;
import net.minecraft.client.render.model.json.ModelElementFace;
import net.minecraft.client.render.model.json.ModelElement;
import net.minecraft.client.render.model.json.ModelRotation;
import org.joml.Vector3f;
import org.spongepowered.asm.mixin.Final;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Mutable;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(ModelElement.class)
public class ModelElementMixin {
   @Mutable
   @Final
   @Shadow
   public Map<Direction, ModelElementFace> faces;

   @Inject(method = "<init>", at = @At("TAIL"))
   private void init(Vector3f from, Vector3f to, Map<Direction, ModelElementFace> faces, ModelRotation blockElementRotation, boolean bl, CallbackInfo ci) {
      Raytracer.filterDoubleFaces(faces, new Vector3f(from.x, from.y, from.z), new Vector3f(to.x, to.y, to.z));
   }
}
