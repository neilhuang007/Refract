package at.redi2go.photonic.client;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Objects;
import net.minecraft.text.Text;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.font.TextRenderer;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.gui.widget.ClickableWidget;
import net.minecraft.client.gui.widget.TextFieldWidget;
import net.minecraft.client.gui.Element;
import net.minecraft.client.gui.widget.ButtonWidget;
import net.minecraft.client.gui.widget.ElementListWidget;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.screen.ScreenTexts;
import net.minecraft.client.gui.Selectable;
import net.minecraft.client.gui.widget.TextWidget;
import net.minecraft.client.gui.widget.Positioner;
import net.minecraft.client.gui.widget.ThreePartsLayoutWidget;
import net.minecraft.client.gui.widget.DirectionalLayoutWidget;
import net.minecraft.client.gui.widget.ElementListWidget.Entry;
import org.jetbrains.annotations.NotNull;

public class ToggleableListScreen extends Screen {
   private final Screen parent;
   private final ToggleableListScreen.Model model;
   private final ThreePartsLayoutWidget layout = new ThreePartsLayoutWidget(this, 61, 33);
   private ToggleableListScreen.ToggleableList list;

   public ToggleableListScreen(Screen parent, String headline, ToggleableListScreen.Model model) {
      super(Text.of(headline));
      this.parent = parent;
      this.model = model;
   }

   protected void init() {
      super.init();
      TextFieldWidget searchBox = new TextFieldWidget(this.textRenderer, 200, 20, Text.of("Search"));
      searchBox.setChangedListener(searchText -> {
         this.model.setFilter(searchText);
         this.list.init();
      });
      DirectionalLayoutWidget searchLinearLayout = (DirectionalLayoutWidget)this.layout.addHeader(DirectionalLayoutWidget.vertical().spacing(8));
      searchLinearLayout.add(new TextWidget(this.getTitle(), this.textRenderer), Positioner::alignHorizontalCenter);
      searchLinearLayout.add(searchBox, Positioner::alignHorizontalCenter);
      this.list = new ToggleableListScreen.ToggleableList(MinecraftClient.getInstance(), this);
      this.list.init();
      this.layout.addBody(this.list);
      this.layout.addFooter(ButtonWidget.builder(ScreenTexts.DONE, button -> this.close()).width(200).build());
      this.layout.forEachChild(x$0 -> {
         ClickableWidget var10000 = (ClickableWidget)this.addDrawableChild(x$0);
      });
      this.layout.refreshPositions();
   }

   protected void initTabNavigation() {
      this.layout.refreshPositions();
      this.list.position(this.width, this.layout);
   }

   public void render(@NotNull DrawContext drawContext, int mouseX, int mouseY, float delta) {
      super.renderBackground(drawContext, mouseX, mouseY, delta);
      super.render(drawContext, mouseX, mouseY, delta);
   }

   public void close() {
      if (this.client != null) {
         this.client.setScreen(this.parent);
      }
   }

   public abstract static class Entry extends ElementListWidget.Entry<ToggleableListScreen.Entry> {
      abstract void refreshEntry();
   }

   public static class Model {
      private final List<ToggleableListScreen.ModelEntry> content;
      private final List<ToggleableListScreen.ModelEntry> filteredContent = new ArrayList<>();

      public Model(List<ToggleableListScreen.ModelEntry> content) {
         this.content = content;
         this.setFilter("");
      }

      public void setFilter(String filter) {
         List<String> filterTokens = Arrays.stream(filter.split(" ")).map(String::toLowerCase).toList();
         this.filteredContent.clear();
         this.content.stream().filter(entry -> {
            String displayValue = entry.getDisplayValue().toLowerCase();

            for (String filterToken : filterTokens) {
               if (!displayValue.contains(filterToken)) {
                  return false;
               }
            }

            return true;
         }).forEach(this.filteredContent::add);
      }

      public List<ToggleableListScreen.ModelEntry> getFilteredContent() {
         return this.filteredContent;
      }
   }

   public abstract static class ModelEntry {
      public abstract String getDisplayValue();

      public abstract boolean isEnabled();

      public abstract void setEnabled(boolean var1);
   }

   public class ToggleableList extends ElementListWidget<ToggleableListScreen.Entry> {
      public ToggleableList(MinecraftClient minecraft, ToggleableListScreen toggleableListScreen) {
         super(minecraft, toggleableListScreen.width, toggleableListScreen.layout.getContentHeight(), toggleableListScreen.layout.getHeaderHeight(), 20);
      }

      public void init() {
         this.clearEntries();

         for (ToggleableListScreen.ModelEntry entry : ToggleableListScreen.this.model.getFilteredContent()) {
            this.addEntry(new ToggleableListScreen.ToggleableList.ListEntry(entry));
         }
      }

      public class ListEntry extends ToggleableListScreen.Entry {
         private final ToggleableListScreen.ModelEntry model;
         private final ButtonWidget toggleButton;

         public ListEntry(ToggleableListScreen.ModelEntry model) {
            this.model = model;
            this.toggleButton = ButtonWidget.builder(Text.of(model.isEnabled() ? "ON" : "OFF"), button -> {
               model.setEnabled(!model.isEnabled());
               this.refreshEntry();
            }).dimensions(0, 0, 75, 20).build();
         }

         @Override
         void refreshEntry() {
            this.toggleButton.setMessage(Text.of(this.model.isEnabled() ? "ON" : "OFF"));
         }

         @NotNull
         public List<? extends Selectable> selectableChildren() {
            return List.of();
         }

         public void render(@NotNull DrawContext guiGraphics, int i, int j, int k, int l, int m, int n, int o, boolean bl, float f) {
            int p = ToggleableList.this.getScrollbarX() - 10;
            int q = j - 2;
            int r = p - 5 - this.toggleButton.getWidth();
            this.toggleButton.setPosition(r, q);
            this.toggleButton.render(guiGraphics, n, o, f);
            TextRenderer var10001 = ToggleableList.this.client.textRenderer;
            Text var10002 = Text.of(this.model.getDisplayValue());
            int var10004 = j + m / 2;
            Objects.requireNonNull(ToggleableList.this.client.textRenderer);
            guiGraphics.drawTextWithShadow(var10001, var10002, k, var10004 - 4, -1);
         }

         @NotNull
         public List<? extends Element> children() {
            return List.of(this.toggleButton);
         }
      }
   }
}
