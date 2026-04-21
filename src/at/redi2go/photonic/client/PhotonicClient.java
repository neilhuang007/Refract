package at.redi2go.photonic.client;

import at.redi2go.photonic.client.config.PhotonicsConfig;
import at.redi2go.photonic.client.config.PhotonicsConfigWatchThread;
import at.redi2go.photonic.client.rendering.world.MinecraftBlockMesher;
import at.redi2go.photonics.core.rendering.world.bakery.BlockMesher;
import net.fabricmc.api.ClientModInitializer;

public class PhotonicClient implements ClientModInitializer {
   public void onInitializeClient() {
      BlockMesher.REGISTRY.addDefault(new MinecraftBlockMesher());
      PhotonicsStorage.applySystemPropertyOverrides();
      PhotonicsConfig.reloadConfig();
      PhotonicsConfigWatchThread.INSTANCE.start();
      ShaderAutomation.initialize();
   }
}
