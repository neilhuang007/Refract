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
   private static final String[] DIRECT_STAGE_VIEW_ORDER = new String[]{
      "stage_direct",
      "direct_noisy",
      "direct_responsive",
      "direct_slow",
      "direct_fast",
      "direct_historyfix",
      "direct_clamped_fast",
      "direct_anti_firefly",
      "direct_denoised",
      "direct_atrous",
      "final"
   };
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
      PhotonicsStorage.Parameter<String> directStageView = PhotonicsStorage.DEBUG_DIRECT_STAGE_VIEW;
      buttons.add(new ModSettingsScreen.PButton("Direct View: " + formatDirectStageView(directStageView.value), w -> {
         directStageView.value = getNextDirectStageView(directStageView.value);
         directStageView.modified();
         w.setMessage(Text.of("Direct View: " + formatDirectStageView(directStageView.value)));
      }, "Cycles the direct-lighting inspection source:\nRT Raw, Noisy, Responsive, Slow, Fast,\nHist Fix, Clamp Fast, Firefly, Denoised, Atrous, Final.", () -> true));
      PhotonicsStorage.Parameter<Boolean> directTemporalReuse = PhotonicsStorage.DEBUG_ENABLE_DIRECT_TEMPORAL_REUSE;
      buttons.add(new ModSettingsScreen.PButton("Direct Temporal Reuse: " + (directTemporalReuse.value ? "On" : "Off"), w -> {
         directTemporalReuse.value = !directTemporalReuse.value;
         directTemporalReuse.modified();
         w.setMessage(Text.of("Direct Temporal Reuse: " + (directTemporalReuse.value ? "On" : "Off")));
      }, "Enables or bypasses ReSTIR DI temporal reuse.\nTurn this off to isolate overlap and ownership flashing from proposal-only direct lighting.", () -> true));
      PhotonicsStorage.Parameter<Boolean> directSpatialReuse = PhotonicsStorage.DEBUG_ENABLE_DIRECT_SPATIAL_REUSE;
      buttons.add(new ModSettingsScreen.PButton("Direct Spatial Reuse: " + (directSpatialReuse.value ? "On" : "Off"), w -> {
         directSpatialReuse.value = !directSpatialReuse.value;
         directSpatialReuse.modified();
         w.setMessage(Text.of("Direct Spatial Reuse: " + (directSpatialReuse.value ? "On" : "Off")));
      }, "Enables or bypasses ReSTIR DI spatial reuse.\nTurn this off to isolate proposal-only direct-lighting behavior.", () -> true));
      PhotonicsStorage.Parameter<Boolean> directFinalVisibility = PhotonicsStorage.DEBUG_ENABLE_DIRECT_FINAL_VISIBILITY;
      buttons.add(new ModSettingsScreen.PButton("Direct Final Visibility: " + (directFinalVisibility.value ? "On" : "Off"), w -> {
         directFinalVisibility.value = !directFinalVisibility.value;
         directFinalVisibility.modified();
         w.setMessage(Text.of("Direct Final Visibility: " + (directFinalVisibility.value ? "On" : "Off")));
      }, "Toggles the final shadow ray in direct shading.\nUse this to separate reuse artifacts from final-visibility shadow artifacts.", () -> true));
      PhotonicsStorage.Parameter<String> checkerboardMode = PhotonicsStorage.RESTIR_CHECKERBOARD_MODE;
      checkerboardMode.value = PhotonicsStorage.normalizeCheckerboardMode(checkerboardMode.value);
      buttons.add(new ModSettingsScreen.PButton("ReSTIR Checkerboard: " + formatCheckerboardMode(checkerboardMode.value), w -> {
         checkerboardMode.value = getNextCheckerboardMode(checkerboardMode.value);
         checkerboardMode.modified();
         w.setMessage(Text.of("ReSTIR Checkerboard: " + formatCheckerboardMode(checkerboardMode.value)));
         this.reloadShaders();
      }, "Cycles the RTXDI checkerboard field used by the direct-lighting path:\nOff, Black, White.", () -> true));
      PhotonicsStorage.Parameter<String> localLightSamplingMode = PhotonicsStorage.RESTIR_LOCAL_LIGHT_SAMPLING_MODE;
      buttons.add(new ModSettingsScreen.PButton("Local Light Sampling: " + formatRestirLocalLightSamplingMode(localLightSamplingMode.value), w -> {
         localLightSamplingMode.value = getNextRestirLocalLightSamplingMode(localLightSamplingMode.value);
         localLightSamplingMode.modified();
         w.setMessage(Text.of("Local Light Sampling: " + formatRestirLocalLightSamplingMode(localLightSamplingMode.value)));
         this.reloadShaders();
      }, "Cycles the RTXDI/ReSTIR DI local-light proposal mode:\nUniform, Power RIS, and ReGIR RIS.", () -> true));
      PhotonicsStorage.Parameter<String> spatialMisMode = PhotonicsStorage.RESTIR_SPATIAL_MIS_MODE;
      spatialMisMode.value = PhotonicsStorage.normalizeRestirSpatialMisMode(spatialMisMode.value);
      buttons.add(new ModSettingsScreen.PButton("Spatial MIS: " + formatRestirSpatialMisMode(spatialMisMode.value), w -> {
         spatialMisMode.value = getNextRestirSpatialMisMode(spatialMisMode.value);
         spatialMisMode.modified();
         w.setMessage(Text.of("Spatial MIS: " + formatRestirSpatialMisMode(spatialMisMode.value)));
      }, "Chooses the RTXDI spatial reuse bias correction mode:\nBasic MIS or Pairwise MIS. Pairwise MIS is the default and matches the current RTXDI reference intent for spatial reuse.", () -> true));
      PhotonicsStorage.Parameter<Float> debugViewMode = PhotonicsStorage.DEBUG_VIEW_MODE;
      buttons.add(new ModSettingsScreen.PButton("Debug View: " + formatDebugViewMode(debugViewMode.value), w -> {
         debugViewMode.value = getNextDebugViewMode(debugViewMode.value);
         debugViewMode.modified();
         w.setMessage(Text.of("Debug View: " + formatDebugViewMode(debugViewMode.value)));
      }, "Cycles debug visualization overlays:\nOff, Distance Heatmap, ReGIR Grid Hit/Miss, ReGIR Cell Index,\nReGIR Coverage, Initial Sampling Reason, Final Visibility Class, Selected Light Distance,\nReservoir Inv PDF, Reservoir Target PDF, Selected Solid Angle PDF,\nIncident Radiance, BRDF Response.", () -> true));
      OilifySlider oilifySizeSlider = new OilifySlider(PhotonicsStorage.OILIFY_SIZE, 3.0f, 15.0f, "OILIFY_SIZE", true);
      OilifySlider oilifySharpnessSlider = new OilifySlider(PhotonicsStorage.OILIFY_SHARPNESS, 0.0f, 1.0f, "Sharpness", false);
      OilifySlider oilifyScaleSlider = new OilifySlider(PhotonicsStorage.OILIFY_SCALE, 1.0f, 4.0f, "Scale", false);
      OilifySlider oilifyTuningSlider = new OilifySlider(PhotonicsStorage.OILIFY_TUNING, 0.0f, 4.0f, "Anistropy Tuning", false);
      OilifySlider oilifyIterationsSlider = new OilifySlider(PhotonicsStorage.OILIFY_ITERATIONS, 1.0f, 8.0f, "OILIFY_ITERATIONS", true);
      OilifySlider oilifyDepthScalingSlider = new OilifySlider(PhotonicsStorage.OILIFY_DEPTH_SCALING, 0.0f, 2.0f, "Depth Scaling", false);
      OilifySlider oilifyStrokeStrengthSlider = new OilifySlider(PhotonicsStorage.OILIFY_STROKE_STRENGTH, 0.0f, 1.0f, "Stroke Strength", false);
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

   private static String getNextRestirLocalLightSamplingMode(String samplingMode) {
      return switch (PhotonicsStorage.normalizeRestirLocalLightSamplingMode(samplingMode)) {
         case "uniform" -> "power_ris";
         case "power_ris" -> "regir_ris";
         default -> "uniform";
      };
   }

   private static String formatRestirLocalLightSamplingMode(String samplingMode) {
      return switch (PhotonicsStorage.normalizeRestirLocalLightSamplingMode(samplingMode)) {
         case "uniform" -> "Uniform";
         case "power_ris" -> "Power RIS";
         default -> "ReGIR RIS";
      };
   }

   private static String getNextRestirSpatialMisMode(String misMode) {
      return switch (PhotonicsStorage.normalizeRestirSpatialMisMode(misMode)) {
         case "basic" -> "pairwise";
         default -> "basic";
      };
   }

   private static String formatRestirSpatialMisMode(String misMode) {
      return switch (PhotonicsStorage.normalizeRestirSpatialMisMode(misMode)) {
         case "basic" -> "Basic MIS";
         default -> "Pairwise MIS";
      };
   }

   private static String formatDebugViewMode(float mode) {
      int m = Math.round(mode);
      return switch (m) {
         case 1 -> "Distance";
         case 2 -> "ReGIR Grid";
         case 3 -> "ReGIR Cell";
         case 4 -> "ReGIR Coverage";
         case 5 -> "Initial Reason";
         case 6 -> "Visibility Class";
         case 7 -> "Light Distance";
         case 8 -> "Inv PDF";
         case 9 -> "Target PDF";
         case 10 -> "Solid Angle PDF";
         case 11 -> "Incident Radiance";
         case 12 -> "BRDF Response";
         default -> "Off";
      };
   }

   private static float getNextDebugViewMode(float current) {
      int m = Math.round(current);
      return (float) ((m + 1) % 13);
   }

   private static String getNextDirectStageView(String current) {
      String normalized = PhotonicsStorage.normalizeDirectStageView(current);

      for (int i = 0; i < DIRECT_STAGE_VIEW_ORDER.length; i++) {
         if (DIRECT_STAGE_VIEW_ORDER[i].equals(normalized)) {
            return DIRECT_STAGE_VIEW_ORDER[(i + 1) % DIRECT_STAGE_VIEW_ORDER.length];
         }
      }

      return DIRECT_STAGE_VIEW_ORDER[0];
   }

   private static String formatDirectStageView(String stageView) {
      return switch (PhotonicsStorage.normalizeDirectStageView(stageView)) {
         case "stage_direct" -> "RT Raw";
         case "direct_noisy" -> "Noisy";
         case "direct_responsive" -> "Responsive";
         case "direct_slow" -> "Slow";
         case "direct_fast" -> "Fast";
         case "direct_historyfix" -> "Hist Fix";
         case "direct_clamped_fast" -> "Clamp Fast";
         case "direct_anti_firefly" -> "Firefly";
         case "direct_denoised" -> "Denoised";
         case "direct_atrous" -> "Atrous";
         default -> "Final";
      };
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

