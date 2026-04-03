package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.rendering.opengl.rendering.ShaderUtil;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import net.irisshaders.iris.gl.program.ProgramBuilder;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.ModifyArgs;
import org.spongepowered.asm.mixin.injection.invoke.arg.Args;

@Mixin(value = ProgramBuilder.class, remap = false)
public class ProgramBuilderMixin {
   @ModifyArgs(
      method = "buildShader",
      at = @At(
         value = "INVOKE",
         target = "Lnet/irisshaders/iris/gl/shader/GlShader;<init>(Lnet/irisshaders/iris/gl/shader/ShaderType;Ljava/lang/String;Ljava/lang/String;)V"
      )
   )
   private static void initGlShader(Args args) {
      String shaderName = (String) args.get(1);
      String shaderSource = (String) args.get(2);

      if (shaderName.contains("ph_")) {
         shaderSource = ShaderUtil.preprocessAutoUniforms(shaderSource);
         args.set(2, shaderSource);
      }

      if (shaderName.contains("ShadeSamplesLighting")) {
         photonics$dumpShaderSource(shaderName, shaderSource);
      }
   }

   private static void photonics$dumpShaderSource(String shaderName, String shaderSource) {
      try {
         Path outDir = Path.of("build", "shader-debug");
         Files.createDirectories(outDir);
         String fileName = shaderName.replace('/', '_').replace('\\', '_').replace(':', '_');
         Files.writeString(outDir.resolve(fileName + ".dump.glsl"), shaderSource);
      } catch (IOException ignored) {
      }
   }
}
