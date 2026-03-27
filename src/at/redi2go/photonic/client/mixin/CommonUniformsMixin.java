package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.PhotonicsStorage;
import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.RenderDispatcher;
import at.redi2go.photonic.client.rendering.opengl.rendering.ShaderUtil;
import at.redi2go.photonic.client.rendering.opengl.rendering.RegirComputeProgram;
import at.redi2go.photonic.client.rendering.world.WorldRegistry;
import java.util.function.Supplier;
import net.irisshaders.iris.gl.state.FogMode;
import net.irisshaders.iris.gl.uniform.DynamicUniformHolder;
import net.irisshaders.iris.gl.uniform.UniformHolder;
import net.irisshaders.iris.gl.uniform.UniformUpdateFrequency;
import net.irisshaders.iris.shaderpack.IdMap;
import net.irisshaders.iris.shaderpack.properties.PackDirectives;
import net.irisshaders.iris.uniforms.CapturedRenderingState;
import net.irisshaders.iris.uniforms.CommonUniforms;
import net.irisshaders.iris.uniforms.FrameUpdateNotifier;
import net.minecraft.client.MinecraftClient;
import net.minecraft.util.math.Vec3d;
import org.joml.Matrix4f;
import org.joml.Vector3d;
import org.joml.Vector3i;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(value = CommonUniforms.class, remap = false)
public class CommonUniformsMixin {
   @Inject(method = "addNonDynamicUniforms", at = @At("TAIL"))
   private static void addIrisExclusiveUniforms(
      UniformHolder uniforms, IdMap idMap, PackDirectives directives, FrameUpdateNotifier updateNotifier, CallbackInfo ci
   ) {
      Raytracer raytracer = Raytracer.INSTANCE;
      if (Raytracer.shouldBeEnabled() && raytracer != null) {
         Supplier<WorldRegistry> worldRegistry = raytracer::getWorldRegistry;
         Supplier<RenderDispatcher> renderDispatcher = raytracer::getRenderDispatcher;
         uniforms.uniformMatrix(
            UniformUpdateFrequency.PER_FRAME,
            "direction_transformation_matrix_in",
            () -> {
               org.joml.Matrix4fc projection = CapturedRenderingState.INSTANCE.getGbufferProjection();
               org.joml.Matrix4fc modelView = CapturedRenderingState.INSTANCE.getGbufferModelView();
               if (projection == null || modelView == null) {
                  return new Matrix4f();
               }

               return ShaderUtil.createScreenCameraMatrix(projection, modelView);
            }
         );
         uniforms.uniform3f(UniformUpdateFrequency.PER_FRAME, "handheld_color", () -> renderDispatcher.get().getHandheldColor());
         uniforms.uniform1b(UniformUpdateFrequency.PER_FRAME, "left_handed", () -> renderDispatcher.get().isLeftHanded());
         uniforms.uniform1b(UniformUpdateFrequency.PER_FRAME, "light_reload", () -> worldRegistry.get().fetchLightReload());
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_mod_shadow_pixelation_enabled",
            () -> PhotonicsStorage.SHADOW_PIXELATION_ENABLED.value ? 1.0F : 0.0F);
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_mod_shadow_pixel_size_rt",
            () -> PhotonicsStorage.SHADOW_PIXELATION_SIZE.value);
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_debug_show_direct",
            () -> PhotonicsStorage.DEBUG_SHOW_DIRECT.value ? 1.0F : 0.0F);
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_debug_show_indirect",
            () -> PhotonicsStorage.DEBUG_SHOW_INDIRECT.value ? 1.0F : 0.0F);
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_debug_show_handheld",
            () -> PhotonicsStorage.DEBUG_SHOW_HANDHELD.value ? 1.0F : 0.0F);
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_debug_show_scene",
            () -> PhotonicsStorage.DEBUG_SHOW_SCENE.value ? 1.0F : 0.0F);
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_debug_show_denoiser",
            () -> PhotonicsStorage.DEBUG_SHOW_DENOISER.value ? 1.0F : 0.0F);
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_debug_disable_denoiser",
            () -> PhotonicsStorage.DEBUG_DISABLE_DENOISER.value ? 1.0F : 0.0F);
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_debug_disable_shadow_rays",
            () -> PhotonicsStorage.DEBUG_DISABLE_SHADOW_RAYS.value ? 1.0F : 0.0F);
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_debug_lock_traversal_rng",
            () -> PhotonicsStorage.DEBUG_LOCK_TRAVERSAL_RNG.value ? 1.0F : 0.0F);
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_debug_disable_temporal_reset",
            () -> PhotonicsStorage.DEBUG_DISABLE_TEMPORAL_RESET.value ? 1.0F : 0.0F);
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_debug_disable_taa_jitter",
            () -> PhotonicsStorage.DEBUG_DISABLE_TAA_JITTER.value ? 1.0F : 0.0F);
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_debug_freeze_rng",
            () -> PhotonicsStorage.DEBUG_FREEZE_RNG.value ? 1.0F : 0.0F);
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_debug_constant_albedo",
            () -> PhotonicsStorage.DEBUG_CONSTANT_ALBEDO.value ? 1.0F : 0.0F);
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "phFirstBuildTime",
            () -> worldRegistry.get().getFirstBuildTime());
      }
   }

   @Inject(method = "addDynamicUniforms", at = @At("TAIL"))
   private static void addIrisExclusiveUniforms(DynamicUniformHolder uniforms, FogMode fogMode, CallbackInfo ci) {
      Raytracer raytracer = Raytracer.INSTANCE;
      if (Raytracer.shouldBeEnabled() && raytracer != null) {
         Supplier<WorldRegistry> worldRegistry = raytracer::getWorldRegistry;
         uniforms.uniform3d(UniformUpdateFrequency.PER_FRAME, "world_offset", () -> worldRegistry.get().getWorldOffset());
         uniforms.uniform3d(UniformUpdateFrequency.PER_FRAME, "world_min_voxel", () -> new Vector3d(worldRegistry.get().getWorldMinVoxel().toVector()));
         uniforms.uniform3d(UniformUpdateFrequency.PER_FRAME, "world_max_voxel", () -> new Vector3d(worldRegistry.get().getWorldMaxVoxel().toVector()));
         uniforms.uniform3d(UniformUpdateFrequency.PER_FRAME, "rt_camera_position", () -> worldRegistry.get().toRt(photonic$getWorldCameraPosition()));
         uniforms.uniform1i(UniformUpdateFrequency.PER_FRAME, "ph_light_count", () -> {
            Raytracer rt = Raytracer.INSTANCE;
            return rt == null ? 0 : rt.getWorldRegistry().getLightRegistry().lightCount();
         });
         // RTXDI: center-based grid anchoring — origin derived in shader as center - gridRes * cellSize * 0.5
         uniforms.uniform3f(UniformUpdateFrequency.PER_FRAME, "ph_regir_grid_center", () -> worldRegistry.get().getLightRegistry().getRegirGridCenter());
         uniforms.uniform3i(UniformUpdateFrequency.PER_FRAME, "ph_regir_grid_cells", () -> {
            int gridRes = worldRegistry.get().getLightRegistry().getRegirGridResolution();
            return new Vector3i(gridRes, gridRes, gridRes);
         });
         uniforms.uniform1i(UniformUpdateFrequency.PER_FRAME, "ph_regir_lights_per_cell", () -> worldRegistry.get().getLightRegistry().getRegirLightsPerCell());
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_regir_cell_size", () -> 32.0F);
         // ph_regir_build_samples is compute-only (set by RegirComputeProgram.dispatch()).
         // RTXDI FullSample multiplies the dynamic ReGIR jitter by 2.0 before uploading
         // constants, so the shader-side default is 2.0 (= plus/minus one cell of jitter).
         uniforms.uniform1f(
            UniformUpdateFrequency.PER_FRAME,
            "ph_regir_sampling_jitter",
            () -> worldRegistry.get().getLightRegistry().getRegirSamplingJitter()
         );
         // Unified RIS buffer offsets for fragment shaders (light_tree.glsl, reuse_bridge.glsl).
         uniforms.uniform1i(UniformUpdateFrequency.PER_FRAME, "ph_ris_tile_size", () -> RegirComputeProgram.tileSize);
         uniforms.uniform1i(UniformUpdateFrequency.PER_FRAME, "ph_ris_tile_count", () -> RegirComputeProgram.tileCount);
         // ph_ris_tile_buffer_offset = 0 (tiles always at the start of ph_ris_buffer).
         // ph_regir_ris_buffer_offset = tileCount * tileSize (ReGIR region follows tiles).
         uniforms.uniform1i(UniformUpdateFrequency.PER_FRAME, "ph_ris_tile_buffer_offset", () -> 0);
         uniforms.uniform1i(UniformUpdateFrequency.PER_FRAME, "ph_regir_ris_buffer_offset",
            () -> RegirComputeProgram.tileCount * RegirComputeProgram.tileSize);
         uniforms.uniform1i(UniformUpdateFrequency.PER_FRAME, "light_blend_region_count", () -> worldRegistry.get().getLightBlendRegionCount());
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "light_blend_factor", () -> worldRegistry.get().fetchLightBlendFactor());
         uniforms.uniform3d(UniformUpdateFrequency.PER_FRAME, "light_blend_min", () -> worldRegistry.get().getLightBlendMin());
         uniforms.uniform3d(UniformUpdateFrequency.PER_FRAME, "light_blend_max", () -> worldRegistry.get().getLightBlendMax());
         photonic$registerLightBlendRegionUniform(uniforms, worldRegistry, 1);
         photonic$registerLightBlendRegionUniform(uniforms, worldRegistry, 2);
         photonic$registerLightBlendRegionUniform(uniforms, worldRegistry, 3);
         photonic$registerLightBlendRegionUniform(uniforms, worldRegistry, 4);
         photonic$registerLightBlendRegionUniform(uniforms, worldRegistry, 5);
         photonic$registerLightBlendRegionUniform(uniforms, worldRegistry, 6);
         photonic$registerLightBlendRegionUniform(uniforms, worldRegistry, 7);
         raytracer.getMainRenderer().registerCustomUniforms(uniforms);
      }
   }

   private static void photonic$registerLightBlendRegionUniform(
      DynamicUniformHolder uniforms, Supplier<WorldRegistry> worldRegistry, int index
   ) {
      uniforms.uniform3d(UniformUpdateFrequency.PER_FRAME, "light_blend_min_" + index, () -> worldRegistry.get().getLightBlendMin(index));
      uniforms.uniform3d(UniformUpdateFrequency.PER_FRAME, "light_blend_max_" + index, () -> worldRegistry.get().getLightBlendMax(index));
   }

   private static Vector3d photonic$getWorldCameraPosition() {
      MinecraftClient client = MinecraftClient.getInstance();
      if (client == null || client.gameRenderer == null || client.gameRenderer.getCamera() == null) {
         return new Vector3d();
      }

      Vec3d position = client.gameRenderer.getCamera().getPos();
      return new Vector3d(position.x, position.y, position.z);
   }
}
