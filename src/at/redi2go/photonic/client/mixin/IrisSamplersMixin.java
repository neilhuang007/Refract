package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.IrisRenderTargetAliases;
import at.redi2go.photonic.client.Raytracer;
import com.google.common.collect.ImmutableSet;
import it.unimi.dsi.fastutil.objects.Object2ObjectMap;
import net.irisshaders.iris.gl.sampler.SamplerHolder;
import net.irisshaders.iris.gl.texture.TextureAccess;
import net.irisshaders.iris.pipeline.WorldRenderingPipeline;
import net.irisshaders.iris.samplers.IrisSamplers;
import net.irisshaders.iris.targets.RenderTargets;
import java.util.function.Supplier;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(value = IrisSamplers.class, remap = false)
public abstract class IrisSamplersMixin {
   @Inject(method = "addCustomTextures", at = @At("TAIL"))
   private static void addCustomTexture(SamplerHolder samplers, Object2ObjectMap<String, TextureAccess> irisCustomTextures, CallbackInfo ci) {
      Raytracer raytracer = Raytracer.INSTANCE;
      if (Raytracer.shouldBeEnabled() && raytracer != null) {
         raytracer.getMainRenderer().registerCustomTextures(samplers);
      }
   }

   @Inject(method = "addRenderTargetSamplers", at = @At("TAIL"))
   private static void photonic$addAliasedRenderTargetSamplers(
      SamplerHolder samplers,
      Supplier<ImmutableSet<Integer>> flipped,
      RenderTargets renderTargets,
      boolean isFullscreenPass,
      WorldRenderingPipeline pipeline,
      CallbackInfo ci
   ) {
      IrisRenderTargetAliases.addSamplerAliases(samplers, flipped, renderTargets);
   }
}
