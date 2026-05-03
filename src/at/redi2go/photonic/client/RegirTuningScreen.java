package at.redi2go.photonic.client;

import java.util.List;
import java.util.Locale;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.gui.tooltip.Tooltip;
import net.minecraft.client.gui.widget.ButtonWidget;
import net.minecraft.client.gui.widget.SliderWidget;
import net.minecraft.screen.ScreenTexts;
import net.minecraft.text.Text;
import org.jetbrains.annotations.NotNull;

public class RegirTuningScreen extends Screen {
   private static final float DEFAULT_LOOKUP_JITTER = 1.0f;
   private static final float DEFAULT_BUILD_JITTER = 1.0f;
   private static final float DEFAULT_BUILD_SAMPLES = 8.0f;
   private static final float DEFAULT_LOCAL_LIGHT_SAMPLES = 8.0f;
   private static final float DEFAULT_LIGHTS_PER_CELL = 64.0f;
   private static final boolean DEFAULT_COLLAPSE_NORMAL_BUCKETS = true;
   private static final boolean DEFAULT_FIXED_FRAME_SEED = true;
   private static final float DEFAULT_FRAME_SEED = 0.0f;

   private final Screen parent;
   private List<RegirSlider> sliders = List.of();
   private ButtonWidget collapseNormalBucketsButton;
   private ButtonWidget fixedFrameSeedButton;

   public RegirTuningScreen(Screen parent) {
      super(Text.of("ReGIR Tuning"));
      this.parent = parent;
   }

   @Override
   protected void init() {
      super.init();

      int centerX = this.width / 2;
      int sliderWidth = 320;
      int x = centerX - sliderWidth / 2;
      int y = 52;

      RegirSlider lookupJitter = new RegirSlider(
         PhotonicsStorage.REGIR_LOOKUP_JITTER,
         0.0f,
         1.5f,
         0.05f,
         "Lookup Jitter",
         " cells",
         "Jitter applied when the final ReGIR path resolves a surface to a hash cell.\nLower values reduce near-light cell switching."
      );
      RegirSlider buildJitter = new RegirSlider(
         PhotonicsStorage.REGIR_BUILD_JITTER,
         0.0f,
         2.0f,
         0.05f,
         "Build Jitter",
         " cells",
         "Jitter expansion used by the ReGIR build target radius.\nHigher values make cells more conservative but less local."
      );
      RegirSlider buildSamples = new RegirSlider(
         PhotonicsStorage.REGIR_BUILD_SAMPLES,
         1.0f,
         64.0f,
         1.0f,
         "Build Samples",
         "",
         "Number of proposal samples used to populate each ReGIR light slot.\nHigher values reduce slot variance and cost more GPU time."
      );
      RegirSlider localSamples = new RegirSlider(
         PhotonicsStorage.REGIR_LOCAL_LIGHT_SAMPLES,
         1.0f,
         32.0f,
         1.0f,
         "Local Candidates",
         "",
         "Number of local-light candidates sampled from the chosen ReGIR cell per initial path.\nHigher values reduce flicker and cost more shading work."
      );
      RegirSlider lightsPerCell = new RegirSlider(
         PhotonicsStorage.REGIR_LIGHTS_PER_CELL,
         16.0f,
         128.0f,
         16.0f,
         "Slots / Cell",
         "",
         "Number of ReGIR slots allocated per hash cell.\nApplies after the light registry is rebuilt; restart or reload the world."
      );
      RegirSlider frameSeed = new RegirSlider(
         PhotonicsStorage.REGIR_FRAME_SEED,
         0.0f,
         1024.0f,
         1.0f,
         "Frame Seed",
         "",
         "Seed used by the ReGIR presample/build RNG when Fixed Frame Seed is enabled.\nMatches -Dphotonics.regirFrameSeed for diagnosing temporal proposal churn."
      );

      this.sliders = List.of(lookupJitter, buildJitter, buildSamples, localSamples, lightsPerCell, frameSeed);
      for (RegirSlider slider : this.sliders) {
         slider.setPosition(x, y);
         this.addDrawableChild(slider);
         y += 28;
      }

      this.collapseNormalBucketsButton = ButtonWidget.builder(this.getCollapseNormalBucketsText(), button -> this.toggleCollapseNormalBuckets(button))
         .position(x, y)
         .size(sliderWidth, 20)
         .tooltip(Tooltip.of(Text.of("Builds one volumetric ReGIR normal bucket and lets lookup fall back to bucket 0.\nDisable for diagnosing directional or shaped-light bucket artifacts.")))
         .build();
      this.addDrawableChild(this.collapseNormalBucketsButton);
      y += 28;

      this.fixedFrameSeedButton = ButtonWidget.builder(this.getFixedFrameSeedText(), button -> this.toggleFixedFrameSeed(button))
         .position(x, y)
         .size(sliderWidth, 20)
         .tooltip(Tooltip.of(Text.of("Freezes ReGIR presample/build frame RNG to the Frame Seed value.\nUse this to test whether near-light flashing comes from temporal proposal churn.")))
         .build();
      this.addDrawableChild(this.fixedFrameSeedButton);
      y += 28;

      this.addDrawableChild(
         ButtonWidget.builder(Text.of("Reset ReGIR Defaults"), button -> this.resetDefaults())
            .position(centerX - 160, y + 8)
            .size(150, 20)
            .tooltip(Tooltip.of(Text.of("Restores the practical defaults: jitter 1.0, build samples 8, local candidates 8, slots/cell 64, fixed seed on.")))
            .build()
      );
      this.addDrawableChild(
         ButtonWidget.builder(ScreenTexts.DONE, button -> this.close())
            .position(centerX + 10, y + 8)
            .size(150, 20)
            .build()
      );
   }

   private void resetDefaults() {
      this.sliders.get(0).setParameterValue(DEFAULT_LOOKUP_JITTER);
      this.sliders.get(1).setParameterValue(DEFAULT_BUILD_JITTER);
      this.sliders.get(2).setParameterValue(DEFAULT_BUILD_SAMPLES);
      this.sliders.get(3).setParameterValue(DEFAULT_LOCAL_LIGHT_SAMPLES);
      this.sliders.get(4).setParameterValue(DEFAULT_LIGHTS_PER_CELL);
      this.sliders.get(5).setParameterValue(DEFAULT_FRAME_SEED);
      PhotonicsStorage.REGIR_COLLAPSE_NORMAL_BUCKETS.value = DEFAULT_COLLAPSE_NORMAL_BUCKETS;
      PhotonicsStorage.REGIR_COLLAPSE_NORMAL_BUCKETS.modified();
      PhotonicsStorage.REGIR_FIXED_FRAME_SEED.value = DEFAULT_FIXED_FRAME_SEED;
      PhotonicsStorage.REGIR_FIXED_FRAME_SEED.modified();
      if (this.collapseNormalBucketsButton != null) {
         this.collapseNormalBucketsButton.setMessage(this.getCollapseNormalBucketsText());
      }
      if (this.fixedFrameSeedButton != null) {
         this.fixedFrameSeedButton.setMessage(this.getFixedFrameSeedText());
      }
   }

   private Text getCollapseNormalBucketsText() {
      return Text.of("Collapse Normal Buckets: " + (PhotonicsStorage.REGIR_COLLAPSE_NORMAL_BUCKETS.value ? "On" : "Off"));
   }

   private void toggleCollapseNormalBuckets(ButtonWidget button) {
      PhotonicsStorage.REGIR_COLLAPSE_NORMAL_BUCKETS.value = !PhotonicsStorage.REGIR_COLLAPSE_NORMAL_BUCKETS.value;
      PhotonicsStorage.REGIR_COLLAPSE_NORMAL_BUCKETS.modified();
      button.setMessage(this.getCollapseNormalBucketsText());
   }

   private Text getFixedFrameSeedText() {
      return Text.of("Fixed Frame Seed: " + (PhotonicsStorage.REGIR_FIXED_FRAME_SEED.value ? "On" : "Off"));
   }

   private void toggleFixedFrameSeed(ButtonWidget button) {
      PhotonicsStorage.REGIR_FIXED_FRAME_SEED.value = !PhotonicsStorage.REGIR_FIXED_FRAME_SEED.value;
      PhotonicsStorage.REGIR_FIXED_FRAME_SEED.modified();
      button.setMessage(this.getFixedFrameSeedText());
   }

   @Override
   public void close() {
      this.client.setScreen(this.parent);
   }

   @Override
   public void render(@NotNull DrawContext drawContext, int mouseX, int mouseY, float delta) {
      super.renderBackground(drawContext, mouseX, mouseY, delta);
      drawContext.drawCenteredTextWithShadow(this.textRenderer, this.title, this.width / 2, 20, 0xFFFFFF);
      super.render(drawContext, mouseX, mouseY, delta);
   }

   private static final class RegirSlider extends SliderWidget {
      private final PhotonicsStorage.Parameter<Float> param;
      private final float min;
      private final float max;
      private final float step;
      private final String label;
      private final String suffix;

      private RegirSlider(
         PhotonicsStorage.Parameter<Float> param,
         float min,
         float max,
         float step,
         String label,
         String suffix,
         String tooltip
      ) {
         super(0, 0, 320, 20, Text.of(""), normalize(param.value, min, max));
         this.param = param;
         this.min = min;
         this.max = max;
         this.step = step;
         this.label = label;
         this.suffix = suffix;
         this.setTooltip(Tooltip.of(Text.of(tooltip)));
         this.updateMessage();
      }

      private void setParameterValue(float value) {
         this.value = normalize(value, this.min, this.max);
         this.param.value = this.getValue();
         this.param.modified();
         this.updateMessage();
      }

      @Override
      protected void updateMessage() {
         float value = this.getValue();
         String valueText = this.step >= 1.0f
            ? Integer.toString(Math.round(value))
            : String.format(Locale.ROOT, "%.2f", value);
         this.setMessage(Text.of(this.label + ": " + valueText + this.suffix));
      }

      @Override
      protected void applyValue() {
         this.param.value = this.getValue();
         this.param.modified();
         this.updateMessage();
      }

      private float getValue() {
         float raw = this.min + (float)this.value * (this.max - this.min);
         float stepped = this.step > 0.0f ? Math.round(raw / this.step) * this.step : raw;
         return Math.max(this.min, Math.min(this.max, stepped));
      }

      private static double normalize(float value, float min, float max) {
         return (Math.max(min, Math.min(max, value)) - min) / (max - min);
      }
   }
}
