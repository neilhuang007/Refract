package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.PhotonicsStorage;
import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.UniformPatcher;
import at.redi2go.photonic.client.api.PhotonicsProperties;
import at.redi2go.photonic.client.rendering.patching.Patch;
import com.google.common.collect.ImmutableList;
import com.llamalad7.mixinextras.injector.wrapoperation.Operation;
import com.llamalad7.mixinextras.injector.wrapoperation.WrapOperation;
import com.llamalad7.mixinextras.sugar.Local;
import com.mojang.brigadier.exceptions.CommandSyntaxException;
import java.io.IOException;
import java.io.StringReader;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Properties;
import net.fabricmc.loader.api.ModContainer;
import net.fabricmc.loader.api.SemanticVersion;
import net.irisshaders.iris.Iris;
import net.irisshaders.iris.helpers.StringPair;
import net.irisshaders.iris.shaderpack.ShaderPack;
import net.irisshaders.iris.shaderpack.include.AbsolutePackPath;
import net.irisshaders.iris.shaderpack.include.IncludeProcessor;
import net.irisshaders.iris.shaderpack.option.OrderBackedProperties;
import net.irisshaders.iris.shaderpack.properties.ShaderProperties;
import org.apache.commons.compress.utils.Lists;
import org.apache.commons.lang3.StringUtils;
import org.spongepowered.asm.mixin.Final;
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
   @Shadow
   @Final
   private ShaderProperties shaderProperties;

   @Unique
   private static boolean isPhotonicsSource = false;

   @Unique
   private static boolean patchProperties = true;

   @Shadow
   private static Optional<String> loadProperties(Path shaderPath, String name) {
      return Optional.empty();
   }

   @Inject(
      method = "<init>(Ljava/nio/file/Path;Ljava/util/Map;Lcom/google/common/collect/ImmutableList;Z)V",
      at = @At(value = "INVOKE", target = "Ljava/util/EnumMap;<init>(Ljava/lang/Class;)V")
   )
   private void init(Path root, Map<String, String> changedConfigs, ImmutableList<StringPair> environmentDefines, boolean isZip, CallbackInfo ci) {
      Raytracer.reloadPatches();
      Raytracer.SHADERPACK_CHANGED_OPTIONS = changedConfigs;

      try {
         Raytracer.SHADERPACK_PROPERTIES = new OrderBackedProperties();
         patchProperties = false;
         Raytracer.SHADERPACK_PROPERTIES.load(new StringReader(loadProperties(root, "shaders.properties").orElseThrow()));
         patchProperties = true;
         Raytracer.PATCHED_SHADERPACK_PROPERTIES = new OrderBackedProperties();
         Raytracer.PATCHED_SHADERPACK_PROPERTIES.load(new StringReader(loadProperties(root, "shaders.properties").orElseThrow()));
      } catch (IOException var7) {
         Raytracer.SHADERPACK_PROPERTIES = new Properties();
         Raytracer.PATCHED_SHADERPACK_PROPERTIES = new Properties();
         var7.printStackTrace();
      }
   }

   @Inject(method = "readProperties", at = @At("HEAD"), cancellable = true)
   private static void readProperties(Path shaderPath, String name, CallbackInfoReturnable<String> cir) {
      if (patchProperties) {
         Patch patch = Raytracer.getAppliedPatch();
         if (patch == null) {
            return;
         }

         String patchedFile = patch.readPatchedFile(shaderPath.resolve(name));
         if (patchedFile == null) {
            return;
         }

         cir.setReturnValue(patchedFile);
         cir.cancel();
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
   private static void lambda$new$8Pre(
      List disabledPrograms, IncludeProcessor includeProcessor, Iterable finalEnvironmentDefines1, AbsolutePackPath path, CallbackInfoReturnable<String> cir
   ) {
      isPhotonicsSource = path.getPathString().contains("photonics");
   }

   @WrapOperation(
      method = "lambda$new$8",
      at = @At(
         value = "INVOKE",
         target = "Lnet/irisshaders/iris/shaderpack/preprocessor/JcppProcessor;glslPreprocessSource(Ljava/lang/String;Ljava/lang/Iterable;)Ljava/lang/String;"
      ),
      remap = false
   )
   private static String lambda$new$8Post(String source, Iterable<StringPair> environmentDefines, Operation<String> original) {
      UniformPatcher.prepare();

      try {
         return UniformPatcher.addRequiredUniforms((String)original.call(new Object[]{source, environmentDefines}));
      } catch (CommandSyntaxException var4) {
         throw new RuntimeException(var4);
      }
   }

   @Inject(
      method = "<init>(Ljava/nio/file/Path;Ljava/util/Map;Lcom/google/common/collect/ImmutableList;Z)V",
      at = @At(
         value = "INVOKE",
         target = "Lcom/google/common/collect/ImmutableList;copyOf(Ljava/util/Collection;)Lcom/google/common/collect/ImmutableList;",
         ordinal = 0
      )
   )
   private void addDefines0(
      Path root,
      Map<String, String> changedConfigs,
      ImmutableList<StringPair> environmentDefines,
      boolean isZip,
      CallbackInfo ci,
      @Local(name = "envDefines1") ArrayList<StringPair> envDefines1
   ) {
      envDefines1.add(new StringPair("PHOTONICS", ""));
      String versionString = "0";
      Optional<ModContainer> photonics = net.fabricmc.loader.api.FabricLoader.getInstance().getModContainer("photonics");
      if (photonics.isPresent() && photonics.get().getMetadata().getVersion() instanceof SemanticVersion version) {
         String major = version.getVersionComponentCount() >= 1 ? Integer.toString(version.getVersionComponent(0)) : "0";
         String minor = version.getVersionComponentCount() >= 2 ? Integer.toString(version.getVersionComponent(1)) : "0";
         String increment = version.getVersionComponentCount() >= 3 ? Integer.toString(version.getVersionComponent(2)) : "0";
         versionString = StringUtils.stripStart(
            major + StringUtils.leftPad(minor, 2, '0') + StringUtils.leftPad(increment, 2, '0'),
            "0"
         );
      }

      envDefines1.add(new StringPair("PHOTONICS_VERSION", versionString));
      envDefines1.add(new StringPair("PHOTONICS_LIGHTING_MODE", "2"));
      envDefines1.add(new StringPair("PHOTONICS_MAX_LIGHTS", Integer.toString(PhotonicsProperties.DEFAULT_MAX_LIGHTS)));
   }

   @Inject(
      method = "<init>(Ljava/nio/file/Path;Ljava/util/Map;Lcom/google/common/collect/ImmutableList;Z)V",
      at = @At(
         value = "INVOKE",
         target = "Lcom/google/common/collect/ImmutableList;copyOf(Ljava/util/Collection;)Lcom/google/common/collect/ImmutableList;",
         ordinal = 1
      )
   )
   private void addDefines2(
      Path root,
      Map<String, String> changedConfigs,
      ImmutableList<StringPair> environmentDefines,
      boolean isZip,
      CallbackInfo ci,
      @Local(name = "newEnvDefines") List<StringPair> newEnvDefines
   ) {
      PhotonicsProperties properties = (PhotonicsProperties)this.shaderProperties;
      floatDefine(newEnvDefines, "PH_RENDER_SCALE", PhotonicsStorage.RENDER_SCALE.value >= 0 ? PhotonicsStorage.RENDER_SCALE.value : properties.getRenderScale());
      intDefine(newEnvDefines, "PH_MAX_LIGHTS", properties.getMaxLights());
      properties.getAlphaMode().registerDefines(newEnvDefines);
      if (properties.isGiEnabled().orElse(true)) {
         stringDefine(newEnvDefines, "PH_ENABLE_GI", "");
      }

      if (properties.isBlockLightEnabled().orElse(true)) {
         stringDefine(newEnvDefines, "PH_ENABLE_BLOCKLIGHT", "");
      }

      if (properties.isHandheldLightEnabled().orElse(true)) {
         stringDefine(newEnvDefines, "PH_ENABLE_HANDHELD_LIGHT", "");
      }

      intDefine(newEnvDefines, "PH_LIGHTING_MODE", 2);
      intDefine(newEnvDefines, "PH_LIGHTTREE_INITIAL_SAMPLES", properties.getLightTreeInitialSamples());
      intDefine(newEnvDefines, "PH_RESTIR_INITIAL_SAMPLES", properties.getLightTreeInitialSamples());
      intDefine(newEnvDefines, "PH_LIGHTTREE_SPATIAL_REUSE_SAMPLES", PhotonicsStorage.RESTIR_SPATIAL_SAMPLES.value >= 0 ? (int) PhotonicsStorage.RESTIR_SPATIAL_SAMPLES.value.floatValue() : properties.getLightTreeSpatialReuseSamples());
      intDefine(newEnvDefines, "PH_RESTIR_SPATIAL_REUSE_SAMPLES", PhotonicsStorage.RESTIR_SPATIAL_SAMPLES.value >= 0 ? (int) PhotonicsStorage.RESTIR_SPATIAL_SAMPLES.value.floatValue() : properties.getLightTreeSpatialReuseSamples());
      floatDefine(newEnvDefines, "PH_LIGHTTREE_SPATIAL_REUSE_RADIUS", PhotonicsStorage.RESTIR_SPATIAL_RADIUS.value >= 0 ? PhotonicsStorage.RESTIR_SPATIAL_RADIUS.value : properties.getLightTreeSpatialReuseRadius());
      floatDefine(newEnvDefines, "PH_RESTIR_SPATIAL_REUSE_RADIUS", PhotonicsStorage.RESTIR_SPATIAL_RADIUS.value >= 0 ? PhotonicsStorage.RESTIR_SPATIAL_RADIUS.value : properties.getLightTreeSpatialReuseRadius());
      intDefine(newEnvDefines, "PH_LIGHTTREE_ACCUMULATION_FRAMES", properties.getLightTreeAccumulationFrames());
      intDefine(newEnvDefines, "PH_RESTIR_ACCUMULATION_FRAMES", properties.getLightTreeAccumulationFrames());
      intDefine(newEnvDefines, "PH_LIGHTTREE_DENOISER_PASSES", properties.getLightTreeDenoiserPasses());
      intDefine(newEnvDefines, "PH_RESTIR_DENOISER_PASSES", properties.getLightTreeDenoiserPasses());
      intDefine(newEnvDefines, "PH_NRD_ATROUS_PASSES", PhotonicsStorage.NRD_ATROUS_PASSES.value >= 0 ? Math.max(1, (int) PhotonicsStorage.NRD_ATROUS_PASSES.value.floatValue()) : properties.getNrdAtrousPasses());
      if (properties.useLightTreeSoftShadows().orElse(false)) {
         stringDefine(newEnvDefines, "PH_LIGHTTREE_SOFT_SHADOWS", "");
         stringDefine(newEnvDefines, "PH_RESTIR_SOFT_SHADOWS", "");
      }

      intDefine(newEnvDefines, "PH_MAX_SAMPLES", properties.getMaxSamples());
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
         String dimensionName = Iris.getCurrentDimension().getName();

         String dimensionDefine = switch (dimensionName) {
            case "overworld" -> "OVERWORLD";
            case "the_nether" -> "NETHER";
            case "the_end" -> "END";
            default -> throw new IllegalStateException("Unexpected value: " + dimensionName);
         };
         stringDefine(definitions, dimensionDefine, "");
         definitions.add(new StringPair(dimensionDefine, ""));
         args.set(1, definitions);
      }
   }

   @Unique
   private static void stringDefine(List<StringPair> defines, String name, String value) {
      defines.add(new StringPair(name, value));
   }

   @Unique
   private static void intDefine(List<StringPair> defines, String name, int value) {
      defines.add(new StringPair(name, Integer.toString(value)));
   }

   @Unique
   private static void floatDefine(List<StringPair> defines, String name, float value) {
      defines.add(new StringPair(name, Float.toString(value)));
   }

   @Unique
   private static <T extends Enum<T>> void enumDefine(List<StringPair> defines, String name, T value) {
      defines.add(new StringPair(name, Integer.toString(value.ordinal())));
   }
}
