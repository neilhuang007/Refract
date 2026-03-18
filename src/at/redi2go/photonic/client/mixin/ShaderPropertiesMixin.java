package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.api.AlphaMode;
import at.redi2go.photonic.client.api.PhotonicsProperties;
import java.io.IOException;
import java.io.StringReader;
import java.util.HashSet;
import java.util.Properties;
import java.util.function.Consumer;
import net.irisshaders.iris.Iris;
import net.irisshaders.iris.helpers.OptionalBoolean;
import net.irisshaders.iris.shaderpack.option.ShaderPackOptions;
import net.irisshaders.iris.shaderpack.properties.ShaderProperties;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(value = ShaderProperties.class, remap = false)
public abstract class ShaderPropertiesMixin implements PhotonicsProperties {
   @Unique
   private OptionalBoolean isPhotonicsEnabled = OptionalBoolean.DEFAULT;
   @Unique
   private float renderScale = DEFAULT_RENDER_SCALE;
   @Unique
   private int maxLights = DEFAULT_MAX_LIGHTS;
   @Unique
   private int maxSamples = DEFAULT_MAX_SAMPLES;
   @Unique
   private float minTracedLightLuma = DEFAULT_MIN_TRACED_LIGHT_LUMA;
   @Unique
   private AlphaMode alphaMode = DEFAULT_ALPHA_MODE;
   @Unique
   private OptionalBoolean isGiEnabled = OptionalBoolean.DEFAULT;
   @Unique
   private OptionalBoolean isBlockLightEnabled = OptionalBoolean.DEFAULT;
   @Unique
   private OptionalBoolean isHandheldLightEnabled = OptionalBoolean.DEFAULT;
   @Unique
   private OptionalBoolean isLightBinningEnabled = OptionalBoolean.DEFAULT;
   @Unique
   private OptionalBoolean voxelizeLava = OptionalBoolean.DEFAULT;
   @Unique
   private int lightTreeInitialSamples = DEFAULT_LIGHTTREE_INITIAL_SAMPLES;
   @Unique
   private int lightTreeSpatialReuseSamples = DEFAULT_LIGHTTREE_SPATIAL_REUSE_SAMPLES;
   @Unique
   private float lightTreeSpatialReuseRadius = DEFAULT_LIGHTTREE_SPATIAL_REUSE_RADIUS;
   @Unique
   private int lightTreeAccumulationFrames = DEFAULT_LIGHTTREE_ACCUMULATION_FRAMES;
   @Unique
   private OptionalBoolean lightTreeSoftShadows = OptionalBoolean.DEFAULT;
   @Unique
   private int denoiserPasses = DEFAULT_LIGHTTREE_DENOISER_PASSES;
   @Unique
   private int nrdAtrousPasses = DEFAULT_NRD_ATROUS_PASSES;

   @Inject(
      method = "<init>(Ljava/lang/String;Lnet/irisshaders/iris/shaderpack/option/ShaderPackOptions;Ljava/lang/Iterable;)V",
      at = @At("TAIL")
   )
   private void initFromProperties(String contents, ShaderPackOptions shaderPackOptions, Iterable<?> environmentDefines, CallbackInfo ci) {
      Properties props = new Properties();
      try {
         props.load(new StringReader(contents));
      } catch (IOException e) {
         return;
      }
      if (Raytracer.SHADERPACK_PROPERTIES != null) {
         for (String key : Raytracer.SHADERPACK_PROPERTIES.stringPropertyNames()) {
            if (key.startsWith("photonics.") && !props.containsKey(key)) {
               props.setProperty(key, Raytracer.SHADERPACK_PROPERTIES.getProperty(key));
            }
         }
      }
      photonics$applyShaderOptionOverrides(props, shaderPackOptions);
      photonics$applySystemPropertyOverrides(props);
      for (String key : props.stringPropertyNames()) {
         String value = props.getProperty(key);
         photonics$handleDirective(key, value);
      }
   }

   @Unique
   private void photonics$handleDirective(String key, String value) {
      switch (key) {
         case "photonics.enabled" -> this.isPhotonicsEnabled = photonics$parseBoolean(value);
         case "photonics.renderScale" -> photonics$parseFloat(key, value, e -> this.renderScale = e);
         case "photonics.maxLights" -> photonics$parseUnsignedInt(key, value, e -> this.maxLights = e);
         case "photonics.maxSamples" -> photonics$parseUnsignedInt(key, value, e -> this.maxSamples = e);
         case "photonics.minTracedLightLuma" -> photonics$parseFloat(key, value, e -> this.minTracedLightLuma = e);
         case "photonics.alphaMode" -> photonics$parseAlphaMode(key, value, e -> this.alphaMode = e);
         case "photonics.enableGi" -> this.isGiEnabled = photonics$parseBoolean(value);
         case "photonics.enableBlockLight" -> this.isBlockLightEnabled = photonics$parseBoolean(value);
         case "photonics.enableHandheldLight" -> this.isHandheldLightEnabled = photonics$parseBoolean(value);
         case "photonics.enableLightBinning" -> this.isLightBinningEnabled = photonics$parseBoolean(value);
         case "photonics.voxelizeLava" -> this.voxelizeLava = photonics$parseBoolean(value);
         case "photonics.lightTreeInitialSamples", "photonics.restirInitialSamples" -> photonics$parseUnsignedInt(key, value, e -> this.lightTreeInitialSamples = e);
         case "photonics.lightTreeSpatialReuseSamples", "photonics.restirSpatialReuseSamples" -> photonics$parseUnsignedInt(key, value, e -> this.lightTreeSpatialReuseSamples = e);
         case "photonics.lightTreeSpatialReuseRadius", "photonics.restirSpatialReuseRadius" -> photonics$parseFloat(key, value, e -> this.lightTreeSpatialReuseRadius = e);
         case "photonics.lightTreeAccumulationFrames", "photonics.restirAccumulationFrames" -> photonics$parseUnsignedInt(key, value, e -> this.lightTreeAccumulationFrames = e);
         case "photonics.lightTreeSoftShadows", "photonics.restirSoftShadows" -> this.lightTreeSoftShadows = photonics$parseBoolean(value);
         case "photonics.lightTreeDenoiserPasses", "photonics.restirDenoiserPasses" -> photonics$parseNonNegativeInt(key, value, e -> this.denoiserPasses = e);
         case "photonics.nrdAtrousPasses" -> photonics$parseUnsignedInt(key, value, e -> this.nrdAtrousPasses = e);
      }
   }

   @Override
   public OptionalBoolean isPhotonicsEnabled() {
      return this.isPhotonicsEnabled;
   }

   @Override
   public float getRenderScale() {
      return this.renderScale;
   }

   @Override
   public int getMaxLights() {
      return this.maxLights;
   }

   @Override
   public int getMaxSamples() {
      return this.maxSamples;
   }

   @Override
   public float getMinTracedLightLuma() {
      return this.minTracedLightLuma;
   }

   @Override
   public AlphaMode getAlphaMode() {
      return this.alphaMode;
   }

   @Override
   public OptionalBoolean isGiEnabled() {
      return this.isGiEnabled;
   }

   @Override
   public OptionalBoolean isBlockLightEnabled() {
      return this.isBlockLightEnabled;
   }

   @Override
   public OptionalBoolean isHandheldLightEnabled() {
      return this.isHandheldLightEnabled;
   }

   @Override
   public OptionalBoolean isLightBinningEnabled() {
      return this.isLightBinningEnabled;
   }

   @Override
   public OptionalBoolean voxelizeLava() {
      return this.voxelizeLava;
   }


   @Override
   public int getLightTreeInitialSamples() {
      return this.lightTreeInitialSamples;
   }

   @Override
   public int getLightTreeSpatialReuseSamples() {
      return this.lightTreeSpatialReuseSamples;
   }

   @Override
   public float getLightTreeSpatialReuseRadius() {
      return this.lightTreeSpatialReuseRadius;
   }

   @Override
   public int getLightTreeAccumulationFrames() {
      return this.lightTreeAccumulationFrames;
   }

   @Override
   public OptionalBoolean useLightTreeSoftShadows() {
      return this.lightTreeSoftShadows;
   }

   @Override
   public int getLightTreeDenoiserPasses() {
      return this.denoiserPasses;
   }

   @Override
   public int getNrdAtrousPasses() {
      return this.nrdAtrousPasses;
   }

   @Unique
   private static void photonics$applyShaderOptionOverrides(Properties props, ShaderPackOptions shaderPackOptions) {
      if (shaderPackOptions == null) {
         return;
      }

      String lightTreeSoftShadows = photonics$resolveOptionValue(shaderPackOptions, "PHOTONICS_LIGHTTREE_SOFT_SHADOWS");
      if (lightTreeSoftShadows == null) {
         lightTreeSoftShadows = photonics$resolveOptionValue(shaderPackOptions, "PHOTONICS_RESTIR_SOFT_SHADOWS");
      }
      if (lightTreeSoftShadows != null) {
         props.setProperty("photonics.lightTreeSoftShadows", lightTreeSoftShadows);
         props.setProperty("photonics.restirSoftShadows", lightTreeSoftShadows);
      }

      for (String key : new HashSet<>(props.stringPropertyNames())) {
         String value = props.getProperty(key);
         String resolvedValue = photonics$resolveOptionAlias(value, shaderPackOptions);
         if (resolvedValue != null) {
            props.setProperty(key, resolvedValue);
         }
      }
   }

   @Unique
   private static String photonics$resolveOptionAlias(String value, ShaderPackOptions shaderPackOptions) {
      if (value == null || !value.startsWith("PHOTONICS_")) {
         return null;
      }

      return photonics$resolveOptionValue(shaderPackOptions, value);
   }

   @Unique
   private static String photonics$resolveOptionValue(ShaderPackOptions shaderPackOptions, String optionName) {
      if (shaderPackOptions == null || optionName == null) {
         return null;
      }

      if (shaderPackOptions.getOptionSet().getBooleanOptions().containsKey(optionName)) {
         return Boolean.toString(shaderPackOptions.getOptionValues().getBooleanValueOrDefault(optionName));
      }

      if (shaderPackOptions.getOptionSet().getStringOptions().containsKey(optionName)) {
         return shaderPackOptions.getOptionValues().getStringValueOrDefault(optionName);
      }

      return null;
   }


   @Unique
   private static void photonics$applySystemPropertyOverrides(Properties props) {
      for (String key : System.getProperties().stringPropertyNames()) {
         if (key.startsWith("photonics.") && !key.startsWith("photonics.automation.")) {
            String value = System.getProperty(key);
            if (value != null) {
               props.setProperty(key, value);
            }
         }
      }
   }

   @Unique
   private static OptionalBoolean photonics$parseBoolean(String value) {
      return switch (value.toLowerCase()) {
         case "true" -> OptionalBoolean.TRUE;
         case "false" -> OptionalBoolean.FALSE;
         default -> OptionalBoolean.DEFAULT;
      };
   }

   @Unique
   private static void photonics$parseUnsignedInt(String key, String value, Consumer<Integer> handler) {
      try {
         int result = Integer.parseInt(value);
         if (result <= 0) {
            throw new NumberFormatException("Was negative");
         }
         handler.accept(result);
      } catch (NumberFormatException e) {
         Iris.logger.warn("Unexpected value for unsigned integer key " + key + " in shaders.properties: got " + value + ", but expected an unsigned integer");
      }
   }

   @Unique
   private static void photonics$parseNonNegativeInt(String key, String value, Consumer<Integer> handler) {
      try {
         int result = Integer.parseInt(value);
         if (result < 0) {
            throw new NumberFormatException("Was negative");
         }
         handler.accept(result);
      } catch (NumberFormatException e) {
         Iris.logger.warn("Unexpected value for unsigned integer key " + key + " in shaders.properties: got " + value + ", but expected a non-negative integer");
      }
   }

   @Unique
   private static void photonics$parseFloat(String key, String value, Consumer<Float> handler) {
      try {
         handler.accept(Float.parseFloat(value));
      } catch (NumberFormatException e) {
         Iris.logger.warn("Unexpected value for float key " + key + " in shaders.properties: got " + value + ", but expected a float");
      }
   }

   @Unique
   private static void photonics$parseAlphaMode(String key, String value, Consumer<AlphaMode> handler) {
      try {
         handler.accept(AlphaMode.valueOf(value.toUpperCase()));
      } catch (IllegalArgumentException e) {
         Iris.logger.warn("Unexpected value for alpha mode key " + key + " in shaders.properties: got " + value + ", but expected alpha mode");
      }
   }

}