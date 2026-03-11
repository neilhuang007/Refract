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
import org.joml.Vector3d;
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
   private static Vector3d previousWorldCameraPosition = new Vector3d();

   @Inject(method = "addNonDynamicUniforms", at = @At("TAIL"))
   private static void addIrisExclusiveUniforms(
      UniformHolder uniforms, IdMap idMap, PackDirectives directives, FrameUpdateNotifier updateNotifier, CallbackInfo ci
   ) {
      if (Raytracer.shouldBeEnabled()) {
         Supplier<WorldRegistry> worldRegistry = () -> Raytracer.INSTANCE.getWorldRegistry();
         Supplier<RenderDispatcher> renderDispatcher = () -> Raytracer.INSTANCE.getRenderDispatcher();
         uniforms.uniform3d(UniformUpdateFrequency.PER_FRAME, "world_camera_position", () -> new Vector3d(MinecraftAccessor.getCameraPosition()));
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
            () -> renderDispatcher.get().getModelViewProjectionMatrix(new Vector3f(MinecraftAccessor.getCameraPosition()))
         );
         uniforms.uniformMatrix(UniformUpdateFrequency.PER_FRAME, "previous_modelview_projection", () -> {
            Matrix4f previous = previousModelViewProjection;
            previousModelViewProjection = renderDispatcher.get().getModelViewProjectionMatrix(new Vector3f(MinecraftAccessor.getCameraPosition()));
            return previous;
         });
         uniforms.uniform3d(UniformUpdateFrequency.PER_FRAME, "previous_world_camera_position", () -> {
            Vector3d previous = previousWorldCameraPosition;
            previousWorldCameraPosition = new Vector3d(MinecraftAccessor.getCameraPosition());
            return previous;
         });
         uniforms.uniform3f(UniformUpdateFrequency.PER_FRAME, "handheld_color", () -> renderDispatcher.get().getHandheldColor());
         uniforms.uniform1b(UniformUpdateFrequency.PER_FRAME, "left_handed", () -> renderDispatcher.get().isLeftHanded());
         uniforms.uniform1b(UniformUpdateFrequency.PER_FRAME, "light_reload", () -> worldRegistry.get().fetchLightReload());
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_mod_shadow_pixelation_enabled",
            () -> PhotonicsStorage.SHADOW_PIXELATION_ENABLED.value ? 1.0F : 0.0F);
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "ph_mod_shadow_pixel_size_rt",
            () -> PhotonicsStorage.SHADOW_PIXELATION_SIZE.value);
      }
   }

   @Inject(method = "addDynamicUniforms", at = @At("TAIL"))
   private static void addIrisExclusiveUniforms(DynamicUniformHolder uniforms, FogMode fogMode, CallbackInfo ci) {
      if (Raytracer.shouldBeEnabled()) {
         Supplier<WorldRegistry> worldRegistry = () -> Raytracer.INSTANCE.getWorldRegistry();
         uniforms.uniform3d(UniformUpdateFrequency.PER_FRAME, "world_offset", () -> worldRegistry.get().getWorldOffset());
         uniforms.uniform3d(UniformUpdateFrequency.PER_FRAME, "world_min_voxel", () -> new Vector3d(worldRegistry.get().getWorldMinVoxel().toVector()));
         uniforms.uniform3d(UniformUpdateFrequency.PER_FRAME, "world_max_voxel", () -> new Vector3d(worldRegistry.get().getWorldMaxVoxel().toVector()));
         uniforms.uniform3d(UniformUpdateFrequency.PER_FRAME, "rt_camera_position", () -> worldRegistry.get().toRt(new Vector3d(MinecraftAccessor.getCameraPosition())));
         uniforms.uniform1i(UniformUpdateFrequency.PER_FRAME, "ph_light_count", () -> {
            Raytracer rt = Raytracer.INSTANCE;
            return rt == null ? 0 : rt.getWorldRegistry().getLightRegistry().lightCount();
         });
         uniforms.uniform1f(UniformUpdateFrequency.PER_FRAME, "light_blend_factor", () -> worldRegistry.get().fetchLightBlendFactor());
         uniforms.uniform3d(UniformUpdateFrequency.PER_FRAME, "light_blend_min", () -> worldRegistry.get().getLightBlendMin());
         uniforms.uniform3d(UniformUpdateFrequency.PER_FRAME, "light_blend_max", () -> worldRegistry.get().getLightBlendMax());
         Raytracer.INSTANCE.getMainRenderer().registerCustomUniforms(uniforms);
      }
   }
}
