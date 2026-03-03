package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.Photonic;
import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.ShaderPackPath;
import at.redi2go.photonic.client.rendering.patching.Patch;
import com.google.common.collect.ImmutableList;
import java.io.IOException;
import java.io.StringReader;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Properties;
import net.irisshaders.iris.Iris;
import net.irisshaders.iris.helpers.StringPair;
import net.irisshaders.iris.shaderpack.ShaderPack;
import net.irisshaders.iris.shaderpack.include.AbsolutePackPath;
import net.irisshaders.iris.shaderpack.include.IncludeProcessor;
import net.irisshaders.iris.shaderpack.option.OrderBackedProperties;
import org.apache.commons.compress.utils.Lists;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Shadow;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.ModifyArgs;
import org.spongepowered.asm.mixin.injection.At.Shift;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;
import org.spongepowered.asm.mixin.injection.invoke.arg.Args;

@Mixin(value = ShaderPack.class, remap = false)
public abstract class ShaderPackMixin {
   @Unique
   private static boolean isPhotonicsSource = false;

   @Shadow
   private static Optional<String> loadProperties(Path shaderPath, String name) {
      return Optional.empty();
   }

   @Inject(
      method = "<init>(Ljava/nio/file/Path;Ljava/util/Map;Lcom/google/common/collect/ImmutableList;Z)V",
      at = @At(value = "INVOKE", target = "Ljava/util/EnumMap;<init>(Ljava/lang/Class;)V")
   )
   private void init(Path root, Map<String, String> changedConfigs, ImmutableList environmentDefines, boolean isZip, CallbackInfo ci) {
      Raytracer.reloadPatches();
      Raytracer.SHADERPACK_CHANGED_OPTIONS = changedConfigs;

      try {
         Raytracer.SHADERPACK_PROPERTIES = new OrderBackedProperties();
         String propsStr = loadProperties(root, "shaders.properties").orElseThrow();
         Raytracer.SHADERPACK_PROPERTIES.load(new StringReader(propsStr));
      } catch (IOException var7) {
         Raytracer.SHADERPACK_PROPERTIES = new Properties();
         Photonic.error(var7);
      }
   }

   @Inject(method = "readProperties", at = @At("HEAD"), cancellable = true)
   private static void readProperties(Path shaderPath, String name, CallbackInfoReturnable<String> cir) {
      Patch patch = Raytracer.getAppliedPatch();
      if (patch != null) {
         String patchedFile = patch.readPatchedFile(new ShaderPackPath(shaderPath.resolve(name)));
         if (patchedFile != null) {
            cir.setReturnValue(patchedFile);
            cir.cancel();
         }
      }
   }

   @Inject(
      method = "lambda$new$8",
      at = @At(
         value = "INVOKE",
         target = "Lnet/irisshaders/iris/shaderpack/preprocessor/JcppProcessor;glslPreprocessSource(Ljava/lang/String;Ljava/lang/Iterable;)Ljava/lang/String;",
         shift = Shift.BEFORE
      ),
      remap = false
   )
   private static void lambda$new$8(
      List disabledPrograms, IncludeProcessor includeProcessor, Iterable finalEnvironmentDefines1, AbsolutePackPath path, CallbackInfoReturnable<String> cir
   ) {
      isPhotonicsSource = path.getPathString().contains("photonics");
   }

   @ModifyArgs(
      method = "lambda$new$8",
      at = @At(
         value = "INVOKE",
         target = "Lnet/irisshaders/iris/shaderpack/preprocessor/JcppProcessor;glslPreprocessSource(Ljava/lang/String;Ljava/lang/Iterable;)Ljava/lang/String;"
      ),
      remap = false
   )
   private static void provideSource(Args args) {
      if (isPhotonicsSource) {
         Iterable<StringPair> environmentDefines = (Iterable<StringPair>)args.get(1);
         List<StringPair> definitions = Lists.newArrayList(environmentDefines.iterator());
         String var4 = Iris.getCurrentDimension().getName();

         String dimensionDefine = switch (var4) {
            case "overworld" -> "OVERWORLD";
            case "the_nether" -> "NETHER";
            case "the_end" -> "END";
            default -> throw new IllegalStateException("Unexpected value: " + Iris.getCurrentDimension().getName());
         };
         definitions.add(new StringPair(dimensionDefine, ""));
         args.set(1, definitions);
      }
   }
}
