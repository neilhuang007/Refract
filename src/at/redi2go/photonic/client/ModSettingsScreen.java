package at.redi2go.photonic.client;

import at.redi2go.photonic.client.config.PhotonicsConfig;
import at.redi2go.photonic.client.rendering.world.LightBlock;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.function.BooleanSupplier;
import java.util.function.Supplier;
import com.mojang.blaze3d.systems.RenderSystem;
import net.irisshaders.iris.Iris;
import net.minecraft.block.Blocks;
import net.minecraft.block.Block;
import net.minecraft.text.Text;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.gui.widget.ClickableWidget;
import net.minecraft.util.Unit;
import net.minecraft.resource.ResourceReload;
import net.minecraft.client.gui.widget.ButtonWidget;
import net.minecraft.client.gui.screen.SplashOverlay;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.screen.ScreenTexts;
import net.minecraft.client.gui.widget.TextWidget;
import net.minecraft.client.gui.widget.GridWidget;
import net.minecraft.client.gui.widget.Positioner;
import net.minecraft.client.gui.tooltip.Tooltip;
import net.minecraft.registry.Registries;
import net.minecraft.client.gui.widget.ThreePartsLayoutWidget;
import net.minecraft.client.gui.widget.DirectionalLayoutWidget;
import net.minecraft.client.gui.widget.ButtonWidget.PressAction;
import net.minecraft.client.gui.widget.GridWidget.Adder;
import net.minecraft.client.gui.widget.SliderWidget;
import org.jetbrains.annotations.NotNull;

public class ModSettingsScreen extends Screen {
   private static final ToggleableListScreen.Model BLOCKS_3D_MODEL = new ToggleableListScreen.Model(Registries.BLOCK.stream().filter(block -> {
      Set<Block> blacklistedBlocks = Set.of(Blocks.AIR, Blocks.WATER, Blocks.LAVA);
      return !blacklistedBlocks.contains(block);
   }).sorted(Comparator.comparing(block -> block.getName().getString())).map(block -> (ToggleableListScreen.ModelEntry)new ModSettingsScreen.BlockModel3DEntry(block)).toList());
   private final Screen parent;
   private final ToggleableListScreen.Model tracedBlocksModel;
   private SchematicExporter schematicExporter = null;
   private final ThreePartsLayoutWidget layout = new ThreePartsLayoutWidget(this, 61, 33);

   protected ModSettingsScreen(Screen parent) {
      super(Text.of("Photonic Client Settings"));
      this.parent = parent;
      this.tracedBlocksModel = new ToggleableListScreen.Model(
         PhotonicsConfig.getLightList()
            .keySet()
            .stream()
            .sorted(Comparator.comparing(block -> block.getName().getString()))
            .map(block -> (ToggleableListScreen.ModelEntry)new ModSettingsScreen.TracedLightBlockEntry(block))
            .toList()
      );
      PhotonicsConfig.prepareModify();
   }

   protected void init() {
      super.init();
      List<ModSettingsScreen.PButton> buttons = new ArrayList<>();
      buttons.add(
         new ModSettingsScreen.PButton(
            "Generate schematics.zip",
            w -> this.exportSchematics(),
            "Exports all blockstates to the root\nMinecraft folder (schematics.zip). Only works in-game!",
            () -> MinecraftClient.getInstance().world != null
         )
      );
      buttons.add(new ModSettingsScreen.PButton("MultiThreading: " + (PhotonicsConfig.isMultiThreadingEnabled() ? "On" : "Off"), w -> {
         PhotonicsConfig.setMultiThreadingEnabled(!PhotonicsConfig.isMultiThreadingEnabled());
         w.setMessage(Text.of("MultiThreading: " + (PhotonicsConfig.isMultiThreadingEnabled() ? "On" : "Off")));
      }, "Turns MultiThreading on or off; MultiThreading is considerably faster, but can cause bugs.", () -> true));
      PhotonicsStorage.Parameter<Boolean> profilerEnabled = PhotonicsStorage.PROFILER_ENABLED;
      buttons.add(new ModSettingsScreen.PButton("Performance Profiler: " + (profilerEnabled.value ? "On" : "Off"), w -> {
         profilerEnabled.value = !profilerEnabled.value;
         profilerEnabled.modified();
         w.setMessage(Text.of("Performance Profiler: " + (profilerEnabled.value ? "On" : "Off")));
      }, "Logs per-frame timing data (world update, render dispatch,\nshader passes) to latest.log for performance diagnostics.", () -> true));
      PhotonicsStorage.Parameter<Boolean> disableDenoiser = PhotonicsStorage.DEBUG_DISABLE_DENOISER;
      buttons.add(new ModSettingsScreen.PButton("Disable Denoiser: " + (disableDenoiser.value ? "On" : "Off"), w -> {
         disableDenoiser.value = !disableDenoiser.value;
         disableDenoiser.modified();
         w.setMessage(Text.of("Disable Denoiser: " + (disableDenoiser.value ? "On" : "Off")));
         this.reloadShaders();
      }, "Bypasses the temporal/spatial denoiser so you can inspect raw\ndirect and indirect lighting stability.", () -> true));
      PhotonicsStorage.Parameter<String> checkerboardMode = PhotonicsStorage.RESTIR_CHECKERBOARD_MODE;
      buttons.add(new ModSettingsScreen.PButton("ReSTIR Checkerboard: " + formatCheckerboardMode(checkerboardMode.value), w -> {
         checkerboardMode.value = getNextCheckerboardMode(checkerboardMode.value);
         checkerboardMode.modified();
         w.setMessage(Text.of("ReSTIR Checkerboard: " + formatCheckerboardMode(checkerboardMode.value)));
         this.reloadShaders();
      }, "Cycles ReSTIR checkerboard sampling between Off, Black, and White\nso ph_restir_active_checkerboard_field matches RTXDI runtime modes.", () -> true));
      PhotonicsStorage.Parameter<String> qualityProfile = PhotonicsStorage.QUALITY_PROFILE;
      buttons.add(new ModSettingsScreen.PButton("Quality: " + formatQualityProfile(qualityProfile.value), w -> {
         qualityProfile.value = getNextQualityProfile(qualityProfile.value);
         qualityProfile.modified();
         applyQualityProfile(qualityProfile.value);
         w.setMessage(Text.of("Quality: " + formatQualityProfile(qualityProfile.value)));
         this.reloadShaders();
      }, "Quality preset: Potato (fastest), Low, Medium, High, Ultra (best).\nSets render scale, sample counts, denoiser passes, and bias correction.\nCustom = use shaderpack defaults.", () -> true));
      OilifySlider oilifySizeSlider = new OilifySlider(PhotonicsStorage.OILIFY_SIZE, 3.0f, 15.0f, "OILIFY_SIZE", true);
      OilifySlider oilifySharpnessSlider = new OilifySlider(PhotonicsStorage.OILIFY_SHARPNESS, 0.0f, 1.0f, "Sharpness", false);
      OilifySlider oilifyScaleSlider = new OilifySlider(PhotonicsStorage.OILIFY_SCALE, 1.0f, 4.0f, "Scale", false);
      OilifySlider oilifyTuningSlider = new OilifySlider(PhotonicsStorage.OILIFY_TUNING, 0.0f, 4.0f, "Anistropy Tuning", false);
      OilifySlider oilifyIterationsSlider = new OilifySlider(PhotonicsStorage.OILIFY_ITERATIONS, 1.0f, 8.0f, "OILIFY_ITERATIONS", true);
      OilifySlider oilifyDepthScalingSlider = new OilifySlider(PhotonicsStorage.OILIFY_DEPTH_SCALING, 0.0f, 2.0f, "Depth Scaling", false);
      OilifySlider oilifyStrokeStrengthSlider = new OilifySlider(PhotonicsStorage.OILIFY_STROKE_STRENGTH, 0.0f, 1.0f, "Stroke Strength", false);
      OilifySlider renderScaleSlider = new OilifySlider(PhotonicsStorage.RENDER_SCALE, -1.0f, 1.0f, "Render Scale", false);
      OilifySlider atrousPassesSlider = new OilifySlider(PhotonicsStorage.NRD_ATROUS_PASSES, -1.0f, 7.0f, "Atrous Passes", true);
      OilifySlider initialSamplesSlider = new OilifySlider(PhotonicsStorage.RESTIR_INITIAL_SAMPLES, -1.0f, 32.0f, "Initial Samples", true);
      OilifySlider spatialSamplesSlider = new OilifySlider(PhotonicsStorage.RESTIR_SPATIAL_SAMPLES, -1.0f, 8.0f, "DI Spatial Samples", true);
      OilifySlider giSpatialSamplesSlider = new OilifySlider(PhotonicsStorage.RESTIR_GI_SPATIAL_SAMPLES, -1.0f, 4.0f, "GI Spatial Samples", true);
      OilifySlider spatialRadiusSlider = new OilifySlider(PhotonicsStorage.RESTIR_SPATIAL_RADIUS, -1.0f, 64.0f, "Spatial Radius", true);
      PhotonicsStorage.Parameter<Float> biasMode = PhotonicsStorage.RESTIR_SPATIAL_BIAS_MODE;
      buttons.add(new ModSettingsScreen.PButton("Bias Correction: " + formatBiasMode(biasMode.value), w -> {
         biasMode.value = getNextBiasMode(biasMode.value);
         biasMode.modified();
         w.setMessage(Text.of("Bias Correction: " + formatBiasMode(biasMode.value)));
      }, "Bias correction mode for spatial resampling.\nAuto = use shaderpack default, Off = fastest,\nBasic = MIS correction, Ray Traced = visibility rays (slowest).", () -> true));
      List<OilifySlider> oilifySliders = List.of(oilifySizeSlider, oilifySharpnessSlider, oilifyScaleSlider, oilifyTuningSlider, oilifyIterationsSlider, oilifyDepthScalingSlider, oilifyStrokeStrengthSlider);
      oilifySliders.forEach(s -> s.active = PhotonicsStorage.OILIFY_ENABLED.value);
      PhotonicsStorage.Parameter<Boolean> oilify = PhotonicsStorage.OILIFY_ENABLED;
      buttons.add(new ModSettingsScreen.PButton("Oilify: " + (oilify.value ? "On" : "Off"), w -> {
         oilify.value = !oilify.value;
         oilify.modified();
         oilifySliders.forEach(s -> s.active = oilify.value);
         w.setMessage(Text.of("Oilify: " + (oilify.value ? "On" : "Off")));
      }, "Applies an oil painting effect to the world using\nan anisotropic Kuwahara filter.", () -> true));
      ToggleableListScreen volumetricRenderedBlocks = new ToggleableListScreen(this, "3D Blocks", BLOCKS_3D_MODEL);
      buttons.add(
         new ModSettingsScreen.PButton(
            "3D Blocks",
            w -> this.client.setScreen(volumetricRenderedBlocks),
            "Configures, whether a specific block should be rendered as a 3D block",
            () -> true
         )
      );
      ToggleableListScreen tracedBlocks = new ToggleableListScreen(this, "Raytraced Block Lights", this.tracedBlocksModel);
      buttons.add(
         new ModSettingsScreen.PButton(
            "Raytraced Lights",
            w -> this.client.setScreen(tracedBlocks),
            "Configures, whether a specific block should emit ray-traced light",
            () -> true
         )
      );
      DirectionalLayoutWidget linearLayout = (DirectionalLayoutWidget)this.layout.addHeader(DirectionalLayoutWidget.vertical().spacing(8));
      linearLayout.add(new TextWidget(Text.of("Photonics Mod settings"), this.textRenderer), Positioner::alignHorizontalCenter);
      GridWidget gridLayout = new GridWidget();
      gridLayout.getMainPositioner().marginX(4).marginBottom(4).alignHorizontalCenter();
      Adder rowHelper = gridLayout.createAdder(2);
      int midX = this.width / 2;
      int i = 0;

      for (ModSettingsScreen.PButton button : buttons) {
         int x = i % 2 * 220 + midX - 210;
         int y = (i / 2 + 1) * 30;
         button.widget = ButtonWidget.builder(Text.of(button.text), button.pressAction)
            .position(x, y)
            .size(200, 20)
            .tooltip(Tooltip.of(Text.of(button.toolTip)))
            .build();
         button.widget.active = button.active.getAsBoolean();
         rowHelper.add(button.widget);
         i++;
      }

      rowHelper.add(oilifySizeSlider, 2);
      rowHelper.add(oilifySharpnessSlider, 2);
      rowHelper.add(oilifyScaleSlider, 2);
      rowHelper.add(oilifyTuningSlider, 2);
      rowHelper.add(oilifyIterationsSlider, 2);
      rowHelper.add(oilifyDepthScalingSlider, 2);
      rowHelper.add(oilifyStrokeStrengthSlider, 2);
      rowHelper.add(renderScaleSlider, 2);
      rowHelper.add(atrousPassesSlider, 2);
      rowHelper.add(initialSamplesSlider, 2);
      rowHelper.add(spatialSamplesSlider, 2);
      rowHelper.add(giSpatialSamplesSlider, 2);
      rowHelper.add(spatialRadiusSlider, 2);

      this.layout.addBody(gridLayout);
      this.layout.addFooter(ButtonWidget.builder(ScreenTexts.DONE, buttonx -> this.close()).width(200).build());
      this.layout.forEachChild(x$0 -> {
         ClickableWidget var10000 = (ClickableWidget)this.addDrawableChild(x$0);
      });
      this.layout.refreshPositions();
   }

   public void render(@NotNull DrawContext drawContext, int mouseX, int mouseY, float delta) {
      super.renderBackground(drawContext, mouseX, mouseY, delta);
      super.render(drawContext, mouseX, mouseY, delta);
   }

   public void exportSchematics() {
      if (this.schematicExporter == null) {
         try {
            this.schematicExporter = new SchematicExporter(new File("."));
            MinecraftClient.getInstance().setOverlay(buildLoadingOverlay(() -> {
               if (this.schematicExporter == null) {
                  return 1.0F;
               } else {
                  for (int i = 0; i < 100; i++) {
                     if (!this.schematicExporter.exportOne()) {
                        this.schematicExporter = null;
                        return 1.0F;
                     }
                  }

                  return this.schematicExporter.getProgress();
               }
            }));
         } catch (FileNotFoundException var2) {
            var2.printStackTrace();
         }
      }
   }

   public void close() {
      this.client.setScreen(this.parent);

      try {
         PhotonicsConfig.onChanged();
         PhotonicsConfig.save();
      } catch (Exception e) {
         Photonic.error("error saving config", e);
      }
   }


   private void reloadShaders() {
      RenderSystem.recordRenderCall(() -> {
         try {
            Iris.reload();
         } catch (IOException e) {
            Photonic.error("error reloading shaders after lighting pipeline update", e);
         }
      });
   }

   private static void applyQualityProfile(String profile) {
      switch (profile.toLowerCase()) {
         case "potato" -> {
            PhotonicsStorage.RENDER_SCALE.value = 0.50F;
            PhotonicsStorage.NRD_ATROUS_PASSES.value = 2.0F;
            PhotonicsStorage.RESTIR_INITIAL_SAMPLES.value = 4.0F;
            PhotonicsStorage.RESTIR_SPATIAL_SAMPLES.value = 1.0F;
            PhotonicsStorage.RESTIR_GI_SPATIAL_SAMPLES.value = 1.0F;
            PhotonicsStorage.RESTIR_SPATIAL_RADIUS.value = 8.0F;
            PhotonicsStorage.RESTIR_SPATIAL_BIAS_MODE.value = -1.0F;
         }
         case "low" -> {
            PhotonicsStorage.RENDER_SCALE.value = 0.65F;
            PhotonicsStorage.NRD_ATROUS_PASSES.value = 3.0F;
            PhotonicsStorage.RESTIR_INITIAL_SAMPLES.value = 8.0F;
            PhotonicsStorage.RESTIR_SPATIAL_SAMPLES.value = 2.0F;
            PhotonicsStorage.RESTIR_GI_SPATIAL_SAMPLES.value = 1.0F;
            PhotonicsStorage.RESTIR_SPATIAL_RADIUS.value = 10.0F;
            PhotonicsStorage.RESTIR_SPATIAL_BIAS_MODE.value = 2.0F;
         }
         case "medium" -> {
            PhotonicsStorage.RENDER_SCALE.value = 0.75F;
            PhotonicsStorage.NRD_ATROUS_PASSES.value = 3.0F;
            PhotonicsStorage.RESTIR_INITIAL_SAMPLES.value = 16.0F;
            PhotonicsStorage.RESTIR_SPATIAL_SAMPLES.value = 3.0F;
            PhotonicsStorage.RESTIR_GI_SPATIAL_SAMPLES.value = 2.0F;
            PhotonicsStorage.RESTIR_SPATIAL_RADIUS.value = 10.0F;
            PhotonicsStorage.RESTIR_SPATIAL_BIAS_MODE.value = 2.0F;
         }
         case "high" -> {
            PhotonicsStorage.RENDER_SCALE.value = 1.0F;
            PhotonicsStorage.NRD_ATROUS_PASSES.value = 5.0F;
            PhotonicsStorage.RESTIR_INITIAL_SAMPLES.value = 32.0F;
            PhotonicsStorage.RESTIR_SPATIAL_SAMPLES.value = 5.0F;
            PhotonicsStorage.RESTIR_GI_SPATIAL_SAMPLES.value = 2.0F;
            PhotonicsStorage.RESTIR_SPATIAL_RADIUS.value = 10.0F;
            PhotonicsStorage.RESTIR_SPATIAL_BIAS_MODE.value = 2.0F;
         }
         case "ultra" -> {
            PhotonicsStorage.RENDER_SCALE.value = 1.0F;
            PhotonicsStorage.NRD_ATROUS_PASSES.value = 5.0F;
            PhotonicsStorage.RESTIR_INITIAL_SAMPLES.value = 32.0F;
            PhotonicsStorage.RESTIR_SPATIAL_SAMPLES.value = 5.0F;
            PhotonicsStorage.RESTIR_GI_SPATIAL_SAMPLES.value = 2.0F;
            PhotonicsStorage.RESTIR_SPATIAL_RADIUS.value = 10.0F;
            PhotonicsStorage.RESTIR_SPATIAL_BIAS_MODE.value = 2.0F;
         }
         default -> {
            // "custom" — leave individual settings as-is, set all to auto
            PhotonicsStorage.RENDER_SCALE.value = -1.0F;
            PhotonicsStorage.NRD_ATROUS_PASSES.value = -1.0F;
            PhotonicsStorage.RESTIR_INITIAL_SAMPLES.value = -1.0F;
            PhotonicsStorage.RESTIR_SPATIAL_SAMPLES.value = -1.0F;
            PhotonicsStorage.RESTIR_GI_SPATIAL_SAMPLES.value = -1.0F;
            PhotonicsStorage.RESTIR_SPATIAL_RADIUS.value = -1.0F;
            PhotonicsStorage.RESTIR_SPATIAL_BIAS_MODE.value = -1.0F;
         }
      }
      PhotonicsStorage.RENDER_SCALE.modified();
      PhotonicsStorage.NRD_ATROUS_PASSES.modified();
      PhotonicsStorage.RESTIR_INITIAL_SAMPLES.modified();
      PhotonicsStorage.RESTIR_SPATIAL_SAMPLES.modified();
      PhotonicsStorage.RESTIR_GI_SPATIAL_SAMPLES.modified();
      PhotonicsStorage.RESTIR_SPATIAL_RADIUS.modified();
      PhotonicsStorage.RESTIR_SPATIAL_BIAS_MODE.modified();
   }

   private static String getNextQualityProfile(String current) {
      return switch (current.toLowerCase()) {
         case "custom" -> "potato";
         case "potato" -> "low";
         case "low" -> "medium";
         case "medium" -> "high";
         case "high" -> "ultra";
         case "ultra" -> "custom";
         default -> "custom";
      };
   }

   private static String formatQualityProfile(String profile) {
      return switch (profile.toLowerCase()) {
         case "potato" -> "Potato";
         case "low" -> "Low";
         case "medium" -> "Medium";
         case "high" -> "High";
         case "ultra" -> "Ultra";
         default -> "Custom";
      };
   }

   private static String formatBiasMode(float value) {
      if (value < 0) return "Auto";
      if (value < 0.5f) return "Off";
      if (value < 2.0f) return "Basic";
      return "Ray Traced";
   }

   private static float getNextBiasMode(float value) {
      if (value < 0) return 0.0F;
      if (value < 0.5f) return 1.0F;
      if (value < 2.0f) return 3.0F;
      return -1.0F;
   }

   private static String getNextCheckerboardMode(String checkerboardMode) {
      if ("off".equalsIgnoreCase(checkerboardMode)) {
         return "black";
      }
      if ("black".equalsIgnoreCase(checkerboardMode)) {
         return "white";
      }
      return "off";
   }

   private static String formatCheckerboardMode(String checkerboardMode) {
      if ("black".equalsIgnoreCase(checkerboardMode)) {
         return "Black";
      }
      if ("white".equalsIgnoreCase(checkerboardMode)) {
         return "White";
      }
      return "Off";
   }

   private static SplashOverlay buildLoadingOverlay(Supplier<Float> progressSupplier) {
      return new SplashOverlay(MinecraftClient.getInstance(), new ResourceReload() {
         public CompletableFuture<Unit> whenComplete() {
            return null;
         }

         public float getProgress() {
            return progressSupplier.get();
         }

         public boolean isComplete() {
            return this.getProgress() == 1.0F;
         }
      }, o -> {}, false);
   }

   public static class BlockModel3DEntry extends ToggleableListScreen.ModelEntry {
      private final Block block;

      public BlockModel3DEntry(Block block) {
         this.block = block;
      }

      @Override
      public String getDisplayValue() {
         return this.block.getName().getString();
      }

      @Override
      public boolean isEnabled() {
         return PhotonicsConfig.isVoxelized(this.block);
      }

      @Override
      public void setEnabled(boolean enabled) {
         PhotonicsConfig.setVoxelized(this.block, enabled);
      }
   }

   private static class PButton {
      public ButtonWidget widget;
      public final String text;
      public final PressAction pressAction;
      public final String toolTip;
      public final BooleanSupplier active;

      public PButton(String text, PressAction pressAction, String toolTip, BooleanSupplier active) {
         this.text = text;
         this.pressAction = pressAction;
         this.toolTip = toolTip;
         this.active = active;
      }
   }

   private static class OilifySlider extends SliderWidget {
      private final PhotonicsStorage.Parameter<Float> param;
      private final float min;
      private final float max;
      private final String label;
      private final boolean intDisplay;

      OilifySlider(PhotonicsStorage.Parameter<Float> param, float min, float max, String label, boolean intDisplay) {
         super(0, 0, 200, 20, Text.of(""), normalize(param.value, min, max));
         this.param = param;
         this.min = min;
         this.max = max;
         this.label = label;
         this.intDisplay = intDisplay;
         this.updateMessage();
      }

      @Override
      protected void updateMessage() {
         float val = getValue();
         String valueStr;
         if (val < min + 0.01f && min < 0) {
            valueStr = "Auto";
         } else if (intDisplay) {
            valueStr = String.valueOf(Math.max(1, (int) val));
         } else {
            valueStr = String.format("%.2f", Math.max(0.25f, val));
         }
         this.setMessage(Text.of(label + ": " + valueStr));
      }

      @Override
      protected void applyValue() {
         this.param.value = getValue();
         this.param.modified();
         this.updateMessage();
      }

      private static double normalize(float val, float min, float max) {
         return (Math.max(min, Math.min(max, val)) - min) / (max - min);
      }

      private float getValue() {
         if (intDisplay) {
            return Math.max(min, Math.min(max, min + Math.round((float)(this.value * (max - min)))));
         }
         float raw = (float)(min + this.value * (max - min));
         return Math.max(min, Math.min(max, raw));
      }
   }

   public static class TracedLightBlockEntry extends ToggleableListScreen.ModelEntry {
      private final Block block;

      public TracedLightBlockEntry(Block block) {
         this.block = block;
      }

      @Override
      public String getDisplayValue() {
         return Registries.BLOCK.getId(this.block).getPath();
      }

      @Override
      public boolean isEnabled() {
         Boolean override = PhotonicsConfig.getTracedOverrides().get(this.block);
         return override != null ? override : PhotonicsConfig.getLightList().isTraced(this.block);
      }

      @Override
      public void setEnabled(boolean traced) {
         if (!Screen.hasShiftDown()) {
            PhotonicsConfig.getTracedOverrides().put(this.block, traced);
         } else {
            PhotonicsConfig.getTracedOverrides().remove(this.block);
         }
      }
   }
}

