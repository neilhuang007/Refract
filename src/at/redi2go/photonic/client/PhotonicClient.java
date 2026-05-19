package at.redi2go.photonic.client;

import at.redi2go.photonic.client.config.PhotonicsConfig;
import at.redi2go.photonic.client.config.PhotonicsConfigWatchThread;
import net.fabricmc.api.ClientModInitializer;

public class PhotonicClient implements ClientModInitializer {
   public void onInitializeClient() {
      PhotonicsStorage.applySystemPropertyOverrides();
      PhotonicsConfig.reloadConfig();
      PhotonicsConfigWatchThread.INSTANCE.start();
      if (Photonic.automationEnabled()) {
         ShaderAutomation.initialize();
      }
   }
}
