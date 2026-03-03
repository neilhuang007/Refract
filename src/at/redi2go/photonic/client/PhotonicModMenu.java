package at.redi2go.photonic.client;

import com.terraformersmc.modmenu.api.ConfigScreenFactory;
import com.terraformersmc.modmenu.api.ModMenuApi;

public class PhotonicModMenu implements ModMenuApi {
   public ConfigScreenFactory<?> getModConfigScreenFactory() {
      return ModSettingsScreen::new;
   }
}
