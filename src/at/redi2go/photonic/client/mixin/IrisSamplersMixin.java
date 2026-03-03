package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.rendering.opengl.objects.TextureObject;
import at.redi2go.photonic.client.rendering.opengl.rendering.ColorFramebuffer;
import it.unimi.dsi.fastutil.objects.Object2ObjectMap;
import java.util.function.Supplier;
import net.irisshaders.iris.gl.sampler.SamplerHolder;
import net.irisshaders.iris.gl.texture.TextureAccess;
import net.irisshaders.iris.samplers.IrisSamplers;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(value = IrisSamplers.class, remap = false)
public abstract class IrisSamplersMixin {
   @Inject(method = "addCustomTextures", at = @At("TAIL"))
   private static void addCustomTexture(SamplerHolder samplers, Object2ObjectMap<String, TextureAccess> irisCustomTextures, CallbackInfo ci) {
      if (Raytracer.shouldBeEnabled()) {
         Supplier<ColorFramebuffer> lightBuffer = () -> Raytracer.INSTANCE.getMainRenderer().getLightBuffer();
         addTextureSampler(samplers, "radiosity_position", () -> lightBuffer.get().getWriteAttachment("position"));
         addTextureSampler(samplers, "radiosity_normal", () -> lightBuffer.get().getWriteAttachment("normal"));
         addTextureSampler(samplers, "radiosity_direct", () -> lightBuffer.get().getWriteAttachment("direct"));
         addTextureSampler(samplers, "radiosity_direct_soft", () -> lightBuffer.get().getWriteAttachment("direct_soft"));
         addTextureSampler(samplers, "radiosity_handheld", () -> lightBuffer.get().getWriteAttachment("handheld"));
         addTextureSampler(samplers, "prev_radiosity_position", () -> lightBuffer.get().getReadAttachment("position"));
         addTextureSampler(samplers, "prev_radiosity_normal", () -> lightBuffer.get().getReadAttachment("normal"));
         addTextureSampler(samplers, "prev_radiosity_direct", () -> lightBuffer.get().getReadAttachment("direct"));
         addTextureSampler(samplers, "prev_radiosity_direct_soft", () -> lightBuffer.get().getReadAttachment("direct_soft"));
         addTextureSampler(samplers, "prev_radiosity_handheld", () -> lightBuffer.get().getReadAttachment("handheld"));
      }
   }

   @Unique
   private static void addTextureSampler(SamplerHolder samplers, String name, Supplier<TextureObject> textureObjectSupplier) {
      samplers.addDynamicSampler(() -> {
         TextureObject textureObject = textureObjectSupplier.get();
         textureObject.updatePerFrame();
         return textureObject.getTextureId();
      }, new String[]{name});
   }
}
