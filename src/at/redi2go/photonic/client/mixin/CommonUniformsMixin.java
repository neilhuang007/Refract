package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.PhotonicsStorage;
import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.RenderDispatcher;
import at.redi2go.photonic.client.rendering.MinecraftAccessor;
import at.redi2go.photonic.client.rendering.opengl.rendering.ShaderUtil;
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
import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(value = CommonUniforms.class, remap = false)
public class CommonUniformsMixin {
   @Unique
   private static Matrix4f previousModelViewProjection = new Matrix4f().identity();
   @Unique
   private static Vector3f previousWorldCameraPosition = new Vector3f();

   @Inject(method = "addNonDynamicUniforms", at = @At("TAIL"))
   private static void addIrisExclusiveUniforms(
      UniformHolder uniforms, IdMap idMap, PackDirectives directives, FrameUpdateNotifier updateNotifier, CallbackInfo ci
   ) {
      if (Raytracer.shouldBeEnabled()) {
         Supplier<WorldRegistry> worldRegistry = () -> Raytracer.INSTANCE.getWorldRegistry();
         Supplier<RenderDispatcher> renderDispatcher = () -> Raytracer.INSTANCE.getRenderDispatcher();
         uniforms.uniform3f(UniformUpdateFrequency.PER_FRAME, "world_camera_position", MinecraftAccessor::getCameraPosition);
         uniforms.uniformMatrix(
            UniformUpdateFrequency.PER_FRAME,
            "direction_transformation_matrix_in",
            () -> ShaderUtil.createScreenCameraMatrix(
               CapturedRenderingState.INSTANCE.getGbufferProjection(), CapturedRenderingState.INSTANCE.getGbufferModelView()
            )
         );
         uniforms.uniformMatrix(
            UniformUpdateFrequency.PER_FRAME,
            "modelview_projection",
            () -> renderDispatcher.get().getModelViewProjectionMatrix(MinecraftAccessor.getCameraPosition())
         );
         uniforms.uniformMatrix(UniformUpdateFrequency.PER_FRAME, "previous_modelview_projection", () -> {
            Matrix4f previous = previousModelViewProjection;
            previousModelViewProjection = renderDispatcher.get().getModelViewProjectionMatrix(MinecraftAccessor.getCameraPosition());
            return previous;
         });
         uniforms.uniform3f(UniformUpdateFrequency.PER_FRAME, "previous_world_camera_position", () -> {
            Vector3f previous = previousWorldCameraPosition;
            previousWorldCameraPosition = new Vector3f(MinecraftAccessor.getCameraPosition());
            return previous;
         });
         uniforms.uniform3f(UniformUpdateFrequency.PER_FRAME, "handheld_color", () -> renderDispatcher.get().getHandheldColor());
         uniforms.uniform1b(UniformUpdateFrequency.PER_FRAME, "left_handed", () -> renderDispatcher.get().isLeftHanded());
         uniforms.uniform1b(UniformUpdateFrequency.PER_FRAME, "light_reload", () -> worldRegistry.get().fetchLightReload());
         uniforms.uniform1f(
            UniformUpdateFrequency.PER_FRAME, "ph_mod_shadow_pixelation_enabled", () -> PhotonicsStorage.SHADOW_PIXELATION_ENABLED.value ? 1.0F : 0.0F
         );
         uniforms.uniform1f(
            UniformUpdateFrequency.PER_FRAME, "ph_mod_oilify_enabled", () -> PhotonicsStorage.OILIFY_ENABLED.value ? 1.0F : 0.0F
         );
         uniforms.uniform1f(
            UniformUpdateFrequency.PER_FRAME, "ph_mod_oilify_size", () -> PhotonicsStorage.OILIFY_SIZE.value
         );
         uniforms.uniform1f(
            UniformUpdateFrequency.PER_FRAME, "ph_mod_oilify_sharpness", () -> PhotonicsStorage.OILIFY_SHARPNESS.value
         );
         uniforms.uniform1f(
            UniformUpdateFrequency.PER_FRAME, "ph_mod_oilify_scale", () -> PhotonicsStorage.OILIFY_SCALE.value
         );
         uniforms.uniform1f(
            UniformUpdateFrequency.PER_FRAME, "ph_mod_oilify_tuning", () -> PhotonicsStorage.OILIFY_TUNING.value
         );
         uniforms.uniform1f(
            UniformUpdateFrequency.PER_FRAME, "ph_mod_oilify_iterations", () -> PhotonicsStorage.OILIFY_ITERATIONS.value
         );
         uniforms.uniform1f(
            UniformUpdateFrequency.PER_FRAME, "ph_mod_oilify_depth_scaling", () -> PhotonicsStorage.OILIFY_DEPTH_SCALING.value
         );
         uniforms.uniform1f(
            UniformUpdateFrequency.PER_FRAME, "ph_mod_oilify_stroke_strength", () -> PhotonicsStorage.OILIFY_STROKE_STRENGTH.value
         );
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_mod_shadow_pixel_size_rt", () -> {
            float shadowSize = Math.max(1.0F, PhotonicsStorage.SHADOW_PIXELATION_SIZE.value);
            return shadowSize;
         });
         uniforms.uniform1f(
            UniformUpdateFrequency.PER_FRAME,
            "ph_mod_pixelation_debug_enabled",
            () -> PhotonicsStorage.PIXELATED_LIGHTING_DEBUG_LOG.value ? 1.0F : 0.0F
         );
      }
   }

   @Inject(method = "addDynamicUniforms", at = @At("TAIL"))
   private static void addIrisExclusiveUniforms(DynamicUniformHolder uniforms, FogMode fogMode, CallbackInfo ci) {
      if (Raytracer.shouldBeEnabled()) {
         Supplier<WorldRegistry> worldRegistry = () -> Raytracer.INSTANCE.getWorldRegistry();
         uniforms.uniform3f(UniformUpdateFrequency.PER_FRAME, "world_offset", () -> worldRegistry.get().getWorldOffset());
         uniforms.uniform3f(UniformUpdateFrequency.PER_FRAME, "world_min_voxel", () -> new Vector3f(worldRegistry.get().getWorldMinVoxel().toVector()));
         uniforms.uniform3f(UniformUpdateFrequency.PER_FRAME, "world_max_voxel", () -> new Vector3f(worldRegistry.get().getWorldMaxVoxel().toVector()));
         uniforms.uniform3f(UniformUpdateFrequency.PER_FRAME, "camera_position", () -> worldRegistry.get().toRt(MinecraftAccessor.getCameraPosition()));
      }
   }
}
