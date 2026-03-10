package at.redi2go.photonic.client.mixin;

import at.redi2go.photonic.client.Raytracer;
import at.redi2go.photonic.client.api.AlphaMode;
import at.redi2go.photonic.client.api.PhotonicsProperties;
import java.io.IOException;
import java.io.StringReader;
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
   private OptionalBoolean useDeferredPass = OptionalBoolean.DEFAULT;
   @Unique
   private float renderScale = 1.0F;
   @Unique
   private int maxLights = 1000;
   @Unique
   private int maxSamples = 20;
   @Unique
   private AlphaMode alphaMode = PhotonicsProperties.DEFAULT_ALPHA_MODE;
   @Unique
   private OptionalBoolean isGiEnabled = OptionalBoolean.DEFAULT;
   @Unique
   private OptionalBoolean isBlockLightEnabled = OptionalBoolean.DEFAULT;
   @Unique
   private OptionalBoolean isHandheldLightEnabled = OptionalBoolean.DEFAULT;
   @Unique
   private OptionalBoolean voxelizeLava = OptionalBoolean.DEFAULT;

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
      // Merge raw SHADERPACK_PROPERTIES for photonics keys that JCPP may have stripped
      // from #ifdef blocks (e.g., #ifdef PHOTONICS_LIGHTING which is a GLSL-level define,
      // not an environment define available during shaders.properties preprocessing).
      if (Raytracer.SHADERPACK_PROPERTIES != null) {
         for (String key : Raytracer.SHADERPACK_PROPERTIES.stringPropertyNames()) {
            if (key.startsWith("photonics.") && !props.containsKey(key)) {
               props.setProperty(key, Raytracer.SHADERPACK_PROPERTIES.getProperty(key));
            }
         }
      }
      for (String key : props.stringPropertyNames()) {
         String value = props.getProperty(key);
         photonics$handleDirective(key, value);
      }
   }

   @Unique
   private void photonics$handleDirective(String key, String value) {
      switch (key) {
         case "photonics.enabled" -> this.isPhotonicsEnabled = photonics$parseBoolean(value);
         case "photonics.useDeferredPass" -> this.useDeferredPass = photonics$parseBoolean(value);
         case "photonics.renderScale" -> photonics$parseFloat(key, value, e -> this.renderScale = e);
         case "photonics.maxLights" -> photonics$parseUnsignedInt(key, value, e -> this.maxLights = e);
         case "photonics.maxSamples" -> photonics$parseUnsignedInt(key, value, e -> this.maxSamples = e);
         case "photonics.alphaMode" -> photonics$parseAlphaMode(key, value, e -> this.alphaMode = e);
         case "photonics.enableGi" -> this.isGiEnabled = photonics$parseBoolean(value);
         case "photonics.enableBlockLight" -> this.isBlockLightEnabled = photonics$parseBoolean(value);
         case "photonics.enableHandheldLight" -> this.isHandheldLightEnabled = photonics$parseBoolean(value);
         case "photonics.voxelizeLava" -> this.voxelizeLava = photonics$parseBoolean(value);
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
   public OptionalBoolean useDeferredPass() {
      return this.useDeferredPass;
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
   public OptionalBoolean voxelizeLava() {
      return this.voxelizeLava;
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
