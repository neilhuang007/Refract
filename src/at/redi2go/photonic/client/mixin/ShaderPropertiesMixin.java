package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.api.AlphaMode;
import at.redi2go.photonic.client.api.LightingMode;
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
   private LightingMode lightingMode = DEFAULT_LIGHTING_MODE;
   @Unique
   private int restirInitialSamples = DEFAULT_RESTIR_INITIAL_SAMPLES;
   @Unique
   private int restirSpatialReuseSamples = DEFAULT_RESTIR_SPATIAL_REUSE_SAMPLES;
   @Unique
   private float restirSpatialReuseRadius = DEFAULT_RESTIR_SPATIAL_REUSE_RADIUS;
   @Unique
   private int restirAccumulationFrames = DEFAULT_RESTIR_ACCUMULATION_FRAMES;
   @Unique
   private OptionalBoolean restirSoftShadows = OptionalBoolean.DEFAULT;
   @Unique
   private int denoiserPasses = DEFAULT_RESTIR_DENOISER_PASSES;

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
         case "photonics.alphaMode" -> photonics$parseAlphaMode(key, value, e -> this.alphaMode = e);
         case "photonics.enableGi" -> this.isGiEnabled = photonics$parseBoolean(value);
         case "photonics.enableBlockLight" -> this.isBlockLightEnabled = photonics$parseBoolean(value);
         case "photonics.enableHandheldLight" -> this.isHandheldLightEnabled = photonics$parseBoolean(value);
         case "photonics.enableLightBinning" -> this.isLightBinningEnabled = photonics$parseBoolean(value);
         case "photonics.voxelizeLava" -> this.voxelizeLava = photonics$parseBoolean(value);
         case "photonics.lightingMode" -> photonics$parseLightingMode(key, value, e -> this.lightingMode = e);
         case "photonics.restirInitialSamples" -> photonics$parseUnsignedInt(key, value, e -> this.restirInitialSamples = e);
         case "photonics.restirSpatialReuseSamples" -> photonics$parseUnsignedInt(key, value, e -> this.restirSpatialReuseSamples = e);
         case "photonics.restirSpatialReuseRadius" -> photonics$parseFloat(key, value, e -> this.restirSpatialReuseRadius = e);
         case "photonics.restirAccumulationFrames" -> photonics$parseUnsignedInt(key, value, e -> this.restirAccumulationFrames = e);
         case "photonics.restirSoftShadows" -> this.restirSoftShadows = photonics$parseBoolean(value);
         case "photonics.restirDenoiserPasses" -> photonics$parseNonNegativeInt(key, value, e -> this.denoiserPasses = e);
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
   public LightingMode getLightingMode() {
      return this.lightingMode;
   }

   @Override
   public int getRestirInitialSamples() {
      return this.restirInitialSamples;
   }

   @Override
   public int getRestirSpatialReuseSamples() {
      return this.restirSpatialReuseSamples;
   }

   @Override
   public float getRestirSpatialReuseRadius() {
      return this.restirSpatialReuseRadius;
   }

   @Override
   public int getRestirAccumulationFrames() {
      return this.restirAccumulationFrames;
   }

   @Override
   public OptionalBoolean useRestirSoftShadows() {
      return this.restirSoftShadows;
   }

   @Override
   public int getRestirDenoiserPasses() {
      return this.denoiserPasses;
   }

   @Unique
   private static void photonics$applyShaderOptionOverrides(Properties props, ShaderPackOptions shaderPackOptions) {
      if (shaderPackOptions == null) {
         return;
      }

      String lightingMode = photonics$resolveLightingMode(shaderPackOptions);
      if (lightingMode != null) {
         props.setProperty("photonics.lightingMode", lightingMode);
      }

      String restirSoftShadows = photonics$resolveOptionValue(shaderPackOptions, "PHOTONICS_RESTIR_SOFT_SHADOWS");
      if (restirSoftShadows != null) {
         props.setProperty("photonics.restirSoftShadows", restirSoftShadows);
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
   private static String photonics$resolveLightingMode(ShaderPackOptions shaderPackOptions) {
      String value = photonics$resolveOptionValue(shaderPackOptions, "PHOTONICS_LIGHTING_MODE");
      if (value == null) {
         return null;
      }

      return switch (value) {
         case "0" -> LightingMode.OFF.name();
         case "1" -> LightingMode.BASIC.name();
         case "2" -> LightingMode.RESTIR.name();
         case "3" -> LightingMode.OCTRAY.name();
         default -> value;
      };
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

   @Unique
   private static void photonics$parseLightingMode(String key, String value, Consumer<LightingMode> handler) {
      try {
         handler.accept(LightingMode.valueOf(value.toUpperCase()));
      } catch (IllegalArgumentException e) {
         Iris.logger.warn("Unexpected value for lighting mode key " + key + " in shaders.properties: got " + value + ", but expected lighting mode");
      }
   }
}
