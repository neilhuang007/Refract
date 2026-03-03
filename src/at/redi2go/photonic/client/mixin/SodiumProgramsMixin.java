package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.Raytracer;
import com.google.common.collect.ImmutableSet;
import com.llamalad7.mixinextras.sugar.Local;
import java.util.function.Supplier;
import net.caffeinemc.mods.sodium.client.gl.shader.GlProgram;
import net.caffeinemc.mods.sodium.client.render.chunk.shader.ChunkShaderInterface;
import net.caffeinemc.mods.sodium.client.render.chunk.terrain.TerrainRenderPass;
import net.irisshaders.iris.gl.framebuffer.GlFramebuffer;
import net.irisshaders.iris.pipeline.IrisRenderingPipeline;
import net.irisshaders.iris.pipeline.programs.SodiumPrograms;
import net.irisshaders.iris.pipeline.programs.SodiumPrograms.Pass;
import net.irisshaders.iris.shaderpack.programs.ProgramFallbackResolver;
import net.irisshaders.iris.shaderpack.programs.ProgramSet;
import net.irisshaders.iris.shaderpack.programs.ProgramSource;
import net.irisshaders.iris.shadows.ShadowRenderTargets;
import net.irisshaders.iris.shadows.ShadowRenderingState;
import net.irisshaders.iris.targets.RenderTargets;
import net.irisshaders.iris.uniforms.custom.CustomUniforms;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(value = SodiumPrograms.class, remap = false)
public class SodiumProgramsMixin {
   @Inject(method = "<init>", at = @At(value = "INVOKE", target = "Ljava/util/EnumMap;put(Ljava/lang/Enum;Ljava/lang/Object;)Ljava/lang/Object;", ordinal = 1))
   public void putShader(
      IrisRenderingPipeline pipeline,
      ProgramSet programSet,
      ProgramFallbackResolver resolver,
      RenderTargets renderTargets,
      Supplier shadowRenderTargets,
      CustomUniforms customUniforms,
      CallbackInfo ci,
      @Local Pass pass,
      @Local GlProgram<ChunkShaderInterface> program
   ) {
      if (!Raytracer.isDisabled()) {
         if (pass == Pass.valueOf("VOXELS") || pass == Pass.valueOf("SHADOW_VOXELS")) {
            Raytracer.INSTANCE.getMainRenderer().configureVoxelsShaders(program);
         }
      }
   }

   @Inject(method = "mapTerrainRenderPass", at = @At("HEAD"), cancellable = true)
   public void mapTerrainRenderPass(TerrainRenderPass pass, CallbackInfoReturnable<Pass> cir) {
      if (pass == Raytracer.VOXEL) {
         Pass sodiumPass = ShadowRenderingState.areShadowsCurrentlyBeingRendered() ? Pass.valueOf("SHADOW_VOXELS") : Pass.valueOf("VOXELS");
         cir.setReturnValue(sodiumPass);
      }
   }

   @Inject(method = "createFramebuffer", at = @At("HEAD"), cancellable = true)
   public void createFramebuffer(
      Pass pass,
      ProgramSource source,
      Supplier<ShadowRenderTargets> shadowRenderTargets,
      RenderTargets renderTargets,
      Supplier<ImmutableSet<Integer>> flipState,
      CallbackInfoReturnable<GlFramebuffer> cir
   ) {
      if (pass == Pass.valueOf("SHADOW_VOXELS")) {
         GlFramebuffer framebuffer = shadowRenderTargets.get()
            .createShadowFramebuffer(
               ImmutableSet.of(),
               source == null ? new int[]{0, 1} : (source.getDirectives().hasUnknownDrawBuffers() ? new int[]{0, 1} : source.getDirectives().getDrawBuffers())
            );
         cir.setReturnValue(framebuffer);
         cir.cancel();
      }
   }
}
